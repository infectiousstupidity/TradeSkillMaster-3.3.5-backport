-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local TSM = select(2, ...) ---@type TSM
local DisenchantSearch = TSM.Shopping:NewPackage("DisenchantSearch") ---@type AddonPackage
local CustomString = TSM.LibTSMTypes:Include("CustomString")
local L = TSM.Locale.GetTable()
local ChatMessage = TSM.LibTSMService:Include("UI.ChatMessage")
local Threading = TSM.LibTSMTypes:Include("Threading")
local ItemInfo = TSM.LibTSMService:Include("Item.ItemInfo")
local ItemString = TSM.LibTSMTypes:Include("Item.ItemString")
local ClientInfo = TSM.LibTSMWoW:Include("Util.ClientInfo")
local AuctionHouse = TSM.LibTSMWoW:Include("API.AuctionHouse")
local Event = TSM.LibTSMWoW:Include("Service.Event")
local DefaultUI = TSM.LibTSMWoW:Include("UI.DefaultUI")
local AuctionSearchContext = TSM.LibTSMService:IncludeClassType("AuctionSearchContext")
local USE_GET_ALL = true

-- DE-able minimum quality for slowscan fallback (Uncommon=2). On 3.3.5
-- QueryAuctionItems honors only minQuality (not max). Class translation
-- (modern Enum.ItemClass.* -> 1-based AH index) now lives in AuctionHouseWrapper,
-- so SetClass works correctly on 3.3.5 — slowscan uses 2 narrow queries
-- (Weapon + Armor) instead of one broad minQuality=2 dump. DE-able items live
-- almost entirely in these two AH classes; the few stragglers (recipes etc.)
-- aren't worth a third query.
local SLOWSCAN_MIN_QUALITY = 2
local FORCE_GET_ALL = false
local MAX_PER_ITEM_DE_SCAN = 150

