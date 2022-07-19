local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local latest_equip_items = {}
local latest_get_items = {}
local latest_get_slots = {}
local saved_inventory = {}

local function print_data(data) --for debugging
   for k, v in pairs(data) do
      print(k, v)
   end
end

local function cancel_task(task)
   if task ~= nil then
      task:Cancel()
      task = nil
   end
end
local function try_put_active_item_to_slot(inst, slot)
   local playercontroller = inst.components.playercontroller
   local playercontroller_deploy_mode = playercontroller.deploy_mode --to study
   playercontroller.deploy_mode = false
   inst.replica.inventory:PutAllOfActiveItemInSlot(slot)
   playercontroller.deploy_mode = playercontroller_deploy_mode
end

local function try_take_active_item_from_slot(inst, slot)
   local playercontroller = inst.components.playercontroller
   local playercontroller_deploy_mode = playercontroller.deploy_mode --to study
   playercontroller.deploy_mode = false
   inst.replica.inventory:TakeActiveItemFromAllOfSlot(slot)
   playercontroller.deploy_mode = playercontroller_deploy_mode
end

local function main_auto_switch(inst, eslot, previous_equipped_item, removed_slot)
   local item_to_move = latest_get_items[eslot]
   local slot_taken_from = latest_get_slots[eslot]
   if previous_equipped_item == item_to_move and previous_equipped_item and item_to_move then
      --print("Move", item_to_move, "from", slot_taken_from, "to", removed_slot)
      local current_task = nil

      local function put_prompt()
         local inventory = inst.replica.inventory
         if not item_to_move:IsValid() or inventory:GetItemInSlot(removed_slot) ~= nil then
            cancel_task(current_task)
         elseif item_to_move == inventory:GetActiveItem() then
            try_put_active_item_to_slot(inst, removed_slot)
         else
            cancel_task(current_task)
         end
      end
      local function take_prompt()
         local inventory = inst.replica.inventory
         if not item_to_move:IsValid() or inventory:GetItemInSlot(removed_slot) ~= nil then
            cancel_task(current_task)
         elseif item_to_move == inventory:GetItemInSlot(slot_taken_from) then
            try_take_active_item_from_slot(inst, slot_taken_from)
         elseif item_to_move == inventory:GetActiveItem() then
            cancel_task(current_task)
            current_task = inst:DoPeriodicTask(0, put_prompt)
         else
            cancel_task(current_task)
         end
      end

      current_task = inst:DoPeriodicTask(0, take_prompt)
   end
end

local function update_latest_equip_fn_to_delay(_, item, eslot)
   latest_equip_items[eslot] = item
end

local function ModOnEquip(inst, data)
   if not (type(data) == "table" and data.eslot and data.item) then return end
   local item = data.item
   local eslot = data.eslot
   inst:DoTaskInTime(0, update_latest_equip_fn_to_delay, item, eslot)
end

local function ModOnUnequip(_, data)
   if type(data) ~= "table" then return end
   local eslot = data.eslot
   latest_equip_items[eslot] = nil
end

local function ModOnItemGet(_, data)
   local item = data.item
   local get_slot = data.slot
   saved_inventory[get_slot] = item
   local equippable = item.replica.equippable
   if equippable == nil then return end

   local eslot = equippable:EquipSlot()
   latest_get_items[eslot] = item
   latest_get_slots[eslot] = get_slot
   --print("ModOnItemGet data:", item, get_slot, eslot, "Finished Updating Saved Inventory")
end

local function ModOnItemLose(inst, data) -- IMPORTANT EVENT FUNCTION THAT IS CALLED ONLY WHEN NEEDED! USE THIS!
   local current_equips = inst.replica.inventory:GetEquips()
   local removed_slot = data.slot
   local equipped_item = nil
   local eslot = nil
   for _, item in pairs(current_equips) do
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
   --print("ModOnItemLose Variables:", equipped_item, removed_slot, eslot, "Finished Saving Shared Mod Variables")
   inst:DoTaskInTime(0, main_auto_switch, eslot, previous_equipped_item, removed_slot)
end

local function load_whole_inventory(inst)
   local inventory = inst.replica.inventory
   if inventory == nil then return {} end
   local numslots = inventory:GetNumSlots()
   local whole_inventory = {}
   for slot=1, numslots do
      whole_inventory[slot] = inventory:GetItemInSlot(slot)
   end
   return whole_inventory
end

local function initialize_inventory_and_equips(inst)
   saved_inventory = load_whole_inventory(inst)
   latest_equip_items = inst.replica.inventory:GetEquips()
   print_data(saved_inventory)
   print_data(latest_equip_items)
end

ENV.AddComponentPostInit("playercontroller", function(self)
   if self.inst ~= ThePlayer then return end
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