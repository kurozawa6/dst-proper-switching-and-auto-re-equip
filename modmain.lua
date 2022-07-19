local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
local saved_inventory = {}

--[[
    Try taking if:
        item is valid?/item is in slot_taken_from
        item is not active item
    until:
        item is invalid/item is not in slot_taken_from
        item is already the active item
        an item already exists in removed_slot

    Try moving/putting if:
        item is valid and is activeitem
        removed_slot is empty
    until:
        item is invalid or is no longer active item
        item or an item is in removed_slot

    Completely cancel task if?:
        an item already exists in removed_slot
        item is invalid
]]

local function delay_again(inst, fn)
    inst:DoTaskInTime(0, fn)
end

local function item_in_list(item, list)
	for _, v in pairs(list) do
		if v == item then return true end
	end
	return false
end

local function print_data(data)
    for k, v in pairs(data) do
        print(k, v)
    end
end

local function ModOnEquip(inst, data)
    if not (type(data) == "table" and data.eslot and data.item) then return end
    local item = data.item
    local eslot = data.eslot
    local function update_latest_equip_fn_to_delay(_)
        latest_equip_items[eslot] = item
    end
    inst:DoTaskInTime(0, update_latest_equip_fn_to_delay)
    --print("ModOnEquip data.item:", item)
    -- initial rough idea, deletable:
    --if mod latest remove slot == nil or mod latest give slot == nil then return end
    --if mod latest remove slot == mod latest give slot then return end
    --move previous equipped item to latest remove slot
end

local function ModOnUnequip(_, data)
    if type(data) ~= "table" then return end
    local eslot = data.eslot
    latest_equip_items[eslot] = nil
end

local function ModOnItemGet(_, data)
    --record to mod latest get slot
    local item = data.item
    local get_slot = data.slot
    saved_inventory[get_slot] = item
    local equippable = item.replica.equippable
    if equippable == nil then return end

    local eslot = equippable:EquipSlot()
    latest_get_items[eslot] = item
    latest_get_slots[eslot] = get_slot
    print("ModOnItemGet data:", item, get_slot, eslot, "Finished Updating Saved Inventory")
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS! use separate removed_slot for every equipslot?, terminate when item has no equipslot?
    local current_equips = inst.replica.inventory:GetEquips()
    --print_data(current_equips)
    local removed_slot = data.slot
    local equipped_item = nil
    local eslot = nil
    for _, item in pairs(current_equips) do
        --print(item, saved_inventory[removed_slot])
        if item == saved_inventory[removed_slot] then
            equipped_item = item
            eslot = equipped_item.replica.equippable:EquipSlot()
            break
        end
    end
    saved_inventory[removed_slot] = nil
    if eslot == nil then return end

    local previous_equipped_item = latest_equip_items[eslot]
    latest_equip_items[eslot] = equipped_item
    local item_to_move = nil
    local slot_taken_from = nil

    local function main_auto_switch(inst)
        item_to_move = latest_get_items[eslot]
        slot_taken_from = latest_get_slots[eslot]
        print("ModOnItemLose Variables:", equipped_item, removed_slot, eslot, "Finished Saving Shared Mod Variables")
        if previous_equipped_item == item_to_move and previous_equipped_item and item_to_move then
            print("Move", item_to_move, "from", slot_taken_from, "to", removed_slot) -- TO IMPLEMENT ACTUAL FUNCTION

            local current_task = nil
            local function cancel_task(task)
                if task ~= nil then
                    task:Cancel()
                    task = nil
                end
            end
            local function try_put_active_item_to_removed_slot()
                local playercontroller = inst.components.playercontroller
                local playercontroller_deploy_mode = playercontroller.deploy_mode --to study
                playercontroller.deploy_mode = false
                inst.replica.inventory:PutAllOfActiveItemInSlot(removed_slot)
                playercontroller.deploy_mode = playercontroller_deploy_mode
            end
            local function put_prompt()
                local inventory = inst.replica.inventory
                if not item_to_move:IsValid() or inventory:GetItemInSlot(removed_slot) ~= nil then
                    cancel_task(current_task)
                elseif item_to_move == inventory:GetActiveItem() then -- if item is valid and is active item and removed_slot is empty
                    try_put_active_item_to_removed_slot()
                else
                    cancel_task(current_task)
                end
            end

            local function try_take_active_item_from_slot_taken_from()
                local playercontroller = inst.components.playercontroller
                local playercontroller_deploy_mode = playercontroller.deploy_mode --to study
                playercontroller.deploy_mode = false
                inst.replica.inventory:TakeActiveItemFromAllOfSlot(slot_taken_from)
                playercontroller.deploy_mode = playercontroller_deploy_mode
            end
            local function take_prompt()
                local inventory = inst.replica.inventory
                if not item_to_move:IsValid() or inventory:GetItemInSlot(removed_slot) ~= nil then
                    cancel_task(current_task)
                elseif item_to_move == inventory:GetItemInSlot(slot_taken_from) then -- if item is valid and item is in slot_taken from and item is not active item then
                    try_take_active_item_from_slot_taken_from()
                elseif item_to_move == inventory:GetActiveItem() then -- if item is not in slot_taken from and item is active item
                    cancel_task(current_task)
                    current_task = inst:DoPeriodicTask(0, put_prompt)
                else
                    cancel_task(current_task)
                end
            end

            current_task = inst:DoPeriodicTask(0, take_prompt)

        end
    end
    inst:DoTaskInTime(0, main_auto_switch)
end

local function load_whole_inventory(inst)
    local inventory = inst.replica.inventory
    if inventory == nil then return {} end
    local numslots = inventory:GetNumSlots()
    local whole_inventory = {}
    for slot=1, numslots do
        whole_inventory[slot] = inventory:GetItemInSlot(slot)
        --print(slot, inst.replica.inventory:GetItemInSlot(slot))
    end
    return whole_inventory
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end
    local function initialize_inventory_and_equips(inst)
        saved_inventory = load_whole_inventory(inst)
        latest_equip_items = inst.replica.inventory:GetEquips()
        print_data(saved_inventory)
        print_data(latest_equip_items)
    end
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