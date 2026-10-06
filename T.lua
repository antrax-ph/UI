-- ============================================================
-- Break and Steal an Egg - ATX
-- WindUI · no key system · auto break + auto steal fixed
-- ============================================================

print("[ATX BSE] Script started")
print("AntraxdevZ | Telegram: @AntraxdevZ")

-- ============================================================
-- SERVICES
-- ============================================================
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local UIS         = game:GetService("UserInputService")
local Run         = game:GetService("RunService")
local Teleport    = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui  = game:GetService("StarterGui")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local CREDIT = "AntraxdevZ · Telegram: @AntraxdevZ"

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    -- Egg Farm
    AutoEggBreak         = false,
    AutoEggTeleport      = true,
    EggFireCooldown      = 0.15,
    EggSearchRange       = 5000,
    EggRescanInterval    = 2,
    PickaxeTier          = 1,

    -- Auto Steal
    AutoSteal            = false,
    StealRange           = 5000,
    StealCooldown        = 0.3,
    StealOnlyEnemy       = true,
    StealRescanInterval  = 3,

    -- Base / Place
    BasePosition         = nil,
    AutoPlace            = false,
    AutoPlaceInterval    = 1.5,
    PlaceSpreadRadius    = 12,
    PlacePriorityMode    = "Highest",

    -- Treadmill
    AutoTreadmill        = false,
    TreadmillInterval    = 1.0,

    -- Index
    AutoClaimIndex       = false,
    ClaimIndexInterval   = 30,

    -- Shops
    AutoBuyPickaxe       = false,
    AutoBuyTrail         = false,
    TrailId              = 1,

    -- Movement
    Fly                  = false,
    FlySpeed             = 60,
    Noclip               = false,
    SpeedToggle          = false,
    SpeedValue           = 60,

    -- ESP
    PlayerESP            = false,
    EggESP               = false,
    PlacedAnimalESP      = true,

    -- Misc
    AntiAFK              = true,
    AntiFling            = false,
    HUD                  = true,
    Notify               = true,

    DiscoveredRemotes    = {},
    DiscoverOn           = false,
}

-- ============================================================
-- HELPERS
-- ============================================================
local function getHRP(plr)
    plr = plr or LP
    local char = plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHum(plr)
    plr = plr or LP
    local char = plr.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local WindUI, Window
local function UI_Notify(text, kind)
    pcall(function()
        if WindUI then
            WindUI:Notify({ Title="ATX", Content=tostring(text), Duration=2.5,
                Icon = kind == "error" and "alert-circle" or "info" })
        else
            StarterGui:SetCore("SendNotification", { Title="ATX", Text=tostring(text), Duration=2.5 })
        end
    end)
    print("[ATX BSE] " .. tostring(text))
end

-- ============================================================
-- REMOTES
-- ============================================================
local Remotes = {
    IndexRemote            = nil,
    PlaceAnimalRemote      = nil,
    TreadmillSessionRemote = nil,
    EggHitRequest          = nil,
    TrailShopRequest       = nil,
    PickaxeShopRequest     = nil,
    UnlockTreadmillRequest = nil,
    SpeedGainRemote        = nil,
    AnimalBankedRemote     = nil,
    Notify                 = nil,
    EggHitConfirmed        = nil,
    AnimalPlacedVFXRemote  = nil,
}

task.spawn(function()
    local t = 0
    while t < 30 do
        for _, name in ipairs({
            "IndexRemote", "PlaceAnimalRemote", "TreadmillSessionRemote",
            "EggHitRequest", "TrailShopRequest", "PickaxeShopRequest",
            "UnlockTreadmillRequest", "SpeedGainRemote", "AnimalBankedRemote",
            "Notify", "EggHitConfirmed", "AnimalPlacedVFXRemote",
        }) do
            if not Remotes[name] then
                Remotes[name] = RS:FindFirstChild(name)
            end
        end
        if Remotes.EggHitRequest and Remotes.PlaceAnimalRemote and Remotes.Notify then break end
        task.wait(0.5)
        t = t + 0.5
    end
end)

-- ============================================================
-- STATE
-- ============================================================
local State = {
    Speed = 0,
    Cash = 0,
    Banked = {},
    IndexState = {},
    PlacedAnimals = {},  -- [id] = { pos, owner, time, mine }
    OwnedPickaxeTier = 1,
}

if Remotes.SpeedGainRemote then
    Remotes.SpeedGainRemote.OnClientEvent:Connect(function(gain, newTotal)
        if type(newTotal) == "number" then State.Speed = newTotal end
    end)
end

if Remotes.IndexRemote then
    Remotes.IndexRemote.OnClientEvent:Connect(function(action, data)
        if action == "State" and type(data) == "table" then
            State.IndexState = data
        end
    end)
end

if Remotes.AnimalBankedRemote then
    Remotes.AnimalBankedRemote.OnClientEvent:Connect(function(list)
        if type(list) ~= "table" then return end
        for _, entry in ipairs(list) do
            if type(entry) == "table" and entry.Name then
                State.Banked[entry.Name] = (State.Banked[entry.Name] or 0) + (entry.Count or 1)
            end
        end
    end)
end

if Remotes.PlaceAnimalRemote then
    Remotes.PlaceAnimalRemote.OnClientEvent:Connect(function(name, remaining)
        if type(name) == "string" and type(remaining) == "number" then
            State.Banked[name] = math.max(0, remaining)
        end
    end)
end

-- Track pickaxe tier from Notify text
if Remotes.Notify then
    Remotes.Notify.OnClientEvent:Connect(function(text, kind, opts)
        if type(text) ~= "string" then return end
        -- "Successfully equipped {Stone Pickaxe}!"
        local pick = text:match("{(.-) Pickaxe}")
        if pick then
            -- map known names to tiers
            local tierMap = {
                Wooden = 1, Stone = 2, Iron = 3, Gold = 4,
                Diamond = 5, Emerald = 6, Ruby = 7, Amethyst = 8,
            }
            if tierMap[pick] then
                State.OwnedPickaxeTier = tierMap[pick]
            end
        end
        -- cash parse
        local cash = text:match("%$(%d+)")
        if cash then State.Cash = tonumber(cash) or State.Cash end
    end)
