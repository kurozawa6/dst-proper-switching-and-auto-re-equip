local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
local previous_saved_inventory = {}

local function print_data(data) --for debugging
    for k, v in pairs(data) do
        print(k, v)
    end
end

local function cancel_task(task)
    if task ~= nil then
        task:Cancel()
        task = nil
    end
end

local function do_invntry_act_on_slot_w_dmmode_false(inst, slot, ActionFn)
    local playercontroller = inst.components.playercontroller
    local playercontroller_deploy_mode = playercontroller.deploy_mode --to study
    local inventory = inst.replica.inventory
    playercontroller.deploy_mode = false
    ActionFn(inventory, slot)
    playercontroller.deploy_mode = playercontroller_deploy_mode
end

local function try_put_active_item_to_slot(inst, slot)
    do_invntry_act_on_slot_w_dmmode_false(inst, slot, inst.replica.inventory.PutAllOfActiveItemInSlot)
end

local function try_swap_active_item_with_slot(inst, slot)
    do_invntry_act_on_slot_w_dmmode_false(inst, slot, inst.replica.inventory.SwapActiveItemWithSlot)
end

local function try_take_active_item_from_slot(inst, slot)
    do_invntry_act_on_slot_w_dmmode_false(inst, slot, inst.replica.inventory.TakeActiveItemFromAllOfSlot)
end

local function main_auto_switch(inst, eslot, previous_equipped_item, removed_slot)
    local obtained_item = latest_get_items[eslot]
    local slot_taken_from = latest_get_slots[eslot]
    if previous_equipped_item == obtained_item and previous_equipped_item and obtained_item then
        --print("Move", previous_equipped_item, "from", slot_taken_from, "to", removed_slot)
        local current_task = nil

        local function put_prompt()
            local inventory = inst.replica.inventory
            local item_on_dest_slot = inventory:GetItemInSlot(removed_slot)
            if not previous_equipped_item:IsValid() or
                   previous_equipped_item ~= inventory:GetActiveItem() or
                   previous_equipped_item == item_on_dest_slot then --or item_on_dest_slot ~= nil then
                cancel_task(current_task)
                --print("Put Task Cancelled with the following conditions:")
                --print(not previous_equipped_item:IsValid(), "IsNotValid", previous_equipped_item ~= inventory:GetActiveItem(),
                      --previous_equipped_item, "~=", inventory:GetActiveItem(), previous_equipped_item == item_on_dest_slot,
                      --previous_equipped_item, "==", item_on_dest_slot)
            elseif item_on_dest_slot == nil then
                try_put_active_item_to_slot(inst, removed_slot)
            elseif item_on_dest_slot ~= nil then --and previous_equipped_item ~= item_on_dest_slot then
                try_swap_active_item_with_slot(inst, removed_slot)
            else
                cancel_task(current_task)
                print("Put Task Cancelled Unexpectedly with the following:")
                print(previous_equipped_item, removed_slot, "IsValid is", previous_equipped_item:IsValid(), "Item on Dest Slot:", item_on_dest_slot, inventory:GetActiveItem())
            end
        end
        local function take_prompt()
            local inventory = inst.replica.inventory
            local item_on_dest_slot = inventory:GetItemInSlot(removed_slot)
            local item_on_slot_to_take = inventory:GetItemInSlot(slot_taken_from)
            if inventory:GetActiveItem() ~= nil and
               inventory:GetActiveItem() == previous_equipped_item and
               previous_equipped_item:IsValid() then
                cancel_task(current_task)
                current_task = inst:DoPeriodicTask(0, put_prompt)
            elseif not previous_equipped_item:IsValid() or
                       previous_equipped_item ~= item_on_slot_to_take or
                       previous_equipped_item == item_on_dest_slot or --or item_on_dest_slot ~= nil then
                       item_on_slot_to_take == nil then
                cancel_task(current_task)
                --print("Task Cancelled with the following conditions:")
                --print(not previous_equipped_item:IsValid(), previous_equipped_item ~= item_on_slot_to_take, previous_equipped_item, item_on_slot_to_take,
                      --previous_equipped_item == item_on_dest_slot, item_on_slot_to_take == nil)
            elseif previous_equipped_item == item_on_slot_to_take then
                try_take_active_item_from_slot(inst, slot_taken_from)
            else
                cancel_task(current_task)
                print("Take Task Cancelled Unexpectedly with the following:")
                print(previous_equipped_item, removed_slot, "IsValid is", previous_equipped_item:IsValid(), "Item on Dest Slot:", item_on_dest_slot, item_on_slot_to_take,
                      inventory:GetActiveItem())
            end
        end

        current_task = inst:DoPeriodicTask(0, take_prompt)
    end
