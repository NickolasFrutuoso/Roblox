--// Anime Dice - MacUI
--// Place: 113290951185459

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer

if getgenv().AnimeDiceRuntime and getgenv().AnimeDiceRuntime.Unload then
    getgenv().AnimeDiceRuntime.Unload()
end

local Runtime = {
    connections = {}, running = true, unloaded = false, history = {}, controls = {},
    nativeTowerLoop = false, towerStartPending = false,
    towerStatus = "Ready", sellStatus = "Waiting for full inventory",
    graphicsOriginal = {}, globalShadowsOriginal = nil,
    walkHumanoid = nil, walkSpeedOriginal = nil,
    webhookUrl = "", webhookMessageId = nil, webhookBusy = false, webhookOfflineSent = false,
    webhookLastAttempt = 0, webhookStartedAt = os.time(),
    questClaims = {}, questShopCursor = 0,
    Unload = function() end,
}
getgenv().AnimeDiceRuntime = Runtime

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Runtime.connections, connection)
    return connection
end

local Network = ReplicatedStorage:WaitForChild("Network")
local function child(root, ...)
    for _, name in ipairs({...}) do root = root:WaitForChild(name) end
    return root
end

local Remotes = {
    SetAutoRoll = child(Network, "RollService", "RE", "SetAutoRoll"),
    RollDice = child(Network, "RollService", "RF", "RollDice"),
    InteractSlot = child(Network, "PlotService", "RE", "InteractSlot"),
    LevelUpSlot = child(Network, "PlotService", "RE", "LevelUpSlot"),
    CollectBalance = child(Network, "PlotService", "RE", "CollectBalance"),
    EquipBest = child(Network, "PlotService", "RE", "EquipBest"),
    BuyDice = child(Network, "DiceShopService", "RE", "BuyDice"),
    EquipDice = child(Network, "DiceShopService", "RE", "EquipDice"),
    SellEquipped = child(Network, "SellService", "RF", "SellEquipped"),
    SellInventory = child(Network, "SellService", "RF", "SellInventory"),
    BuyUpgrade = child(Network, "RE", "BuyUpgrade"),
    Rebirth = child(Network, "RebirthService", "RE", "Rebirth"),
    GradeRoll = child(Network, "GradeService", "RE", "Roll"),
    TraitRoll = child(Network, "TraitService", "RE", "Roll"),
    QuestClaim = child(Network, "QuestService", "RE", "Claim"),
    QuestBuy = child(Network, "QuestService", "RE", "Buy"),
    EquipBestTowerTeam = child(Network, "Towers", "RE", "EquipBestTowerTeam"),
}

local Framework = ReplicatedStorage:WaitForChild("Framework")
local DataController = require(child(Framework, "Features", "Data", "DataController"))
local Dice = require(child(Framework, "Features", "Rolling", "Dice"))
local PlotConfig = require(child(Framework, "Features", "Plot", "PlotConfig"))
local Rebirths = require(child(Framework, "Features", "Rebirth", "Rebirths"))
local Upgrades = require(child(Framework, "Features", "Upgrades", "Upgrades"))
local TreeStructure = require(child(Framework, "Features", "Upgrades", "TreeStructure"))
local EntryRegistry = require(child(Framework, "Features", "Inventory", "EntryRegistry"))
local UnitUtil = require(child(Framework, "Features", "Inventory", "Kinds", "Unit", "UnitUtil"))
local SellUtil = require(child(Framework, "Features", "Selling", "SellUtil"))
local BuffController = require(child(Framework, "Features", "Buffs", "BuffController"))
local BoostConfig = require(child(Framework, "Features", "Inventory", "Kinds", "Boost", "BoostConfig"))
local BoostController = require(child(Framework, "Features", "Inventory", "Kinds", "Boost", "BoostController"))
local Towers = require(child(Framework, "Features", "Towers", "Towers"))
local TowerController = require(child(Framework, "Features", "Towers", "TowerController"))
local Grades = require(child(Framework, "Features", "Grades", "Grades"))
local Traits = require(child(Framework, "Features", "Traits", "Traits"))
local QuestConfig = require(child(Framework, "Features", "Quests", "QuestConfig"))
local UIReferences = require(child(Framework, "Features", "UI", "UIReferences"))
local Rarities = require(child(Framework, "Other", "Rarities"))

local CONFIG_FOLDER = "AnimeDiceMacUI"
local CONFIG_FILE = CONFIG_FOLDER .. "/settings.json"
local Defaults = {
    RollDelay = 0.15, HiddenRoll = false, AutoRoll = false,
    AutoPlace = false, AutoUpgrade = false, UpgradeDelay = 1,
    AutoCollect = false, CollectDelay = 2, MinCollect = 1,
    AutoEquipBest = false, EquipBestDelay = 10,
    AutoBuyDice = false, AutoEquipDice = true,
    AutoSell = false, SellMode = "By Rarity",
    SellRarities = {"Common"},
    AutoSkillTree = false, SkillDelay = 1,
    SkillPriority = {"Luck", "Money", "Roll Speed", "Unit Storage", "Sell", "Damage", "Health", "Walkspeed"},
    AutoRebirth = false, RebirthDelay = 2, StopRebirth = 11,
    AutoBoost = false, SelectedBoosts = {},
    AutoGrade = false, GradeSlots = {}, DesiredGrades = {"A", "A+", "S", "S+", "Z", "Z+"}, GradeDelay = 0.3,
    AutoTrait = false, TraitSlots = {}, DesiredTraits = {"Samurai", "Shogun", "Monarch", "Transcendent"}, TraitDelay = 0.25,
    PreserveProtectedRolls = true, AutoClaimQuests = false, AutoQuestShop = false,
    QuestShopItems = {"Trait Reroll", "Gems"}, QuestShopDelay = 1, QuestTicketReserve = 0,
    AutoTower = false, SelectedTower = "Dragon Tower",
    AntiAFK = false, LowGraphics = false, SpeedWalk = false, WalkSpeed = 32,
    InfiniteJump = false, MenuKeybind = "F12", WebhookEnabled = false, WebhookInterval = 30,
}
local G = table.clone(Defaults)

local function loadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(CONFIG_FILE))
    if ok and type(decoded) == "table" then
        for key, value in pairs(decoded) do if G[key] ~= nil then G[key] = value end end
    end
end
local function saveConfig()
    if not (writefile and makefolder) then return false end
    if isfolder and not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
    return pcall(writefile, CONFIG_FILE, HttpService:JSONEncode(G))
end
loadConfig()
-- CreateHUB build removes these generic client/player helper controls; clear persisted old toggles too.
G.AntiAFK = false
G.LowGraphics = false
G.SpeedWalk = false
G.InfiniteJump = false

local function value(state, fallback)
    if state == nil then return fallback end
    local ok, result = pcall(function() return state() end)
    return ok and result or fallback
end
local function money() return tonumber(value(DataController.Money, 0)) or 0 end
local function rebirth() return tonumber(value(DataController.Rebirth, 0)) or 0 end
local function slotData(index)
    local slots = DataController.Slots
    local state = slots and slots[tostring(index)]
    return value(state, nil)
end
local function inventoryUnit(id)
    local inventory = DataController.Inventory
    return inventory and value(inventory[id], nil) or nil
end
local function unlocked(index)
    return PlotConfig.GetSlotRebirthRequirement(index) <= rebirth()
end
local function entryConfig(name)
    local ok, result = pcall(EntryRegistry.getEntryConfig, name)
    return ok and result or nil
end
local function unitSummary(index)
    local slot = slotData(index)
    if not slot or not slot.unitId then
        return {slot = index, unlocked = unlocked(index), empty = true, balance = slot and slot.balance or 0}
    end
    local unit = inventoryUnit(slot.unitId)
    if not unit then return {slot = index, unitId = slot.unitId, missing = true, balance = slot.balance or 0} end
    local attributes = unit.attributes or {}
    local config = entryConfig(unit.name)
    local income = config and config.income and config.income(attributes) or 0
    local levelPrice = config and UnitUtil.GetLevelPrice(unit.name, attributes) or 0
    return {
        slot = index, unitId = slot.unitId, name = unit.name or "Unknown",
        level = attributes.level or 1, grade = attributes.grade or "-",
        trait = attributes.trait or "-", mutation = attributes.mutation or "-",
        income = income, balance = tonumber(slot.balance) or 0, levelPrice = levelPrice,
        raw = unit,
    }
