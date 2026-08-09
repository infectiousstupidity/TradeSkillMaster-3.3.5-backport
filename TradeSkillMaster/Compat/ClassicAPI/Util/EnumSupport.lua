if __TSM_ClassicAPI_SKIP then return end
local Enum = Enum

-- These are used by internal functions, etc.
-- TODO: Certain strings need to be localized.
-- TODO: Certain locale tables have outdated information.

local ItemConsumableSubclassLocale = {
	[Enum.ItemConsumableSubclass.Generic] = "Explosives and Devices",
	[Enum.ItemConsumableSubclass.Potion] = "Potion",
	[Enum.ItemConsumableSubclass.Elixir] = "Elixir",
	[Enum.ItemConsumableSubclass.Scroll] = "Scroll (OBSOLETE)",
	[Enum.ItemConsumableSubclass.Fooddrink] = "Food & Drink",
	[Enum.ItemConsumableSubclass.Itemenhancement] = "Item Enhancement (OBSOLETE)",
	[Enum.ItemConsumableSubclass.Bandage] = "Bandage",
	[Enum.ItemConsumableSubclass.Other] = "Other",
}

local ItemContainerSubclassLocale = {
	"Bag",
	"Soul Bag",
	"Herb Bag",
	"Enchanting Bag",
	"Engineering Bag",
	"Gem Bag",
	"Mining Bag",
	"Leatherworking Bag",
	"Inscription Bag",
	"Tackle Box",
	"Cooking Bag",
}

local ItemProjectileSubclassLocale = {
	"Wand(OBSOLETE)",
	"Bolt(OBSOLETE)",
	"Arrow",
	"Bullet",
	"Thrown(OBSOLETE)",
}

local ItemTradegoodsSubclassLocale = {
	"Trade Goods (OBSOLETE)",
	"Parts",
	"Explosives (OBSOLETE)",
	"Devices (OBSOLETE)",
	"Jewelcrafting",
	"Cloth",
	"Leather",
	"Metal & Stone",
	"Cooking",
	"Herb",
	"Elemental",
	"Other",
	"Enchanting",
	"Materials (OBSOLETE)",
	"Item Enchantment (OBSOLETE)",
	"Weapon Enchantment (OBSOLETE)",
	"Inscription",
	"Explosives and Devices (OBSOLETE)",
}

local ItemQuiverSubclassLocale = {
	"Quiver(OBSOLETE)",
	"Bolt(OBSOLETE)",
	"Quiver",
	"Ammo Pouch",
}

local ItemQuestitemSubclassLocale = {
	"Quest",
}

local ItemGlyphSubclassLocale = {
	"Warrior",
	"Paladin",
	"Hunter",
	"Rogue",
	"Priest",
	"Death Knight",
	"Shaman",
	"Mage",
	"Warlock",
	"Monk",
	"Druid",
	"Demon Hunter",
}

local ItemWeaponSubclassLocale = {
	[Enum.ItemWeaponSubclass.Axe1H] = "One-Handed Axes",
	[Enum.ItemWeaponSubclass.Axe2H] = "Two-Handed Axes",
	[Enum.ItemWeaponSubclass.Bows] = "Bows",
	[Enum.ItemWeaponSubclass.Guns] = "Guns",
	[Enum.ItemWeaponSubclass.Mace1H] = "One-Handed Maces",
	[Enum.ItemWeaponSubclass.Mace2H] = "Two-Handed Maces",
	[Enum.ItemWeaponSubclass.Polearm] = "Polearms",
	[Enum.ItemWeaponSubclass.Sword1H] = "One-Handed Swords",
	[Enum.ItemWeaponSubclass.Sword2H] = "Two-Handed Swords",
	[Enum.ItemWeaponSubclass.Warglaive] = "Warglaives",
	[Enum.ItemWeaponSubclass.Staff] = "Staves",
	[Enum.ItemWeaponSubclass.Bearclaw] = "Bear Claws",
	[Enum.ItemWeaponSubclass.Catclaw] = "CatClaws",
	[Enum.ItemWeaponSubclass.Unarmed] = "Fist Weapons",
	[Enum.ItemWeaponSubclass.Generic] = "Miscellaneous",
	[Enum.ItemWeaponSubclass.Dagger] = "Daggers",
	[Enum.ItemWeaponSubclass.Thrown] = "Thrown",
	[Enum.ItemWeaponSubclass.Obsolete3] = "Spears",
	[Enum.ItemWeaponSubclass.Crossbow] = "Crossbows",
	[Enum.ItemWeaponSubclass.Wand] = "Wands",
	[Enum.ItemWeaponSubclass.Fishingpole] = "Fishing Poles",
}

