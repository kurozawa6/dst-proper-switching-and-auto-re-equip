local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
--local latest_remove_slot = nil
local saved_eslot = nil
local equipment_switched = false

local function delay_again(inst, fn)
    inst:DoTaskInTime(0, fn)
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
            equipment_switched = true
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
    saved_eslot = eslot
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS! use separate remove_slot for every equipslot?, terminate when item has no equipslot?
    local eslot = nil
    local item = nil
    local slot_recipient = nil
    --local remove_slot = nil
    local function save_local_copies(_)
        eslot = saved_eslot
        item = latest_get_items[eslot]
        slot_recipient = latest_get_slots[eslot]
    end
    inst:DoTaskInTime(0, save_local_copies)
    local function main_auto_switch()
        if equipment_switched == true then
            equipment_switched = false
            print("Move", item, "from", slot_recipient, "to", data.slot) -- TO IMPLEMENT ACTUAL FUNCTION
        end
    end
    inst:DoTaskInTime(0, delay_again, main_auto_switch)
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end
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