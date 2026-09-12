--// Nr HUB Key Hub for Work.ink
--// Client-side key screen only. Do NOT place your Work.ink account API key in this file.
--// If you have a private server/Worker, set VERIFY_URL to your own endpoint.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    HubName = "Nr HUB",
    GameName = "Key System",
    GetKeyUrl = "https://work.ink/2XEh/key-system", -- Work.ink generated link
    -- Safer option: create the Worker in workink-verify-worker.js and set VERIFY_URL to it.
    VerifyUrl = nil, -- e.g. "https://your-worker.your-subdomain.workers.dev/verify?token="
    UsePublicWorkInkValidation = true, -- fallback: https://work.ink/_api/v2/token/isValid/{TOKEN}
    DeleteTokenOnUse = false,
    MainScriptUrl = "https://raw.githubusercontent.com/NickolasFrutuoso/NickolasFrutuoso/Roblox/edit/main/NrGameLoader.lua", -- runs the game detector/loader after key validation
    AutoSaveToken = true,
    AutoValidateSavedToken = true,
}

local function getExecutorRequest()
    local env = getgenv and getgenv() or _G
    local synTable = rawget(env, "syn")
    local httpTable = rawget(env, "http")
    return (synTable and synTable.request) or http_request or request or (httpTable and httpTable.request)
end

local function getParentGui()
    local ok, hidden = pcall(function()
        if gethui then return gethui() end
        return nil
    end)
    if ok and hidden then return hidden end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function safeRead(path)
    if not isfile then return nil end
    local ok, value = pcall(readfile, path)
    if ok then return value end
    return nil
end

local function safeWrite(path, value)
    if not (writefile and makefolder) then return end
    pcall(function()
        makefolder("NrHub")
        writefile(path, value)
    end)
end

local function requestJson(url)
    local req = getExecutorRequest()
    if req then
        local response = req({ Url = url, Method = "GET", Headers = { ["Accept"] = "application/json" } })
        local body
        local status = 200
        if type(response) == "table" then
            body = response.Body or response.body or ""
            status = response.StatusCode or response.Status or status
        else
            body = tostring(response or "")
        end
        if status >= 400 then
            return false, "HTTP " .. tostring(status)
        end
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if ok then return true, data end
        return false, "Invalid JSON response"
    end

    local ok, body = pcall(function()
        return game:HttpGet(url, true)
    end)
    if not ok then return false, tostring(body) end
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(body) end)
    if decodedOk then return true, data end
    return false, "Invalid JSON response"
end

local function verifyToken(token)
    token = tostring(token or ""):gsub("%s+", "")
    if #token < 8 then
        return false, "Enter a valid key."
    end

    local encoded = HttpService:UrlEncode(token)
    local url
    if CONFIG.VerifyUrl and #CONFIG.VerifyUrl > 0 then
        url = CONFIG.VerifyUrl .. encoded
    elseif CONFIG.UsePublicWorkInkValidation then
        url = "https://work.ink/_api/v2/token/isValid/" .. encoded
    else
        return false, "No verify endpoint configured."
    end
    if CONFIG.DeleteTokenOnUse then
        url ..= (url:find("?", 1, true) and "&" or "?") .. "deleteToken=1"
    end

    local ok, dataOrErr = requestJson(url)
    if not ok then return false, dataOrErr end
    if type(dataOrErr) == "table" and dataOrErr.valid == true then
        return true, dataOrErr
    end
    return false, "Invalid or expired key."
end

