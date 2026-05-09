local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(3)

-- Networker 0.3.1 = game services, 0.2.1 = DataService
local gameRemotes = nil
local dataRemotes = nil

for _, desc in pairs(ReplicatedStorage:GetDescendants()) do
    if desc:IsA("Folder") and desc.Name == "_remotes" then
        local path = desc:GetFullName()
        if path:find("0.3.1") then
            gameRemotes = desc
        elseif path:find("0.2.1") then
            dataRemotes = desc
        else
            if desc:FindFirstChild("RollService") then
                gameRemotes = desc
            elseif desc:FindFirstChild("DataService") then
                dataRemotes = desc
            end
        end
    end
end

if not gameRemotes or not dataRemotes then
    task.wait(5)
    for _, desc in pairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("Folder") and desc.Name == "_remotes" then
            local path = desc:GetFullName()
            if path:find("0.3.1") and not gameRemotes then
                gameRemotes = desc
            elseif path:find("0.2.1") and not dataRemotes then
                dataRemotes = desc
            end
            if not gameRemotes and desc:FindFirstChild("RollService") then
                gameRemotes = desc
            end
            if not dataRemotes and desc:FindFirstChild("DataService") then
                dataRemotes = desc
            end
        end
    end
end

if not gameRemotes then
    warn("[Zinnyware] FATAL: Could not find game _remotes (0.3.1)")
    return
end

local function getRemote(folder, serviceName)
    if not folder then return nil end
    local svc = folder:FindFirstChild(serviceName)
    if svc then return svc:FindFirstChild("RemoteFunction") end
    return nil
end

local RollRemote = getRemote(gameRemotes, "RollService")
local ZonesRemote = getRemote(gameRemotes, "ZonesService")
local RebirthRemote = getRemote(gameRemotes, "RebirthService")
local InventoryRemote = getRemote(gameRemotes, "InventoryService")
local LootRemote = getRemote(gameRemotes, "LootService")
local BoostRemote = getRemote(gameRemotes, "BoostService")
local IndexRemote = getRemote(gameRemotes, "IndexService")
local DataRemote = getRemote(dataRemotes, "DataService")

-- DataService: InvokeServer("get", key)
local dataCache = {}
local dataCacheTime = {}
local DATA_CACHE_TTL = 2

local function getData(key)
    if not DataRemote then return nil end
    local now = os.clock()
    if dataCache[key] ~= nil and dataCacheTime[key] and (now - dataCacheTime[key]) < DATA_CACHE_TTL then
        return dataCache[key]
    end
    local ok, result = pcall(function()
        return DataRemote:InvokeServer("get", key)
    end)
    if ok then
        dataCache[key] = result
        dataCacheTime[key] = now
        return result
    end
    return dataCache[key]
end

local function getDataFresh(key)
    if not DataRemote then return nil end
    local ok, result = pcall(function()
        return DataRemote:InvokeServer("get", key)
    end)
    if ok then
        dataCache[key] = result
        dataCacheTime[key] = os.clock()
        return result
    end
    return nil
end

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local AutoRollEnabled = false
local AutoBuyZoneEnabled = false
local AutoRebirthEnabled = false
local AutoTeleportEnabled = false
local AutoUseDiceEnabled = false
local AutoCollectLootEnabled = false
local AutoUsePotionsEnabled = false
local AutoClaimIndexEnabled = false
local DebugRunning = false

local RollDelay = 0.1
local RebirthCheckInterval = 2
local ZoneCheckInterval = 3
local LootCollectInterval = 1
local PotionCheckInterval = 5

local TotalRolls = 0
local TotalRebirths = 0
local TotalZonesBought = 0
local SessionStart = os.clock()

local function safeInvoke(remote, ...)
    if not remote then return nil end
    local args = {...}
    local success, result = pcall(function()
        return remote:InvokeServer(unpack(args))
    end)
    if success then return result end
    return nil
end

local function doRoll()
    if not RollRemote then return false end
    local result = safeInvoke(RollRemote, "requestRoll")
    if result then TotalRolls = TotalRolls + 1 return true end
    return false
end

local function tryBuyZone()
    if not ZonesRemote then return false end
    local result = safeInvoke(ZonesRemote, "requestPurchaseZone")
    if result then TotalZonesBought = TotalZonesBought + 1 return true end
    return false
end

local function tryRebirth()
    if not RebirthRemote then return false end
    local result = safeInvoke(RebirthRemote, "requestRebirth")
    if result then TotalRebirths = TotalRebirths + 1 return true end
    return false
end

