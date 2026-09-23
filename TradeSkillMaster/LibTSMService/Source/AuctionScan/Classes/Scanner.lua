-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                          https://tradeskillmaster.com                          --
--    All Rights Reserved - Detailed license information included with addon.     --
-- ------------------------------------------------------------------------------ --

local LibTSMService = select(2, ...).LibTSMService
local Scanner = LibTSMService:Init("AuctionScan.Scanner")
local ItemInfo = LibTSMService:Include("Item.ItemInfo")
local ScanUtil = LibTSMService:Include("AuctionScan.Util")
local DelayTimer = LibTSMService:From("LibTSMWoW"):IncludeClassType("DelayTimer")
local AuctionHouse = LibTSMService:From("LibTSMWoW"):Include("API.AuctionHouse")
local Event = LibTSMService:From("LibTSMWoW"):Include("Service.Event")
local DefaultUI = LibTSMService:From("LibTSMWoW"):Include("UI.DefaultUI")
local ClientInfo = LibTSMService:From("LibTSMWoW"):Include("Util.ClientInfo")
local ItemString = LibTSMService:From("LibTSMTypes"):Include("Item.ItemString")
local FSM = LibTSMService:From("LibTSMUtil"):Include("FSM")
local Future = LibTSMService:From("LibTSMUtil"):IncludeClassType("Future")
local Log = LibTSMService:From("LibTSMUtil"):Include("Util.Log")
local Threading = LibTSMService:From("LibTSMTypes"):Include("Threading")
local private = {
	resolveSellers = nil,
	pendingFuture = nil,
	query = nil, ---@type AuctionQuery
	callback = nil,
	browseId = 1,
	browseIsNoScan = false,
	browseIndex = 1,
	browsePendingIndexes = {},
	browseSellerRetries = {},
	browseInfoWaitStart = {},
	browseInfoFailed = false,
	searchRow = nil,
	useCachedData = nil,
	retryCount = 0,
	browseEmptyRetryCount = 0,
	browseSendThrottleWaitCount = 0,
	browseSendIsThrottleWait = false,
	requestFuture = Future.New("AUCTION_SCANNER_FUTURE"),
	requestResult = nil,
	fsm = nil,
	retryTimer = nil,
	doneTimer = nil,
	updateTimer = nil,
	missingItemIds = {},
	auctionDBScanData = nil,
	-- 3.3.5 diagnostics: per-scan counters for the classic browse processing
	-- pipeline (printed for traced queries, e.g. DE scan)
	classicStats = { seen = 0, noInfo = 0, noLink = 0, badLink = 0, nameSkip = 0, earlyReject = 0, added = 0 },
}
local BROWSE_MISSING_INFO_RETRY_DELAY = 0.05
local BROWSE_EMPTY_RETRY_DELAY = 0.25
local BROWSE_EMPTY_RETRY_MAX = 12
-- Some 3.3.5/private-server rows never finish resolving their link/info. Such a
-- row must not keep the whole Post/Cancel scan in ST_BROWSE_CHECKING forever.
-- Pending rows are retried concurrently and skipped only after this wall-clock
-- timeout, so normal asynchronous item-cache resolution still has time to finish.
local BROWSE_INFO_WAIT_TIMEOUT = 2
local SEARCH_NOT_READY_RETRY_DELAY = 0.1
local SEARCH_MISSING_ITEM_INFO_RETRY_DELAY = 0.1
local SEARCH_AH_NOT_READY_RETRY_DELAY = 0.5
local SEARCH_MISSING_INFO_RETRY_DELAY = 0.5
local FUTURE_FAILED_RETRY_DELAY = 0.1
local SORT_RETRY_DELAY = 0.5
local BROWSE_SEND_THROTTLE_RETRY_DELAY = 0.1
local BROWSE_SEND_THROTTLE_MAX_WAIT = 30
-- 3.3.5 perf: бюджет времени (мс) на обработку browse-страницы за один кадр.
-- Без него цикл ограничивался только числом pending-предметов: если данные
-- всех лотов были в кэше, страница целиком (сотни/тысячи лотов на ядрах с
-- крупными страницами / GetAll) обрабатывалась за один кадр — каждый лот
-- это дорогие C-вызовы GetAuctionItemInfo/GetAuctionItemLink. Это давало
-- многосекундные фризы на каждом поиске.
local BROWSE_PROCESS_TIME_BUDGET_MS = 25



-- ============================================================================
-- Module Loading
-- ============================================================================

