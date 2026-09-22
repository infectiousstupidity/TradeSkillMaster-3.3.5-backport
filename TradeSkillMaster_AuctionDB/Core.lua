-- TradeSkillMaster_AuctionDB - Local auction scan database for 3.3.5a
-- Schema v4: per-item record
--   mb, mv, na, ts           live scan fields (DBMinBuyout, DBRecent, auction count, lastScan)
--   ns                        priced-auction sample count from the latest scan
--   mkt, hist                computed DBMarket / DBHistorical (also legacy baseline during migration)
--   mktDays, histDays        accepted day coverage for the rolling windows
--   migDay                   calendar day v4 migration started (legacy influence decays from here)
--   dSum, dCnt, dDay         running accepted snapshot sum/count for current calendar day
--   snaps                    compact ring: "day:avg,..." daily snapshot averages (≤15 days)
--   mktRing                  compact ring: "day:mkt,..." daily DBMarket values (≤60 days)
--   pend, pendDay            sparse quarantine candidate snapshot

local CURRENT_VERSION = 4
local SECONDS_PER_DAY = 86400
local MARKET_WINDOW = 15
local HIST_WINDOW = 60
local LEGACY_MARKET_DAYS = 14
local LEGACY_HIST_DAYS = 60
local SPARSE_SAMPLE_MAX = 2
local EXTREME_HIGH = 5
local EXTREME_LOW = 0.2

-- Original TSM DBMarket weights for days 0..14 (today .. 14 days ago).
local MARKET_WEIGHTS = { 132, 125, 100, 75, 45, 34, 33, 38, 28, 21, 15, 10, 7, 5, 4 }



-- ============================================================================
-- Ring encoding (compact SavedVariable storage)
-- ============================================================================

local function ParseRing(str)
	local out = {}
	if type(str) ~= "string" or str == "" then
		return out
	end
	for part in string.gmatch(str, "[^,]+") do
		local day, val = string.match(part, "(%d+):(%d+)")
		day, val = tonumber(day), tonumber(val)
		if day and val and val > 0 then
			out[day] = val
		end
	end
	return out
end

