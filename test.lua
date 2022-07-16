local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
--local latest_remove_slot = nil
local saved_replaced_eslot = nil

local function delay_again(inst, fn)
    inst:DoTaskInTime(0, fn)
end

local function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
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
            saved_replaced_eslot = eslot
        end
    end
    inst:DoTaskInTime(0, update_equipped_item)
    --if equipslots slot is taken then record item on slot
    --equipslots slot = equipped item
    --if mod latest remove slot == nil or mod latest give slot == nil then return end
    --if mod latest remove slot == mod latest give slot then return end
    --move previous equipped item to latest remove slot
end

local function ModOnUnequip(_, data)
    if type(data) ~= "table" then return end
    local eslot = data.eslot
    --local item = data.item
    latest_equip_items[eslot] = nil
    --print(item)
    --remove item from equipslots
end

local function ModOnItemGet(_, data)
    --record to mod latest get slot
    local item = data.item
    if item.replica.equippable == nil then return end
    local eslot = item.replica.equippable:EquipSlot()
    local get_slot = data.slot
    latest_get_items[eslot] = item
    latest_get_slots[eslot] = get_slot
    --local function latest_update(_)
    --end
    --inst:DoTaskInTime(0, latest_update)
    --print("ModOnItemGet data:", item, get_slot)
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS! use separate remove_slot for every equipslot, terminate when item has no equipslot
    --print("ModOnItemLose data:", remove_slot, item)
    local get_items_copy = {}
    local get_slots_copy = {}
    local remove_slot = nil
    local function save_local_copies(_)
        get_items_copy = shallowcopy(latest_get_items)
        get_slots_copy = shallowcopy(latest_get_slots)
        remove_slot = data.slot
    end
    inst:DoTaskInTime(0, save_local_copies)
    local function main_auto_switch()
        if saved_replaced_eslot then
            local eslot = saved_replaced_eslot --.equippable:EquipSlot()
            saved_replaced_eslot = nil
            --latest_remove_slot = remove_slot
            print("Move", get_items_copy[eslot], "from", get_slots_copy[eslot], "to", remove_slot) -- TO IMPLEMENT ACTUAL FUNCTION
        end
    end
    inst:DoTaskInTime(0, delay_again, main_auto_switch)
    --record to mod latest remove slot
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