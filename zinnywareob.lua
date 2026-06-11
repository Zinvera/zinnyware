local scriptId = ({
    [92416421522960] = "31902265834266433589",
    [79268393072444] = "60093404824722724300",
    [84332574190497] = "73925828768522463007",
    [81272814168643] = "91116184787292144860",
})[game.PlaceId]

if not scriptId and game.GameId == 6170143659 then
    scriptId = "19504575357719348339"
end

if not scriptId then
    return game:GetService("Players").LocalPlayer:Kick("This game is not supported by Zinnyware!")
end

if lp_key and lp_key ~= "" then
    loadstring(game:HttpGet("https://luaprot.net/api/v2/loaders/get/" .. scriptId))()
    return
end

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local KEY_FILE = "ZinnywareLemon/lp_key.txt"

local function getSavedKey()
    local ok, content = pcall(function()
        return readfile(KEY_FILE)
    end)
    if ok and content then return content:match("^%s*(.-)%s*$") end
    return nil
end

local function saveKey(key) 
    pcall(function()
        makefolder("ZinnywareLemon")
    end)
    pcall(function()
        writefile(KEY_FILE, key)
    end)
end

local Window = Library:CreateWindow({
    Title            = "Zinnyware Loader",
    Footer           = "discord.gg/JW2pNczusb",
    NotifySide       = "Right",
    ShowCustomCursor = true,
    AutoShow         = true,
    Center           = true,
})

local KeyTab = Window:AddKeyTab("Key System", "key")
KeyTab:AddLabel("Get your key below or join Discord:")
KeyTab:AddButton("Copy Key Link", function()
    pcall(function() setclipboard("https://luaprot.net/ad/a0fb0da9") end)
    Library:Notify("Copied: https://luaprot.net/ad/a0fb0da9", 3)
end)
KeyTab:AddButton("Copy Discord Invite", function()
    pcall(function() setclipboard("https://discord.gg/JW2pNczusb") end)
    Library:Notify("Discord invite copied!", 3)
end)

local luaprotSdk = nil
pcall(function()
    luaprotSdk = loadstring(game:HttpGet("https://sdk.luaprot.net/"))()
    luaprotSdk.scriptId = scriptId
end)

local function isKeyValid(key)
    if not luaprotSdk then return false end
    local ok, result = pcall(function()
        return luaprotSdk:checkKey(key)
    end)
    if ok and result and result.status == "VALID" then
        return true, result.data
    end
    return false
end

local function loadMainScript(key)
    lp_key = key
    Library:Unload()
    loadstring(game:HttpGet("https://luaprot.net/api/v2/loaders/get/" .. scriptId))()
end

local savedKey = getSavedKey()
if savedKey and savedKey ~= "" then
    local valid = isKeyValid(savedKey)
    if valid then
        loadMainScript(savedKey)
        return
    end
end

local keyAccepted = false
KeyTab:AddKeyBox(function(enteredKey)
    local valid = isKeyValid(enteredKey)
    if valid then
        saveKey(enteredKey)
        keyAccepted = true
        Library:Notify("Key accepted! Loading...", 3)
        task.delay(0.5, function()
            loadMainScript(enteredKey)
        end)
        return true
    else
        Library:Notify("Invalid or expired key.", 4)
        return false
    end
end)