local old = getParentGui():FindFirstChild("NrHubKeyGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "NrHubKeyGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = getParentGui()

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.16
overlay.Size = UDim2.fromScale(1, 1)
overlay.Parent = gui

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function stroke(parent, transparency, color)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(255,255,255)
    s.Transparency = transparency or 0.85
    s.Parent = parent
    return s
end

local loader = Instance.new("Frame")
loader.Name = "LoadingCard"
loader.AnchorPoint = Vector2.new(0.5, 0.5)
loader.Position = UDim2.fromScale(0.5, 0.5)
loader.Size = UDim2.fromOffset(360, 190)
loader.BackgroundColor3 = Color3.fromRGB(12, 13, 13)
loader.BackgroundTransparency = 0.03
loader.Parent = overlay
corner(loader, 16)
stroke(loader, 0.86)

local loaderPad = Instance.new("UIPadding")
loaderPad.PaddingTop = UDim.new(0, 22)
loaderPad.PaddingBottom = UDim.new(0, 22)
loaderPad.PaddingLeft = UDim.new(0, 24)
loaderPad.PaddingRight = UDim.new(0, 24)
loaderPad.Parent = loader

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = CONFIG.HubName
title.TextColor3 = Color3.fromRGB(245,245,245)
title.TextSize = 30
title.Size = UDim2.new(1, 0, 0, 36)
title.Parent = loader

local gameName = Instance.new("TextLabel")
gameName.BackgroundTransparency = 1
gameName.Font = Enum.Font.GothamMedium
gameName.Text = CONFIG.GameName
gameName.TextColor3 = Color3.fromRGB(160,160,160)
gameName.TextSize = 14
gameName.Position = UDim2.fromOffset(0, 40)
gameName.Size = UDim2.new(1, 0, 0, 22)
gameName.Parent = loader

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
title.TextXAlignment = Enum.TextXAlignment.Center
gameName.TextXAlignment = Enum.TextXAlignment.Center
status.TextXAlignment = Enum.TextXAlignment.Center
status.Text = "Loading scripts..."
status.TextColor3 = Color3.fromRGB(190,190,190)
status.TextSize = 13
status.Position = UDim2.fromOffset(0, 88)
status.Size = UDim2.new(1, 0, 0, 20)
status.Parent = loader

local barBg = Instance.new("Frame")
barBg.BackgroundColor3 = Color3.fromRGB(28,28,28)
barBg.Position = UDim2.fromOffset(0, 122)
barBg.Size = UDim2.new(1, 0, 0, 10)
barBg.Parent = loader
corner(barBg, 10)

local bar = Instance.new("Frame")
bar.BackgroundColor3 = Color3.fromRGB(235,235,235)
bar.Size = UDim2.fromScale(0, 1)
bar.Parent = barBg
corner(bar, 10)

local card = Instance.new("Frame")
card.Name = "KeyCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(330, 390)
card.BackgroundColor3 = Color3.fromRGB(12, 13, 13)
card.BackgroundTransparency = 0.04
card.Visible = false
card.Parent = overlay
corner(card, 16)
stroke(card, 0.84)

local cardPad = Instance.new("UIPadding")
cardPad.PaddingTop = UDim.new(0, 22)
cardPad.PaddingBottom = UDim.new(0, 20)
cardPad.PaddingLeft = UDim.new(0, 24)
cardPad.PaddingRight = UDim.new(0, 24)
cardPad.Parent = card

local cardTitle = Instance.new("TextLabel")
cardTitle.BackgroundTransparency = 1
cardTitle.Font = Enum.Font.GothamBold
cardTitle.Text = CONFIG.HubName
cardTitle.TextColor3 = Color3.fromRGB(245,245,245)
cardTitle.TextSize = 22
cardTitle.Size = UDim2.new(1, 0, 0, 26)
cardTitle.Parent = card

local cardSub = Instance.new("TextLabel")
cardSub.BackgroundTransparency = 1
cardSub.Font = Enum.Font.GothamMedium
cardSub.Text = CONFIG.GameName
cardSub.TextColor3 = Color3.fromRGB(150,150,150)
cardSub.TextSize = 13
cardSub.Position = UDim2.fromOffset(0, 28)
cardSub.Size = UDim2.new(1, 0, 0, 20)
cardSub.Parent = card

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 8, 0, -8)
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
closeButton.BackgroundTransparency = 0.08
closeButton.BorderSizePixel = 0
closeButton.AutoButtonColor = false
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(220, 220, 220)
closeButton.TextSize = 13
closeButton.Parent = card
corner(closeButton, 8)
stroke(closeButton, 0.86)
closeButton.MouseEnter:Connect(function()
    TweenService:Create(closeButton, TweenInfo.new(0.12), {
        BackgroundColor3 = Color3.fromRGB(36, 20, 20),
        TextColor3 = Color3.fromRGB(255, 170, 170)
    }):Play()
end)
closeButton.MouseLeave:Connect(function()
    TweenService:Create(closeButton, TweenInfo.new(0.12), {
        BackgroundColor3 = Color3.fromRGB(20, 20, 20),
        TextColor3 = Color3.fromRGB(220, 220, 220)
    }):Play()
end)
closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local avatarRing = Instance.new("Frame")
avatarRing.AnchorPoint = Vector2.new(0.5, 0)
avatarRing.Position = UDim2.new(0.5, 0, 0, 70)
avatarRing.Size = UDim2.fromOffset(94, 94)
avatarRing.BackgroundColor3 = Color3.fromRGB(22,22,22)
avatarRing.Parent = card
corner(avatarRing, 100)
stroke(avatarRing, 0.78)

local avatar = Instance.new("ImageLabel")
avatar.BackgroundTransparency = 1
avatar.AnchorPoint = Vector2.new(0.5, 0.5)
avatar.Position = UDim2.fromScale(0.5, 0.5)
avatar.Size = UDim2.fromOffset(82, 82)
avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150"
avatar.Parent = avatarRing
corner(avatar, 100)

local user = Instance.new("TextLabel")
user.BackgroundTransparency = 1
user.Font = Enum.Font.GothamMedium
user.Text = LocalPlayer.DisplayName .. "  @" .. LocalPlayer.Name
user.TextColor3 = Color3.fromRGB(210,210,210)
user.TextSize = 13
user.Position = UDim2.fromOffset(0, 174)
user.Size = UDim2.new(1, 0, 0, 18)
user.Parent = card

local input = Instance.new("TextBox")
input.Name = "KeyInput"
input.ClearTextOnFocus = false
input.PlaceholderText = "Enter your key..."
input.Text = CONFIG.AutoSaveToken and (safeRead("NrHub/key.txt") or "") or ""
input.Font = Enum.Font.Gotham
input.TextSize = 14
input.TextColor3 = Color3.fromRGB(240,240,240)
input.PlaceholderColor3 = Color3.fromRGB(110,110,110)
input.BackgroundColor3 = Color3.fromRGB(20,20,20)
input.Position = UDim2.fromOffset(0, 212)
input.Size = UDim2.new(1, 0, 0, 44)
input.Parent = card
corner(input, 10)
stroke(input, 0.9)