Scanner:OnModuleLoad(function()
	private.retryTimer = DelayTimer.New("AUCTION_SCANNER_RETRY", private.RetryHandler)
	private.doneTimer = DelayTimer.New("AUCTION_SCANNER_DONE", private.RequestDoneHandler)
	private.updateTimer = DelayTimer.New("AUCTION_SCANNER_RETRY", function()
		private.fsm:SetLoggingEnabled(false)
		private.fsm:ProcessEvent("EV_BROWSE_RESULTS_UPDATED")
		private.fsm:SetLoggingEnabled(true)
	end)
	private.requestFuture:SetScript("OnCleanup", function()
		private.doneTimer:Cancel()
		private.fsm:ProcessEvent("EV_CANCEL")
	end)

	if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
		Event.Register("COMMODITY_SEARCH_RESULTS_UPDATED", function()
			private.fsm:ProcessEvent("EV_SEARCH_RESULTS_UPDATED")
		end)
		Event.Register("ITEM_SEARCH_RESULTS_UPDATED", function()
			private.fsm:ProcessEvent("EV_SEARCH_RESULTS_UPDATED")
		end)
		Event.Register("ITEM_KEY_ITEM_INFO_RECEIVED", function(_, itemId)
			private.fsm:SetLoggingEnabled(false)
			private.fsm:ProcessEvent("EV_ITEM_KEY_INFO_RECEIVED", itemId)
			private.fsm:SetLoggingEnabled(true)
		end)
	else
		Event.Register("AUCTION_ITEM_LIST_UPDATE", function()
			local numAuctions, totalAuctions = AuctionHouse.GetNumAuctions()
			TSMDBG.Log("Scanner", "AUCTION_ITEM_LIST_UPDATE numAuctions=%d totalAuctions=%d", numAuctions or 0, totalAuctions or 0)
			private.updateTimer:RunForFrames(0)
		end)
	end

	private.fsm = FSM.New("AUCTION_SCANNER_FSM")
		:AddState(FSM.NewState("ST_INIT")
			:SetOnEnter(function()
				private.query = nil
				private.resolveSellers = nil
				private.useCachedData = nil
				private.searchRow = nil
				private.callback = nil
				private.retryCount = 0
				private.browseEmptyRetryCount = 0
				private.browseSendThrottleWaitCount = 0
				wipe(private.browseInfoWaitStart)
				private.browseInfoFailed = false
				private.browseSendIsThrottleWait = false
				private.auctionDBScanData = nil
				private.retryTimer:Cancel()
				if private.pendingFuture then
					private.pendingFuture:Cancel()
					private.pendingFuture = nil
				end
			end)
			:AddTransition("ST_BROWSE_SORT")
			:AddTransition("ST_BROWSE_CHECKING")
			:AddTransition("ST_SEARCH_GET_KEY")
			:AddEvent("EV_START_BROWSE", function(_, query, resolveSellers, callback)
				assert(not private.query)
				-- Debug output disabled for EV_START_BROWSE to reduce chat spam
				-- print(string.format("TSM:EV_START_BROWSE query._str=%s", tostring(query._str)))
				private.query = query
				private.resolveSellers = resolveSellers
				private.browseId = private.browseId + 1
				private.browseIsNoScan = false
				private.callback = callback
				private.StartAuctionDBScan(query)
				return "ST_BROWSE_SORT"
			end)
			:AddEvent("EV_START_BROWSE_NO_SCAN", function(_, query, itemKeys, callback)
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				assert(not private.query)
				private.query = query
				private.browseId = private.browseId + 1
				private.browseIsNoScan = true
				private.callback = callback
				for _, itemKey in ipairs(itemKeys) do
					local baseItemString = ItemString.GetBaseFromItemKey(itemKey)
					private.query:_ProcessBrowseResult(baseItemString, itemKey)
				end
				return "ST_BROWSE_CHECKING"
			end)
			:AddEvent("EV_START_SEARCH", function(_, query, resolveSellers, useCachedData, searchRow, callback)
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				assert(not private.query)
				private.query = query
				private.resolveSellers = resolveSellers
				private.useCachedData = useCachedData
				private.searchRow = searchRow
				private.callback = callback
				private.searchRow:SearchReset()
				return "ST_SEARCH_GET_KEY"
			end)
		)
		:AddState(FSM.NewState("ST_BROWSE_SORT")
			:SetOnEnter(function()
				if not private.query:_SetSort() then
					private.retryTimer:RunForTime(SORT_RETRY_DELAY)
					return
				end
				return "ST_BROWSE_SEND"
			end)
			:AddTransition("ST_BROWSE_SORT")
			:AddTransition("ST_BROWSE_SEND")
			:AddTransition("ST_CANCELING")
			:AddEventTransition("EV_RETRY", "ST_BROWSE_SORT")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_BROWSE_SEND")
			:SetOnEnter(function()
				if private.MaybeWaitForBrowseSendThrottle() then
					return
				end
				private.browseSendIsThrottleWait = false
				private.HandleAuctionHouseWrapperResult(private.query:_SendWowQuery())
			end)
			:AddTransition("ST_BROWSE_SEND")
			:AddTransition("ST_BROWSE_CHECKING")
			:AddTransition("ST_CANCELING")
			:AddEvent("EV_FUTURE_SUCCESS", function()
				if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
					for _, result in ipairs(AuctionHouse.GetBrowseResults()) do
						local baseItemString = ItemString.GetBaseFromItemKey(result.itemKey)
						private.query:_ProcessBrowseResult(baseItemString, result.itemKey, result.minPrice, result.totalQuantity)
					end
				else
					private.browseIndex = 1
					wipe(private.browsePendingIndexes)
				end
				return "ST_BROWSE_CHECKING"
			end)
			:AddEventTransition("EV_RETRY", "ST_BROWSE_SEND")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_BROWSE_CHECKING")
			:SetOnEnter(function()
				-- Debug output disabled for ST_BROWSE_CHECKING to reduce chat spam
				-- print(string.format("TSM:ST_BROWSE_CHECKING browseIndex=%d numAuctions=%d", private.browseIndex, AuctionHouse.GetNumAuctions() or 0))
				if not private.query:_BrowseIsPageValid() then
					-- This page isn't valid, so go to the next page
					return "ST_BROWSE_REQUEST_MORE"
				else
					local browseResultsReady, browseResultsFailed = private.CheckBrowseResults()
					if browseResultsFailed then
						-- Never make pricing decisions from an incomplete Classic page.
						return "ST_BROWSE_DONE", false
					elseif not browseResultsReady then
						-- Results aren't valid yet, so check again.
						private.retryTimer:RunForTime(BROWSE_MISSING_INFO_RETRY_DELAY)
						return
					end
				end
				-- We're done with this set of browse results
				if private.callback then
					private.callback(private.query)
				end
				if private.browseIsNoScan or private.query:_BrowseIsDone() then
					-- We're done
					return "ST_BROWSE_DONE"
				else
					-- move on to the next page
					return "ST_BROWSE_REQUEST_MORE"
				end
			end)
			:AddTransition("ST_BROWSE_CHECKING")
			:AddTransition("ST_BROWSE_DONE")
			:AddTransition("ST_BROWSE_REQUEST_MORE")
			:AddTransition("ST_CANCELING")
			:AddEventTransition("EV_RETRY", "ST_BROWSE_CHECKING")
			:AddEventTransition("EV_BROWSE_RESULTS_UPDATED", "ST_BROWSE_CHECKING")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
			:AddEvent("EV_ITEM_KEY_INFO_RECEIVED", function(_, itemId)
				if not next(private.missingItemIds) then
					return
				end
				private.missingItemIds[itemId] = nil
				if not next(private.missingItemIds) then
					private.retryTimer:Cancel()
					return "ST_BROWSE_CHECKING"
				end
			end)
		)
		:AddState(FSM.NewState("ST_BROWSE_REQUEST_MORE")
			:SetOnEnter(function(_, isRetry)
				if private.query:_BrowseIsDone(isRetry) then
					return "ST_BROWSE_CHECKING"
				end
				if private.MaybeWaitForBrowseSendThrottle() then
					return
				end
				if private.browseSendIsThrottleWait then
					isRetry = false
					private.browseSendIsThrottleWait = false
				end
				private.HandleAuctionHouseWrapperResult(private.query:_BrowseRequestMore(isRetry))
			end)
			:AddTransition("ST_BROWSE_REQUEST_MORE")
			:AddTransition("ST_BROWSE_CHECKING")
			:AddTransition("ST_CANCELING")
			:AddEvent("EV_FUTURE_SUCCESS", function(_, ...)
				if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
					local newResults = ...
					for _, result in ipairs(newResults) do
						local baseItemString = ItemString.GetBaseFromItemKey(result.itemKey)
						private.query:_ProcessBrowseResult(baseItemString, result.itemKey, result.minPrice, result.totalQuantity)
					end
				else
					private.browseIndex = 1
					wipe(private.browsePendingIndexes)
					wipe(private.browseSellerRetries)
					wipe(private.browseInfoWaitStart)
					private.browseInfoFailed = false
				end
				return "ST_BROWSE_CHECKING"
			end)
			:AddEvent("EV_RETRY", function()
				if private.browseSendIsThrottleWait then
					return "ST_BROWSE_REQUEST_MORE"
				end
				return "ST_BROWSE_REQUEST_MORE", true
			end)
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_BROWSE_DONE")
			:SetOnEnter(function(_, result)
				private.HandleRequestDone(result ~= false)
				return "ST_INIT"
			end)
			:AddTransition("ST_INIT")
		)
		:AddState(FSM.NewState("ST_SEARCH_GET_KEY")
			:SetOnEnter(function()
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				if not private.searchRow:SearchIsReady() then
					private.retryTimer:RunForTime(SEARCH_NOT_READY_RETRY_DELAY)
					return
				end
				return "ST_SEARCH_SEND"
			end)
			:AddTransition("ST_SEARCH_GET_KEY")
			:AddTransition("ST_SEARCH_SEND")
			:AddTransition("ST_CANCELING")
			:AddEventTransition("EV_FUTURE_SUCCESS", "ST_SEARCH_SEND")
			:AddEventTransition("EV_RETRY", "ST_SEARCH_GET_KEY")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_SEARCH_SEND")
			:SetOnEnter(function()
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				if not DefaultUI.IsAuctionHouseVisible() then
					return "ST_CANCELING"
				end
				if private.useCachedData and private.searchRow:HasCachedSearchData() then
					return "ST_SEARCH_REQUEST_MORE"
				end
				local future, delayTime = private.searchRow:SearchSend()
				if future then
					private.HandleAuctionHouseWrapperResult(future)
				else
					if not delayTime then
						Log.Err("Failed to send search query - retrying")
						delayTime = SEARCH_AH_NOT_READY_RETRY_DELAY
					end
					-- Try again after a delay
					private.retryTimer:RunForTime(delayTime)
				end
			end)
			:AddTransition("ST_SEARCH_SEND")
			:AddTransition("ST_SEARCH_REQUEST_MORE")
			:AddTransition("ST_CANCELING")
			:AddEventTransition("EV_FUTURE_SUCCESS", "ST_SEARCH_REQUEST_MORE")
			:AddEventTransition("EV_RETRY", "ST_SEARCH_SEND")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_SEARCH_REQUEST_MORE")
			:SetOnEnter(function()
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				local baseItemString = private.searchRow:GetBaseItemString()
				-- Get if the item is a commodity or not
				local isCommodity = ItemInfo.IsCommodity(baseItemString)
				if isCommodity == nil then
					private.retryTimer:RunForTime(SEARCH_MISSING_ITEM_INFO_RETRY_DELAY)
					return
				end

				local isDone, future = private.searchRow:SearchCheckStatus()
				if isDone then
					return "ST_SEARCH_CHECKING"
				elseif future then
					private.HandleAuctionHouseWrapperResult(future)
				else
					private.retryTimer:RunForTime(SEARCH_AH_NOT_READY_RETRY_DELAY)
				end
			end)
			:AddTransition("ST_SEARCH_SEND")
			:AddTransition("ST_SEARCH_CHECKING")
			:AddTransition("ST_CANCELING")
			:AddEventTransition("EV_FUTURE_SUCCESS", "ST_SEARCH_CHECKING")
			:AddEventTransition("EV_RETRY", "ST_SEARCH_SEND")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_SEARCH_CHECKING")
			:SetOnEnter(function()
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				private.retryTimer:Cancel()
				private.searchRow:PopulateSubRows(private.browseId)

				-- check if all the sub rows have their data
				local missingInfo = false
				for _, subRow in private.searchRow:SubRowIterator(true) do
					if not subRow:HasRawData() or not subRow:HasItemString() then
						missingInfo = true
					elseif private.resolveSellers and not subRow:HasOwners() and not private.query:_IsFiltered(subRow, true) then
						-- Waiting for owner info
						-- Currently can't rely on owner info as of 9.2.7, so limit the retries for it
						if not ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) or private.retryCount <= 10 then
							missingInfo = true
						end
					end
				end

				if missingInfo and private.retryCount >= 100 then
					-- Out of retries, so give up
					return "ST_SEARCH_DONE", false
				elseif missingInfo then
					-- We'll try again
					private.retryCount = private.retryCount + 1
					private.retryTimer:RunForTime(SEARCH_MISSING_INFO_RETRY_DELAY)
					return
				end

				-- Filter the sub rows we don't care about
				private.searchRow:FilterSubRows(private.query)

				if private.callback then
					private.callback(private.query, private.searchRow)
				end
				if private.searchRow:SearchNext() then
					-- there is more to search
					return "ST_SEARCH_GET_KEY"
				else
					-- scanned everything
					return "ST_SEARCH_DONE", true
				end
			end)
			:AddTransition("ST_SEARCH_GET_KEY")
			:AddTransition("ST_SEARCH_CHECKING")
			:AddTransition("ST_SEARCH_DONE")
			:AddTransition("ST_CANCELING")
			:AddEventTransition("EV_RETRY", "ST_SEARCH_CHECKING")
			:AddEventTransition("EV_SEARCH_RESULTS_UPDATED", "ST_SEARCH_CHECKING")
			:AddEventTransition("EV_CANCEL", "ST_CANCELING")
		)
		:AddState(FSM.NewState("ST_SEARCH_DONE")
			:SetOnEnter(function(_, result)
				assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
				private.HandleRequestDone(result)
				return "ST_INIT"
			end)
			:AddTransition("ST_INIT")
		)
		:AddState(FSM.NewState("ST_CANCELING")
			:SetOnEnter(function()
				private.doneTimer:Cancel()
				return "ST_INIT"
			end)
			:AddTransition("ST_INIT")
		)
		:Init("ST_INIT", nil)
