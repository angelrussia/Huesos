-- Auto Teleport • Liquid Glass v3 (для экзекьютера)
-- Вставь код целиком и нажми Execute

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- ⚙️ Настройки
local DEFAULT_TARGET = Vector3.new(-202, 800, -88) -- координаты по умолчанию (для сброса)
local TARGET = DEFAULT_TARGET
local INTERVAL = 4                         -- кулдаун по умолчанию (сек)
local MIN_CD, MAX_CD = 0.5, 60
local TOGGLE_KEY = Enum.KeyCode.RightShift  -- показать/скрыть окно
local TOAST_TIME = 1.6                     -- сколько висит уведомление
local FULL_H = 360                         -- высота окна

-- 🎨 Палитра
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
for _, name in ipairs({ "AutoTeleportGlass", "AutoTeleportESP" }) do
	local old = guiParent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- 🧰 Хелперы
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

-- Бегущий блик по краю (стекло)
local edgeGrads = {}
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

-- Слой "жидкого стекла" (чуть меньше родителя, чтобы обводка не обрезалась CanvasGroup)
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

-- Стеклянная карточка
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

-- Эффект нажатия: наведение + "сквиш"
local function pressable(btn, restT, hoverT, hoverColor)
	local restColor = btn.BackgroundColor3
	local s = make("UIScale", { Scale = 1 }, btn)
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
		tween(s, 0.3, { Scale = 1 }, BACK)
	end)
	btn.MouseButton1Down:Connect(function()
		tween(s, 0.1, { Scale = 0.93 })
	end)
	btn.MouseButton1Up:Connect(function()
		tween(s, 0.4, { Scale = 1 }, BACK)
	end)
end