local function EncodeRing(map, minDay)
	local parts = {}
	for day, val in pairs(map) do
		if (not minDay or day >= minDay) and val and val > 0 then
			parts[#parts + 1] = day .. ":" .. val
		end
	end
	table.sort(parts, function(a, b)
		return tonumber(string.match(a, "^(%d+)")) < tonumber(string.match(b, "^(%d+)"))
	end)
	return table.concat(parts, ",")
end

local function PruneRing(map, minDay, maxEntries)
	local days = {}
	for day in pairs(map) do
		if day >= minDay then
			days[#days + 1] = day
		else
			map[day] = nil
		end
	end
	table.sort(days)
	while #days > maxEntries do
		map[days[1]] = nil
		table.remove(days, 1)
	end
end

local function CountRingDays(str, minDay)
	local count = 0
	for day in pairs(ParseRing(str)) do
		if not minDay or day >= minDay then
			count = count + 1
		end
	end
	return count
end



-- ============================================================================
-- Pricing helpers
-- ============================================================================

local function CalendarDay(now)
	return math.floor((now or time()) / SECONDS_PER_DAY)
end

local function GetSnapAverage(record, day)
	local snaps = ParseRing(record.snaps)
	if snaps[day] then
		return snaps[day]
	end
	if record.dDay == day and record.dCnt and record.dCnt > 0 then
		return math.floor(record.dSum / record.dCnt + 0.5)
	end
	return nil
end

local function SetSnapAverage(record, day, avg)
	local snaps = ParseRing(record.snaps)
	snaps[day] = avg
	PruneRing(snaps, day - (MARKET_WINDOW - 1), MARKET_WINDOW)
	record.snaps = EncodeRing(snaps)
end

local function ComputeWeightedMarket(record, today)
	local snaps = ParseRing(record.snaps)
	if record.dDay == today and record.dCnt and record.dCnt > 0 then
		snaps[today] = math.floor(record.dSum / record.dCnt + 0.5)
	end

	local weightedSum, weightTotal, hasV4 = 0, 0, false
	for age = 0, MARKET_WINDOW - 1 do
		local day = today - age
		local avg = snaps[day]
		if avg and avg > 0 then
			local w = MARKET_WEIGHTS[age + 1]
			weightedSum = weightedSum + avg * w
			weightTotal = weightTotal + w
			hasV4 = true
		end
	end

	local migDay = record.migDay
	local legacyMkt = record.mkt
	if migDay and legacyMkt and legacyMkt > 0 then
		local daysSince = today - migDay
		if daysSince >= 0 and daysSince < LEGACY_MARKET_DAYS then
			local legacyWeight = MARKET_WEIGHTS[1] * (LEGACY_MARKET_DAYS - daysSince) / LEGACY_MARKET_DAYS
			if legacyWeight > 0 then
				weightedSum = weightedSum + legacyMkt * legacyWeight
				weightTotal = weightTotal + legacyWeight
			end
		end
	end

	if weightTotal > 0 then
		return math.floor(weightedSum / weightTotal + 0.5), hasV4
	end
	-- No accepted snapshots remain inside the 15-day window. A migrated legacy
	-- baseline only participates during its explicit migration grace period above;
	-- never carry an expired market value forward forever.
	return nil, false
end

local function StoreDailyMarket(record, today, mkt)
	local ring = ParseRing(record.mktRing)
	ring[today] = mkt
	PruneRing(ring, today - (HIST_WINDOW - 1), HIST_WINDOW)
	record.mktRing = EncodeRing(ring)
end

local function ComputeHistorical(record, today)
	local ring = ParseRing(record.mktRing)
	local sum, count = 0, 0
	for age = 0, HIST_WINDOW - 1 do
		local val = ring[today - age]
		if val and val > 0 then
			sum = sum + val
			count = count + 1
		end
	end

	local migDay = record.migDay
	local legacyHist = record.hist or record.mkt
	if migDay and legacyHist and legacyHist > 0 then
		local daysSince = today - migDay
		if daysSince >= 0 and daysSince < LEGACY_HIST_DAYS and count == 0 then
			return legacyHist
		end
		if daysSince >= 0 and daysSince < LEGACY_HIST_DAYS and count > 0 then
			local legacyWeight = (LEGACY_HIST_DAYS - daysSince) / LEGACY_HIST_DAYS
			if legacyWeight > 0 then
				sum = sum + legacyHist * legacyWeight
				count = count + legacyWeight
			end
		end
	end

	if count > 0 then
		return math.floor(sum / count + 0.5)
	end
	-- As with DBMarket, the legacy baseline is only valid during the bounded
	-- migration grace period above. Once the 60-day window is empty, expire it.
	return nil
end

local function GetConfirmedMarket(record, today)
	local mkt = ComputeWeightedMarket(record, today)
	return mkt
end

local function IsExtremeChange(newMv, confirmedMv)
	if not confirmedMv or confirmedMv <= 0 or not newMv or newMv <= 0 then
		return false
	end
	if newMv > confirmedMv * EXTREME_HIGH then
		return true
	end
	if newMv < confirmedMv * EXTREME_LOW then
		return true
	end
	return false
end

local function FoldDayIfNeeded(record, today)
	if record.dDay and record.dDay ~= today and record.dCnt and record.dCnt > 0 then
		local avg = math.floor(record.dSum / record.dCnt + 0.5)
		SetSnapAverage(record, record.dDay, avg)
	end
	if record.dDay ~= today then
		record.dSum, record.dCnt, record.dDay = 0, 0, today
	end
end

local function AcceptSnapshot(record, mv, today)
	FoldDayIfNeeded(record, today)
	record.dSum = (record.dSum or 0) + mv
	record.dCnt = (record.dCnt or 0) + 1
	record.dDay = today
	local dailyAvg = math.floor(record.dSum / record.dCnt + 0.5)
	SetSnapAverage(record, today, dailyAvg)
end

local function TryConfirmPending(record, nsamples, today)
	if not record.pend or not record.pendDay then
		return
	end
	if nsamples and nsamples >= 3 then
		AcceptSnapshot(record, record.pend, today)
		record.pend, record.pendDay = nil, nil
		return
	end
	if today > record.pendDay then
		AcceptSnapshot(record, record.pend, today)
		record.pend, record.pendDay = nil, nil
	end
end

local function ShouldAcceptSnapshot(record, mv, nsamples, today)
	nsamples = nsamples or 0
	if nsamples >= 3 then
		return true
	end
	if nsamples <= 0 or nsamples > SPARSE_SAMPLE_MAX then
		return false
	end

	local confirmed = GetConfirmedMarket(record, today)
	if not confirmed or confirmed <= 0 then
		record.pend = mv
		record.pendDay = today
		return false
	end
	if IsExtremeChange(mv, confirmed) then
		record.pend = mv
		record.pendDay = today
		return false
	end
	return true
end

local function RecomputeAggregates(record, today)
	local mkt = ComputeWeightedMarket(record, today)
	if mkt and mkt > 0 then
		StoreDailyMarket(record, today, mkt)
	end
	local hist = ComputeHistorical(record, today)
	-- Persist the recomputed truth, including nil when a rolling window has
	-- genuinely expired. Leaving the old value in-place would resurrect stale
	-- data the next time this item is scanned.
	record.mkt = mkt
	record.hist = hist
	record.mktDays = CountRingDays(record.snaps, today - (MARKET_WINDOW - 1))
	record.histDays = CountRingDays(record.mktRing, today - (HIST_WINDOW - 1))
	return mkt, hist
end



-- ============================================================================
-- Database bootstrap / migration
-- ============================================================================

local function EnsureRecord(record)
	if type(record) ~= "table" then
		return { mb = record }
	end
	return record
end

local function EnsureDB()
	if not TSM_AuctionDB then
		TSM_AuctionDB = { __version = CURRENT_VERSION, realms = {} }
		return
	end
	TSM_AuctionDB.realms = TSM_AuctionDB.realms or {}
	local v = TSM_AuctionDB.__version or 1
	if v < 2 then
		for _, items in pairs(TSM_AuctionDB.realms) do
			for is, val in pairs(items) do
				if type(val) == "number" then
					items[is] = { mb = val }
				end
			end
		end
		TSM_AuctionDB.__version = 2
		v = 2
	end
	if v < 3 then
		TSM_AuctionDB.__version = 3
		v = 3
	end
	if v < 4 then
		local migDay = CalendarDay()
		for _, items in pairs(TSM_AuctionDB.realms) do
			for is, val in pairs(items) do
				local record = EnsureRecord(val)
				record.migDay = record.migDay or migDay
				if record.mkt and not record.hist then
					record.hist = record.mkt
				end
				items[is] = record
			end
		end
		TSM_AuctionDB.__version = 4
	end
end

local function GetRealmKey()
	local realm = GetRealmName()
	local faction = UnitFactionGroup("player")
	return faction .. " - " .. realm
end



-- ============================================================================
-- Public API
-- ============================================================================

-- Write scan summary. Accepts {[is]={mb,mv,na,nsamples}} or legacy {[is]=N}.
function TSM_AuctionDB_RecordScan(scanData)
	if type(scanData) ~= "table" then
		return 0
	end
	EnsureDB()
	local key = GetRealmKey()
	TSM_AuctionDB.realms[key] = TSM_AuctionDB.realms[key] or {}
	local items = TSM_AuctionDB.realms[key]
	local now = time()
	local today = CalendarDay(now)
	local recorded = 0

	for is, data in pairs(scanData) do
		local mb, mv, na, nsamples
		if type(data) == "number" then
			mb = data
		elseif type(data) == "table" then
			mb = data.mb or data.minBuyout
			mv = data.mv or data.marketValue
			na = data.na or data.numAuctions
			nsamples = data.nsamples
		end

		if type(mb) == "number" and mb > 0 then
			local existing = EnsureRecord(items[is])
			existing.mb = mb
			if type(na) == "number" and na > 0 then
				existing.na = na
			end
			if type(nsamples) == "number" and nsamples >= 0 then
				existing.ns = nsamples
			end
			existing.ts = now
			existing.migDay = existing.migDay or today

			if type(mv) == "number" and mv > 0 then
				existing.mv = mv
				TryConfirmPending(existing, nsamples, today)
				if ShouldAcceptSnapshot(existing, mv, nsamples, today) then
					AcceptSnapshot(existing, mv, today)
				end
				local mkt, hist = RecomputeAggregates(existing, today)
				if type(data) == "table" then
					data.mkt = mkt or existing.mkt
					data.hist = hist or existing.hist
				end
			end

			if type(data) == "table" then
				data.ts = now
				data.scanSamples = existing.ns
				data.marketDays = existing.mktDays or 0
				data.historicalDays = existing.histDays or 0
			end
			items[is] = existing
			recorded = recorded + 1
		end
	end
	return recorded
end

-- Read all data for current realm-faction.
function TSM_AuctionDB_GetRealmData()
	EnsureDB()
	local key = GetRealmKey()
	return TSM_AuctionDB.realms[key] or {}
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
	if name == "TradeSkillMaster_AuctionDB" then
		EnsureDB()
		f:UnregisterEvent("ADDON_LOADED")
	end
end)

_G.TSM_AuctionDB_RecordScan = TSM_AuctionDB_RecordScan
_G.TSM_AuctionDB_GetRealmData = TSM_AuctionDB_GetRealmData