local ItemGemSubclassLocale = {
	[Enum.ItemGemSubclass.Red] = "Red",
	[Enum.ItemGemSubclass.Blue] = "Blue",
	[Enum.ItemGemSubclass.Yellow] = "Yellow",
	[Enum.ItemGemSubclass.Purple] = "Purple",
	[Enum.ItemGemSubclass.Green] = "Green",
	[Enum.ItemGemSubclass.Orange] = "Orange",
	[Enum.ItemGemSubclass.Meta] = "Meta",
	[Enum.ItemGemSubclass.Simple] = "Simple",
	[Enum.ItemGemSubclass.Prismatic] = "Prismatic",
}

local ItemArmorSubclassLocale = {
	[Enum.ItemArmorSubclass.Generic] = "Miscellaneous",
	[Enum.ItemArmorSubclass.Cloth] = "Cloth",
	[Enum.ItemArmorSubclass.Leather] = "Leather",
	[Enum.ItemArmorSubclass.Mail] = "Mail",
	[Enum.ItemArmorSubclass.Plate] = "Plate",
	[Enum.ItemArmorSubclass.Cosmetic] = "Cosmetic",
	[Enum.ItemArmorSubclass.Shield] = "Shields",
	[Enum.ItemArmorSubclass.Libram] = "Librams",
	[Enum.ItemArmorSubclass.Idol] = "Idols",
	[Enum.ItemArmorSubclass.Totem] = "Totems",
	[Enum.ItemArmorSubclass.Sigil] = "Sigils",
	[Enum.ItemArmorSubclass.Relic] = "Relic",
}

local ItemReagentSubclassLocale = {
	[Enum.ItemReagentSubclass.Reagent] = "Reagent",
	[Enum.ItemReagentSubclass.Keystone] = "Keystone",
	[Enum.ItemReagentSubclass.ContextToken] = "Context Token",
}

local ItemRecipeSubclassLocale = {
	[Enum.ItemRecipeSubclass.Book] = "Book",
	[Enum.ItemRecipeSubclass.Leatherworking] = "Leatherworking",
	[Enum.ItemRecipeSubclass.Tailoring] = "Tailoring",
	[Enum.ItemRecipeSubclass.Engineering] = "Engineering",
	[Enum.ItemRecipeSubclass.Blacksmithing] = "Blacksmithing",
	[Enum.ItemRecipeSubclass.Cooking] = "Cooking",
	[Enum.ItemRecipeSubclass.Alchemy] = "Alchemy",
	[Enum.ItemRecipeSubclass.FirstAid] = "First Aid",
	[Enum.ItemRecipeSubclass.Enchanting] = "Enchanting",
	[Enum.ItemRecipeSubclass.Fishing] = "Fishing",
	[Enum.ItemRecipeSubclass.Jewelcrafting] = "Jewelcrafting",
	[Enum.ItemRecipeSubclass.Inscription] = "Inscription",
}

local ItemMiscellaneousSubclassLocale = {
	[Enum.ItemMiscellaneousSubclass.Junk] = "Junk",
	[Enum.ItemMiscellaneousSubclass.Reagent] = "Reagent",
	[Enum.ItemMiscellaneousSubclass.CompanionPet] = "Companion Pets",
	[Enum.ItemMiscellaneousSubclass.Holiday] = "Holiday",
	[Enum.ItemMiscellaneousSubclass.Other] = "Other",
	[Enum.ItemMiscellaneousSubclass.Mount] = "Mount",
	[Enum.ItemMiscellaneousSubclass.MountEquipment] = "Mount Equipment",
}