local function getZoneCenter(zoneNumber)
    local Zones = workspace:FindFirstChild("Zones")
    if not Zones then return nil end
    local zoneModel = Zones:FindFirstChild(tostring(zoneNumber))
    if zoneModel and zoneModel:IsA("Model") then
        local pos = zoneModel:GetPivot().Position
        return Vector3.new(pos.X, pos.Y, pos.Z)
    end
    return nil
end

local function teleportToZone(zoneNumber)
    if not ZonesRemote then return false end
    local result = safeInvoke(ZonesRemote, "requestTeleportZone", zoneNumber)
    if result == true then
        task.wait(0.3)
        local center = getZoneCenter(zoneNumber)
        if center then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(center.X, hrp.Position.Y, center.Z)
            end
        end
    end
    return result == true
end

local function teleportToMaxZone()
    local maxZone = getData("maxZone") or 1
    return teleportToZone(maxZone)
end

local function getPlayerCoins() return getData("coins") or 0 end
local function getPlayerGoop() return getData("goop") or 0 end
local function getPlayerRebirths() return getData("rebirths") or 0 end
local function getMaxZone() return getData("maxZone") or 1 end
local function getCurrentZone() return getData("zone") or 1 end

-- InventoryService: "requestUseItem" arms dice for next roll
local function useSpecialDice(diceId)
    if not InventoryRemote then return false end
    local result = safeInvoke(InventoryRemote, "requestUseItem", diceId)
    return result == true
end

-- Priority: inverted > huge > shiny > big
local function useAllSpecialDice()
    if not InventoryRemote then return end
    local items = getData("items") or {}
    local diceOrder = {"invertedDice", "hugeDice", "shinyDice", "bigDice"}
    for _, diceId in pairs(diceOrder) do
        if items[diceId] and items[diceId] > 0 then
            useSpecialDice(diceId)
            task.wait(0.05)
        end
    end
end

local function collectAllLoot()
    if not LootRemote then return 0 end
    local ok, lootData = pcall(function()
        return LootRemote:InvokeServer("getLootData")
    end)
    if not ok or not lootData then return 0 end

    local collected = 0
    for _, loot in pairs(lootData) do
        if loot and loot.uniqueId then
            local success = pcall(function()
                return LootRemote:InvokeServer("requestCollect", loot.uniqueId)
            end)
            if success then collected = collected + 1 end
            task.wait(0.05)
        end
    end
    return collected
end

-- BoostService: kinds = luck, ultraLuck, currency, rollSpeed (180s each)
local function useBoost(boostKind)
    if not BoostRemote then return false end
    local result = safeInvoke(BoostRemote, "requestUseBoost", boostKind)
    return result == true
end

-- Only uses potion if boost expired (expirationTime <= now)
local function consumeAllPotions()
    if not BoostRemote then return end
    local boosts = getData("boosts")
    if not boosts then return end

    local boostKinds = {"luck", "ultraLuck", "currency", "rollSpeed"}
    local serverTime = os.time()

    for _, kind in pairs(boostKinds) do
        local boostData = boosts[kind]
        if boostData then
            local amount = boostData.amount or 0
            local expiration = boostData.expirationTime or 0
            if amount > 0 and expiration <= serverTime then
                useBoost(kind)
                task.wait(0.1)
            end
        end
    end
end

local function claimAllIndexRewards()
    if not IndexRemote then return end
    local categories = {"basic", "big", "huge", "shiny", "inverted"}
    for _, category in pairs(categories) do
        for _ = 1, 10 do
            local ok, result = pcall(function()
                return IndexRemote:InvokeServer("requestClaimReward", category)
            end)
            if not ok or not result then break end
            task.wait(0.1)
        end
    end
end

local function formatNumber(n)
    if type(n) ~= "number" then return "?" end
    if n >= 1e15 then return string.format("%.2fQ", n / 1e15)
    elseif n >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
    else return tostring(math.floor(n)) end
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

task.spawn(function()
    while true do
        if AutoRollEnabled then
            if AutoUseDiceEnabled then
                local armed = getData("armedSpecialDice") or {}
                if #armed == 0 then pcall(useAllSpecialDice) end
            end
            pcall(doRoll)
            task.wait(RollDelay)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if AutoRollEnabled then
            if InventoryRemote then
                pcall(function() InventoryRemote:InvokeServer("requestEquipBest") end)
            end
            if AutoClaimIndexEnabled and IndexRemote then
                for _, cat in pairs({"basic", "big", "huge", "shiny", "inverted"}) do
                    local ok, result = pcall(function()
                        return IndexRemote:InvokeServer("requestClaimReward", cat)
                    end)
                    if not ok or not result then break end
                    task.wait(0.1)
                end
            end
        end
        task.wait(10)
    end
end)

local AntiAFKEnabled = true
local AntiAFKInterval = 60
local lastAfkTick = 0

local VirtualUser = game:GetService("VirtualUser")

