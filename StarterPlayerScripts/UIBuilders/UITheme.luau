--!strict
-- Shared UI look (M5-09): chunky FredokaOne text with dark outlines, gradient
-- buttons with a press bounce, rounded panels. Every screen builds through here so
-- the game reads as one studio-made product.

local TweenService = game:GetService("TweenService")

local FxSounds = require(script.Parent:WaitForChild("FxSounds"))
local Progression = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Progression"))

local UITheme = {}

UITheme.FONT = Enum.Font.FredokaOne
UITheme.COLORS = {
	panel = Color3.fromRGB(34, 28, 52),
	panelDeep = Color3.fromRGB(24, 20, 38),
	stroke = Color3.fromRGB(16, 12, 26),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(190, 184, 210),
	green = Color3.fromRGB(80, 220, 110),
	greenDark = Color3.fromRGB(40, 160, 70),
	blue = Color3.fromRGB(70, 160, 255),
	blueDark = Color3.fromRGB(40, 100, 220),
	gold = Color3.fromRGB(255, 205, 70),
	goldDark = Color3.fromRGB(230, 150, 30),
	red = Color3.fromRGB(255, 90, 90),
	redDark = Color3.fromRGB(200, 50, 60),
	purple = Color3.fromRGB(170, 110, 255),
	purpleDark = Color3.fromRGB(110, 60, 210),
	grey = Color3.fromRGB(120, 118, 132),
	greyDark = Color3.fromRGB(80, 78, 92),
	teal = Color3.fromRGB(70, 240, 210),
	tealDark = Color3.fromRGB(30, 170, 160),
}

export type ButtonStyle = "green" | "blue" | "gold" | "red" | "purple" | "grey" | "teal"

function UITheme.corner(parent: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

function UITheme.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2.5
	s.Color = color or UITheme.COLORS.stroke
	s.ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton")
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Top-to-bottom gradient from `top` to `bottom`.
function UITheme.gradient(parent: GuiObject, top: Color3, bottom: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Outlined text label (white + dark stroke reads on any background).
function UITheme.label(parent: Instance, name: string, text: string, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = UITheme.FONT
	l.TextScaled = true
	l.TextColor3 = color or UITheme.COLORS.text
	l.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UITheme.COLORS.stroke
	stroke.Parent = l
	l.Parent = parent
	return l
end

-- Rounded panel with a dark border.
function UITheme.panel(parent: Instance, name: string, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color or UITheme.COLORS.panel
	f.BorderSizePixel = 0
	UITheme.corner(f, 16)
	UITheme.stroke(f, 3)
	f.Parent = parent
	return f
end

local STYLE_COLORS: { [ButtonStyle]: { Color3 } } = {
	green = { UITheme.COLORS.green, UITheme.COLORS.greenDark },
	blue = { UITheme.COLORS.blue, UITheme.COLORS.blueDark },
	gold = { UITheme.COLORS.gold, UITheme.COLORS.goldDark },
	red = { UITheme.COLORS.red, UITheme.COLORS.redDark },
	purple = { UITheme.COLORS.purple, UITheme.COLORS.purpleDark },
	grey = { UITheme.COLORS.grey, UITheme.COLORS.greyDark },
	teal = { UITheme.COLORS.teal, UITheme.COLORS.tealDark },
}

-- Re-skin an existing themed button (affordable -> green, locked -> grey...).
function UITheme.setStyle(button: GuiButton, style: ButtonStyle)
	local colors = STYLE_COLORS[style]
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = button:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(colors[1], colors[2])
	end
end

-- Chunky gradient button with a press bounce (scale 0.92 -> 1).
function UITheme.button(parent: Instance, name: string, text: string, style: ButtonStyle): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Font = UITheme.FONT
	b.TextScaled = true
	b.TextColor3 = UITheme.COLORS.text
	b.Text = text
	UITheme.corner(b, 12)
	local colors = STYLE_COLORS[style]
	UITheme.gradient(b, colors[1], colors[2])
	local border = Instance.new("UIStroke")
	border.Name = "Border"
	border.Thickness = 3
	border.Color = UITheme.COLORS.stroke
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = b
	local textStroke = Instance.new("UIStroke")
	textStroke.Name = "TextStroke"
	textStroke.Thickness = 2
	textStroke.Color = UITheme.COLORS.stroke
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = b
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = b
	local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.92 }):Play()
	end)
	b.Activated:Connect(function()
		FxSounds.uiClick()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	b.Parent = parent
	return b
end

-- Pop-in animation for modals (scale 0.85 -> 1 with a little overshoot).
function UITheme.popIn(frame: GuiObject)
	local scale = frame:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "PopScale"
		created.Parent = frame
		scale = created
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- 1234567 -> "1,234,567" (cash readouts).
function UITheme.commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return if n < 0 then "-" .. formatted else formatted
end

-- Short number formatting for prices / cash: 950, 9,950, 12.3K ... 1.2Dc (M8-01).
function UITheme.short(n: number): string
	return Progression.format(n)
end

return UITheme