local BattlePetTypesLocale = {
	[Enum.BattlePetTypes.Humanoid] = "Humanoid",
	[Enum.BattlePetTypes.Dragonkin] = "Dragonkin",
	[Enum.BattlePetTypes.Flying] = "Flying",
	[Enum.BattlePetTypes.Undead] = "Undead",
	[Enum.BattlePetTypes.Critter] = "Critter",
	[Enum.BattlePetTypes.Magic] = "Magic",
	[Enum.BattlePetTypes.Elemental] = "Elemental",
	[Enum.BattlePetTypes.Beast] = "Beast",
	[Enum.BattlePetTypes.Aquatic] = "Aquatic",
	[Enum.BattlePetTypes.Mechanical] = "Mechanical",
	[Enum.BattlePetTypes.NonCombat] = "Non-Combat",
}

local ItemProfessionSubclassLocale = {
	[Enum.ItemProfessionSubclass.Blacksmithing] = "Blacksmithing",
	[Enum.ItemProfessionSubclass.Leatherworking] = "Leatherworking",
	[Enum.ItemProfessionSubclass.Alchemy] = "Alchemy",
	[Enum.ItemProfessionSubclass.Herbalism] = "Herbalism",
	[Enum.ItemProfessionSubclass.Cooking] = "Cooking",
	[Enum.ItemProfessionSubclass.Mining] = "Mining",
	[Enum.ItemProfessionSubclass.Tailoring] = "Tailoring",
	[Enum.ItemProfessionSubclass.Engineering] = "Engineering",
	[Enum.ItemProfessionSubclass.Enchanting] = "Enchanting",
	[Enum.ItemProfessionSubclass.Fishing] = "Fishing",
	[Enum.ItemProfessionSubclass.Skinning] = "Skinning",
	[Enum.ItemProfessionSubclass.Jewelcrafting] = "Jewelcrafting",
	[Enum.ItemProfessionSubclass.Inscription] = "Inscription",
	[Enum.ItemProfessionSubclass.Archaeology] = "Archaeology",
}

local ItemConsumableSubclassLocale_zhCN = {
	[Enum.ItemConsumableSubclass.Generic] = "爆炸物和装置",
	[Enum.ItemConsumableSubclass.Potion] = "药水",
	[Enum.ItemConsumableSubclass.Elixir] = "药剂",
	[Enum.ItemConsumableSubclass.Scroll] = "卷轴",
	[Enum.ItemConsumableSubclass.Fooddrink] = "食物和饮料",
	[Enum.ItemConsumableSubclass.Itemenhancement] = "物品强化",
	[Enum.ItemConsumableSubclass.Bandage] = "绷带",
	[Enum.ItemConsumableSubclass.Other] = "其他",
}

local ItemContainerSubclassLocale_zhCN = {
	"容器",
	"灵魂袋",
	"草药袋",
	"附魔材料袋",
	"工程学材料袋",
	"宝石袋",
	"矿石袋",
	"制皮材料袋",
	"铭文材料袋",
	"钓鱼宝箱",
	"烹饪袋",
}

local ItemProjectileSubclassLocale_zhCN = {
	"魔杖",
	"箭",
	"子弹",
	"投掷武器",
}

local ItemTradegoodsSubclassLocale_zhCN = {
	"商品",
	"零件",
	"炸药",
	"装置",
	"珠宝加工",
	"布料",
	"皮革",
	"金属与石头",
	"烹饪",
	"草药",
	"元素",
	"其他",
	"附魔",
	"材料",
	"护甲附魔",
	"武器附魔",
	"铭文",
}

local ItemQuiverSubclassLocale_zhCN = {
	"箭袋",
	"箭袋",
	"弹药包",
}

local ItemQuestitemSubclassLocale_zhCN = {
	"任务",
}

local ItemGlyphSubclassLocale_zhCN = {
	"战士",
	"圣骑士",
	"猎人",
	"潜行者",
	"牧师",
	"死亡骑士",
	"萨满祭司",
	"法师",
	"术士",
	"武僧",
	"德鲁伊",
	"恶魔猎手",
}