local function runAntiAFK()
    pcall(function()
        local UserInputService = game:GetService("UserInputService")
        if getconnections then
            local conns = getconnections(UserInputService.InputEnded)
            if conns and conns[1] then
                pcall(function() conns[1]:Fire() end)
            end
        end
    end)
end

LocalPlayer.Idled:Connect(function()
    if not AntiAFKEnabled then return end
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
    runAntiAFK()
end)

pcall(function() VirtualUser:CaptureController() end)

task.spawn(function()
    while true do
        if AntiAFKEnabled then
            local now = os.clock()
            if now - lastAfkTick >= AntiAFKInterval then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    task.wait(0.05)
                    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end)
                runAntiAFK()
                lastAfkTick = now
            end
        end
        task.wait(5)
    end
end)

task.spawn(function()
    pcall(function()
        local autoRejoinFolder = gameRemotes and gameRemotes:FindFirstChild("AutoRejoinService")
        if autoRejoinFolder then
            local remoteEvent = autoRejoinFolder:FindFirstChild("RemoteEvent")
            if remoteEvent and hookfunction then
                local oldFireServer
                oldFireServer = hookfunction(remoteEvent.FireServer, function(self, arg, ...)
                    if self == remoteEvent and arg == "autoRejoin" then
                        return
                    end
                    return oldFireServer(self, arg, ...)
                end)
            end
        end
    end)

    pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if method == "FireServer" and args[1] == "autoRejoin" then
                return
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
end)

-- Auto re-execute on teleport/rejoin
pcall(function()
    local url = "https://raw.githubusercontent.com/Zinvera/zinnyware/refs/heads/main/zinnywareob.lua"
    local code = game:HttpGet(url)
    if queue_on_teleport then
        queue_on_teleport(code)
    elseif syn and syn.queue_on_teleport then
        syn.queue_on_teleport(code)
    elseif fluxus and fluxus.queue_on_teleport then
        fluxus.queue_on_teleport(code)
    elseif getgenv and getgenv().queue_on_teleport then
        getgenv().queue_on_teleport(code)
    end
end)

task.spawn(function()
    while true do
        if AutoBuyZoneEnabled then
            local ok, bought = pcall(tryBuyZone)
            if ok and bought and AutoTeleportEnabled then
                task.wait(0.5)
                pcall(teleportToMaxZone)
            end
        end
        task.wait(ZoneCheckInterval)
    end
end)

task.spawn(function()
    while true do
        if AutoRebirthEnabled then pcall(tryRebirth) end
        task.wait(RebirthCheckInterval)
    end
end)

task.spawn(function()
    local lastMaxZone = getMaxZone()
    local initialized = false
    while true do
        if AutoTeleportEnabled then
            local ok, currentMax = pcall(getMaxZone)
            if ok and currentMax then
                if not initialized then
                    lastMaxZone = currentMax
                    initialized = true
                elseif currentMax > lastMaxZone then
                    lastMaxZone = currentMax
                    task.wait(0.5)
                    pcall(teleportToMaxZone)
                end
            end
        end
        task.wait(2)
    end
end)

task.spawn(function()
    while true do
        if AutoCollectLootEnabled then pcall(collectAllLoot) end
        task.wait(LootCollectInterval)
    end
end)

task.spawn(function()
    while true do
        if AutoUsePotionsEnabled then pcall(consumeAllPotions) end
        task.wait(PotionCheckInterval)
    end
end)

local SlimeTheme = {
    TextColor = Color3.fromRGB(230, 255, 230),
    Background = Color3.fromRGB(15, 20, 15),
    Topbar = Color3.fromRGB(20, 30, 20),
    Shadow = Color3.fromRGB(10, 15, 10),
    NotificationBackground = Color3.fromRGB(15, 22, 15),
    NotificationActionsBackground = Color3.fromRGB(200, 255, 200),
    TabBackground = Color3.fromRGB(30, 50, 30),
    TabStroke = Color3.fromRGB(40, 70, 40),
    TabBackgroundSelected = Color3.fromRGB(80, 200, 80),
    TabTextColor = Color3.fromRGB(180, 255, 180),
    SelectedTabTextColor = Color3.fromRGB(10, 20, 10),
    ElementBackground = Color3.fromRGB(20, 32, 20),
    ElementBackgroundHover = Color3.fromRGB(25, 40, 25),
    SecondaryElementBackground = Color3.fromRGB(15, 25, 15),
    ElementStroke = Color3.fromRGB(40, 70, 40),
    SecondaryElementStroke = Color3.fromRGB(30, 55, 30),
    SliderBackground = Color3.fromRGB(30, 80, 30),
    SliderProgress = Color3.fromRGB(50, 180, 50),
    SliderStroke = Color3.fromRGB(60, 200, 60),
    ToggleBackground = Color3.fromRGB(18, 28, 18),
    ToggleEnabled = Color3.fromRGB(50, 200, 50),
    ToggleDisabled = Color3.fromRGB(60, 80, 60),
    ToggleEnabledStroke = Color3.fromRGB(70, 230, 70),
    ToggleDisabledStroke = Color3.fromRGB(80, 100, 80),
    ToggleEnabledOuterStroke = Color3.fromRGB(40, 100, 40),
    ToggleDisabledOuterStroke = Color3.fromRGB(35, 55, 35),
    DropdownSelected = Color3.fromRGB(25, 45, 25),
    DropdownUnselected = Color3.fromRGB(18, 30, 18),
    InputBackground = Color3.fromRGB(18, 28, 18),
    InputStroke = Color3.fromRGB(40, 70, 40),
    PlaceholderColor = Color3.fromRGB(120, 170, 120)
}

