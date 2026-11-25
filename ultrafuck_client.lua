-- ULTRAFUCK CLIENT (для экзекьютера)
-- Вставь код целиком и нажми Execute

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Настройки
local CLIENT_NAME = "ULTRAFUCK CLIENT"
local DEFAULT_TARGET = Vector3.new(-202, 800, -88) -- координаты по умолчанию (для сброса)
local TARGET = DEFAULT_TARGET
local INTERVAL = 4                          -- кулдаун автотелепорта (сек)
local MIN_CD, MAX_CD = 0.5, 60
local TOGGLE_KEY = Enum.KeyCode.RightShift   -- показать/скрыть окно
local TOAST_TIME = 1.6                      -- сколько висит уведомление
local WIN_W, FULL_H = 320, 360              -- размер окна

-- Палитра
local C = {
	white = Color3.new(1, 1, 1),
	tint = Color3.fromRGB(22, 22, 38),
	tint2 = Color3.fromRGB(72, 64, 125),
	sub = Color3.fromRGB(205, 205, 235),
	accent = Color3.fromRGB(125, 95, 255),
	cyan = Color3.fromRGB(80, 210, 255),
	green = Color3.fromRGB(70, 215, 140),
	red = Color3.fromRGB(255, 85, 105),
	gray = Color3.fromRGB(150, 150, 185),
	off = Color3.fromRGB(95, 95, 130),
}

local QUAD, BACK, QUINT = Enum.EasingStyle.Quad, Enum.EasingStyle.Back, Enum.EasingStyle.Quint
local OUT, IN = Enum.EasingDirection.Out, Enum.EasingDirection.In

-- GUI parent: gethui() если есть, иначе PlayerGui
local function getGuiParent()
	local ok, hui = pcall(function()
		return gethui and gethui()
	end)
	if ok and hui then
		return hui
	end
	return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
-- если клиент уже запущен, выгружаем старую копию
pcall(function()
	local env = (getgenv and getgenv()) or _G
	if env.UltrafuckUnload then
		env.UltrafuckUnload()
	end
end)

for _, name in ipairs({ "UltrafuckClient", "UltrafuckESP", "AutoTeleportGlass", "AutoTeleportESP" }) do
	local old = guiParent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- Общие списки
local conns = {}      -- все соединения (чтобы отключить при выгрузке)
local stepFns = {}    -- функции, вызываемые каждый кадр
local cleanups = {}   -- функции очистки при выгрузке
local edgeGrads = {}  -- бегущие блики стекла

local function track(c)
	table.insert(conns, c)
	return c
end

-- Хелперы
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or QUAD, dir or OUT), props)
	tw:Play()
	return tw
end

local function edgeLight(parent, thickness)
	local s = make("UIStroke", {
		Color = C.white,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
	local g = make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.25, 0.85),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.75, 0.85),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
	}, s)
	table.insert(edgeGrads, g)
	return s, g
end

-- Слой жидкого стекла (чуть меньше родителя, чтобы обводка не обрезалась CanvasGroup)
local function glassLayer(parent, radius, transp)
	local f = make("Frame", {
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		BackgroundColor3 = C.tint,
		BackgroundTransparency = transp or 0.28,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, parent)
	corner(f, radius)
	make("UIGradient", {
		Color = ColorSequence.new(C.tint2, C.tint),
		Rotation = 65,
		Transparency = NumberSequence.new(0, 0.25),
	}, f)

	local sheen = make("Frame", {
		Size = UDim2.new(1, 0, 0.55, 0),
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
	}, f)
	corner(sheen, radius)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.85, 1),
	}, sheen)

	edgeLight(f, 1.5)
	return f
end

local function card(parent, size, pos, radius)
	local f = make("Frame", {
		Size = size,
		Position = pos,
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
	}, parent)
	corner(f, radius or 12)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.8,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, f)
	return f
end

-- Эффект "сквиш" при нажатии
local function squish(btn)
	local s = make("UIScale", { Scale = 1 }, btn)
	btn.MouseLeave:Connect(function()
		tween(s, 0.3, { Scale = 1 }, BACK)
	end)
	btn.MouseButton1Down:Connect(function()
		tween(s, 0.1, { Scale = 0.93 })
	end)
	btn.MouseButton1Up:Connect(function()
		tween(s, 0.4, { Scale = 1 }, BACK)
	end)
end

-- Наведение + сквиш
local function pressable(btn, restT, hoverT, hoverColor)
	local restColor = btn.BackgroundColor3
	squish(btn)
	btn.MouseEnter:Connect(function()
		tween(btn, 0.2, { BackgroundTransparency = hoverT })
		if hoverColor then
			tween(btn, 0.2, { BackgroundColor3 = hoverColor })
		end
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, 0.2, { BackgroundTransparency = restT })
		if hoverColor then
			tween(btn, 0.2, { BackgroundColor3 = restColor })
		end
	end)
end

local function glassButton(parent, size, pos, text, textSize, radius)
	local b = make("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.86,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = textSize or 14,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, parent)
	corner(b, radius or 10)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.75,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)
	pressable(b, 0.86, 0.68)
	return b
end

local function label(parent, text, size, pos, textSize, color, font, align)
	return make("TextLabel", {
		Size = size,
		Position = pos,
		BackgroundTransparency = 1,
		Text = text,
		Font = font or Enum.Font.GothamMedium,
		TextSize = textSize or 13,
		TextColor3 = color or C.white,
		TextXAlignment = align or Enum.TextXAlignment.Left,
	}, parent)
end

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos
	local state = { moved = false }
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			state.moved = false
			dragStart = input.Position
			startPos = target.Position
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 5 then
				state.moved = true
			end
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	return state
end

-- ScreenGui, слой линий ESP и контейнер ESP
local gui = make("ScreenGui", {
	Name = "UltrafuckClient",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

local tracerLayer = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 0,
}, gui)

local espFolder = make("Folder", { Name = "UltrafuckESP" }, guiParent)

-- ГЛАВНОЕ ОКНО
local main = make("CanvasGroup", {
	Size = UDim2.fromOffset(WIN_W, FULL_H),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, -FULL_H / 2),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
	Active = true,
}, gui)
local mainScale = make("UIScale", { Scale = 0.8 }, main)

glassLayer(main, 22, 0.28)

-- Шапка
local header = make("Frame", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
}, main)

local dot = make("Frame", {
	Size = UDim2.fromOffset(10, 10),
	Position = UDim2.fromOffset(20, 17),
	BackgroundColor3 = C.gray,
	BorderSizePixel = 0,
}, header)
corner(dot, 5)

label(header, CLIENT_NAME, UDim2.new(1, -130, 1, 0), UDim2.fromOffset(38, 0), 15, C.white, Enum.Font.GothamBold)

local function headerBtn(text, x, size)
	local b = make("TextButton", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, x, 0, 8),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.88,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = size,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, header)
	corner(b, 14)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.75,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)
	return b
end

local minBtn = headerBtn("-", -76, 18)
local closeBtn = headerBtn("X", -42, 13)
pressable(minBtn, 0.88, 0.7)
pressable(closeBtn, 0.88, 0.4, C.red)

-- Вкладки (листаются свайпом по горизонтали)
local TAB_NAMES = { "ТП", "Места", "Игроки", "ESP", "Бой", "Движ.", "Прочее" }
local TAB_COUNT = #TAB_NAMES
local TAB_W = 66
local TAB_VIEW = WIN_W - 32

local tabBar = make("Frame", {
	Size = UDim2.new(1, -32, 0, 30),
	Position = UDim2.fromOffset(16, 46),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 0.92,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, main)
corner(tabBar, 15)
make("UIStroke", {
	Color = C.white,
	Transparency = 0.82,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, tabBar)

local tabScroll = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, TAB_W * TAB_COUNT, 1, 0),
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ClipsDescendants = true,
}, tabBar)

local tabInd = make("Frame", {
	Size = UDim2.new(0, TAB_W - 4, 1, -4),
	Position = UDim2.fromOffset(2, 2),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 0.78,
	BorderSizePixel = 0,
}, tabScroll)
corner(tabInd, 13)
make("UIStroke", {
	Color = C.white,
	Transparency = 0.6,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, tabInd)

local tabBtns = {}
for i, name in ipairs(TAB_NAMES) do
	tabBtns[i] = make("TextButton", {
		Size = UDim2.new(0, TAB_W, 1, 0),
		Position = UDim2.fromOffset((i - 1) * TAB_W, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = i == 1 and C.white or C.sub,
		AutoButtonColor = false,
		ZIndex = 2,
	}, tabScroll)
end

-- Тело и страницы
local body = make("Frame", {
	Size = UDim2.new(1, 0, 0, 280),
	Position = UDim2.fromOffset(0, 80),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, main)

local pages = {}
for i = 1, TAB_COUNT do
	pages[i] = make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = i == 1 and 0 or 1,
		Visible = i == 1,
	}, body)
end

-- ПЛАВАЮЩАЯ КАПЛЯ (когда окно закрыто)
local orb = make("TextButton", {
	Size = UDim2.fromOffset(52, 52),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -FULL_H / 2 + 22),
	BackgroundColor3 = C.accent,
	BackgroundTransparency = 0.35,
	Text = "UF",
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = C.white,
	AutoButtonColor = false,
	Visible = false,
	Active = true,
}, gui)
corner(orb, 26)
edgeLight(orb, 2)
make("UIGradient", {
	Color = ColorSequence.new(C.cyan, C.accent),
	Rotation = 45,
}, orb)
local orbScale = make("UIScale", { Scale = 0 }, orb)