end

if Remotes.AnimalPlacedVFXRemote then
    Remotes.AnimalPlacedVFXRemote.OnClientEvent:Connect(function(pos, plr, isMine)
        if typeof(pos) == "Vector3" then
            local id = string.format("%.1f_%.1f_%.1f", pos.X, pos.Y, pos.Z)
            State.PlacedAnimals[id] = {
                pos = pos,
                owner = plr,
                mine = isMine == true or plr == LP,
                time = tick(),
            }
        end
    end)
end

-- ============================================================
-- EGG DETECTION (broader)
-- ============================================================
local EggCache = { list = {}, lastScan = 0 }

-- Names that indicate a breakable object
local EGG_NAME_HINTS   = { "egg", "breakable", "crate", "rock", "ore", "node" }
local EGG_PARENT_HINTS = { "egg", "breakable", "resource", "spawn", "map" }
local EGG_PROMPT_HINTS = { "break", "hit", "mine", "tap", "smash", "crack" }

local function isInstanceEgg(inst)
    if not inst or not inst.Parent then return false end
    -- direct name match
    local n = (inst.Name or ""):lower()
    for _, h in ipairs(EGG_NAME_HINTS) do
        if n:find(h, 1, true) then return true end
    end
    -- attribute check
    local attrs = {"EggType", "IsEgg", "Breakable", "Health", "HitPoints", "HitsLeft"}
    for _, a in ipairs(attrs) do
        local ok, v = pcall(function() return inst:GetAttribute(a) end)
        if ok and v ~= nil then return true end
    end
    -- parent folder check
    local p = inst.Parent
    local depth = 0
    while p and depth < 4 do
        local pn = (p.Name or ""):lower()
        for _, h in ipairs(EGG_PARENT_HINTS) do
            if pn:find(h, 1, true) then return true end
        end
        p = p.Parent
        depth = depth + 1
    end
    -- prox prompt check
    local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local at = (prompt.ActionText or ""):lower()
        for _, h in ipairs(EGG_PROMPT_HINTS) do
            if at:find(h, 1, true) then return true end
        end
    end
    return false
end

local function getInstancePos(inst)
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
        if pp then return pp.Position end
    end
    local pp = inst:FindFirstChildWhichIsA("BasePart")
    return pp and pp.Position or nil
end

local function scanEggs(force)
    local now = tick()
    if not force and now - EggCache.lastScan < Config.EggRescanInterval then
        return EggCache.list
    end
    EggCache.lastScan = now
    local out = {}
    local seen = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Model") then
            if not d:IsDescendantOf(LP.Character) and isInstanceEgg(d) then
                local pos = getInstancePos(d)
                if pos then
                    -- dedupe: skip children if parent already tracked
                    local parentOk = true
                    local p = d.Parent
                    local depth = 0
                    while p and depth < 3 do
                        if seen[p] then parentOk = false break end
                        p = p.Parent
                        depth = depth + 1
                    end
                    if parentOk then
                        seen[d] = true
                        table.insert(out, { instance = d, pos = pos })
                    end
                end
            end
        end
    end
    EggCache.list = out
    return out
end

local function getNearestEgg(maxDist)
    local hrp = getHRP()
    if not hrp then return nil, math.huge end
    maxDist = maxDist or math.huge
    local best, bd = nil, maxDist
    for _, e in ipairs(scanEggs()) do
        local d = (e.pos - hrp.Position).Magnitude
        if d < bd then best, bd = e, d end
    end
    return best, bd
end

-- ============================================================
-- EGG FARM LOOP (fixed)
-- ============================================================
local lastEggFire = 0

local function tickEggFarm()
    if not Config.AutoEggBreak then return end
    if not Remotes.EggHitRequest then return end
    local now = tick()
    if now - lastEggFire < Config.EggFireCooldown then return end

    local egg, dist = getNearestEgg(Config.EggSearchRange)
    if not egg then return end

    -- Teleport near so server distance check passes
    if Config.AutoEggTeleport and dist > 8 then
        local hrp = getHRP()
        if hrp then
            -- offset so we don't clip inside
            local dir = flat(hrp.Position - egg.pos)
            if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
            dir = dir.Unit
            local dest = egg.pos + dir * 4 + Vector3.new(0, 3, 0)
            pcall(function() hrp.CFrame = CFrame.new(dest) end)
            return  -- wait one frame before firing
        end
    end

    lastEggFire = now
    local tier = math.max(1, State.OwnedPickaxeTier)
    pcall(function()
        Remotes.EggHitRequest:FireServer(egg.instance, tier)
    end)
end

-- ============================================================
-- AUTO STEAL (proximity prompt based)
-- ============================================================
local PromptCache = { all = {}, lastScan = 0 }

local STEAL_PROMPT_HINTS = { "steal", "take", "grab", "pickup", "pick up", "snatch", "loot" }

local function scanStealPrompts(force)
    local now = tick()
    if not force and now - PromptCache.lastScan < Config.StealRescanInterval then
        return PromptCache.all
    end
    PromptCache.lastScan = now
    local out = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local at = (d.ActionText or ""):lower()
            local ob = (d.ObjectText or ""):lower()
            local matched = false
            for _, h in ipairs(STEAL_PROMPT_HINTS) do
                if at:find(h, 1, true) or ob:find(h, 1, true) then matched = true break end
            end
            if matched then
                local parent = d.Parent
                local pos = getInstancePos(parent) or (parent and parent:FindFirstChildWhichIsA("BasePart") and parent:FindFirstChildWhichIsA("BasePart").Position)
                if pos then
                    table.insert(out, { prompt = d, parent = parent, pos = pos })
                end
            end
        end
    end
    PromptCache.all = out
    return out
end

local function firePrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if fireproximityprompt then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then return true end
    end
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration or 0, 0.05))
        prompt:InputHoldEnd()
    end)
    return true
end

