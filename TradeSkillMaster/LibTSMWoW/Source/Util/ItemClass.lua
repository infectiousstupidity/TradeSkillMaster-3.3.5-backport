-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local LibTSMWoW = select(2, ...).LibTSMWoW
local ItemClass = LibTSMWoW:Init("Util.ItemClass")
local ClientInfo = LibTSMWoW:Include("Util.ClientInfo")
local private = {
	classes = {},
	subClasses = {},
	classLookup = {},
	classIdLookup = {},
	inventorySlotIdLookup = {},
	armorSubClassHasInventorySlots = {},
	armorGenericInventorySlots = {},
	armorInventorySlots = {},
	emptyTable = {},
}



-- ============================================================================
-- Data
-- ============================================================================

local RETAIL_ITEM_CLASS_IDS = {
	Enum.ItemClass.Weapon,
	Enum.ItemClass.Armor,
	Enum.ItemClass.Container,
	Enum.ItemClass.Gem,
	Enum.ItemClass.ItemEnhancement,
	Enum.ItemClass.Consumable,
	Enum.ItemClass.Glyph,
	Enum.ItemClass.Tradegoods,
	Enum.ItemClass.Recipe,
	Enum.ItemClass.Profession,
	Enum.ItemClass.Housing,
	Enum.ItemClass.Battlepet,
	Enum.ItemClass.Questitem,
	Enum.ItemClass.Miscellaneous,
}
local PANDA_ITEM_CLASS_IDS = {
	Enum.ItemClass.Weapon,
	Enum.ItemClass.Armor,
	Enum.ItemClass.Container,
	Enum.ItemClass.Consumable,
	Enum.ItemClass.Glyph,
	Enum.ItemClass.Tradegoods,
	Enum.ItemClass.Projectile,
	Enum.ItemClass.Quiver,
	Enum.ItemClass.Recipe,
	Enum.ItemClass.Gem,
	Enum.ItemClass.Miscellaneous,
	Enum.ItemClass.Questitem,
	Enum.ItemClass.Battlepet,
}
local WRATH_ITEM_CLASS_IDS = {
	Enum.ItemClass.Weapon,
	Enum.ItemClass.Armor,
	Enum.ItemClass.Container,
	Enum.ItemClass.Consumable,
	Enum.ItemClass.Glyph,
	Enum.ItemClass.Tradegoods,
	Enum.ItemClass.Projectile,
	Enum.ItemClass.Quiver,
	Enum.ItemClass.Recipe,
	Enum.ItemClass.Gem,
	Enum.ItemClass.Miscellaneous,
	Enum.ItemClass.Questitem,
}
local BCC_ITEM_CLASS_IDS = {
	Enum.ItemClass.Weapon,
	Enum.ItemClass.Armor,
	Enum.ItemClass.Container,
	Enum.ItemClass.Consumable,
	Enum.ItemClass.Tradegoods,
	Enum.ItemClass.Projectile,
	Enum.ItemClass.Quiver,
	Enum.ItemClass.Recipe,
	Enum.ItemClass.Gem,
	Enum.ItemClass.Reagent,
	Enum.ItemClass.Miscellaneous,
	Enum.ItemClass.Questitem,
}
local VANILLA_ITEM_CLASS_IDS = {
	Enum.ItemClass.Weapon,
	Enum.ItemClass.Armor,
	Enum.ItemClass.Container,
	Enum.ItemClass.Consumable,
	Enum.ItemClass.Tradegoods,
	Enum.ItemClass.Projectile,
	Enum.ItemClass.Quiver,
	Enum.ItemClass.Recipe,
	Enum.ItemClass.Reagent,
	Enum.ItemClass.Miscellaneous,
}
local ARMOR_GENERIC_INVENTORY_SLOTS = {
	Enum.InventoryType.IndexNeckType,
	Enum.InventoryType.IndexCloakType,
	Enum.InventoryType.IndexFingerType,
	Enum.InventoryType.IndexTrinketType,
	Enum.InventoryType.IndexHoldableType,
	Enum.InventoryType.IndexBodyType,
}
local ARMOR_INVENTORY_SLOTS = {
	Enum.InventoryType.IndexHeadType,
	Enum.InventoryType.IndexShoulderType,
	Enum.InventoryType.IndexChestType,
	Enum.InventoryType.IndexWaistType,
	Enum.InventoryType.IndexLegsType,
	Enum.InventoryType.IndexFeetType,
	Enum.InventoryType.IndexWristType,
	Enum.InventoryType.IndexHandType,
}
local ARMOR_SUB_CLASSES_WITH_INVENTORY_SLOTS = {
	Enum.ItemArmorSubclass.Plate,
	Enum.ItemArmorSubclass.Mail,
	Enum.ItemArmorSubclass.Leather,
	Enum.ItemArmorSubclass.Cloth,
}



