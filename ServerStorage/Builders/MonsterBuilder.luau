--!strict
-- Night monster rigs. A single-part humanoid root (invisible ball, does the physics)
-- driven by MonsterAI's chase loop, wearing a welded, massless visual model from
-- ServerStorage.AssetLibrary/Monsters (M5-08: AI-generated Fogling imp + bark-and-moss
-- Grove Stalker). A soft outline Highlight keeps them readable in the night fog; the
-- Stalker windup flashes it red (MonsterAI.setStalkerGlow).
-- 2026-10-18: + Wisp (floating seed thief), Moss Golem (slam) and Mire Spitter
-- (spore lobber), also AI-generated meshes in AssetLibrary/Monsters.

local ServerStorage = game:GetService("ServerStorage")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)

local MonsterBuilder = {}

export type MonsterKind = "Fogling" | "Stalker" | "Wisp" | "Golem" | "Spitter" | "Warden"

type Look = {
	size: number, -- invisible physics ball diameter
	hip: number, -- Humanoid.HipHeight
	color: Color3, -- fallback blob colour
	eye: Color3, -- eye light + outline colour
	eyeHeight: number,
	float: boolean, -- visual hovers at the ball instead of standing on the ground
	yaw: number?, -- extra turn so the mesh faces the walking direction
	visual: string?, -- library model to wear (default: the kind name)
	visualScale: number?, -- extra scale on that model
	fill: Color3?, -- resting Highlight fill (bosses read as different from their base kind)
}

local LOOKS: { [string]: Look } = {
	Fogling = {
		size = 2.2,
		hip = 0.8,
		color = Color3.fromRGB(60, 40, 90),
		eye = Color3.fromRGB(140, 255, 220),
		eyeHeight = 0.6,
		float = false,
	},
	Stalker = {
		size = 4,
		hip = 1.2,
		color = Color3.fromRGB(25, 15, 40),
		eye = Color3.fromRGB(255, 60, 60),
		eyeHeight = 3.5,
		float = false,
	},
	Wisp = {
		size = 1.8,
		hip = 3,
		color = Color3.fromRGB(150, 230, 255),
		eye = Color3.fromRGB(170, 240, 255),
		eyeHeight = 1.4,
		float = true,
	},
	Golem = {
		size = 4.5,
		hip = 1.6,
		color = Color3.fromRGB(95, 110, 85),
		eye = Color3.fromRGB(255, 180, 70),
		eyeHeight = 5.5,
		float = false,
	},
	-- M9-03 boss: a giant, darkened Moss Golem.
	Warden = {
		size = 9,
		hip = 4,
		color = Color3.fromRGB(40, 30, 60),
		eye = Color3.fromRGB(190, 90, 255),
		eyeHeight = 10,
		float = false,
		visual = "Golem",
		visualScale = 1.7,
		fill = Color3.fromRGB(120, 50, 200),
	},
	Spitter = {
		size = 3,
		hip = 0.6,
		color = Color3.fromRGB(140, 90, 200),
		eye = Color3.fromRGB(150, 255, 110),
		eyeHeight = 2.2,
		float = false,
	},
}

MonsterBuilder.GLOW_NAME = "Glow"

local function eyeLight(root: BasePart, color: Color3, height: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "EyeLight"
	attachment.Position = Vector3.new(0, height, -0.6)
	attachment.Parent = root
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = 10
	light.Shadows = false
	light.Parent = attachment
end

-- Clone the library visual and weld it to the root so its feet touch the ground.
local function dress(model: Model, root: BasePart, kind: string, groundOffset: number, yaw: number?): boolean
	local look = LOOKS[kind]
	local library = ServerStorage:FindFirstChild("AssetLibrary")
	local folder = library and library:FindFirstChild("Monsters")
	local source = folder and folder:FindFirstChild(look and look.visual or kind)
	if not source or not source:IsA("Model") then
		return false
	end
	local visual = source:Clone()
	visual.Name = "Visual"
	if look and look.visualScale then
		visual:ScaleTo(visual:GetScale() * look.visualScale)
	end
	-- Library pivots are bottom-centre; face the root's forward (-Z).
	visual:PivotTo(root.CFrame * CFrame.new(0, -groundOffset, 0) * CFrame.Angles(0, yaw or 0, 0))
	for _, d in visual:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
	visual.Parent = model
	return true
end

-- Builds a monster of `kind` at `position`.
function MonsterBuilder.create(kind: MonsterKind, position: Vector3): Model
	local spec = (Config.Monsters :: any)[kind]
	local look = LOOKS[kind]
	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Damage", spec.Damage)

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * look.size
	body.Color = look.color
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = CFrame.new(position)
	body.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = spec.Health
	humanoid.Health = spec.Health
	humanoid.WalkSpeed = spec.Speed
	humanoid.HipHeight = look.hip
	humanoid.Parent = model

	local eyeColor = look.eye
	local groundOffset = if look.float then body.Size.Y / 2 else humanoid.HipHeight + body.Size.Y / 2
	if dress(model, body, kind, groundOffset, look.yaw) then
		body.Transparency = 1
		eyeLight(body, eyeColor, look.eyeHeight)
	else
		-- Library missing (fresh place): fall back to the visible blob.
		body.Transparency = 0.15
		eyeLight(body, eyeColor, 0.4)
	end

	local glow = Instance.new("Highlight")
	glow.Name = MonsterBuilder.GLOW_NAME
	glow.FillColor = look.fill or eyeColor
	glow.FillTransparency = if look.fill then 0.55 else 1
	glow.OutlineColor = eyeColor
	glow.OutlineTransparency = 0.55
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = model

	model.PrimaryPart = body
	-- Monsters pass through decoration (trees/rocks) so straight-line chases never snag.
	CollisionGroups.ensure()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = CollisionGroups.Monsters
		end
	end
	model.Parent = workspace
	body:SetNetworkOwner(nil) -- server-authoritative movement
	return model
end

-- Windup telegraph (Stalker lunge red, Golem slam orange): fill + solid outline while on.
function MonsterBuilder.setTelegraph(model: Model, on: boolean, color: Color3?)
	local glow = model:FindFirstChild(MonsterBuilder.GLOW_NAME)
	local kind = model:GetAttribute("Kind")
	local look = LOOKS[if type(kind) == "string" then kind else "Stalker"] or LOOKS.Stalker
	local flash = color or Config.Monsters.StalkerTelegraphColor
	if glow and glow:IsA("Highlight") then
		glow.FillColor = if on then flash else (look.fill or flash)
		glow.FillTransparency = if on then 0.45 elseif look.fill then 0.55 else 1
		glow.OutlineColor = if on then flash else look.eye
		glow.OutlineTransparency = if on then 0 else 0.55
	end
end

return MonsterBuilder
