--!strict
-- Analytics placeholders (M4-04): structured console lines only — no external
-- HTTP, no SDKs. At launch the same events can feed a real sink; the funnel
-- (join -> firstCore -> firstSteal / rebirth / nightSurvive) stays identical.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local AnalyticsService = {}

local counts: { [string]: number } = {
	joins = 0,
	firstCore = 0,
	firstSteal = 0,
	rebirth = 0,
	nightSurvive = 0,
}

local seenFirstCore: { [Player]: boolean } = {}
local seenFirstSteal: { [Player]: boolean } = {}

local function log(event: string, player: Player?, detail: string?)
	counts[event] = (counts[event] or 0) + 1
	local payload = {
		event = event,
		player = if player then player.Name else nil,
		detail = detail,
		total = counts[event],
	}
	print(`[Analytics] {HttpService:JSONEncode(payload)}`)
end

function AnalyticsService.onJoin(player: Player)
	log("joins", player)
end

-- The player's first hatched core this session (funnel step 2).
function AnalyticsService.onCoreHatched(state: Types.PlayerState)
	local player = state.player
	if not player or seenFirstCore[player] then
		return
	end
	seenFirstCore[player] = true
	log("firstCore", player)
end

-- The player's first successful rip this session (funnel step 3a).
function AnalyticsService.onSteal(player: Player)
	if seenFirstSteal[player] then
		return
	end
	seenFirstSteal[player] = true
	log("firstSteal", player)
end

function AnalyticsService.onRebirth(player: Player)
	log("rebirth", player)
end

function AnalyticsService.onNightSurvive(state: Types.PlayerState)
	log("nightSurvive", state.player)
end

function AnalyticsService.summary(): string
	return HttpService:JSONEncode(counts)
end

function AnalyticsService.init()
	for _, player in Players:GetPlayers() do
		AnalyticsService.onJoin(player)
	end
	Players.PlayerAdded:Connect(AnalyticsService.onJoin)

	game:BindToClose(function()
		print(`[Analytics] session summary {AnalyticsService.summary()}`)
	end)
end

-- Session counters reset on the next server start; nothing is persisted (M4-04 scope).
return AnalyticsService
