local latest_equip_items = {}
local latest_get_item_per_eslot = {}
local latest_get_slot_per_eslot = {}
local latest_get_item_is_inbackpack_per_eslot = {}
local previous_saved_inventory = {}
local previous_saved_backpack = {}
local saved_backpack_replica_container = nil
local saved_handequip_is_projectile = false

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
    local playercontroller_deploy_mode = playercontroller.deploy_mode --to study
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

local function update_inventory_on_get_fn_to_delay(_, get_slot, item)
    previous_saved_inventory[get_slot] = item
end

local function InventoryOnItemGet(inst, data)
    local item = data.item
    local get_slot = data.slot
    local equippable = item.replica.equippable
    if equippable ~= nil then
        local eslot = equippable:EquipSlot()
        latest_get_item_per_eslot[eslot] = item
        latest_get_slot_per_eslot[eslot] = get_slot
        latest_get_item_is_inbackpack_per_eslot[eslot] = false
    end
    inst:DoTaskInTime(0, update_inventory_on_get_fn_to_delay, get_slot, item)
    --print("InventoryOnItemGet data:", item, get_slot, eslot, "Finished Updating Saved Inventory")
end

local function update_inventory_on_remove_fn_to_delay(_, removed_slot)
    previous_saved_inventory[removed_slot] = nil
end

local function InventoryOnItemLose(inst, data) -- Huge mistake on hindsight: "IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS!"
    local removed_slot = data.slot
    inst:DoTaskInTime(0, update_inventory_on_remove_fn_to_delay, removed_slot)
end

local function initialize_backpack(backpack_replica_container)
    previous_saved_backpack = backpack_replica_container:GetItems()
    --print_data(previous_saved_backpack)
end

local function update_backpack_on_get_fn_to_delay(_, get_slot, item)
    previous_saved_backpack[get_slot] = item
end

local function BackpackOnItemGet(inst, data)
    local item = data.item
    local get_slot = data.slot
    local equippable = item.replica.equippable
    if equippable ~= nil then
        local eslot = equippable:EquipSlot()
        latest_get_item_per_eslot[eslot] = item
        latest_get_slot_per_eslot[eslot] = get_slot
        latest_get_item_is_inbackpack_per_eslot[eslot] = true
    end
    inst:DoTaskInTime(0, update_backpack_on_get_fn_to_delay, get_slot, item)
    --print("InventoryOnItemGet data:", item, get_slot, eslot, "Finished Updating Saved Backpack")
end

local function update_backpack_on_remove_fn_to_delay(_, removed_slot)
    previous_saved_backpack[removed_slot] = nil
end

local function BackpackOnItemLose(inst, data)
    local removed_slot = data.slot
    inst:DoTaskInTime(0, update_backpack_on_remove_fn_to_delay, removed_slot)
end

local function ListenForEventsBackpack(inst)
    inst:ListenForEvent("itemget", BackpackOnItemGet)
    inst:ListenForEvent("itemlose", BackpackOnItemLose)
end

local function RemoveEventCallbacksBackpack(inst)
    inst:RemoveEventCallback("itemget", BackpackOnItemGet)
    inst:RemoveEventCallback("itemlose", BackpackOnItemLose)
end

local function cancel_task(task)
    if task ~= nil then
        task:Cancel()
        --task = nil -- oopsie
        --print("A periodic task has been cancelled successfully.")
    else
        --print("A nil periodic task has been tried to cancel")
    end
end

