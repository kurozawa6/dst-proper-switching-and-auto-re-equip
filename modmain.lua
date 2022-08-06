local saved_equip_items = {}
local saved_replaced_item_per_eslot = {}
local saved_removed_slot_per_eslot = {}
local saved_removed_slot_is_inbackpack_per_eslot = {}
local saved_get_item_per_eslot = {}
local saved_get_slot_per_eslot = {}
local saved_get_item_is_inbackpack_per_eslot = {}
local saved_inventory_items = {}
local saved_backpack_items = {}
local saved_backpack_replica_container = nil
local saved_handequip_is_projectile = false
local saved_slingshot_item = nil
local saved_slingshot_ammo = nil
local GetTime = GLOBAL.GetTime

local table = table --binding common/global utility stuff to locals for speed
local type = type
--local next = next -- next doesn't exist in the modmain environment
local print = print
local pairs = pairs
local ipairs = ipairs

local function print_data(data) --for debugging
    for k, v in pairs(data) do
        print(k, v)
    end
end

local function do_invntry_act_on_slot_or_item_w_dmmode_false(slot_or_item, inventory_or_backpack, ActionFn)
    local playercontroller = GLOBAL.ThePlayer.components.playercontroller
    local playercontroller_deploy_mode = playercontroller.deploy_mode --to study, slingshot auto reload in client fails without this function
    playercontroller.deploy_mode = false
    ActionFn(inventory_or_backpack, slot_or_item)
    playercontroller.deploy_mode = playercontroller_deploy_mode
end

local function try_put_active_item_to_slot(slot, inventory_or_backpack)
    local PutAllOfActiveItemInSlot = inventory_or_backpack.PutAllOfActiveItemInSlot
    do_invntry_act_on_slot_or_item_w_dmmode_false(slot, inventory_or_backpack, PutAllOfActiveItemInSlot)
end

local function try_swap_active_item_with_slot(slot, inventory_or_backpack)
    local SwapActiveItemWithSlot = inventory_or_backpack.SwapActiveItemWithSlot
    do_invntry_act_on_slot_or_item_w_dmmode_false(slot, inventory_or_backpack, SwapActiveItemWithSlot)
end

local function try_take_active_item_from_slot(slot, inventory_or_backpack)
    local TakeActiveItemFromAllOfSlot = inventory_or_backpack.TakeActiveItemFromAllOfSlot
    do_invntry_act_on_slot_or_item_w_dmmode_false(slot, inventory_or_backpack, TakeActiveItemFromAllOfSlot)
end

local function try_use_item_on_self(item, inventory)
    local ControllerUseItemOnSelfFromInvTile = inventory.ControllerUseItemOnSelfFromInvTile
    do_invntry_act_on_slot_or_item_w_dmmode_false(item, inventory, ControllerUseItemOnSelfFromInvTile)
end

local function cancel_task(task)
    if task ~= nil then
        task:Cancel()
        --print("A periodic task has been cancelled successfully.")
    --else
        --print("A nil periodic task has been tried to cancel")
    end
end

--[[
Gist of auto switch slot logic:
When equipping an item to replace another equipped, "equip" and "itemget" events are pushed client side.
To be able to move the item to the correct slot, we mainly need the item to move, its origin slot, and its destination slot.
The "itemget" event gives us the item to move and its origin slot. But "equip" only gives us the eslot and
the latest equipped item. We'll use the previous saved inventory state and some other tables with eslot as the indexing
to figure out, from "equip", what the destination slot is as well as to confirm that all conditions are met. The "itemremove"
could also give us the destination slot but it's not pushed in some circumstance, so we just use it mainly for updating the
previous saved inventory state.

Another problem is the receiving order of "equip" and "itemget" events upon equip switching is random. This could be solved
by inducing a frame delay for either event's function. So that we are certain the other event function would fire last, after
all the information needed are updated. But now I'm using a trickier one that doesn't have any induced frame delay - I sort of
mirrored the autoswitch checker function. So now the autoswitch works regardless of whether "equip" or "itemget" is pushed first.
I also made sure that it only works once per proper scenario. Should it unexpectedly fire in other unforeseen circumstances,
there are other checks to keep it from moving items around unnecessarily.

For when the client is also the server (hosting cave-less or DSA mod), the pushed events per equip switch are different.
The order isn't random and there are a couple more events. Overall, they are "unequip", "itemremove", "itemget", and then
"equip". The same client side logic will work provided I induce a frame delay for unequip (so "equip" function can fire first
before the needed shared tables are updated by the "unequip" fn). But instead I used a different logic, which you can see
around at the bottom of this file.
]]