-- ============================================================================
-- Module Loading
-- ============================================================================

ItemClass:OnModuleLoad(function()
	local data = nil
	if LibTSMWoW.IsRetail() then
		data = RETAIL_ITEM_CLASS_IDS
	elseif LibTSMWoW.IsPandaClassic() then
		data = PANDA_ITEM_CLASS_IDS
	elseif LibTSMWoW.IsWrathClassic() then
		data = WRATH_ITEM_CLASS_IDS
	elseif LibTSMWoW.IsBCClassic() then
		data = BCC_ITEM_CLASS_IDS
	elseif LibTSMWoW.IsVanillaClassic() then
		data = VANILLA_ITEM_CLASS_IDS
	else
		error("Unknown game version")
	end

	for _, classId in ipairs(data) do
		local class = ItemClass.GetClassInfo(classId)
		if class then
			private.classIdLookup[strlower(class)] = classId
			private.classLookup[class] = {}
			private.classLookup[class]._index = classId
			if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
				local subClasses = C_AuctionHouse.GetAuctionItemSubClasses(classId)
				for _, subClassId in pairs(subClasses) do
					-- In 1.5.8, Blizzard added an invalid classId=0, subClassId=1
					if classId ~= 0 and subClassId ~= -1 then
						local subClassName = ItemClass.GetSubClassInfo(classId, subClassId)
						if subClassName and not strfind(subClassName, "(OBSOLETE)") then
							private.classLookup[class][subClassName] = subClassId
						end
					end
				end
			else
				-- 3.3.5a: GetAuctionItemSubClasses(classId) takes a 1-based AH *position* (not the
				-- modern Enum class id) and returns subclass *names*, so feeding the Enum class id and
				-- treating the result as ids gave subclasses from the wrong class (e.g. Container showed
				-- Bows/Crossbows). Build straight from Enum.__ItemClassInfo, which is keyed by the real
				-- Enum subclass id -> localized name, so the dropdown and the GetSubClassId filter agree.
				local subClassInfo = Enum.__ItemClassInfo and Enum.__ItemClassInfo[classId]
				if subClassInfo then
					for subClassId, subClassName in pairs(subClassInfo) do
						if subClassName and not strfind(subClassName, "(OBSOLETE)") then
							private.classLookup[class][subClassName] = subClassId
						end
					end
				end
			end
		end
	end

	-- Standard TSM class aliases (both English slash filters and Chinese translations)
	local BUILTIN_CLASS_ALIASES = {
		gem = Enum.ItemClass.Gem,
		gems = Enum.ItemClass.Gem,
		["珠宝"] = Enum.ItemClass.Gem,
		armor = Enum.ItemClass.Armor,
		["护甲"] = Enum.ItemClass.Armor,
		weapon = Enum.ItemClass.Weapon,
		weapons = Enum.ItemClass.Weapon,
		["武器"] = Enum.ItemClass.Weapon,
		container = Enum.ItemClass.Container,
		containers = Enum.ItemClass.Container,
		bag = Enum.ItemClass.Container,
		bags = Enum.ItemClass.Container,
		["容器"] = Enum.ItemClass.Container,
		consumable = Enum.ItemClass.Consumable,
		consumables = Enum.ItemClass.Consumable,
		["消耗品"] = Enum.ItemClass.Consumable,
		glyph = Enum.ItemClass.Glyph,
		glyphs = Enum.ItemClass.Glyph,
		["雕文"] = Enum.ItemClass.Glyph,
		tradegoods = Enum.ItemClass.Tradegoods,
		["商品"] = Enum.ItemClass.Tradegoods,
		["交易商品"] = Enum.ItemClass.Tradegoods,
		recipe = Enum.ItemClass.Recipe,
		recipes = Enum.ItemClass.Recipe,
		["配方"] = Enum.ItemClass.Recipe,
		projectile = Enum.ItemClass.Projectile,
		["弹药"] = Enum.ItemClass.Projectile,
		quiver = Enum.ItemClass.Quiver,
		["箭袋"] = Enum.ItemClass.Quiver,
		reagent = Enum.ItemClass.Reagent,
		reagents = Enum.ItemClass.Reagent,
		["材料"] = Enum.ItemClass.Reagent,
		misc = Enum.ItemClass.Miscellaneous,
		miscellaneous = Enum.ItemClass.Miscellaneous,
		["杂项"] = Enum.ItemClass.Miscellaneous,
		quest = Enum.ItemClass.Questitem,
		["任务"] = Enum.ItemClass.Questitem,
		pet = Enum.ItemClass.Battlepet,
		pets = Enum.ItemClass.Battlepet,
		["宠物"] = Enum.ItemClass.Battlepet,
	}
	for alias, cId in pairs(BUILTIN_CLASS_ALIASES) do
		private.classIdLookup[alias] = cId
	end

	for class, subClasses in pairs(private.classLookup) do
		tinsert(private.classes, class)
		private.subClasses[class] = {}
		for subClass in pairs(subClasses) do
			if subClass ~= "_index" then
				tinsert(private.subClasses[class], subClass)
			end
		end
		sort(private.subClasses[class], function(a, b) return private.classLookup[class][a] < private.classLookup[class][b] end)
	end
	sort(private.classes, function(a, b) return private.classIdLookup[strlower(a)] < private.classIdLookup[strlower(b)] end)

	for _, id in pairs(Enum.InventoryType) do
		local invType = ItemClass.GetInventorySlotInfo(id)
		if invType then
			private.inventorySlotIdLookup[strlower(invType)] = id
		end
	end

	for _, id in ipairs(ARMOR_GENERIC_INVENTORY_SLOTS) do
		tinsert(private.armorGenericInventorySlots, ItemClass.GetInventorySlotInfo(id))
	end

	for _, id in ipairs(ARMOR_INVENTORY_SLOTS) do
		tinsert(private.armorInventorySlots, ItemClass.GetInventorySlotInfo(id))
	end

	for _, subClassId in ipairs(ARMOR_SUB_CLASSES_WITH_INVENTORY_SLOTS) do
		private.armorSubClassHasInventorySlots[ItemClass.GetSubClassInfo(Enum.ItemClass.Armor, subClassId)] = true
	end
end)



