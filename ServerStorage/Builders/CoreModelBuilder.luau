--!strict
-- Core + seed visuals on pedestals (M5-07): a glowing gem sized by rarity tier,
-- sparkle aura (gold glitter when mutated), one light, and an overhead BillboardGui
-- label: rarity / mutation / "$X/s" (or a hatch countdown for incubating seeds).
-- The orb part keeps the legacy names "CoreOrb" / "SeedOrb" other systems look up.
-- Gems carry the CollectionService tag "SpinCore"; the client spins/bobs them locally.

local CollectionService = game:GetService("CollectionService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Progression = require(game:GetService("ReplicatedStorage").Shared.Progression)

local CoreModelBuilder = {}

CoreModelBuilder.SPIN_TAG = "SpinCore"
local LABEL_NAME = "CoreLabel"
local HOVER = 2.15 -- studs above the pad top (matches the old CORE_CLEARANCE + 0.15)

local TEXT_STROKE = Color3.fromRGB(20, 14, 30)
local RATE_COLOR = Color3.fromRGB(120, 255, 120)
local MUTATION_COLOR = Color3.fromRGB(255, 215, 90)

local function textLine(parent: Instance, name: string, order: number, height: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, height)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = TEXT_STROKE
	stroke.Parent = label
	return label
end

local function buildLabel(orb: BasePart, title: string, titleColor: Color3, mutationText: string?, rateText: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = LABEL_NAME
	gui.Size = UDim2.fromScale(7, 3) -- world-sized: shrinks naturally with distance
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = gui
	if mutationText then
		textLine(gui, "Mutation", 1, 0.28, MUTATION_COLOR).Text = mutationText
	end
	textLine(gui, "Title", 2, 0.4, titleColor).Text = title
	textLine(gui, "Rate", 3, 0.32, RATE_COLOR).Text = rateText
	gui.Parent = orb
end

local function sparkles(orb: BasePart, color: Color3, rate: number, gold: boolean)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Aura"
	emitter.Color = if gold
		then ColorSequence.new(MUTATION_COLOR, Color3.new(1, 1, 1))
		else ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(1, 2.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = orb
end

local function clear(model: Model)
	for _, name in { "SeedOrb", "CoreOrb" } do
		local old = model:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

local function formatRate(rate: number): string
	if rate >= 1000 then
		return `${Progression.format(rate)}/s` -- K .. Dc (M8-01)
	elseif rate >= 10 or math.abs(rate - math.floor(rate)) < 0.05 then
		return string.format("$%d/s", math.floor(rate + 0.5))
	end
	return string.format("$%.1f/s", rate)
end
CoreModelBuilder.formatRate = formatRate

export type CoreSpec = {
	kind: "seed" | "core",
	color: Color3,
	rarity: string?,
	mutation: string?,
	rate: number?, -- cash per second (cores)
	secondsLeft: number?, -- hatch countdown (seeds)
	boosted: boolean?, -- Grove Heart seed
	level: number?, -- M8-04 pedestal upgrade level (shown on cores above 1)
	title: string?, -- M8-05 seed title override ("Fertile Crate")
	size: string?, -- M9-01 core size (Tiny/Big/Huge/Titanic); nil = Normal
}

-- Replace whatever sits on the pedestal with the described orb. kind "none" clears.
function CoreModelBuilder.attach(model: Model?, spec: CoreSpec?)
	if not model or not model.PrimaryPart then
		return
	end
	clear(model)
	if not spec then
		return
	end
	local pad = model.PrimaryPart :: BasePart
	local orb = Instance.new("Part")
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Color = spec.color
	orb.Material = Enum.Material.Neon

	if spec.kind == "seed" then
		orb.Name = "SeedOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(1.2, 1.2, 1.2)
		orb.Transparency = 0.1
		orb.CFrame = pad.CFrame * CFrame.new(0, HOVER - 0.4, 0)
		sparkles(orb, spec.color, 4, spec.boosted == true)
		buildLabel(
			orb,
			spec.title or (if spec.boosted then "Heart Seed" else "Seed"),
			Color3.fromRGB(200, 255, 220),
			nil,
			`Hatching {math.max(0, math.ceil(spec.secondsLeft or 0))}s`
		)
	else
		orb.Name = "CoreOrb"
		local info = spec.rarity and Config.Rarities[spec.rarity :: any]
		local tier = if info then info.tier else 1
		local sizeDef = if spec.size then Config.Sizes.Defs[spec.size] else nil
		local baseSize = 1.3 + tier * 0.22
		local s = baseSize * (if sizeDef then sizeDef.scale else 1)
		orb.Size = Vector3.new(s, s, s)
		orb.Transparency = 0.05
		-- Diamond silhouette: a cube stood on its corner (the client spins it on Y).
		orb.CFrame = pad.CFrame
			* CFrame.new(0, HOVER + 0.2 + tier * 0.1 + (s - baseSize) * 0.75, 0) -- bigger gems float higher
			* CFrame.Angles(math.rad(45), 0, math.rad(45))
		sparkles(orb, spec.color, 4 + tier * 3, spec.mutation ~= nil)
		local mutationText: string? = nil
		if spec.mutation then
			local m = Config.Mutations[spec.mutation :: any]
			mutationText = `{string.upper(spec.mutation)} x{if m then m.multiplier else 1}`
		end
		local level = spec.level or 1
		buildLabel(
			orb,
			(if sizeDef and spec.size ~= "Normal" then `{string.upper(spec.size :: string)} ` else "")
				.. (spec.rarity or "Core")
				.. (if level > 1 then ` Lv{level}` else ""),
			if info then info.color else spec.color,
			mutationText,
			formatRate(spec.rate or 0)
		)
		-- Big gems push their label up so it never sits inside the gem.
		local label = orb:FindFirstChild(LABEL_NAME)
		if label and label:IsA("BillboardGui") then
			label.StudsOffsetWorldSpace = Vector3.new(0, 3.2 + (s - baseSize) * 0.6, 0)
		end
	end

	local light = Instance.new("PointLight")
	light.Color = spec.color
	light.Brightness = if spec.kind == "core" then 1.5 else 0.8
	light.Range = 14
	light.Shadows = false
	light.Parent = orb
	CollectionService:AddTag(orb, CoreModelBuilder.SPIN_TAG)
	orb.Parent = model
end

-- Cheap 1 Hz label refresh: only writes when the text actually changes.
function CoreModelBuilder.setRateText(model: Model?, text: string)
	if not model then
		return
	end
	local orb = model:FindFirstChild("CoreOrb") or model:FindFirstChild("SeedOrb")
	local gui = orb and orb:FindFirstChild(LABEL_NAME)
	local rate = gui and gui:FindFirstChild("Rate")
	if rate and rate:IsA("TextLabel") and rate.Text ~= text then
		rate.Text = text
	end
end

return CoreModelBuilder
