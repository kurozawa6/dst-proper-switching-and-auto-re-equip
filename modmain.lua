--IMPORTANT NOTES:
--GetItemSlot from replica inventory returns nil
--"equip" and "unequip" events' data.item.prevslot return nil

--local ThePlayer = GLOBAL.ThePlayer
--local EQUIPSLOTS = GLOBAL.EQUIPSLOTS

local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local move_item_task = nil
local mod_current_equipped_slots = {}

local function ModGetItemSlot(inventory, target_item)
    print("6666 ModGetItemSlot INITIATED")
    if target_item == nil then
        return nil
    end
    local numslots = inventory:GetNumSlots()
    print("4444 NUMSLOTS PRINTED BELOW")
    print(numslots)
    if numslots then
        for slot = 1, numslots do
            local item = inventory:GetItemInSlot(slot)
            print("5555 ITERATED ITEM PRINTED BELOW")
            print(item)
            if item == target_item then
                return slot
            end
        end
    end
end

local function CancelEquipTask()
    if move_item_task then
        move_item_task:Cancel()
        move_item_task = nil
    end
end

local function item_move_is_valid(item, slot)
    if item == nil then
        return false
    end
    local inventory = ThePlayer.replica.inventory
    if ModGetItemSlot(inventory, item) == slot then
        return false
    end
    return true
end

local function move_item_attempt(item, slot)
    local playercontroller = ThePlayer.components.playercontroller
    local current_deploy_mode = playercontroller.deploy_mode
    playercontroller.deploy_mode = false
    local inventory = ThePlayer.replica.inventory
    local slot_taken_from = ModGetItemSlot(inventory, item)
    ThePlayer.replica.inventory:TakeActiveItemFromAllOfSlot(slot_taken_from)
    ThePlayer.replica.inventory:PutAllOfActiveItemInSlot(slot)
    playercontroller.deploy_mode = current_deploy_mode
end

local function move_item_repeater(_, item, slot)
    if not item:isValid() or not item_move_is_valid(item, slot) then
        CancelEquipTask()
    else
        move_item_attempt(item, slot)
    end
end

local function move_to_replacers_prevslot(item, slot)
    if move_item_task then
        CancelEquipTask()
    end
    move_item_attempt(item, slot)
    move_item_task = ThePlayer:DoPeriodicTask(0, move_item_repeater, nil, item)
end

local function ModOnEquip(_, data)
    if type(data) == "table" and data.eslot and data.item then
        local item = data.item
        mod_current_equipped_slots[data.eslot] = item
        print("2222 equipped info BELOW")
        print(item)
        print(item.prevslot)
        --print(data.item.prefab)
        --print(ModGetItemSlot(ThePlayer.replica.inventory, data.item)) --crashes coz equipped item disappeared from slot
    end
end

local function some_print_debug(data)
    print("3333 UNEQUIPPED ITEM AND CURRENT SLOT BELOW")
    --print(data.item)
    --print(data.item.prefab) --data.item is nil, so this line crashes
    --print(ModGetItemSlot(ThePlayer.replica.inventory, data.item))
end

local function ModOnUnequip(inst, data)
    if type(data) ~= "table" then return end
    local item = data.item
    print(item)
    print(data.eslot)
    local current_equipped = mod_current_equipped_slots[data.eslot]
    if current_equipped == nil then return end
    local replacers_prevslot = current_equipped.prevslot
    --print(data.slip) --seemingly always nil
    --[[inst:DoTaskInTime(0, some_print_debug, data)
    print(data.item)
    if replacers_prevslot == nil then return end
    if replacers_prevslot == data.item.prevslot then return end

    move_to_replacers_prevslot(data.item, replacers_prevslot)
    mod_current_equipped_slots[data.eslot] = nil]]
end


local function register_equipped_items(inst)
    for _, eslot in pairs(EQUIPSLOTS) do
        ModOnEquip(inst, {
            eslot = eslot,
            item = inst.replica.inventory:GetEquippedItem(eslot)
        })
    end
end

ENV.AddComponentPostInit("playercontroller", function(self)
    --print("6666 POSTINIT SPECIALIZED")
    if self.inst ~= ThePlayer then return end
    print("7777 THE PLAYER SUCCESSFULLY REGISTERED")

    self.inst:ListenForEvent("equip", ModOnEquip)
    self.inst:ListenForEvent("unequip", ModOnUnequip)
--[[
    if not self.ismastersim then
        self.inst:DoTaskInTime(0, register_equipped_items)
    end
]]
    local OnRemoveFromEntity = self.OnRemoveFromEntity
    self.OnRemoveFromEntity = function(self, ...)
        self.inst:RemoveEventCallback("equip", ModOnEquip)
        self.inst:RemoveEventCallback("unequip", ModOnUnequip)
        return OnRemoveFromEntity(self, ...)
    end
end)