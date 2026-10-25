--!strict
-- Weather visuals (M9-06), client-only and driven by the server's WorldEvent
-- attribute: rain around the camera (Rain / Thunderstorm), a darker sky in a
-- storm, and slow green-violet aurora ribbons high over the grove at night.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local rainPart: BasePart? = nil
local aurora: Folder? = nil
local follow: RBXScriptConnection? = nil
local storm: ColorCorrectionEffect? = nil

local function stopRain()
	if follow then
		follow:Disconnect()
		follow = nil
	end
	if rainPart then
		rainPart:Destroy()
		rainPart = nil
	end
end

local function startRain(heavy: boolean)
	stopRain()
	local part = Instance.new("Part")
	part.Name = "RainEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(90, 1, 90)
	local rain = Instance.new("ParticleEmitter")
	rain.Color = ColorSequence.new(Color3.fromRGB(190, 215, 255))
	rain.LightEmission = 0.3
	rain.Transparency = NumberSequence.new(0.25)
	rain.Size = NumberSequence.new(0.22)
	rain.Lifetime = NumberRange.new(0.9, 1.1)
	rain.Speed = NumberRange.new(55, 65)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(4, 4)
	rain.Rate = if heavy then 900 else 500
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Squash = NumberSequence.new(3)
	rain.Parent = part
	part.Parent = Workspace
	rainPart = part
	follow = RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera and rainPart then
			rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
		end
	end)
end

local function setStorm(on: boolean)
	if on and not storm then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "StormGrade"
		effect.Parent = Lighting
		storm = effect
		TweenService:Create(effect, TweenInfo.new(3), { Brightness = -0.08, Saturation = -0.25 }):Play()
	elseif not on and storm then
		local effect = storm :: ColorCorrectionEffect
		storm = nil
		local tween = TweenService:Create(effect, TweenInfo.new(3), { Brightness = 0, Saturation = 0 })
		tween.Completed:Connect(function()
			effect:Destroy()
		end)
		tween:Play()
	end
end

local function setAurora(on: boolean)
	if aurora then
		aurora:Destroy()
		aurora = nil
	end
	if not on then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Aurora"
	local colors = {
		ColorSequence.new(Color3.fromRGB(80, 255, 170), Color3.fromRGB(140, 90, 255)),
		ColorSequence.new(Color3.fromRGB(120, 255, 220), Color3.fromRGB(80, 160, 255)),
	}
	for i = 1, 5 do
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		local z = -300 + i * 110
		anchor.CFrame = CFrame.new(0, 260 + i * 12, z)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-500, 0, 0)
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(500, 0, 0)
		a1.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = colors[(i % 2) + 1]
		beam.Width0 = 40
		beam.Width1 = 28
		beam.CurveSize0 = 120
		beam.CurveSize1 = -120
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Segments = 20
		beam.Parent = anchor
		anchor.Parent = folder
	end
	folder.Parent = Workspace
	aurora = folder
end

local function apply()
	local event = Workspace:GetAttribute("WorldEvent")
	if event == "Rain" or event == "Thunderstorm" then
		startRain(event == "Thunderstorm")
	else
		stopRain()
	end
	setStorm(event == "Thunderstorm")
	setAurora(event == "Aurora")
end

Workspace:GetAttributeChangedSignal("WorldEvent"):Connect(apply)
apply()
