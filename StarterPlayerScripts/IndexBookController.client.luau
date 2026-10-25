--!strict
-- Index book controller (M2-10): toggle button, discovery chime + refresh.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local IndexBookBuilder = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("IndexBook"))

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once.
if player:GetAttribute("IndexBookInitialized") then
	return
end
player:SetAttribute("IndexBookInitialized", true)

local book = IndexBookBuilder.build()

local function refresh()
	IndexBookBuilder.refresh(book, player:GetAttribute("IndexKeys"))
end
player:GetAttributeChangedSignal("IndexKeys"):Connect(refresh)
refresh()

-- M5-09: the side menu opens the book through the router (one modal at a time).
local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
book.toggleButton.Visible = false
UIRouter.register("Index", {
	open = function()
		refresh()
		book.gui.Enabled = true
		UITheme.popIn(book.page)
	end,
	close = function()
		book.gui.Enabled = false
	end,
})
local close = UITheme.button(book.page, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(44, 44)
close.Activated:Connect(function()
	UIRouter.close("Index")
end)

-- New discovery: chime + refresh.
Remotes.get("Discovery").OnClientEvent:Connect(function(kind: string, name: string)
	local sound = Instance.new("Sound")
	sound.SoundId = Config.FX.HarvestSound
	sound.Volume = Config.FX.FxVolume
	sound.Parent = SoundService
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
	print(`[IndexBook] NEW DISCOVERY ({kind}): {name}`)
	refresh()
end)