-- УВЕДОМЛЕНИЕ СНИЗУ
local TOAST_W, TOAST_H = 280, 50
local TOAST_SHOWN = UDim2.new(0.5, 0, 1, -70)
local TOAST_HIDDEN = UDim2.new(0.5, 0, 1, 40)
local DEFAULT_TOAST = "ТЕЛЕПОРТИРОВАНО"

local toast = make("CanvasGroup", {
	Size = UDim2.fromOffset(TOAST_H, TOAST_H),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = TOAST_HIDDEN,
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
}, gui)
local toastScale = make("UIScale", { Scale = 1 }, toast)
glassLayer(toast, 23, 0.25)

-- цветная точка вместо иконки (зелёная = успех, голубая = инфо, красная = внимание)
local toastDot = make("Frame", {
	Size = UDim2.fromOffset(12, 12),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 25, 0.5, 0),
	BackgroundColor3 = C.green,
	BorderSizePixel = 0,
}, toast)
corner(toastDot, 6)

local toastLabel = make("TextLabel", {
	Size = UDim2.fromOffset(TOAST_W - 60, TOAST_H),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 46, 0.5, 0),
	BackgroundTransparency = 1,
	Text = DEFAULT_TOAST,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = C.white,
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, toast)

local toastToken = 0
local toastShown = false

local function showToast(text, kind)
	toastToken += 1
	local my = toastToken
	toastLabel.Text = text or DEFAULT_TOAST
	local dotColor = (kind == "warn" and C.red) or (kind == "info" and C.cyan) or C.green
	tween(toastDot, 0.25, { BackgroundColor3 = dotColor })

	if not toastShown then
		toastShown = true
		toast.Visible = true
		toast.Size = UDim2.fromOffset(TOAST_H, TOAST_H)
		toast.Position = TOAST_HIDDEN
		toast.GroupTransparency = 1
		toastLabel.TextTransparency = 1
		toastScale.Scale = 0.8

		tween(toast, 0.5, { Position = TOAST_SHOWN }, BACK)
		tween(toast, 0.25, { GroupTransparency = 0 })
		tween(toastScale, 0.5, { Scale = 1 }, BACK)
		task.delay(0.15, function()
			if toastToken == my then
				tween(toast, 0.55, { Size = UDim2.fromOffset(TOAST_W, TOAST_H) }, BACK)
			end
		end)
		task.delay(0.35, function()
			if toastToken == my then
				tween(toastLabel, 0.25, { TextTransparency = 0 })
			end
		end)
	else
		toast.Position = TOAST_SHOWN
		toast.Size = UDim2.fromOffset(TOAST_W, TOAST_H)
		toast.GroupTransparency = 0
		toastLabel.TextTransparency = 0
		toastScale.Scale = 1.08
		tween(toastScale, 0.35, { Scale = 1 }, BACK)
	end

	task.spawn(function()
		task.wait(TOAST_TIME)
		if toastToken ~= my then return end
		toastShown = false
		tween(toastLabel, 0.15, { TextTransparency = 1 })
		tween(toast, 0.35, { Size = UDim2.fromOffset(TOAST_H, TOAST_H) }, QUINT, IN)
		task.wait(0.25)
		if toastToken ~= my then return end
		tween(toast, 0.3, { Position = TOAST_HIDDEN, GroupTransparency = 1 }, QUINT, IN)
		task.wait(0.3)
		if toastToken == my then
			toast.Visible = false
		end
	end)
end

-- Кнопка, которую нужно держать (UP/DN для полёта, AIM для прицела)
local function holdButton(text, pos)
	local b = make("TextButton", {
		Size = UDim2.fromOffset(58, 58),
		AnchorPoint = Vector2.new(1, 1),
		Position = pos,
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.35,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = C.white,
		AutoButtonColor = false,
		Visible = false,
	}, gui)
	corner(b, 29)
	edgeLight(b, 2)
	local sc = make("UIScale", { Scale = 0 }, b)
	local st = { down = false }
	local active = nil

	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			st.down = true
			active = input
			tween(b, 0.1, { BackgroundTransparency = 0.1 })
		end
	end)
	track(UserInputService.InputEnded:Connect(function(input)
		if active and (input == active
			or (input.UserInputType == Enum.UserInputType.MouseButton1
				and active.UserInputType == Enum.UserInputType.MouseButton1)) then
			st.down = false
			active = nil
			tween(b, 0.2, { BackgroundTransparency = 0.35 })
		end
	end))

	function st.show(on)
		if on then
			b.Visible = true
			tween(sc, 0.4, { Scale = 1 }, BACK)
		else
			st.down = false
			tween(sc, 0.2, { Scale = 0 }, QUAD, IN)
			task.delay(0.2, function()
				if sc.Scale < 0.05 then
					b.Visible = false
				end
			end)
		end
	end
	return st
end

-- Кнопка ВКЛ/ВЫКЛ
local function onOffButton(parent, size, pos)
	local b = make("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = C.off,
		BackgroundTransparency = 0.4,
		Text = "ВЫКЛ",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, parent)
	corner(b, 14)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)
	pressable(b, 0.4, 0.25)
	return b
end

local function paintOnOff(b, on, redOn)
	b.Text = on and "ВКЛ" or "ВЫКЛ"
	tween(b, 0.3, { BackgroundColor3 = on and (redOn and C.red or C.green) or C.off })
end

-- Переключатель-чип
local function chipButton(parent, size, pos, text)
	local b = make("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.88,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, parent)
	corner(b, 15)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.75,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)
	squish(b)
	return b
end

local function paintChip(b, on)
	tween(b, 0.25, {
		BackgroundColor3 = on and C.green or C.white,
		BackgroundTransparency = on and 0.45 or 0.88,
	})
end

-- ЯДРО
local enabled = false
local minimized = false
local open = false
local currentTab = 1
local timeLeft = INTERVAL
local S = { fly = false } -- общее состояние между модулями
local refreshBoxes -- заполняется на странице "ТП"
local unload       -- заполняется в конце

local function getHRP(plr)
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum(plr)
	local char = plr.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function teleport()
	local hrp = getHRP(player)
	if hrp then
		hrp.CFrame = CFrame.new(TARGET)
		showToast()
	end
end

-- СТРАНИЦА 1: ТП
do
	local page = pages[1]

	local coordCard = card(page, UDim2.new(1, -32, 0, 76), UDim2.fromOffset(16, 4), 12)
	label(coordCard, "Координаты", UDim2.fromOffset(100, 28), UDim2.fromOffset(12, 6), 14)
	local resetBtn = glassButton(coordCard, UDim2.fromOffset(54, 26), UDim2.new(1, -66, 0, 7), "Сброс", 12, 13)
	local pinBtn = glassButton(coordCard, UDim2.fromOffset(52, 26), UDim2.new(1, -124, 0, 7), "Я тут", 12, 13)

	local axisBoxes = {}
	local function axisField(axis, x)
		local f = make("Frame", {
			Size = UDim2.fromOffset(84, 28),
			Position = UDim2.fromOffset(x, 40),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		}, coordCard)
		corner(f, 14)
		label(f, axis, UDim2.fromOffset(22, 28), UDim2.fromOffset(4, 0), 13, C.cyan, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		axisBoxes[axis] = make("TextBox", {
			Size = UDim2.fromOffset(58, 28),
			Position = UDim2.fromOffset(24, 0),
			BackgroundTransparency = 1,
			Text = "0",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = C.white,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, f)
	end
	axisField("X", 12)
	axisField("Y", 102)
	axisField("Z", 192)

	refreshBoxes = function()
		axisBoxes.X.Text = string.format("%g", TARGET.X)
		axisBoxes.Y.Text = string.format("%g", TARGET.Y)
		axisBoxes.Z.Text = string.format("%g", TARGET.Z)
	end
	refreshBoxes()

	for axis, box in pairs(axisBoxes) do
		box.FocusLost:Connect(function()
			local v = tonumber(box.Text)
			if v then
				TARGET = Vector3.new(
					axis == "X" and v or TARGET.X,
					axis == "Y" and v or TARGET.Y,
					axis == "Z" and v or TARGET.Z
				)
			end
			refreshBoxes()
		end)
	end

	resetBtn.MouseButton1Click:Connect(function()
		TARGET = DEFAULT_TARGET
		refreshBoxes()
		showToast("КООРДИНАТЫ СБРОШЕНЫ", "info")
	end)

	pinBtn.MouseButton1Click:Connect(function()
		local hrp = getHRP(player)
		if hrp then
			local p = hrp.Position
			TARGET = Vector3.new(math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
			refreshBoxes()
			showToast("ПОЗИЦИЯ ЗАПИСАНА В ПОЛЯ", "info")
		end
	end)

	-- Кулдаун
	local cdCard = card(page, UDim2.new(1, -32, 0, 52), UDim2.fromOffset(16, 86), 12)
	label(cdCard, "Кулдаун", UDim2.fromOffset(100, 52), UDim2.fromOffset(12, 0), 14)
	local plusBtn = glassButton(cdCard, UDim2.fromOffset(30, 30), UDim2.new(1, -42, 0.5, -15), "+", 18, 15)
	local cdBox = make("TextBox", {
		Size = UDim2.fromOffset(52, 30),
		Position = UDim2.new(1, -98, 0.5, -15),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = string.format("%g", INTERVAL),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = C.cyan,
		ClearTextOnFocus = false,
		PlaceholderText = "сек",
	}, cdCard)
	corner(cdBox, 15)
	local minusBtn = glassButton(cdCard, UDim2.fromOffset(30, 30), UDim2.new(1, -134, 0.5, -15), "-", 18, 15)

	-- Прогресс
	local barBg = make("Frame", {
		Size = UDim2.new(1, -32, 0, 8),
		Position = UDim2.fromOffset(16, 148),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
	}, page)
	corner(barBg, 4)
	local barFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
	}, barBg)
	corner(barFill, 4)
	make("UIGradient", { Color = ColorSequence.new(C.accent, C.cyan) }, barFill)

	local timerLabel = label(page, "Выключено", UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 160), 13, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)

	-- Кнопка ВКЛ/ВЫКЛ
	local toggleBtn = make("TextButton", {
		Size = UDim2.new(1, -32, 0, 44),
		Position = UDim2.fromOffset(16, 188),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.3,
		Text = "ВКЛЮЧИТЬ",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, page)
	corner(toggleBtn, 14)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, toggleBtn)
	make("UIGradient", {
		Color = ColorSequence.new(C.white, Color3.fromRGB(190, 190, 225)),
		Rotation = 90,
	}, toggleBtn)
	pressable(toggleBtn, 0.3, 0.15)

	local nowBtn = glassButton(page, UDim2.new(1, -32, 0, 34), UDim2.fromOffset(16, 240), "Телепорт сейчас", 14, 12)
	nowBtn.Font = Enum.Font.GothamMedium

	local function setEnabled(on)
		enabled = on
		timeLeft = INTERVAL
		tween(toggleBtn, 0.3, { BackgroundColor3 = on and C.green or C.accent })
		tween(dot, 0.3, { BackgroundColor3 = on and C.green or C.gray })
		toggleBtn.Text = on and "ВЫКЛЮЧИТЬ" or "ВКЛЮЧИТЬ"
		if not on then
			timerLabel.Text = "Выключено"
			tween(barFill, 0.25, { Size = UDim2.fromScale(0, 1) })
		end
	end

	local function setInterval(v)
		v = tonumber(v)
		if not v then
			cdBox.Text = string.format("%g", INTERVAL)
			return
		end
		INTERVAL = math.clamp(math.floor(v * 10 + 0.5) / 10, MIN_CD, MAX_CD)
		timeLeft = INTERVAL
		cdBox.Text = string.format("%g", INTERVAL)
	end

	toggleBtn.MouseButton1Click:Connect(function() setEnabled(not enabled) end)
	nowBtn.MouseButton1Click:Connect(teleport)
	plusBtn.MouseButton1Click:Connect(function() setInterval(INTERVAL + 0.5) end)
	minusBtn.MouseButton1Click:Connect(function() setInterval(INTERVAL - 0.5) end)
	cdBox.FocusLost:Connect(function() setInterval(cdBox.Text) end)

	table.insert(stepFns, function(dt)
		if enabled then
			timeLeft -= dt
			if timeLeft <= 0 then
				teleport()
				timeLeft = INTERVAL
			end
			barFill.Size = UDim2.fromScale(math.clamp(1 - timeLeft / INTERVAL, 0, 1), 1)
			timerLabel.Text = string.format("Следующий ТП через %.1f с", math.max(timeLeft, 0))
		end
	end)
