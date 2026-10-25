--!strict
-- M8-01: RuneScape XP table, number formatting, cost curves.
local Progression = require(game:GetService("ReplicatedStorage").Shared.Progression)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Progression", function()
		t.it("matches the RuneScape XP table", function()
			t.equal(Progression.xpForLevel(1), 0)
			t.equal(Progression.xpForLevel(2), 83)
			t.equal(Progression.xpForLevel(10), 1154)
			t.equal(Progression.xpForLevel(50), 101333)
			t.equal(Progression.xpForLevel(92), 6517253)
			t.equal(Progression.xpForLevel(99), 13034431)
		end)

		t.it("levelForXp is the inverse at every boundary", function()
			t.equal(Progression.levelForXp(0), 1)
			t.equal(Progression.levelForXp(82), 1)
			t.equal(Progression.levelForXp(83), 2)
			for level = 1, 99 do
				t.equal(Progression.levelForXp(Progression.xpForLevel(level)), level)
			end
			t.equal(Progression.levelForXp(200000000), 99)
		end)

		t.it("progress reports the span inside a level and 0 at 99", function()
			local level, into, span = Progression.progress(100)
			t.equal(level, 2)
			t.equal(into, 17)
			t.equal(span, 174 - 83)
			local maxLevel, _, maxSpan = Progression.progress(13034431)
			t.equal(maxLevel, 99)
			t.equal(maxSpan, 0)
		end)

		t.it("formats small numbers with commas and big ones with suffixes", function()
			t.equal(Progression.format(950), "950")
			t.equal(Progression.format(9950), "9,950")
			t.equal(Progression.format(12345), "12.3K")
			t.equal(Progression.format(123456), "123K")
			t.equal(Progression.format(4560000), "4.56M")
			t.equal(Progression.format(1e12), "1.00T")
			t.equal(Progression.format(2.5e15), "2.50Qa")
			t.equal(Progression.format(-12345), "-12.3K")
		end)

		t.it("cost and compound curves", function()
			t.equal(Progression.cost(100, 2, 1), 100)
			t.equal(Progression.cost(100, 2, 4), 800)
			t.near(Progression.compound(1.07, 10), 1.07 ^ 10)
			t.equal(Progression.compound(1.07, -3), 1)
			t.equal(Progression.xpToLevel(0, 2), 83)
		end)
	end)
end