local function main_auto_switch(inst, eslot, previous_equipped_item, destination_slot, equipped_is_from_backpack)
    local obtained_item = latest_get_item_per_eslot[eslot]

    if not (previous_equipped_item == obtained_item and previous_equipped_item and obtained_item) then
        return
    end
    local slot_to_take_from = latest_get_slot_per_eslot[eslot]
    --print("Move", previous_equipped_item, "from", slot_to_take_from, "to", destination_slot)
    local obtained_is_in_backpack = latest_get_item_is_inbackpack_per_eslot[eslot]

    local active_item = nil
    local inventory_destination = nil
    local item_on_dest_slot = nil
    local function refresh_common_variables() --refreshes active_item, inventory_destination, and item_on_dest_slot
        active_item = inst.replica.inventory:GetActiveItem()
        inventory_destination = nil
        if not equipped_is_from_backpack then
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
               active_item ~= previous_equipped_item or
               previous_equipped_item == item_on_dest_slot or
               not previous_equipped_item:IsValid() then
            cancel_task(current_second_task)
            --print("Put Task Cancelled with the following conditions:")
            --print(not previous_equipped_item:IsValid(), "IsNotValid", previous_equipped_item ~= active_item,
                    --previous_equipped_item, "~=", active_item, previous_equipped_item == item_on_dest_slot,
                    --previous_equipped_item, "==", item_on_dest_slot)
        elseif item_on_dest_slot == nil then
            try_put_active_item_to_slot(destination_slot, inventory_destination)
        elseif item_on_dest_slot ~= nil then --and previous_equipped_item ~= item_on_dest_slot then
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
               active_item == previous_equipped_item and
               previous_equipped_item ~= item_on_dest_slot and
               previous_equipped_item:IsValid() then
            if item_on_dest_slot == nil then
                try_put_active_item_to_slot(destination_slot, inventory_destination)
            else
                try_swap_active_item_with_slot(destination_slot, inventory_destination)
            end
            cancel_task(current_task)
            current_second_task = inst:DoPeriodicTask(0, put_prompt)
        elseif not previous_equipped_item:IsValid() or
                   previous_equipped_item ~= item_on_slot_to_take or
                   previous_equipped_item == item_on_dest_slot or --or item_on_dest_slot ~= nil then
                   item_on_slot_to_take == nil then
            cancel_task(current_task)
            --print("Task Cancelled with the following conditions:")
            --print(not previous_equipped_item:IsValid(), previous_equipped_item ~= item_on_slot_to_take, previous_equipped_item, item_on_slot_to_take,
                    --previous_equipped_item == item_on_dest_slot, item_on_slot_to_take == nil)
        elseif previous_equipped_item == item_on_slot_to_take then
            try_take_active_item_from_slot(slot_to_take_from, inventory_source)
        else
            cancel_task(current_task)
        end
    end

    take_prompt()
    current_task = inst:DoPeriodicTask(0, take_prompt)
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
    if latest_equip_items[eslot] then
        previous_equipped_item = latest_equip_items[eslot]
    end
    latest_equip_items[eslot] = latest_equipped_item

    if eslot == GLOBAL.EQUIPSLOTS.HANDS then
        saved_handequip_is_projectile = latest_equipped_item:HasTag("projectile")
    end

    for slot, item in pairs(previous_saved_inventory) do
        --print(slot, item) --verbose, for debugging only
        if item == latest_equipped_item then -- if the latest equipped item is found on the previous saved inventory, then get its slot as destination slot
            removed_slot = slot
            break
        end
    end 
    --removed usage of next fn to check for empty tables because next doesn't exist in the modmain environment
    if removed_slot == nil then --and previous_saved_backpack ~= nil then -- no need to check for previous_saved_backpack being nil because it defaults to {}
        for slot, item in pairs(previous_saved_backpack) do
            if item == latest_equipped_item then
                removed_slot = slot
                is_from_backpack = true
                break
            end
        end
    end
    if latest_equipped_item:HasTag("backpack") then
        local backpack = inst.replica.inventory:GetOverflowContainer()
        if backpack ~= nil then
            if saved_backpack_replica_container ~= nil then
                RemoveEventCallbacksBackpack(saved_backpack_replica_container.inst)
            end
            saved_backpack_replica_container = backpack.inst.replica.container
            initialize_backpack(saved_backpack_replica_container)
            ListenForEventsBackpack(saved_backpack_replica_container.inst)
        end
    end

    if removed_slot == nil then
        return
    end
    inst:DoTaskInTime(0, main_auto_switch, eslot, previous_equipped_item, removed_slot, is_from_backpack)
