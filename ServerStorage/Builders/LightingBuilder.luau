--!strict
-- Lighting presets for the two phases (GDD 8, restyled in M5-02): bright stylized day
-- with haze, bloom and sun rays; readable purple-teal night with thick atmosphere.
-- The builder owns the presets and the tween application; DayNightCycle drives it.
-- Idempotent: creates its effect instances once and reuses them.
-- Skies come from ServerStorage.AssetLibrary/Skies (free Creator Store skyboxes).

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local LightingBuilder = {}

local CORRECTION_NAME = "GradeCorrection"
local ATMOSPHERE_NAME = "GroveAtmosphere"
local BLOOM_NAME = "GroveBloom"
local RAYS_NAME = "GroveSunRays"
local SKY_NAME = "ActiveSky"

type Preset = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	bloom: { [string]: any },
	rays: { [string]: any },
	correction: { [string]: any },
	sky: string,
}

local DAY: Preset = {
	lighting = {
		ClockTime = 14.5,
		Brightness = 3,
		Ambient = Color3.fromRGB(70, 70, 85),
		OutdoorAmbient = Color3.fromRGB(150, 150, 165),
		ColorShift_Top = Color3.fromRGB(255, 240, 215),
		ExposureCompensation = 0.1,
	},
	atmosphere = {
		Density = 0.28,
		Offset = 0.2,
		Color = Color3.fromRGB(200, 222, 240),
		Decay = Color3.fromRGB(110, 150, 185),
		Glare = 0.25,
		Haze = 1.1,
	},
	bloom = { Intensity = 0.55, Size = 24, Threshold = 1.7 },
	rays = { Intensity = 0.05, Spread = 0.6 },
	correction = { Brightness = 0.02, Contrast = 0.06, Saturation = 0.18, TintColor = Color3.fromRGB(255, 252, 245) },
	sky = "DaySky",
}

-- Night stays readable (top sims never go pitch black) but the haze closes in.
local NIGHT: Preset = {
	lighting = {
		ClockTime = 0,
		Brightness = 1.4,
		Ambient = Color3.fromRGB(70, 50, 105),
		OutdoorAmbient = Color3.fromRGB(120, 95, 170),
		ColorShift_Top = Color3.fromRGB(170, 150, 255),
		ExposureCompensation = -0.05,
	},
	atmosphere = {
		Density = 0.4,
		Offset = 0.15,
		Color = Color3.fromRGB(105, 60, 150), -- deep purple fog (GDD 8)
		Decay = Color3.fromRGB(60, 30, 100),
		Glare = 0,
		Haze = 0.8,
	},
	bloom = { Intensity = 0.9, Size = 28, Threshold = 0.95 }, -- neon cores pop at night
	rays = { Intensity = 0, Spread = 0.6 },
	correction = { Brightness = 0.02, Contrast = 0.15, Saturation = 0.05, TintColor = Color3.fromRGB(235, 215, 255) },
	sky = "NightSky",
}

-- Plot thresholds mark the entry gap: teal by day, hazard orange by night (GDD 8).
local THRESHOLD_DAY = Color3.fromRGB(60, 255, 220)
local THRESHOLD_NIGHT = Color3.fromRGB(255, 140, 40)

local function thresholdParts(): { BasePart }
	local found: { BasePart } = {}
	local root = workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local threshold = plot:FindFirstChild("Threshold")
			if threshold and threshold:IsA("BasePart") then
				table.insert(found, threshold :: BasePart)
			end
		end
	end
	return found
end

local function applyThresholds(preset: "Day" | "Night", duration: number)
	local color = if preset == "Day" then THRESHOLD_DAY else THRESHOLD_NIGHT
	for _, part in thresholdParts() do
		TweenService:Create(part, TweenInfo.new(duration), { Color = color }):Play()
	end
end