local function getNearestStealPrompt(maxDist)
    local hrp = getHRP()
    if not hrp then return nil, math.huge end
    maxDist = maxDist or math.huge
    local best, bd = nil, maxDist
    for _, e in ipairs(scanStealPrompts()) do
        -- Optionally skip own animals by checking VFX records
        if Config.StealOnlyEnemy then
            local skip = false
            for _, p in pairs(State.PlacedAnimals) do
                if p.mine and (p.pos - e.pos).Magnitude < 8 then
                    skip = true break
                end
            end
            if skip then continue end
        end
        local d = (e.pos - hrp.Position).Magnitude
        if d < bd then best, bd = e, d end
    end
    return best, bd
end

local lastStealFire = 0

local function tickAutoSteal()
    if not Config.AutoSteal then return end
    local now = tick()
    if now - lastStealFire < Config.StealCooldown then return end

    local target, dist = getNearestStealPrompt(Config.StealRange)
    if not target then return end

    -- Teleport near prompt
    if dist > 6 then
        local hrp = getHRP()
        if hrp then
            local dir = flat(hrp.Position - target.pos)
            if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
            dir = dir.Unit
            local dest = target.pos + dir * 3 + Vector3.new(0, 3, 0)
            pcall(function() hrp.CFrame = CFrame.new(dest) end)
            return
        end
    end

    lastStealFire = now
    firePrompt(target.prompt)
end

-- Also: trigger steal prompts when an enemy animal is placed nearby (fallback path)
local lastVFXSteal = 0
local function tickVFXSteal()
    if not Config.AutoSteal then return end
    local now = tick()
    if now - lastVFXSteal < Config.StealCooldown * 2 then return end
    lastVFXSteal = now
    local hrp = getHRP()
    if not hrp then return end
    -- Find any nearby enemy placed animal
    for id, p in pairs(State.PlacedAnimals) do
        if not p.mine and (hrp.Position - p.pos).Magnitude < 40 then
            -- look for a prompt at that position
            for _, e in ipairs(scanStealPrompts()) do
                if (e.pos - p.pos).Magnitude < 6 then
                    firePrompt(e.prompt)
                    return
                end
            end
        end
    end
end

-- ============================================================
-- AUTO PLACE
-- ============================================================
local lastPlaceFire = 0
local function getBestBankedAnimal()
    local best, bestCount = nil, -1
    for name, count in pairs(State.Banked) do
        if count and count > 0 then
            if Config.PlacePriorityMode == "Highest" and count > bestCount then
                best, bestCount = name, count
            elseif Config.PlacePriorityMode == "Lowest" and (bestCount < 0 or count < bestCount) then
                best, bestCount = name, count
            elseif not best then
                best, bestCount = name, count
            end
        end
    end
    return best, bestCount
end

local function tickAutoPlace()
    if not Config.AutoPlace then return end
    if not Config.BasePosition then return end
    if not Remotes.PlaceAnimalRemote then return end
    local now = tick()
    if now - lastPlaceFire < Config.AutoPlaceInterval then return end

    local name, count = getBestBankedAnimal()
    if not name then return end
    lastPlaceFire = now

    local r = Config.PlaceSpreadRadius
    local offset = Vector3.new((math.random() - 0.5) * r, 0, (math.random() - 0.5) * r)
    local pos = Config.BasePosition + offset
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LP.Character and { LP.Character } or {}
    local hit = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -50, 0), params)
    if hit then pos = hit.Position + Vector3.new(0, 1.3, 0) end

    pcall(function() Remotes.PlaceAnimalRemote:FireServer(name, pos, count) end)
end

-- ============================================================
-- TREADMILL / INDEX / SHOPS
-- ============================================================
local lastTreadmill, lastClaimIndex, lastPickaxeBuy, lastTrailBuy = 0, 0, 0, 0

local function tickTreadmill()
    if not Config.AutoTreadmill then return end
    local now = tick()
    if now - lastTreadmill < Config.TreadmillInterval then return end
    lastTreadmill = now
    if Remotes.TreadmillSessionRemote then
        pcall(function() Remotes.TreadmillSessionRemote:FireServer() end)
    end
end

local function tickClaimIndex()
    if not Config.AutoClaimIndex then return end
    local now = tick()
    if now - lastClaimIndex < Config.ClaimIndexInterval then return end
    lastClaimIndex = now
    if Remotes.IndexRemote then
        pcall(function() Remotes.IndexRemote:FireServer("ClaimAll") end)
    end
end

local function tickShops()
    local now = tick()
    if Config.AutoBuyPickaxe and now - lastPickaxeBuy > 3 then
        lastPickaxeBuy = now
        if Remotes.PickaxeShopRequest then
            Remotes.PickaxeShopRequest:FireServer("Buy", State.OwnedPickaxeTier + 1)
        end
    end
    if Config.AutoBuyTrail and now - lastTrailBuy > 3 then
        lastTrailBuy = now
        if Remotes.TrailShopRequest then
            Remotes.TrailShopRequest:FireServer("Buy", Config.TrailId)
        end
    end
end

-- ============================================================
-- MAIN HEARTBEAT
-- ============================================================
Run.Heartbeat:Connect(function()
    pcall(tickEggFarm)
    pcall(tickAutoSteal)
    pcall(tickVFXSteal)
    pcall(tickAutoPlace)
    pcall(tickTreadmill)
    pcall(tickClaimIndex)
    pcall(tickShops)
end)

-- ============================================================
-- MOVEMENT
-- ============================================================
local flyConn
local function updateFly()
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if not Config.Fly then return end
    flyConn = Run.RenderStepped:Connect(function()
        local hrp = getHRP()
        if not hrp or not Camera then return end
        local move = Vector3.new()
        if UIS:IsKeyDown(Enum.KeyCode.W) then move += Camera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then move -= Camera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then move -= Camera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then move += Camera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end
        if move.Magnitude > 0 then move = move.Unit end
        hrp.AssemblyLinearVelocity = move * Config.FlySpeed
    end)
end

local noclipConn
local function updateNoclip()
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if not Config.Noclip then return end
    noclipConn = Run.Stepped:Connect(function()
        local char = LP.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end)
end