end)



-- ============================================================================
-- Module Functions
-- ============================================================================

---Starts a browse scan.
---@param query AuctionQuery The query
---@param resolveSellers boolean Whether or not to resolve seller names
---@param callback fun(query: AuctionQuery, row: AuctionRow) A function to call with results
---@return Future
function Scanner.Browse(query, resolveSellers, callback)
	if not private.WaitForFutureReady() then
		if TSMDBG then TSMDBG.Warn("Scanner", "Browse: WaitForFutureReady FAILED, returning nil") end
		return nil
	end
	if TSMDBG then TSMDBG.Log("Scanner", "Browse: starting future for new browse") end
	private.requestFuture:Start()
	private.fsm:ProcessEvent("EV_START_BROWSE", query, resolveSellers, callback)
	return private.requestFuture
end

---Starts a browse scan without issuing a new query to the game.
---@param query AuctionQuery The query
---@param itemKeys ItemKey[] The item keys to browse for
---@param callback fun(query: AuctionQuery, row: AuctionRow) A function to call with results
---@return Future
function Scanner.BrowseNoScan(query, itemKeys, callback)
	assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
	if not private.WaitForFutureReady() then
		return nil
	end
	private.requestFuture:Start()
	private.fsm:ProcessEvent("EV_START_BROWSE_NO_SCAN", query, itemKeys, callback)
	return private.requestFuture
