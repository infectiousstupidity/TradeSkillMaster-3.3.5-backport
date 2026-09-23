-- Regression coverage for the v136 default material cost migration.
-- This loads the real AddonSettings implementation with only the small set of
-- WoW / TSM services needed to exercise a v135 -> v136 settings upgrade.

strlower = string.lower
gsub = string.gsub
tinsert = table.insert

function wipe(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
end

local OLD_DEFAULT = "min(dbmarket, crafting, vendorbuy, convert(dbmarket))"
local NEW_DEFAULT = "min(dbmarketrecent, crafting, vendorbuy, convert(dbmarketrecent))"
local oldValue = nil
local migratedValue = nil

local SessionInfo = {
	GetRealmName = function() return "Test Realm" end,
	GetFactionName = function() return "Alliance" end,
	GetCharacterName = function() return "Test Character" end,
}
local Settings = {}
local Schema = {
	Get = function() return {} end,
}
local Log = {
	Warn = function() end,
}
local RealmInfo = {}
function RealmInfo:GetRealmInfo()
	return 1
end

function LibStub(name)
	assert(name == "LibRealmInfo")
	return RealmInfo
end

function Settings.NewDB()
	migratedValue = NEW_DEFAULT

	local db = {}
	function db:Set(scope, scopeKey, namespace, key, value)
		assert(scope == "global")
		assert(scopeKey == "GLOBAL")
		assert(namespace == "craftingOptions")
		assert(key == "defaultMatCostMethod")
		migratedValue = value
	end

	local upgrade = {}
	function upgrade:GetPrevVersion()
		return 135
	end
	function upgrade:RemovedSettingIterator(scope, scopeKey, namespace, key)
		assert(scope == "global")
		assert(scopeKey == nil)
		assert(namespace == "craftingOptions")
		assert(key == "defaultMatCostMethod")
		local yielded = false
		return function()
			if yielded then
				return
			end
			yielded = true
			return 1, "global@GLOBAL@craftingOptions@defaultMatCostMethod", oldValue
		end
	end
	function upgrade:GetScopeKey()
		return "GLOBAL"
	end

	return db, upgrade
end

local AddonSettings = {}
local LibTSMApp = {
	Locale = {
		GetTable = function() return {} end,
	},
	IsRetail = function() return false end,
	IsPandaClassic = function() return false end,
}
function LibTSMApp:Init(name)
	assert(name == "Service.AddonSettings")
	return AddonSettings
end
function LibTSMApp:From(packageName)
	return {
		Include = function(_, moduleName)
			if packageName == "LibTSMWoW" and moduleName == "Util.SessionInfo" then
				return SessionInfo
			elseif packageName == "LibTSMTypes" and moduleName == "Settings" then
				return Settings
			elseif packageName == "LibTSMSystem" and moduleName == "AddonSettings.Schema" then
				return Schema
			elseif packageName == "LibTSMUtil" and moduleName == "Util.Log" then
				return Log
			end
			return {}
		end,
		IncludeClassType = function()
			return {}
		end,
	}
end

local chunk = assert(loadfile("TradeSkillMaster/LibTSMApp/Source/Service/AddonSettings.lua"))
chunk("TradeSkillMaster", { LibTSMApp = LibTSMApp })

local function check(name, input, expected)
	oldValue = input
	migratedValue = nil
	AddonSettings.LoadDB()
	assert(
		migratedValue == expected,
		name..": expected "..expected..", got "..tostring(migratedValue)
	)
end

check("stock default", OLD_DEFAULT, NEW_DEFAULT)
check(
	"stock default with case and whitespace differences",
	"  MIN ( DBMARKET,\tCRAFTING, VENDORBUY,\nCONVERT(DBMARKET) )  ",
	NEW_DEFAULT
)
check("custom source", "dbhistorical", "dbhistorical")
check(
	"custom expression preserved exactly",
	"first(DBMinBuyout, dbmarket * 0.90)",
	"first(DBMinBuyout, dbmarket * 0.90)"
)

print("OK: v136 default material cost migration")
