repeat
	task.wait()
until game:IsLoaded()

local Hub = "Zinnyware"
local Hub_Script_ID = "a8952aa33fe3b395dbf1e68ff05eda16"
local Discord_Invite = "9bMH9d7wTU"
local UI_Theme = "Dark"

local Workink_Enabled = true
local Workink = "https://ads.luarmor.net/get_key?for=Zinnyware-zggJvNsvAYzD"


local PlaceIDs = {
    ["92416421522960"] = "927a206afa4b04d92f39d88217a5ec7a",
    ["79268393072444"] = "e9435abc5a27def136274b5ef0949e32",
    ["81272814168643"] = "e9860b215866c2a1e61911546520a774",
    ["97598239454123"] = "2f33339f69a2d7122b59e3e7129dd81f",
    ["133438856880402"] = "2f33339f69a2d7122b59e3e7129dd81f",
}

local scriptId = PlaceIDs[tostring(game.PlaceId)]

if not scriptId and game.GameId == 6170143659 then
    scriptId = "32824326ba720c7f913e24a23fa306aa"
end

makefolder(Hub)
local key_path = Hub .. "/Key.txt"
script_key = script_key or isfile(key_path) and readfile(key_path) or nil

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()
local API = loadstring(game:HttpGet("https://sdkAPI-public.luarmor.net/library.lua"))()
local Cloneref = cloneref or function(instance)
	return instance
end
local Players = Cloneref(game:GetService("Players"))
local HttpService = Cloneref(game:GetService("HttpService"))
local AssetService = Cloneref(game:GetService("AssetService"))
local Request = http_request or request or (syn and syn.request) or http
local GamePlacesPages = AssetService:GetGamePlacesAsync()
local Pages = GamePlacesPages:GetCurrentPage()

local resolved = scriptId or Hub_Script_ID
local found = scriptId ~= nil
while not found do
	for _, place in ipairs(Pages) do
		local mapped = PlaceIDs[tostring(place.PlaceId)]
		if mapped then
			resolved = mapped
			found = true
			break
		end
	end
	if found or GamePlacesPages.IsFinished then
		break
	end
	GamePlacesPages:AdvanceToNextPageAsync()
	Pages = GamePlacesPages:GetCurrentPage()
end
API.script_id = resolved

local function notify(title, content, duration)
	Library:Notify({ Title = title, Description = content, Time = duration or 8 })
end

local function checkKey(input_key)
	local status = API.check_key(input_key or script_key)
	if status.code == "KEY_VALID" then
		script_key = input_key or script_key
		writefile(key_path, script_key)
		Library:Unload()
		API.load_script()
	elseif status.code:find("KEY_") then
		local messages = {
			KEY_HWID_LOCKED = "Key linked to a different HWID. Please reset it using our bot",
			KEY_INCORRECT = "Key is incorrect",
			KEY_INVALID = "Key is invalid",
		}
		notify("Key Check Failed", messages[status.code] or "Unknown error")
	else
		Players.LocalPlayer:Kick("Key check failed: " .. status.message .. " Code: " .. status.code)
	end
end

if script_key then
	checkKey()
end

local Window = Library:CreateWindow({
	Title = "Zinnyware v1.0",
	Footer = "Loader",
	Center = true,
	AutoShow = true,
	Size = UDim2.fromOffset(660, 420),
	ToggleKeybind = Enum.KeyCode.End,
})

local Tabs = { Main = Window:AddTab("Key", "key") }

local KeyBox = Tabs.Main:AddLeftGroupbox("Key System", "key-round")

local Input = KeyBox:AddInput("KeyInput", {
	Text = "Enter Key:",
	Default = script_key or "",
	Placeholder = "Example: agKhRikQP..",
	Numeric = false,
	Finished = false,
})

if Workink_Enabled then
	KeyBox:AddButton({
		Text = "Get Key (Work.ink)",
		Func = function()
			setclipboard(Workink)
			notify("Copied To Clipboard", "Ad Reward Link has been copied to your clipboard", 16)
		end,
	})
end

KeyBox:AddButton({
	Text = "Check Key",
	Func = function()
		checkKey(Input.Value)
	end,
})

KeyBox:AddButton({
	Text = "Permanent Key",
	Func = function()
		setclipboard("https://discord.gg/" .. Discord_Invite)
		notify("Copied To Clipboard", "discord.gg/" .. Discord_Invite, 16)
		Request({
			Url = "http://127.0.0.1:6463/rpc?v=1",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["origin"] = "https://discord.com" },
			Body = HttpService:JSONEncode({ args = { code = Discord_Invite }, cmd = "INVITE_BROWSER", nonce = "." }),
		})
	end,
})

KeyBox:AddButton({
	Text = "Join Discord",
	Func = function()
		setclipboard("https://discord.gg/" .. Discord_Invite)
		notify("Copied To Clipboard", "discord.gg/" .. Discord_Invite, 16)
		Request({
			Url = "http://127.0.0.1:6463/rpc?v=1",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["origin"] = "https://discord.com" },
			Body = HttpService:JSONEncode({ args = { code = Discord_Invite }, cmd = "INVITE_BROWSER", nonce = "." }),
		})
	end,
})

notify(Hub, "Loader Has Loaded Successfully")
