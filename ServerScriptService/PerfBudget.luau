--!strict
-- Rolling worst-case timings for the heartbeat loops (M4-01): each loop reports
-- its per-iteration work via spot(); perf:report prints the worst ms per label.
-- Budget: the combined per-tick work must stay well under the 8 ms heartbeat
-- budget (GDD mobile target).

local PerfBudget = {}

local worstMs: { [string]: number } = {}

-- Record one measured iteration (seconds) for a labeled loop.
function PerfBudget.spot(label: string, seconds: number)
	local ms = seconds * 1000
	if ms > (worstMs[label] or 0) then
		worstMs[label] = ms
	end
end

-- "MonsterAI=1.23ms CoreTick=0.45ms ..." over the labels seen so far.
function PerfBudget.report(): string
	local parts: { string } = {}
	local total = 0
	for label, ms in worstMs do
		table.insert(parts, `{label}={string.format("%.2f", ms)}ms`)
		total += ms
	end
	table.sort(parts)
	table.insert(parts, `total={string.format("%.2f", total)}ms (budget 8ms)`)
	return table.concat(parts, " ")
end

function PerfBudget.reset()
	worstMs = {}
end

return PerfBudget