local ItemWeaponSubclassLocale_zhCN = {
	[Enum.ItemWeaponSubclass.Axe1H] = "单手斧",
	[Enum.ItemWeaponSubclass.Axe2H] = "双手斧",
	[Enum.ItemWeaponSubclass.Bows] = "弓",
	[Enum.ItemWeaponSubclass.Guns] = "枪械",
	[Enum.ItemWeaponSubclass.Mace1H] = "单手锤",
	[Enum.ItemWeaponSubclass.Mace2H] = "双手锤",
	[Enum.ItemWeaponSubclass.Polearm] = "长柄武器",
	[Enum.ItemWeaponSubclass.Sword1H] = "单手剑",
	[Enum.ItemWeaponSubclass.Sword2H] = "双手剑",
	[Enum.ItemWeaponSubclass.Warglaive] = "战刃",
	[Enum.ItemWeaponSubclass.Staff] = "法杖",
	[Enum.ItemWeaponSubclass.Bearclaw] = "熊爪",
	[Enum.ItemWeaponSubclass.Catclaw] = "猫爪",
	[Enum.ItemWeaponSubclass.Unarmed] = "拳套",
	[Enum.ItemWeaponSubclass.Generic] = "杂项",
	[Enum.ItemWeaponSubclass.Dagger] = "匕首",
	[Enum.ItemWeaponSubclass.Thrown] = "投掷武器",
	[Enum.ItemWeaponSubclass.Crossbow] = "弩",
	[Enum.ItemWeaponSubclass.Wand] = "魔杖",
	[Enum.ItemWeaponSubclass.Fishingpole] = "钓鱼竿",
}

local ItemGemSubclassLocale_zhCN = {
	[Enum.ItemGemSubclass.Red] = "红色",
	[Enum.ItemGemSubclass.Blue] = "蓝色",
	[Enum.ItemGemSubclass.Yellow] = "黄色",
	[Enum.ItemGemSubclass.Purple] = "紫色",
	[Enum.ItemGemSubclass.Green] = "绿色",
	[Enum.ItemGemSubclass.Orange] = "橙色",
	[Enum.ItemGemSubclass.Meta] = "多彩",
	[Enum.ItemGemSubclass.Simple] = "简单",
	[Enum.ItemGemSubclass.Prismatic] = "棱彩",
}

local ItemArmorSubclassLocale_zhCN = {
	[Enum.ItemArmorSubclass.Generic] = "杂项",
	[Enum.ItemArmorSubclass.Cloth] = "布甲",
	[Enum.ItemArmorSubclass.Leather] = "皮甲",
	[Enum.ItemArmorSubclass.Mail] = "锁甲",
	[Enum.ItemArmorSubclass.Plate] = "板甲",
	[Enum.ItemArmorSubclass.Cosmetic] = "装饰品",
	[Enum.ItemArmorSubclass.Shield] = "盾牌",
	[Enum.ItemArmorSubclass.Libram] = "圣契",
	[Enum.ItemArmorSubclass.Idol] = "神像",
	[Enum.ItemArmorSubclass.Totem] = "图腾",
	[Enum.ItemArmorSubclass.Sigil] = "魔印",
	[Enum.ItemArmorSubclass.Relic] = "圣物",
}

local ItemReagentSubclassLocale_zhCN = {
	[Enum.ItemReagentSubclass.Reagent] = "材料",
	[Enum.ItemReagentSubclass.Keystone] = "钥石",
	[Enum.ItemReagentSubclass.ContextToken] = "兑换物",
}

local ItemRecipeSubclassLocale_zhCN = {
	[Enum.ItemRecipeSubclass.Book] = "书籍",
	[Enum.ItemRecipeSubclass.Leatherworking] = "制皮",
	[Enum.ItemRecipeSubclass.Tailoring] = "裁缝",
	[Enum.ItemRecipeSubclass.Engineering] = "工程学",
	[Enum.ItemRecipeSubclass.Blacksmithing] = "锻造",
	[Enum.ItemRecipeSubclass.Cooking] = "烹饪",
	[Enum.ItemRecipeSubclass.Alchemy] = "炼金术",
	[Enum.ItemRecipeSubclass.FirstAid] = "急救",
	[Enum.ItemRecipeSubclass.Enchanting] = "附魔",
	[Enum.ItemRecipeSubclass.Fishing] = "钓鱼",
	[Enum.ItemRecipeSubclass.Jewelcrafting] = "珠宝加工",
	[Enum.ItemRecipeSubclass.Inscription] = "铭文",
}

