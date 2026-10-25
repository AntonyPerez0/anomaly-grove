--!strict
-- Entry point for the agent. During a playtest, run with execute_luau (datamodel_type = Server):
--   return require(game.ServerStorage.Tests.RunTests).run()

local TestKit = require(script.Parent.TestKit)

local RunTests = {}

function RunTests.run(): string
	local result = TestKit.run(script.Parent)
	if result.failed > 0 then
		warn(result.report)
	else
		print(result.report)
	end
	return result.report
end

return RunTests
