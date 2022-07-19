--IMPORTANT NOTES:
--GetItemSlot from replica inventory returns nil
--"equip" and "unequip" events' data.item.prevslot return nil

local ThePlayer = GLOBAL.ThePlayer
local EQUIPSLOTS = GLOBAL.EQUIPSLOTS

local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local move_item_task = nil
local mod_equipped_prevslots = {}
local mod_current_inventory_slots = {}

local function ModGetItemSlot(inventory, target_item)
    if target_item == nil then
        return nil
    end
    local numslots = inventory:GetNumSlots()
    print(numslots)
    if numslots then
        for slot = 1, numslots do
            local item = inventory:GetItemInSlot(slot)
            print(item)
            if item == target_item then
                return slot
            end
        end
    end
end

local function cancel_move_task()
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
        cancel_move_task()
    else
        move_item_attempt(item, slot)
    end
end

local function move_to_replacers_prevslot(item, slot)
    if move_item_task then
        cancel_move_task()
    end
    move_item_attempt(item, slot)
    move_item_task = ThePlayer:DoPeriodicTask(0, move_item_repeater, nil, item)
end

local function ModOnEquip(_, data)
    if type(data) == "table" and data.eslot and data.item then
        local item = data.item
        mod_equipped_prevslots[data.eslot] = item
        print(item)
        --print(item.prevslot) --always nil
        --print(data.item.prefab)
        --print(ModGetItemSlot(ThePlayer.replica.inventory, data.item)) --crashes coz... equipped item disappeared from slot?
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
    --local unequipped_item = mod_equipped_prevslots[data.eslot]
    --if unequipped_item == nil then return end
    local inventory = ThePlayer.replica.inventory
    local newslot = ModGetItemSlot(inventory, unequipped_item)
    if newslot ~= nil then
        mod_current_inventory_slots[newslot] = unequipped_item -- WARNING - ITEMS OBTAINED NOT BY UNEQUIP EVENT ARE NOT YET CONSIDERED
    end
    mod_equipped_prevslots[data.eslot] = nil

    --local current_equipped = mod_current_equipped_slots[data.eslot]
    --[[
    if current_equipped ~= nil then
        if TheWorld.ismastersim then
            inst:DoTaskInTime(0, )
    end
    ]]
    --local replacers_prevslot = current_equipped.prevslot --oops
    --print(data.slip) --seemingly always nil
    --[[inst:DoTaskInTime(0, some_print_debug, data)
    print(data.item)
    if replacers_prevslot == nil then return end
    if replacers_prevslot == data.item.prevslot then return end
    move_to_replacers_prevslot(data.item, replacers_prevslot)]]
end


local function register_inventory_slots(inventory)
    local numslots = inventory:GetNumSlots()
    if numslots == nil then return end
    for slot = 1, numslots do
        local item = inventory:GetItemInSlot(slot)
        print(item)
        mod_current_inventory_slots[slot] = item
    end
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end
    print("7777 THE PLAYER SUCCESSFULLY REGISTERED")

    self.inst:ListenForEvent("equip", ModOnEquip)
    self.inst:ListenForEvent("unequip", ModOnUnequip)

    local inventory = ThePlayer.replica.inventory
    if not self.ismastersim then
        self.inst:DoTaskInTime(0, register_inventory_slots, inventory)
    end

    local OnRemoveFromEntity = self.OnRemoveFromEntity
    self.OnRemoveFromEntity = function(self, ...)
        self.inst:RemoveEventCallback("equip", ModOnEquip)
        self.inst:RemoveEventCallback("unequip", ModOnUnequip)
        return OnRemoveFromEntity(self, ...)
    end
end)