-- Стеклянная кнопка
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
	UserInputService.InputChanged:Connect(function(input)
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
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return state
end

-- 🖼️ ScreenGui и контейнер ESP
local gui = make("ScreenGui", {
	Name = "AutoTeleportGlass",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

local espFolder = make("Folder", { Name = "AutoTeleportESP" }, guiParent)

-- ═══════════ ГЛАВНОЕ ОКНО ═══════════
local main = make("CanvasGroup", {
	Size = UDim2.fromOffset(300, FULL_H),
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

make("TextLabel", {
	Size = UDim2.new(1, -130, 1, 0),
	Position = UDim2.fromOffset(38, 0),
	BackgroundTransparency = 1,
	Text = "Auto Teleport",
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

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

local minBtn = headerBtn("–", -76, 18)
local closeBtn = headerBtn("✕", -42, 13)
pressable(minBtn, 0.88, 0.7)
pressable(closeBtn, 0.88, 0.4, C.red)

-- Вкладки
local tabBar = make("Frame", {
	Size = UDim2.new(1, -32, 0, 30),
	Position = UDim2.fromOffset(16, 46),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 0.92,
	BorderSizePixel = 0,
}, main)
corner(tabBar, 15)
make("UIStroke", {
	Color = C.white,
	Transparency = 0.82,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, tabBar)

local tabInd = make("Frame", {
	Size = UDim2.new(1 / 3, -4, 1, -4),
	Position = UDim2.fromOffset(2, 2),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 0.78,
	BorderSizePixel = 0,
}, tabBar)
corner(tabInd, 13)
make("UIStroke", {
	Color = C.white,
	Transparency = 0.6,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, tabInd)

local function tabButton(text, xScale)
	return make("TextButton", {
		Size = UDim2.fromScale(1 / 3, 1),
		Position = UDim2.fromScale(xScale, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = C.sub,
		AutoButtonColor = false,
		ZIndex = 2,
	}, tabBar)
end
local tabBtns = { tabButton("📍 Телепорт", 0), tabButton("📌 Места", 1 / 3), tabButton("👥 Игроки", 2 / 3) }
tabBtns[1].TextColor3 = C.white

-- Тело
local body = make("Frame", {
	Size = UDim2.new(1, 0, 0, 280),
	Position = UDim2.fromOffset(0, 80),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, main)

local function makePage(visible)
	return make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = visible and 0 or 1,
		Visible = visible,
	}, body)
end
local pages = { makePage(true), makePage(false), makePage(false) }
local page1, page2, page3 = pages[1], pages[2], pages[3]

-- ═══════════ СТРАНИЦА 1: ТЕЛЕПОРТ ═══════════

-- Координаты
local coordCard = card(page1, UDim2.new(1, -32, 0, 76), UDim2.fromOffset(16, 4), 12)
make("TextLabel", {
	Size = UDim2.fromOffset(130, 28),
	Position = UDim2.fromOffset(12, 6),
	BackgroundTransparency = 1,
	Text = "📍 Координаты",
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Left,
}, coordCard)

local resetBtn = glassButton(coordCard, UDim2.fromOffset(34, 26), UDim2.new(1, -46, 0, 7), "↺", 16, 13)
local pinBtn = glassButton(coordCard, UDim2.fromOffset(34, 26), UDim2.new(1, -84, 0, 7), "📌", 13, 13)

local axisBoxes = {}
local function axisField(axis, x)
	local f = make("Frame", {
		Size = UDim2.fromOffset(76, 28),
		Position = UDim2.fromOffset(x, 40),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, coordCard)
	corner(f, 14)
	make("TextLabel", {
		Size = UDim2.fromOffset(22, 28),
		Position = UDim2.fromOffset(4, 0),
		BackgroundTransparency = 1,
		Text = axis,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.cyan,
	}, f)
	local box = make("TextBox", {
		Size = UDim2.fromOffset(50, 28),
		Position = UDim2.fromOffset(24, 0),
		BackgroundTransparency = 1,
		Text = "0",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.white,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, f)
	axisBoxes[axis] = box
	return box
end
axisField("X", 12)
axisField("Y", 96)
axisField("Z", 180)

local function refreshBoxes()
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

-- Кулдаун
local cdCard = card(page1, UDim2.new(1, -32, 0, 52), UDim2.fromOffset(16, 86), 12)
make("TextLabel", {
	Size = UDim2.fromOffset(100, 52),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Text = "⏱ Кулдаун",
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Left,
}, cdCard)

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
local minusBtn = glassButton(cdCard, UDim2.fromOffset(30, 30), UDim2.new(1, -134, 0.5, -15), "–", 18, 15)

-- Прогресс-бар
local barBg = make("Frame", {
	Size = UDim2.new(1, -32, 0, 8),
	Position = UDim2.fromOffset(16, 148),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
}, page1)
corner(barBg, 4)

local barFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
}, barBg)
corner(barFill, 4)
make("UIGradient", { Color = ColorSequence.new(C.accent, C.cyan) }, barFill)

local timerLabel = make("TextLabel", {
	Size = UDim2.new(1, -32, 0, 20),
	Position = UDim2.fromOffset(16, 160),
	BackgroundTransparency = 1,
	Text = "Выключено",
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = C.sub,
}, page1)

-- Кнопка ВКЛ/ВЫКЛ
local toggleBtn = make("TextButton", {
	Size = UDim2.new(1, -32, 0, 44),
	Position = UDim2.fromOffset(16, 188),
	BackgroundColor3 = C.accent,
	BackgroundTransparency = 0.3,
	Text = "▶  Включить",
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = C.white,
	AutoButtonColor = false,
}, page1)
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

-- Телепорт сейчас
local nowBtn = glassButton(page1, UDim2.new(1, -32, 0, 34), UDim2.fromOffset(16, 240), "Телепорт сейчас", 14, 12)
nowBtn.Font = Enum.Font.GothamMedium

-- ═══════════ СТРАНИЦА 3: ИГРОКИ ═══════════

-- ESP
local espCard = card(page3, UDim2.new(1, -32, 0, 80), UDim2.fromOffset(16, 4), 12)
make("TextLabel", {
	Size = UDim2.fromOffset(150, 28),
	Position = UDim2.fromOffset(12, 8),
	BackgroundTransparency = 1,
	Text = "👁 ESP игроков",
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Left,
}, espCard)

local espBtn = make("TextButton", {
	Size = UDim2.fromOffset(74, 28),
	Position = UDim2.new(1, -86, 0, 8),
	BackgroundColor3 = C.off,
	BackgroundTransparency = 0.4,
	Text = "ВЫКЛ",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = C.white,
	AutoButtonColor = false,
}, espCard)
corner(espBtn, 14)
make("UIStroke", {
	Color = C.white,
	Transparency = 0.7,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, espBtn)
pressable(espBtn, 0.4, 0.25)

-- Палитра цветов ESP
local espColor = Color3.fromRGB(255, 85, 105)
local rainbow = false

local swatchDefs = {
	{ Color3.fromRGB(255, 85, 105) },
	{ Color3.fromRGB(255, 160, 60) },
	{ Color3.fromRGB(255, 225, 80) },
	{ Color3.fromRGB(70, 215, 140) },
	{ Color3.fromRGB(80, 210, 255) },
	{ Color3.fromRGB(160, 100, 255) },
	{ Color3.fromRGB(255, 110, 200) },
	{ Color3.fromRGB(255, 255, 255) },
	{ nil, true }, -- 🌈 радуга
}
local swatches = {}

-- ESP: объекты и логика
local espEnabled = false
local espObjects = {}

local function getEspColor()
	if rainbow then
		return Color3.fromHSV((tick() % 5) / 5, 0.85, 1)
	end
	return espColor
end

local function applyEspColor()
	local col = getEspColor()
	for _, o in pairs(espObjects) do
		o.hl.FillColor = col
		o.hl.OutlineColor = col
		o.lbl.TextColor3 = col
	end
end

local function selectSwatch(idx)
	local def = swatchDefs[idx]
	if def[2] then
		rainbow = true
	else
		rainbow = false
		espColor = def[1]
	end
	for i, s in ipairs(swatches) do
		tween(s.stroke, 0.2, { Transparency = i == idx and 0 or 1 })
		tween(s.scale, 0.3, { Scale = i == idx and 1.18 or 1 }, BACK)
	end
	applyEspColor()
end

for i, def in ipairs(swatchDefs) do
	local b = make("TextButton", {
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(12 + (i - 1) * 27, 46),
		BackgroundColor3 = def[2] and C.white or def[1],
		Text = "",
		AutoButtonColor = false,
	}, espCard)
	corner(b, 11)
	if def[2] then
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

local function removeESP(plr)
	local o = espObjects[plr]
	if o then
		o.hl:Destroy()
		o.bb:Destroy()
		espObjects[plr] = nil
	end
end

local function addESP(plr)
	removeESP(plr)
	local char = plr.Character
	if not char then return end
	task.spawn(function()
		local head = char:WaitForChild("Head", 5)
		if not head or not espEnabled or plr.Character ~= char or espObjects[plr] then
			return
		end
		local col = getEspColor()
		local hl = make("Highlight", {
			Adornee = char,
			FillColor = col,
			OutlineColor = col,
			FillTransparency = 0.65,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		}, espFolder)
		local bb = make("BillboardGui", {
			Adornee = head,
			Size = UDim2.fromOffset(150, 30),
			StudsOffset = Vector3.new(0, 2.6, 0),
			AlwaysOnTop = true,
			ResetOnSpawn = false,
		}, espFolder)
		local lbl = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = plr.Name,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = col,
			TextStrokeTransparency = 0.4,
		}, bb)
		espObjects[plr] = { hl = hl, bb = bb, lbl = lbl, plr = plr }
	end)
end

local function hookPlayer(plr)
	if plr == player then return end
	plr.CharacterAdded:Connect(function()
		if espEnabled then addESP(plr) end
	end)
	plr.CharacterRemoving:Connect(function()
		removeESP(plr)
	end)
	if espEnabled then addESP(plr) end
end

local function setESP(on)
	espEnabled = on
	espBtn.Text = on and "ВКЛ" or "ВЫКЛ"
	tween(espBtn, 0.3, { BackgroundColor3 = on and C.green or C.off })
	if on then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then addESP(p) end
		end
	else
		for p in pairs(espObjects) do
			removeESP(p)
		end
	end
end

-- Список игроков
local playersLabel = make("TextLabel", {
	Size = UDim2.new(1, -32, 0, 18),
	Position = UDim2.fromOffset(16, 92),
	BackgroundTransparency = 1,
	Text = "👥 Игроки онлайн: 0",
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, page3)

local listFrame = make("ScrollingFrame", {
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
}, page3)
make("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, listFrame)

local emptyLabel = make("TextLabel", {
	Size = UDim2.new(1, -32, 0, 40),
	Position = UDim2.fromOffset(16, 130),
	BackgroundTransparency = 1,
	Text = "Других игроков нет",
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = C.sub,
	Visible = false,
}, page3)

-- ═══════════ ПЛАВАЮЩАЯ КАПЛЯ ═══════════
local orb = make("TextButton", {
	Size = UDim2.fromOffset(52, 52),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -FULL_H / 2 + 22),
	BackgroundColor3 = C.accent,
	BackgroundTransparency = 0.35,
	Text = "⚡",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
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

-- ═══════════ УВЕДОМЛЕНИЕ СНИЗУ ═══════════
local TOAST_W, TOAST_H = 250, 50
local TOAST_SHOWN = UDim2.new(0.5, 0, 1, -70)
local TOAST_HIDDEN = UDim2.new(0.5, 0, 1, 40)
local DEFAULT_TOAST = "✅  ТЕЛЕПОРТИРОВАНО"

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

local toastLabel = make("TextLabel", {
	Size = UDim2.fromOffset(TOAST_W - 24, TOAST_H),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	Text = DEFAULT_TOAST,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = C.white,
	TextTransparency = 1,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, toast)

local toastToken = 0
local toastShown = false

local function showToast(text)
	toastToken += 1
	local my = toastToken
	toastLabel.Text = text or DEFAULT_TOAST

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

-- ═══════════ ЛОГИКА ═══════════
local enabled = false
local minimized = false
local open = false
local timeLeft = INTERVAL
local currentTab = 1

local mainDrag = makeDraggable(header, main)
local orbDrag = makeDraggable(orb, orb)

local function getHRP(plr)
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleport()
	local hrp = getHRP(player)
	if hrp then
		hrp.CFrame = CFrame.new(TARGET)
		showToast()
	end
end

local function teleportToPlayer(plr)
	local me, them = getHRP(player), getHRP(plr)
	if me and them then
		me.CFrame = CFrame.new(them.Position + Vector3.new(0, 4, 0))
		showToast("✅  ТП К " .. plr.Name)
	else
		showToast("⚠️  ИГРОК НЕДОСТУПЕН")
	end
end

local function refreshList()
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

	playersLabel.Text = string.format("👥 Игроки онлайн: %d", #others)
	emptyLabel.Visible = #others == 0

	for i, p in ipairs(others) do
		local row = card(listFrame, UDim2.new(1, -6, 0, 38), UDim2.new(), 12)
		row.LayoutOrder = i

		local shown = p.Name
		if p.DisplayName ~= p.Name then
			shown = p.DisplayName .. " (@" .. p.Name .. ")"
		end
		make("TextLabel", {
			Size = UDim2.new(1, -76, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Text = shown,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = C.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)

		local btn = make("TextButton", {
			Size = UDim2.fromOffset(52, 26),
			Position = UDim2.new(1, -60, 0.5, -13),
			BackgroundColor3 = C.accent,
			BackgroundTransparency = 0.35,
			Text = "ТП",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = C.white,
			AutoButtonColor = false,
		}, row)
		corner(btn, 13)
		pressable(btn, 0.35, 0.15)
		btn.MouseButton1Click:Connect(function()
			teleportToPlayer(p)
		end)
	end
end

local function setEnabled(on)
	enabled = on
	timeLeft = INTERVAL
	tween(toggleBtn, 0.3, { BackgroundColor3 = on and C.green or C.accent })
	tween(dot, 0.3, { BackgroundColor3 = on and C.green or C.gray })
	toggleBtn.Text = on and "⏹  Выключить" or "▶  Включить"
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

local function setTab(i)
	if i == currentTab then return end
	local fromIdx = currentTab
	local from, to = pages[fromIdx], pages[i]
	local dir = i > fromIdx and 1 or -1
	currentTab = i

	local tabPos = { UDim2.fromOffset(2, 2), UDim2.new(1 / 3, 2, 0, 2), UDim2.new(2 / 3, 2, 0, 2) }
	tween(tabInd, 0.4, { Position = tabPos[i] }, QUINT)
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
	minBtn.Text = min and "+" or "–"
	tween(main, 0.4, { Size = UDim2.fromOffset(300, min and 44 or FULL_H) }, QUINT)
end

-- События
toggleBtn.MouseButton1Click:Connect(function() setEnabled(not enabled) end)
nowBtn.MouseButton1Click:Connect(teleport)
minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
orb.MouseButton1Click:Connect(function()
	if not orbDrag.moved then setOpen(true) end
end)

tabBtns[1].MouseButton1Click:Connect(function() setTab(1) end)
tabBtns[2].MouseButton1Click:Connect(function() setTab(2) end)
tabBtns[3].MouseButton1Click:Connect(function() setTab(3) end)

plusBtn.MouseButton1Click:Connect(function() setInterval(INTERVAL + 0.5) end)
minusBtn.MouseButton1Click:Connect(function() setInterval(INTERVAL - 0.5) end)
cdBox.FocusLost:Connect(function() setInterval(cdBox.Text) end)

resetBtn.MouseButton1Click:Connect(function()
	TARGET = DEFAULT_TARGET
	refreshBoxes()
	showToast("↺  КООРДИНАТЫ СБРОШЕНЫ")
end)

pinBtn.MouseButton1Click:Connect(function()
	local hrp = getHRP(player)
	if hrp then
		local p = hrp.Position
		TARGET = Vector3.new(math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
		refreshBoxes()
		showToast("📌  ПОЗИЦИЯ СОХРАНЕНА")
	end
end)

espBtn.MouseButton1Click:Connect(function() setESP(not espEnabled) end)

-- ═══════════ СТРАНИЦА 2: СОХРАНЁННЫЕ МЕСТА ═══════════
-- Места сохраняются в файл (отдельно для каждой игры), если экзекьютер умеет writefile
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

-- Карточка добавления
local addCard = card(page2, UDim2.new(1, -32, 0, 76), UDim2.fromOffset(16, 4), 12)
local nameBox = make("TextBox", {
	Size = UDim2.new(1, -24, 0, 28),
	Position = UDim2.fromOffset(12, 8),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.55,
	Text = "",
	PlaceholderText = "✏️ Название места",
	PlaceholderColor3 = C.gray,
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextColor3 = C.white,
	ClearTextOnFocus = false,
}, addCard)
corner(nameBox, 14)

local saveHereBtn = glassButton(addCard, UDim2.new(0.5, -16, 0, 28), UDim2.fromOffset(12, 40), "📌 Где я", 12, 14)
local saveFieldsBtn = glassButton(addCard, UDim2.new(0.5, -16, 0, 28), UDim2.new(0.5, 4, 0, 40), "📍 Из полей", 12, 14)

local savedLabel = make("TextLabel", {
	Size = UDim2.new(1, -32, 0, 18),
	Position = UDim2.fromOffset(16, 92),
	BackgroundTransparency = 1,
	Text = "📌 Сохранённые места: 0",
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, page2)

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
}, page2)
make("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, savedList)

local savedEmpty = make("TextLabel", {
	Size = UDim2.new(1, -48, 0, 50),
	Position = UDim2.fromOffset(24, 134),
	BackgroundTransparency = 1,
	Text = "Пока пусто.\nСохрани свою позицию или координаты из полей",
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = C.sub,
	TextWrapped = true,
	Visible = false,
}, page2)

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

	savedLabel.Text = string.format("📌 Сохранённые места: %d", #saved)
	savedEmpty.Visible = #saved == 0

	for i, entry in ipairs(saved) do
		local row = card(savedList, UDim2.new(1, -6, 0, 52), UDim2.new(), 12)
		row.LayoutOrder = i

		-- название (можно редактировать прямо в списке)
		local nb = make("TextBox", {
			Size = UDim2.new(1, -130, 0, 22),
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

		make("TextLabel", {
			Size = UDim2.new(1, -130, 0, 18),
			Position = UDim2.fromOffset(12, 28),
			BackgroundTransparency = 1,
			Text = string.format("X %g   Y %g   Z %g", entry.x, entry.y, entry.z),
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		-- 🎯 сделать целью автотелепорта
		local aimBtn = rowButton(row, UDim2.fromOffset(28, 26), UDim2.new(1, -110, 0.5, -13), "🎯", 12)
		pressable(aimBtn, 0.86, 0.65)
		aimBtn.MouseButton1Click:Connect(function()
			TARGET = Vector3.new(entry.x, entry.y, entry.z)
			refreshBoxes()
			showToast("🎯  ЦЕЛЬ: " .. entry.name)
		end)

		-- ТП сейчас
		local goBtn = rowButton(row, UDim2.fromOffset(40, 26), UDim2.new(1, -78, 0.5, -13), "ТП", 12)
		goBtn.BackgroundColor3 = C.accent
		goBtn.BackgroundTransparency = 0.35
		pressable(goBtn, 0.35, 0.15)
		goBtn.MouseButton1Click:Connect(function()
			local hrp = getHRP(player)
			if hrp then
				hrp.CFrame = CFrame.new(entry.x, entry.y, entry.z)
				showToast("✅  ТП: " .. entry.name)
			end
		end)

		-- 🗑 удалить
		local delBtn = rowButton(row, UDim2.fromOffset(28, 26), UDim2.new(1, -34, 0.5, -13), "✕", 12)
		pressable(delBtn, 0.86, 0.4, C.red)
		delBtn.MouseButton1Click:Connect(function()
			local idx = table.find(saved, entry)
			if idx then
				table.remove(saved, idx)
			end
			persist()
			refreshSaved()
			showToast("🗑  УДАЛЕНО: " .. entry.name)
		end)
	end
end

local function addPlace(name, v)
	if #saved >= MAX_PLACES then
		showToast("⚠️  ЛИМИТ МЕСТ: " .. MAX_PLACES)
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
	showToast("💾  СОХРАНЕНО: " .. name)
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

Players.PlayerAdded:Connect(function(p)
	hookPlayer(p)
	refreshList()
end)
Players.PlayerRemoving:Connect(function(p)
	removeESP(p)
	task.defer(refreshList)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == TOGGLE_KEY then
		setOpen(not open)
	end
end)

-- 🔁 Главный цикл
local espAccum = 0
RunService.Heartbeat:Connect(function(dt)
	-- бегущие блики стекла
	for _, g in ipairs(edgeGrads) do
		g.Rotation = (g.Rotation + dt * 45) % 360
	end

	-- автотелепорт
	if enabled then
		timeLeft -= dt
		if timeLeft <= 0 then
			teleport()
			timeLeft = INTERVAL
		end
		barFill.Size = UDim2.fromScale(math.clamp(1 - timeLeft / INTERVAL, 0, 1), 1)
		timerLabel.Text = string.format("Следующий ТП через %.1f с", math.max(timeLeft, 0))
	end

	-- ESP: радуга и дистанция
	if espEnabled then
		if rainbow then
			applyEspColor()
		end
		espAccum += dt
		if espAccum >= 0.25 then
			espAccum = 0
			local me = getHRP(player)
			for plr, o in pairs(espObjects) do
				local them = getHRP(plr)
				if me and them then
					local dist = (me.Position - them.Position).Magnitude
					o.lbl.Text = string.format("%s  [%dm]", plr.Name, dist)
				else
					o.lbl.Text = plr.Name
				end
			end
		end
	end
end)

-- Запуск
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
refreshList()
loadSaved()
refreshSaved()
selectSwatch(1)
setOpen(true)
