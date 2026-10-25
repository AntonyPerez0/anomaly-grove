--!strict
-- Minimal test framework (no packages needed).
-- A spec is a ModuleScript whose name ends in "Spec" and that returns `function(t: TestKit.Context) ... end`.
-- Run all specs during a playtest with:
--   require(game.ServerStorage.Tests.RunTests).run()

export type Context = {
	describe: (name: string, body: () -> ()) -> (),
	it: (name: string, body: () -> ()) -> (),
	equal: (actual: any, expected: any, message: string?) -> (),
	deepEqual: (actual: any, expected: any, message: string?) -> (),
	truthy: (value: any, message: string?) -> (),
	near: (actual: number, expected: number, epsilon: number?, message: string?) -> (),
	throws: (fn: () -> (), message: string?) -> (),
}

export type Result = {
	passed: number,
	failed: number,
	failures: { string },
	report: string,
}

local TestKit = {}

local function fail(message: string)
	-- Level 3 points the error at the line in the spec that called the assertion.
	error(message, 3)
end

local function describeValue(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function isDeepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not isDeepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function withMessage(base: string, message: string?): string
	if message then
		return message .. ": " .. base
	end
	return base
end

local function buildContext(path: { string }, record: (ok: boolean, name: string, err: any) -> ()): Context
	local function joinPath(name: string?): string
		local parts = table.clone(path)
		if name then
			table.insert(parts, name)
		end
		return table.concat(parts, " > ")
	end

	local context: Context = {
		describe = function(name: string, body: () -> ())
			table.insert(path, name)
			-- Cast: pcall on a function with no return values is typed as returning only `ok`.
			local ok, err = pcall(body :: any)
			if not ok then
				record(false, joinPath("(error inside describe)"), err)
			end
			table.remove(path)
		end,

		it = function(name: string, body: () -> ())
			-- Cast: pcall on a function with no return values is typed as returning only `ok`.
			local ok, err = pcall(body :: any)
			record(ok, joinPath(name), err)
		end,

		equal = function(actual: any, expected: any, message: string?)
			if actual ~= expected then
				fail(
					withMessage(
						string.format("expected %s, got %s", describeValue(expected), describeValue(actual)),
						message
					)
				)
			end
		end,

		deepEqual = function(actual: any, expected: any, message: string?)
			if not isDeepEqual(actual, expected) then
				fail(withMessage("tables are not deeply equal", message))
			end
		end,

		truthy = function(value: any, message: string?)
			if not value then
				fail(withMessage(string.format("expected a truthy value, got %s", describeValue(value)), message))
			end
		end,

		near = function(actual: number, expected: number, epsilon: number?, message: string?)
			local tolerance = epsilon or 1e-6
			if math.abs(actual - expected) > tolerance then
				fail(
					withMessage(
						string.format(
							"expected %s +/- %s, got %s",
							tostring(expected),
							tostring(tolerance),
							tostring(actual)
						),
						message
					)
				)
			end
		end,

		throws = function(fn: () -> (), message: string?)
			local ok = pcall(fn)
			if ok then
				fail(withMessage("expected function to throw", message))
			end
		end,
	}

	return context
end

-- Runs every "*Spec" ModuleScript under `root` and returns a summary.
function TestKit.run(root: Instance): Result
	local passed = 0
	local failed = 0
	local failures: { string } = {}
	local path: { string } = {}

	local function record(ok: boolean, name: string, err: any)
		if ok then
			passed += 1
		else
			failed += 1
			if err == nil then
				table.insert(failures, name)
			else
				table.insert(failures, name .. "\n    " .. tostring(err))
			end
		end
	end

	local context = buildContext(path, record)

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ModuleScript") and string.sub(descendant.Name, -4) == "Spec" then
			table.insert(path, descendant.Name)
			local loaded, specOrError = pcall(require, descendant)
			if not loaded then
				record(false, table.concat(path, " > ") .. " (failed to load)", specOrError)
			elseif type(specOrError) ~= "function" then
				record(false, table.concat(path, " > ") .. " (spec must return a function)", nil)
			else
				local ran, runError = pcall(specOrError, context)
				if not ran then
					record(false, table.concat(path, " > ") .. " (error at top level of spec)", runError)
				end
			end
			table.remove(path)
		end
	end

	local lines = { string.format("TESTS: %d passed, %d failed", passed, failed) }
	for _, failure in failures do
		table.insert(lines, "FAIL " .. failure)
	end
	if failed == 0 then
		table.insert(lines, "ALL TESTS PASSED")
	end

	return {
		passed = passed,
		failed = failed,
		failures = failures,
		report = table.concat(lines, "\n"),
	}
end

return TestKit