local Window = Rayfield:CreateWindow({
    Name = "Zinnyware v2.3",
    Icon = "zap",
    LoadingTitle = "Zinnyware",
    LoadingSubtitle = "Connecting...",
    Theme = SlimeTheme,
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "SlimeAutoFarm",
        FileName = "SlimeConfig"
    }
})

local FarmTab = Window:CreateTab("Auto Farm", "bot")

FarmTab:CreateSection("Rolling")

FarmTab:CreateParagraph({
    Title = "Auto Roll",
    Content = "Rolls directly via server remote, skipping all animations. Auto-equips best slimes every 10 rolls. Sub-toggles: auto-use special dice, auto-claim index rewards every 20 rolls."
})

FarmTab:CreateToggle({
    Name = "Auto Roll",
    CurrentValue = false,
    Flag = "AutoRoll",
    Callback = function(Value) AutoRollEnabled = Value end
})

FarmTab:CreateSlider({
    Name = "Roll Speed",
    Range = {0, 200},
    Increment = 5,
    Suffix = "ms",
    CurrentValue = 100,
    Flag = "RollDelay",
    Callback = function(Value) RollDelay = Value / 1000 end
})

FarmTab:CreateToggle({
    Name = "Auto Use Special Dice",
    CurrentValue = false,
    Flag = "AutoUseDice",
    Callback = function(Value) AutoUseDiceEnabled = Value end
})

FarmTab:CreateToggle({
    Name = "Auto Claim Index Rewards",
    CurrentValue = false,
    Flag = "AutoClaimIndex",
    Callback = function(Value) AutoClaimIndexEnabled = Value end
})

FarmTab:CreateSection("Loot")

FarmTab:CreateToggle({
    Name = "Auto Collect All Loot",
    CurrentValue = false,
    Flag = "AutoCollectLoot",
    Callback = function(Value) AutoCollectLootEnabled = Value end
})

FarmTab:CreateSlider({
    Name = "Loot Collect Interval",
    Range = {500, 5000},
    Increment = 100,
    Suffix = "ms",
    CurrentValue = 1000,
    Flag = "LootInterval",
    Callback = function(Value) LootCollectInterval = Value / 1000 end
})

FarmTab:CreateButton({
    Name = "Collect All Loot Now",
    Callback = function()
        local count = collectAllLoot()
        Rayfield:Notify({ Title = "Loot Collected", Content = "Picked up " .. count .. " items.", Duration = 3, Image = "package" })
    end
})

FarmTab:CreateSection("Potions")

FarmTab:CreateToggle({
    Name = "Auto Consume All Potions",
    CurrentValue = false,
    Flag = "AutoUsePotions",
    Callback = function(Value) AutoUsePotionsEnabled = Value end
})

FarmTab:CreateButton({
    Name = "Use All Potions Now",
    Callback = function()
        consumeAllPotions()
        Rayfield:Notify({ Title = "Potions", Content = "Consumed all available potions.", Duration = 3, Image = "flask-round" })
    end
})

FarmTab:CreateSection("Zones")

FarmTab:CreateToggle({
    Name = "Auto Buy New Zone",
    CurrentValue = false,
    Flag = "AutoBuyZone",
    Callback = function(Value) AutoBuyZoneEnabled = Value end
})

FarmTab:CreateToggle({
    Name = "Auto Teleport to New Zone",
    CurrentValue = false,
    Flag = "AutoTeleport",
    Callback = function(Value) AutoTeleportEnabled = Value end
})

FarmTab:CreateButton({
    Name = "Teleport to Max Zone Now",
    Callback = function()
        local maxZone = getMaxZone()
        Rayfield:Notify({ Title = "Teleporting...", Content = "Going to zone " .. maxZone, Duration = 2, Image = "map-pin" })
        teleportToZone(maxZone)
    end
})

