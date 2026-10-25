--!strict
-- Tutorial toasts (M3-10): a pill under the phase bar that slides in, holds and
-- slides out. One ScreenGui hosts every toast; each toast destroys itself.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ToastBuilder = {}

local HOLD_SECONDS = 4

function ToastBuilder.show(text: string)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("Toasts")
	if not gui or not gui:IsA("ScreenGui") then
		local created = Instance.new("ScreenGui")
		created.Name = "Toasts"
		created.ResetOnSpawn = false
		created.DisplayOrder = 40
		created.Parent = playerGui
		gui = created
	end

	-- GDD 9: at most 2 toasts visible; drop the oldest when a third arrives.
	local existing: { TextLabel } = {}
	for _, child in (gui :: ScreenGui):GetChildren() do
		if child:IsA("TextLabel") and child.Name == "Toast" then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.AbsolutePosition.Y < b.AbsolutePosition.Y
	end)
	while #existing >= 2 do
		local oldest = table.remove(existing, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.fromScale(0.5, 0.09)
	toast.Size = UDim2.fromOffset(320, 44)
	toast.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(120, 255, 220)
	toast.Font = Enum.Font.FredokaOne
	toast.TextScaled = true
	toast.Text = text
	toast.Visible = false
	toast.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = toast
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 255, 220)
	stroke.Transparency = 0.4
	stroke.Parent = toast

	-- Slide in from above, hold, slide out, clean up.
	toast.Position = UDim2.fromScale(0.5, 0.02)
	toast.Visible = true
	TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.09),
	}):Play()
	task.delay(HOLD_SECONDS, function()
		local out = TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, -0.1),
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		out:Play()
		out.Completed:Wait()
		toast:Destroy()
	end)
end

return ToastBuilder
