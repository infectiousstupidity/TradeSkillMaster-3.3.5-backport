-- Regression coverage for the DBMarket availability regression introduced by
-- 3b66cb00. Auctioning validates operation prices before it scans, so the public
-- DBMarket source must retain a last-known market value between scans. Live /
-- trust-sensitive sources remain age-gated.

local NOW = 2000000000

max = math.max
time = function()
	return NOW
end

local AuctionDB = {}
local CustomString = {
	InvalidateCache = function() end,
}
local ItemString = {
	Get = function(itemString)
		return itemString
	end,
	ToLevel = function(itemString)
		return itemString
	end,
	GetBaseFast = function(itemString)
		return itemString
	end,
}

local function IncludeUtil(name)
	if name == "Util.Log" then
		return { Info = function() end }
	elseif name == "Lua.Table" then
		return {}
	elseif name == "BaseType.TempTable" then
		return {}
	end
	return {}
end

local TSM = {
	Locale = {
		GetTable = function()
			return {}
		end,
	},
	LibTSMUtil = {
		Include = function(_, name)
			return IncludeUtil(name)
		end,
	},
	LibTSMService = {
		Include = function()
			return {}
		end,
	},
	LibTSMTypes = {
		Include = function(_, name)
			if name == "Item.ItemString" then
				return ItemString
			elseif name == "CustomString" then
				return CustomString
			end
			return {}
		end,
	},
	LibTSMApp = {
		Include = function()
			return {}
		end,
	},
	LibTSMWoW = {
		IncludeClassType = function()
			return {}
		end,
	},
}
function TSM:NewPackage(name)
	assert(name == "AuctionDB")
	return AuctionDB
end

local chunk = assert(loadfile("TradeSkillMaster/Core/Service/AuctionDB/Core.lua"))
chunk("TradeSkillMaster", TSM)

local function assertEqual(actual, expected, label)
	assert(actual == expected, label..": expected "..tostring(expected)..", got "..tostring(actual))
end

-- Sparse item: no established rolling market and the latest scan is older than
-- DBRecent's 12-hour live window. DBRecent stays nil, but compatibility DBMarket
-- must retain the last robust scan value just as it did before 3b66cb00.
AuctionDB.RecordLocalScanResults({
	["i:38934"] = {
		mb = 100,
		mv = 200,
		na = 1,
		ts = NOW - 13 * 60 * 60,
	},
})
assertEqual(AuctionDB.GetRealmItemData("i:38934", "marketValueRecent"), nil, "stale DBRecent")
assertEqual(AuctionDB.GetMarketOrRecentValue("i:38934"), 200, "sparse DBMarket compatibility")
assertEqual(AuctionDB.GetAdaptiveMarketValue("i:38934"), nil, "adaptive source remains trust constrained")

-- Established market older than the 15-day live gate: compatibility DBMarket
-- prefers the stored rolling market rather than degrading to the raw snapshot.
AuctionDB.RecordLocalScanResults({
	["i:38935"] = {
		mb = 100,
		mv = 200,
		mkt = 150,
		na = 1,
		ts = NOW - 16 * 24 * 60 * 60,
	},
})
assertEqual(AuctionDB.GetRealmItemData("i:38935", "marketValue"), nil, "stale live DBMarket field")
assertEqual(AuctionDB.GetMarketOrRecentValue("i:38935"), 150, "stored rolling DBMarket compatibility")
assertEqual(AuctionDB.GetAdaptiveMarketValue("i:38935"), nil, "stale adaptive source remains unavailable")

-- Fresh established data still prefers the rolling market value.
AuctionDB.RecordLocalScanResults({
	["i:38936"] = {
		mb = 100,
		mv = 200,
		mkt = 175,
		na = 1,
		ts = NOW,
	},
})
assertEqual(AuctionDB.GetMarketOrRecentValue("i:38936"), 175, "fresh rolling market preferred")

print("OK: AuctionDB DBMarket compatibility")
