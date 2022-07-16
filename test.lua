local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_remove_slot = nil
local latest_get_slot = nil

local function ModOnEquip(inst, data)
    if type(data) == "table" and data.eslot and data.item then
        local item = data.item
        print("ModOnEquip data.item:", item)
    end
    local function debug_print(_)
        print(latest_remove_slot, latest_get_slot)
    end
    local function delay_twice_debug_print(_)
        _:DoTaskInTime(0, debug_print)
    end
    inst:DoTaskInTime(0, delay_twice_debug_print)
    --if equipslots slot is taken then record item on slot
    --equipslots slot = equipped item
    --if mod latest remove slot == nil or mod latest give slot == nil then return end
    --if mod latest remove slot == mod latest give slot then return end
    --move previous equipped item to latest remove slot
end

local function ModOnUnequip(_, data)
    if type(data) ~= "table" then return end
    local item = data.item
    --print(item)
    --remove item from equipslots
end

local function ModOnItemGet(inst, data)
    --record to mod latest get slot
    local get_slot = data.slot
    local item = data.item
    local function latest_update(_)
        latest_get_slot = get_slot
    end
    inst:DoTaskInTime(0, latest_update)
    print("ModOnItemGet data:", item, get_slot)
end

local function ModOnItemLose(_, data)
    local remove_slot = data.slot
    latest_remove_slot = remove_slot
    print("ModOnItemLose data.slot:", remove_slot)
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