local function auto_switch_slot(inst, obtained_item, slot_to_take_from, destination_slot, obtained_is_in_backpack, destination_is_in_backpack)
    local active_item = nil
    local inventory_destination = nil
    local item_on_dest_slot = nil
    local function refresh_common_variables() --refreshes active_item, inventory_destination, and item_on_dest_slot
        active_item = inst.replica.inventory:GetActiveItem()
        inventory_destination = nil
        if not destination_is_in_backpack then
            inventory_destination = inst.replica.inventory
        else
            local backpack = inst.replica.inventory:GetOverflowContainer()
            if backpack ~= nil then
                inventory_destination = backpack.inst.replica.container
            end
        end
        item_on_dest_slot = nil
        if inventory_destination ~= nil then
            item_on_dest_slot = inventory_destination:GetItemInSlot(destination_slot)
        end
    end
    local inventory_source = nil
    local item_on_slot_to_take = nil

    local current_task = nil
    local current_second_task = nil --needed as canceling a task right before changing its value apparently sets the task's later value back to the previous, yielding an infinite loop (as second task value is no longer referenced and cannot be cancelled)
    local function put_prompt()
        --print("initiating put_prompt() periodic task... [ASSRE]")
        refresh_common_variables()
        if inventory_destination == nil then
           cancel_task(current_second_task)
        elseif active_item == nil or --or item_on_dest_slot ~= nil then
               active_item ~= obtained_item or
               obtained_item == item_on_dest_slot or
               not obtained_item:IsValid() then
            cancel_task(current_second_task)
        elseif item_on_dest_slot == nil then
            try_put_active_item_to_slot(destination_slot, inventory_destination)
        elseif item_on_dest_slot ~= nil then --and obtained_item ~= item_on_dest_slot then
            try_swap_active_item_with_slot(destination_slot, inventory_destination)
        else
            cancel_task(current_second_task)
        end
    end
    local function take_prompt()
        --print("initiating take_prompt() periodic task... [ASSRE]")
        refresh_common_variables()
        if not obtained_is_in_backpack then
            inventory_source = inst.replica.inventory
        else
            local backpack = inst.replica.inventory:GetOverflowContainer()
            if backpack ~= nil then
                inventory_source = backpack.inst.replica.container
            end
        end
        if inventory_source ~= nil then
            item_on_slot_to_take = inventory_source:GetItemInSlot(slot_to_take_from)
        end
        if inventory_destination == nil then
            cancel_task(current_task)
        elseif inventory_source == nil then
            cancel_task(current_task)
        elseif active_item ~= nil and
               active_item == obtained_item and
               obtained_item ~= item_on_dest_slot and
               obtained_item:IsValid() then
            if item_on_dest_slot == nil then
                try_put_active_item_to_slot(destination_slot, inventory_destination)
            else
                try_swap_active_item_with_slot(destination_slot, inventory_destination)
            end
            cancel_task(current_task)
            current_second_task = inst:DoPeriodicTask(0, put_prompt)
        elseif not obtained_item:IsValid() or
                   obtained_item ~= item_on_slot_to_take or
                   obtained_item == item_on_dest_slot or --or item_on_dest_slot ~= nil then
                   item_on_slot_to_take == nil then
            cancel_task(current_task)
        elseif obtained_item == item_on_slot_to_take then
            try_take_active_item_from_slot(slot_to_take_from, inventory_source)
        else
            cancel_task(current_task)
        end
    end

    take_prompt()
    current_task = inst:DoPeriodicTask(0, take_prompt)