end

-- 3.3.5: requestFuture is shared across all browse callers. When two threads
-- (e.g. FILTER_SEARCH and AUCTION_SCAN_FIND) want to scan back-to-back, the
-- second one hits assert(self._state == STATE.RESET) inside Future:Start.
-- Wait briefly for the previous browse to finish before we Start ours.
function private.WaitForFutureReady()
	if private.requestFuture:IsReady() then
		return true
	end
	if TSMDBG then TSMDBG.Log("Scanner", "WaitForFutureReady: future busy, yielding...") end
	local waitStart = GetTime()
	local yields = 0
	while not private.requestFuture:IsReady() do
		Threading.Yield(true)
		yields = yields + 1
		if GetTime() - waitStart > 5 then
			if TSMDBG then TSMDBG.Warn("Scanner", "WaitForFutureReady: timeout after %d yields, %.2fs", yields, GetTime() - waitStart) end
			return false
		end
	end
	if TSMDBG then TSMDBG.Log("Scanner", "WaitForFutureReady: ready after %d yields, %.2fs", yields, GetTime() - waitStart) end
	return true
end

---Starts a search.
---@param query AuctionQuery The query
---@param resolveSellers boolean Whether or not to resolve seller names
---@param useCachedData boolean Use cached data
---@param browseRow AuctionRow The auction row to search for
---@param callback fun(query: AuctionQuery, row: AuctionRow) A function to call with results
---@return Future
function Scanner.Search(query, resolveSellers, useCachedData, browseRow, callback)
	assert(ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE))
	private.requestFuture:Start()
	private.fsm:ProcessEvent("EV_START_SEARCH", query, resolveSellers, useCachedData, browseRow, callback)
	return private.requestFuture