local message = Instance.new("TextLabel")
message.BackgroundTransparency = 1
message.Font = Enum.Font.Gotham
message.Text = "Paste your Work.ink token to continue."
message.TextColor3 = Color3.fromRGB(145,145,145)
message.TextSize = 12
message.TextWrapped = true
message.Position = UDim2.fromOffset(0, 266)
message.Size = UDim2.new(1, 0, 0, 34)
message.Parent = card

local buttons = Instance.new("Frame")
buttons.BackgroundTransparency = 1
buttons.Position = UDim2.fromOffset(0, 318)
buttons.Size = UDim2.new(1, 0, 0, 42)
buttons.Parent = card

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = buttons

local function button(name, text)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(235,235,235)
    b.AutoButtonColor = false
    b.BackgroundColor3 = Color3.fromRGB(24,24,24)
    b.Size = UDim2.new(0.5, -5, 1, 0)
    b.Parent = buttons
    corner(b, 10)
    stroke(b, 0.86)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(34,34,34)}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(24,24,24)}):Play() end)
    return b
end

local submit = button("SubmitButton", "Submit")
local getKey = button("GetKeyButton", "Get Key")

local function setMessage(text, color)
    message.Text = text
    message.TextColor3 = color or Color3.fromRGB(145,145,145)
end

local accessFinished = false
local function finishAccess(token, autoLoaded)
    if accessFinished then return end
    accessFinished = true
    if CONFIG.AutoSaveToken then safeWrite("NrHub/key.txt", token) end
    setMessage(autoLoaded and "Saved key active. Loading hub..." or "Access granted. Loading hub...", Color3.fromRGB(130, 255, 170))
    task.wait(autoLoaded and 0.15 or 0.35)
    if gui and gui.Parent then gui:Destroy() end
    if type(getgenv().NrHubOnKeyVerified) == "function" then
        task.spawn(getgenv().NrHubOnKeyVerified, token)
    elseif CONFIG.MainScriptUrl and #CONFIG.MainScriptUrl > 0 then
        local ok, code = pcall(function() return game:HttpGet(CONFIG.MainScriptUrl, true) end)
        if ok then
            local chunk = loadstring(code)
            if chunk then chunk() end
        else
            warn("[Nr HUB] Failed to load main script: " .. tostring(code))
        end
    end
end

local function tryAutoValidateSavedToken()
    if not (CONFIG.AutoSaveToken and CONFIG.AutoValidateSavedToken) then return end
    local savedToken = safeRead("NrHub/key.txt")
    savedToken = tostring(savedToken or ""):gsub("%s+", "")
    if #savedToken < 8 then return end

    input.Text = savedToken
    submit.Active = false
    submit.Text = "Checking..."
    setMessage("Checking saved key...", Color3.fromRGB(220,220,220))

    task.spawn(function()
        local ok, dataOrErr = verifyToken(savedToken)
        submit.Active = true
        submit.Text = "Submit"
        if ok then
            finishAccess(savedToken, true)
        elseif not accessFinished then
            setMessage("Saved key expired. Paste a new key.", Color3.fromRGB(255, 190, 120))
        end
    end)
end

task.defer(tryAutoValidateSavedToken)

getKey.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(CONFIG.GetKeyUrl)
        setMessage("Key link copied. Open it in your browser.", Color3.fromRGB(220,220,220))
    else
        setMessage("Get key: " .. CONFIG.GetKeyUrl, Color3.fromRGB(220,220,220))
    end
end)

submit.MouseButton1Click:Connect(function()
    submit.Text = "Checking..."
    submit.Active = false
    setMessage("Verifying key...", Color3.fromRGB(220,220,220))
    local token = input.Text
    task.spawn(function()
        local ok, dataOrErr = verifyToken(token)
        submit.Active = true
        submit.Text = "Submit"
        if ok then
            finishAccess(token)
        else
            setMessage(tostring(dataOrErr), Color3.fromRGB(255, 120, 120))
        end
    end)
end)

local loadingSteps = {
    {"Loading scripts...", 0.22},
    {"Preparing interface...", 0.48},
    {"Checking session...", 0.74},
    {"Ready.", 1},
}

task.spawn(function()
    loader.Size = UDim2.fromOffset(330, 170)
    TweenService:Create(loader, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(360, 190)}):Play()
    for _, step in ipairs(loadingSteps) do
        status.Text = step[1]
        TweenService:Create(bar, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.fromScale(step[2], 1)}):Play()
        task.wait(0.48)
    end
    TweenService:Create(loader, TweenInfo.new(0.22), {BackgroundTransparency = 1}):Play()
    task.wait(0.22)
    loader.Visible = false
    card.Visible = true
    card.Size = UDim2.fromOffset(306, 362)
    TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(330, 390)}):Play()
end)

return gui

