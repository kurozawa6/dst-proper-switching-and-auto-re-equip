local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
--local latest_remove_slot = nil
--local saved_eslot = nil
local saved_remove_slots = {}
local equipment_switched = {}
local saved_inventory = {}

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

local function ModOnItemGet(_, data)
    --record to mod latest get slot
    local item = data.item
    if item.replica.equippable == nil then return end
    local eslot = item.replica.equippable:EquipSlot()
    local get_slot = data.slot
    latest_get_items[eslot] = item
    latest_get_slots[eslot] = get_slot
    print("ModOnItemGet data:", item, get_slot, eslot, "Finished Updating Shared Mod Variables")
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS! use separate removed_slot for every equipslot?, terminate when item has no equipslot?
    --print("Printing itemlose Data:", data.item, data.slot)
    --print_data(data)
    local current_inventory = ThePlayer.replica.inventory:GetItems(inst)
    local current_equips = ThePlayer.replica.inventory:GetEquips(inst)
    local eslot = nil
    for _, item in pairs(current_equips) do
        if item_in_list(item, saved_inventory) and not item_in_list(item, current_inventory) then
            eslot = item.replica.equippable:EquipSlot()
            saved_remove_slots[eslot] = data.slot
        end
    end
    saved_inventory = current_inventory
    if eslot == nil then return end
    local removed_slot = nil
    local item = nil
    local slot_taken_from = nil
    local function save_local_copies(_)
        removed_slot = saved_remove_slots[eslot]
        item = latest_get_items[eslot]
        slot_taken_from = latest_get_slots[eslot]
        print("ModOnItemLose Variables:", item, removed_slot, eslot, "Finished Saving Shared Mod Variables")
    end
    inst:DoTaskInTime(0, save_local_copies)
    local function main_auto_switch()
        if equipment_switched[eslot] == true then
            equipment_switched[eslot] = false
            print("Move", item, "from", slot_taken_from, "to", removed_slot) -- TO IMPLEMENT ACTUAL FUNCTION
        end
    end
    inst:DoTaskInTime(0, delay_again, main_auto_switch)
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end
    if self.inst.replica.inventory ~= nil then
        saved_inventory = self.inst.replica.inventory:GetItems(self.inst)
    end
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