local speedConn, savedWalkSpeed = nil, nil
local function updateSpeed()
    if speedConn then speedConn:Disconnect() speedConn = nil end
    if not Config.SpeedToggle then
        local h = getHum()
        if h and savedWalkSpeed then h.WalkSpeed = savedWalkSpeed end
        savedWalkSpeed = nil
        return
    end
    local h = getHum()
    if h and not savedWalkSpeed then savedWalkSpeed = h.WalkSpeed end
    speedConn = Run.Heartbeat:Connect(function()
        local hum = getHum()
        if not hum or hum.Health <= 0 then return end
        if hum.WalkSpeed ~= Config.SpeedValue then
            pcall(function() hum.WalkSpeed = Config.SpeedValue end)
        end
    end)
end

local function onCharacterAdded(char)
    savedWalkSpeed = nil
    task.wait(1.5)
    local h = char:FindFirstChildOfClass("Humanoid")
    if h then savedWalkSpeed = h.WalkSpeed or 16 end
    if Config.SpeedToggle then savedWalkSpeed = nil; updateSpeed() end
    if Config.Fly then updateFly() end
    if Config.Noclip then updateNoclip() end
end

if LP.Character then task.spawn(onCharacterAdded, LP.Character) end
LP.CharacterAdded:Connect(onCharacterAdded)

-- ============================================================
-- ANTI FLING / AFK
-- ============================================================
local antiFlingConn
local function updateAntiFling()
    if antiFlingConn then antiFlingConn:Disconnect() antiFlingConn = nil end
    if not Config.AntiFling then return end
    antiFlingConn = Run.Heartbeat:Connect(function()
        local hrp = getHRP()
        if not hrp then return end
        local v = hrp.AssemblyLinearVelocity
        if v.Magnitude > 200 then hrp.AssemblyLinearVelocity = v.Unit * 60 end
    end)
end

