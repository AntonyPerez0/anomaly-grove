--!strict
-- Pedestal world builder: one generator pedestal per plot (slot 1) at its anchor.
-- Idempotent: wipes PedestalN models in every plot and rebuilds slot 1. Purchased
-- pedestals (slots 2..8) are added by later milestones through the same builder.

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PedestalBuilder = {}

local COLORS = {
	base = Color3.fromRGB(150, 144, 136),
	column = Color3.fromRGB(96, 98, 112),
	trim = Color3.fromRGB(210, 170, 90),
	pad = Color3.fromRGB(120, 255, 230),
}

local function buildPedestal(anchor: BasePart, slot: number): Model
	local model = Instance.new("Model")
	model.Name = "Pedestal" .. slot

	local function part(name: string, size: Vector3, yOffset: number, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = anchor.CFrame * CFrame.new(0, yOffset, 0)
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	-- Round decorative piece (cylinder axis rotated to world Y).
	local function disc(
		name: string,
		height: number,
		diameter: number,
		yOffset: number,
		color: Color3,
		material: Enum.Material
	): Part
		local p = part(name, Vector3.new(height, diameter, diameter), yOffset, color, material)
		p.Shape = Enum.PartType.Cylinder
		p.CFrame = anchor.CFrame * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.rad(90))
		return p
	end

	-- The anchor's top face sits at anchor y + 0.5 (anchors are 1 stud tall).
	-- Gameplay parts (Base/Column/Pad) keep their names; Pad stays an unrotated block
	-- because cores and orbs sit at Pad.CFrame + Y.
	local top = 0.5
	disc("Plinth", 0.5, 5.2, top + 0.25, COLORS.base, Enum.Material.Cobblestone)
	part("Base", Vector3.new(3.2, 0.7, 3.2), top + 0.5 + 0.35, COLORS.column, Enum.Material.Slate)
	part("Column", Vector3.new(1.8, 2.2, 1.8), top + 1.2 + 1.1, COLORS.column, Enum.Material.Slate)
	disc("Collar", 0.4, 3.4, top + 3.4 + 0.2, COLORS.trim, Enum.Material.Metal)
	local pad = part("Pad", Vector3.new(2.8, 0.3, 2.8), top + 3.4 + 0.4 + 0.15, COLORS.pad, Enum.Material.Neon)
	pad.Transparency = 0.15
	local ring = disc("GlowRing", 0.15, 5.6, top + 0.55, COLORS.pad, Enum.Material.Neon)
	ring.Transparency = 0.45
	ring.CanCollide = false
	ring.CanQuery = false
	model.PrimaryPart = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlacePrompt"
	prompt.ActionText = "Place Seed"
	prompt.ObjectText = "Generator Pedestal"
	prompt.HoldDuration = Config.Incubation.PlaceHoldTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	model.Parent = anchor.Parent
	return model
end

-- Builds (or rebuilds) the slot-1 pedestal for every plot. Returns how many exist.
function PedestalBuilder.build(): string
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plotsRoot = root and root:FindFirstChild("Plots")
	if not plotsRoot then
		error("MapBuilder.build() must run before PedestalBuilder.build()", 2)
	end
	local built = 0
	for _, plot in plotsRoot:GetChildren() do
		if not plot:IsA("Folder") then
			continue
		end
		for _, child in plot:GetChildren() do
			if child:IsA("Model") and string.match(child.Name, "^Pedestal%d+$") then
				child:Destroy()
			end
		end
		local anchor = plot:FindFirstChild("PedestalSlot1")
		if anchor and anchor:IsA("BasePart") then
			buildPedestal(anchor, 1)
			built += 1
		end
	end
	return `[PedestalBuilder] built {built} pedestals`
end

-- Vault Lock visual (M3-04): a forcefield dome marking the un-stealable pedestal.
-- Idempotent: adding twice keeps one shield; locked=false removes it.
function PedestalBuilder.setVaultLockVisual(plotIndex: number, slot: number, locked: boolean): boolean
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plotsRoot = root and root:FindFirstChild("Plots")
	local folder = plotsRoot and plotsRoot:FindFirstChild("Plot" .. (plotIndex + 1))
	local model = folder and folder:FindFirstChild("Pedestal" .. slot)
	if not model or not model:IsA("Model") then
		return false
	end
	local old = model:FindFirstChild("VaultShield")
	if not locked then
		if old then
			old:Destroy()
		end
		return true
	end
	if old then
		return true
	end
	local pad = model.PrimaryPart
	if not pad or not pad:IsA("BasePart") then
		return false
	end
	local shield = Instance.new("Part")
	shield.Name = "VaultShield"
	shield.Shape = Enum.PartType.Ball
	shield.Size = Vector3.new(4.2, 4.2, 4.2)
	shield.CFrame = pad.CFrame * CFrame.new(0, 0.6, 0)
	shield.Material = Enum.Material.ForceField
	shield.Color = Color3.fromRGB(120, 90, 255)
	shield.Anchored = true
	shield.CanCollide = false
	shield.CanQuery = false
	shield.Parent = model
	return true
end

-- Builds one pedestal for a specific plot slot (purchase path, M2-06).
-- No-op if the slot already has its model. Returns whether a model exists after.
function PedestalBuilder.buildForPlot(plotIndex: number, slot: number): boolean
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plotsRoot = root and root:FindFirstChild("Plots")
	local plot = plotsRoot and plotsRoot:FindFirstChild("Plot" .. (plotIndex + 1))
	if not plot then
		return false
	end
	local existing = plot:FindFirstChild("Pedestal" .. slot)
	if existing and existing:IsA("Model") then
		return true
	end
	local anchor = plot:FindFirstChild("PedestalSlot" .. slot)
	if not anchor or not anchor:IsA("BasePart") then
		return false
	end
	buildPedestal(anchor, slot)
	return true
end

return PedestalBuilder