end

-- СТРАНИЦА 2: МЕСТА
do
	local page = pages[2]
	local SAVE_FILE = "AutoTeleport_places_" .. tostring(game.PlaceId) .. ".json"
	local MAX_PLACES = 50
	local saved = {}

	local function loadSaved()
		local ok, data = pcall(function()
			if isfile and readfile and isfile(SAVE_FILE) then
				return HttpService:JSONDecode(readfile(SAVE_FILE))
			end
		end)
		if ok and type(data) == "table" then
			for _, e in ipairs(data) do
				if type(e) == "table" and type(e.name) == "string"
					and type(e.x) == "number" and type(e.y) == "number" and type(e.z) == "number" then
					table.insert(saved, e)
				end
			end
		end
	end

	local function persist()
		pcall(function()
			if writefile then
				writefile(SAVE_FILE, HttpService:JSONEncode(saved))
			end
		end)
	end

	local addCard = card(page, UDim2.new(1, -32, 0, 76), UDim2.fromOffset(16, 4), 12)
	local nameBox = make("TextBox", {
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "",
		PlaceholderText = "Название места",
		PlaceholderColor3 = C.gray,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = C.white,
		ClearTextOnFocus = false,
	}, addCard)
	corner(nameBox, 14)

	local saveHereBtn = glassButton(addCard, UDim2.new(0.5, -16, 0, 28), UDim2.fromOffset(12, 40), "Моя позиция", 12, 14)
	local saveFieldsBtn = glassButton(addCard, UDim2.new(0.5, -16, 0, 28), UDim2.new(0.5, 4, 0, 40), "Из полей", 12, 14)

	local savedLabel = label(page, "Сохранённые места: 0", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 92), 13, C.sub)

	local savedList = make("ScrollingFrame", {
		Size = UDim2.new(1, -32, 0, 162),
		Position = UDim2.fromOffset(16, 112),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.white,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, savedList)

	local savedEmpty = label(page, "Пока пусто.\nСохрани свою позицию или координаты из полей", UDim2.new(1, -48, 0, 50), UDim2.fromOffset(24, 134), 13, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
	savedEmpty.TextWrapped = true
	savedEmpty.Visible = false

	local function rowButton(row, size, pos, text, textSize)
		local b = make("TextButton", {
			Size = size,
			Position = pos,
			BackgroundColor3 = C.white,
			BackgroundTransparency = 0.86,
			Text = text,
			Font = Enum.Font.GothamBold,
			TextSize = textSize,
			TextColor3 = C.white,
			AutoButtonColor = false,
		}, row)
		corner(b, 13)
		return b
	end

	local function refreshSaved()
		for _, ch in ipairs(savedList:GetChildren()) do
			if ch:IsA("Frame") then
				ch:Destroy()
			end
		end

		savedLabel.Text = string.format("Сохранённые места: %d", #saved)
		savedEmpty.Visible = #saved == 0

		for i, entry in ipairs(saved) do
			local row = card(savedList, UDim2.new(1, -6, 0, 52), UDim2.new(), 12)
			row.LayoutOrder = i

			-- название можно редактировать прямо в списке
			local nb = make("TextBox", {
				Size = UDim2.new(1, -138, 0, 22),
				Position = UDim2.fromOffset(12, 5),
				BackgroundTransparency = 1,
				Text = entry.name,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = C.white,
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
			}, row)
			nb.FocusLost:Connect(function()
				local t = nb.Text:match("^%s*(.-)%s*$")
				if t == "" then
					t = entry.name
				end
				entry.name = t:sub(1, 24)
				nb.Text = entry.name
				persist()
			end)

			label(row, string.format("X %g   Y %g   Z %g", entry.x, entry.y, entry.z),
				UDim2.new(1, -138, 0, 18), UDim2.fromOffset(12, 28), 11, C.sub, Enum.Font.Gotham)

			-- сделать целью автотелепорта
			local aimBtn = rowButton(row, UDim2.fromOffset(44, 26), UDim2.new(1, -126, 0.5, -13), "Цель", 11)
			pressable(aimBtn, 0.86, 0.65)
			aimBtn.MouseButton1Click:Connect(function()
				TARGET = Vector3.new(entry.x, entry.y, entry.z)
				refreshBoxes()
				showToast("ЦЕЛЬ: " .. entry.name, "info")
			end)

			-- телепорт сейчас
			local goBtn = rowButton(row, UDim2.fromOffset(40, 26), UDim2.new(1, -78, 0.5, -13), "ТП", 12)
			goBtn.BackgroundColor3 = C.accent
			goBtn.BackgroundTransparency = 0.35
			pressable(goBtn, 0.35, 0.15)
			goBtn.MouseButton1Click:Connect(function()
				local hrp = getHRP(player)
				if hrp then
					hrp.CFrame = CFrame.new(entry.x, entry.y, entry.z)
					showToast("ТП: " .. entry.name)
				end
			end)

			-- удалить
			local delBtn = rowButton(row, UDim2.fromOffset(28, 26), UDim2.new(1, -34, 0.5, -13), "X", 12)
			pressable(delBtn, 0.86, 0.4, C.red)
			delBtn.MouseButton1Click:Connect(function()
				local idx = table.find(saved, entry)
				if idx then
					table.remove(saved, idx)
				end
				persist()
				refreshSaved()
				showToast("УДАЛЕНО: " .. entry.name, "warn")
			end)
		end
	end

	local function addPlace(name, v)
		if #saved >= MAX_PLACES then
			showToast("ЛИМИТ МЕСТ: " .. MAX_PLACES, "warn")
			return
		end
		name = (name or ""):match("^%s*(.-)%s*$")
		if name == "" then
			name = "Место " .. (#saved + 1)
		end
		name = name:sub(1, 24)
		table.insert(saved, { name = name, x = v.X, y = v.Y, z = v.Z })
		persist()
		refreshSaved()
		nameBox.Text = ""
		task.defer(function()
			savedList.CanvasPosition = Vector2.new(0, savedList.AbsoluteCanvasSize.Y)
		end)
		showToast("СОХРАНЕНО: " .. name)
	end

	saveHereBtn.MouseButton1Click:Connect(function()
		local hrp = getHRP(player)
		if hrp then
			local p = hrp.Position
			addPlace(nameBox.Text, Vector3.new(
				math.floor(p.X * 10 + 0.5) / 10,
				math.floor(p.Y * 10 + 0.5) / 10,
				math.floor(p.Z * 10 + 0.5) / 10
			))
		end
	end)

	saveFieldsBtn.MouseButton1Click:Connect(function()
		addPlace(nameBox.Text, TARGET)
	end)

	loadSaved()
	refreshSaved()
end

-- СТРАНИЦА 3: ИГРОКИ + СЛЕЖКА
do
	local page = pages[3]
	local followTarget = nil
	local followMode = "walk"   -- "walk" (ходьба) или "tp" (прилипание)
	local followDist = 6
	local walkAccum = 0
	local refreshList

	local fCard = card(page, UDim2.new(1, -32, 0, 78), UDim2.fromOffset(16, 4), 12)
	local fStatus = label(fCard, "Слежка: никого", UDim2.new(1, -90, 0, 28), UDim2.fromOffset(12, 6), 13)
	fStatus.TextTruncate = Enum.TextTruncate.AtEnd
	local stopBtn = glassButton(fCard, UDim2.fromOffset(62, 26), UDim2.new(1, -74, 0, 7), "Стоп", 12, 13)

	label(fCard, "Дист.", UDim2.fromOffset(44, 28), UDim2.fromOffset(12, 42), 12, C.sub)
	local dMinus = glassButton(fCard, UDim2.fromOffset(26, 26), UDim2.fromOffset(56, 43), "-", 16, 13)
	local dBox = make("TextBox", {
		Size = UDim2.fromOffset(40, 26),
		Position = UDim2.fromOffset(86, 43),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = tostring(followDist),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.cyan,
		ClearTextOnFocus = false,
	}, fCard)
	corner(dBox, 13)
	local dPlus = glassButton(fCard, UDim2.fromOffset(26, 26), UDim2.fromOffset(130, 43), "+", 16, 13)
	local modeBtn = glassButton(fCard, UDim2.new(1, -176, 0, 26), UDim2.fromOffset(164, 43), "Режим: Ходьба", 11, 13)

	local playersLabel = label(page, "Игроки онлайн: 0", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 90), 13, C.sub)

	local listFrame = make("ScrollingFrame", {
		Size = UDim2.new(1, -32, 0, 164),
		Position = UDim2.fromOffset(16, 110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.white,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)

	local emptyLabel = label(page, "Других игроков нет", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 130), 13, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
	emptyLabel.Visible = false

	local function setFollow(plr)
		local was = followTarget
		followTarget = plr
		fStatus.Text = plr and ("Слежка: " .. plr.Name) or "Слежка: никого"
		if plr then
			showToast("СЛЕЖУ ЗА " .. plr.Name, "info")
		elseif was then
			local hrp, hum = getHRP(player), getHum(player)
			if hrp and hum then
				hum:MoveTo(hrp.Position)
			end
			showToast("СЛЕЖКА ВЫКЛЮЧЕНА", "warn")
		end
		refreshList()
	end

	local function teleportToPlayer(plr)
		local me, them = getHRP(player), getHRP(plr)
		if me and them then
			me.CFrame = CFrame.new(them.Position + Vector3.new(0, 4, 0))
			showToast("ТП К " .. plr.Name)
		else
			showToast("ИГРОК НЕДОСТУПЕН", "warn")
		end
	end

	refreshList = function()
		for _, ch in ipairs(listFrame:GetChildren()) do
			if ch:IsA("Frame") then
				ch:Destroy()
			end
		end

		local others = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				table.insert(others, p)
			end
		end
		table.sort(others, function(a, b)
			return a.Name:lower() < b.Name:lower()
		end)

		playersLabel.Text = string.format("Игроки онлайн: %d", #others)
		emptyLabel.Visible = #others == 0

		for i, p in ipairs(others) do
			local row = card(listFrame, UDim2.new(1, -6, 0, 38), UDim2.new(), 12)
			row.LayoutOrder = i

			local shown = p.Name
			if p.DisplayName ~= p.Name then
				shown = p.DisplayName .. " (@" .. p.Name .. ")"
			end
			local nl = label(row, shown, UDim2.new(1, -128, 1, 0), UDim2.fromOffset(12, 0), 13)
			nl.TextTruncate = Enum.TextTruncate.AtEnd

			local isFollowed = followTarget == p

			local fBtn = make("TextButton", {
				Size = UDim2.fromOffset(62, 26),
				Position = UDim2.new(1, -112, 0.5, -13),
				BackgroundColor3 = isFollowed and C.red or C.white,
				BackgroundTransparency = isFollowed and 0.4 or 0.86,
				Text = isFollowed and "Стоп" or "Следить",
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = C.white,
				AutoButtonColor = false,
			}, row)
			corner(fBtn, 13)
			pressable(fBtn, isFollowed and 0.4 or 0.86, isFollowed and 0.25 or 0.65)
			fBtn.MouseButton1Click:Connect(function()
				if followTarget == p then
					setFollow(nil)
				else
					setFollow(p)
				end
			end)

			local tBtn = make("TextButton", {
				Size = UDim2.fromOffset(40, 26),
				Position = UDim2.new(1, -46, 0.5, -13),
				BackgroundColor3 = C.accent,
				BackgroundTransparency = 0.35,
				Text = "ТП",
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = C.white,
				AutoButtonColor = false,
			}, row)
			corner(tBtn, 13)
			pressable(tBtn, 0.35, 0.15)
			tBtn.MouseButton1Click:Connect(function()
				teleportToPlayer(p)
			end)
		end
	end

	local function setDist(v)
		v = tonumber(v)
		if v then
			followDist = math.clamp(math.floor(v + 0.5), 2, 30)
		end
		dBox.Text = tostring(followDist)
	end

	stopBtn.MouseButton1Click:Connect(function() setFollow(nil) end)
	dMinus.MouseButton1Click:Connect(function() setDist(followDist - 1) end)
	dPlus.MouseButton1Click:Connect(function() setDist(followDist + 1) end)
	dBox.FocusLost:Connect(function() setDist(dBox.Text) end)
	modeBtn.MouseButton1Click:Connect(function()
		followMode = followMode == "walk" and "tp" or "walk"
		modeBtn.Text = followMode == "walk" and "Режим: Ходьба" or "Режим: Прилипание"
	end)

	track(Players.PlayerAdded:Connect(function()
		refreshList()
	end))
	track(Players.PlayerRemoving:Connect(function(p)
		if p == followTarget then
			setFollow(nil)
		end
		task.defer(refreshList)
	end))

	table.insert(stepFns, function(dt)
		if not followTarget then return end
		local me, them = getHRP(player), getHRP(followTarget)
		if not me or not them then return end

		if followMode == "tp" then
			local goal = (them.CFrame * CFrame.new(0, 0, followDist)).Position
			local cf = CFrame.new(goal, Vector3.new(them.Position.X, goal.Y, them.Position.Z))
			me.CFrame = me.CFrame:Lerp(cf, math.clamp(dt * 10, 0, 1))
			me.AssemblyLinearVelocity = Vector3.zero
		else
			local hum = getHum(player)
			if hum then
				walkAccum += dt
				if walkAccum >= 0.15 then
					walkAccum = 0
					local d = them.Position - me.Position
					local flat = Vector3.new(d.X, 0, d.Z).Magnitude
					if flat > followDist + 1.5 then
						hum:MoveTo(them.Position)
					else
						hum:MoveTo(me.Position)
					end
					if d.Y > 3 and flat < followDist + 6 then
						hum.Jump = true
					end
				end
			end
		end
	end)

	table.insert(cleanups, function()
		followTarget = nil
	end)

	refreshList()
end

-- СТРАНИЦА 4: ESP
do
	local page = pages[4]

	local espEnabled = false
	local rainbow = false
	local espColor = Color3.fromRGB(255, 85, 105)
	local opts = { highlight = true, name = true, dist = true, health = true, tracers = false, team = false }
	local maxDist = 0
	local objects = {}
	local tickAccum = 0

	local function baseColor()
		if rainbow then
			return Color3.fromHSV((tick() % 5) / 5, 0.85, 1)
		end
		return espColor
	end

	local function colorFor(plr)
		if opts.team and plr.Team then
			return plr.TeamColor.Color
		end
		return baseColor()
	end

	local function applyColors(o)
		local col = colorFor(o.plr)
		o.hl.FillColor = col
		o.hl.OutlineColor = col
		o.nameLbl.TextColor3 = col
		o.line.BackgroundColor3 = col
	end

	local function removeESP(plr)
		local o = objects[plr]
		if o then
			o.hl:Destroy()
			o.bb:Destroy()
			o.line:Destroy()
			objects[plr] = nil
		end
	end

	local function addESP(plr)
		removeESP(plr)
		local char = plr.Character
		if not char then return end
		task.spawn(function()
			local head = char:WaitForChild("Head", 5)
			if not head or not espEnabled or plr.Character ~= char or objects[plr] then
				return
			end
			local hl = make("Highlight", {
				Adornee = char,
				FillTransparency = 0.65,
				OutlineTransparency = 0,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			}, espFolder)

			local bb = make("BillboardGui", {
				Adornee = head,
				Size = UDim2.fromOffset(170, 34),
				StudsOffset = Vector3.new(0, 2.8, 0),
				AlwaysOnTop = true,
				ResetOnSpawn = false,
			}, espFolder)
			local nameLbl = make("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = plr.Name,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = C.white,
				TextStrokeTransparency = 0.4,
			}, bb)
			local hpBg = make("Frame", {
				Size = UDim2.fromOffset(90, 6),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 22),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
			}, bb)
			corner(hpBg, 3)
			local hpFill = make("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.green,
				BorderSizePixel = 0,
			}, hpBg)
			corner(hpFill, 3)

			local line = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(0, 2),
				BackgroundColor3 = C.white,
				BorderSizePixel = 0,
				Visible = false,
			}, tracerLayer)

			objects[plr] = {
				plr = plr, hl = hl, bb = bb, nameLbl = nameLbl,
				hpBg = hpBg, hpFill = hpFill, line = line, inRange = true,
			}
			applyColors(objects[plr])
		end)
	end

	local function hookPlayer(plr)
		if plr == player then return end
		track(plr.CharacterAdded:Connect(function()
			if espEnabled then addESP(plr) end
		end))
		track(plr.CharacterRemoving:Connect(function()
			removeESP(plr)
		end))
		if espEnabled then addESP(plr) end
	end

	-- Главная карточка
	local mCard = card(page, UDim2.new(1, -32, 0, 76), UDim2.fromOffset(16, 4), 12)
	label(mCard, "ESP игроков", UDim2.fromOffset(150, 28), UDim2.fromOffset(12, 8), 14)

	local masterBtn = make("TextButton", {
		Size = UDim2.fromOffset(74, 28),
		Position = UDim2.new(1, -86, 0, 8),
		BackgroundColor3 = C.off,
		BackgroundTransparency = 0.4,
		Text = "ВЫКЛ",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, mCard)
	corner(masterBtn, 14)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, masterBtn)
	pressable(masterBtn, 0.4, 0.25)

	-- Палитра
	local swatchDefs = {
		Color3.fromRGB(255, 85, 105),
		Color3.fromRGB(255, 160, 60),
		Color3.fromRGB(255, 225, 80),
		Color3.fromRGB(70, 215, 140),
		Color3.fromRGB(80, 210, 255),
		Color3.fromRGB(160, 100, 255),
		Color3.fromRGB(255, 110, 200),
		Color3.fromRGB(255, 255, 255),
		false, -- радуга
	}
	local swatches = {}

	local function selectSwatch(idx)
		local def = swatchDefs[idx]
		if def then
			rainbow = false
			espColor = def
		else
			rainbow = true
		end
		for i, s in ipairs(swatches) do
			tween(s.stroke, 0.2, { Transparency = i == idx and 0 or 1 })
			tween(s.scale, 0.3, { Scale = i == idx and 1.18 or 1 }, BACK)
		end
		for _, o in pairs(objects) do
			applyColors(o)
		end
	end

	for i, def in ipairs(swatchDefs) do
		local b = make("TextButton", {
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromOffset(12 + (i - 1) * 28, 46),
			BackgroundColor3 = def or C.white,
			Text = "",
			AutoButtonColor = false,
		}, mCard)
		corner(b, 11)
		if not def then
			make("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
					ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 140)),
					ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
				}),
				Rotation = 45,
			}, b)
		end
		local st = make("UIStroke", {
			Color = C.white,
			Thickness = 2,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, b)
		local sc = make("UIScale", { Scale = 1 }, b)
		swatches[i] = { stroke = st, scale = sc }
		b.MouseButton1Click:Connect(function()
			selectSwatch(i)
		end)
	end

	-- Переключатели опций
	local chipDefs = {
		{ "Подсветка", "highlight" },
		{ "Имя", "name" },
		{ "Дистанция", "dist" },
		{ "Здоровье", "health" },
		{ "Линии", "tracers" },
		{ "Цвет команды", "team" },
	}
	for i, def in ipairs(chipDefs) do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local on = opts[def[2]]
		local b = make("TextButton", {
			Size = UDim2.fromOffset(141, 30),
			Position = UDim2.fromOffset(16 + col * 147, 88 + row * 36),
			BackgroundColor3 = on and C.green or C.white,
			BackgroundTransparency = on and 0.45 or 0.88,
			Text = def[1],
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = C.white,
			AutoButtonColor = false,
		}, page)
		corner(b, 15)
		make("UIStroke", {
			Color = C.white,
			Transparency = 0.75,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, b)
		squish(b)
		b.MouseButton1Click:Connect(function()
			opts[def[2]] = not opts[def[2]]
			local now = opts[def[2]]
			tween(b, 0.25, {
				BackgroundColor3 = now and C.green or C.white,
				BackgroundTransparency = now and 0.45 or 0.88,
			})
		end)
	end

	-- Максимальная дистанция
	local dCard = card(page, UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, 198), 12)
	label(dCard, "Макс. дистанция", UDim2.fromOffset(130, 44), UDim2.fromOffset(12, 0), 13)
	local mPlus = glassButton(dCard, UDim2.fromOffset(28, 28), UDim2.new(1, -40, 0.5, -14), "+", 16, 14)
	local mBox = make("TextBox", {
		Size = UDim2.fromOffset(56, 28),
		Position = UDim2.new(1, -100, 0.5, -14),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "0",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.cyan,
		ClearTextOnFocus = false,
	}, dCard)
	corner(mBox, 14)
	local mMinus = glassButton(dCard, UDim2.fromOffset(28, 28), UDim2.new(1, -132, 0.5, -14), "-", 16, 14)
	label(page, "0 = без ограничения. Шаг 100 м. Подсветка Roblox показывает до 31 игрока.",
		UDim2.new(1, -32, 0, 28), UDim2.fromOffset(16, 246), 11, C.sub, Enum.Font.Gotham).TextWrapped = true

	local function setMax(v)
		v = tonumber(v)
		if v then
			maxDist = math.clamp(math.floor(v + 0.5), 0, 5000)
		end
		mBox.Text = tostring(maxDist)
	end
	mPlus.MouseButton1Click:Connect(function() setMax(maxDist + 100) end)
	mMinus.MouseButton1Click:Connect(function() setMax(maxDist - 100) end)
	mBox.FocusLost:Connect(function() setMax(mBox.Text) end)

	local function setESP(on)
		espEnabled = on
		masterBtn.Text = on and "ВКЛ" or "ВЫКЛ"
		tween(masterBtn, 0.3, { BackgroundColor3 = on and C.green or C.off })
		if on then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player then
					addESP(p)
				end
			end
			showToast("ESP ВКЛЮЧЕН", "info")
		else
			for p in pairs(objects) do
				removeESP(p)
			end
		end
	end
	masterBtn.MouseButton1Click:Connect(function() setESP(not espEnabled) end)

	track(Players.PlayerAdded:Connect(hookPlayer))
	track(Players.PlayerRemoving:Connect(removeESP))
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end

	-- Обновление каждый кадр: цвета (радуга) и линии
	table.insert(stepFns, function(dt)
		if not espEnabled then return end

		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize

		for plr, o in pairs(objects) do
			if rainbow then
				applyColors(o)
			end

			local show = false
			if opts.tracers and o.inRange and cam then
				local them = getHRP(plr)
				if them then
					local v = cam:WorldToViewportPoint(them.Position)
					if v.Z > 0 then
						local s = Vector2.new(vp.X / 2, vp.Y)
						local p = Vector2.new(v.X, v.Y)
						local d = p - s
						o.line.Position = UDim2.fromOffset((s.X + p.X) / 2, (s.Y + p.Y) / 2)
						o.line.Size = UDim2.fromOffset(d.Magnitude, 2)
						o.line.Rotation = math.deg(math.atan2(d.Y, d.X))
						show = true
					end
				end
			end
			o.line.Visible = show
		end

		-- Тяжёлая часть (тексты, здоровье, видимость) раз в 0.1 с
		tickAccum += dt
		if tickAccum < 0.1 then return end
		tickAccum = 0

		local me = getHRP(player)
		for plr, o in pairs(objects) do
			local them = getHRP(plr)
			local dist = (me and them) and (me.Position - them.Position).Magnitude or 0
			local inRange = them ~= nil and (maxDist <= 0 or dist <= maxDist)
			o.inRange = inRange

			o.hl.Enabled = inRange and opts.highlight
			local showText = opts.name or opts.dist
			o.bb.Enabled = inRange and (showText or opts.health)
			o.nameLbl.Visible = showText

			local t = ""
			if opts.name then
				t = plr.Name
			end
			if opts.dist then
				t = t .. (t ~= "" and "  " or "") .. string.format("[%dm]", math.floor(dist))
			end
			o.nameLbl.Text = t

			o.hpBg.Visible = opts.health
			if opts.health then
				local hum = getHum(plr)
				if hum and hum.MaxHealth > 0 then
					local f = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
					o.hpFill.Size = UDim2.fromScale(f, 1)
					o.hpFill.BackgroundColor3 = Color3.fromHSV(f * 0.33, 0.85, 1)
				end
			end

			applyColors(o)
		end
	end)

	table.insert(cleanups, function()
		for p in pairs(objects) do
			removeESP(p)
		end
	end)

	selectSwatch(1)
end

-- СТРАНИЦА 5: БОЙ (AIM BOT, АНТИГРЕБ, GODMODE)
do
	local page = pages[5]

	-- AIM BOT
	local aimOn = false
	local aimSel = { kind = "cross" } -- cross | dist | player
	local aimPartName = "Head"
	local wallCheck = false
	local holdMode = false
	local smooth = 30
	local aimHold = holdButton("AIM", UDim2.new(1, -100, 1, -230))

	local aCard = card(page, UDim2.new(1, -32, 0, 172), UDim2.fromOffset(16, 4), 12)
	label(aCard, "AIM BOT", UDim2.fromOffset(120, 28), UDim2.fromOffset(12, 6), 14, C.white, Enum.Font.GothamBold)
	local aimBtn = onOffButton(aCard, UDim2.fromOffset(74, 28), UDim2.new(1, -86, 0, 6))

	local prevBtn = glassButton(aCard, UDim2.fromOffset(30, 28), UDim2.fromOffset(12, 38), "<", 14, 14)
	local nextBtn = glassButton(aCard, UDim2.fromOffset(30, 28), UDim2.new(1, -42, 0, 38), ">", 14, 14)
	local selBox = make("TextLabel", {
		Size = UDim2.new(1, -96, 0, 28),
		Position = UDim2.fromOffset(48, 38),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "",
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = C.cyan,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, aCard)
	corner(selBox, 14)

	local partBtn = glassButton(aCard, UDim2.fromOffset(129, 28), UDim2.fromOffset(12, 70), "Часть: Голова", 12, 14)
	local wallBtn = glassButton(aCard, UDim2.fromOffset(129, 28), UDim2.fromOffset(147, 70), "Стены: Игнор", 12, 14)
	local modeBtn = glassButton(aCard, UDim2.fromOffset(264, 28), UDim2.fromOffset(12, 102), "Режим: Всегда", 12, 14)

	label(aCard, "Плавность %", UDim2.fromOffset(100, 28), UDim2.fromOffset(12, 134), 12)
	local sPlus = glassButton(aCard, UDim2.fromOffset(28, 28), UDim2.new(1, -40, 0, 134), "+", 16, 14)
	local sBox = make("TextBox", {
		Size = UDim2.fromOffset(52, 28),
		Position = UDim2.new(1, -96, 0, 134),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = tostring(smooth),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.cyan,
		ClearTextOnFocus = false,
	}, aCard)
	corner(sBox, 14)
	local sMinus = glassButton(aCard, UDim2.fromOffset(28, 28), UDim2.new(1, -128, 0, 134), "-", 16, 14)

	local function getOptions()
		local list = { { kind = "cross" }, { kind = "dist" } }
		local names = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				table.insert(names, p.Name)
			end
		end
		table.sort(names, function(a, b) return a:lower() < b:lower() end)
		for _, n in ipairs(names) do
			table.insert(list, { kind = "player", name = n })
		end
		return list
	end

	local function selText()
		if aimSel.kind == "cross" then
			return "Ближайший к центру"
		elseif aimSel.kind == "dist" then
			return "Ближайший по дистанции"
		end
		return aimSel.name
	end
	selBox.Text = selText()

	local function cycle(dir)
		local list = getOptions()
		local idx = 1
		for i, o in ipairs(list) do
			if o.kind == aimSel.kind and o.name == aimSel.name then
				idx = i
				break
			end
		end
		idx = ((idx - 1 + dir) % #list) + 1
		aimSel = list[idx]
		selBox.Text = selText()
	end

	local function partOf(plr)
		local char = plr.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local part
		if aimPartName == "Head" then
			part = char:FindFirstChild("Head")
		else
			part = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		end
		part = part or char:FindFirstChild("HumanoidRootPart")
		return part, char
	end

	local function visible(cam, part, char)
		if not wallCheck then return true end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character, char }
		local origin = cam.CFrame.Position
		return Workspace:Raycast(origin, part.Position - origin, params) == nil
	end

	local function pickTarget(cam)
		local vp = cam.ViewportSize
		local center = Vector2.new(vp.X / 2, vp.Y / 2)
		local best, bestScore

		if aimSel.kind == "player" then
			local plr = Players:FindFirstChild(aimSel.name)
			if plr and plr ~= player then
				local part, char = partOf(plr)
				if part and visible(cam, part, char) then
					return part
				end
			end
			return nil
		end

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player then
				local part, char = partOf(plr)
				if part and visible(cam, part, char) then
					local score
					if aimSel.kind == "dist" then
						score = (part.Position - cam.CFrame.Position).Magnitude
					else
						local v = cam:WorldToViewportPoint(part.Position)
						if v.Z > 0 then
							score = (Vector2.new(v.X, v.Y) - center).Magnitude
						end
					end
					if score and (not bestScore or score < bestScore) then
						best, bestScore = part, score
					end
				end
			end
		end
		return best
	end

	local function aimStep()
		if not aimOn then return end
		if holdMode and not (aimHold.down or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local part = pickTarget(cam)
		if not part then return end
		local goal = CFrame.lookAt(cam.CFrame.Position, part.Position)
		cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(smooth / 100, 0.02, 1))
	end

	local function setAim(on)
		aimOn = on
		paintOnOff(aimBtn, on)
		aimHold.show(on and holdMode)
		showToast(on and "AIM BOT ВКЛЮЧЕН" or "AIM BOT ВЫКЛЮЧЕН", on and "info" or "warn")
	end

	local function setSmooth(v)
		v = tonumber(v)
		if v then
			smooth = math.clamp(math.floor(v + 0.5), 2, 100)
		end
		sBox.Text = tostring(smooth)
	end

	aimBtn.MouseButton1Click:Connect(function() setAim(not aimOn) end)
	prevBtn.MouseButton1Click:Connect(function() cycle(-1) end)
	nextBtn.MouseButton1Click:Connect(function() cycle(1) end)
	partBtn.MouseButton1Click:Connect(function()
		aimPartName = aimPartName == "Head" and "Torso" or "Head"
		partBtn.Text = aimPartName == "Head" and "Часть: Голова" or "Часть: Торс"
	end)
	wallBtn.MouseButton1Click:Connect(function()
		wallCheck = not wallCheck
		wallBtn.Text = wallCheck and "Стены: Проверка" or "Стены: Игнор"
	end)
	modeBtn.MouseButton1Click:Connect(function()
		holdMode = not holdMode
		modeBtn.Text = holdMode and "Режим: Удержание кнопки AIM" or "Режим: Всегда"
		aimHold.show(aimOn and holdMode)
	end)
	sPlus.MouseButton1Click:Connect(function() setSmooth(smooth + 5) end)
	sMinus.MouseButton1Click:Connect(function() setSmooth(smooth - 5) end)
	sBox.FocusLost:Connect(function() setSmooth(sBox.Text) end)

	track(Players.PlayerRemoving:Connect(function(p)
		if aimSel.kind == "player" and aimSel.name == p.Name then
			aimSel = { kind = "cross" }
			selBox.Text = selText()
		end
	end))

	pcall(function() RunService:UnbindFromRenderStep("UltrafuckAim") end)
	RunService:BindToRenderStep("UltrafuckAim", Enum.RenderPriority.Camera.Value + 1, aimStep)
	table.insert(cleanups, function()
		pcall(function() RunService:UnbindFromRenderStep("UltrafuckAim") end)
		aimOn = false
	end)

	-- АНТИГРЕБ (анти-рэгдолл и анти-откидывание)
	local antiOn = false
	local antiChar, antiConn = nil, nil
	local BAD = {
		BodyVelocity = true, BodyAngularVelocity = true, BodyPosition = true,
		BodyForce = true, BodyThrust = true, BodyGyro = true,
		LinearVelocity = true, AngularVelocity = true, VectorForce = true,
		AlignPosition = true, AlignOrientation = true, RocketPropulsion = true,
	}
	local RAG_STATES = { Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown }

	local gCard = card(page, UDim2.new(1, -32, 0, 36), UDim2.fromOffset(16, 182), 12)
	label(gCard, "Антигреб (анти-откид)", UDim2.fromOffset(180, 36), UDim2.fromOffset(12, 0), 13)
	local antiBtn = onOffButton(gCard, UDim2.fromOffset(74, 26), UDim2.new(1, -86, 0.5, -13))

	local function killMover(d)
		if BAD[d.ClassName] then
			pcall(function() d:Destroy() end)
		end
	end

	local function setAnti(on)
		antiOn = on
		paintOnOff(antiBtn, on)
		if not on then
			if antiConn then
				antiConn:Disconnect()
				antiConn = nil
			end
			antiChar = nil
			local hum = getHum(player)
			if hum then
				for _, st in ipairs(RAG_STATES) do
					pcall(function() hum:SetStateEnabled(st, true) end)
				end
			end
		end
		showToast(on and "АНТИГРЕБ ВКЛЮЧЕН" or "АНТИГРЕБ ВЫКЛЮЧЕН", on and "info" or "warn")
	end
	antiBtn.MouseButton1Click:Connect(function() setAnti(not antiOn) end)

	table.insert(stepFns, function()
		if not antiOn then return end
		local char = player.Character
		if char ~= antiChar then
			if antiConn then
				antiConn:Disconnect()
				antiConn = nil
			end
			antiChar = char
			if char then
				antiConn = char.DescendantAdded:Connect(function(d)
					if antiOn then
						task.defer(killMover, d)
					end
				end)
				for _, d in ipairs(char:GetDescendants()) do
					killMover(d)
				end
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					for _, st in ipairs(RAG_STATES) do
						pcall(function() hum:SetStateEnabled(st, false) end)
					end
				end
			end
		end

		local hum, hrp = getHum(player), getHRP(player)
		if hum and hrp and not S.fly then
			if hum.PlatformStand then
				hum.PlatformStand = false
			end
			local v = hrp.AssemblyLinearVelocity
			local limit = math.max(90, hum.WalkSpeed * 1.5 + 40)
			local horiz = Vector3.new(v.X, 0, v.Z).Magnitude
			local nx, ny, nz = v.X, v.Y, v.Z
			if horiz > limit then
				nx, nz = 0, 0
			end
			if ny > limit then
				ny = 0
			end
			if nx ~= v.X or ny ~= v.Y or nz ~= v.Z then
				hrp.AssemblyLinearVelocity = Vector3.new(nx, ny, nz)
			end
		end
	end)

	table.insert(cleanups, function()
		if antiOn then
			setAnti(false)
		end
	end)

	-- GODMODE (с предупреждением на 10 секунд)
	local godOn = false
	local godChar = nil
	local dialogOpen = false

	local godCard = card(page, UDim2.new(1, -32, 0, 36), UDim2.fromOffset(16, 224), 12)
	label(godCard, "GODMODE", UDim2.fromOffset(180, 36), UDim2.fromOffset(12, 0), 13, C.white, Enum.Font.GothamBold)
	local godBtn = onOffButton(godCard, UDim2.fromOffset(74, 26), UDim2.new(1, -86, 0.5, -13))

	local function setGod(on)
		godOn = on
		paintOnOff(godBtn, on, true)
		if not on then
			local hum = getHum(player)
			if hum then
				pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
			end
			godChar = nil
		end
	end

	local function openGodWarning()
		if dialogOpen then return end
		dialogOpen = true

		local overlay = make("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Active = true,
			ZIndex = 50,
		}, gui)
		local box = make("CanvasGroup", {
			Size = UDim2.fromOffset(300, 240),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			GroupTransparency = 1,
			ZIndex = 51,
		}, overlay)
		local boxScale = make("UIScale", { Scale = 0.85 }, box)
		glassLayer(box, 22, 0.12)

		label(box, "ВНИМАНИЕ", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 14), 20, C.red, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		local msg = label(box,
			"GODMODE может привести к БАНУ аккаунта: античит и модераторы замечают такие читы. Включай только на свой риск. Эффект зависит от игры.",
			UDim2.new(1, -36, 0, 92), UDim2.fromOffset(18, 50), 13, C.white, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
		msg.TextWrapped = true
		msg.TextYAlignment = Enum.TextYAlignment.Top

		-- полоска ожидания 10 секунд
		local barBg = make("Frame", {
			Size = UDim2.new(1, -36, 0, 6),
			Position = UDim2.fromOffset(18, 150),
			BackgroundColor3 = C.white,
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
		}, box)
		corner(barBg, 3)
		local fill = make("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.red,
			BorderSizePixel = 0,
		}, barBg)
		corner(fill, 3)

		local cancelBtn = glassButton(box, UDim2.fromOffset(126, 44), UDim2.fromOffset(18, 174), "ОТМЕНА", 14, 14)
		local confirmBtn = make("TextButton", {
			Size = UDim2.fromOffset(126, 44),
			Position = UDim2.fromOffset(156, 174),
			BackgroundColor3 = C.red,
			BackgroundTransparency = 0.8,
			Text = "ВКЛЮЧИТЬ (10)",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = C.white,
			AutoButtonColor = false,
		}, box)
		corner(confirmBtn, 14)
		squish(confirmBtn)

		local closed, ready = false, false

		local function close()
			if closed then return end
			closed = true
			dialogOpen = false
			tween(overlay, 0.25, { BackgroundTransparency = 1 })
			tween(box, 0.25, { GroupTransparency = 1 })
			tween(boxScale, 0.25, { Scale = 0.85 }, QUINT, IN)
			task.delay(0.3, function()
				overlay:Destroy()
			end)
		end

		tween(overlay, 0.3, { BackgroundTransparency = 0.45 })
		tween(box, 0.3, { GroupTransparency = 0 })
		tween(boxScale, 0.5, { Scale = 1 }, BACK)
		TweenService:Create(fill, TweenInfo.new(10, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()

		task.spawn(function()
			for s = 10, 1, -1 do
				if closed then return end
				confirmBtn.Text = "ВКЛЮЧИТЬ (" .. s .. ")"
				task.wait(1)
			end
			if closed then return end
			ready = true
			confirmBtn.Text = "ВКЛЮЧИТЬ"
			tween(confirmBtn, 0.3, { BackgroundTransparency = 0.05 })
		end)

		cancelBtn.MouseButton1Click:Connect(function()
			close()
			showToast("GODMODE ОТМЕНЁН", "info")
		end)
		confirmBtn.MouseButton1Click:Connect(function()
			if not ready then
				showToast("ПОДОЖДИ 10 СЕКУНД", "warn")
				return
			end
			close()
			setGod(true)
			showToast("GODMODE ВКЛЮЧЕН", "warn")
		end)
	end

	godBtn.MouseButton1Click:Connect(function()
		if godOn then
			setGod(false)
			showToast("GODMODE ВЫКЛЮЧЕН", "warn")
		else
			openGodWarning()
		end
	end)

	table.insert(stepFns, function()
		if not godOn then return end
		local hum = getHum(player)
		if not hum then return end
		local char = player.Character
		if char ~= godChar then
			godChar = char
			pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
		end
		if hum.Health < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end)

	table.insert(cleanups, function()
		if godOn then
			setGod(false)
		end
	end)
end

-- СТРАНИЦА 6: ДВИЖЕНИЕ (FLY, NOCLIP, СКОРОСТЬ, ПРЫЖОК, ГРАВИТАЦИЯ)
do
	local page = pages[6]

	local flyOn, noclipOn = false, false
	local flySpeed = 60
	local custom = { walk = nil, jump = nil, grav = nil }

	local hum0 = getHum(player)
	local DEF = {
		walk = hum0 and hum0.WalkSpeed or 16,
		jump = hum0 and hum0.JumpPower or 50,
		grav = Workspace.Gravity,
	}

	local flyUp = holdButton("UP", UDim2.new(1, -24, 1, -230))
	local flyDown = holdButton("DN", UDim2.new(1, -24, 1, -160))

	local flyChip = chipButton(page, UDim2.fromOffset(141, 32), UDim2.fromOffset(16, 4), "Полёт")
	local noclipChip = chipButton(page, UDim2.fromOffset(141, 32), UDim2.fromOffset(163, 4), "Ноклип")

	local function setFly(on)
		flyOn = on
		S.fly = on
		paintChip(flyChip, on)
		flyUp.show(on)
		flyDown.show(on)
		if not on then
			local hum, hrp = getHum(player), getHRP(player)
			if hum then
				hum.PlatformStand = false
				pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
			end
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end
		showToast(on and "ПОЛЁТ ВКЛЮЧЕН" or "ПОЛЁТ ВЫКЛЮЧЕН", on and "info" or "warn")
	end

	local touched = {}
	local function setNoclip(on)
		noclipOn = on
		paintChip(noclipChip, on)
		if not on then
			for p in pairs(touched) do
				if p.Parent then
					p.CanCollide = true
				end
			end
			touched = {}
		end
		showToast(on and "НОКЛИП ВКЛЮЧЕН" or "НОКЛИП ВЫКЛЮЧЕН", on and "info" or "warn")
	end

	flyChip.MouseButton1Click:Connect(function() setFly(not flyOn) end)
	noclipChip.MouseButton1Click:Connect(function() setNoclip(not noclipOn) end)

	-- строка со значением: - [число] + [Сброс]
	local function valueRow(y, title, step, min, max, default, apply, onReset)
		local row = card(page, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, y), 12)
		label(row, title, UDim2.fromOffset(78, 40), UDim2.fromOffset(12, 0), 12)
		local minus = glassButton(row, UDim2.fromOffset(26, 26), UDim2.fromOffset(92, 7), "-", 16, 13)
		local box = make("TextBox", {
			Size = UDim2.fromOffset(52, 26),
			Position = UDim2.fromOffset(122, 7),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			Text = string.format("%g", default),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = C.cyan,
			ClearTextOnFocus = false,
		}, row)
		corner(box, 13)
		local plus = glassButton(row, UDim2.fromOffset(26, 26), UDim2.fromOffset(178, 7), "+", 16, 13)

		local value = default
		local obj = {}

		local function set(v)
			v = tonumber(v)
			if v then
				value = math.clamp(v, min, max)
				apply(value)
			end
			box.Text = string.format("%g", value)
		end

		minus.MouseButton1Click:Connect(function() set(value - step) end)
		plus.MouseButton1Click:Connect(function() set(value + step) end)
		box.FocusLost:Connect(function() set(box.Text) end)

		if onReset then
			local rBtn = glassButton(row, UDim2.fromOffset(66, 26), UDim2.fromOffset(210, 7), "Сброс", 11, 13)
			function obj.reset()
				onReset()
				value = default
				box.Text = string.format("%g", value)
			end
			rBtn.MouseButton1Click:Connect(function()
				obj.reset()
				showToast("СБРОШЕНО: " .. title, "info")
			end)
		end
		return obj
	end

	valueRow(42, "Полёт", 10, 10, 300, flySpeed, function(v) flySpeed = v end, nil)

	local walkRow = valueRow(88, "Скорость", 4, 0, 500, DEF.walk,
		function(v) custom.walk = v end,
		function()
			custom.walk = nil
			local hum = getHum(player)
			if hum then hum.WalkSpeed = DEF.walk end
		end)

	local jumpRow = valueRow(134, "Прыжок", 10, 0, 500, DEF.jump,
		function(v) custom.jump = v end,
		function()
			custom.jump = nil
			local hum = getHum(player)
			if hum then hum.JumpPower = DEF.jump end
		end)

	local gravRow = valueRow(180, "Гравитация", 20, 0, 500, DEF.grav,
		function(v) custom.grav = v end,
		function()
			custom.grav = nil
			Workspace.Gravity = DEF.grav
		end)

	local resetAll = glassButton(page, UDim2.new(1, -32, 0, 34), UDim2.fromOffset(16, 226), "Сбросить скорость, прыжок и гравитацию", 12, 12)
	resetAll.MouseButton1Click:Connect(function()
		walkRow.reset()
		jumpRow.reset()
		gravRow.reset()
		showToast("ВСЁ СБРОШЕНО", "info")
	end)

	-- Noclip: каждый физический шаг отключаем коллизию частей персонажа
	track(RunService.Stepped:Connect(function()
		if not noclipOn then return end
		local char = player.Character
		if not char then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				touched[p] = true
				p.CanCollide = false
			end
		end
	end))

	-- Скорость, прыжок, гравитация и полёт
	table.insert(stepFns, function()
		local hum, hrp = getHum(player), getHRP(player)

		if hum then
			if custom.walk and hum.WalkSpeed ~= custom.walk then
				hum.WalkSpeed = custom.walk
			end
			if custom.jump then
				if not hum.UseJumpPower then
					hum.UseJumpPower = true
				end
				if hum.JumpPower ~= custom.jump then
					hum.JumpPower = custom.jump
				end
			end
		end
		if custom.grav and Workspace.Gravity ~= custom.grav then
			Workspace.Gravity = custom.grav
		end

		if flyOn and hum and hrp then
			local cam = Workspace.CurrentCamera
			local dir = hum.MoveDirection * flySpeed
			local vy = 0
			if flyUp.down or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				vy = flySpeed
			elseif flyDown.down or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				vy = -flySpeed
			end
			hum.PlatformStand = true
			hrp.AssemblyLinearVelocity = Vector3.new(dir.X, vy, dir.Z)
			hrp.AssemblyAngularVelocity = Vector3.zero
			if cam then
				local look = cam.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.01 then
					hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
				end
			end
		end
	end)

	table.insert(cleanups, function()
		if flyOn then
			setFly(false)
		end
		if noclipOn then
			setNoclip(false)
		end
		custom.walk, custom.jump, custom.grav = nil, nil, nil
		Workspace.Gravity = DEF.grav
		local hum = getHum(player)
		if hum then
			hum.WalkSpeed = DEF.walk
			hum.JumpPower = DEF.jump
		end
	end)
end

-- СТРАНИЦА 7: ПРОЧЕЕ
do
	local page = pages[7]

	-- Анти-АФК
	local afkOn = false
	local afkConn = nil
	local afkCount = 0

	local aCard = card(page, UDim2.new(1, -32, 0, 76), UDim2.fromOffset(16, 4), 12)
	label(aCard, "Анти-АФК", UDim2.fromOffset(150, 28), UDim2.fromOffset(12, 8), 14)
	local afkBtn = make("TextButton", {
		Size = UDim2.fromOffset(74, 28),
		Position = UDim2.new(1, -86, 0, 8),
		BackgroundColor3 = C.off,
		BackgroundTransparency = 0.4,
		Text = "ВЫКЛ",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.white,
		AutoButtonColor = false,
	}, aCard)
	corner(afkBtn, 14)
	make("UIStroke", {
		Color = C.white,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, afkBtn)
	pressable(afkBtn, 0.4, 0.25)

	local afkInfo = label(aCard, "Не даёт кикнуть за бездействие. Срабатываний: 0",
		UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 40), 11, C.sub, Enum.Font.Gotham)
	afkInfo.TextWrapped = true

	local function setAfk(on)
		afkOn = on
		afkBtn.Text = on and "ВКЛ" or "ВЫКЛ"
		tween(afkBtn, 0.3, { BackgroundColor3 = on and C.green or C.off })
		if on and not afkConn then
			afkConn = player.Idled:Connect(function()
				pcall(function()
					VirtualUser:CaptureController()
					VirtualUser:ClickButton2(Vector2.new(0, 0))
				end)
				afkCount += 1
				afkInfo.Text = "Не даёт кикнуть за бездействие. Срабатываний: " .. afkCount
			end)
		elseif not on and afkConn then
			afkConn:Disconnect()
			afkConn = nil
		end
	end
	afkBtn.MouseButton1Click:Connect(function()
		setAfk(not afkOn)
		showToast(afkOn and "АНТИ-АФК ВКЛЮЧЕН" or "АНТИ-АФК ВЫКЛЮЧЕН", afkOn and "ok" or "warn")
	end)
	table.insert(cleanups, function()
		if afkConn then
			afkConn:Disconnect()
			afkConn = nil
		end
	end)

	-- Подсказки
	local hCard = card(page, UDim2.new(1, -32, 0, 92), UDim2.fromOffset(16, 88), 12)
	local hint = label(hCard,
		"Right Shift - скрыть или показать окно.\nОкно двигается за шапку, вкладки листаются свайпом.\nКнопка X сворачивает окно в круглую каплю UF, нажми на неё чтобы открыть снова.",
		UDim2.new(1, -24, 1, -16), UDim2.fromOffset(12, 8), 12, C.sub, Enum.Font.Gotham)
	hint.TextWrapped = true
	hint.TextYAlignment = Enum.TextYAlignment.Top

	-- Выгрузка
	local unloadBtn = glassButton(page, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 192), "Выгрузить клиент", 14, 14)
	unloadBtn.BackgroundColor3 = C.red
	unloadBtn.BackgroundTransparency = 0.6
	unloadBtn.MouseButton1Click:Connect(function()
		unload()
	end)

	label(page, CLIENT_NAME, UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 246), 11, C.gray, Enum.Font.GothamBold, Enum.TextXAlignment.Center)

	-- Анти-АФК включен по умолчанию
	setAfk(true)