local function ensure<T>(name: string, className: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	if existing then
		existing:Destroy()
	end
	local effect = Instance.new(className :: any)
	effect.Name = name
	effect.Parent = Lighting
	return effect :: any
end

-- Swap the skybox (instant; done mid-transition so it hides inside the haze change).
local function setSky(skyName: string)
	local library = ServerStorage:FindFirstChild("AssetLibrary")
	local skies = library and library:FindFirstChild("Skies")
	local source = skies and skies:FindFirstChild(skyName)
	local current = Lighting:FindFirstChild(SKY_NAME)
	if current and current:GetAttribute("Preset") == skyName then
		return
	end
	-- Remove any other Sky (starter place default) so ours wins.
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") then
			child:Destroy()
		end
	end
	if source then
		local sky = source:Clone()
		sky.Name = SKY_NAME
		sky:SetAttribute("Preset", skyName)
		sky.Parent = Lighting
	else
		local sky = Instance.new("Sky")
		sky.Name = SKY_NAME
		sky:SetAttribute("Preset", skyName)
		sky.Parent = Lighting
	end
end

local function tween(instance: Instance, duration: number, goals: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Sine), goals :: any):Play()
end

-- Tweens Lighting + every post effect into a preset over `duration` seconds.
function LightingBuilder.apply(preset: "Day" | "Night", duration: number)
	local values = if preset == "Day" then DAY else NIGHT
	tween(Lighting, duration, values.lighting)
	tween(ensure(ATMOSPHERE_NAME, "Atmosphere"), duration, values.atmosphere)
	tween(ensure(BLOOM_NAME, "BloomEffect"), duration, values.bloom)
	tween(ensure(RAYS_NAME, "SunRaysEffect"), duration, values.rays)
	tween(ensure(CORRECTION_NAME, "ColorCorrectionEffect"), duration, values.correction)
	if duration <= 0 then
		setSky(values.sky)
	else
		task.delay(duration / 2, setSky, values.sky)
	end
	applyThresholds(preset, duration)
end

-- Blood Moon (M6-04): paint the running night red. The next applyDay restores everything.
function LightingBuilder.applyBloodMoon(duration: number)
	tween(ensure(ATMOSPHERE_NAME, "Atmosphere"), duration, {
		Color = Color3.fromRGB(150, 30, 40),
		Decay = Color3.fromRGB(90, 10, 20),
		Density = 0.45,
	})
	tween(ensure(CORRECTION_NAME, "ColorCorrectionEffect"), duration, {
		TintColor = Color3.fromRGB(255, 170, 170),
		Contrast = 0.2,
		Saturation = 0.15,
	})
	tween(Lighting, duration, {
		OutdoorAmbient = Color3.fromRGB(150, 70, 80),
		ColorShift_Top = Color3.fromRGB(255, 90, 90),
	})
end

function LightingBuilder.applyDay(duration: number)
	LightingBuilder.apply("Day", duration)
end

function LightingBuilder.applyNight(duration: number)
	LightingBuilder.apply("Night", duration)
end

-- Instant setup so Edit mode / fresh joins look right before the first tween.
-- Lighting.Technology is not script-accessible (needs a human click in Studio:
-- Lighting > Technology = Future; see LAUNCH_CHECKLIST), so it is not touched here.
function LightingBuilder.build(): string
	-- Unified lighting (replaces the deprecated, unscriptable Technology = Future):
	-- realistic light falloff with the best quality the device can afford.
	-- Only plugin/edit contexts may write these (game scripts lack the capability),
	-- so at runtime this is a no-op and the value saved in the place applies.
	pcall(function()
		Lighting.LightingStyle = Enum.LightingStyle.Realistic
		Lighting.PrioritizeLightingQuality = true
	end)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	-- Atmosphere owns the fog now; classic fog would fight it.
	Lighting.FogStart = 0
	Lighting.FogEnd = 100000
	ensure(ATMOSPHERE_NAME, "Atmosphere")
	LightingBuilder.apply("Day", 0)
	return "[LightingBuilder] day preset applied"
end

return LightingBuilder