FarmTab:CreateSection("Rebirth")

FarmTab:CreateToggle({
    Name = "Auto Rebirth",
    CurrentValue = false,
    Flag = "AutoRebirth",
    Callback = function(Value) AutoRebirthEnabled = Value end
})

FarmTab:CreateSection("Anti-AFK")

FarmTab:CreateToggle({
    Name = "Anti-AFK (auto on)",
    CurrentValue = true,
    Flag = "AntiAFK",
    Callback = function(Value) AntiAFKEnabled = Value end
})

FarmTab:CreateSlider({
    Name = "Anti-AFK Interval",
    Range = {10, 120},
    Increment = 5,
    Suffix = "s",
    CurrentValue = 60,
    Flag = "AntiAFKInterval",
    Callback = function(Value) AntiAFKInterval = Value end
})

local UpgradeRemote = getRemote(gameRemotes, "UpgradeService")
local AutoUpgradeEnabled = false

local allUpgradeIds = {
    "backpack", "autoRoll",
    "rollSpeed1", "rollSpeed2", "rollSpeed3", "rollSpeed4", "rollSpeed5", "rollSpeed6",
    "extraRollChance1", "extraRollChance2", "extraRollChance3",
    "cloverRolls1", "cloverRolls2", "cloverRolls3", "cloverRolls4", "cloverRolls5",
    "bonusRolls1", "bonusRolls2", "bonusRolls3",
    "lootTree", "playerTree",
    "slots2", "slots3", "slots4", "slots5", "slots6",
    "slimeTargetRange1", "slimeTargetRange2", "slimeTargetRange3",
    "bigSlimes", "hugeSlimes", "shinySlimes", "invertedSlimes",
    "enemyCount2", "enemyCount3", "enemyCount4", "enemyCount5", "enemyCount6", "enemyCount7",
    "goop", "goopDropRate1", "goopDropRate2", "goopDropRate3", "goopDropRate4", "goopDropRate5", "goopDropRate6",
    "bigEnemies", "bigEnemyChance1", "shinyEnemies", "shinyEnemyChance1",
    "hugeEnemies", "hugeEnemyChance1", "invertedEnemies", "invertedEnemyChance1",
    "enemySpawnSpeed1", "enemySpawnSpeed2", "enemySpawnSpeed3",
    "goldenRolls", "goldenRolls2", "goldenRolls3", "goldenRolls4",
    "diamondRolls", "diamondRolls2", "diamondRolls3", "diamondRolls4",
    "voidRolls", "voidRolls2", "voidRolls3", "voidRolls4",
    "luck1", "luck2", "luck3", "luck4", "luck5", "luck6", "luck7", "luck8",
    "luck9", "luck10", "luck11", "luck12", "luck13", "luck14", "luck15",
    "friendLuck1", "friendLuck2", "friendLuck3", "friendLuck4", "friendLuck5", "friendLuck6",
    "friendLuckBoost1", "friendLuckBoost2", "friendLuckBoost3", "friendLuckBoost4",
    "coinIncome1", "coinIncome2", "coinIncome3", "coinIncome4", "coinIncome5",
    "coinIncome6", "coinIncome7", "coinIncome8", "coinIncome9", "coinIncome10",
    "coinIncome11", "coinIncome12", "coinIncome13",
    "overkill1", "overkill2", "overkill3", "overkill4", "overkill5", "overkill6",
    "offlineLootAmount1", "offlineLootAmount2", "offlineLootAmount3", "offlineLootAmount4", "offlineLootAmount5",
    "lootApple", "lootCarrot", "lootCherries", "lootGrapes", "lootBanana",
    "lootWatermelon", "lootPizza", "lootChicken", "lootDrumstick",
    "lootLuck", "lootCurrency", "lootRollSpeed", "lootUltraLuck",
    "walkSpeed1", "walkSpeed2", "walkSpeed3",
    "teleporter",
    "magnet1", "magnet2", "magnet3",
}

local function buyAllAffordable()
    if not UpgradeRemote then return 0 end
    local bought = 0
    local boughtThisPass = true
    while boughtThisPass do
        boughtThisPass = false
        for _, id in pairs(allUpgradeIds) do
            local ok, result = pcall(function()
                return UpgradeRemote:InvokeServer("requestUnlock", id)
            end)
            if ok and result and result ~= false then
                bought = bought + 1
                boughtThisPass = true
                task.wait(0.05)
            end
        end
    end
    return bought
end

local UpgradesTab = Window:CreateTab("Upgrades", "trending-up")
UpgradesTab:CreateSection("Skill Tree")

UpgradesTab:CreateParagraph({
    Title = "Auto Upgrade",
    Content = "Reads ALL upgrades from the game's skill tree and buys everything you can afford. No fixed list — if the game adds new upgrades, they get bought too."
})

