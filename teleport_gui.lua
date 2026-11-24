-- LocalScript → положи в StarterPlayer > StarterPlayerScripts
-- Автотелепорт каждые 4 секунды на заданные координаты

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ⚙️ Настройки
local TARGET = Vector3.new(-202, 800, -88)
local INTERVAL = 4

local enabled = false
local timeLeft = INTERVAL

-- 🖼️ GUI
local gui = Instance.new("ScreenGui")
gui.Name = "AutoTeleportGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(260, 190)
main.Position = UDim2.new(0.5, -130, 0.5, -95)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 90, 255)
stroke.Thickness = 2
stroke.Parent = main

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(34, 30, 56), Color3.fromRGB(18, 18, 28))
grad.Rotation = 90
grad.Parent = main

-- Заголовок
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 36)
title.Position = UDim2.fromOffset(14, 4)
title.BackgroundTransparency = 1
title.Text = "⚡ Auto Teleport"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

-- Кнопка закрытия
local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(28, 28)
close.Position = UDim2.new(1, -38, 0, 8)
close.BackgroundColor3 = Color3.fromRGB(220, 60, 80)
close.Text = "✕"
close.Font = Enum.Font.GothamBold
close.TextSize = 14
close.TextColor3 = Color3.new(1, 1, 1)
close.AutoButtonColor = true
close.Parent = main
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

-- Координаты
local coords = Instance.new("TextLabel")
coords.Size = UDim2.new(1, -28, 0, 22)
coords.Position = UDim2.fromOffset(14, 46)
coords.BackgroundTransparency = 1
coords.Text = string.format("📍 X: %d  Y: %d  Z: %d", TARGET.X, TARGET.Y, TARGET.Z)
coords.Font = Enum.Font.Gotham
coords.TextSize = 14
coords.TextColor3 = Color3.fromRGB(180, 180, 210)
coords.TextXAlignment = Enum.TextXAlignment.Left
coords.Parent = main

-- Таймер
local timer = Instance.new("TextLabel")
timer.Size = UDim2.new(1, -28, 0, 22)
timer.Position = UDim2.fromOffset(14, 70)
timer.BackgroundTransparency = 1
timer.Text = "⏱ Выключено"
timer.Font = Enum.Font.Gotham
timer.TextSize = 14
timer.TextColor3 = Color3.fromRGB(180, 180, 210)
timer.TextXAlignment = Enum.TextXAlignment.Left
timer.Parent = main

-- Кнопка ВКЛ/ВЫКЛ
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -28, 0, 40)
toggle.Position = UDim2.fromOffset(14, 102)
toggle.BackgroundColor3 = Color3.fromRGB(90, 70, 220)
toggle.Text = "▶ Включить"
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 16
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.AutoButtonColor = true
toggle.Parent = main
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 10)

-- Кнопка "Телепорт сейчас"
local now = Instance.new("TextButton")
now.Size = UDim2.new(1, -28, 0, 32)
now.Position = UDim2.fromOffset(14, 148)
now.BackgroundColor3 = Color3.fromRGB(45, 45, 66)
now.Text = "Телепорт сейчас"
now.Font = Enum.Font.GothamMedium
now.TextSize = 14
now.TextColor3 = Color3.fromRGB(220, 220, 240)
now.AutoButtonColor = true
now.Parent = main
Instance.new("UICorner", now).CornerRadius = UDim.new(0, 10)

-- 🖱️ Перетаскивание окна (мышь и тач)
do
	local dragging, dragStart, startPos
	main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- 🚀 Телепорт
local function teleport()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(TARGET)
	end
end

local function setState(on)
	enabled = on
	timeLeft = INTERVAL
	local color = on and Color3.fromRGB(60, 190, 120) or Color3.fromRGB(90, 70, 220)
	TweenService:Create(toggle, TweenInfo.new(0.25), { BackgroundColor3 = color }):Play()
	toggle.Text = on and "⏹ Выключить" or "▶ Включить"
	if not on then
		timer.Text = "⏱ Выключено"
	end
end

toggle.MouseButton1Click:Connect(function()
	setState(not enabled)
end)

now.MouseButton1Click:Connect(teleport)

close.MouseButton1Click:Connect(function()
	enabled = false
	gui:Destroy()
end)

-- 🔁 Основной цикл
task.spawn(function()
	while gui.Parent do
		task.wait(0.1)
		if enabled then
			timeLeft -= 0.1
			if timeLeft <= 0 then
				teleport()
				timeLeft = INTERVAL
			end
			timer.Text = string.format("⏱ Следующий ТП через: %.1f с", math.max(timeLeft, 0))
		end
	end
end)