end

local function onitemget_auto_ss(inst, eslot, obtained_item, slot_to_take_from, obtained_is_in_backpack)
    local previous_equipped_item = saved_replaced_item_per_eslot[eslot]
    saved_replaced_item_per_eslot[eslot] = nil
    --print(obtained_item, previous_equipped_item)
    if not (previous_equipped_item == obtained_item and previous_equipped_item and obtained_item) then
        return
    end

    --print("initializing onitemget_auto_ss [ASSRE]")
    local destination_slot = saved_removed_slot_per_eslot[eslot]
    --print("Move", obtained_item, "from", slot_to_take_from, "to", destination_slot)
    local destination_is_in_backpack = saved_removed_slot_is_inbackpack_per_eslot[eslot]

    auto_switch_slot(inst, obtained_item, slot_to_take_from, destination_slot, obtained_is_in_backpack, destination_is_in_backpack)
end

local function update_inventory_on_get_fn_to_delay(inst, get_slot, get_item)
    local item_in_slot = inst.replica.inventory:GetItemInSlot(get_slot)
    if item_in_slot == get_item and get_slot ~= nil then
        saved_inventory_items[get_slot] = item_in_slot
        --print("saved_inventory_items[", get_slot, "]:", saved_inventory_items[get_slot])
    end
end

local function InventoryOnItemGet(inst, data)
    local item = data.item
    local get_slot = data.slot
    local equippable = item.replica.equippable
    local eslot = nil
    if equippable ~= nil then
        eslot = equippable:EquipSlot()
        saved_get_item_per_eslot[eslot] = item
        saved_get_slot_per_eslot[eslot] = get_slot
        saved_get_item_is_inbackpack_per_eslot[eslot] = false
    end
    if eslot ~= nil then
        onitemget_auto_ss(inst, eslot, item, get_slot, false)
    end
    inst:DoTaskInTime(0, update_inventory_on_get_fn_to_delay, get_slot, item)
end

local function update_backpack_on_get_fn_to_delay(_, get_slot, get_item)
    if saved_backpack_replica_container == nil then
        return
    end
    local item_in_slot = saved_backpack_replica_container:GetItemInSlot(get_slot)
    if item_in_slot == get_item and get_slot ~= nil then
        saved_backpack_items[get_slot] = get_item
        --print("saved_backpack_items[", get_slot, "]:", saved_backpack_items[get_slot])
    end
end

local function BackpackOnItemGet(inst, data)
    local item = data.item
    local get_slot = data.slot
    local equippable = item.replica.equippable
    local eslot = nil
    if equippable ~= nil then
        eslot = equippable:EquipSlot()
        saved_get_item_per_eslot[eslot] = item
        saved_get_slot_per_eslot[eslot] = get_slot
        saved_get_item_is_inbackpack_per_eslot[eslot] = true
    end
    if eslot ~= nil then
        onitemget_auto_ss(GLOBAL.ThePlayer, eslot, item, get_slot, true)
    end
    inst:DoTaskInTime(0, update_backpack_on_get_fn_to_delay, get_slot, item)
end

local function update_inventory_on_remove_fn_to_delay(inst, removed_slot)
    local item_in_slot = inst.replica.inventory:GetItemInSlot(removed_slot)
    if item_in_slot == nil and removed_slot ~= nil then
        saved_inventory_items[removed_slot] = nil
        --print("saved_inventory_items[", removed_slot, "]:", saved_inventory_items[removed_slot])
    end
end

local function InventoryOnItemLose(inst, data) -- Huge mistake on hindsight: "IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS!"
    local removed_slot = data.slot
    inst:DoTaskInTime(0, update_inventory_on_remove_fn_to_delay, removed_slot)
end

local function update_backpack_on_remove_fn_to_delay(_, removed_slot)
    if saved_backpack_replica_container == nil then
        return
    end
    local item_in_slot = saved_backpack_replica_container:GetItemInSlot(removed_slot)
    if item_in_slot == nil and removed_slot ~= nil then
        saved_backpack_items[removed_slot] = nil
        --print("saved_backpack_items[", removed_slot, "]:", saved_backpack_items[removed_slot])
    end