end

-- ОКНО: вкладки, открытие, сворачивание
local mainDrag = makeDraggable(header, main)
local orbDrag = makeDraggable(orb, orb)

local function setTab(i)
	if i == currentTab then return end
	local fromIdx = currentTab
	local from, to = pages[fromIdx], pages[i]
	local dir = i > fromIdx and 1 or -1
	currentTab = i

	tween(tabInd, 0.4, { Position = UDim2.fromOffset((i - 1) * TAB_W + 2, 2) }, QUINT)
	local maxScroll = math.max(TAB_W * TAB_COUNT - TAB_VIEW, 0)
	local want = math.clamp((i - 1) * TAB_W - (TAB_VIEW - TAB_W) / 2, 0, maxScroll)
	tween(tabScroll, 0.4, { CanvasPosition = Vector2.new(want, 0) }, QUINT)
	for idx, b in ipairs(tabBtns) do
		tween(b, 0.25, { TextColor3 = idx == i and C.white or C.sub })
	end

	tween(from, 0.2, { GroupTransparency = 1 })
	task.delay(0.2, function()
		if currentTab ~= fromIdx then
			from.Visible = false
		end
	end)

	to.Position = UDim2.fromOffset(dir * 24, 0)
	to.GroupTransparency = 1
	to.Visible = true
	tween(to, 0.4, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, QUINT)
