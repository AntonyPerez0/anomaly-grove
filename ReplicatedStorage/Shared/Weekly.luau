--!strict
-- Weekly scheduled event clock (M9-09), shared by server and client. Pure: works
-- on a UTC os.time() so every server (and the HUD countdown) agrees.

local Config = require(script.Parent.Config)

local Weekly = {}

local DAY = 86400
local HOUR = 3600

-- Seconds since this week's start moment (can be negative = later this week).
local function offsetIntoEvent(now: number): number
	local t = os.date("!*t", now)
	local secondsToday = t.hour * HOUR + t.min * 60 + t.sec
	local dayDelta = t.wday - Config.Weekly.Weekday -- days since the event weekday
	return dayDelta * DAY + secondsToday - Config.Weekly.StartHour * HOUR
end

function Weekly.isActive(now: number): boolean
	local offset = offsetIntoEvent(now)
	return offset >= 0 and offset < Config.Weekly.DurationHours * HOUR
end

-- Seconds left while active (0 when not active).
function Weekly.secondsLeft(now: number): number
	if not Weekly.isActive(now) then
		return 0
	end
	return Config.Weekly.DurationHours * HOUR - offsetIntoEvent(now)
end

-- Seconds until the next start (0 while active).
function Weekly.secondsUntilStart(now: number): number
	if Weekly.isActive(now) then
		return 0
	end
	local offset = offsetIntoEvent(now)
	local week = 7 * DAY
	local untilStart = -offset % week
	return if untilStart == 0 then week else untilStart
end

return Weekly
