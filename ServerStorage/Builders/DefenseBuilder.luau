--!strict
-- Defense builders (M3-02): laser door across the plot's threshold gap and
-- trap tiles on the pedestal approach. Models carry their recharge visuals.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local DefenseBuilder = {}

local COLORS = {
	laser = Color3.fromRGB(255, 70, 70),
	trapArmed = Color3.fromRGB(255, 170, 60),
	trapRecharging = Color3.fromRGB(90, 94, 102),
}

-- Laser door: a neon beam part spanning the threshold gap.
function DefenseBuilder.createLaserDoor(threshold: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "LaserDoor"

	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Size = Vector3.new(Config.LaserDoor.Thickness, 4, 1)
	beam.Color = COLORS.laser
	beam.Material = Enum.Material.Neon
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CFrame = threshold.CFrame * CFrame.new(0, 2.5, 0)
	beam.Parent = model

	local light = Instance.new("PointLight")
	light.Color = COLORS.laser
	light.Brightness = 2
	light.Range = 10
	light.Parent = beam

	model.PrimaryPart = beam
	model.Parent = threshold.Parent
	return model
end

-- Trap tile: a flat plate near a pedestal approach; dims while recharging.
function DefenseBuilder.createTrapTile(anchor: BasePart, index: number): Model
	local model = Instance.new("Model")
	model.Name = "TrapTile" .. index

	local tile = Instance.new("Part")
	tile.Name = "Plate"
	tile.Size = Vector3.new(5, 0.3, 5)
	tile.Color = COLORS.trapArmed
	tile.Material = Enum.Material.Neon
	tile.Anchored = true
	tile.CanCollide = false
	tile.CFrame = anchor.CFrame * CFrame.new(0, 0.6, 0)
	tile.Parent = model
	model.PrimaryPart = tile

	model:SetAttribute("Recharging", false)
	model.Parent = anchor.Parent
	return model
end

-- Trap visuals for recharge state.
function DefenseBuilder.setTrapRecharging(model: Model, recharging: boolean)
	local plate = model:FindFirstChild("Plate")
	if plate and plate:IsA("BasePart") then
		plate.Color = if recharging then COLORS.trapRecharging else COLORS.trapArmed
		plate.Material = if recharging then Enum.Material.SmoothPlastic else Enum.Material.Neon
	end
	model:SetAttribute("Recharging", recharging)
end

return DefenseBuilder