local ItemMiscellaneousSubclassLocale_zhCN = {
	[Enum.ItemMiscellaneousSubclass.Junk] = "垃圾",
	[Enum.ItemMiscellaneousSubclass.Reagent] = "材料",
	[Enum.ItemMiscellaneousSubclass.CompanionPet] = "宠物",
	[Enum.ItemMiscellaneousSubclass.Holiday] = "节日",
	[Enum.ItemMiscellaneousSubclass.Other] = "其他",
	[Enum.ItemMiscellaneousSubclass.Mount] = "坐骑",
	[Enum.ItemMiscellaneousSubclass.MountEquipment] = "坐骑装备",
}

local BattlePetTypesLocale_zhCN = {
	[Enum.BattlePetTypes.Humanoid] = "人型",
	[Enum.BattlePetTypes.Dragonkin] = "龙类",
	[Enum.BattlePetTypes.Flying] = "飞行",
	[Enum.BattlePetTypes.Undead] = "亡灵",
	[Enum.BattlePetTypes.Critter] = "小动物",
	[Enum.BattlePetTypes.Magic] = "魔法",
	[Enum.BattlePetTypes.Elemental] = "元素",
	[Enum.BattlePetTypes.Beast] = "野兽",
	[Enum.BattlePetTypes.Aquatic] = "水栖",
	[Enum.BattlePetTypes.Mechanical] = "机械",
}

local ItemProfessionSubclassLocale_zhCN = {
	[Enum.ItemProfessionSubclass.Blacksmithing] = "锻造",
	[Enum.ItemProfessionSubclass.Leatherworking] = "制皮",
	[Enum.ItemProfessionSubclass.Alchemy] = "炼金术",
	[Enum.ItemProfessionSubclass.Herbalism] = "草药学",
	[Enum.ItemProfessionSubclass.Cooking] = "烹饪",
	[Enum.ItemProfessionSubclass.Mining] = "采矿",
	[Enum.ItemProfessionSubclass.Tailoring] = "裁缝",
	[Enum.ItemProfessionSubclass.Engineering] = "工程学",
	[Enum.ItemProfessionSubclass.Enchanting] = "附魔",
	[Enum.ItemProfessionSubclass.Fishing] = "钓鱼",
	[Enum.ItemProfessionSubclass.Skinning] = "剥皮",
	[Enum.ItemProfessionSubclass.Jewelcrafting] = "珠宝加工",
	[Enum.ItemProfessionSubclass.Inscription] = "铭文",
	[Enum.ItemProfessionSubclass.Archaeology] = "考古学",
}

local isZh = GetLocale and (GetLocale() == "zhCN" or GetLocale() == "zhTW")

Enum.__ItemClassInfo = {
	[Enum.ItemClass.Consumable] = isZh and ItemConsumableSubclassLocale_zhCN or ItemConsumableSubclassLocale,
	[Enum.ItemClass.Container] = isZh and ItemContainerSubclassLocale_zhCN or ItemContainerSubclassLocale,
	[Enum.ItemClass.Weapon] = isZh and ItemWeaponSubclassLocale_zhCN or ItemWeaponSubclassLocale,
	[Enum.ItemClass.Gem] = isZh and ItemGemSubclassLocale_zhCN or ItemGemSubclassLocale,
	[Enum.ItemClass.Armor] = isZh and ItemArmorSubclassLocale_zhCN or ItemArmorSubclassLocale,
	[Enum.ItemClass.Reagent] = isZh and ItemReagentSubclassLocale_zhCN or ItemReagentSubclassLocale,
	[Enum.ItemClass.Projectile] = isZh and ItemProjectileSubclassLocale_zhCN or ItemProjectileSubclassLocale,
	[Enum.ItemClass.Tradegoods] = isZh and ItemTradegoodsSubclassLocale_zhCN or ItemTradegoodsSubclassLocale,
	[Enum.ItemClass.Recipe] = isZh and ItemRecipeSubclassLocale_zhCN or ItemRecipeSubclassLocale,
	[Enum.ItemClass.Quiver] = isZh and ItemQuiverSubclassLocale_zhCN or ItemQuiverSubclassLocale,
	[Enum.ItemClass.Questitem] = isZh and ItemQuestitemSubclassLocale_zhCN or ItemQuestitemSubclassLocale,
	[Enum.ItemClass.Miscellaneous] = isZh and ItemMiscellaneousSubclassLocale_zhCN or ItemMiscellaneousSubclassLocale,
	[Enum.ItemClass.Glyph] = isZh and ItemGlyphSubclassLocale_zhCN or ItemGlyphSubclassLocale,
	[Enum.ItemClass.Battlepet] = isZh and BattlePetTypesLocale_zhCN or BattlePetTypesLocale,
	[Enum.ItemClass.Profession] = isZh and ItemProfessionSubclassLocale_zhCN or ItemProfessionSubclassLocale,
}

