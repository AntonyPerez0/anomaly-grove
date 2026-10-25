--!strict
-- Example spec and a self-check of TestKit. Copy this shape for new tests.
local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("TestKit", function()
		t.it("compares values", function()
			t.equal(1 + 1, 2)
			t.truthy(true)
			t.near(0.1 + 0.2, 0.3)
		end)

		t.it("compares tables deeply", function()
			t.deepEqual({ a = 1, b = { 2, 3 } }, { a = 1, b = { 2, 3 } })
		end)

		t.it("detects errors", function()
			t.throws(function()
				error("boom")
			end)
		end)
	end)
end
