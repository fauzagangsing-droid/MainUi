--[[
    AstralHub 2.0 - an independent, client-side Roblox UI library.

    local Window = AstralHub:CreateWindow({
        Title = "AstralHub",
        Subtitle = "Your subtitle",
    })
    local Misc = Window:AddTab({ Name = "Misc", Icon = "⚙️" })
    Misc:AddToggle({ Name = "Example", Default = false, Callback = print })
]]

local AstralHub = {}
AstralHub.__index = AstralHub

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local HUB_ICON_ASSET = "rbxassetid://101879171935546"
local OWNER_ATTRIBUTE = "AstralHubOwned"
local CLEANUP_EVENT = "AstralHubCleanup"
local DRAG_THRESHOLD = 6
local MAX_NOTIFICATIONS = 3

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ZERO_UDIM2 = UDim2.new()
local ZERO_VECTOR2 = Vector2.new(0, 0)

local activeWindow

-- Solid dark purple palette inspired by Potassium UI (zero glassmorphism/translucency)
local COLORS = {
    panel = Color3.fromRGB(15, 12, 22),
    sidebar = Color3.fromRGB(20, 16, 30),
    panelSoft = Color3.fromRGB(26, 20, 38),
    panelRaised = Color3.fromRGB(34, 26, 49),
    primary = Color3.fromRGB(112, 72, 178),
    primaryHover = Color3.fromRGB(128, 86, 198),
    violet = Color3.fromRGB(184, 158, 226),
    white = Color3.fromRGB(246, 243, 255),
    muted = Color3.fromRGB(165, 153, 186),
    dim = Color3.fromRGB(110, 98, 132),
    line = Color3.fromRGB(45, 35, 64),
    lineBright = Color3.fromRGB(76, 56, 110),
    hover = Color3.fromRGB(36, 28, 52),
    danger = Color3.fromRGB(238, 126, 154),
    dangerHover = Color3.fromRGB(64, 30, 46),
    backdrop = Color3.fromRGB(10, 8, 15),
}

local function create(className, properties, parent)
    local instance = Instance.new(className)
    if properties then
        for property, value in pairs(properties) do
            instance[property] = value
        end
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

local function corner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function stroke(parent, color)
    return create("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = color or COLORS.line,
        Transparency = 0,
        Thickness = 1,
    }, parent)
end

local function padding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left),
        PaddingRight = UDim.new(0, right),
        PaddingTop = UDim.new(0, top),
        PaddingBottom = UDim.new(0, bottom),
    }, parent)
end

local function makeText(parent, text, size, color, font)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(text or ""),
        TextColor3 = color or COLORS.white,
        TextSize = size or 12,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local function makeButton(parent, text, size, position, color)
    local button = create("TextButton", {
        BackgroundColor3 = color or COLORS.panelSoft,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = COLORS.white,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        Size = size,
        Position = position,
    }, parent)
    corner(button, 6)
    return button
end

local function connect(owner, signal, callback)
    local connection = signal:Connect(callback)
    owner._connections[connection] = true
    return connection
end

local function disconnectAll(owner)
    for connection in pairs(owner._connections) do
        connection:Disconnect()
    end
    table.clear(owner._connections)
end

local function cancelTween(window, instance)
    local animation = window._tweens[instance]
    if animation then
        window._tweens[instance] = nil
        animation:Cancel()
        animation:Destroy()
    end
end

local function tween(window, instance, goal, duration)
    if window.Closed or not instance.Parent then
        return
    end
    cancelTween(window, instance)
    local info = duration and TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) or TWEEN_FAST
    local animation = TweenService:Create(instance, info, goal)
    window._tweens[instance] = animation
    animation:Play()
end

local function bindHover(window, button, baseColor, hoverColor)
    local targetHover = hoverColor or COLORS.hover
    connect(window, button.MouseEnter, function()
        if not window.Closed then
            cancelTween(window, button)
            button.BackgroundColor3 = targetHover
        end
    end)
    connect(window, button.MouseLeave, function()
        if not window.Closed then
            cancelTween(window, button)
            local resolved = type(baseColor) == "function" and baseColor() or baseColor
            button.BackgroundColor3 = resolved or COLORS.panelSoft
        end
    end)
end

local function invoke(callback, ...)
    if type(callback) == "function" then
        local ok, message = pcall(callback, ...)
        if not ok then
            warn("[AstralHub] Callback failed: " .. tostring(message))
        end
    end
end

local function numberOr(value, default)
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) == math.huge then
        return default
    end
    return number
end

local function buildSearchKey(name, description)
    if description ~= nil and description ~= "" then
        return string.lower(tostring(name or "") .. "\n" .. tostring(description))
    end
    return string.lower(tostring(name or ""))
end

local function snapSliderValue(value, minValue, maxValue, step)
    if maxValue <= minValue then
        return minValue
    end
    local clamped = math.clamp(value, minValue, maxValue)
    if step and step > 0 then
        local steps = math.floor((clamped - minValue) / step + 0.5)
        local snapped = minValue + steps * step
        snapped = tonumber(string.format("%.6g", snapped)) or snapped
        return math.clamp(snapped, minValue, maxValue)
    end
    return clamped
end

local function sanitizeNumeric(text)
    local sign = string.match(text, "^%-") or ""
    local body = string.gsub(text, "[^%d%.]", "")
    local dotIndex = string.find(body, "%.", 1)
    if dotIndex then
        body = string.sub(body, 1, dotIndex) .. string.gsub(string.sub(body, dotIndex + 1), "%.", "")
    end
    return sign .. body
end

function AstralHub:_clampPosition(target, position)
    local viewport = self.Overlay.AbsoluteSize
    local size = target == self.Panel and self._panelPixelSize or target.AbsoluteSize
    if not size or viewport.X <= 0 or viewport.Y <= 0 then
        return position
    end
    local marginX = math.min(12, math.max(0, (viewport.X - size.X) / 2))
    local marginY = math.min(12, math.max(0, (viewport.Y - size.Y) / 2))
    local x = position.X.Scale * viewport.X + position.X.Offset
    local y = position.Y.Scale * viewport.Y + position.Y.Offset
    return UDim2.fromOffset(
        math.clamp(x, marginX, math.max(marginX, viewport.X - size.X - marginX)),
        math.clamp(y, marginY, math.max(marginY, viewport.Y - size.Y - marginY))
    )
end

function AstralHub:_updateLayout()
    if self.Closed then
        return
    end
    local viewport = self.Overlay.AbsoluteSize
    if viewport.X <= 0 or viewport.Y <= 0 then
        return
    end
    local availableX = math.max(1, viewport.X - 24)
    local availableY = math.max(1, viewport.Y - 24)
    -- Reflow first; scale only when the screen cannot fit a usable two-column layout.
    local scale = math.min(1, availableX / 420, availableY / 300)
    local width = math.min(self._width, availableX / scale)
    local height = math.min(self._height, availableY / scale)
    self.PanelScale.Scale = scale
    self.Panel.Size = UDim2.fromOffset(width, height)
    self._panelPixelSize = Vector2.new(width * scale, height * scale)

    local railWidth = width < 500 and 126 or 148
    self.TabRail.Size = UDim2.new(0, railWidth, 1, 0)
    self.Divider.Position = UDim2.fromOffset(railWidth, 0)

    local contentLeft = railWidth + 12
    local contentWidth = -(railWidth + 24)
    self.Search.Position = UDim2.fromOffset(contentLeft, 10)
    self.Search.Size = UDim2.new(1, contentWidth, 0, 32)
    self.Content.Position = UDim2.fromOffset(contentLeft, 50)
    self.Content.Size = UDim2.new(1, contentWidth, 1, -58)

    if not self._positioned then
        self._positioned = true
        self.Panel.Position = UDim2.fromOffset(
            (viewport.X - self._panelPixelSize.X) / 2,
            (viewport.Y - self._panelPixelSize.Y) / 2
        )
    end
    self.Panel.Position = self:_clampPosition(self.Panel, self.Panel.Position)
    self.HubIcon.Position = self:_clampPosition(self.HubIcon, self.HubIcon.Position)
    self.DialogScale.Scale = math.min(1, availableX / 300, availableY / 162)
    if self.NotificationStack then
        self.NotificationStack.Size = UDim2.fromOffset(
            math.min(300, availableX), math.min(240, availableY)
        )
    end
    self:_cancelDrags()