end

local function setOpen(show)
	if show == open then return end
	open = show

	if show then
		tween(orbScale, 0.2, { Scale = 0 }, QUAD, IN)
		task.delay(0.2, function()
			if open then orb.Visible = false end
		end)

		local target = UDim2.new(
			orb.Position.X.Scale, orb.Position.X.Offset,
			orb.Position.Y.Scale, orb.Position.Y.Offset - 22
		)
		main.Position = target + UDim2.fromOffset(0, 26)
		mainScale.Scale = 0.8
		main.GroupTransparency = 1
		main.Visible = true

		tween(mainScale, 0.55, { Scale = 1 }, BACK)
		tween(main, 0.35, { GroupTransparency = 0 })
		tween(main, 0.55, { Position = target }, QUINT)
	else
		orb.Position = UDim2.new(
			main.Position.X.Scale, main.Position.X.Offset,
			main.Position.Y.Scale, main.Position.Y.Offset + 22
		)
		tween(mainScale, 0.3, { Scale = 0.7 }, QUINT, IN)
		tween(main, 0.3, { GroupTransparency = 1 }, QUAD, IN)

		task.delay(0.28, function()
			if not open then
				main.Visible = false
				orb.Visible = true
				orbScale.Scale = 0
				tween(orbScale, 0.55, { Scale = 1 }, BACK)
			end
		end)
	end
