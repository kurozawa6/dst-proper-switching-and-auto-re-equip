local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_remove_slot = nil -- TO CHANGE TO TABLE?
local latest_get_slot = nil
local latest_get_item = nil
local latest_equipped_item = nil
local equipment_switched = false

local function delay_again(inst, fn)
    inst:DoTaskInTime(0, fn)
end

local function ModOnEquip(inst, data)
    if not (type(data) == "table" and data.eslot and data.item) then return end
    local item = data.item
    local item_to_replace = nil
    if latest_equipped_item then
        item_to_replace = latest_equipped_item
    end
    latest_equipped_item = item
    --print("ModOnEquip data.item:", item)
    local function update_equipped_item(_)
        if item_to_replace and latest_get_item and item_to_replace == latest_get_item then
            equipment_switched = true
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
    --local item = data.item
    latest_equipped_item = nil
    --print(item)
    --remove item from equipslots
end

local function ModOnItemGet(_, data)
    --record to mod latest get slot
    local get_slot = data.slot
    local item = data.item
    latest_get_slot = get_slot
    latest_get_item = item
    --local function latest_update(_)
    --end
    --inst:DoTaskInTime(0, latest_update)
    --print("ModOnItemGet data:", item, get_slot)
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS! use separate remove_slot for every equipslot, terminate when item has no equipslot
    local remove_slot = data.slot
    latest_remove_slot = remove_slot
    --print("ModOnItemLose data:", remove_slot, item)
    local function main_auto_switch()
        if equipment_switched == true then
            equipment_switched = false
            print("Move", latest_get_item, "from", latest_get_slot, "to", latest_remove_slot) -- TO IMPLEMENT ACTUAL FUNCTION
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