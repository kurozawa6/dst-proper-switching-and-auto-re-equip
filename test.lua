local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
--local latest_remove_slot = nil
--local saved_eslot = nil
--local saved_remove_slots = {}
local equipment_switched = {}
local saved_inventory = nil

local function save_inventory(inst)
    local inventory = inst.replica.inventory
    if inventory == nil then return nil end
    local numslots = inventory:GetNumSlots()
    local output_saved_inventory = {}
    for slot=1, numslots do
        output_saved_inventory[slot] = inventory:GetItemInSlot(slot)
        --print(slot, inst.replica.inventory:GetItemInSlot(slot))
    end
    return output_saved_inventory
end

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
    local equip_item_to_replace = nil
    if latest_equip_items[eslot] then
        equip_item_to_replace = latest_equip_items[eslot]
    end
    latest_equip_items[eslot] = item
    --print("ModOnEquip data.item:", item)
    local function update_equipped_item(_)
        if equip_item_to_replace and latest_get_items[eslot] and equip_item_to_replace == latest_get_items[eslot] then
            equipment_switched[eslot] = true
        end
    end
    inst:DoTaskInTime(0, update_equipped_item)
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

local function ModOnItemGet(inst, data)
    --record to mod latest get slot
    local item = data.item
    if item.replica.equippable == nil then return end
    local eslot = item.replica.equippable:EquipSlot()
    local get_slot = data.slot
    latest_get_items[eslot] = item
    latest_get_slots[eslot] = get_slot
    saved_inventory = save_inventory(inst)
    print("ModOnItemGet data:", item, get_slot, eslot, "Finished Updating Shared Mod Variables")
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS! use separate removed_slot for every equipslot?, terminate when item has no equipslot?
    local current_equips = inst.replica.inventory:GetEquips()
    --print_data(current_equips)
    local removed_slot = data.slot
    --local item_equipped = nil
    local eslot = nil
    if saved_inventory ~= nil then
        for _, item in pairs(current_equips) do
            print(item, saved_inventory[removed_slot])
            if item == saved_inventory[removed_slot] then
                eslot = item.replica.equippable:EquipSlot()
                print("ITEM FOUND!", item, eslot)
                break
            end
        end
    end
    saved_inventory = save_inventory(inst)
    if eslot == nil then return end
    --saved_remove_slots[eslot] = removed_slot
    local item_to_move = nil
    local slot_taken_from = nil
    local function update_variables_to_use(_)
        item_to_move = latest_get_items[eslot]
        slot_taken_from = latest_get_slots[eslot]
        print("ModOnItemLose Variables:", item_to_move, removed_slot, eslot, "Finished Saving Shared Mod Variables")
    end
    inst:DoTaskInTime(0, update_variables_to_use)
    local function main_auto_switch()
        if equipment_switched[eslot] == true then
            equipment_switched[eslot] = false
            print("Move", item_to_move, "from", slot_taken_from, "to", removed_slot) -- TO IMPLEMENT ACTUAL FUNCTION
        end
    end
    inst:DoTaskInTime(0, delay_again, main_auto_switch)
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end
    saved_inventory = save_inventory(self.inst)
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