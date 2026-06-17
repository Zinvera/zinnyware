local scriptId = ({
    [92416421522960] = "927a206afa4b04d92f39d88217a5ec7a",
    [79268393072444] = "e9435abc5a27def136274b5ef0949e32",
    [81272814168643] = "e9860b215866c2a1e61911546520a774",
    [97598239454123] = "2f33339f69a2d7122b59e3e7129dd81f",
    [133438856880402] = "2f33339f69a2d7122b59e3e7129dd81f",
})[game.PlaceId]

if not scriptId and game.GameId == 6170143659 then
    scriptId = "32824326ba720c7f913e24a23fa306aa"
end

if not scriptId then
    return game:GetService("Players").LocalPlayer:Kick("This game is not supported by Zinnyware!")
end

loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/" .. scriptId .. ".lua"))()