end

local function setMinimized(min)
	minimized = min
	minBtn.Text = min and "+" or "-"
	tween(main, 0.4, { Size = UDim2.fromOffset(WIN_W, min and 44 or FULL_H) }, QUINT)
end

minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
orb.MouseButton1Click:Connect(function()
	if not orbDrag.moved then setOpen(true) end
end)
for i, b in ipairs(tabBtns) do
	b.MouseButton1Click:Connect(function() setTab(i) end)
end

track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == TOGGLE_KEY then
		setOpen(not open)
	end
end))

-- Главный цикл
local reported = {}
track(RunService.Heartbeat:Connect(function(dt)
	for _, g in ipairs(edgeGrads) do
		g.Rotation = (g.Rotation + dt * 45) % 360
	end
	for _, f in ipairs(stepFns) do
		local ok, err = pcall(f, dt)
		if not ok and not reported[f] then
			reported[f] = true
			warn("[" .. CLIENT_NAME .. "] " .. tostring(err))
		end
	end
end))

-- Выгрузка клиента
unload = function()
	for _, f in ipairs(cleanups) do
		pcall(f)
	end
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	pcall(function() espFolder:Destroy() end)
	pcall(function() gui:Destroy() end)
end

pcall(function()
	local env = (getgenv and getgenv()) or _G
	env.UltrafuckUnload = unload
end)

-- Запуск
setOpen(true)
