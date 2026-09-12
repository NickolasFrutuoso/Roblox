--// Nr HUB - Game Loader
--// Flow: Key System -> valid key -> detect current game -> load matching script.
--// Add new supported games inside SUPPORTED_GAMES as more scripts are created.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer = Players.LocalPlayer

local LOADER_VERSION = "1.0.0"
local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/NickolasFrutuoso/Roblox/refs/heads/main"

local SUPPORTED_GAMES = {
    -- Anime Dice
    [113290951185459] = {
        Name = "Anime Dice",
        ScriptUrl = GITHUB_RAW_BASE .. "/AnimeDice.lua",
        Enabled = true,
    },

    -- Add future games here:
    -- [PLACE_ID] = {
    --     Name = "Game Name",
    --     ScriptUrl = GITHUB_RAW_BASE .. "/GameScript.lua",
    --     Enabled = true,
    -- },
}

local function getExecutorRequest()
    local env = getgenv and getgenv() or _G
    local synTable = rawget(env, "syn")
    local httpTable = rawget(env, "http")
    return (synTable and synTable.request) or http_request or request or (httpTable and httpTable.request)
end

local function notify(title, text, duration)
    title = tostring(title or "Nr HUB")
    text = tostring(text or "")
    duration = tonumber(duration) or 5
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration,
        })
    end)
    print(('[Nr HUB] %s - %s'):format(title, text))
end

local function httpGet(url)
    local req = getExecutorRequest()
    if req then
        local ok, response = pcall(req, {
            Url = url,
            Method = "GET",
            Headers = { ["Accept"] = "text/plain, */*" },
        })
        if not ok then
            return false, tostring(response)
        end
        if type(response) == "table" then
            local status = tonumber(response.StatusCode or response.Status or response.status_code) or 200
            if status < 200 or status >= 300 then
                return false, "HTTP " .. tostring(status)
            end
            return true, response.Body or response.body or ""
        end
        return true, tostring(response or "")
    end

    local ok, body = pcall(function()
        return game:HttpGet(url, true)
    end)
    if not ok then
        return false, tostring(body)
    end
    return true, body
end

local function getExperienceName()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok and type(info) == "table" and info.Name then
        return tostring(info.Name)
    end
    return "Unknown Experience"
end

local function getCurrentGameConfig()
    return SUPPORTED_GAMES[game.PlaceId]
end

local function runScriptFromUrl(url, gameName)
    notify("Nr HUB", "Loading " .. tostring(gameName or "script") .. "...", 4)

    local ok, sourceOrErr = httpGet(url)
    if not ok then
        notify("Nr HUB", "Failed to download script: " .. tostring(sourceOrErr), 8)
        return false, sourceOrErr
    end

    if type(sourceOrErr) ~= "string" or #sourceOrErr < 20 then
        local err = "Downloaded script is empty or invalid."
        notify("Nr HUB", err, 8)
        return false, err
    end

    local chunk, compileErr = loadstring(sourceOrErr)
    if not chunk then
        local err = "Script compile failed: " .. tostring(compileErr)
        notify("Nr HUB", err, 8)
        return false, err
    end

    local okRun, runErr = pcall(chunk)
    if not okRun then
        local err = "Script runtime failed: " .. tostring(runErr)
        notify("Nr HUB", err, 8)
        return false, err
    end

    notify("Nr HUB", tostring(gameName or "Script") .. " loaded.", 4)
    return true
end

local function loadCurrentGame()
    local config = getCurrentGameConfig()
    local placeId = game.PlaceId
    local universeId = game.GameId
    local experienceName = getExperienceName()

    if not config then
        notify("Nr HUB", ("Unsupported game: %s | PlaceId %s"):format(experienceName, tostring(placeId)), 10)
        warn(("[Nr HUB] Unsupported game. PlaceId=%s UniverseId=%s Name=%s"):format(tostring(placeId), tostring(universeId), experienceName))
        return false, "Unsupported game"
    end

    if config.Enabled == false then
        notify("Nr HUB", tostring(config.Name or experienceName) .. " is currently disabled.", 8)
        return false, "Game disabled"
    end

    if not config.ScriptUrl or config.ScriptUrl == "" then
        notify("Nr HUB", tostring(config.Name or experienceName) .. " has no script URL configured.", 8)
        return false, "Missing ScriptUrl"
    end

    return runScriptFromUrl(config.ScriptUrl, config.Name or experienceName)
end

local API = {
    Version = LOADER_VERSION,
    SupportedGames = SUPPORTED_GAMES,
    LoadCurrentGame = loadCurrentGame,
    GetCurrentGameConfig = getCurrentGameConfig,
}

getgenv().NrHubGameLoader = API

-- If this file is executed directly after a validated key, it loads immediately.
return loadCurrentGame()
