--!strict
-- Every declared remote must exist as a RemoteEvent once the server booted (M1-02).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Remotes", function()
		t.it("creates every remote as a RemoteEvent", function()
			local folder = ReplicatedStorage:FindFirstChild("Remotes")
			t.truthy(folder, "Remotes folder missing - did RemotesInit.server run?")
			if not folder then
				return
			end
			for _, name in Remotes.names do
				local remote = folder:FindFirstChild(name)
				t.truthy(remote, "missing remote: " .. name)
				if remote then
					t.truthy(remote:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
				end
			end
		end)
	end)
end
