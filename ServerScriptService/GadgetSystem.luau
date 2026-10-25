--!strict
-- Gadget shop + effects (M2-07): server-authoritative purchase and activation.
-- The server owns cooldowns and applies speed effects; the client only sends intent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)

local GadgetSystem = {}

-- (player, gadget) -> os.clock() ready time
local useReadyAt: { [Player]: { [string]: number } } = {}

-- (player) -> os.clock() when the smoke cloud dissipates
local smokeUntil: { [Player]: number } = {}

-- Invisible anchored part carrying an Attachment (beam endpoint helper).
local function tempAnchorPart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CFrame = CFrame.new(position)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	part.Parent = workspace
	return part
end

-- True while the player's smoke cloud blinds monsters/turrets.
function GadgetSystem.isSmokeActive(player: Player, now: number): boolean
	local untilTime = smokeUntil[player]
	return untilTime ~= nil and now < untilTime
end

-- Smoke Bomb: gray burst + a 3 s ignore window for monster/turret targeting.
local function applySmokeBomb(player: Player)
	local tuning = Config.Gadgets.SmokeBomb
	smokeUntil[player] = os.clock() + tuning.duration
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		FXService.burstAt(root.Position, Color3.fromRGB(120, 120, 128), 24)
	end
	print(`[GadgetSystem] {player.Name} pops a smoke bomb ({tuning.duration}s cover)`)
end

-- Grapple: pull up to Config range toward the aim point, with a beam visual.
local function applyGrapple(player: Player, aimPosition: Vector3?)
	local tuning = Config.Gadgets.Grapple
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local start = root.Position
	local direction: Vector3
	if aimPosition then
		direction = (aimPosition - start) * Vector3.new(1, 0, 1)
	else
		direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if direction.Magnitude < 0.1 then
		direction = Vector3.new(0, 0, 1)
	end
	direction = direction.Unit
	local landing = start + direction * tuning.range
	-- Keep the landing near ground level: sample the start's height.
	landing = Vector3.new(landing.X, start.Y + 2, landing.Z)
	local beamStart = tempAnchorPart(start)
	local beamEnd = tempAnchorPart(landing)
	local beam = Instance.new("Beam")
	beam.Attachment0 = beamStart:FindFirstChildOfClass("Attachment") :: Attachment
	beam.Attachment1 = beamEnd:FindFirstChildOfClass("Attachment") :: Attachment
	beam.Color = ColorSequence.new(Color3.fromRGB(60, 255, 220))
	beam.Width0 = 0.4
	beam.Width1 = 0.4
	beam.LightEmission = 1
	beam.Parent = beamStart
	game:GetService("Debris"):AddItem(beamStart, 0.5)
	game:GetService("Debris"):AddItem(beamEnd, 0.5)
	local liveCharacter = player.Character
	if liveCharacter then
		liveCharacter:PivotTo(CFrame.new(landing))
	end
	FXService.burstAt(landing, Color3.fromRGB(60, 255, 220), 10)
	print(`[GadgetSystem] {player.Name} grappled {math.floor((landing - start).Magnitude)} studs`)
end

-- Lantern (M9-02): a bright flash. MonsterAI registers the stun handler (it
-- already requires this module, so the hook avoids a require cycle).
local lanternHandler: ((player: Player, position: Vector3) -> number)? = nil

function GadgetSystem.onLantern(handler: (player: Player, position: Vector3) -> number)
	lanternHandler = handler
end

local function applyLantern(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 230, 150)
	flash.Brightness = 6
	flash.Range = Config.Gadgets.Lantern.radius
	flash.Shadows = false
	flash.Parent = root
	game:GetService("Debris"):AddItem(flash, 0.8)
	FXService.burstAt(root.Position, Color3.fromRGB(255, 230, 150), 30)
	local stunned = if lanternHandler then lanternHandler(player, root.Position) else 0
	if stunned > 0 then
		SkillService.addXp(player, "Survival", Config.Skills.Xp.lanternStun * stunned)
	end
	print(`[GadgetSystem] {player.Name} flashes the Lantern ({stunned} monsters stunned)`)
end

local COOLDOWN_STAT: { [string]: string } =
	{ DashBoots = "dashCooldown", SmokeBomb = "smokeCooldown", Grapple = "grappleCooldown" }

local function gadgetPrice(gadget: Types.Gadget): number?
	return (Config.Prices :: any)[gadget]
end

-- Pure purchase rules.
function GadgetSystem.checkPurchase(state: Types.PlayerState, gadget: Types.Gadget): (boolean, string)
	local price = gadgetPrice(gadget)
	if price == nil then
		return false, "unknown gadget"
	end
	if state.gadgets[gadget] then
		return false, "already owned"
	end
	if state.cash < (price :: number) then
		return false, `not enough cash (need {price})`
	end
	return true, "ok"