end

local function BackpackOnItemLose(inst, data)
    local removed_slot = data.slot
    inst:DoTaskInTime(0, update_backpack_on_remove_fn_to_delay, removed_slot)
end

local function BackpackListenForEvents(inst)
    inst:ListenForEvent("itemget", BackpackOnItemGet)
    inst:ListenForEvent("itemlose", BackpackOnItemLose)
end

local function BackpackRemoveEventCallbacks(inst)
    inst:RemoveEventCallback("itemget", BackpackOnItemGet)
    inst:RemoveEventCallback("itemlose", BackpackOnItemLose)
end

local function item_tables_to_check(inst)
    local inventory = inst.replica.inventory
    local tables_to_check = {}
    local active_item = inventory:GetActiveItem()
    if active_item ~= nil then
        table.insert(tables_to_check, {active_item})
    end
    local inventory_items_table = {}
    local inventory_numslots = inventory:GetNumSlots()
    for slot = 1, inventory_numslots do
        local item = inventory:GetItemInSlot(slot)
        inventory_items_table[slot] = item~=nil and item or {}
    end
    table.insert(tables_to_check, inventory_items_table)
    local open_containers = inventory:GetOpenContainers()
    if open_containers ~= nil then
        for container_object in pairs(open_containers) do
            local container_replica = container_object and container_object.replica.container
            if container_replica ~= nil then
                local container_items_table = {}
                local container_numslots = container_replica:GetNumSlots()
                for slot = 1, container_numslots do
                    local item = container_replica:GetItemInSlot(slot)
                    container_items_table[slot] = item~=nil and item or {}
                end
                table.insert(tables_to_check, container_items_table)
            end
        end
    end
    return tables_to_check
end

local function next_same_prefab_item_from_tables(tables_to_check, item_to_compare)
    for _, item_table in ipairs(tables_to_check) do
        for _, item in ipairs(item_table) do
            if item.prefab == item_to_compare.prefab then
                return item
            end
        end
    end
    return nil
end

local function get_entity_with_prefab_name_and_spawntime(name, time)
    for _, v in pairs(GLOBAL.Ents) do
        if v.prefab == name then
            if v.spawntime ~= nil then
                if time - v.spawntime < 0.07 then
                    return v
                end
            end
        end
    end
    return nil
end

local function slingshot_auto_reload(inst, ammo) -- can't loop this due to quick equip-unequip bug
    local inventory = GLOBAL.ThePlayer.replica.inventory
    local ammo_slot = inst.replica.container
    local tables_to_check = item_tables_to_check(GLOBAL.ThePlayer)
    local item_to_equip = next_same_prefab_item_from_tables(tables_to_check, ammo)

    if item_to_equip == nil or
       ammo_slot:GetItemInSlot(1) ~= nil then
        return
    elseif not item_to_equip:IsValid() then
        return
    end
    try_use_item_on_self(item_to_equip, inventory)
end

local function SlingshotOnItemGet(_, data)
    if data.item == nil then
        return
    end
    saved_slingshot_ammo = data.item
end

local function SlingshotOnItemLose(inst)
    local current_time = GetTime()
    local ammo = saved_slingshot_ammo
    saved_slingshot_ammo = nil

    if ammo == nil then
        return
    end
    local item_prefab = ammo.prefab
    local projectile_prefab = item_prefab.."_proj"
    local ammo_projectile = get_entity_with_prefab_name_and_spawntime(projectile_prefab, current_time)
    if ammo_projectile ~= nil then
        if not GLOBAL.TheWorld.ismastersim then
            slingshot_auto_reload(inst, ammo)
        else
            inst:DoTaskInTime(0, slingshot_auto_reload, ammo) -- wait 1 frame to prevent invisible ammo icon bug
        end
    end
end

local function SlingshotListenForEvents(inst)
    inst:ListenForEvent("itemget", SlingshotOnItemGet)
    inst:ListenForEvent("itemlose", SlingshotOnItemLose)