local afkConn
local function updateAntiAFK()
    if afkConn then afkConn:Disconnect() afkConn = nil end
    if not Config.AntiAFK then return end
    afkConn = LP.Idled:Connect(function()
        local h = getHum()
        if not h or h.Health <= 0 then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

-- ============================================================
-- ESP
-- ============================================================
local playerESPs = {}
local function clearPlayerESP()
    for _, e in pairs(playerESPs) do
        if e.billboard then pcall(function() e.billboard:Destroy() end) end
        if e.highlight then pcall(function() e.highlight:Destroy() end) end
    end
    playerESPs = {}
end

local function refreshPlayerESP()
    if not Config.PlayerESP then
        if next(playerESPs) then clearPlayerESP() end
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do        if plr ~= LP then
            local hrp = getHRP(plr)
            local hum = getHum(plr)
            if hrp and hum and hum.Health > 0 then
                local e = playerESPs[plr]
                if not e or not e.part or not e.part.Parent then
                    local bb = Instance.new("BillboardGui")
                    bb.Adornee = hrp
                    bb.AlwaysOnTop = true
                    bb.Size = UDim2.new(0, 200, 0, 36)
                    bb.StudsOffset = Vector3.new(0, 3, 0)
                    bb.MaxDistance = 2000
                    bb.Parent = hrp
                    local lb = Instance.new("TextLabel")
                    lb.BackgroundTransparency = 1
                    lb.Size = UDim2.new(1, 0, 1, 0)
                    lb.Font = Enum.Font.GothamBold
                    lb.TextScaled = true
                    lb.TextStrokeTransparency = 0.3
                    lb.TextColor3 = Color3.fromRGB(255, 120, 120)
                    lb.Text = plr.Name
                    lb.Parent = bb
                    local hl = Instance.new("Highlight")
                    hl.Adornee = hrp
                    hl.FillColor = Color3.fromRGB(255, 120, 120)
                    hl.FillTransparency = 0.85
                    hl.OutlineColor = Color3.fromRGB(255, 160, 160)
                    hl.OutlineTransparency = 0
                    hl.Parent = hrp
                    playerESPs[plr] = { billboard = bb, highlight = hl, label = lb, part = hrp }
                end
            else
                local e = playerESPs[plr]
                if e then
                    if e.billboard then e.billboard:Destroy() end
                    if e.highlight then e.highlight:Destroy() end
                    playerESPs[plr] = nil
                end
            end
        end
    end
end

local eggESPs = {}
local function clearEggESP()
    for _, e in pairs(eggESPs) do
        if e.billboard then pcall(function() e.billboard:Destroy() end) end
        if e.highlight then pcall(function() e.highlight:Destroy() end) end
    end
    eggESPs = {}
end

local function refreshEggESP()
    if not Config.EggESP then
        if next(eggESPs) then clearEggESP() end
        return
    end
    local seen = {}
    for i, e in ipairs(scanEggs()) do
        local id = tostring(e.instance)
        seen[id] = true
        if not eggESPs[id] or not eggESPs[id].part or not eggESPs[id].part.Parent then
            if eggESPs[id] then
                if eggESPs[id].billboard then eggESPs[id].billboard:Destroy() end
                if eggESPs[id].highlight then eggESPs[id].highlight:Destroy() end
            end
            local part = e.instance:IsA("BasePart") and e.instance
                      or e.instance:FindFirstChildWhichIsA("BasePart")
            if part then
                local bb = Instance.new("BillboardGui")
                bb.Adornee = part
                bb.AlwaysOnTop = true
                bb.Size = UDim2.new(0, 160, 0, 30)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.MaxDistance = 3000
                bb.Parent = part
                local lb = Instance.new("TextLabel")
                lb.BackgroundTransparency = 1
                lb.Size = UDim2.new(1, 0, 1, 0)
                lb.Font = Enum.Font.GothamBold
                lb.TextScaled = true
                lb.TextStrokeTransparency = 0.3
                lb.TextColor3 = Color3.fromRGB(255, 220, 100)
                lb.Text = e.instance.Name
                lb.Parent = bb
                local hl = Instance.new("Highlight")
                hl.Adornee = part
                hl.FillColor = Color3.fromRGB(255, 220, 100)
                hl.FillTransparency = 0.75
                hl.OutlineColor = Color3.fromRGB(255, 240, 150)
                hl.OutlineTransparency = 0
                hl.Parent = part
                eggESPs[id] = { billboard = bb, highlight = hl, label = lb, part = part }
            end
        end
    end
    for id, e in pairs(eggESPs) do
        if not seen[id] then
            if e.billboard then e.billboard:Destroy() end
            if e.highlight then e.highlight:Destroy() end
            eggESPs[id] = nil
        end
    end
end

local placedESPs = {}
local function clearPlacedESP()
    for _, e in pairs(placedESPs) do
        if e.part then pcall(function() e.part:Destroy() end) end
    end
    placedESPs = {}
end

local function refreshPlacedESP()
    if not Config.PlacedAnimalESP then
        if next(placedESPs) then clearPlacedESP() end
        return
    end
    for id, p in pairs(State.PlacedAnimals) do
        if tick() - p.time > 120 then
            State.PlacedAnimals[id] = nil
        else
            if not placedESPs[id] then
                local part = Instance.new("Part")
                part.Name = "ATX_PlacedMarker"
                part.Size = Vector3.new(2, 4, 2)
                part.Position = p.pos + Vector3.new(0, 2, 0)
                part.Anchored = true
                part.CanCollide = false
                part.Transparency = 0.9
                part.Material = Enum.Material.Neon
                part.Color = p.mine and Color3.fromRGB(100, 255, 150) or Color3.fromRGB(255, 100, 100)
                part.Parent = workspace
                local bb = Instance.new("BillboardGui")
                bb.Adornee = part
                bb.AlwaysOnTop = true
                bb.Size = UDim2.new(0, 180, 0, 30)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.MaxDistance = 2000
                bb.Parent = part
                local lb = Instance.new("TextLabel")
                lb.BackgroundTransparency = 1
                lb.Size = UDim2.new(1, 0, 1, 0)
                lb.Font = Enum.Font.GothamBold
                lb.TextScaled = true
                lb.TextStrokeTransparency = 0.3
                lb.TextColor3 = part.Color
                lb.Text = p.mine and "YOURS" or (typeof(p.owner) == "Instance" and p.owner.Name or "ENEMY")
                lb.Parent = bb
                placedESPs[id] = { billboard = bb, label = lb, part = part }
            end
        end
    end
    for id, e in pairs(placedESPs) do
        if not State.PlacedAnimals[id] then
            if e.part then pcall(function() e.part:Destroy() end) end
            placedESPs[id] = nil
        end
    end
end

Run.Heartbeat:Connect(function()
    pcall(refreshPlayerESP)
    pcall(refreshEggESP)
    pcall(refreshPlacedESP)
end)

-- ============================================================
-- HUD
-- ============================================================
local hudGui, hudSpeedLbl, hudInfoLbl
local function buildHUD()
    if hudGui then pcall(function() hudGui:Destroy() end) hudGui = nil end
    if not Config.HUD then return end
    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "ATX_BSE_HUD"
    hudGui.ResetOnSpawn = false
    hudGui.DisplayOrder = 9999
    pcall(function()
        if gethui then hudGui.Parent = gethui()
        else hudGui.Parent = game:GetService("CoreGui") end
    end)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 96)
    frame.Position = UDim2.new(0, 12, 0, 12)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = hudGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    hudSpeedLbl = Instance.new("TextLabel")
    hudSpeedLbl.Size = UDim2.new(1, -12, 0, 20)
    hudSpeedLbl.Position = UDim2.new(0, 6, 0, 4)
    hudSpeedLbl.BackgroundTransparency = 1
    hudSpeedLbl.Font = Enum.Font.GothamBold
    hudSpeedLbl.TextSize = 14
    hudSpeedLbl.TextColor3 = Color3.fromRGB(120, 220, 255)
    hudSpeedLbl.TextXAlignment = Enum.TextXAlignment.Left
    hudSpeedLbl.Text = "Speed: 0"
    hudSpeedLbl.Parent = frame

    hudInfoLbl = Instance.new("TextLabel")
    hudInfoLbl.Size = UDim2.new(1, -12, 0, 66)
    hudInfoLbl.Position = UDim2.new(0, 6, 0, 26)
    hudInfoLbl.BackgroundTransparency = 1
    hudInfoLbl.Font = Enum.Font.RobotoMono
    hudInfoLbl.TextSize = 11
    hudInfoLbl.TextColor3 = Color3.fromRGB(200, 200, 210)
    hudInfoLbl.TextXAlignment = Enum.TextXAlignment.Left
    hudInfoLbl.TextYAlignment = Enum.TextYAlignment.Top
    hudInfoLbl.Text = "…"
    hudInfoLbl.Parent = frame
end