-- ============================================================================
-- Module Functions
-- ============================================================================

---Gets the name of the item type.
---@return string
function ItemClass.GetClassInfo(classId)
	return C_Item.GetItemClassInfo(classId)
end

---Gets the name of the item subtype.
---@return string
function ItemClass.GetSubClassInfo(classId, subClassId)
	return C_Item.GetItemSubClassInfo(classId, subClassId)
end

---Gets the name of the item subtype.
---@return string
function ItemClass.GetInventorySlotInfo(inventorySlot)
	return C_Item.GetItemInventorySlotInfo(inventorySlot)
end

---Gets the pet class ID.
---@return number
function ItemClass.GetPetClassId()
	return Enum.ItemClass.Battlepet
end

---Gets the armor class ID.
---@return number
function ItemClass.GetArmorClassId()
	return Enum.ItemClass.Armor
end

---Gets the weapon class ID.
---@return number
function ItemClass.GetWeaponClassId()
	return Enum.ItemClass.Weapon
end

---Gets the profession class ID.
---@return number
function ItemClass.GetProfessionClassId()
	return Enum.ItemClass.Profession
end

---Gets all item class names.
---@return string[]
function ItemClass.GetClasses()
	return private.classes
end

---Gets all item sub class names.
---@param class string The class name
---@return string[]
function ItemClass.GetSubClasses(class)
	return private.subClasses[class]
end

---Gets the class ID.
---@param classStr string The class name
---@return number
function ItemClass.GetClassIdFromClassString(classStr)
	return private.classIdLookup[strlower(classStr)]
end

---Gets the sub class ID.
---@param subClass string The sub class name
---@param classId number The class ID
---@return number
function ItemClass.GetSubClassIdFromSubClassString(subClass, classId)
	if not classId or not subClass then return end
	local subLower = strlower(subClass)
	local class = ItemClass.GetClassInfo(classId)
	if private.classLookup[class] then
		for str, index in pairs(private.classLookup[class]) do
			if strlower(str) == subLower then
				return index
			end
		end
	end
	-- Fallback check against Enum.__ItemClassInfo (English / static subclass names)
	local subClassInfo = Enum.__ItemClassInfo and Enum.__ItemClassInfo[classId]
	if subClassInfo then
		for index, str in pairs(subClassInfo) do
			if type(str) == "string" and strlower(str) == subLower then
				return index
			end
		end
	end
end

---Gets the inventory slot ID by name.
---@param slot string The name
---@return number
function ItemClass.GetInventorySlotIdFromInventorySlotString(slot)
	return private.inventorySlotIdLookup[strlower(slot)]
end

---Iterates over the generic inventory slots for a given class.
---@param class string The name of the class
---@return fun(): number, string @Iterator with fields: `index`, `name`
function ItemClass.GenericInventorySlotStringIterator(class)
	if class == ItemClass.GetClassInfo(Enum.ItemClass.Armor) then
		return ipairs(private.armorGenericInventorySlots)
	else
		return ipairs(private.emptyTable)
	end
end

---Gets the list of inventory slots for the given class and subClass.
---@return string[]
function ItemClass.GetInventorySlots(class, subClass)
	if class == ItemClass.GetClassInfo(Enum.ItemClass.Armor) and private.armorSubClassHasInventorySlots[subClass] then
		return private.armorInventorySlots
	else
		return private.emptyTable
	end
end