end

---Cancels any in progress scan.
function Scanner.Cancel()
	-- 3.3.5 fix: also skip when the future is already DONE (resolved but not yet
	-- cleaned up), which happens when cancel races the done timer on AH close;
	-- calling Done() twice trips the Future.lua:91 assertion
	if private.requestFuture:IsReady() or private.requestFuture:IsDone() then
		return
	end
	private.requestFuture:Done(false)
end

---Cancels and discards any active browse so that a higher-priority operation
---(typically per-item find) can take over the AH query channel without racing
---with a long FILTER_SEARCH browse.
---3.3.5: BrowseAndFind operations share `private.requestFuture` and the
---underlying QueryAuctionItems channel, so we must explicitly preempt.
---ВАЖНО: вызывать ИЗ thread context (например _FindAuctionThreadedClassic).
---Future:Done синхронно резюмирует ожидающий thread, что нарушает Thread.lua:184
---assertion (private.runningThread должен быть nil). Поэтому ставим cancel
---через doneTimer (RunForTime(0)) — он отстрелит на следующем tick'е, когда
---текущий thread уже отдаст квант. После таймера нужно дождаться RESET.
function Scanner.PreemptForFind()
	if private.requestFuture:IsReady() then
		return false
	end
	if TSMDBG then TSMDBG.Log("Scanner", "PreemptForFind: scheduling cancel of active browse") end
	private.requestResult = false
	private.doneTimer:RunForTime(0)
	return true