UpgradesTab:CreateToggle({
    Name = "Auto Buy Upgrades",
    CurrentValue = false,
    Flag = "AutoUpgrade",
    Callback = function(Value) AutoUpgradeEnabled = Value end
})

UpgradesTab:CreateButton({
    Name = "Buy All Affordable Now",
    Callback = function()
        local count = buyAllAffordable()
        Rayfield:Notify({ Title = "Upgrades", Content = "Bought " .. count .. " upgrade(s).", Duration = 3, Image = "trending-up" })
    end
})

task.spawn(function()
    local backoff = 5
    while true do
        if AutoUpgradeEnabled then
            local ok, count = pcall(buyAllAffordable)
            if ok and count and count > 0 then
                backoff = 5
            else
                backoff = math.min(backoff + 5, 30)
            end
        else
            backoff = 5
        end
        task.wait(backoff)
    end
end)

local TeleportTab = Window:CreateTab("Teleport", "navigation")
TeleportTab:CreateSection("Quick Teleport")

local ZoneNames = {
    "1 - Grasslands", "2 - Desert", "3 - Polar", "4 - Volcano",
    "5 - Islands", "6 - Cave", "7 - Heaven", "8 - Jungle",
    "9 - Canyon", "10 - Mushroom Forest", "11 - Moon", "12 - Redwood Forest",
    "13 - Meteor", "14 - Candyland", "15 - Cherry Grove", "16 - Crystal Cavern",
    "17 - Pumpkin Patch", "18 - Atlantis", "19 - River", "20 - Pyramids",
    "21 - Graveyard", "22 - Hot Springs", "23 - Tribe", "24 - Toxic Wasteland",
    "25 - Steampunk", "26 - Winter Wonderland", "27 - Farm", "28 - Jungle Temple"
}

local selectedTeleportZone = 1

TeleportTab:CreateDropdown({
    Name = "Select Zone",
    Options = ZoneNames,
    CurrentOption = {"1 - Grasslands"},
    MultipleOptions = false,
    Flag = "TeleportZone",
    Callback = function(Options)
        local selected = Options[1]
        if not selected then return end
        local zoneNum = tonumber(selected:match("^(%d+)"))
        if zoneNum then selectedTeleportZone = zoneNum end
    end
})

TeleportTab:CreateButton({
    Name = "Teleport to Selected Zone",
    Callback = function()
        local maxZone = getMaxZone()
        if selectedTeleportZone > maxZone then
            Rayfield:Notify({ Title = "Zone Locked", Content = "Zone " .. selectedTeleportZone .. " not unlocked. (Max: " .. maxZone .. ")", Duration = 4, Image = "lock" })
            return
        end
        local success = teleportToZone(selectedTeleportZone)
        Rayfield:Notify({ Title = success and "Teleported" or "Failed", Content = success and ("Moved to zone " .. selectedTeleportZone) or "Server rejected.", Duration = 3, Image = "map-pin" })
    end
})

local StatsTab = Window:CreateTab("Stats", "bar-chart-2")
StatsTab:CreateSection("Player Data")

local StatsInfo = StatsTab:CreateParagraph({ Title = "Player Stats", Content = "Press Refresh to load." })

StatsTab:CreateButton({
    Name = "Refresh Stats",
    Callback = function()
        local coins = getDataFresh("coins") or 0
        local goop = getDataFresh("goop") or 0
        local rebirths = getDataFresh("rebirths") or 0
        local maxZone = getDataFresh("maxZone") or 1
        local furthestZone = getDataFresh("furthestZone") or 1
        local unlockedZones = math.max(maxZone, furthestZone)
        local currentZone = getDataFresh("zone") or 1
        local rebirthCost = 2 ^ rebirths * 500

        local text = "Coins: " .. formatNumber(coins) .. "\n"
        text = text .. "Goop: " .. formatNumber(goop) .. "\n"
        text = text .. "Rebirths: " .. rebirths .. " (next: " .. formatNumber(rebirthCost) .. " goop)\n"
        text = text .. "Zone: " .. currentZone .. " (unlocked: " .. unlockedZones .. "/28)\n"
        text = text .. "Luck Multi: " .. string.format("%.1fx", 1.82 ^ rebirths)
        StatsInfo:Set({ Title = "Player Stats", Content = text })
    end
})

StatsTab:CreateSection("Session")
local SessionInfo = StatsTab:CreateParagraph({ Title = "Session Stats", Content = "Rolls: 0 | Rebirths: 0 | Zones: 0 | Uptime: 0s" })