Enum.__InventoryTypeInfo = {
	[Enum.InventoryType.IndexNonEquipType] = INVTYPE_NON_EQUIP or "Non-equippable",
	[Enum.InventoryType.IndexHeadType] = INVTYPE_HEAD or "Head",
	[Enum.InventoryType.IndexNeckType] = INVTYPE_NECK or "Neck",
	[Enum.InventoryType.IndexShoulderType] = INVTYPE_SHOULDER or "Shoulder",
	[Enum.InventoryType.IndexBodyType] = INVTYPE_BODY or "Shirt",
	[Enum.InventoryType.IndexChestType] = INVTYPE_CHEST or "Chest",
	[Enum.InventoryType.IndexWaistType] = INVTYPE_WAIST or "Waist",
	[Enum.InventoryType.IndexLegsType] = INVTYPE_LEGS or "Legs",
	[Enum.InventoryType.IndexFeetType] = INVTYPE_FEET or "Feet",
	[Enum.InventoryType.IndexWristType] = INVTYPE_WRIST or "Wrist",
	[Enum.InventoryType.IndexHandType] = INVTYPE_HAND or "Hands",
	[Enum.InventoryType.IndexFingerType] = INVTYPE_FINGER or "Finger",
	[Enum.InventoryType.IndexTrinketType] = INVTYPE_TRINKET or "Trinket",
	[Enum.InventoryType.IndexWeaponType] = INVTYPE_WEAPON or "One-Hand",
	[Enum.InventoryType.IndexShieldType] = INVTYPE_SHIELD or "Off Hand",
	[Enum.InventoryType.IndexRangedType] = INVTYPE_RANGED or "Ranged",
	[Enum.InventoryType.IndexCloakType] = INVTYPE_CLOAK or "Back",
	[Enum.InventoryType.Index2HweaponType] = INVTYPE_2HWEAPON or "Two-Hand",
	[Enum.InventoryType.IndexBagType] = INVTYPE_BAG or "Bag",
	[Enum.InventoryType.IndexTabardType] = INVTYPE_TABARD or "Tabard",
	[Enum.InventoryType.IndexRobeType] = INVTYPE_ROBE or "Chest",
	[Enum.InventoryType.IndexWeaponmainhandType] = INVTYPE_WEAPONMAINHAND or "Main Hand",
	[Enum.InventoryType.IndexWeaponoffhandType] = INVTYPE_WEAPONOFFHAND or "Off Hand",
	[Enum.InventoryType.IndexHoldableType] = INVTYPE_HOLDABLE or "Held In Off-hand",
	[Enum.InventoryType.IndexAmmoType] = INVTYPE_AMMO or "Ammo",
	[Enum.InventoryType.IndexThrownType] = INVTYPE_THROWN or "Thrown",
	[Enum.InventoryType.IndexRangedrightType] = INVTYPE_RANGEDRIGHT or "Ranged",
	[Enum.InventoryType.IndexQuiverType] = INVTYPE_QUIVER or "Quiver",
	[Enum.InventoryType.IndexRelicType] = INVTYPE_RELIC or "Relic",
	[Enum.InventoryType.IndexProfessionToolType] = INVTYPE_PROFESSION_TOOL or "Profession Tool",
	[Enum.InventoryType.IndexProfessionGearType] = INVTYPE_PROFESSION_GEAR or "Profession Equipment",
	[Enum.InventoryType.IndexEquipablespellOffensiveType] = INVTYPE_EQUIPABLESPELL_OFFENSIVE or "Equipable Spell - Offensive",
	[Enum.InventoryType.IndexEquipablespellUtilityType] = INVTYPE_EQUIPABLESPELL_UTILITY or "Equipable Spell - Utility",
	[Enum.InventoryType.IndexEquipablespellDefensiveType] = INVTYPE_EQUIPABLESPELL_DEFENSIVE or "Equipable Spell - Defensive",
	[Enum.InventoryType.IndexEquipablespellWeaponType] = INVTYPE_EQUIPABLESPELL_WEAPON or "Equipable Spell - Weapon",
}