end

---Returns true if the requestFuture is in RESET (no scan active).
---Public mirror of WaitForFutureReady's check, used by ScanManager to wait
---out a preempted browse before issuing a new query.
function Scanner.IsFutureReady()
	return private.requestFuture:IsReady()
end



-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function private.PendingFutureDoneHandler()
	local result = private.pendingFuture:GetValue()
	private.pendingFuture = nil
	if result then
		private.fsm:ProcessEvent("EV_FUTURE_SUCCESS", result)
	else
		private.retryTimer:RunForTime(FUTURE_FAILED_RETRY_DELAY)
	end
end

function private.RetryHandler()
	private.fsm:SetLoggingEnabled(false)
	private.fsm:ProcessEvent("EV_RETRY")
	private.fsm:SetLoggingEnabled(true)
end

---Returns true when a classic browse send must wait for CanSendAuctionQuery().
---@return boolean
function private.MaybeWaitForBrowseSendThrottle()
	if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
		return false
	end
	if private.browseSendThrottleWaitCount < BROWSE_SEND_THROTTLE_MAX_WAIT and not AuctionHouse.CanSendQuery() then
		private.browseSendThrottleWaitCount = private.browseSendThrottleWaitCount + 1
		private.browseSendIsThrottleWait = true
		private.retryTimer:RunForTime(BROWSE_SEND_THROTTLE_RETRY_DELAY)
		return true
	end
	private.browseSendThrottleWaitCount = 0
	return false
end

function private.RequestDoneHandler()
	local result = private.requestResult
	private.requestResult = nil
	-- 3.3.5 fix: the done timer fires on the NEXT frame, and the future can be
	-- resolved in between (e.g. the AH closes mid-scan -> Scanner.Cancel() calls
	-- Done(false) directly, or a preempt resolves it first). Calling Done() on a
	-- future that isn't STARTED trips the Future.lua:91 assertion, so bail out if
	-- there's nothing left to resolve.
	if private.requestFuture:IsReady() or private.requestFuture:IsDone() then
		return
	end
	private.requestFuture:Done(result)
end

function private.HandleAuctionHouseWrapperResult(future)
	if future then
		private.pendingFuture = future
		private.pendingFuture:SetScript("OnDone", private.PendingFutureDoneHandler)
	else
		private.retryTimer:RunForTime(FUTURE_FAILED_RETRY_DELAY)
	end
end

function private.HandleRequestDone(result)
	private.requestResult = result
	if TSMDBG then TSMDBG.Log("Scanner", "HandleRequestDone result=%s hasQuery=%s",
		tostring(result), tostring(private.query ~= nil)) end
	-- Persist the raw Classic market snapshot only after the browse completed
	-- successfully. Prices were captured before client-side operation/UI filters,
	-- so those filters cannot poison DBMinBuyout / DBRecent.
	if result and private.query and private.query:CanRecordAuctionDB() then
		local ok, err = pcall(private.FlushAuctionDBScan)
		if not ok and _G.TSMDebugDB then
			_G.TSMDebugDB.auctiondb_local = _G.TSMDebugDB.auctiondb_local or {}
			table.insert(_G.TSMDebugDB.auctiondb_local, "FlushAuctionDBScan ERR: "..tostring(err))
			if TSMDBG then TSMDBG.Warn("Scanner", "FlushAuctionDBScan ERR: %s", tostring(err)) end
		end
	end
	-- Delay a bit so that we complete our current FSM transition
	private.doneTimer:RunForTime(0)
end

-- 3.3.5: записать сводку browse-скана в локальную DB (TradeSkillMaster_AuctionDB).
-- Собирает minBuyout / marketValue / numAuctions per baseItemString и зовёт
-- _G.TSM_AuctionDB_RecordScan({[is]={mb=N, mv=N, na=N}}).
function private.StartAuctionDBScan(query)
	private.auctionDBScanData = nil
	if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) or not query:CanRecordAuctionDB() then
		return
	end

	local data = {}
	if query:CanInvalidateMissingAuctionDBItems() then
		for itemString in query:ItemIterator() do
			local baseItemString = ItemString.GetBaseFast(itemString)
			if baseItemString and itemString == baseItemString then
				data[baseItemString] = { na = 0, prices = {} }
			end
		end
	end
	private.auctionDBScanData = data
end