-- 3.3.5a hard cap: no item exists above ilvl 284 (ICC 25H gear), so clamp the
-- user's configured max DE search level. Guards against garbage/typo input in
-- the settings (e.g. 9999) producing pointless filter passes on impossible
-- levels. The min level is left untouched (user's choice).
local MAX_DE_ITEM_LEVEL = 284
local CLASSIC_ITEM_INFO_RETRY_SECONDS = 2
local CLASSIC_ITEM_INFO_RETRY_INTERVAL = 0.1

-- Native scan engine constants — ported from Core/UI/AuctionUI/FullScan.lua
-- StartPagedScan. Bypasses AuctionScanManager/Query/Scanner pipeline entirely
-- and drives QueryAuctionItems(page=N) directly, with a bypass-throttle probe
-- and a frame-based throttle poll. Produces FullScan slow-scan style per-page
-- chat output. Toggle with /run TSM_DE_NATIVE_SCAN() or via flag below.
local NATIVE_PAGE_SIZE = 50
local NATIVE_BYPASS_PROBE_TIMEOUT = 0.5
local NATIVE_PAGE_TIMEOUT = 30
local NATIVE_THROTTLE_MAX_WAIT = 30
local NATIVE_MIN_MISSING_FOR_RETRY = 15
local NATIVE_MAX_PAGE_RETRIES = 1

local private = {
	settings = nil,
	itemList = {},
	itemListLookup = {},
	scanThreadId = nil,
	searchContext = nil,
	filterStats = nil,
	useNativeScan = false,
	native = {
		state = nil, -- nil | "paged" | "done"
		mode = nil,
		currentPage = 0,
		totalPages = 0,
		totalAuctions = 0,
		tStart = 0,
		tPageQuerySent = nil,
		tPageThrottleStart = nil,
		tPageThrottleWaitTime = 0,
		pageRetries = {},
		scanData = {}, -- baseItemString -> { minBuyout, totalCount, bestLink, lots }
		pagedRegistered = false,
		timeoutToken = 0,
		pollFrame = nil,
		stats = nil,
		onDone = nil,
	},
}



-- ============================================================================
-- Module Functions
-- ============================================================================

function DisenchantSearch.OnInitialize(settingsDB)
	private.settings = settingsDB:NewView()
		:AddKey("global", "shoppingOptions", "minDeSearchLvl")
		:AddKey("global", "shoppingOptions", "maxDeSearchLvl")
		:AddKey("global", "shoppingOptions", "maxDeSearchPercent")
	private.scanThreadId = Threading.New("DISENCHANT_SEARCH", private.ScanThread)
	private.searchContext = AuctionSearchContext(private.scanThreadId, private.MarketValueFunction)

	-- Slash commands to flip native scan path on/off at runtime.
	-- /dgnativeon  -> use native paged engine (bypass AuctionScanManager)
	-- /dgnativeoff -> use AuctionScanManager-driven slowscan-dual
	_G.SLASH_TSMDENATIVEON1 = "/dgnativeon"
	_G.SlashCmdList.TSMDENATIVEON = function()
		private.useNativeScan = true
		print("|cFFFFA500TSM:|r DE native scan = ON (bypass AuctionScanManager)")
	end
	_G.SLASH_TSMDENATIVEOFF1 = "/dgnativeoff"
	_G.SlashCmdList.TSMDENATIVEOFF = function()
		private.useNativeScan = false
		print("|cFFFFA500TSM:|r DE native scan = OFF (back to AuctionScanManager slowscan-dual)")
	end
end

function DisenchantSearch.GetSearchContext()
	return private.searchContext:SetScanContext(L["Disenchant Search"], nil, nil, L["Disenchant Value"])
end



-- ============================================================================
-- Native Paged Scan Engine (port of FullScan StartPagedScan)
-- ============================================================================

local function NativeEnsurePollFrame()
	local n = private.native
	if n.pollFrame then return end
	n.pollFrame = CreateFrame("Frame")
	n.pollFrame:Hide()
	n.pollFrame:SetScript("OnUpdate", function(self, elapsed)
		self._elapsed = (self._elapsed or 0) + elapsed
		if self._elapsed > NATIVE_THROTTLE_MAX_WAIT then
			self:Hide()
			self._elapsed = nil
			if private.native.state == "paged" then
				private.NativeAbort("throttle never cleared")
			end
			return
		end
		if CanSendAuctionQuery() then
			self:Hide()
			self._elapsed = nil
			if private.native.state == "paged" then
				private.NativeQueryNextPage()
			end
		end
	end)
end

local function NativeStartThrottlePoll()
	NativeEnsurePollFrame()
	private.native.pollFrame._elapsed = 0
	private.native.pollFrame:Show()
end

function private.NativeUnregister()
	if private.native.pagedRegistered then
		private.native.pagedRegistered = false
		pcall(Event.Unregister, "AUCTION_ITEM_LIST_UPDATE", private.NativeOnPagedResult)
	end
end

function private.NativeAbort(reason)
	print(string.format("|cffff5555[DE native]|r abort: %s", tostring(reason)))
	private.NativeUnregister()
	if private.native.pollFrame then private.native.pollFrame:Hide() end
	private.native.state = "done"
	if private.native.onDone then private.native.onDone(false) end
end

function private.NativeStart(itemList, onDone)
	local n = private.native
	n.state = "paged"
	n.mode = "paged"
	n.currentPage = 0
	n.totalPages = 0
	n.totalAuctions = 0
	n.tStart = GetTime()
	n.tPageQuerySent = nil
	n.tPageThrottleStart = nil
	n.tPageThrottleWaitTime = 0
	wipe(n.pageRetries)
	wipe(n.scanData)
	n.stats = { ok = 0, noLink = 0, noItemString = 0, noBuyout = 0, matched = 0, lots = 0, pageRetries = 0 }
	n.onDone = onDone
	n.timeoutToken = (n.timeoutToken or 0) + 1

	wipe(private.itemListLookup)
	for _, baseStr in ipairs(itemList) do
		private.itemListLookup[baseStr] = true
	end

	print(string.format("|cff00ff00[DE native]|r start: filter=%d items, bypass-probe+frame-poll engine",
		#itemList))
	private.NativeQueryNextPage()
end

function private.NativeQueryNextPage()
	local n = private.native
	if n.state ~= "paged" then return end
	if not DefaultUI.IsAuctionHouseVisible() then
		private.NativeAbort("AH window not visible")
		return
	end

	if not n.tPageThrottleStart then
		n.tPageThrottleStart = GetTime()
	end

	local canQuery = CanSendAuctionQuery()
	if not canQuery then
		-- Bypass probe: shoot QueryAuctionItems immediately without waiting for
		-- the ~1.5s client throttle timer. Many private cores have a shorter
		-- server-side throttle than the client thinks. If accepted → server
		-- response in 0.1-0.2s. If dropped → no response in BYPASS_PROBE_TIMEOUT
		-- → fall back to frame-poll throttle clear.
		n.tPageQuerySent = GetTime()
		n.tPageThrottleWaitTime = 0
		Event.Register("AUCTION_ITEM_LIST_UPDATE", private.NativeOnPagedResult)
		n.pagedRegistered = true
		QueryAuctionItems(nil, nil, nil, nil, nil, nil, n.currentPage, nil, SLOWSCAN_MIN_QUALITY)

		local pageAtStart = n.currentPage
		local bypassToken = n.timeoutToken
		C_Timer.After(NATIVE_BYPASS_PROBE_TIMEOUT, function()
			if private.native.state ~= "paged"
				or private.native.currentPage ~= pageAtStart
				or not private.native.pagedRegistered
				or private.native.timeoutToken ~= bypassToken then
				return -- server already responded or scan aborted
			end
			private.NativeUnregister()
			if CanSendAuctionQuery() then
				private.NativeQueryNextPage()
			else
				NativeStartThrottlePoll()
			end
		end)
		return
	end

	n.tPageQuerySent = GetTime()
	n.tPageThrottleWaitTime = n.tPageQuerySent - (n.tPageThrottleStart or n.tPageQuerySent)

	Event.Register("AUCTION_ITEM_LIST_UPDATE", private.NativeOnPagedResult)
	n.pagedRegistered = true
	QueryAuctionItems(nil, nil, nil, nil, nil, nil, n.currentPage, nil, SLOWSCAN_MIN_QUALITY)

	local pageAtStart = n.currentPage
	C_Timer.After(NATIVE_PAGE_TIMEOUT, function()
		if private.native.state == "paged"
			and private.native.currentPage == pageAtStart
			and private.native.pagedRegistered then
			private.NativeAbort(string.format("page %d timeout (%ds)", pageAtStart + 1, NATIVE_PAGE_TIMEOUT))
		end
	end)
end

function private.NativeOnPagedResult()
	local n = private.native
	if n.state ~= "paged" then return end
	private.NativeUnregister()

	local now = GetTime()
	local throttleWait = n.tPageThrottleWaitTime or 0
	local serverTime = n.tPageQuerySent and (now - n.tPageQuerySent) or 0
	local totalPageTime = throttleWait + serverTime

	local numBatch, numTotal = GetNumAuctionItems("list")
	if n.currentPage == 0 and (n.pageRetries[0] or 0) == 0 then
		n.totalAuctions = numTotal or 0
		n.totalPages = math.ceil((numTotal or 0) / NATIVE_PAGE_SIZE)
		print(string.format(
			"|cff00ff00[DE native]|r totalAuctions=%d pages=%d (PAGE_SIZE=%d)",
			n.totalAuctions, n.totalPages, NATIVE_PAGE_SIZE))
	end

	local modeTag = (throttleWait < 0.05) and "|cff00ff00[bypass]|r" or "[normal]"
	print(string.format(
		"|cff66ccff[DE native]|r page %d/%d: %.2fs (throttle %.2fs + server %.2fs)  batch=%d %s",
		n.currentPage + 1, n.totalPages > 0 and n.totalPages or 0,
		totalPageTime, throttleWait, serverTime, numBatch or 0, modeTag))

	n.tPageThrottleStart = nil
	n.tPageQuerySent = nil
	n.tPageThrottleWaitTime = 0

	local pageOk, pageMissing = 0, 0
	if numBatch and numBatch > 0 then
		for i = 1, numBatch do
			local ok = private.NativeProcessAuction(i)
			if ok then pageOk = pageOk + 1 else pageMissing = pageMissing + 1 end
		end
	end

	-- Per-page retry if too many items missed (item cache cold).
	local retriesSoFar = n.pageRetries[n.currentPage] or 0
	local shouldRetry = numBatch and numBatch > 0
		and pageMissing > NATIVE_MIN_MISSING_FOR_RETRY
		and retriesSoFar < NATIVE_MAX_PAGE_RETRIES
	if shouldRetry then
		n.pageRetries[n.currentPage] = retriesSoFar + 1
		n.stats.pageRetries = n.stats.pageRetries + 1
		print(string.format(
			"|cffffaa00[DE native]|r retry page %d (ok=%d miss=%d, attempt %d/%d)",
			n.currentPage + 1, pageOk, pageMissing,
			retriesSoFar + 1, NATIVE_MAX_PAGE_RETRIES))
		private.NativeQueryNextPage()
		return
	end

	-- advance
	n.currentPage = n.currentPage + 1
	if (n.totalPages > 0 and n.currentPage >= n.totalPages) or numBatch == 0 then
		private.NativeFinish()
		return
	end
	private.NativeQueryNextPage()
end

function private.NativeProcessAuction(idx)
	local n = private.native
	local link = GetAuctionItemLink("list", idx)
	if not link then
		n.stats.noLink = n.stats.noLink + 1
		return false
	end
	local itemString = ItemString.Get(link)
	local baseItemString = itemString and ItemString.GetBaseFast(itemString) or nil
	if not baseItemString then
		n.stats.noItemString = n.stats.noItemString + 1
		return false
	end
	if not private.itemListLookup[baseItemString] then
		-- not a DE-able target, but we did get its info -> not a "missed" page item
		n.stats.ok = n.stats.ok + 1
		return true
	end
	-- 3.3.5 signature: name, texture, count, quality, canUse, level, minBid,
	-- minIncrement, buyoutPrice (9th), ...
	local _, _, count, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo("list", idx)
	if not count or count <= 0 then
		n.stats.ok = n.stats.ok + 1
		return true
	end
	if not buyoutPrice or buyoutPrice <= 0 then
		n.stats.noBuyout = n.stats.noBuyout + 1
		n.stats.ok = n.stats.ok + 1
		return true -- bid-only, skip but count as processed
	end
	local perUnit = math.floor(buyoutPrice / count)
	local entry = n.scanData[baseItemString]
	if not entry then
		entry = { minBuyout = perUnit, totalCount = count, bestLink = link, lots = 1 }
		n.scanData[baseItemString] = entry
		n.stats.matched = n.stats.matched + 1
	else
		if perUnit < entry.minBuyout then
			entry.minBuyout = perUnit
			entry.bestLink = link
		end
		entry.totalCount = entry.totalCount + count
		entry.lots = entry.lots + 1
	end
	n.stats.lots = n.stats.lots + 1
	n.stats.ok = n.stats.ok + 1
	return true
end

function private.NativeFinish()
	local n = private.native
	private.NativeUnregister()
	if n.pollFrame then n.pollFrame:Hide() end
	local elapsed = GetTime() - n.tStart
	local s = n.stats
	print(string.format(
		"|cff00ff00[DE native]|r DONE  pages=%d auctions=%d  matched=%d items / %d lots  elapsed=%.2fs",
		n.totalPages, n.totalAuctions, s.matched, s.lots, elapsed))
	print(string.format(
		"|cff00ff00[DE native]|r stats: ok=%d noLink=%d noItemStr=%d bidOnly=%d pageRetries=%d",
		s.ok, s.noLink, s.noItemString, s.noBuyout, s.pageRetries))

	-- Print matched items, cheapest-first.
	local sorted = {}
	for baseStr, e in pairs(n.scanData) do
		tinsert(sorted, { baseStr, e })
	end
	table.sort(sorted, function(a, b) return a[2].minBuyout < b[2].minBuyout end)
	for i = 1, math.min(#sorted, 60) do
		local baseStr, e = sorted[i][1], sorted[i][2]
		local deVal = CustomString.GetSourceValue("Destroy", baseStr) or 0
		local pct = deVal > 0 and (e.minBuyout / deVal * 100) or 0
		print(string.format(
			"|cff66ccff[DE]|r %s  min=%dc  count=%d  lots=%d  DE=%dc  buy/DE=%.0f%%",
			e.bestLink or tostring(baseStr), e.minBuyout, e.totalCount, e.lots, deVal, pct))
	end
	if #sorted > 60 then
		print(string.format("|cff66ccff[DE]|r ...and %d more matched items not printed", #sorted - 60))
	end

	n.state = "done"
	if n.onDone then n.onDone(true) end
end



-- ============================================================================
-- Scan Thread
-- ============================================================================

function private.ScanThread(auctionScan)
	if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
		return private.ScanRetail(auctionScan)
	end
	return private.ScanClassic(auctionScan)
end

-- Retail keeps the upstream AuctionDB-seeded item-list behavior. The 3.3.5
-- path below deliberately does not: the live AH is the source of truth for
-- what is currently for sale, while AuctionDB is used only by price sources.
function private.ScanRetail(auctionScan)
	local hasAppData = TSM.AuctionDB.GetAppDataUpdateTimes() >= time() - 60 * 60 * 12
	local hasLocalData = TSM.AuctionDB.HasLocalScanData and TSM.AuctionDB.HasLocalScanData()
	if not hasAppData and not hasLocalData then
		ChatMessage.PrintUser(L["No recent AuctionDB scan data found."])
		return false
	end

	wipe(private.itemList)
	for itemString, minBuyout in TSM.AuctionDB.LastScanIteratorThreaded() do
		if minBuyout and private.ShouldInclude(itemString, minBuyout) then
			tinsert(private.itemList, itemString)
		end
		Threading.Yield()
	end

	auctionScan:AddItemListQueriesThreaded(private.itemList)
	for _, query in auctionScan:QueryIterator() do
		query:AddCustomFilter(private.QueryFilter)
	end
	private.filterStats = nil
	if not auctionScan:ScanQueriesThreaded() then
		ChatMessage.PrintUser(L["TSM failed to scan some auctions. Please rerun the scan."])
		return false
	end
	return true
end

-- On 3.3.5, discover candidates from the current AH instead of from
-- AuctionDB.LastScanIteratorThreaded(). The old ordering meant a currently
-- listed item could never appear unless a previous AuctionDB scan had already
-- seen and valued it.
function private.ScanClassic(auctionScan)
	private.filterStats = {
		notDE = 0,
		badLevel = 0,
		noDEValue = 0,
		tooExpensive = 0,
		noBuyout = 0,
		pending = 0,
		unresolved = 0,
	}

	if private.useNativeScan then
		-- Keep the diagnostic native path available. It is not the production UI path.
		wipe(private.itemList)
		for itemString, minBuyout in TSM.AuctionDB.LastScanIteratorThreaded() do
			if minBuyout and private.ShouldInclude(itemString, minBuyout) then
				tinsert(private.itemList, itemString)
			end
			Threading.Yield()
		end
		local nativeDone, nativeSuccess = false, false
		private.NativeStart(private.itemList, function(success)
			nativeSuccess = success
			nativeDone = true
		end)
		while not nativeDone do
			Threading.Yield()
		end
		return nativeSuccess
	end

	local canGetAll = USE_GET_ALL and AuctionHouse.CanSendGetAllQuery()
	local forcedGetAll = false
	if not canGetAll and FORCE_GET_ALL then
		AuctionHouse.SetForceGetAll(true)
		forcedGetAll = true
		canGetAll = true
	end

	if canGetAll then
		auctionScan:NewQuery()
			:SetStr("", false)
			:SetQualityRange(SLOWSCAN_MIN_QUALITY, nil)
			:SetUseGetAll(true)
			:SetUsePriceSort(true)
			:SetIncrementalFilter(true)
		if forcedGetAll then
			AuctionHouse.SetForceGetAll(false)
		end
	else
		-- All disenchantable 3.3.5 equipment is in Weapon or Armor. Scan those
		-- live and let QueryFilter apply DE / ilvl / value / profitability rules.
		auctionScan:NewQuery()
			:SetStr("", false)
			:SetClass(Enum.ItemClass.Weapon)
			:SetQualityRange(SLOWSCAN_MIN_QUALITY, nil)
			:SetUsePriceSort(true)
			:SetIncrementalFilter(true)
		auctionScan:NewQuery()
			:SetStr("", false)
			:SetClass(Enum.ItemClass.Armor)
			:SetQualityRange(SLOWSCAN_MIN_QUALITY, nil)
			:SetUsePriceSort(true)
			:SetIncrementalFilter(true)
	end

	for _, query in auctionScan:QueryIterator() do
		query:AddCustomFilter(private.QueryFilter)
	end

	if not auctionScan:ScanQueriesThreaded() then
		ChatMessage.PrintUser(L["TSM failed to scan some auctions. Please rerun the scan."])
		return false
	end

	private.FinalizeClassicResults(auctionScan)
	private.PrintClassicSummary(auctionScan)
	return true
end

function private.ShouldInclude(itemString, minBuyout)
	if not ItemInfo.IsDisenchantable(itemString) then
		return false
	end

	local maxLevel = math.min(private.settings.maxDeSearchLvl, MAX_DE_ITEM_LEVEL)
	local itemLevel = ItemInfo.GetItemLevel(itemString) or -1
	if itemLevel < private.settings.minDeSearchLvl or itemLevel > maxLevel then
		return false
	end

	if private.IsItemBuyoutTooHigh(itemString, minBuyout) then
		return false
	end

	return true
end

---Same as ShouldInclude but returns the rejection reason for diagnostics.
function private.ShouldIncludeDebug(itemString, minBuyout)
	if not ItemInfo.IsDisenchantable(itemString) then
		return "not_de"
	end
	local maxLevel = math.min(private.settings.maxDeSearchLvl, MAX_DE_ITEM_LEVEL)
	local itemLevel = ItemInfo.GetItemLevel(itemString) or -1
	if itemLevel < private.settings.minDeSearchLvl or itemLevel > maxLevel then
		return "bad_level"
	end
	local disenchantValue = CustomString.GetSourceValue("Destroy", itemString)
	if not disenchantValue then
		return "no_de_value"
	end
	if minBuyout > private.settings.maxDeSearchPercent / 100 * disenchantValue then
		return "too_expensive"
	end
	return "ok"
end

function private.QueryFilter(_, row)
	if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
		local itemString = row:GetItemString()
		if not itemString then
			return false
		end
		local _, itemBuyout = row:GetBuyouts()
		return itemBuyout and private.IsItemBuyoutTooHigh(itemString, itemBuyout) or false
	end

	local reason = private.GetClassicFilterReason(row)
	local stats = private.filterStats
	if reason == "ok" then
		return false
	elseif reason == "pending" then
		if stats then stats.pending = stats.pending + 1 end
		return false
	end
	if stats and stats[reason] ~= nil then
		stats[reason] = stats[reason] + 1
	end
	return true
end

-- Return a stable filter decision for a live Classic auction. Missing item
-- metadata is not treated as "not disenchantable": calling the ItemInfo getters
-- requests the data, and the row is kept until FinalizeClassicResults retries it.
function private.GetClassicFilterReason(row)
	local itemString = row:GetItemString()
	if not itemString then
		return "pending"
	end
	local _, itemBuyout = row:GetBuyouts()
	if not itemBuyout or itemBuyout <= 0 then
		return "noBuyout"
	end

	local baseItemString = ItemString.GetBase(itemString)
	local classId = baseItemString and ItemInfo.GetClassId(baseItemString) or nil
	local quality = baseItemString and ItemInfo.GetQuality(baseItemString) or nil
	local itemLevel = baseItemString and ItemInfo.GetItemLevel(baseItemString) or nil
	local invSlotId = baseItemString and ItemInfo.GetInvSlotId(baseItemString) or nil
	if not classId or not quality or not itemLevel or not invSlotId then
		local _, rawLink = row:GetLinks()
		if rawLink then
			_G.GetItemInfo(rawLink)
		end
		return "pending"
	end
	if not ItemInfo.IsDisenchantable(baseItemString) then
		return "notDE"
	end

	local maxLevel = math.min(private.settings.maxDeSearchLvl, MAX_DE_ITEM_LEVEL)
	if itemLevel < private.settings.minDeSearchLvl or itemLevel > maxLevel then
		return "badLevel"
	end

	local disenchantValue = CustomString.GetSourceValue("Destroy", itemString)
	if not disenchantValue or disenchantValue <= 0 then
		return "noDEValue"
	end
	if itemBuyout > private.settings.maxDeSearchPercent / 100 * disenchantValue then
		return "tooExpensive"
	end
	return "ok"
end

-- The initial live scan keeps rows whose item metadata is still cold. Resolve
-- all such rows together for a bounded period rather than rejecting each one on
-- the first nil GetItemInfo result (which disproportionately hid old gear).
function private.FinalizeClassicResults(auctionScan)
	local deadline = GetTime() + CLASSIC_ITEM_INFO_RETRY_SECONDS
	while true do
		local pending = {}
		local remove = {}
		for _, query in auctionScan:QueryIterator() do
			for _, row in query:BrowseResultsIterator() do
				for _, subRow in row:SubRowIterator() do
					local reason = private.GetClassicFilterReason(subRow)
					if reason == "pending" then
						tinsert(pending, subRow)
					elseif reason ~= "ok" then
						tinsert(remove, { subRow, reason })
					end
				end
			end
		end

		for _, info in ipairs(remove) do
			local subRow, reason = info[1], info[2]
			local resultRow = subRow:GetResultRow()
			if resultRow then
				resultRow:RemoveSubRow(subRow)
				if private.filterStats and private.filterStats[reason] ~= nil then
					private.filterStats[reason] = private.filterStats[reason] + 1
				end
			end
		end

		if #pending == 0 then
			return
		elseif GetTime() >= deadline then
			for _, subRow in ipairs(pending) do
				local resultRow = subRow:GetResultRow()
				if resultRow then
					resultRow:RemoveSubRow(subRow)
					private.filterStats.unresolved = private.filterStats.unresolved + 1
				end
			end
			return
		end
		Threading.Sleep(CLASSIC_ITEM_INFO_RETRY_INTERVAL)
	end
end

function private.PrintClassicSummary(auctionScan)
	local itemCount, auctionCount = 0, 0
	for _, query in auctionScan:QueryIterator() do
		for _, row in query:BrowseResultsIterator() do
			itemCount = itemCount + 1
			for _, subRow in row:SubRowIterator() do
				local _, numAuctions = subRow:GetQuantities()
				auctionCount = auctionCount + (numAuctions or 1)
			end
		end
	end
	local s = private.filterStats
	print(string.format(
		"|cFFFFA500TSM DE Scan:|r kept=%d items / %d auctions; filtered notDE=%d ilvl=%d noValue=%d tooExpensive=%d noBuyout=%d unresolved=%d",
		itemCount, auctionCount, s.notDE, s.badLevel, s.noDEValue, s.tooExpensive, s.noBuyout, s.unresolved))
end

function private.IsItemBuyoutTooHigh(itemString, itemBuyout)
	local disenchantValue = CustomString.GetSourceValue("Destroy", itemString)
	return not disenchantValue or itemBuyout > private.settings.maxDeSearchPercent / 100 * disenchantValue
end

function private.MarketValueFunction(row)
	return CustomString.GetSourceValue("Destroy", row:GetItemString() or row:GetBaseItemString())
end