end

function AstralHub:_cancelDrags()
    self._activeDrag = nil
    if self._activeSlider then
        self._activeSlider.Input = nil
        self._activeSlider = nil
    end
    for _, state in ipairs(self._drags) do
        state.Input = nil
    end
    if not self.Closed and self.HubIcon then
        cancelTween(self, self.HubIcon)
        self.HubIcon.BackgroundColor3 = COLORS.panelRaised
    end
end

function AstralHub:_moveDrag(state, position)
    local delta = Vector2.new(position.X - state.Start.X, position.Y - state.Start.Y)
    if not state.Moved and delta.Magnitude >= DRAG_THRESHOLD then
        state.Moved = true
    end
    if state.Moved then
        state.Target.Position = self:_clampPosition(state.Target, UDim2.fromOffset(
            state.Origin.X + delta.X, state.Origin.Y + delta.Y
        ))
    end
end

function AstralHub:_finishDrag(state, canceled)
    if not state.Input then
        return
    end
    local shouldActivate = not canceled and not state.Moved
    state.Input = nil
    if self._activeDrag == state then
        self._activeDrag = nil
    end
    if state.Target == self.HubIcon then
        self.HubIcon.BackgroundColor3 = COLORS.panelRaised
    end
    if shouldActivate and state.Activate then
        state.Activate()
    end
end

function AstralHub:_makeDraggable(handle, target, activate)
    target = target or self.Panel
    local state = { Target = target, Activate = activate }
    table.insert(self._drags, state)
    handle.Active = true
    connect(self, handle.InputBegan, function(input)
        local inputType = input.UserInputType
        if self.Closed or not self.Visible or self.DialogShade.Visible or self._activeDrag or self._activeSlider
            or (inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch)
            or (target == self.Panel and self.Minimized)
            or (target == self.HubIcon and not self.Minimized) then
            return
        end
        local viewport = self.Overlay.AbsoluteSize
        state.Input = input
        state.Start = input.Position
        state.Origin = Vector2.new(
            target.Position.X.Scale * viewport.X + target.Position.X.Offset,
            target.Position.Y.Scale * viewport.Y + target.Position.Y.Offset
        )
        state.Moved = false
        self._activeDrag = state
        if target == self.HubIcon then
            target.BackgroundColor3 = COLORS.hover
        end
    end)
end

