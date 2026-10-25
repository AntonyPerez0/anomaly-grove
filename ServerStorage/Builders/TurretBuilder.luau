--!strict
-- Turret builder (M3-01): a small auto-turret model placed on plot corners.
-- Idempotent per slot; the DefenseSystem drives aiming and damage.

local TurretBuilder = {}

local COLORS = {
	base = Color3.fromRGB(70, 74, 82),
	head = Color3.fromRGB(50, 54, 60),
	barrelTip = Color3.fromRGB(60, 255, 220),
}

-- Builds a turret model at an anchor part. Returns the Model (PrimaryPart = Head).
function TurretBuilder.create(anchor: BasePart, index: number): Model
	local model = Instance.new("Model")
	model.Name = "Turret" .. index

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.4, 1.2, 2.4)
	base.CFrame = anchor.CFrame * CFrame.new(0, 1.6, 0)
	base.Color = COLORS.base
	base.Material = Enum.Material.Metal
	base.Anchored = true
	base.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.8, 1.4, 1.8)
	head.Color = COLORS.head
	head.Material = Enum.Material.Metal
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = base.CFrame * CFrame.new(0, 1.3, 0)
	head.Parent = model

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.5, 0.5, 2.2)
	barrel.Color = COLORS.head
	barrel.Material = Enum.Material.Metal
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.CFrame = head.CFrame * CFrame.new(0, 0.2, -1.4)
	barrel.Parent = model

	local tip = Instance.new("Part")
	tip.Name = "BarrelTip"
	tip.Size = Vector3.new(0.55, 0.55, 0.3)
	tip.Color = COLORS.barrelTip
	tip.Material = Enum.Material.Neon
	tip.Anchored = true
	tip.CanCollide = false
	tip.CFrame = barrel.CFrame * CFrame.new(0, 0, -1.2)
	tip.Parent = model
	barrel = barrel :: Part
	tip = tip :: Part

	model.PrimaryPart = head
	model.Parent = anchor.Parent
	return model
end

-- Aims the head+barrel at a world position.
function TurretBuilder.aim(model: Model, position: Vector3)
	local head = model.PrimaryPart
	if not head then
		return
	end
	local barrel = model:FindFirstChild("Barrel")
	local tip = model:FindFirstChild("BarrelTip")
	local look = CFrame.lookAt(head.Position, Vector3.new(position.X, head.Position.Y, position.Z))
	head.CFrame = look
	if barrel and barrel:IsA("BasePart") then
		barrel.CFrame = look * CFrame.new(0, 0.2, -1.4)
	end
	if tip and tip:IsA("BasePart") then
		tip.CFrame = look * CFrame.new(0, 0.2, -2.6)
	end
end

return TurretBuilder