Enum.__InventoryTypeIndex = {
	INVTYPE_NON_EQUIP = Enum.InventoryType.IndexNonEquipType,
	INVTYPE_HEAD = Enum.InventoryType.IndexHeadType,
	INVTYPE_NECK = Enum.InventoryType.IndexNeckType,
	INVTYPE_SHOULDER = Enum.InventoryType.IndexShoulderType,
	INVTYPE_BODY = Enum.InventoryType.IndexBodyType,
	INVTYPE_CHEST = Enum.InventoryType.IndexChestType,
	INVTYPE_WAIST = Enum.InventoryType.IndexWaistType,
	INVTYPE_LEGS = Enum.InventoryType.IndexLegsType,
	INVTYPE_FEET = Enum.InventoryType.IndexFeetType,
	INVTYPE_WRIST = Enum.InventoryType.IndexWristType,
	INVTYPE_HAND = Enum.InventoryType.IndexHandType,
	INVTYPE_FINGER = Enum.InventoryType.IndexFingerType,
	INVTYPE_TRINKET = Enum.InventoryType.IndexTrinketType,
	INVTYPE_WEAPON = Enum.InventoryType.IndexWeaponType,
	INVTYPE_SHIELD = Enum.InventoryType.IndexShieldType,
	INVTYPE_RANGED = Enum.InventoryType.IndexRangedType,
	INVTYPE_CLOAK = Enum.InventoryType.IndexCloakType,
	INVTYPE_2HWEAPON = Enum.InventoryType.Index2HweaponType,
	INVTYPE_BAG = Enum.InventoryType.IndexBagType,
	INVTYPE_TABARD = Enum.InventoryType.IndexTabardType,
	INVTYPE_ROBE = Enum.InventoryType.IndexRobeType,
	INVTYPE_WEAPONMAINHAND = Enum.InventoryType.IndexWeaponmainhandType,
	INVTYPE_WEAPONOFFHAND = Enum.InventoryType.IndexWeaponoffhandType,
	INVTYPE_HOLDABLE = Enum.InventoryType.IndexHoldableType,
	INVTYPE_AMMO = Enum.InventoryType.IndexAmmoType,
	INVTYPE_THROWN = Enum.InventoryType.IndexThrownType,
	INVTYPE_RANGEDRIGHT = Enum.InventoryType.IndexRangedrightType,
	INVTYPE_QUIVER = Enum.InventoryType.IndexQuiverType,
	INVTYPE_RELIC = Enum.InventoryType.IndexRelicType,
	INVTYPE_PROFESSION_TOOL = Enum.InventoryType.IndexProfessionToolType,
	INVTYPE_PROFESSION_GEAR = Enum.InventoryType.IndexProfessionGearType,
	INVTYPE_EQUIPABLESPELL_OFFENSIVE = Enum.InventoryType.IndexEquipablespellOffensiveType,
	INVTYPE_EQUIPABLESPELL_UTILITY = Enum.InventoryType.IndexEquipablespellUtilityType,
	INVTYPE_EQUIPABLESPELL_DEFENSIVE = Enum.InventoryType.IndexEquipablespellDefensiveType,
	INVTYPE_EQUIPABLESPELL_WEAPON = Enum.InventoryType.IndexEquipablespellWeaponType,
}