end

local function SlingshotRemoveEventCallbacks(inst)
    inst:RemoveEventCallback("itemget", SlingshotOnItemGet)
    inst:RemoveEventCallback("itemlose", SlingshotOnItemLose)
end

local function initialize_backpack(backpack_replica_container)
    local potentially_live_items_table = backpack_replica_container:GetItems()
    for slot, item in pairs(potentially_live_items_table) do
        saved_backpack_items[slot] = item
    end
    --print_data(saved_backpack_items)
end

local function onequip_auto_ss(inst, eslot, previous_equipped_item, destination_slot, destination_is_in_backpack)
    local obtained_item = saved_get_item_per_eslot[eslot]
    --print(obtained_item, previous_equipped_item)
    if not (previous_equipped_item == obtained_item and previous_equipped_item and obtained_item) then
        return
    end
    saved_replaced_item_per_eslot[eslot] = nil
    local slot_to_take_from = saved_get_slot_per_eslot[eslot]
    --print("Move", previous_equipped_item, "from", slot_to_take_from, "to", destination_slot)
    local obtained_is_in_backpack = saved_get_item_is_inbackpack_per_eslot[eslot]

    auto_switch_slot(inst, obtained_item, slot_to_take_from, destination_slot, obtained_is_in_backpack, destination_is_in_backpack)
end

local function OnEquip(inst, data)
    if not (type(data) == "table" and data.eslot and data.item) then
        return
    end
    local latest_equipped_item = data.item
    local eslot = data.eslot
    local previous_equipped_item = nil
    local removed_slot = nil
    local is_from_backpack = false
    if saved_equip_items[eslot] ~= nil then
        previous_equipped_item = saved_equip_items[eslot]
    end
    saved_equip_items[eslot] = latest_equipped_item
    local saved_backpack_eslot = nil
    if saved_backpack_replica_container ~= nil then
        local backpack_equippable = saved_backpack_replica_container.inst.replica.equippable
        saved_backpack_eslot = backpack_equippable and backpack_equippable:EquipSlot()
    end
    if eslot == GLOBAL.EQUIPSLOTS.HANDS then
        saved_handequip_is_projectile = latest_equipped_item:HasTag("projectile")
        if saved_slingshot_item ~= nil then
            SlingshotRemoveEventCallbacks(saved_slingshot_item)
            saved_slingshot_item = nil
        end
        if latest_equipped_item:HasTag("slingshot") then
            saved_slingshot_item = latest_equipped_item
            SlingshotListenForEvents(saved_slingshot_item)
        end
    elseif latest_equipped_item:HasTag("backpack") then
        local backpack = latest_equipped_item.replica.container --or inst.replica.inventory:GetOverflowContainer()
        if backpack ~= nil then
            if saved_backpack_replica_container ~= nil then
                BackpackRemoveEventCallbacks(saved_backpack_replica_container.inst)
            end
            saved_backpack_replica_container = backpack
            initialize_backpack(saved_backpack_replica_container)
            BackpackListenForEvents(saved_backpack_replica_container.inst)
        end
    elseif eslot == saved_backpack_eslot then
        if saved_backpack_replica_container ~= nil then
            saved_backpack_items = {}
            BackpackRemoveEventCallbacks(saved_backpack_replica_container.inst)
            saved_backpack_replica_container = nil
        end
    end

    for slot, item in pairs(saved_inventory_items) do
        if item == latest_equipped_item then -- if the latest equipped item is found on the previous saved inventory, then get its slot as destination slot
            removed_slot = slot
            break
        end
    end
    if removed_slot == nil then --and saved_backpack_items ~= nil then -- no need to check for saved_backpack_items being nil because it defaults to {}
        for slot, item in pairs(saved_backpack_items) do
            if item == latest_equipped_item then
                removed_slot = slot
                is_from_backpack = true
                break
            end
        end
    end

    if removed_slot == nil or previous_equipped_item == nil then
        saved_replaced_item_per_eslot[eslot] = nil
        saved_removed_slot_per_eslot[eslot] = nil
    else
        saved_replaced_item_per_eslot[eslot] = previous_equipped_item
        saved_removed_slot_per_eslot[eslot] = removed_slot
        saved_removed_slot_is_inbackpack_per_eslot[eslot] = is_from_backpack
        onequip_auto_ss(inst, eslot, previous_equipped_item, removed_slot, is_from_backpack)
    end