function private.RecordAuctionDBResult(baseItemString, stackSize, buyout)
	local scanData = private.auctionDBScanData
	if not scanData then
		return
	end
	local data = scanData[baseItemString]
	if not data then
		data = { na = 0, prices = {} }
		scanData[baseItemString] = data
	end
	data.na = data.na + 1
	if buyout and buyout > 0 and stackSize and stackSize > 0 then
		local itemBuyout = math.floor(buyout / stackSize)
		if itemBuyout > 0 then
			data.mb = data.mb and math.min(data.mb, itemBuyout) or itemBuyout
			data.prices[#data.prices + 1] = itemBuyout
		end
	end
end

function private.FlushAuctionDBScan()
	local rawData = private.auctionDBScanData
	private.auctionDBScanData = nil
	if not rawData or not _G.TSM_AuctionDB_RecordScan then
		return
	end

	local scanData = {}
	local count = 0
	for itemString, data in pairs(rawData) do
		local prices = data.prices
		local record = {
			na = data.na,
			nsamples = #prices,
		}
		if data.mb and data.mb > 0 then
			record.mb = data.mb
			record.mv = ScanUtil.CalcMarketValue(prices) or data.mb
		else
			record.clearLive = true
		end
		scanData[itemString] = record
		count = count + 1
	end

	if count == 0 then
		return
	end
	_G.TSM_AuctionDB_RecordScan(scanData)
	if _G.TSM_AuctionDB_RecordLocalScanResults then
		_G.TSM_AuctionDB_RecordLocalScanResults(scanData)
	end
	if _G.TSMDebugDB then
		_G.TSMDebugDB.auctiondb_local = _G.TSMDebugDB.auctiondb_local or {}
		local log = _G.TSMDebugDB.auctiondb_local
		while #log > 200 do
			table.remove(log, 1)
		end
		table.insert(log, string.format("[%s] RecordScan items=%d", date("%H:%M:%S"), count))
	end
end

function private.CheckBrowseResults()
	if not ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
		-- Process as many auctions as we can
		local numAuctions = AuctionHouse.GetNumAuctions()
		if private.browseIndex == 1 and #private.browsePendingIndexes == 0 then
			-- new scan starting: reset the diagnostics counters
			local cs = private.classicStats
			cs.seen, cs.noInfo, cs.noLink, cs.badLink, cs.nameSkip, cs.earlyReject, cs.added = 0, 0, 0, 0, 0, 0, 0
			wipe(private.browseSellerRetries)
			wipe(private.browseInfoWaitStart)
			private.browseInfoFailed = false
		end
		-- Some 3.3.5a cores briefly return an empty page right after a browse query.
		-- Retry a few times instead of immediately showing an empty result set.
		if numAuctions > 0 then
			private.browseEmptyRetryCount = 0
		elseif private.query and private.query._str and private.query._str ~= "" and private.browseEmptyRetryCount < BROWSE_EMPTY_RETRY_MAX then
			private.browseEmptyRetryCount = private.browseEmptyRetryCount + 1
			private.retryTimer:RunForTime(BROWSE_EMPTY_RETRY_DELAY)
			TSMDBG.Log("Scanner", "Classic browse returned empty page; retrying (%d/%d)", private.browseEmptyRetryCount, BROWSE_EMPTY_RETRY_MAX)
			return false
		end
		for i = #private.browsePendingIndexes, 1, -1 do
			local index = private.browsePendingIndexes[i]
			if private.ProcessBrowseResultClassic(index) then
				tremove(private.browsePendingIndexes, i)
			end
		end
		if private.browseInfoFailed then
			return false, true
		end
		-- 3.3.5 perf: обрабатываем не дольше BROWSE_PROCESS_TIME_BUDGET_MS за
		-- вызов; при исчерпании бюджета продолжаем на следующем кадре через
		-- updateTimer (retryTimer от FSM с его 0.5с задержкой перекрывается
		-- более быстрым тиком updateTimer — EV_BROWSE_RESULTS_UPDATED вернёт
		-- нас в ST_BROWSE_CHECKING немедленно)
		local budgetStart = debugprofilestop()
		local budgetExhausted = false
		local index = private.browseIndex
		while index <= numAuctions and #private.browsePendingIndexes < 50 do
			if not private.ProcessBrowseResultClassic(index) then
				tinsert(private.browsePendingIndexes, index)
			end
			index = index + 1
			if debugprofilestop() - budgetStart > BROWSE_PROCESS_TIME_BUDGET_MS then
				budgetExhausted = index <= numAuctions
				break
			end
		end
		private.browseIndex = index
		if budgetExhausted then
			TSMDBG.Log("Scanner", "Browse page budget exhausted at index %d/%d; continuing next frame", private.browseIndex - 1, numAuctions)
			private.updateTimer:RunForFrames(1)
			return false
		end
		if private.browseIndex <= numAuctions or #private.browsePendingIndexes > 0 then
			return false
		end
	end

	-- Attempt to populate the browse results
	wipe(private.missingItemIds)
	local populated, numRemoved = nil, 0
	if ClientInfo.HasFeature(ClientInfo.FEATURES.C_AUCTION_HOUSE) then
		populated, numRemoved = private.query:_PopulateBrowseData(private.missingItemIds)
		if numRemoved > 0 then
			Log.Info("Removed %d results while populing data", numRemoved)
		end
		if not populated then
			return false
		end
	else
		TSMDBG.Log("Scanner", "Calling _PopulateBrowseData (classic, no-wait)")
		populated, numRemoved = private.query:_PopulateBrowseData(private.missingItemIds)
		if numRemoved > 0 then
			Log.Info("Removed %d results while populing data", numRemoved)
		end
		populated = true
	end

	-- Filter the results
	numRemoved = private.query:_FilterBrowseResults()
	if numRemoved > 0 then
		Log.Info("Removed %d filtered results", numRemoved)
		TSMDBG.Log("Scanner", "Filtered out %d results", numRemoved)
	end

	-- Count final results
	local totalResults = 0
	for _ in private.query:BrowseResultsIterator() do
		totalResults = totalResults + 1
	end
	TSMDBG.Log("Scanner", "Final results count=%d", totalResults)
	TSMDBG.TimeEnd("Scanner:CheckBrowseResults")

	return true
end

function private.HandleUnresolvedBrowseRow(index, reason)
	local now = GetTime()
	local startTime = private.browseInfoWaitStart[index]
	if not startTime then
		private.browseInfoWaitStart[index] = now
		return false
	end
	if now - startTime < BROWSE_INFO_WAIT_TIMEOUT then
		return false
	end
	private.browseInfoWaitStart[index] = nil
	private.browseInfoFailed = true
	Log.Err("Classic auction row %d stayed unresolved for %.1fs (%s); failing this query rather than using incomplete prices", index, BROWSE_INFO_WAIT_TIMEOUT, reason)
	return true
end

function private.ProcessBrowseResultClassic(index)
	local cs = private.classicStats
	cs.seen = cs.seen + 1
	local rawName, itemLink, stackSize, timeLeft, buyout, seller = AuctionHouse.GetBrowseResult(index)
	
	if not rawName or rawName == "" or not buyout or not stackSize or not timeLeft then
		cs.noInfo = cs.noInfo + 1
		return private.HandleUnresolvedBrowseRow(index, "auction info")
	end

	-- 3.3.5: Фильтруем по поисковой строке прямо здесь, как в Auctionator (не добавляем в browseResults, если не совпадает)
	if private.query._str and private.query._str ~= "" then
		local nameLower = strlower(rawName)
		if private.query._exact then
			if nameLower ~= private.query._strLower then
				cs.nameSkip = cs.nameSkip + 1
				return true
			end
		else
			if not strfind(nameLower, private.query._strLower, 1, true) then
				cs.nameSkip = cs.nameSkip + 1
				return true
			end
		end
	end


	if not itemLink then
		cs.noLink = cs.noLink + 1
		return private.HandleUnresolvedBrowseRow(index, "item link")
	end

	local baseItemString = ItemString.GetBase(itemLink)
	if not baseItemString then
		cs.badLink = cs.badLink + 1
		return private.HandleUnresolvedBrowseRow(index, "item string")
	end
	private.browseInfoWaitStart[index] = nil

	-- getAll dumps the whole AH; skip items not in the requested set early so we don't
	-- spend cycles populating SubRows for 50k irrelevant lots.
	local items = private.query._items
	if next(items) and not items[baseItemString] then
		cs.earlyReject = cs.earlyReject + 1
		return true
	end
	if private.resolveSellers and (not seller or seller == "") then
		local retries = (private.browseSellerRetries[index] or 0) + 1
		private.browseSellerRetries[index] = retries
		if retries <= 6 then
			-- Wait for server NAME_QUERY_RESPONSE to resolve player name
			return false
		end
		seller = "?"
	end
	-- Capture the raw lot before _FilterBrowseResults applies Shopping /
	-- Auctioning filters. Each Classic list index is one auction lot.
	private.RecordAuctionDBResult(baseItemString, stackSize, buyout)
	private.query:_ProcessBrowseResult(baseItemString, itemLink)
	private.query:_MarkDirtyRow(baseItemString)
	local row = private.query:_GetBrowseResults(baseItemString)
	local page = (private.query and private.query._page) or 0
	row:PopulateSubRows(private.browseId, index, itemLink, page)
	cs.added = cs.added + 1
	-- Classic browse rows always have raw data for newly populated listings,
	-- so no need to scan all existing subRows on every auction index.
	return true
end