end

local function item_tables_to_check(inst)
    local inventory = inst.replica.inventory
    local tables_to_check = {}
    local active_item = inventory:GetActiveItem()
    if active_item ~= nil then
        table.insert(tables_to_check, {_ = active_item})
    end
    local inventory_items_table = inventory:GetItems()
    if inventory_items_table ~= nil then
        table.insert(tables_to_check, inventory_items_table)
    end
    local open_containers = inventory:GetOpenContainers()
    if open_containers ~= nil then
        for container in pairs(open_containers) do
            local container_replica = container and container.replica.container
            if container_replica then
                table.insert(tables_to_check, container_replica:GetItems())
            end
        end
    end
    return tables_to_check
end

local function next_same_prefab_item_from_tables(tables_to_check, item_to_compare)
    for _, item_table in ipairs(tables_to_check) do
        for _,item in pairs(item_table) do
            if item.prefab == item_to_compare.prefab then
                return item
            end
        end
    end
    return nil
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

local function OnUnequip(inst, data)
    if type(data) ~= "table" then
        return
    end
    local eslot = data.eslot
    local item = latest_equip_items[eslot]
    latest_equip_items[eslot] = nil

    if item == nil then
        return
    end
    if item:HasTag("backpack") then
        previous_saved_backpack = {}
        if saved_backpack_replica_container ~= nil then
            RemoveEventCallbacksBackpack(saved_backpack_replica_container.inst)
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
        inst:DoTaskInTime(0, main_auto_equip, item, eslot, previous_is_projectile) -- delay one frame if mastersim as mastersim unequip event is pushed before projectile thrown fn
    end
end

local function initialize_inventory_and_equips(inst)
    local inventory = inst.replica.inventory
    previous_saved_inventory = inventory:GetItems()
    latest_equip_items = inventory:GetEquips()
    local handequip = latest_equip_items[GLOBAL.EQUIPSLOTS.HANDS]
    if handequip ~= nil then
        saved_handequip_is_projectile = handequip:HasTag("projectile")
    end
    --print_data(previous_saved_inventory)
    --print_data(latest_equip_items)
end

local function ListenForEventsPlayer(inst)
    inst:ListenForEvent("itemget", InventoryOnItemGet)
    inst:ListenForEvent("itemlose", InventoryOnItemLose)
    inst:ListenForEvent("equip", OnEquip)
    inst:ListenForEvent("unequip", OnUnequip)
end

local function RemoveEventCallbacksPlayer(inst)
    inst:RemoveEventCallback("itemget", InventoryOnItemGet)
    inst:RemoveEventCallback("itemlose", InventoryOnItemLose)
    inst:RemoveEventCallback("equip", OnEquip)
    inst:RemoveEventCallback("unequip", OnUnequip)
end

local function initialize_player_and_backpack(inst)
    initialize_inventory_and_equips(inst)
    ListenForEventsPlayer(inst)
    local backpack = inst.replica.inventory:GetOverflowContainer()
    if backpack ~= nil then
        saved_backpack_replica_container = backpack.inst.replica.container
        initialize_backpack(saved_backpack_replica_container)
        ListenForEventsBackpack(saved_backpack_replica_container.inst)
    end
end

AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= GLOBAL.ThePlayer then return end
    self.inst:DoTaskInTime(0, initialize_player_and_backpack)

    local old_OnRemoveFromEntity = self.OnRemoveFromEntity
    self.OnRemoveFromEntity = function(self_local, ...)
        RemoveEventCallbacksPlayer(self_local.inst)
        return old_OnRemoveFromEntity(self_local, ...)
    end
end)