function AstralHub:CreateWindow(options)
    options = options or {}
    local player = Players.LocalPlayer
    assert(player, "AstralHub must be created from a LocalScript")
    local playerGui = player:WaitForChild("PlayerGui")
    if activeWindow then
        activeWindow:Destroy()
    end
    -- The event also disposes connections when a separately loaded copy replaces us.
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui:GetAttribute(OWNER_ATTRIBUTE) == true then
            local cleanup = gui:FindFirstChild(CLEANUP_EVENT)
            if cleanup and cleanup:IsA("BindableEvent") then
                cleanup:Fire()
            end
            gui:Destroy()
        end
    end

    local window = setmetatable({
        Title = options.Title or options.Name or "AstralHub",
        Subtitle = options.Subtitle or "Your space, simplified",
        Icon = options.Icon or "⚙️",
        Theme = options.Theme or "Dark",
        Folder = options.Folder or "AstralHub",
        Visible = true,
        Minimized = false,
        Closed = false,
        Tabs = {},
        _connections = {},
        _tweens = {},
        _drags = {},
        _activeDrag = nil,
        _notifications = {},
        _toastPool = {},
        _query = "",
        _width = math.max(420, numberOr(options.Width, 580)),
        _height = math.max(300, numberOr(options.Height, 430)),
    }, AstralHub)
    activeWindow = window

    local screenGui = create("ScreenGui", {
        Name = "AstralHub",
        ResetOnSpawn = false,
        DisplayOrder = 30,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
    }, playerGui)
    screenGui:SetAttribute(OWNER_ATTRIBUTE, true)
    window.Gui = screenGui
    local cleanup = create("BindableEvent", { Name = CLEANUP_EVENT }, screenGui)
    connect(window, cleanup.Event, function()
        window:Destroy()
    end)
    connect(window, screenGui.Destroying, function()
        window:Destroy(true)
    end)

    local overlay = create("Frame", {
        Name = "Overlay",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ClipsDescendants = true,
    }, screenGui)
    window.Overlay = overlay

    local panel = create("Frame", {
        Name = "Panel",
        Size = UDim2.fromOffset(window._width, window._height),
        BackgroundColor3 = COLORS.panel,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, overlay)
    window.Panel = panel
    window.PanelScale = create("UIScale", { Scale = 1 }, panel)
    corner(panel, 8)
    stroke(panel, COLORS.lineBright)

    local topBar = create("Frame", {
        Name = "TopBar",
        BackgroundColor3 = COLORS.sidebar,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 48),
    }, panel)
    window.TopBar = topBar
    create("Frame", {
        Name = "TopBorder",
        BackgroundColor3 = COLORS.line,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
    }, topBar)

    local dragHandle = create("Frame", {
        Name = "DragHandle",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -84, 1, 0),
    }, topBar)
    create("ImageLabel", {
        Name = "Logo",
        BackgroundTransparency = 1,
        Image = HUB_ICON_ASSET,
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.fromOffset(12, 10),
    }, dragHandle)
    local title = makeText(dragHandle, window.Title, 14, COLORS.white, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(48, 7)
    title.Size = UDim2.new(1, -54, 0, 18)
    local subtitle = makeText(dragHandle, window.Subtitle, 11, COLORS.muted, Enum.Font.Gotham)
    subtitle.Position = UDim2.fromOffset(48, 25)
    subtitle.Size = UDim2.new(1, -54, 0, 14)

    local minimize = makeButton(topBar, "−", UDim2.fromOffset(28, 28), UDim2.new(1, -72, 0, 10))
    minimize.Name = "Minimize"
    minimize.TextSize = 18
    minimize.TextColor3 = COLORS.muted
    stroke(minimize, COLORS.line)
    bindHover(window, minimize, COLORS.panelSoft, COLORS.hover)

    local close = makeButton(topBar, "×", UDim2.fromOffset(28, 28), UDim2.new(1, -38, 0, 10))
    close.Name = "Close"
    close.TextSize = 18
    close.TextColor3 = COLORS.danger
    stroke(close, COLORS.line)
    bindHover(window, close, COLORS.panelSoft, COLORS.dangerHover)

    local body = create("Frame", {
        Name = "Body",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, -48),
        Position = UDim2.fromOffset(0, 48),
    }, panel)

    local tabRail = create("ScrollingFrame", {
        Name = "Tabs",
        BackgroundColor3 = COLORS.sidebar,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 148, 1, 0),
        CanvasSize = ZERO_UDIM2,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = COLORS.lineBright,
        ScrollBarImageTransparency = 0,
        ClipsDescendants = true,
    }, body)
    padding(tabRail, 8, 8, 8, 8)
    create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabRail)
    window.TabRail = tabRail

    window.Divider = create("Frame", {
        Name = "Divider",
        BackgroundColor3 = COLORS.line,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 1, 1, 0),
    }, body)

    local search = create("TextBox", {
        Name = "Search",
        BackgroundColor3 = COLORS.panelSoft,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        MultiLine = false,
        PlaceholderText = "Search controls...",
        PlaceholderColor3 = COLORS.dim,
        Text = "",
        TextColor3 = COLORS.white,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -172, 0, 32),
        Position = UDim2.fromOffset(160, 10),
    }, body)
    corner(search, 6)
    local searchStroke = stroke(search, COLORS.line)
    padding(search, 10, 10, 0, 0)
    window.Search = search

    connect(window, search.Focused, function()
        searchStroke.Color = COLORS.primary
    end)
    connect(window, search.FocusLost, function()
        searchStroke.Color = COLORS.line
    end)

    window.Content = create("Frame", {
        Name = "Content",
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, body)

    local empty = makeText(window.Content, "Select a tab to begin", 12, COLORS.dim, Enum.Font.GothamMedium)
    empty.Name = "EmptyState"
    empty.Size = UDim2.new(1, -16, 1, 0)
    empty.Position = UDim2.fromOffset(8, 0)
    empty.TextWrapped = true
    empty.TextXAlignment = Enum.TextXAlignment.Center
    empty.ZIndex = 2
    window.EmptyLabel = empty

    local minimized = create("ImageButton", {
        Name = "HubIcon",
        Position = UDim2.new(0, 16, 0.45, 0),
        Size = UDim2.fromOffset(46, 46),
        BackgroundColor3 = COLORS.panelRaised,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Image = HUB_ICON_ASSET,
        ScaleType = Enum.ScaleType.Fit,
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 3,
    }, overlay)
    corner(minimized, 8)
    stroke(minimized, COLORS.lineBright)
    window.HubIcon = minimized
    bindHover(window, minimized, COLORS.panelRaised, COLORS.hover)

    window:_createCloseDialog()
    window:_makeDraggable(dragHandle, panel)
    window:_makeDraggable(minimized, minimized, function()
        window:SetMinimized(false)
    end)

    connect(window, minimize.Activated, function()
        window:SetMinimized(true)
    end)
    connect(window, minimized.Activated, function(input)
        -- Pointer taps are handled on release by the drag recognizer, never twice.
        if input and input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            window:SetMinimized(false)
        end
    end)
    connect(window, close.Activated, function()
        window:_showCloseDialog()
    end)
    connect(window, search:GetPropertyChangedSignal("Text"), function()
        window:_filter(search.Text)
    end)
    connect(window, overlay:GetPropertyChangedSignal("AbsoluteSize"), function()
        window:_updateLayout()
    end)
    connect(window, UserInputService.InputChanged, function(input)
        local slider = window._activeSlider
        if slider then
            local start = slider.Input
            if start and ((start.UserInputType == Enum.UserInputType.Touch and input == start)
                or (start.UserInputType == Enum.UserInputType.MouseButton1
                    and input.UserInputType == Enum.UserInputType.MouseMovement)) then
                if input.UserInputState == Enum.UserInputState.Cancel then
                    slider.Input = nil
                    window._activeSlider = nil
                else
                    slider.Update(input.Position.X)
                end
            end
            return
        end
        local state = window._activeDrag
        if not state then
            return
        end
        local start = state.Input
        if start and ((start.UserInputType == Enum.UserInputType.Touch and input == start)
            or (start.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            if input.UserInputState == Enum.UserInputState.Cancel then
                window:_finishDrag(state, true)
            else
                window:_moveDrag(state, input.Position)
            end
        end
    end)
    connect(window, UserInputService.InputEnded, function(input)
        local slider = window._activeSlider
        if slider then
            local start = slider.Input
            if start and (input == start or (start.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1)) then
                if input.UserInputState ~= Enum.UserInputState.Cancel then
                    slider.Update(input.Position.X)
                end
                slider.Input = nil
                window._activeSlider = nil
            end
            return
        end
        local state = window._activeDrag
        if not state then
            return
        end
        local start = state.Input
        if start and (input == start or (start.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1)) then
            local canceled = input.UserInputState == Enum.UserInputState.Cancel
            if not canceled then
                window:_moveDrag(state, input.Position)
            end
            window:_finishDrag(state, canceled)
        end
    end)
    connect(window, UserInputService.WindowFocusReleased, function()
        window:_cancelDrags()
    end)
    window:_updateLayout()
    return window
end

function AstralHub:_createCloseDialog()
    local shade = create("TextButton", {
        Name = "DialogShade",
        Text = "",
        AutoButtonColor = false,
        Active = true,
        Modal = true,
        BackgroundColor3 = COLORS.backdrop,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 10,
    }, self.Overlay)
    self.DialogShade = shade

    local modal = create("Frame", {
        Name = "CloseDialog",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(300, 152),
        BackgroundColor3 = COLORS.panelRaised,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }, shade)
    corner(modal, 8)
    stroke(modal, COLORS.lineBright)
    self.CloseDialog = modal
    self.DialogScale = create("UIScale", { Scale = 1 }, modal)

    local title = makeText(modal, "Close AstralHub?", 14, COLORS.white, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(16, 16)
    title.Size = UDim2.new(1, -32, 0, 20)

    local copy = makeText(modal, "This removes the interface and its controls.", 12, COLORS.muted)
    copy.Position = UDim2.fromOffset(16, 42)
    copy.Size = UDim2.new(1, -32, 0, 38)
    copy.TextWrapped = true

    local cancel = makeButton(modal, "Cancel", UDim2.fromOffset(128, 32), UDim2.fromOffset(16, 104), COLORS.panelSoft)
    cancel.Name = "Cancel"
    stroke(cancel, COLORS.line)
    bindHover(self, cancel, COLORS.panelSoft, COLORS.hover)

    local confirm = makeButton(modal, "Close", UDim2.fromOffset(128, 32), UDim2.fromOffset(156, 104), COLORS.primary)
    confirm.Name = "Confirm"
    bindHover(self, confirm, COLORS.primary, COLORS.primaryHover)

    connect(self, cancel.Activated, function()
        self:_hideCloseDialog()
    end)
    connect(self, confirm.Activated, function()
        self:Destroy()
    end)
end

function AstralHub:_showCloseDialog()
    if self.Closed or not self.Visible or self.Minimized then
        return
    end
    self:_cancelDrags()
    self.Search:ReleaseFocus()
    self.DialogShade.Visible = true
end

function AstralHub:_hideCloseDialog()
    if not self.Closed then
        self.DialogShade.Visible = false
    end
end

function AstralHub:SetMinimized(minimized)
    if self.Closed then
        return
    end
    self:_cancelDrags()
    self:_hideCloseDialog()
    self.Search:ReleaseFocus()
    self.Minimized = minimized == true
    self.Panel.Visible = not self.Minimized
    self.HubIcon.Visible = self.Minimized
end

function AstralHub:SetVisible(visible)
    if self.Closed then
        return
    end
    self.Visible = visible == true
    self.Overlay.Visible = self.Visible
    if not self.Visible then
        self:_cancelDrags()
        self:_hideCloseDialog()
        self.Search:ReleaseFocus()
    end
end

function AstralHub:_updateEmptyState(tab)
    if self.ActiveTab == tab then
        self.EmptyLabel.Text = self._query == "" and "This tab is empty" or "No matching controls"
        self.EmptyLabel.Visible = (tab.Matches or 0) == 0
    end
end

function AstralHub:_filterTab(tab)
    local query = self._query
    local matches = 0
    for _, element in ipairs(tab.Elements) do
        local visible
        if query == "" then
            visible = true
        elseif element.Spacer then
            visible = false
        else
            local key = element._searchKey
            if not key then
                local name = element.SearchLabel and element.SearchLabel.Text or element.Name or ""
                key = buildSearchKey(name, element.Description)
                element._searchKey = key
            end
            visible = string.find(key, query, 1, true) ~= nil
        end
        element.Frame.Visible = visible
        if visible and not element.Spacer then
            matches = matches + 1
        end
    end
    tab.Matches = matches
    tab._filteredQuery = query
    self:_updateEmptyState(tab)
end

function AstralHub:_filter(query)
    if self.Closed then
        return
    end
    query = string.lower(tostring(query or "")):match("^%s*(.-)%s*$")
    if query == self._query then
        return
    end
    self._query = query
    for _, tab in ipairs(self.Tabs) do
        self:_filterTab(tab)
        tab.Content.CanvasPosition = ZERO_VECTOR2
    end
end

function AstralHub:_selectTab(tab)
    if self.Closed or tab.Window ~= self then
        return
    end
    local previous = self.ActiveTab
    if previous == tab then
        self:_updateEmptyState(tab)
        return
    end
    self.ActiveTab = tab
    if previous then
        previous.Content.Visible = false
        previous:_setActive(false)
    end
    tab.Content.Visible = true
    tab:_setActive(true)
    if tab._filteredQuery ~= self._query then
        self:_filterTab(tab)
    else
        self:_updateEmptyState(tab)
    end
end

local function makeControl(tab, data, fallbackName, trailingWidth)
    local hasDescription = data.Description ~= nil and tostring(data.Description) ~= ""
    local row = create("TextButton", {
        Name = fallbackName,
        BackgroundColor3 = COLORS.panelSoft,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, hasDescription and 52 or 38),
        AutomaticSize = hasDescription and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        LayoutOrder = #tab.Elements + 1,
    }, tab.Content)
    corner(row, 6)
    stroke(row, COLORS.line)
    padding(row, 12, 12, 9, 9)

    local label = makeText(row, data.Name or fallbackName, 12, COLORS.white, Enum.Font.GothamMedium)
    if hasDescription then
        label.Size = UDim2.new(1, -trailingWidth, 0, 16)

        local description = makeText(row, data.Description, 11, COLORS.muted)
        description.Position = UDim2.fromOffset(0, 19)
        description.Size = UDim2.new(1, -trailingWidth, 0, 15)
        description.AutomaticSize = Enum.AutomaticSize.Y
        description.TextWrapped = true
        description.TextTruncate = Enum.TextTruncate.None
    else
        row.AutomaticSize = Enum.AutomaticSize.Y
        label.Size = UDim2.new(1, -trailingWidth, 0, 20)
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.TextWrapped = true
        label.TextTruncate = Enum.TextTruncate.None
    end

    bindHover(tab.Window, row, COLORS.panelSoft, COLORS.hover)
    return row
end

function AstralHub:AddTab(options)
    if self.Closed then
        return
    end
    options = options or {}
    local tab = {
        Window = self,
        Name = options.Name or options.Title or "Misc",
        Icon = options.Icon or "⚙️",
        Elements = {},
        Matches = 0,
        _filteredQuery = self._query,
    }
    table.insert(self.Tabs, tab)

    local button = makeButton(
        self.TabRail,
        tostring(tab.Icon) .. "  " .. tostring(tab.Name),
        UDim2.new(1, 0, 0, 34),
        ZERO_UDIM2,
        COLORS.sidebar
    )
    button.Name = tostring(tab.Name) .. "Tab"
    button.TextSize = 12
    button.TextXAlignment = Enum.TextXAlignment.Left
    button.TextTruncate = Enum.TextTruncate.AtEnd
    button.LayoutOrder = #self.Tabs
    padding(button, 12, 8, 0, 0)

    local indicator = create("Frame", {
        Name = "Indicator",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, -8, 0.5, 0),
        Size = UDim2.fromOffset(3, 16),
        BackgroundColor3 = COLORS.primary,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Visible = false,
    }, button)
    corner(indicator, 2)
    tab.TabButton = button

    local content = create("ScrollingFrame", {
        Name = tostring(tab.Name) .. "Content",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = ZERO_UDIM2,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = COLORS.lineBright,
        ScrollBarImageTransparency = 0,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ClipsDescendants = true,
        Visible = false,
    }, self.Content)
    padding(content, 1, 6, 1, 4)
    create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, content)
    tab.Content = content

    function tab:_setActive(active)
        cancelTween(self.Window, button)
        button.BackgroundColor3 = active and COLORS.panelRaised or COLORS.sidebar
        button.TextColor3 = active and COLORS.white or COLORS.muted
        indicator.Visible = active
    end

    function tab:_addElement(frame, data)
        data = data or {}
        data.Frame = frame
        frame.LayoutOrder = #self.Elements + 1
        if not data.Spacer then
            local name = data.SearchLabel and data.SearchLabel.Text or data.Name or ""
            data._searchKey = buildSearchKey(name, data.Description)
        end
        table.insert(self.Elements, data)

        local query = self.Window._query
        local visible = query == "" or (not data.Spacer and string.find(data._searchKey, query, 1, true) ~= nil)
        frame.Visible = visible
        if visible and not data.Spacer then
            self.Matches = (self.Matches or 0) + 1
        end
        self.Window:_updateEmptyState(self)
        return data
    end

    function tab:AddLabel(text)
        if self.Window.Closed then
            return
        end
        local label = makeText(content, text, 12, COLORS.muted)
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 0, 22)
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.TextWrapped = true
        label.TextTruncate = Enum.TextTruncate.None
        local element = self:_addElement(label, { Name = tostring(text or ""), SearchLabel = label })
        connect(self.Window, label:GetPropertyChangedSignal("Text"), function()
            element._searchKey = buildSearchKey(label.Text, nil)
            self.Window:_filterTab(self)
        end)
        return label
    end

    function tab:AddButton(data)
        if self.Window.Closed then
            return
        end
        data = data or {}
        local row = makeControl(self, data, "Button", 22)
        local arrow = makeText(row, "›", 18, COLORS.violet, Enum.Font.GothamMedium)
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.fromScale(1, 0.5)
        arrow.Size = UDim2.fromOffset(14, 20)
        arrow.TextXAlignment = Enum.TextXAlignment.Right
        connect(self.Window, row.Activated, function()
            if not self.Window.Closed then
                invoke(data.Callback)
            end
        end)
        self:_addElement(row, data)
        return row
    end

    function tab:Button(data)
        data = data or {}
        return self:AddButton({
            Name = data.Name or data.Title,
            Description = data.Description or data.Desc,
            Callback = data.Callback,
        })
    end

    function tab:AddToggle(data)
        if self.Window.Closed then
            return
        end
        data = data or {}
        local enabled = data.Default == true
        local row = makeControl(self, data, "Toggle", 48)
        local track = create("Frame", {
            Name = "Track",
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor3 = enabled and COLORS.primary or COLORS.line,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(36, 18),
            Position = UDim2.fromScale(1, 0.5),
        }, row)
        corner(track, 9)
        local knob = create("Frame", {
            Name = "Knob",
            BackgroundColor3 = enabled and COLORS.white or COLORS.muted,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(12, 12),
            Position = UDim2.fromOffset(enabled and 21 or 3, 3),
        }, track)
        corner(knob, 6)
        local function setEnabled(value)
            if self.Window.Closed then
                return
            end
            enabled = value == true
            tween(self.Window, track, { BackgroundColor3 = enabled and COLORS.primary or COLORS.line })
            tween(self.Window, knob, {
                Position = UDim2.fromOffset(enabled and 21 or 3, 3),
                BackgroundColor3 = enabled and COLORS.white or COLORS.muted,
            })
            invoke(data.Callback, enabled)
        end
        connect(self.Window, row.Activated, function()
            setEnabled(not enabled)
        end)
        local element = self:_addElement(row, data)
        element.Set = function(_, value)
            setEnabled(value)
        end
        element.Get = function()
            return enabled
        end
        return element
    end

    function tab:Toggle(data)
        data = data or {}
        return self:AddToggle({
            Name = data.Name or data.Title,
            Description = data.Description or data.Desc,
            Default = data.Default == true or data.Value == true,
            Callback = data.Callback,
        })
    end

    function tab:AddParagraph(data)
        if self.Window.Closed then
            return
        end
        if type(data) == "string" then
            data = { Title = "Paragraph", Content = data }
        else
            data = data or {}
        end
        local titleText = tostring(data.Title or data.Name or "Paragraph")
        local contentText = tostring(data.Content or data.Description or data.Desc or data.Text or "")

        local card = create("Frame", {
            Name = "Paragraph",
            BackgroundColor3 = COLORS.panelSoft,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 44),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = #self.Elements + 1,
        }, content)
        corner(card, 6)
        stroke(card, COLORS.line)
        padding(card, 12, 12, 10, 10)
        create("UIListLayout", {
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, card)

        local titleLabel = makeText(card, titleText, 12, COLORS.white, Enum.Font.GothamBold)
        titleLabel.Name = "Title"
        titleLabel.Size = UDim2.new(1, 0, 0, 16)
        titleLabel.AutomaticSize = Enum.AutomaticSize.Y
        titleLabel.TextWrapped = true
        titleLabel.TextTruncate = Enum.TextTruncate.None
        titleLabel.LayoutOrder = 1

        local contentLabel = makeText(card, contentText, 11, COLORS.muted, Enum.Font.Gotham)
        contentLabel.Name = "Content"
        contentLabel.Size = UDim2.new(1, 0, 0, 15)
        contentLabel.AutomaticSize = Enum.AutomaticSize.Y
        contentLabel.TextWrapped = true
        contentLabel.TextTruncate = Enum.TextTruncate.None
        contentLabel.Visible = contentText ~= ""
        contentLabel.LayoutOrder = 2

        local element = self:_addElement(card, {
            Name = titleText,
            Description = contentText,
            TitleLabel = titleLabel,
            ContentLabel = contentLabel,
        })

        local function updateSearch()
            element.Name = titleLabel.Text
            element.Description = contentLabel.Text
            element._searchKey = buildSearchKey(titleLabel.Text, contentLabel.Text)
            self.Window:_filterTab(self)
        end

        function element:SetTitle(newTitle)
            if tab.Window.Closed then
                return
            end
            titleLabel.Text = tostring(newTitle or "")
            updateSearch()
        end

        function element:SetContent(newContent)
            if tab.Window.Closed then
                return
            end
            local text = tostring(newContent or "")
            contentLabel.Text = text
            contentLabel.Visible = text ~= ""
            updateSearch()
        end

        function element:Set(newData)
            if tab.Window.Closed then
                return
            end
            if type(newData) == "table" then
                if newData.Title ~= nil or newData.Name ~= nil then
                    titleLabel.Text = tostring(newData.Title or newData.Name or "")
                end
                if newData.Content ~= nil or newData.Description ~= nil or newData.Desc ~= nil or newData.Text ~= nil then
                    local text = tostring(newData.Content or newData.Description or newData.Desc or newData.Text or "")
                    contentLabel.Text = text
                    contentLabel.Visible = text ~= ""
                end
            else
                local text = tostring(newData or "")
                contentLabel.Text = text
                contentLabel.Visible = text ~= ""
            end
            updateSearch()
        end

        function element:Get()
            return {
                Title = titleLabel.Text,
                Content = contentLabel.Text,
            }
        end

        return element
    end

    function tab:Paragraph(data)
        return self:AddParagraph(data)
    end

    function tab:AddInput(data)
        if self.Window.Closed then
            return
        end
        data = data or {}
        local isNumeric = data.Numeric == true or data.NumbersOnly == true
        local finishedOnly = data.Finished ~= false and data.Realtime ~= true
        local rawDefault = data.Default
        if rawDefault == nil then
            rawDefault = data.Value
        end
        if rawDefault == nil then
            rawDefault = data.Text
        end
        local currentText = tostring(rawDefault ~= nil and rawDefault or "")
        if isNumeric and currentText ~= "" then
            currentText = sanitizeNumeric(currentText)
        end

        local controlData = {
            Name = data.Name or data.Title or "Input",
            Description = data.Description or data.Desc,
            Callback = data.Callback,
        }
        local row = makeControl(self, controlData, "Input", 148)

        local inputBox = create("TextBox", {
            Name = "InputBox",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(136, 24),
            BackgroundColor3 = COLORS.panel,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            ClearTextOnFocus = data.ClearTextOnFocus == true,
            MultiLine = false,
            PlaceholderText = tostring(data.Placeholder or data.PlaceholderText or "Enter text..."),
            PlaceholderColor3 = COLORS.dim,
            Text = currentText,
            TextColor3 = COLORS.white,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        corner(inputBox, 5)
        local inputStroke = stroke(inputBox, COLORS.line)
        padding(inputBox, 8, 8, 0, 0)

        local updatingText = false
        local function setValue(newValue, skipCallback, enterPressed)
            if self.Window.Closed then
                return
            end
            local formatted = tostring(newValue ~= nil and newValue or "")
            if isNumeric and formatted ~= "" then
                formatted = sanitizeNumeric(formatted)
            end
            currentText = formatted
            if inputBox.Text ~= formatted then
                updatingText = true
                inputBox.Text = formatted
                updatingText = false
            end
            if not skipCallback then
                invoke(data.Callback, currentText, enterPressed == true)
            end
        end

        connect(self.Window, row.Activated, function()
            if not self.Window.Closed then
                inputBox:CaptureFocus()
            end
        end)
        connect(self.Window, inputBox.Focused, function()
            inputStroke.Color = COLORS.primary
        end)
        connect(self.Window, inputBox:GetPropertyChangedSignal("Text"), function()
            if updatingText or self.Window.Closed then
                return
            end
            local raw = inputBox.Text
            if isNumeric then
                local clean = sanitizeNumeric(raw)
                if clean ~= raw then
                    updatingText = true
                    inputBox.Text = clean
                    updatingText = false
                    raw = clean
                end
            end
            currentText = raw
            if not finishedOnly then
                invoke(data.Callback, currentText, false)
            end
        end)
        connect(self.Window, inputBox.FocusLost, function(enterPressed)
            inputStroke.Color = COLORS.line
            if self.Window.Closed then
                return
            end
            currentText = inputBox.Text
            invoke(data.Callback, currentText, enterPressed)
        end)

        local element = self:_addElement(row, controlData)
        element.Input = inputBox
        element.TextBox = inputBox
        element.Set = function(_, value, skipCallback)
            setValue(value, skipCallback == true, false)
        end
        element.Get = function()
            return currentText
        end
        return element
    end

    function tab:Input(data)
        return self:AddInput(data)
    end

    function tab:AddTextbox(data)
        return self:AddInput(data)
    end

    function tab:Textbox(data)
        return self:AddInput(data)
    end

    function tab:AddSlider(data)
        if self.Window.Closed then
            return
        end
        data = data or {}
        local minValue = numberOr(data.Min ~= nil and data.Min or data.Minimum, 0)
        local maxValue = numberOr(data.Max ~= nil and data.Max or data.Maximum, 100)
        if maxValue < minValue then
            minValue, maxValue = maxValue, minValue
        end
        local step = math.max(0, numberOr(data.Increment or data.Step or data.Rounding, 1))
        local suffix = tostring(data.Suffix or data.Unit or "")
        local rawDefault = data.Default ~= nil and data.Default or data.Value
        local currentValue = snapSliderValue(numberOr(rawDefault, minValue), minValue, maxValue, step)

        local titleText = tostring(data.Name or data.Title or "Slider")
        local descText = data.Description or data.Desc
        local hasDescription = descText ~= nil and tostring(descText) ~= ""

        local row = create("Frame", {
            Name = "Slider",
            BackgroundColor3 = COLORS.panelSoft,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, hasDescription and 70 or 54),
            LayoutOrder = #self.Elements + 1,
        }, content)
        corner(row, 6)
        stroke(row, COLORS.line)
        padding(row, 12, 12, 9, 10)
        bindHover(self.Window, row, COLORS.panelSoft, COLORS.hover)

        local label = makeText(row, titleText, 12, COLORS.white, Enum.Font.GothamMedium)
        label.Name = "Title"
        label.Size = UDim2.new(1, -76, 0, 16)

        local valueLabel = makeText(row, tostring(currentValue) .. suffix, 11, COLORS.violet, Enum.Font.GothamBold)
        valueLabel.Name = "Value"
        valueLabel.AnchorPoint = Vector2.new(1, 0)
        valueLabel.Position = UDim2.fromScale(1, 0)
        valueLabel.Size = UDim2.fromOffset(72, 16)
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right

        if hasDescription then
            local description = makeText(row, descText, 11, COLORS.muted)
            description.Name = "Description"
            description.Position = UDim2.fromOffset(0, 18)
            description.Size = UDim2.new(1, 0, 0, 14)
        end

        local trackButton = create("TextButton", {
            Name = "SliderTrack",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Position = UDim2.fromOffset(0, hasDescription and 36 or 20),
            Size = UDim2.new(1, 0, 0, 16),
        }, row)

        local track = create("Frame", {
            Name = "Track",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.new(1, 0, 0, 6),
            BackgroundColor3 = COLORS.panel,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
        }, trackButton)
        corner(track, 3)
        stroke(track, COLORS.line)

        local initialAlpha = maxValue > minValue and math.clamp((currentValue - minValue) / (maxValue - minValue), 0, 1) or 0
        local fill = create("Frame", {
            Name = "Fill",
            Size = UDim2.fromScale(initialAlpha, 1),
            BackgroundColor3 = COLORS.primary,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
        }, track)
        corner(fill, 3)

        local knob = create("Frame", {
            Name = "Knob",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(initialAlpha, 0.5),
            Size = UDim2.fromOffset(12, 12),
            BackgroundColor3 = COLORS.white,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
        }, track)
        corner(knob, 6)
        stroke(knob, COLORS.primary)

        local function applyValue(newValue, skipCallback)
            if self.Window.Closed then
                return
            end
            local snapped = snapSliderValue(numberOr(newValue, currentValue), minValue, maxValue, step)
            local alpha = maxValue > minValue and math.clamp((snapped - minValue) / (maxValue - minValue), 0, 1) or 0
            local changed = snapped ~= currentValue
            currentValue = snapped
            fill.Size = UDim2.fromScale(alpha, 1)
            knob.Position = UDim2.fromScale(alpha, 0.5)
            valueLabel.Text = tostring(currentValue) .. suffix
            if changed and not skipCallback then
                invoke(data.Callback, currentValue)
            end
        end

        local function updateFromX(pointerX)
            local trackPos = track.AbsolutePosition.X
            local trackWidth = track.AbsoluteSize.X
            if trackWidth <= 0 then
                return
            end
            local alpha = math.clamp((pointerX - trackPos) / trackWidth, 0, 1)
            local raw = minValue + (maxValue - minValue) * alpha
            applyValue(raw, false)
        end

        local sliderState = {
            Input = nil,
            Update = updateFromX,
        }

        connect(self.Window, trackButton.InputBegan, function(input)
            local inputType = input.UserInputType
            if self.Window.Closed or not self.Window.Visible or self.Window.DialogShade.Visible
                or self.Window._activeDrag or self.Window._activeSlider
                or (inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch) then
                return
            end
            sliderState.Input = input
            self.Window._activeSlider = sliderState
            updateFromX(input.Position.X)
        end)

        local element = self:_addElement(row, {
            Name = titleText,
            Description = descText,
            Callback = data.Callback,
        })
        element.Set = function(_, value, skipCallback)
            if self.Window.Closed then
                return
            end
            local previous = currentValue
            applyValue(value, true)
            if not skipCallback and currentValue ~= previous then
                invoke(data.Callback, currentValue)
            elseif not skipCallback then
                invoke(data.Callback, currentValue)
            end
        end
        element.Get = function()
            return currentValue
        end
        element.SetMin = function(_, newMin)
            minValue = numberOr(newMin, minValue)
            if maxValue < minValue then
                maxValue = minValue
            end
            applyValue(currentValue, true)
        end
        element.SetMax = function(_, newMax)
            maxValue = numberOr(newMax, maxValue)
            if minValue > maxValue then
                minValue = maxValue
            end
            applyValue(currentValue, true)
        end
        return element
    end

    function tab:Slider(data)
        return self:AddSlider(data)
    end

    function tab:AddDropdown(data)
        if self.Window.Closed then
            return
        end
        data = data or {}
        local isMulti = data.Multi == true or data.MultiSelect == true or data.AllowMulti == true
        local allowNone = data.AllowNone == true or isMulti
        local titleText = tostring(data.Name or data.Title or "Dropdown")
        local descText = data.Description or data.Desc
        local hasDescription = descText ~= nil and tostring(descText) ~= ""
        local headerHeight = hasDescription and 34 or 20
        local closedHeight = headerHeight + 18

        local optionsList = {}
        local selectedMap = {}
        local selectedSingle = nil
        local isOpen = false
        local optionPool = {}

        local card = create("Frame", {
            Name = "Dropdown",
            BackgroundColor3 = COLORS.panelSoft,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, closedHeight),
            ClipsDescendants = true,
            LayoutOrder = #self.Elements + 1,
        }, content)
        corner(card, 6)
        local cardStroke = stroke(card, COLORS.line)
        padding(card, 12, 12, 9, 9)

        local header = create("TextButton", {
            Name = "Header",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, headerHeight),
        }, card)

        local label = makeText(header, titleText, 12, COLORS.white, Enum.Font.GothamMedium)
        label.Name = "Title"
        label.Size = UDim2.new(1, -148, 0, hasDescription and 16 or 20)

        if hasDescription then
            local description = makeText(header, descText, 11, COLORS.muted)
            description.Name = "Description"
            description.Position = UDim2.fromOffset(0, 18)
            description.Size = UDim2.new(1, -148, 0, 14)
        end

        local selector = create("Frame", {
            Name = "Selector",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(136, 24),
            BackgroundColor3 = COLORS.panel,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
        }, header)
        corner(selector, 5)
        local selectorStroke = stroke(selector, COLORS.line)

        local selectedLabel = makeText(selector, "None", 11, COLORS.dim, Enum.Font.GothamMedium)
        selectedLabel.Name = "Value"
        selectedLabel.Position = UDim2.fromOffset(8, 0)
        selectedLabel.Size = UDim2.new(1, -24, 1, 0)

        local arrow = makeText(selector, "▾", 11, COLORS.muted, Enum.Font.GothamBold)
        arrow.Name = "Arrow"
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.new(1, -6, 0.5, 0)
        arrow.Size = UDim2.fromOffset(12, 16)
        arrow.TextXAlignment = Enum.TextXAlignment.Center

        local listFrame = create("ScrollingFrame", {
            Name = "OptionList",
            Position = UDim2.fromOffset(0, headerHeight + 8),
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = COLORS.panel,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            CanvasSize = ZERO_UDIM2,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = COLORS.lineBright,
            ScrollBarImageTransparency = 0,
            ClipsDescendants = true,
            Visible = false,
        }, card)
        corner(listFrame, 5)
        stroke(listFrame, COLORS.line)
        padding(listFrame, 4, 4, 4, 4)
        create("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, listFrame)

        local function getMultiResult()
            local result = {}
            for _, opt in ipairs(optionsList) do
                if selectedMap[opt] then
                    table.insert(result, opt)
                end
            end
            return result
        end

        local function updateOptionVisuals()
            for index, opt in ipairs(optionsList) do
                local item = optionPool[index]
                if item then
                    local active = isMulti and (selectedMap[opt] == true) or (selectedSingle == opt)
                    item.Active = active
                    item.Button.BackgroundColor3 = active and COLORS.panelRaised or COLORS.panel
                    item.Text.TextColor3 = active and COLORS.white or COLORS.muted
                    item.Check.Visible = active
                end
            end

            if isMulti then
                local chosen = getMultiResult()
                if #chosen > 0 then
                    selectedLabel.Text = table.concat(chosen, ", ")
                    selectedLabel.TextColor3 = COLORS.violet
                else
                    selectedLabel.Text = "None"
                    selectedLabel.TextColor3 = COLORS.dim
                end
            else
                if selectedSingle ~= nil then
                    selectedLabel.Text = tostring(selectedSingle)
                    selectedLabel.TextColor3 = COLORS.violet
                else
                    selectedLabel.Text = "None"
                    selectedLabel.TextColor3 = COLORS.dim
                end
            end
        end

        local function updateDropdownLayout()
            if isOpen and #optionsList > 0 then
                local visibleCount = math.min(#optionsList, 5)
                local listHeight = visibleCount * 26 + (visibleCount - 1) * 3 + 8
                listFrame.Size = UDim2.new(1, 0, 0, listHeight)
                listFrame.Visible = true
                card.Size = UDim2.new(1, 0, 0, closedHeight + listHeight + 8)
                arrow.Text = "▴"
                selectorStroke.Color = COLORS.primary
                cardStroke.Color = COLORS.lineBright
            else
                listFrame.Visible = false
                card.Size = UDim2.new(1, 0, 0, closedHeight)
                arrow.Text = "▾"
                selectorStroke.Color = COLORS.line
                cardStroke.Color = COLORS.line
            end
        end

        local function setOpen(openState)
            if self.Window.Closed then
                return
            end
            isOpen = openState == true and #optionsList > 0
            updateDropdownLayout()
        end

        local function acquireOptionItem(index)
            local item = optionPool[index]
            if item then
                item.Button.Visible = true
                return item
            end

            local optButton = create("TextButton", {
                Name = "Option" .. index,
                BackgroundColor3 = COLORS.panel,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 26),
                LayoutOrder = index,
            }, listFrame)
            corner(optButton, 4)

            local optText = makeText(optButton, "", 11, COLORS.muted, Enum.Font.GothamMedium)
            optText.Name = "Label"
            optText.Position = UDim2.fromOffset(8, 0)
            optText.Size = UDim2.new(1, -28, 1, 0)

            local optCheck = makeText(optButton, "✓", 11, COLORS.violet, Enum.Font.GothamBold)
            optCheck.Name = "Check"
            optCheck.AnchorPoint = Vector2.new(1, 0.5)
            optCheck.Position = UDim2.new(1, -8, 0.5, 0)
            optCheck.Size = UDim2.fromOffset(12, 16)
            optCheck.TextXAlignment = Enum.TextXAlignment.Right
            optCheck.Visible = false

            item = {
                Button = optButton,
                Text = optText,
                Check = optCheck,
                Value = nil,
                Active = false,
            }
            optionPool[index] = item

            bindHover(self.Window, optButton, function()
                return item.Active and COLORS.panelRaised or COLORS.panel
            end, COLORS.hover)

            connect(self.Window, optButton.Activated, function()
                if self.Window.Closed or item.Value == nil then
                    return
                end
                local val = item.Value
                if isMulti then
                    if selectedMap[val] then
                        selectedMap[val] = nil
                    else
                        selectedMap[val] = true
                    end
                    updateOptionVisuals()
                    invoke(data.Callback, getMultiResult())
                else
                    if selectedSingle == val and allowNone then
                        selectedSingle = nil
                    else
                        selectedSingle = val
                    end
                    updateOptionVisuals()
                    setOpen(false)
                    invoke(data.Callback, selectedSingle)
                end
            end)

            return item
        end

        local function setSelection(newValue, skipCallback)
            if self.Window.Closed then
                return
            end
            if isMulti then
                table.clear(selectedMap)
                if type(newValue) == "table" then
                    for key, val in pairs(newValue) do
                        if type(key) == "number" then
                            local str = tostring(val)
                            if table.find(optionsList, str) then
                                selectedMap[str] = true
                            end
                        elseif val == true then
                            local str = tostring(key)
                            if table.find(optionsList, str) then
                                selectedMap[str] = true
                            end
                        end
                    end
                elseif newValue ~= nil and newValue ~= "" then
                    local str = tostring(newValue)
                    if table.find(optionsList, str) then
                        selectedMap[str] = true
                    end
                end
                updateOptionVisuals()
                if not skipCallback then
                    invoke(data.Callback, getMultiResult())
                end
            else
                local resolved = nil
                if newValue ~= nil and newValue ~= "" then
                    local str = tostring(newValue)
                    if table.find(optionsList, str) then
                        resolved = str
                    end
                end
                if resolved == nil and not allowNone and #optionsList > 0 then
                    resolved = optionsList[1]
                end
                selectedSingle = resolved
                updateOptionVisuals()
                if not skipCallback then
                    invoke(data.Callback, selectedSingle)
                end
            end
        end

        local function rebuildOptions(rawOptions, newDefault, skipCallback)
            table.clear(optionsList)
            if type(rawOptions) == "table" then
                for _, opt in ipairs(rawOptions) do
                    if opt ~= nil then
                        table.insert(optionsList, tostring(opt))
                    end
                end
            end

            for index, opt in ipairs(optionsList) do
                local item = acquireOptionItem(index)
                item.Value = opt
                item.Text.Text = opt
            end
            for index = #optionsList + 1, #optionPool do
                optionPool[index].Button.Visible = false
                optionPool[index].Value = nil
            end

            if newDefault ~= nil then
                setSelection(newDefault, skipCallback)
            elseif isMulti then
                for key in pairs(selectedMap) do
                    if not table.find(optionsList, key) then
                        selectedMap[key] = nil
                    end
                end
                updateOptionVisuals()
            else
                if selectedSingle == nil or not table.find(optionsList, selectedSingle) then
                    selectedSingle = (not allowNone and #optionsList > 0) and optionsList[1] or nil
                end
                updateOptionVisuals()
            end

            if isOpen and #optionsList == 0 then
                isOpen = false
            end
            updateDropdownLayout()
        end

        connect(self.Window, header.Activated, function()
            setOpen(not isOpen)
        end)
        connect(self.Window, header.MouseEnter, function()
            if not self.Window.Closed then
                card.BackgroundColor3 = COLORS.hover
            end
        end)
        connect(self.Window, header.MouseLeave, function()
            if not self.Window.Closed then
                card.BackgroundColor3 = COLORS.panelSoft
            end
        end)

        local initialOptions = data.Options or data.Values or data.List or data.Items or {}
        local initialDefault = data.Default ~= nil and data.Default or data.Value
        rebuildOptions(initialOptions, initialDefault, true)

        local element = self:_addElement(card, {
            Name = titleText,
            Description = descText,
            Callback = data.Callback,
        })
        element.Set = function(_, value, skipCallback)
            setSelection(value, skipCallback == true)
        end
        element.Get = function()
            if isMulti then
                return getMultiResult()
            end
            return selectedSingle
        end
        element.Refresh = function(_, newOptions, newDefault, skipCallback)
            if self.Window.Closed then
                return
            end
            rebuildOptions(newOptions, newDefault, skipCallback ~= false)
        end
        element.SetOptions = element.Refresh
        element.Open = function()
            setOpen(true)
        end
        element.Close = function()
            setOpen(false)
        end
        return element
    end

    function tab:Dropdown(data)
        return self:AddDropdown(data)
    end

    function tab:Section(text)
        local label = self:AddLabel(text or "Section")
        if label then
            label.Font = Enum.Font.GothamBold
            label.TextSize = 11
            label.TextColor3 = COLORS.violet
        end
        return label
    end

    function tab:Space(height)
        if self.Window.Closed then
            return
        end
        local spacer = create("Frame", {
            Name = "Space",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, math.max(0, numberOr(height, 8))),
        }, content)
        self:_addElement(spacer, { Spacer = true })
        return spacer
    end

    connect(self, button.Activated, function()
        self:_selectTab(tab)
    end)
    bindHover(self, button, function()
        return self.ActiveTab == tab and COLORS.panelRaised or COLORS.sidebar
    end, COLORS.hover)
    tab:_setActive(false)
    if not self.ActiveTab then
        self:_selectTab(tab)
    end
    return tab
end

function AstralHub:Tab(options)
    return self:AddTab(options)
end

function AstralHub:_removeNotification(record, destroyInstance)
    if not record.Removed then
        record.Removed = true
        if record.Timer then
            task.cancel(record.Timer)
            record.Timer = nil
        end
        local index = table.find(self._notifications, record)
        if index then
            table.remove(self._notifications, index)
        end
    end
    if destroyInstance or self.Closed then
        local poolIndex = table.find(self._toastPool, record)
        if poolIndex then
            table.remove(self._toastPool, poolIndex)
        end
        disconnectAll(record)
        if record.Frame and record.Frame.Parent then
            record.Frame:Destroy()
        end
    elseif record.Frame and record.Frame.Parent == self.NotificationStack then
        record.Frame.Visible = false
        if not table.find(self._toastPool, record) then
            table.insert(self._toastPool, record)
        end
    end
end

function AstralHub:_acquireToast()
    local record = table.remove(self._toastPool)
    if record and record.Frame and record.Frame.Parent then
        record.Removed = false
        record.Frame.Visible = true
        return record
    end

    local toast = create("Frame", {
        BackgroundColor3 = COLORS.panelRaised,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 44),
    }, self.NotificationStack)
    corner(toast, 6)
    stroke(toast, COLORS.lineBright)

    local accent = create("Frame", {
        Name = "Accent",
        BackgroundColor3 = COLORS.primary,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 6),
        Size = UDim2.new(0, 3, 1, -12),
    }, toast)
    corner(accent, 2)

    local title = makeText(toast, "", 12, COLORS.white, Enum.Font.GothamBold)
    title.Name = "Title"
    title.Position = UDim2.fromOffset(12, 11)
    title.Size = UDim2.new(1, -24, 0, 18)

    local content = makeText(toast, "", 11, COLORS.muted)
    content.Name = "Content"
    content.Position = UDim2.fromOffset(12, 32)
    content.Size = UDim2.new(1, -24, 0, 34)
    content.TextWrapped = true
    content.TextYAlignment = Enum.TextYAlignment.Top
    content.Visible = false

    record = {
        Frame = toast,
        TitleLabel = title,
        ContentLabel = content,
        _connections = {},
    }
    connect(record, toast.Destroying, function()
        local poolIndex = table.find(self._toastPool, record)
        if poolIndex then
            table.remove(self._toastPool, poolIndex)
        end
        self:_removeNotification(record, true)
    end)
    return record