end

local suffixes = {{1e24,"Sp"},{1e21,"Sx"},{1e18,"Qi"},{1e15,"Qa"},{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}
local function formatNumber(number)
    number = tonumber(number) or 0
    for _, item in ipairs(suffixes) do
        if math.abs(number) >= item[1] then return string.format("%.2f%s", number / item[1], item[2]) end
    end
    return tostring(math.floor(number + 0.5))
end

local function getOpenSlots()
    local result = {}
    for i = 1, PlotConfig.GetMaxSlots() do
        local slot = slotData(i)
        if unlocked(i) and (not slot or not slot.unitId) then table.insert(result, i) end
    end
    return result
end
local function getOccupiedSlots()
    local result = {}
    for i = 1, PlotConfig.GetMaxSlots() do
        local slot = slotData(i)
        if unlocked(i) and slot and slot.unitId then table.insert(result, i) end
    end
    return result
end

local function addHistory(kind, text)
    table.insert(Runtime.history, 1, {time = os.date("%H:%M:%S"), kind = kind, text = text})
    while #Runtime.history > 30 do table.remove(Runtime.history) end
end

local function nextAvailableUpgrade()
    local owned = DataController.Upgrades
    local cash = money()
    local priorities = G.SkillPriority
    local candidates = {}
    local function walk(parent)
        for _, id in TreeStructure.GetChildren(parent) do
            local isOwned = value(owned and owned[id], false) == true
            if isOwned then
                walk(id)
            else
                local config = Upgrades[id]
                if config and config.price <= cash then table.insert(candidates, id) end
            end
        end
    end
    walk("Start")
    table.sort(candidates, function(a, b)
        local function score(id)
            for index, prefix in ipairs(priorities) do if string.find(id, prefix, 1, true) then return index end end
            return 999
        end
        local sa, sb = score(a), score(b)
        if sa == sb then return (Upgrades[a].price or 0) < (Upgrades[b].price or 0) end
        return sa < sb
    end)
    return candidates[1]
end

local function ownsDice(name)
    return name == Dice.GetDefault() or value(DataController.OwnedDice and DataController.OwnedDice[name], false) == true
end

local function diceProgression()
    local result = {}
    for name, config in pairs(Dice.GetAll()) do table.insert(result, {name=name, config=config}) end
    table.sort(result, function(a,b) return (a.config.luck or 0)<(b.config.luck or 0) end)
    return result
end

local function bestOwnedDice()
    local bestName, bestLuck = Dice.GetDefault(), -math.huge
    for _, item in ipairs(diceProgression()) do
        if ownsDice(item.name) and (item.config.luck or 0)>bestLuck then bestName,bestLuck=item.name,item.config.luck or 0 end
    end
    return bestName, Dice.Get(bestName)
end

local function nextDiceUpgrade()
    local bestName, bestConfig = bestOwnedDice()
    local bestLuck = bestConfig and bestConfig.luck or 0
    for _, item in ipairs(diceProgression()) do
        if not ownsDice(item.name) and (item.config.luck or 0)>bestLuck then return item.name,item.config,bestName end
    end
    return nil,nil,bestName
end

local function equipBestDice()
    local name = bestOwnedDice()
    if name and value(DataController.Dice, "")~=name then
        Remotes.EquipDice:FireServer(name)
        addHistory("DICE", "Equipped "..name)
    end
    return name
end

local function selectedRarityNames()
    local result = {}
    for key, value in pairs(G.SellRarities) do
        local name = type(key) == "string" and value == true and key or value
        if type(name) == "string" then table.insert(result, name) end
    end
    table.sort(result)
    return result
end

local function plottedUnitIds()
    local result = {}
    for i = 1, PlotConfig.GetMaxSlots() do
        local slot = slotData(i)
        if slot and slot.unitId then result[slot.unitId] = true end
    end
    return result
end

-- Mirrors the game's own backpack counter: each Unit inventory entry occupies
-- one slot, while Unit Storage is read live so rebirths/upgrades are respected.
local function inventoryUsage()
    local used = 0
    for _, entry in pairs(value(DataController.Inventory, {})) do
        if type(entry) == "table" and entry.name then
            local config = entryConfig(entry.name)
            if config and config.kind == "Unit" then used += 1 end
        end
    end
    local ok, capacity = pcall(BuffController.GetBuff, "Unit Storage")
    capacity = ok and tonumber(capacity) or 0
    return used, capacity
end

local function buildSaleKeys()
    local result, protected = {}, plottedUnitIds()
    local inventory = value(DataController.Inventory, {})
    local selectedRarities = {}
    for _, rarity in ipairs(selectedRarityNames()) do selectedRarities[rarity] = true end
    for key, entry in pairs(inventory) do
        -- Unit inventory records are unique entries and do not carry an `amount`
        -- field. Requiring it made every unit in "All" mode ineligible.
        if type(entry) == "table" and entry.name and not protected[key] then
            local attributes = entry.attributes or {}
            if not attributes.locked then
                local config = entryConfig(entry.name)
                if config and config.kind == "Unit" then
                    local rarity = config.getRarity and config.getRarity(attributes) or Rarities.Refs.Common
                    local allowed = G.SellMode == "All" or selectedRarities[rarity] == true
                    if allowed then table.insert(result, key) end
                end
            end
        end
    end
    table.sort(result)
    return result
end

local function sellSelected()
    local keys = buildSaleKeys()
    if #keys == 0 then return 0, 0 end
    local summary = SellUtil.CreateSummary(value(DataController.Inventory, {}), value(DataController.Slots, {}), keys)
    local ok, _, amount = pcall(function() return Remotes.SellInventory:InvokeServer(keys) end)
    if not ok then return 0, 0 end
    local units = summary and summary.totalUnits or 0
    local price = tonumber(amount) or (summary and summary.totalPrice) or 0
    addHistory("SELL", string.format("%d units | $%s", units, formatNumber(price)))
    return units, price
end

local function equipBestThenSell()
    Runtime.sellStatus = "Equipping best units"
    Remotes.EquipBest:FireServer()
    task.wait(1)
    Runtime.sellStatus = "Selling eligible units"
    return sellSelected()
end

local function activeBoostCategories()
    local result = {}
    local now = workspace:GetServerTimeNow()
    for _, entry in pairs(value(DataController.ActiveEntries, {})) do
        if type(entry) == "table" and entry.name then
            local config = entryConfig(entry.name)
            local active = type(entry.remaining) ~= "number" or type(entry.startedAt) ~= "number"
                or entry.remaining > now - entry.startedAt
            if config and config.kind == "Boost" and active then
                result[config.category or entry.name] = true
            end
        end
    end
    return result
end

local function boostInventoryAmount(name)
    local amount = 0
    for _, entry in pairs(value(DataController.Inventory, {})) do
        if type(entry) == "table" and entry.name == name then
            amount += tonumber(entry.amount) or 1
        end
    end
    return amount
end

local function useSelectedBoosts()
    local candidates = {}
    local selected = {}
    for key, value in pairs(G.SelectedBoosts) do
        local name = type(key) == "string" and value == true and key or value
        if type(name) == "string" then table.insert(selected, name) end
    end
    for _, name in ipairs(selected) do
        local config = BoostConfig.entries[name]
        local amount = boostInventoryAmount(name)
        if config and amount > 0 then
            table.insert(candidates, {name=name, config=config, amount=amount})
        end
    end
    table.sort(candidates, function(a, b)
        if a.config.category == b.config.category then return (a.config.tier or 0) > (b.config.tier or 0) end
        return a.name < b.name
    end)
    for _, item in ipairs(candidates) do
        local consumed = 0
        for _ = 1, item.amount do
            if not Runtime.running or not G.AutoBoost then break end
            BoostController.UseBoost(item.name)
            consumed += 1
            task.wait(0.12)
        end
        if consumed > 0 then
            addHistory("BOOST", string.format("%s x%d", item.name, consumed))
        end
    end
end

local function selectedSet(selection)
    local result = {}
    for key, item in pairs(selection or {}) do
        local name = type(key)=="string" and item==true and key or item
        if type(name)=="string" then result[name]=true end
    end
    return result
end

local function selectedCount(selection)
    local count = 0
    for _ in pairs(selectedSet(selection)) do count += 1 end
    return count
end

local function inventoryAmount(entryName)
    local amount = 0
    for _, entry in pairs(value(DataController.Inventory, {})) do
        if type(entry)=="table" and entry.name==entryName then amount += tonumber(entry.amount) or 1 end
    end
    return amount
end

local function selectedPlotSlots(selection)
    local result = {}
    for label in pairs(selectedSet(selection)) do
        local index = tonumber(label:match("(%d+)$"))
        if index then table.insert(result,index) end
    end
    table.sort(result)
    return result
end

local function rollSelectedProgression(kind)
    local isGrade = kind=="Grade"
    local targets = selectedSet(isGrade and G.DesiredGrades or G.DesiredTraits)
    local slots = selectedPlotSlots(isGrade and G.GradeSlots or G.TraitSlots)
    local tokenName = isGrade and "Gems" or "Trait Reroll"
    if inventoryAmount(tokenName)<=0 then return false,tokenName.." depleted" end
    for _, index in ipairs(slots) do
        local slot = slotData(index)
        local unit = slot and slot.unitId and inventoryUnit(slot.unitId)
        if unit then
            local attributes = unit.attributes or {}
            local current = isGrade and attributes.grade or attributes.trait
            local config = current and (isGrade and Grades[current] or Traits[current])
            if not targets[current] then
                if config and config.protected and G.PreserveProtectedRolls then
                    -- Keep protected results unless the user explicitly disables protection.
                else
                    local remote = isGrade and Remotes.GradeRoll or Remotes.TraitRoll
                    if config and config.protected then remote:FireServer(slot.unitId,true)
                    else remote:FireServer(slot.unitId) end
                    addHistory(string.upper(kind),string.format("Slot %02d | %s -> rolling",index,tostring(current or "None")))
                    return true,string.format("Slot %02d | %s",index,tostring(current or "None"))
                end
            end
        end
    end
    return false,#slots==0 and "Select plot slots" or "All selected units reached a target or are protected"
end

local function claimCompletedQuests()
    local now = math.floor(workspace:GetServerTimeNow())
    for period, periodConfig in pairs(QuestConfig.Periods) do
        local questState = value(DataController.Quests and DataController.Quests[period], nil)
        if questState and questState.expiresAt and questState.expiresAt>now then
            for _, quest in ipairs(periodConfig.quests) do
                local progress = tonumber(questState.progress and questState.progress[quest.id]) or 0
                local claimed = questState.claimed and questState.claimed[quest.id]==true
                local key=period..":"..quest.id..":"..tostring(questState.expiresAt)
                if not claimed and progress>=quest.target and os.clock()-(Runtime.questClaims and Runtime.questClaims[key] or 0)>5 then
                    Runtime.questClaims=Runtime.questClaims or {}; Runtime.questClaims[key]=os.clock()
                    Remotes.QuestClaim:FireServer(period,quest.id,questState.expiresAt)
                    addHistory("QUEST",period.." "..quest.id.." claimed")
                end
            end
        end
    end
end

local function buySelectedQuestItem()
    local selected = selectedSet(G.QuestShopItems)
    local tickets = inventoryAmount("Tickets")
    local reserve = math.max(0,tonumber(G.QuestTicketReserve) or 0)
    Runtime.questShopCursor=(Runtime.questShopCursor or 0)+1
    for offset=0,#QuestConfig.Shop-1 do
        local index=((Runtime.questShopCursor+offset-1)%#QuestConfig.Shop)+1
        local item=QuestConfig.Shop[index]
        local owned=item.gamepass and value(DataController.OwnedGamepasses and DataController.OwnedGamepasses[item.name],false)==true
        if selected[item.name] and not owned and tickets-item.tickets>=reserve then
            Runtime.questShopCursor=index
            Remotes.QuestBuy:FireServer(item.name)
            addHistory("QUEST SHOP",string.format("%s | %d tickets",item.name,item.tickets))
            return true
        end
    end
    return false
end

local TowerScreen = UIReferences.Root.Tower.Screen
local function activateTowerButton(button)
    if not button or not button.Visible or not getconnections then return false end
    local activated = false
    for _, connection in ipairs(getconnections(button.Activated)) do
        if connection.Function then
            task.spawn(connection.Function)
            activated = true
        end
    end
    return activated
end

local function setNativeTowerLoop(enabled)
    local autoButton = TowerScreen.Buttons.Auto
    if autoButton.Visible and Runtime.nativeTowerLoop ~= enabled then
        if activateTowerButton(autoButton) then Runtime.nativeTowerLoop = enabled end
    end
    return Runtime.nativeTowerLoop == enabled
end

local function prepareNativeTower()
    task.wait(0.8)
    local autoEnabled = setNativeTowerLoop(true)
    task.wait(0.2)
    local hidden = activateTowerButton(TowerScreen.Parent.Hidden)
    Runtime.towerStartPending = false
    Runtime.towerStatus = autoEnabled and (hidden and "Native Auto + Hidden" or "Native Auto") or "Native Auto unavailable - retrying"
end

local function characterParts()
    local character = LocalPlayer.Character
    if not character then return nil,nil,nil end
    return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

local function setLowGraphics(enabled)
    if enabled then
        if Runtime.globalShadowsOriginal==nil then Runtime.globalShadowsOriginal=Lighting.GlobalShadows end
        Lighting.GlobalShadows=false
        for _,object in ipairs(workspace:GetDescendants()) do
            if object:IsA("BasePart") then
                if not Runtime.graphicsOriginal[object] then Runtime.graphicsOriginal[object]={kind="part",material=object.Material,castShadow=object.CastShadow} end
                object.Material=Enum.Material.Plastic; object.CastShadow=false
            elseif object:IsA("ParticleEmitter") or object:IsA("Trail") then
                if Runtime.graphicsOriginal[object]==nil then Runtime.graphicsOriginal[object]={kind="effect",enabled=object.Enabled} end
                object.Enabled=false
            end
        end
    else
        if Runtime.globalShadowsOriginal~=nil then Lighting.GlobalShadows=Runtime.globalShadowsOriginal; Runtime.globalShadowsOriginal=nil end
        for object,original in pairs(Runtime.graphicsOriginal) do
            if typeof(object)=="Instance" and object.Parent then
                local target: any = object
                if original.kind=="part" and object:IsA("BasePart") then target.Material=original.material; target.CastShadow=original.castShadow
                elseif original.kind=="effect" and (object:IsA("ParticleEmitter") or object:IsA("Trail")) then target.Enabled=original.enabled end
            end
        end
        table.clear(Runtime.graphicsOriginal)
    end
end

connect(LocalPlayer.Idled,function()
    if G.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:Button2Down(Vector2.zero,workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.zero,workspace.CurrentCamera.CFrame)
    end
end)
connect(UserInputService.JumpRequest,function()
    if G.InfiniteJump then
        local _,humanoid=characterParts()
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

local last = {}
local function due(key, delay)
    local now = os.clock()
    if now - (last[key] or 0) < delay then return false end
    last[key] = now
    return true
end

task.spawn(function()
    while Runtime.running do
        task.wait(0.05)
        local _,humanoid=characterParts()
        if G.SpeedWalk and humanoid then
            if Runtime.walkHumanoid~=humanoid then Runtime.walkHumanoid=humanoid; Runtime.walkSpeedOriginal=humanoid.WalkSpeed end
            humanoid.WalkSpeed=G.WalkSpeed
        elseif Runtime.walkHumanoid then
            if Runtime.walkHumanoid.Parent and Runtime.walkSpeedOriginal then Runtime.walkHumanoid.WalkSpeed=Runtime.walkSpeedOriginal end
            Runtime.walkHumanoid=nil; Runtime.walkSpeedOriginal=nil
        end
        if G.HiddenRoll and due("roll", math.max(0.1, G.RollDelay)) then
            pcall(function() Remotes.RollDice:InvokeServer() end)
        end
        if G.AutoCollect and due("collect", G.CollectDelay) then
            for _, index in ipairs(getOccupiedSlots()) do
                local slot = slotData(index)
                if slot and (tonumber(slot.balance) or 0) >= G.MinCollect then
                    Remotes.CollectBalance:FireServer(index)
                    task.wait(0.08)
                end
            end
        end
        if G.AutoUpgrade and due("upgrade", G.UpgradeDelay) then
            for _, index in ipairs(getOccupiedSlots()) do
                local info = unitSummary(index)
                if info.levelPrice and info.levelPrice <= money() then
                    Remotes.LevelUpSlot:FireServer(index)
                    break
                end
            end
        end
        if G.AutoPlace and due("place", 1) then
            local slots = getOpenSlots()
            if #slots > 0 then Remotes.InteractSlot:FireServer(slots[1]) end
        end
        if G.AutoEquipBest and due("best", G.EquipBestDelay) then Remotes.EquipBest:FireServer() end
        if G.AutoBuyDice and due("shop", 1) then
            local target,config = nextDiceUpgrade()
            if target and config and config.price and config.price <= money() then
                Remotes.BuyDice:FireServer(target)
                addHistory("BUY", target .. " | $" .. formatNumber(config.price))
                task.wait(0.5)
            end
            if G.AutoEquipDice then equipBestDice() end
        end
        if G.AutoSell and due("sellCheck", 1) then
            local used, capacity = inventoryUsage()
            if capacity > 0 and used >= capacity then
                local units = equipBestThenSell()
                Runtime.sellStatus = units > 0 and "Inventory full - sold" or "Inventory full - nothing eligible"
                last.sellCheck = os.clock() + (units > 0 and 1 or 9)
            else
                Runtime.sellStatus = "Waiting for full inventory"
            end
        end
        if G.AutoSkillTree and due("skills", G.SkillDelay) then
            local id = nextAvailableUpgrade()
            if id then Remotes.BuyUpgrade:FireServer(id); addHistory("UPGRADE", id) end
        end
        if G.AutoTower and not Runtime.nativeTowerLoop and not Runtime.towerStartPending and G.SelectedTower and due("tower", 3) then
            Remotes.EquipBestTowerTeam:FireServer()
            task.wait(1)
            local ok, started = pcall(TowerController.startTower, G.SelectedTower)
            if ok and started then
                Runtime.towerStartPending = true
                Runtime.towerStatus = "Starting " .. G.SelectedTower
                addHistory("TOWER", "Started " .. G.SelectedTower)
                task.spawn(prepareNativeTower)
            elseif not ok then
                Runtime.towerStatus = "Start failed - retrying"
            end
        end
        if G.AutoRebirth and due("rebirth", G.RebirthDelay) then
            local current = rebirth()
            local nextInfo = Rebirths.GetNext(current)
            if nextInfo and current < G.StopRebirth and money() >= nextInfo.cost then
                Remotes.Rebirth:FireServer()
                addHistory("REBIRTH", tostring(current + 1))
            end
        end
    end
end)

local MacLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/NickolasFrutuoso/Roblox/refs/heads/main/NrHUB-UI.lua"))()
pcall(function() MacLib:SetFolder(CONFIG_FOLDER) end)
local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(900, 650)
local compact = UserInputService.TouchEnabled or viewport.X < 900
local tabs
local scriptTabOrder = {"Dashboard", "Automation", "Economy", "Progression", "Other"}
-- LucideBlox icon ids: https://github.com/frappedevs/lucideblox
local scriptTabIcons = {
    Dashboard = "rbxassetid://7733970318", -- layout-dashboard
    Automation = "rbxassetid://7733916988", -- bot
    Economy = "rbxassetid://7743866529", -- coins
    Progression = "rbxassetid://7743874262", -- trending-up
    Other = "rbxassetid://7733917120", -- box
}
local systemTabIcons = {
    Settings = "rbxassetid://7734053495", -- settings
    Player = "rbxassetid://7743875962", -- user
}
local scriptTabRank = {}
for index, tabName in ipairs(scriptTabOrder) do
    scriptTabRank[tabName] = index
end
local systemTabRank = {
    Settings = #scriptTabOrder + 2,
    Player = #scriptTabOrder + 3,
}
local hub = MacLib:CreateHUB({
    Title = "Nr HUB",
    Subtitle = "Anime Dice",
    Size = compact and UDim2.fromOffset(math.max(300, viewport.X - 18), math.max(380, viewport.Y - 70)) or UDim2.fromOffset(868, 650),
    DragStyle = 1,
    AcrylicBlur = false,
    Keybind = Enum.KeyCode[G.MenuKeybind] or Enum.KeyCode.F12,
    ShowUserInfo = true,
    Logo = "rbxassetid://124193000500623",
    KeyStatus = "Active",
    KeyPlan = "Nr HUB Access",
    KeyDeviceLock = "Linked",
    OnTabGroup = function(tabGroup)
        tabs = tabGroup
        -- Create these tabs inside OnTabGroup because CreateHUB inserts its divider immediately after this callback.
        -- Anything created later would appear below Settings/Player.
        for _, tabName in ipairs(scriptTabOrder) do
            Runtime.controls[tabName] = Runtime.controls[tabName] or tabGroup:Tab({
                Name = tabName,
                Image = scriptTabIcons[tabName],
            })
        end
    end,
})
local window = hub.Window
local function restyleCreateHUBNavigation()
    local containers = {}
    local seen = {}
    local function addContainer(container)
        if container and not seen[container] then
            seen[container] = true
            table.insert(containers, container)
        end
    end
    addContainer(LocalPlayer:FindFirstChild("PlayerGui"))
    pcall(function() if gethui then addContainer(gethui()) end end)
    pcall(function() addContainer(game:GetService("CoreGui")) end)

    for _, container in ipairs(containers) do
        for _, item in ipairs(container:GetDescendants()) do
            if item.Name == "TabDivider" and item:IsA("GuiObject") then
                item.LayoutOrder = #scriptTabOrder + 1
                -- The library hides the divider in compact rail mode; keep that behavior.
            elseif item.Name == "TabSwitcherName" and item:IsA("TextLabel") then
                local tabName = item.Text
                local tabButton = item:FindFirstAncestor("TabSwitcher") or item.Parent
                local rank = scriptTabRank[tabName] or systemTabRank[tabName]
                if tabButton and tabButton:IsA("GuiObject") and rank then
                    local compactRail = item.Visible == false or tabButton.AbsoluteSize.X <= 48
                    tabButton.Visible = true
                    tabButton.LayoutOrder = rank
                    tabButton.Size = compactRail and UDim2.fromOffset(36, 38) or UDim2.new(1, -12, 0, 40)
                    item.LayoutOrder = 1
                    item.TextTransparency = scriptTabRank[tabName] and 0.18 or 0.35
                    item.TextSize = scriptTabRank[tabName] and 15 or 14

                    local padding = tabButton:FindFirstChild("TabSwitcherUIPadding")
                    if padding and padding:IsA("UIPadding") then
                        padding.PaddingLeft = UDim.new(0, compactRail and 0 or 18)
                        padding.PaddingRight = UDim.new(0, compactRail and 0 or 22)
                    end

                    local layout = tabButton:FindFirstChild("TabSwitcherUIListLayout")
                    if layout and layout:IsA("UIListLayout") then
                        layout.HorizontalAlignment = compactRail and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left
                    end

                    local icon = tabButton:FindFirstChild("TabImage")
                    if not icon then
                        icon = Instance.new("ImageLabel")
                        icon.Name = "TabImage"
                        icon.BackgroundTransparency = 1
                        icon.BorderSizePixel = 0
                        icon.LayoutOrder = 0
                        icon.Parent = tabButton
                    end
                    if icon:IsA("ImageLabel") then
                        icon.Image = scriptTabIcons[tabName] or systemTabIcons[tabName] or "rbxassetid://7733917120"
                        icon.Size = UDim2.fromOffset(18, 18)
                        icon.ImageTransparency = compactRail and 0.08 or 0.28
                        icon.Visible = true
                    end

                    local initial = tabButton:FindFirstChild("TabInitial")
                    if initial then
                        initial.Visible = false
                        initial:Destroy()
                    end
                end
            end
        end
    end
end
local hideCreateHUBSystemTabs = restyleCreateHUBNavigation
task.spawn(function()
    while not Runtime.unloaded do
        restyleCreateHUBNavigation()
        task.wait(0.35)
    end
end)
if hub.Home and hub.Home.Select then
    pcall(function() hub.Home:Select() end)
end
-- The script tabs are pre-created above the CreateHUB divider. Sections reuse them instead of creating late tabs.
tabs = tabs or window:TabGroup()
local function section(tabName, side)
    if not Runtime.controls[tabName] then
        Runtime.controls[tabName] = tabs:Tab({Name = tabName, Image = scriptTabIcons[tabName]})
    end
    return Runtime.controls[tabName]:Section({Side = side or "Left"})
end
local function toggle(sec, name, key, callback)
    return sec:Toggle({Name=name,Default=G[key]==true,Callback=function(v) G[key]=v==true; if callback then callback(v==true) end end},key)
end
local function slider(sec,name,key,min,max,suffix)
    return sec:Slider({Name=name,Minimum=min,Maximum=max,Default=G[key],Precision=2,DisplayMethod="Value",Suffix=suffix or "",Callback=function(v) G[key]=tonumber(v) or G[key] end},key)
end

local overview = section("Dashboard","Left"):Paragraph({Header="Account Overview",Body="Loading..."})
local slotPanel = section("Dashboard","Right"):Paragraph({Header="Plot Slots",Body="Loading..."})
local activityPanel = section("Dashboard","Left"):Paragraph({Header="Recent Activity",Body="No actions yet."})
local playerStats = section("Dashboard","Right"):Paragraph({Header="Player Stats",Body="Loading..."})

local rolling = section("Automation","Left")
toggle(rolling,"Auto Roll","AutoRoll",function(v) Remotes.SetAutoRoll:FireServer(v) end)
toggle(rolling,"Hidden Roll","HiddenRoll")
slider(rolling,"Roll Delay","RollDelay",0.1,3,"s")
rolling:Button({Name="Roll Once",Callback=function() pcall(function() Remotes.RollDice:InvokeServer() end) end})

local plot = section("Automation","Right")
toggle(plot,"Auto Place","AutoPlace")
toggle(plot,"Auto Upgrade","AutoUpgrade")
slider(plot,"Upgrade Delay","UpgradeDelay",0.25,10,"s")
toggle(plot,"Auto Collect","AutoCollect")
slider(plot,"Collect Delay","CollectDelay",0.25,15,"s")
slider(plot,"Minimum Balance","MinCollect",0,1000000,"$")
toggle(plot,"Periodic Equip Best","AutoEquipBest")
slider(plot,"Equip Best Delay","EquipBestDelay",2,60,"s")
plot:Button({Name="Equip Best Now",Callback=function() Remotes.EquipBest:FireServer() end})

task.spawn(function()
    while Runtime.running do
        local lines = {}
        for i = 1, PlotConfig.GetMaxSlots() do
            local info = unitSummary(i)
            if not info.unlocked and info.empty then
                table.insert(lines,string.format("%02d | Locked (R%d)",i,PlotConfig.GetSlotRebirthRequirement(i)))
            elseif info.empty then
                table.insert(lines,string.format("%02d | Empty",i))
            else
                table.insert(lines,string.format("%02d | %s Lv.%s | $%s/s | $%s",i,info.name,tostring(info.level),formatNumber(info.income),formatNumber(info.balance)))
            end
        end
        pcall(function() slotPanel:UpdateBody(table.concat(lines,"\n")) end)
        task.wait(1)
    end
end)

local inventory = section("Economy","Left")
inventory:Button({Name="Equip Best",Callback=function() Remotes.EquipBest:FireServer() end})
toggle(inventory,"Auto Sell","AutoSell")
inventory:Dropdown({Name="Sell Mode",Options={"By Rarity","All"},Default=G.SellMode,Multi=false,Required=false,Search=false,Callback=function(v) G.SellMode=tostring(v) end},"SellMode")
inventory:Dropdown({Name="Sell Rarities",Options={"Common","Uncommon","Rare","Epic","Legendary","Mythical","Divine","Exotic","Celestial","Secret I","Secret II","Exclusive"},Default=G.SellRarities,Multi=true,Required=false,Search=true,Callback=function(v) if type(v)=="table" then G.SellRarities=v end end},"SellRarities")
inventory:Button({Name="Equip Best + Sell Now",Callback=function() task.spawn(equipBestThenSell) end})
local sellInfo = inventory:Paragraph({Header="Auto Sell Status",Body="Loading..."})

local diceNames = {}
for name in pairs(Dice.GetAll()) do table.insert(diceNames,name) end
table.sort(diceNames,function(a,b)
    if a=="Best Affordable" then return true elseif b=="Best Affordable" then return false end
    return (Dice.Get(a).luck or 0)<(Dice.Get(b).luck or 0)
end)
local shop = section("Economy","Right")
toggle(shop,"Auto Buy Dice Progression","AutoBuyDice")
toggle(shop,"Auto Equip Best Dice","AutoEquipDice")
shop:Button({Name="Equip Best Dice Now",Callback=equipBestDice})
local shopInfo = shop:Paragraph({Header="Dice Progression",Body="Loading..."})

local skill = section("Economy","Left")
toggle(skill,"Auto Buy Available","AutoSkillTree")
slider(skill,"Purchase Delay","SkillDelay",0.25,10,"s")
skill:Dropdown({Name="Priority",Options={"Luck","Money","Roll Speed","Unit Storage","Sell","Damage","Health","Walkspeed"},Default=G.SkillPriority,Multi=true,Required=false,Search=true,Callback=function(v) if type(v)=="table" then G.SkillPriority=v end end},"SkillPriority")
local nextSkill = skill:Paragraph({Header="Next Skill Upgrade",Body="-"})

local rebirthSec = section("Automation","Left")
toggle(rebirthSec,"Auto Rebirth","AutoRebirth")
slider(rebirthSec,"Check Delay","RebirthDelay",0.5,15,"s")
slider(rebirthSec,"Stop At Rebirth","StopRebirth",1,11,"")
rebirthSec:Button({Name="Rebirth Once",Callback=function()
    local n=Rebirths.GetNext(rebirth()); if n and money()>=n.cost then Remotes.Rebirth:FireServer() end
end})
local rebirthInfo = rebirthSec:Paragraph({Header="Rebirth Progress",Body="-"})

local function plotUnitOptions()
    local options={}
    for _,index in ipairs(getOccupiedSlots()) do
        local info=unitSummary(index)
        if info.raw and info.name then
            table.insert(options,string.format("%s - P%d",info.name,index))
        end
    end
    return options
end
local plotSlotOptions=plotUnitOptions()
local gradeNames={}; for name in pairs(Grades) do table.insert(gradeNames,name) end
table.sort(gradeNames,function(a,b) return (Grades[a].order or 0)<(Grades[b].order or 0) end)
local traitNames={}; for name in pairs(Traits) do table.insert(traitNames,name) end
table.sort(traitNames,function(a,b) return (Traits[a].order or 0)<(Traits[b].order or 0) end)

local gradeSection=section("Progression","Left")
local gradeUnitDropdown=gradeSection:Dropdown({Name="Plot Characters",Options=plotSlotOptions,Default=G.GradeSlots,Multi=true,Required=false,Search=true,Callback=function(v) if type(v)=="table" then G.GradeSlots=v end end},"GradeSlots")
gradeSection:Dropdown({Name="Stop At Grades",Options=gradeNames,Default=G.DesiredGrades,Multi=true,Required=true,Search=false,Callback=function(v) if type(v)=="table" then G.DesiredGrades=v end end},"DesiredGrades")
toggle(gradeSection,"Auto Grade","AutoGrade")
slider(gradeSection,"Grade Roll Delay","GradeDelay",0.25,5,"s")
local gradeInfo=gradeSection:Paragraph({Header="Auto Grade Status",Body="Select equipped plot slots and accepted grades."})

local traitSection=section("Progression","Right")
local traitUnitDropdown=traitSection:Dropdown({Name="Plot Characters",Options=plotSlotOptions,Default=G.TraitSlots,Multi=true,Required=false,Search=true,Callback=function(v) if type(v)=="table" then G.TraitSlots=v end end},"TraitSlots")
traitSection:Dropdown({Name="Stop At Traits",Options=traitNames,Default=G.DesiredTraits,Multi=true,Required=true,Search=true,Callback=function(v) if type(v)=="table" then G.DesiredTraits=v end end},"DesiredTraits")
toggle(traitSection,"Auto Trait","AutoTrait")
slider(traitSection,"Trait Roll Delay","TraitDelay",0.2,5,"s")
toggle(traitSection,"Preserve Protected Results","PreserveProtectedRolls")
local traitInfo=traitSection:Paragraph({Header="Auto Trait Status",Body="Select equipped plot slots and accepted traits."})

local function refreshPlotCharacters()
    local options=plotUnitOptions()
    local valid={}; for _,name in ipairs(options) do valid[name]=true end
    local function refresh(dropdown,current)
        local keep={}
        for old in pairs(selectedSet(current)) do
            if valid[old] then table.insert(keep,old) else
                local oldIndex=tonumber(old:match("(%d+)$"))
                if oldIndex then
                    for _,name in ipairs(options) do
                        if tonumber(name:match("(%d+)$"))==oldIndex then table.insert(keep,name); break end
                    end
                end
            end
        end
        dropdown:ClearOptions()
        dropdown:InsertOptions(options)
        dropdown:UpdateSelection(keep)
    end
    refresh(gradeUnitDropdown,G.GradeSlots)
    refresh(traitUnitDropdown,G.TraitSlots)
    local message=#options>0 and string.format("Found %d occupied plot character(s).",#options) or "No occupied unlocked plot characters found."
    pcall(function() gradeInfo:UpdateBody(message); traitInfo:UpdateBody(message) end)
end
gradeSection:Button({Name="Refresh Plot Characters",Callback=refreshPlotCharacters})
traitSection:Button({Name="Refresh Plot Characters",Callback=refreshPlotCharacters})
task.defer(refreshPlotCharacters)

local questSection=section("Progression","Left")
toggle(questSection,"Auto Claim All Quests","AutoClaimQuests")
local questInfo=questSection:Paragraph({Header="Daily + Weekly Quests",Body="Automatic collection is disabled."})

local questShopNames={}; for _,item in ipairs(QuestConfig.Shop) do table.insert(questShopNames,item.name) end
local questShopSection=section("Progression","Right")
questShopSection:Dropdown({Name="Quest Shop Items",Options=questShopNames,Default=G.QuestShopItems,Multi=true,Required=false,Search=true,Callback=function(v) if type(v)=="table" then G.QuestShopItems=v end end},"QuestShopItems")
toggle(questShopSection,"Auto Quest Shop","AutoQuestShop")
slider(questShopSection,"Purchase Delay","QuestShopDelay",0.5,15,"s")
slider(questShopSection,"Keep Tickets","QuestTicketReserve",0,1000,"")
local questShopInfo=questShopSection:Paragraph({Header="Quest Shop Status",Body="Select the items to purchase."})

task.spawn(function()
    while Runtime.running do
        if G.AutoGrade then
            local _,status=rollSelectedProgression("Grade")
            pcall(function() gradeInfo:UpdateBody(status) end)
            task.wait(math.max(0.25,tonumber(G.GradeDelay) or 0.3))
        else task.wait(0.5) end
    end
end)

task.spawn(function()
    while Runtime.running do
        if G.AutoTrait then
            local _,status=rollSelectedProgression("Trait")
            pcall(function() traitInfo:UpdateBody(status) end)
            task.wait(math.max(0.2,tonumber(G.TraitDelay) or 0.25))
        else task.wait(0.5) end
    end
end)

task.spawn(function()
    while Runtime.running do
        if G.AutoClaimQuests then claimCompletedQuests() end
        task.wait(2)
    end
end)

task.spawn(function()
    while Runtime.running do
        if G.AutoQuestShop then buySelectedQuestItem() end
        task.wait(math.max(0.5,tonumber(G.QuestShopDelay) or 1))
    end
end)

local boostNames = {}
for name in pairs(BoostConfig.entries) do table.insert(boostNames, name) end
table.sort(boostNames, function(a,b)
    local x,y=BoostConfig.entries[a],BoostConfig.entries[b]
    if x.category==y.category then return (x.tier or 0)<(y.tier or 0) end
    return tostring(x.category)<tostring(y.category)
end)
local boosts = section("Automation","Left")
toggle(boosts,"Auto Boost","AutoBoost")
local boostDropdown = boosts:Dropdown({Name="Boosts",Options=boostNames,Default=G.SelectedBoosts,Multi=true,Required=false,Search=true,Callback=function(v) if type(v)=="table" then G.SelectedBoosts=v end end},"SelectedBoosts")
boosts:Button({Name="Select All Boosts",Callback=function() boostDropdown:UpdateSelection(boostNames) end})
local boostInfo = boosts:Paragraph({Header="Auto Boost Status",Body="Loading..."})

-- Continuous boost inventory watcher. Tower floor rewards are detected on the
-- next pass and every owned copy of each selected boost is consumed.
task.spawn(function()
    while Runtime.running do
        if G.AutoBoost then
            useSelectedBoosts()
            task.wait(1)
        else
            task.wait(0.5)
        end
    end
end)

local towerNames = {}
for name in pairs(Towers.GetAll()) do table.insert(towerNames,name) end
table.sort(towerNames,function(a,b) return (Towers.Get(a).order or 99)<(Towers.Get(b).order or 99) end)
local towers = section("Automation","Right")
towers:Button({Name="Equip Best Tower Team",Callback=function() Remotes.EquipBestTowerTeam:FireServer() end})
towers:Dropdown({Name="Tower Mode",Options=towerNames,Default=G.SelectedTower,Multi=false,Required=true,Search=false,Callback=function(v)
    local nextTower=tostring(v)
    if nextTower~=G.SelectedTower and Runtime.nativeTowerLoop then setNativeTowerLoop(false) end
    G.SelectedTower=nextTower
end},"SelectedTower")
toggle(towers,"Auto Tower","AutoTower",function(enabled)
    if enabled then
        Runtime.nativeTowerLoop=false
        Runtime.towerStartPending=false
        Runtime.towerStatus="Equipping best team"
    else
        setNativeTowerLoop(false)
        Runtime.towerStartPending=false
        Runtime.towerStatus="Stops after current fight"
    end
end)
local towerInfo = towers:Paragraph({Header="Tower Status",Body="Loading..."})

local function cleanWebhookUrl(url)
    url=tostring(url or ""):match("^%s*(.-)%s*$")
    url=url:gsub("^https://discordapp%.com/","https://discord.com/"):gsub("^https://canary%.discord%.com/","https://discord.com/")
    return url:gsub("%?.*$",""):gsub("/+$","")
end

local function validWebhookUrl(url)
    return type(url)=="string" and url:match("^https://discord%.com/api/webhooks/%d+/[%w_-]+$")~=nil
end

local function httpRequest()
    local env=getgenv()
    return env.request or env.http_request or (env.syn and env.syn.request)
end

local function safeText(text,limit)
    text=tostring(text or "-"):gsub("[`*_~|>]","")
    return text:sub(1,limit or 1024)
end

local WebhookStatus
local function setWebhookStatus(title,body)
    if WebhookStatus then pcall(function() WebhookStatus:UpdateHeader(title); WebhookStatus:UpdateBody(body) end) end
end

local function webhookSnapshot()
    local occupied=getOccupiedSlots(); local income,stored=0,0
    for _,index in ipairs(occupied) do local info=unitSummary(index); income+=info.income or 0; stored+=info.balance or 0 end
    local used,capacity=inventoryUsage()
    local ownedDice=1
    for name in pairs(Dice.GetAll()) do if name~=Dice.GetDefault() and ownsDice(name) then ownedDice+=1 end end
    local discovered=0; for _,seen in pairs(value(DataController.DiscoveredUnits,{})) do if seen then discovered+=1 end end
    local upgrades=0; for _,owned in pairs(value(DataController.Upgrades,{})) do if owned then upgrades+=1 end end
    local team=0; for _,id in pairs(value(DataController.TowerTeam,{})) do if id then team+=1 end end
    local equipped=value(DataController.Dice,Dice.GetDefault())
    local nextDice,nextConfig=nextDiceUpgrade()
    local autos={}
    for _,item in ipairs({{"Roll",G.AutoRoll or G.HiddenRoll},{"Plot",G.AutoPlace or G.AutoUpgrade or G.AutoCollect},{"Sell",G.AutoSell},{"Dice",G.AutoBuyDice},{"Skills",G.AutoSkillTree},{"Rebirth",G.AutoRebirth},{"Boost",G.AutoBoost},{"Tower",G.AutoTower}}) do
        if item[2] then table.insert(autos,item[1]) end
    end
    return {
        occupied=#occupied,maxSlots=PlotConfig.GetMaxSlots(),income=income,stored=stored,
        used=used,capacity=capacity,ownedDice=ownedDice,totalDice=#diceNames,discovered=discovered,
        upgrades=upgrades,team=team,equipped=equipped,nextDice=nextDice,nextCost=nextConfig and nextConfig.price,
        rolls=tonumber(value(DataController.Rolls,0)) or 0,money=money(),rebirth=rebirth(),
        automations=#autos>0 and table.concat(autos,", ") or "None",
    }
end

local function sendWebhook(online,reason,force)
    if Runtime.webhookBusy then return false,"An update is already running." end
    if not force and not G.WebhookEnabled then return false,"Enable the webhook first." end
    local url=cleanWebhookUrl(Runtime.webhookUrl)
    if not validWebhookUrl(url) then return false,"Enter a valid Discord webhook URL." end
    local request=httpRequest()
    if type(request)~="function" then return false,"HTTP requests are unavailable." end
    Runtime.webhookBusy=true; Runtime.webhookLastAttempt=os.clock()
    task.spawn(function()
        local snapshot=webhookSnapshot()
        local uptime=math.max(0,os.time()-Runtime.webhookStartedAt)
        local duration=string.format("%02d:%02d:%02d",math.floor(uptime/3600),math.floor(uptime%3600/60),uptime%60)
        local state=online and "ONLINE" or "OFFLINE"
        local color=online and 5763719 or 15548997
        local description=online and "Live account and automation overview." or safeText(reason or "Tracker stopped.",300)
        local fields={
            {name="Player",value=string.format("**%s** (@%s)\nUser ID: `%d`",safeText(LocalPlayer.DisplayName,80),safeText(LocalPlayer.Name,80),LocalPlayer.UserId),inline=false},
            {name="Progress",value=string.format("Rolls **%s**\nRebirth **%d/11**\nMoney **$%s**",formatNumber(snapshot.rolls),snapshot.rebirth,formatNumber(snapshot.money)),inline=true},
            {name="Inventory",value=string.format("Units **%d/%d**\nDiscovered **%d**\nUpgrades **%d**",snapshot.used,snapshot.capacity,snapshot.discovered,snapshot.upgrades),inline=true},
            {name="Dice",value=string.format("Equipped **%s**\nOwned **%d/%d**\nNext **%s**",safeText(snapshot.equipped,80),snapshot.ownedDice,snapshot.totalDice,safeText(snapshot.nextDice or "MAX",80)),inline=true},
            {name="Plot",value=string.format("Slots **%d/%d**\nIncome **$%s/s**\nStored **$%s**",snapshot.occupied,snapshot.maxSlots,formatNumber(snapshot.income),formatNumber(snapshot.stored)),inline=true},
            {name="Tower",value=string.format("Mode **%s**\nTeam **%d**\nStatus **%s**",safeText(G.SelectedTower,80),snapshot.team,safeText(Runtime.towerStatus,100)),inline=true},
            {name="Auto Sell",value=string.format("**%s** - %s\n%s",G.AutoSell and "Enabled" or "Disabled",safeText(G.SellMode,40),safeText(G.SellMode=="All" and "All rarities" or table.concat(selectedRarityNames(),", "),150)),inline=true},
            {name="Active Automations",value=safeText(snapshot.automations,500),inline=false},
            {name="Session",value=string.format("Status **%s**\nUptime `%s`\nServer players **%d**",state,duration,#Players:GetPlayers()),inline=false},
        }
        local avatar=string.format("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=420&height=420&format=png",LocalPlayer.UserId)
        local payload={username="Anime Dice Tracker",avatar_url=avatar,allowed_mentions={parse={}},embeds={{
            title="Anime Dice | "..state,description=description,color=color,fields=fields,
            thumbnail={url=avatar},timestamp=os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer={text=string.format("Anime Dice MacUI - Global update every %d min",math.clamp(tonumber(G.WebhookInterval) or 30,10,1440))},
        }}}
        local target=url.."?wait=true"; local method="POST"
        if Runtime.webhookMessageId then target=url.."/messages/"..tostring(Runtime.webhookMessageId); method="PATCH" end
        local ok,response=pcall(request,{Url=target,Method=method,Headers={["Content-Type"]="application/json"},Body=HttpService:JSONEncode(payload)})
        local status=ok and type(response)=="table" and tonumber(response.StatusCode or response.Status or response.status_code) or 0
        local success=ok and ((status>=200 and status<300) or (status==0 and type(response)=="table" and (response.Success or response.success)))
        if success then
            if not Runtime.webhookMessageId and type(response)=="table" then
                local body=response.Body or response.body
                local decodedOk,decoded=pcall(function() return type(body)=="table" and body or HttpService:JSONDecode(tostring(body or "")) end)
                if decodedOk and type(decoded)=="table" then Runtime.webhookMessageId=decoded.id end
            end
            Runtime.webhookOfflineSent=not online
            setWebhookStatus("Webhook | "..state,online and "Live panel updated successfully." or "Offline status sent successfully.")
        else
            if status==401 or status==403 or status==404 then G.WebhookEnabled=false end
            setWebhookStatus("Webhook | OFFLINE","Delivery failed (HTTP "..tostring(status)..").")
        end
        Runtime.webhookBusy=false
    end)
    return true,"Sending..."
end

local webhook = section("Other","Left")
WebhookStatus=webhook:Paragraph({Header="Discord Status Webhook",Body="Paste a webhook URL to start a private live panel."})
webhook:Input({Name="Webhook URL",Default="",Placeholder="https://discord.com/api/webhooks/...",Callback=function(v)
    local nextUrl=cleanWebhookUrl(v)
    if nextUrl~=Runtime.webhookUrl then Runtime.webhookMessageId=nil end
    Runtime.webhookUrl=nextUrl
    setWebhookStatus("Discord Status Webhook",nextUrl=="" and "No URL set." or (validWebhookUrl(nextUrl) and "URL accepted. Ready to connect." or "Invalid Discord webhook URL."))
end})
webhook:Input({Name="Global Update Interval",Default=tostring(G.WebhookInterval),Placeholder="10 - 1440 minutes",AcceptedCharacters="Numbers",Callback=function(v)
    G.WebhookInterval=math.clamp(math.floor(tonumber(v) or 30),10,1440)
    setWebhookStatus("Update Interval",string.format("Every %d minutes.",G.WebhookInterval))
end},"WebhookInterval")
toggle(webhook,"Status Webhook","WebhookEnabled",function(enabled)
    if enabled then Runtime.webhookOfflineSent=false; local ok,msg=sendWebhook(true); if not ok then G.WebhookEnabled=false; setWebhookStatus("Webhook | OFFLINE",msg) end
    elseif Runtime.webhookMessageId and not Runtime.webhookOfflineSent then sendWebhook(false,"Status Webhook disabled.",true) end
end)
webhook:Button({Name="Send Status Now",Callback=function() local ok,msg=sendWebhook(true); if not ok then setWebhookStatus("Webhook | OFFLINE",msg) end end})

task.spawn(function()
    while Runtime.running do
        task.wait(5)
        local interval=math.clamp(tonumber(G.WebhookInterval) or 30,10,1440)*60
        if G.WebhookEnabled and (Runtime.webhookLastAttempt==0 or os.clock()-Runtime.webhookLastAttempt>=interval) then sendWebhook(true) end
    end
end)

if G.LowGraphics then task.spawn(setLowGraphics,true) end

task.spawn(function()
    while Runtime.running do
        local current=rebirth(); local n=Rebirths.GetNext(current)
        pcall(function() rebirthInfo:UpdateBody(n and string.format("Rebirth %d -> %d\n$%s / $%s\nSlots: %d/%d",current,current+1,formatNumber(money()),formatNumber(n.cost),#getOccupiedSlots(),PlotConfig.GetMaxSlots()) or "MAX") end)
        local id=nextAvailableUpgrade(); pcall(function() nextSkill:UpdateBody(id and (id.." | $"..formatNumber(Upgrades[id].price)) or "No affordable upgrade") end)
        local lines={}; for i,item in ipairs(Runtime.history) do if i>12 then break end; table.insert(lines,item.time.." | "..item.kind.." | "..item.text) end
        pcall(function() activityPanel:UpdateBody(#lines>0 and table.concat(lines,"\n") or "No actions yet.") end)
        local occupied=getOccupiedSlots(); local totalIncome,totalBalance=0,0
        for _,slotIndex in ipairs(occupied) do local info=unitSummary(slotIndex); totalIncome+=info.income or 0; totalBalance+=info.balance or 0 end
        pcall(function() overview:UpdateBody(string.format("Money     $%s\nRebirth   %d/11\nSlots     %d/%d\nIncome    $%s/s\nStored    $%s",formatNumber(money()),current,#occupied,PlotConfig.GetMaxSlots(),formatNumber(totalIncome),formatNumber(totalBalance))) end)
        local saleKeys=buildSaleKeys(); local used,capacity=inventoryUsage(); local percent=capacity>0 and math.floor((used/capacity)*100+0.5) or 0
        local rarityNames=selectedRarityNames(); local rarityText=G.SellMode=="All" and "All" or (#rarityNames>0 and table.concat(rarityNames, ", ") or "None")
        pcall(function() sellInfo:UpdateBody(string.format("Storage    %d/%d (%d%%)\nTrigger    When full\nSequence   Equip Best > Sell\nMode       %s\nRarities   %s\nEligible   %d entries\nStatus     %s",used,capacity,percent,G.SellMode,rarityText,#saleKeys,Runtime.sellStatus or "Waiting for full inventory")) end)
        local nextDice,nextDiceConfig=nextDiceUpgrade(); local bestDice,bestDiceConfig=bestOwnedDice(); local equippedDice=value(DataController.Dice,Dice.GetDefault())
        pcall(function() shopInfo:UpdateBody(string.format("Equipped   %s\nBest owned %s (%sx)\nNext       %s\nCost       %s\nFunds      $%s\nStatus     %s",equippedDice,bestDice,formatNumber(bestDiceConfig and bestDiceConfig.luck or 1),nextDice or "MAX",nextDiceConfig and ("$"..formatNumber(nextDiceConfig.price or 0)) or "-",formatNumber(money()),not nextDice and "Complete" or ((nextDiceConfig.price or 0)<=money() and "Ready to buy" or "Saving"))) end)
        local ownedDiceCount=1; for name in pairs(Dice.GetAll()) do if name~=Dice.GetDefault() and ownsDice(name) then ownedDiceCount+=1 end end
        local upgradeCount=0; for _,owned in pairs(value(DataController.Upgrades,{})) do if owned then upgradeCount+=1 end end
        local discoveredCount=0; for _,seen in pairs(value(DataController.DiscoveredUnits,{})) do if seen then discoveredCount+=1 end end
        local towerTeamCount=0; for _,unitId in pairs(value(DataController.TowerTeam,{})) do if unitId then towerTeamCount+=1 end end
        pcall(function() playerStats:UpdateBody(string.format("Player      %s\nRolls       %s\nMoney       $%s\nRebirth     %d/11\nDice        %d/%d\nEquipped    %s\nInventory   %d/%d\nDiscovered  %d\nUpgrades    %d\nTower Team  %d",LocalPlayer.DisplayName,formatNumber(tonumber(value(DataController.Rolls,0)) or 0),formatNumber(money()),current,ownedDiceCount,#diceNames,equippedDice,used,capacity,discoveredCount,upgradeCount,towerTeamCount)) end)
        local active=activeBoostCategories(); local selected=0; for _,v in pairs(G.SelectedBoosts) do if v==true or type(v)=="string" then selected+=1 end end; local activeCount=0; for _ in pairs(active) do activeCount+=1 end
        pcall(function() boostInfo:UpdateBody(string.format("Selected   %d/%d\nActive     %d categories\nWatcher    Continuous (1s)\nBehavior   Consumes all selected boosts, including new tower rewards",selected,#boostNames,activeCount)) end)
        local tower=G.SelectedTower and Towers.Get(G.SelectedTower)
        pcall(function() towerInfo:UpdateBody(string.format("Mode       %s\nDifficulty %s\nTeam       Best available\nAuto       %s\nStatus     %s",G.SelectedTower or "-",tower and tower.difficulty.name or "-",G.AutoTower and "On" or "Off",Runtime.towerStatus or "Ready")) end)
        local gradeLines={"Gems: "..formatNumber(inventoryAmount("Gems"))}
        for _,index in ipairs(selectedPlotSlots(G.GradeSlots)) do
            local info=unitSummary(index)
            table.insert(gradeLines,string.format("%02d | %s | %s",index,info.name or "Empty",info.raw and tostring((info.raw.attributes or {}).grade or "None") or "-"))
        end
        if #gradeLines==1 then table.insert(gradeLines,"No plot units selected") end
        local traitLines={"Trait Rerolls: "..formatNumber(inventoryAmount("Trait Reroll"))}
        for _,index in ipairs(selectedPlotSlots(G.TraitSlots)) do
            local info=unitSummary(index)
            table.insert(traitLines,string.format("%02d | %s | %s",index,info.name or "Empty",info.raw and tostring((info.raw.attributes or {}).trait or "None") or "-"))
        end
        if #traitLines==1 then table.insert(traitLines,"No plot units selected") end
        pcall(function() gradeInfo:UpdateBody(table.concat(gradeLines,"\n")); traitInfo:UpdateBody(table.concat(traitLines,"\n")) end)
        local questLines={}
        for period,periodConfig in pairs(QuestConfig.Periods) do
            local state=value(DataController.Quests and DataController.Quests[period],{})
            for _,quest in ipairs(periodConfig.quests) do
                local progress=math.min(quest.target,tonumber(state.progress and state.progress[quest.id]) or 0)
                local claimed=state.claimed and state.claimed[quest.id]==true
                table.insert(questLines,string.format("%s %s | %s/%s | %s",period,quest.id,formatNumber(progress),formatNumber(quest.target),claimed and "Claimed" or (progress>=quest.target and "Ready" or "In progress")))
            end
        end
        pcall(function()
            questInfo:UpdateBody(table.concat(questLines,"\n"))
            questShopInfo:UpdateBody(string.format("Tickets: %s\nSelected: %d\nReserve: %s\nLoop: %s",formatNumber(inventoryAmount("Tickets")),selectedCount(G.QuestShopItems),formatNumber(G.QuestTicketReserve),G.AutoQuestShop and "On" or "Off"))
        end)
        task.wait(1)
    end
end)

function Runtime.Unload()
    if not Runtime.running then return end
    Runtime.unloaded=true
    if G.WebhookEnabled and not Runtime.webhookOfflineSent then sendWebhook(false,"Script unloaded.",true); task.wait(0.35) end
    Runtime.running=false
    if Runtime.nativeTowerLoop then pcall(setNativeTowerLoop, false) end
    setLowGraphics(false)
    if Runtime.walkHumanoid and Runtime.walkHumanoid.Parent and Runtime.walkSpeedOriginal then Runtime.walkHumanoid.WalkSpeed=Runtime.walkSpeedOriginal end
    pcall(function() Remotes.SetAutoRoll:FireServer(false) end)
    saveConfig()
    for _,connection in ipairs(Runtime.connections) do pcall(function() connection:Disconnect() end) end
    pcall(function() window:Unload() end)
    if getgenv().AnimeDiceRuntime==Runtime then getgenv().AnimeDiceRuntime=nil end
end

print("Anime Dice MacUI loaded")