end

function GadgetSystem.buyGadget(player: Player, gadget: Types.Gadget): boolean
	local state = PlayerState.get(player)
	local ok, reason = GadgetSystem.checkPurchase(state, gadget)
	if not ok then
		print(`[GadgetSystem] {player.Name} {gadget} purchase rejected: {reason}`)
		return false
	end
	local price = Perks.discounted(gadgetPrice(gadget) :: number, SkillService.stats(state)) -- Commerce discount
	if not PlayerState.spendCash(state, price) then
		print(`[GadgetSystem] {player.Name} {gadget} purchase rejected: cash changed mid-purchase`)
		return false
	end
	state.gadgets[gadget] = true
	player:SetAttribute(`Gadget_{gadget}`, "owned")
	SkillService.addCommerceXp(player, price)
	print(`[GadgetSystem] {player.Name} bought {gadget} for {price}`)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

-- Pure use rules: ownership + per-gadget cooldown.
function GadgetSystem.checkUse(
	state: Types.PlayerState,
	gadget: Types.Gadget,
	readyAt: number,
	now: number
): (boolean, string)
	if not state.gadgets[gadget] then
		return false, "not owned"
	end
	if now < readyAt then
		return false, `on cooldown ({string.format("%.1f", readyAt - now)}s)`
	end
	return true, "ok"
end

-- Dash Boots: +20 speed for 4 s, applied server-side on the live character.
local function applyDashBoots(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local tuning = Config.Gadgets.DashBoots
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	for _, key in { "StunnedUntil", "RootedUntil" } do
		local untilTime = root and root:GetAttribute(key)
		if type(untilTime) == "number" and now < untilTime then
			return -- dashing must not break a stun or a trap root (2026-10-18 audit)
		end
	end
	local base = humanoid.WalkSpeed
	humanoid.WalkSpeed = base + tuning.burstBonus
	print(`[GadgetSystem] {player.Name} dash burst ({base} -> {humanoid.WalkSpeed}) for {tuning.burstSeconds}s`)
	task.delay(tuning.burstSeconds, function()
		local live = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if live and math.abs(live.WalkSpeed - (base + tuning.burstBonus)) < 0.01 then
			live.WalkSpeed = base
		end
	end)
end

function GadgetSystem.useGadget(player: Player, gadget: Types.Gadget, aimPosition: Vector3?): boolean
	local state = PlayerState.get(player)
	local playerCooldowns = useReadyAt[player]
	local readyAt = playerCooldowns and playerCooldowns[gadget] or 0
	local now = os.clock()
	local ok, reason = GadgetSystem.checkUse(state, gadget, readyAt, now)
	if not ok then
		print(`[GadgetSystem] {player.Name} {gadget} use rejected: {reason}`)
		return false
	end
	if gadget == "DashBoots" then
		applyDashBoots(player)
	elseif gadget == "SmokeBomb" then
		applySmokeBomb(player)
	elseif gadget == "Grapple" then
		applyGrapple(player, aimPosition)
	elseif gadget == "Lantern" then
		applyLantern(player)
	end
	useReadyAt[player] = useReadyAt[player] or {}
	-- Gadget tuning upgrades cut the cooldown (M8-08), at most in half.
	local cut = math.min(Perks.get(SkillService.stats(state), COOLDOWN_STAT[gadget] or ""), 0.5)
	useReadyAt[player][gadget] = now + Config.Gadgets[gadget].cooldown * (1 - cut)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	useReadyAt[player] = nil
end)

-- Wire remotes. Call once from Main.server.
function GadgetSystem.init()
	local KNOWN: { [string]: boolean } = { DashBoots = true, SmokeBomb = true, Grapple = true, Lantern = true }
	task.spawn(function()
		local buyRemote = Remotes.get("BuyGadget")
		buyRemote.OnServerEvent:Connect(function(player, gadget)
			-- M4-02: only known gadget names pass; anything else is dropped.
			if type(gadget) == "string" and KNOWN[gadget :: string] then
				GadgetSystem.buyGadget(player, gadget :: any)
			end
		end)
		local useRemote = Remotes.get("UseGadget")
		useRemote.OnServerEvent:Connect(function(player, gadget, aimPosition)
			if type(gadget) == "string" and KNOWN[gadget :: string] then
				local aim: Vector3? = nil
				if typeof(aimPosition) == "Vector3" then
					local v = aimPosition :: Vector3
					-- Reject NaN / huge vectors (2026-10-18 audit: NaN teleported you
					-- to NaN, where every distance check is false).
					if v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6 then
						aim = v
					end
				end
				GadgetSystem.useGadget(player, gadget :: any, aim)
			end
		end)
	end)
end

return GadgetSystem