end

local function main_auto_equip(inst, unequipped_item, eslot, previous_is_projectile)
    local unequipped_is_invalid = not unequipped_item:IsValid()
    local unequipped_has_tag_noclick = unequipped_item:HasTag("NOCLICK")
    local autoequip_is_valid = false
    if not previous_is_projectile then
        if unequipped_is_invalid then --if non-projectile item is no longer valid (broken)
            autoequip_is_valid = true
        end
    else
        if unequipped_has_tag_noclick then --if projectile item is thrown (only happens when it's the last ammo)
            autoequip_is_valid = true
        end
    end

    if autoequip_is_valid == false then
        return
    end
    local inventory = inst.replica.inventory
    local current_task = nil
    local function autoequip_prompt()
        if inventory:GetEquippedItem(eslot) then
            cancel_task(current_task)
            return
        end
        local tables_to_check = item_tables_to_check(inst)
        local item_to_equip = next_same_prefab_item_from_tables(tables_to_check, unequipped_item)
        if item_to_equip == nil then
            cancel_task(current_task)
        elseif item_to_equip:IsValid() then
            try_use_item_on_self(item_to_equip, inventory)
        end
    end

    autoequip_prompt()
    current_task = inst:DoPeriodicTask(0, autoequip_prompt)
end

--[[ -- for when applying the "pure client" logic in cave-less/DSA mod is desired, followed by DoTaskInTime in OnUnequip (and commenting next line)
local function update_on_unequip_fn_to_delay(inst, eslot)
    local equip_in_eslot = inst.replica.inventory:GetEquippedItem(eslot)
    if equip_in_eslot == nil and eslot ~= nil then
        saved_equip_items[eslot] = nil
        --print("saved_inventory_items[", removed_slot, "]:", saved_inventory_items[removed_slot])
    end
end
]]
local function OnUnequip(inst, data)
    if type(data) ~= "table" then
        return
    end
    local eslot = data.eslot
    local item = saved_equip_items[eslot]
    --inst:DoTaskInTime(0, update_on_unequip_fn_to_delay)
    saved_equip_items[eslot] = nil

    if item == nil then
        return
    end
    if item:HasTag("backpack") then
        saved_backpack_items = {}
        if saved_backpack_replica_container ~= nil then
            BackpackRemoveEventCallbacks(saved_backpack_replica_container.inst)
            saved_backpack_replica_container = nil
        end
    end

    if eslot ~= GLOBAL.EQUIPSLOTS.HANDS then --to expound for compatibility with modded non-hand projectile equipment?
        return
    end
    local previous_is_projectile = saved_handequip_is_projectile -- needed as "projectile" tag is removed upon item removal i.e. being merged into another stack
    saved_handequip_is_projectile = false
    if not GLOBAL.TheWorld.ismastersim then
        main_auto_equip(inst, item, eslot, previous_is_projectile)
    else
        inst:DoTaskInTime(0, main_auto_equip, item, eslot, previous_is_projectile) -- delay one frame if mastersim as mastersim unequip event is pushed before broken/out of ammo
    end

    if item:HasTag("slingshot") then --and saved_slingshot_item ~= nil
        SlingshotRemoveEventCallbacks(item)
        saved_slingshot_item = nil
    end
end

local function initialize_inventory(inst)
    local inventory = inst.replica.inventory
    local potentially_live_items_table = inventory:GetItems()
    for slot, item in pairs(potentially_live_items_table) do
        saved_inventory_items[slot] = item
    end
    --print_data(saved_inventory_items)
end

local function initialize_equips(inst)
    local inventory = inst.replica.inventory
    local potentially_live_equips_table = inventory:GetEquips()
    for eslot, item in pairs(potentially_live_equips_table) do
        saved_equip_items[eslot] = item
    end
    local handequip = saved_equip_items[GLOBAL.EQUIPSLOTS.HANDS]
    if handequip ~= nil then
        saved_handequip_is_projectile = handequip:HasTag("projectile")
        if handequip:HasTag("slingshot") then
            saved_slingshot_item = handequip
            SlingshotRemoveEventCallbacks(handequip)
            SlingshotListenForEvents(handequip)
            saved_slingshot_ammo = saved_slingshot_item.replica.container:GetItemInSlot(1)
        end
    end
    --print_data(saved_equip_items)
end

local function ClientListenForEvents(inst)
    inst:ListenForEvent("itemget", InventoryOnItemGet)
    inst:ListenForEvent("itemlose", InventoryOnItemLose)
    inst:ListenForEvent("equip", OnEquip)
    inst:ListenForEvent("unequip", OnUnequip)
end

local function ClientRemoveEventCallbacks(inst)
    inst:RemoveEventCallback("itemget", InventoryOnItemGet)
    inst:RemoveEventCallback("itemlose", InventoryOnItemLose)
    inst:RemoveEventCallback("equip", OnEquip)
    inst:RemoveEventCallback("unequip", OnUnequip)
end

local function initialize_client(inst)
    initialize_inventory(inst)
    initialize_equips(inst)
    local backpack = inst.replica.inventory:GetOverflowContainer()
    if backpack ~= nil then
        saved_backpack_replica_container = backpack
        initialize_backpack(saved_backpack_replica_container)
        BackpackRemoveEventCallbacks(saved_backpack_replica_container.inst)
        BackpackListenForEvents(saved_backpack_replica_container.inst)
    end
    ClientListenForEvents(inst)
end

AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= GLOBAL.ThePlayer then
        return
    end
    local old_OnRemoveFromEntity = self.OnRemoveFromEntity
    if not self.ismastersim then
        self.inst:DoTaskInTime(0, initialize_client)
        self.OnRemoveFromEntity = function(self, ...)
            ClientRemoveEventCallbacks(self.inst)
            return old_OnRemoveFromEntity(self, ...)
        end

    else
        self.inst:DoTaskInTime(0, initialize_equips) -- may also use same client side logic with unequip update delayed, but below ComponentPostInit is better
        self.inst:ListenForEvent("equip", OnEquip)
        self.inst:ListenForEvent("unequip", OnUnequip)
        self.OnRemoveFromEntity = function(self, ...)
            self.inst:RemoveEventCallback("equip", OnEquip)
            self.inst:RemoveEventCallback("unequip", OnUnequip)
            return old_OnRemoveFromEntity(self, ...)
        end

    end
end)

AddComponentPostInit("inventory", function(self) --for hosting cave-less worlds without affecting other players, or Don't Starve Alone mod
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
	local old_Equip = self.Equip
	self.Equip = function(self, item, old_to_active, ...)
        if item == nil or item.components.equippable == nil or not item:IsValid() or item.components.equippable:IsRestricted(self.inst) or (self.noheavylifting and item:HasTag("heavy")) then
            return old_Equip(self, item, old_to_active, ...)
        end
        local owner = item.components.inventoryitem.owner
        local container = owner and owner.components.container

        if owner ~= GLOBAL.ThePlayer and
           container ~= GLOBAL.ThePlayer.components.inventory:GetOverflowContainer() then
            return old_Equip(self, item, old_to_active, ...)
        end
        local prevslot = self:GetItemSlot(item)
        local prevcontainer = nil
        if prevslot == nil and container ~= nil then
            prevslot = container:GetItemSlot(item)
            prevcontainer = container
        end

        local eslot = item.components.equippable.equipslot
        local olditem = self:GetEquippedItem(eslot)
        if olditem ~= nil then
            olditem.prevslot = prevslot
            olditem.prevcontainer = prevcontainer
        end

		return old_Equip(self, item, old_to_active, ...)
	end
end)