task.spawn(function()
    while true do
        task.wait(0.4)
        if Config.HUD and hudSpeedLbl then
            pcall(function()
                hudSpeedLbl.Text = string.format("Speed: %.1f | Pickaxe: T%d", State.Speed, State.OwnedPickaxeTier)
                local total, types = 0, 0
                for _, c in pairs(State.Banked) do total = total + c; types = types + 1 end
                local claimed, ready = 0, 0
                for _, s in pairs(State.IndexState) do
                    if s == "Claimed" then claimed = claimed + 1
                    elseif s == "Ready" then ready = ready + 1 end
                end
                hudInfoLbl.Text = string.format(
                    "Banked: %d (%d types)\nIndex: %d claimed / %d ready\nEggs found: %d | Steal prompts: %d",
                    total, types, claimed, ready, #EggCache.list, #PromptCache.all)
            end)
        end
    end
end)

-- ============================================================
-- DISCOVERY
-- ============================================================
local function startDiscovery()
    if Config.DiscoverOn then return end
    local mt = getrawmetatable and getrawmetatable(game) or debug.getmetatable(game)
    if not mt or not mt.__namecall then UI_Notify("Discovery unsupported", "error") return end
    Config.DiscoverOn = true
    local old = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer")
           and typeof(self) == "Instance"
           and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            local path = self:GetFullName()
            local rec = Config.DiscoveredRemotes[path]
            if not rec then
                Config.DiscoveredRemotes[path] = { count = 1, first = tick() }
                print("[ATX Discover] " .. path)
            else
                rec.count = rec.count + 1
            end
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
    UI_Notify("Discovery ON", "success")
end

local function stopDiscovery()
    Config.DiscoverOn = false
    UI_Notify("Discovery OFF")
end

-- ============================================================
-- MISC
-- ============================================================
local function rejoin()
    pcall(function() Teleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
end
local function resetChar()
    local h = getHum()
    if h then h.Health = 0 end
end

-- ============================================================
-- WINDUI
-- ============================================================
local ok, err = pcall(function()
    WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not ok or not WindUI then
    warn("[ATX BSE] WindUI load failed: " .. tostring(err))
    return
end

local created, win = pcall(function()
    return WindUI:CreateWindow({
        Title = "ATX Break & Steal an Egg",
        Icon = "zap",
        Author = CREDIT,
        Folder = "BSEATX",
        Size = UDim2.fromOffset(640, 520),
        Theme = "Dark",
        Resizable = true,
        ToggleKey = Enum.KeyCode.RightShift,
        OpenButton = {
            Title = "ATX",
            Icon = "zap",
            CornerRadius = UDim.new(0, 16),
            StrokeThickness = 2,
            Color = ColorSequence.new(Color3.fromHex("8B3FFF"), Color3.fromHex("C678FF")),
            OnlyMobile = false,
            Enabled = true,
            Draggable = true,
        },
    })
end)
if not created or not win then
    warn("[ATX BSE] Window creation failed")
    return
end
Window = win
pcall(function() WindUI:SetNotificationLower(true) end)

local TabMain   = Window:Tab({ Title = "Main",     Icon = "home" })
local TabBase   = Window:Tab({ Title = "Base",     Icon = "home" })
local TabShops  = Window:Tab({ Title = "Shops",    Icon = "shopping-cart" })
local TabPlayer = Window:Tab({ Title = "Player",   Icon = "user" })
local TabMove   = Window:Tab({ Title = "Move",     Icon = "feather" })
local TabESP    = Window:Tab({ Title = "ESP",      Icon = "eye" })
local TabTools  = Window:Tab({ Title = "Tools",    Icon = "wrench" })
local TabMisc   = Window:Tab({ Title = "Misc",     Icon = "settings" })

-- =================== MAIN ===================
TabMain:Section({ Title = "Egg Breaking" })
TabMain:Toggle({
    Title = "Auto Break Eggs",
    Value = false,
    Callback = function(v) Config.AutoEggBreak = v end,
})
TabMain:Toggle({
    Title = "Auto Teleport to Egg",
    Value = true,
    Callback = function(v) Config.AutoEggTeleport = v end,
})
TabMain:Slider({
    Title = "Fire Cooldown (s)",
    Value = { Min = 0.05, Max = 1, Default = 0.15 },
    Step = 0.05,
    Callback = function(v) Config.EggFireCooldown = v end,
})
TabMain:Slider({
    Title = "Search Range",
    Value = { Min = 50, Max = 5000, Default = 5000 },
    Step = 50,
    Callback = function(v) Config.EggSearchRange = v end,
})
TabMain:Slider({
    Title = "Rescan Interval (s)",
    Value = { Min = 0.5, Max = 10, Default = 2 },
    Step = 0.5,
    Callback = function(v) Config.EggRescanInterval = v end,
})
TabMain:Button({
    Title = "Force Rescan Eggs",
    Icon = "refresh-cw",
    Callback = function()
        scanEggs(true)
        UI_Notify("Eggs: " .. #EggCache.list, "success")
    end,
})
TabMain:Button({
    Title = "Hit Nearest Egg Now",
    Icon = "target",
    Callback = function()
        local egg, d = getNearestEgg(2000)
        if egg and Remotes.EggHitRequest then
            Remotes.EggHitRequest:FireServer(egg.instance, math.max(1, State.OwnedPickaxeTier))
            UI_Notify(string.format("Hit %s (%dm)", egg.instance.Name, math.floor(d)))
        else
            UI_Notify("No egg found", "error")
        end
    end,
})
TabMain:Button({
    Title = "Teleport to Nearest Egg",
    Icon = "map-pin",
    Callback = function()
        local egg, d = getNearestEgg(5000)
        if egg then
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(egg.pos + Vector3.new(0, 3, 0))
                UI_Notify(string.format("TP → %s (%dm)", egg.instance.Name, math.floor(d)))
            end
        else
            UI_Notify("No egg", "error")
        end
    end,
})

TabMain:Section({ Title = "Auto Steal" })
TabMain:Toggle({
    Title = "Auto Steal Enemy Animals",
    Value = false,
    Callback = function(v) Config.AutoSteal = v end,
})
TabMain:Toggle({
    Title = "Only Steal Enemy (skip own)",
    Value = true,
    Callback = function(v) Config.StealOnlyEnemy = v end,
})
TabMain:Slider({
    Title = "Steal Range",
    Value = { Min = 20, Max = 5000, Default = 5000 },
    Step = 20,
    Callback = function(v) Config.StealRange = v end,
})
TabMain:Slider({
    Title = "Steal Cooldown (s)",
    Value = { Min = 0.1, Max = 3, Default = 0.3 },
    Step = 0.1,
    Callback = function(v) Config.StealCooldown = v end,
})
TabMain:Button({
    Title = "Force Rescan Steal Prompts",
    Icon = "refresh-cw",
    Callback = function()
        scanStealPrompts(true)
        UI_Notify("Steal prompts: " .. #PromptCache.all, "success")
    end,
})
TabMain:Button({
    Title = "Steal Nearest Now",
    Icon = "hand",
    Callback = function()
        local p, d = getNearestStealPrompt(5000)
        if p then
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(p.pos + Vector3.new(0, 3, 0))
                task.wait(0.15)
                firePrompt(p.prompt)
                UI_Notify(string.format("Steal fired (%dm)", math.floor(d)))
            end
        else
            UI_Notify("No steal prompt found", "error")
        end
    end,
})

TabMain:Section({ Title = "Index" })
TabMain:Toggle({
    Title = "Auto Claim Index (ClaimAll)",
    Value = false,
    Callback = function(v) Config.AutoClaimIndex = v end,
})
TabMain:Slider({
    Title = "Claim Interval (s)",
    Value = { Min = 5, Max = 300, Default = 30 },
    Step = 5,
    Callback = function(v) Config.ClaimIndexInterval = v end,
})
TabMain:Button({
    Title = "Claim All Now",
    Icon = "check",
    Callback = function()
        if Remotes.IndexRemote then
            Remotes.IndexRemote:FireServer("ClaimAll")
            UI_Notify("ClaimAll fired", "success")
        end
    end,
})

-- =================== BASE ===================
TabBase:Section({ Title = "Base Position" })
TabBase:Button({
    Title = "Set Base at Current Position",
    Icon = "map-pin",
    Callback = function()
        local hrp = getHRP()
        if hrp then
            Config.BasePosition = hrp.Position
            UI_Notify(string.format("Base: %s", tostring(hrp.Position)))
        end
    end,
})
TabBase:Button({
    Title = "Teleport to Base",
    Icon = "home",
    Callback = function()
        if Config.BasePosition then
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(Config.BasePosition + Vector3.new(0, 3, 0))
                UI_Notify("TP → base")
            end
        else
            UI_Notify("No base set", "error")
        end
    end,
})

TabBase:Section({ Title = "Place Animals" })
TabBase:Toggle({
    Title = "Auto Place Animals",
    Value = false,
    Callback = function(v) Config.AutoPlace = v end,
})
TabBase:Slider({
    Title = "Place Interval (s)",
    Value = { Min = 0.5, Max = 10, Default = 1.5 },
    Step = 0.1,
    Callback = function(v) Config.AutoPlaceInterval = v end,
})
TabBase:Slider({
    Title = "Spread Radius",
    Value = { Min = 2, Max = 40, Default = 12 },
    Step = 1,
    Callback = function(v) Config.PlaceSpreadRadius = v end,
})
TabBase:Dropdown({
    Title = "Priority Mode",
    Values = { "Highest", "Lowest", "All" },
    Value = "Highest",
    Callback = function(v) Config.PlacePriorityMode = v end,
})
TabBase:Button({
    Title = "Place One Now",
    Icon = "plus",
    Callback = function()
        local name, count = getBestBankedAnimal()
        if name and Config.BasePosition and Remotes.PlaceAnimalRemote then
            local r = Config.PlaceSpreadRadius
            local offset = Vector3.new((math.random()-0.5)*r, 0, (math.random()-0.5)*r)
            Remotes.PlaceAnimalRemote:FireServer(name, Config.BasePosition + offset, count)
            UI_Notify("Placed " .. name)
        else
            UI_Notify("No banked / no base", "error")
        end
    end,
})
local bankedPara = TabBase:Paragraph({ Title = "Banked Animals", Desc = "…" })

TabBase:Section({ Title = "Treadmill" })
TabBase:Toggle({
    Title = "Auto Treadmill Session",
    Value = false,
    Callback = function(v) Config.AutoTreadmill = v end,
})
TabBase:Slider({
    Title = "Treadmill Interval (s)",
    Value = { Min = 0.2, Max = 5, Default = 1.0 },
    Step = 0.1,
    Callback = function(v) Config.TreadmillInterval = v end,
})
TabBase:Button({
    Title = "Unlock Treadmill",
    Icon = "unlock",
    Callback = function()
        if Remotes.UnlockTreadmillRequest then
            Remotes.UnlockTreadmillRequest:FireServer()
            UI_Notify("Treadmill unlock fired")
        end
    end,
})

-- =================== SHOPS ===================
TabShops:Section({ Title = "Pickaxe Shop" })
TabShops:Toggle({
    Title = "Auto Buy Pickaxe (next tier)",
    Value = false,
    Callback = function(v) Config.AutoBuyPickaxe = v end,
})
TabShops:Paragraph({
    Title = "Current Tier",
    Desc = "Tracked from Notify messages",
})
TabShops:Button({
    Title = "Buy Pickaxe Now",
    Icon = "hammer",
    Callback = function()
        if Remotes.PickaxeShopRequest then
            Remotes.PickaxeShopRequest:FireServer("Buy", State.OwnedPickaxeTier + 1)
            UI_Notify("Pickaxe buy fired")
        end
    end,
})

TabShops:Section({ Title = "Trail Shop" })
TabShops:Toggle({
    Title = "Auto Buy Trail",
    Value = false,
    Callback = function(v) Config.AutoBuyTrail = v end,
})
TabShops:Slider({
    Title = "Trail ID",
    Value = { Min = 1, Max = 20, Default = 1 },
    Step = 1,
    Callback = function(v) Config.TrailId = v end,
})
TabShops:Button({
    Title = "Buy Trail Now",
    Icon = "sparkles",
    Callback = function()
        if Remotes.TrailShopRequest then
            Remotes.TrailShopRequest:FireServer("Buy", Config.TrailId)
            UI_Notify("Trail buy fired")
        end
    end,
})

-- =================== PLAYER ===================
local statsPara = TabPlayer:Paragraph({ Title = "Stats", Desc = "…" })
TabPlayer:Toggle({
    Title = "Show HUD",
    Value = true,
    Callback = function(v) Config.HUD = v; buildHUD() end,
})
TabPlayer:Button({
    Title = "Reset Character",
    Icon = "user-x",
    Callback = function() resetChar() end,
})

-- =================== MOVE ===================
TabMove:Toggle({ Title = "Fly", Value = false, Callback = function(v) Config.Fly = v; updateFly() end })
TabMove:Slider({
    Title = "Fly Speed",
    Value = { Min = 10, Max = 400, Default = 60 },
    Step = 5,
    Callback = function(v) Config.FlySpeed = v end,
})
TabMove:Toggle({ Title = "Noclip", Value = false, Callback = function(v) Config.Noclip = v; updateNoclip() end })
TabMove:Toggle({
    Title = "Speed Mod",
    Value = false,
    Callback = function(v) Config.SpeedToggle = v; updateSpeed() end,
})
TabMove:Slider({
    Title = "Walk Speed",
    Value = { Min = 16, Max = 300, Default = 60 },
    Step = 1,
    Callback = function(v)
        Config.SpeedValue = v
        if Config.SpeedToggle then
            local h = getHum()
            if h then pcall(function() h.WalkSpeed = v end) end
        end
    end,
})

-- =================== ESP ===================
TabESP:Toggle({
    Title = "Egg ESP",
    Value = false,
    Callback = function(v) Config.EggESP = v; if not v then clearEggESP() end end,
})
TabESP:Toggle({
    Title = "Player ESP",
    Value = false,
    Callback = function(v) Config.PlayerESP = v; if not v then clearPlayerESP() end end,
})
TabESP:Toggle({
    Title = "Placed Animal ESP",
    Value = true,
    Callback = function(v) Config.PlacedAnimalESP = v; if not v then clearPlacedESP() end end,
})

-- =================== TOOLS ===================
TabTools:Section({ Title = "Discovery" })
TabTools:Button({
    Title = "Start Remote Discovery",
    Icon = "play",
    Callback = function() startDiscovery() end,
})
TabTools:Button({
    Title = "Stop Remote Discovery",
    Icon = "pause",
    Callback = function() stopDiscovery() end,
})
TabTools:Button({
    Title = "Copy Discovered Remotes",
    Icon = "copy",
    Callback = function()
        local lines = {}
        for path, info in pairs(Config.DiscoveredRemotes) do
            table.insert(lines, string.format("%s | %d", path, info.count))
        end
        pcall(function() setclipboard(table.concat(lines, "\n")) end)
        UI_Notify("Copied " .. #lines .. " remotes")
    end,
})

TabTools:Section({ Title = "Manual Fire" })
TabTools:Input({
    Title = "Remote Name",
    Value = "",
    Placeholder = "e.g. EggHitRequest",
    Callback = function(v) _G._atxRemoteName = v end,
})
TabTools:Input({
    Title = "Args (Lua table)",
    Value = "",
    Placeholder = '{"Buy", 2}',
    Callback = function(v) _G._atxRemoteArgs = v end,
})
TabTools:Button({
    Title = "Fire Remote",
    Icon = "send",
    Callback = function()
        local name = _G._atxRemoteName
        local argsRaw = _G._atxRemoteArgs
        if not name or name == "" then UI_Notify("No remote", "error") return end
        local remote = RS:FindFirstChild(name)
        if not remote or not remote:IsA("RemoteEvent") then
            UI_Notify("Remote not found", "error")
            return
        end
        local args = {}
        if argsRaw and argsRaw ~= "" then
            local fn = loadstring and loadstring("return " .. argsRaw) or load("return " .. argsRaw)
            if fn then
                local ok2, r = pcall(fn)
                if ok2 and type(r) == "table" then args = r end
            end
        end
        remote:FireServer(table.unpack(args))
        UI_Notify("Fired " .. name)
    end,
})

TabTools:Section({ Title = "Debug" })
TabTools:Button({
    Title = "Print State to F9",
    Icon = "list",
    Callback = function()
        print("[ATX] Speed:", State.Speed)
        print("[ATX] Cash:", State.Cash)
        print("[ATX] Pickaxe Tier:", State.OwnedPickaxeTier)
        print("[ATX] Eggs cached:", #EggCache.list)
        print("[ATX] Steal prompts cached:", #PromptCache.all)
        print("[ATX] Banked:")
        for n, c in pairs(State.Banked) do print("  ", n, c) end
        print("[ATX] Index:")
        for n, s in pairs(State.IndexState) do print("  ", n, s) end
        UI_Notify("Printed to F9")
    end,
})
TabTools:Button({
    Title = "Print All Eggs to F9",
    Icon = "list",
    Callback = function()
        scanEggs(true)
        for _, e in ipairs(EggCache.list) do
            print(string.format("[ATX Egg] %s | pos=%s", e.instance:GetFullName(), tostring(e.pos)))
        end
        UI_Notify("Printed " .. #EggCache.list .. " eggs")
    end,
})
TabTools:Button({
    Title = "Print All Steal Prompts to F9",
    Icon = "list",
    Callback = function()
        scanStealPrompts(true)
        for _, e in ipairs(PromptCache.all) do
            print(string.format("[ATX Steal] '%s' | %s | pos=%s",
                e.prompt.ActionText or "", e.prompt:GetFullName(), tostring(e.pos)))
        end
        UI_Notify("Printed " .. #PromptCache.all .. " prompts")
    end,
})

-- =================== MISC ===================
TabMisc:Toggle({
    Title = "Anti AFK",
    Value = true,
    Callback = function(v) Config.AntiAFK = v; updateAntiAFK() end,
})
TabMisc:Toggle({
    Title = "Anti Fling",
    Value = false,
    Callback = function(v) Config.AntiFling = v; updateAntiFling() end,
})
TabMisc:Section({ Title = "Server" })
TabMisc:Button({ Title = "Rejoin", Icon = "refresh-cw", Callback = function() rejoin() end })

-- ============================================================
-- BOOT
-- ============================================================
buildHUD()
updateAntiAFK()
scanEggs(true)
scanStealPrompts(true)
UI_Notify("ATX Break & Steal an Egg ready · " .. CREDIT, "success")

task.spawn(function()
    while Window do
        task.wait(1)
        pcall(function()
            if bankedPara and bankedPara.SetDesc then
                local lines = {}
                local names = {}
                for n in pairs(State.Banked) do table.insert(names, n) end
                table.sort(names)
                for _, n in ipairs(names) do
                    table.insert(lines, string.format("  %s: %d", n, State.Banked[n]))
                end
                if #lines == 0 then lines = {"  (empty)"} end
                bankedPara:SetDesc(table.concat(lines, "\n"))
            end
            if statsPara and statsPara.SetDesc then
                statsPara:SetDesc(string.format(
                    "Speed: %.1f\nPickaxe Tier: %d\nEggs cached: %d\nSteal prompts cached: %d",
                    State.Speed, State.OwnedPickaxeTier, #EggCache.list, #PromptCache.all))
            end
        end)
    end
end)