task.spawn(function()
    while true do
        task.wait(5)
        pcall(function()
            SessionInfo:Set({
                Title = "Session Stats",
                Content = "Rolls: " .. formatNumber(TotalRolls) .. " | Rebirths: " .. TotalRebirths .. " | Zones: " .. TotalZonesBought .. " | Uptime: " .. formatTime(os.clock() - SessionStart)
            })
        end)
    end
end)

local CraftingTab = Window:CreateTab("Crafting", "hammer")
CraftingTab:CreateSection("Recipes")

local CraftingRemote = getRemote(gameRemotes, "CraftingService")

CraftingTab:CreateButton({
    Name = "Auto Collect All Recipes",
    Callback = function()
        if not CraftingRemote then
            Rayfield:Notify({ Title = "Error", Content = "CraftingService remote not found.", Duration = 3, Image = "x" })
            return
        end

        -- Recipe zones: tp to zone -> find tagged "Recipe" part -> claim within 10 studs
        local recipeZones = {
            {zone = 6, key = "crafty"},
            {zone = 8, key = "thorn"},
            {zone = 10, key = "geode"},
            {zone = 12, key = "slimeSlimeSlime"},
            {zone = 14, key = "puffy"},
            {zone = 16, key = "astro"},
            {zone = 18, key = "sunny"},
            {zone = 21, key = "melly"}
        }

        Rayfield:Notify({ Title = "Collecting Recipes", Content = "Teleporting to each zone to find recipes...", Duration = 5, Image = "hammer" })

        task.spawn(function()
            local CollectionService = game:GetService("CollectionService")
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                Rayfield:Notify({ Title = "Error", Content = "No character found.", Duration = 3, Image = "x" })
                return
            end

            local originalCFrame = hrp.CFrame
            local collected = 0
            local maxZone = getMaxZone()

            for _, info in pairs(recipeZones) do
                if info.zone <= maxZone then

                teleportToZone(info.zone)
                task.wait(2)

                local recipes = CollectionService:GetTagged("Recipe")
                for _, instance in pairs(recipes) do
                    local recipeKey = instance:GetAttribute("key")
                    if recipeKey == info.key then
                        local targetPos
                        if instance:IsA("BasePart") then
                            targetPos = instance.Position
                        elseif instance:IsA("Model") then
                            targetPos = instance:GetPivot().Position
                        end

                        if targetPos then
                            hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 2, 0))
                            task.wait(0.5)
                            local ok = pcall(function()
                                return CraftingRemote:InvokeServer("requestClaimRecipe", recipeKey, instance)
                            end)
                            if ok then collected = collected + 1 end
                        end
                        break
                    end
                end
                task.wait(0.5)

                end
            end

            hrp.CFrame = originalCFrame

            Rayfield:Notify({ Title = "Done", Content = "Collected " .. collected .. " recipe(s).", Duration = 4, Image = "check" })
        end)
    end
})

CraftingTab:CreateParagraph({
    Title = "Info",
    Content = "Teleports to each recipe scroll in the world and claims it. You need the crafting machine unlocked and the zone unlocked for each recipe to work."
})

local DebugTab = Window:CreateTab("Debug", "bug")
DebugTab:CreateSection("Remote Testing")

