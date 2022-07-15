--pseudocode
mod_current_equipped_slots = {}

local function move_to_replacers_prevslot(item, slot)
end

local function ModOnEquip(_, data)
    if type(data) == "table" and data.eslot and data.item then
        mod_current_equipped_slots[data.eslot] = data.item
    end
end

local function ModOnUnequip(_, data)
    if type(data) ~= "table" then return end
    local current_equipped = mod_current_equipped_slots[data.eslot]
    if current_equipped == nil then return end
    local replacers_prevslot = current_equipped.prevslot
    if replacers_prevslot == nil then return end
    if replacers_prevslot == data.item.prevslot then return end

    move_to_replacers_prevslot(data.item, replacers_prevslot)
    mod_current_equipped_slots[data.eslot] = nil 
end

self.inst:ListenForEvent("equip", ModOnEquip)
self.inst:ListenForEvent("unequip", ModOnUnequip)