end

function AstralHub:Notify(data)
    if self.Closed or not self.Overlay then
        return
    end
    data = data or {}
    if not self.NotificationStack then
        local stack = create("ScrollingFrame", {
            Name = "Notifications",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -12, 1, -12),
            Size = UDim2.fromOffset(300, 240),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = ZERO_UDIM2,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = COLORS.lineBright,
            ScrollBarImageTransparency = 0,
            ClipsDescendants = true,
            ZIndex = 20,
        }, self.Overlay)
        padding(stack, 1, 5, 1, 1)
        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }, stack)
        self.NotificationStack = stack
        connect(self, stack:GetPropertyChangedSignal("AbsoluteCanvasSize"), function()
            stack.CanvasPosition = Vector2.new(0,
                math.max(0, stack.AbsoluteCanvasSize.Y - stack.AbsoluteWindowSize.Y))
        end)
        self:_updateLayout()
    end

    -- Bound both visible clutter and the number of pending expiration tasks.
    while #self._notifications >= MAX_NOTIFICATIONS do
        self:_removeNotification(self._notifications[1], false)
    end

    self.NotificationIndex = (self.NotificationIndex or 0) + 1
    local record = self:_acquireToast()
    local toast = record.Frame
    local hasContent = data.Content ~= nil and tostring(data.Content) ~= ""

    toast.Name = "Notification" .. self.NotificationIndex
    toast.LayoutOrder = self.NotificationIndex
    toast.Size = UDim2.new(1, 0, 0, hasContent and 76 or 40)
    record.TitleLabel.Text = tostring(data.Title or self.Title)

    if hasContent then
        record.ContentLabel.Text = tostring(data.Content)
        record.ContentLabel.Visible = true
    else
        record.ContentLabel.Text = ""
        record.ContentLabel.Visible = false
    end

    table.insert(self._notifications, record)
    record.Timer = task.delay(math.max(0, numberOr(data.Duration, 4)), function()
        record.Timer = nil
        self:_removeNotification(record, false)
    end)
    return toast
end

function AstralHub:Destroy(fromGui)
    if self.Closed then
        return
    end
    self.Closed = true
    self.Visible = false
    self.Minimized = false
    self:_cancelDrags()
    disconnectAll(self)
    for instance in pairs(self._tweens) do
        cancelTween(self, instance)
    end
    while #self._notifications > 0 do
        self:_removeNotification(self._notifications[1], true)
    end
    for _, record in ipairs(self._toastPool) do
        disconnectAll(record)
    end
    table.clear(self._toastPool)
    if activeWindow == self then
        activeWindow = nil
    end
    if self.Gui and fromGui ~= true then
        self.Gui:Destroy()
    end
end

return AstralHub