DebugTab:CreateButton({ Name = "Test Roll", Callback = function()
    local r = doRoll()
    Rayfield:Notify({ Title = r and "Roll OK" or "Roll Failed", Content = r and "Accepted." or "Rejected.", Duration = 3, Image = r and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Test Buy Zone", Callback = function()
    local r = tryBuyZone()
    Rayfield:Notify({ Title = r and "Zone Bought" or "Buy Failed", Content = r and ("Zone " .. getMaxZone()) or "Not enough coins.", Duration = 3, Image = r and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Test Rebirth", Callback = function()
    local r = tryRebirth()
    Rayfield:Notify({ Title = r and "Rebirth OK" or "Rebirth Failed", Content = r and ("Rebirths: " .. getPlayerRebirths()) or "Not enough goop.", Duration = 3, Image = r and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Test Data Fetch", Callback = function()
    local coins = getData("coins")
    local maxZone = getData("maxZone")
    local msg = "coins=" .. tostring(coins) .. " maxZone=" .. tostring(maxZone)
    Rayfield:Notify({ Title = (coins ~= nil) and "Data OK" or "Data NIL", Content = msg, Duration = 5, Image = (coins ~= nil) and "check" or "x" })
end })

DebugTab:CreateDivider()
DebugTab:CreateSection("Special Dice")

DebugTab:CreateButton({ Name = "Use Inverted Dice", Callback = function()
    local ok = useSpecialDice("invertedDice")
    Rayfield:Notify({ Title = ok and "Armed" or "Failed", Content = ok and "Inverted Dice armed." or "None available.", Duration = 3, Image = ok and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Use Huge Dice", Callback = function()
    local ok = useSpecialDice("hugeDice")
    Rayfield:Notify({ Title = ok and "Armed" or "Failed", Content = ok and "Huge Dice armed." or "None available.", Duration = 3, Image = ok and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Use Shiny Dice", Callback = function()
    local ok = useSpecialDice("shinyDice")
    Rayfield:Notify({ Title = ok and "Armed" or "Failed", Content = ok and "Shiny Dice armed." or "None available.", Duration = 3, Image = ok and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Use Big Dice", Callback = function()
    local ok = useSpecialDice("bigDice")
    Rayfield:Notify({ Title = ok and "Armed" or "Failed", Content = ok and "Big Dice armed." or "None available.", Duration = 3, Image = ok and "check" or "x" })
end })

DebugTab:CreateButton({ Name = "Use ALL Dice", Callback = function()
    useAllSpecialDice()
    Rayfield:Notify({ Title = "Done", Content = "Armed all available dice.", Duration = 3, Image = "check" })
end })

DebugTab:CreateButton({ Name = "Collect All Loot", Callback = function()
    local count = collectAllLoot()
    Rayfield:Notify({ Title = "Collected", Content = count .. " items.", Duration = 3, Image = "package" })
end })

DebugTab:CreateDivider()
DebugTab:CreateSection("Zone Tour")

DebugTab:CreateButton({ Name = "Start Zone Tour (3s each)", Callback = function()
    if DebugRunning then
        Rayfield:Notify({ Title = "Busy", Content = "Tour already running.", Duration = 2, Image = "alert-triangle" })
        return
    end
    DebugRunning = true
    local maxZone = getData("maxZone") or 1
    if maxZone <= 1 then
        local furthest = getData("furthestZone")
        if furthest and furthest > maxZone then maxZone = furthest end
    end
    Rayfield:Notify({ Title = "Zone Tour", Content = "Visiting zones 1-" .. maxZone, Duration = 4, Image = "navigation" })
    task.spawn(function()
        for i = 1, maxZone do
            if not DebugRunning then break end
            teleportToZone(i)
            if i < maxZone then task.wait(3) end
        end
        DebugRunning = false
        Rayfield:Notify({ Title = "Tour Done", Content = "Finished.", Duration = 3, Image = "check" })
    end)
end })

DebugTab:CreateButton({ Name = "Stop Tour", Callback = function()
    DebugRunning = false
    Rayfield:Notify({ Title = "Stopped", Content = "Tour cancelled.", Duration = 2, Image = "square" })
end })

DebugTab:CreateDivider()
DebugTab:CreateSection("Diagnostics")

DebugTab:CreateButton({ Name = "Full Diagnostic (F9)", Callback = function()
    print("\n====== ZINNYWARE DIAGNOSTIC ======")
    print("Game remotes: " .. (gameRemotes and gameRemotes:GetFullName() or "NOT FOUND"))
    print("Data remotes: " .. (dataRemotes and dataRemotes:GetFullName() or "NOT FOUND"))
    print("")
    print("RollService: " .. (RollRemote and "OK" or "MISSING"))
    print("ZonesService: " .. (ZonesRemote and "OK" or "MISSING"))
    print("RebirthService: " .. (RebirthRemote and "OK" or "MISSING"))
    print("InventoryService: " .. (InventoryRemote and "OK" or "MISSING"))
    print("LootService: " .. (LootRemote and "OK" or "MISSING"))
    print("BoostService: " .. (BoostRemote and "OK" or "MISSING"))
    print("DataService: " .. (DataRemote and "OK" or "MISSING"))
    print("")
    for _, key in pairs({"coins", "goop", "rebirths", "zone", "maxZone", "furthestZone"}) do
        print("  " .. key .. " = " .. tostring(getData(key)))
    end
    print("====== END ======\n")
    Rayfield:Notify({ Title = "Diagnostic", Content = "Check console (F9).", Duration = 3, Image = "clipboard" })
end })

local statusParts = {}
if RollRemote then table.insert(statusParts, "Roll") end
if ZonesRemote then table.insert(statusParts, "Zones") end
if RebirthRemote then table.insert(statusParts, "Rebirth") end
if InventoryRemote then table.insert(statusParts, "Inv") end
if LootRemote then table.insert(statusParts, "Loot") end
if BoostRemote then table.insert(statusParts, "Boost") end
if IndexRemote then table.insert(statusParts, "Index") end

Rayfield:Notify({
    Title = "Zinnyware v2.3",
    Content = table.concat(statusParts, "/") .. " | Data: " .. (DataRemote and "OK" or "NIL") .. " | K to toggle",
    Duration = 6,
    Image = "check-circle"
})

Rayfield:LoadConfiguration()