end

local function ModOnEquip(inst, data)
    if not (type(data) == "table" and data.eslot and data.item) then return end
    local latest_equipped_item = data.item
    local eslot = data.eslot
    local previous_equipped_item = nil
    local removed_slot = nil
    if latest_equip_items[eslot] then
        previous_equipped_item = latest_equip_items[eslot]
    end
    latest_equip_items[eslot] = latest_equipped_item

    for slot, item in pairs(previous_saved_inventory) do
        --print(slot, item) --verbose, for debugging only
        if item == latest_equipped_item then -- if the latest equipped item is found on the previous saved inventory, then get its slot as slot to take
            removed_slot = slot
            break
        end
    end

    if removed_slot == nil and eslot and previous_equipped_item and latest_equipped_item then
        print("Main Auto Switch FN Unexpectedly Failed to Run with the Following:")
        print("Previous Equipped:", previous_equipped_item)
        print("Latest Equipped:", latest_equipped_item)
        print("Eslot:", eslot)
    end
    if removed_slot == nil then
        return
    end
    inst:DoTaskInTime(0, main_auto_switch, eslot, previous_equipped_item, removed_slot)
end

local function check_for_unequip(_, item, eslot)
    if not item:IsValid() or item:HasTag("projectile") and item:HasTag("NOCLICK") then
        print("IsValid:", item:IsValid(), "HasTag(\"projectile\"):", item:HasTag("projectile"), "HasTag(\"NOCLICK\"):", item:HasTag("NOCLICK"))
    end
end

local function ModOnUnequip(inst, data)
    if type(data) ~= "table" then return end
    local eslot = data.eslot
    local item = latest_equip_items[eslot]
    latest_equip_items[eslot] = nil
    if item == nil then return end -- to change?
    inst:DoTaskInTime(0, check_for_unequip, item, eslot)
end

local function update_obtain_previous_inventory_fn_to_delay(_, get_slot, item)
    previous_saved_inventory[get_slot] = item
end

local function ModOnItemGet(inst, data)
    local item = data.item
    local get_slot = data.slot
    local equippable = item.replica.equippable
    if equippable ~= nil then
        local eslot = equippable:EquipSlot()
        latest_get_items[eslot] = item
        latest_get_slots[eslot] = get_slot
    end
    inst:DoTaskInTime(0, update_obtain_previous_inventory_fn_to_delay, get_slot, item)
    --print("ModOnItemGet data:", item, get_slot, eslot, "Finished Updating Saved Inventory")
end

local function update_removal_previous_inventory_fn_to_delay(_, removed_slot)
    previous_saved_inventory[removed_slot] = nil
end

local function ModOnItemLose(inst, data) -- Huge mistake on hindsight: "IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS!"
    local removed_slot = data.slot
    inst:DoTaskInTime(0, update_removal_previous_inventory_fn_to_delay, removed_slot)
end

local function load_whole_inventory(inst)
    local inventory = inst.replica.inventory
    if inventory == nil then return {} end
    local numslots = inventory:GetNumSlots()
    local whole_inventory = {}
    for slot=1, numslots do
        whole_inventory[slot] = inventory:GetItemInSlot(slot)
    end
    return whole_inventory
end

local function initialize_inventory_and_equips(inst)
    previous_saved_inventory = load_whole_inventory(inst)
    latest_equip_items = inst.replica.inventory:GetEquips()
    print_data(previous_saved_inventory)
    print_data(latest_equip_items)
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end
    self.inst:DoTaskInTime(0, initialize_inventory_and_equips)

    self.inst:ListenForEvent("equip", ModOnEquip)
    self.inst:ListenForEvent("unequip", ModOnUnequip)
    self.inst:ListenForEvent("itemget", ModOnItemGet)
    self.inst:ListenForEvent("itemlose", ModOnItemLose)

    local OnRemoveFromEntity = self.OnRemoveFromEntity
    self.OnRemoveFromEntity = function(self, ...)
        self.inst:RemoveEventCallback("equip", ModOnEquip)
        self.inst:RemoveEventCallback("unequip", ModOnUnequip)
        self.inst:RemoveEventCallback("itemget", ModOnItemGet)
        self.inst:ListenForEvent("itemlose", ModOnItemLose)
        return OnRemoveFromEntity(self, ...)
    end
end)