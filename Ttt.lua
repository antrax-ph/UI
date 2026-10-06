-- ============================================================
-- Break and Steal an Egg - ATX
-- WindUI · no key system
-- Auto steal: brute-force prompt/clickdetector on enemy animals
-- Returns to plot after steal
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
-- RARITY SYSTEM
-- ============================================================
local RARITY_TIERS = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Cosmic", "Secret", "Eternal", "Divine",
}
local RARITY_RANK = {}
for i, name in ipairs(RARITY_TIERS) do
    RARITY_RANK[name:lower()] = i
end
local NameRarityCache = {}

local function setManualRarity(name, rarity)
    if name and rarity then NameRarityCache[name:lower()] = rarity end
end

local function detectRarity(inst)
    if not inst then return nil end
    local cur = inst
    local depth = 0
    while cur and depth < 5 do
        local sv = cur:FindFirstChild("Rarity")
        if sv and sv:IsA("StringValue") then
            local v = sv.Value
            if RARITY_RANK[(v or ""):lower()] then return v end
        end
        local ok, attr = pcall(function() return cur:GetAttribute("Rarity") end)
        if ok and type(attr) == "string" and RARITY_RANK[attr:lower()] then return attr end
        local n = (cur.Name or ""):lower()
        for rname in pairs(RARITY_RANK) do
            if n:find(rname, 1, true) then return rname:sub(1,1):upper()..rname:sub(2) end
        end
        cur = cur.Parent
        depth = depth + 1
    end
    return nil
end

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    -- Auto Steal
    AutoSteal            = false,
    StealRange           = 5000,
    StealCooldown        = 0.4,
    ReturnToPlot         = true,
    ReturnDelay          = 0.5,
    StealBruteForce      = true,     -- fire all prompts near target
    StealUsePrompts      = true,
    StealUseClickDetector= true,
    StealWaitAfterTP     = 0.2,

    -- Steal filters
    StealFilterMode      = "All",    -- All | Whitelist | Blacklist
    StealWhitelist       = "",
    StealBlacklist       = "",
    StealMinDistance     = 0,

    -- Priority
    StealPriorityMode    = "Highest First",
    StealSpecificRarity  = "Divine",
    StealMinRarity       = "None",
    StealMaxRarity       = "None",
    StealOnlyUnowned     = false,

    -- Plot
    PlotPosition         = nil,
    AutoPlace            = false,
    AutoPlaceInterval    = 1.5,
    PlaceSpreadRadius    = 12,
    PlacePriorityMode    = "Highest",

    -- Treadmill
    AutoTreadmill        = false,
    TreadmillInterval    = 1.0,
    TreadmillPosition    = nil,
    TreadmillTeleport    = true,
    TreadmillRange       = 8,
    AutoUnlockTreadmill  = false,

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
    PlacedAnimalESP      = true,
    StealTargetESP       = true,

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
    TrailShopRequest       = nil,
    PickaxeShopRequest     = nil,
    UnlockTreadmillRequest = nil,
    SpeedGainRemote        = nil,
    AnimalBankedRemote     = nil,
    Notify                 = nil,
    AnimalPlacedVFXRemote  = nil,
}

task.spawn(function()
    local t = 0
    while t < 30 do
        for _, name in ipairs({
            "IndexRemote", "PlaceAnimalRemote", "TreadmillSessionRemote",
            "TrailShopRequest", "PickaxeShopRequest",
            "UnlockTreadmillRequest", "SpeedGainRemote", "AnimalBankedRemote",
            "Notify", "AnimalPlacedVFXRemote",
        }) do
            if not Remotes[name] then
                Remotes[name] = RS:FindFirstChild(name)
            end
        end
        if Remotes.PlaceAnimalRemote and Remotes.Notify then break end
        task.wait(0.5)
        t = t + 0.5
    end
end)

-- ============================================================
-- STATE
-- ============================================================
local State = {
    Speed = 0,
    Banked = {},
    IndexState = {},
    PlacedAnimals = {},
    OwnedPickaxeTier = 1,
    StealBusy = false,
    StealLastFire = 0,
    TreadmillLastFire = 0,
    TreadmillLastMove = 0,
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

if Remotes.Notify then
    Remotes.Notify.OnClientEvent:Connect(function(text, kind, opts)
        if type(text) ~= "string" then return end
        local pick = text:match("{(.-) Pickaxe}")
        if pick then
            local tierMap = { Wooden=1, Stone=2, Iron=3, Gold=4, Diamond=5, Emerald=6, Ruby=7, Amethyst=8 }
            if tierMap[pick] then State.OwnedPickaxeTier = tierMap[pick] end
        end
    end)
end

-- Track every placement VFX (ours + enemies)
if Remotes.AnimalPlacedVFXRemote then
    Remotes.AnimalPlacedVFXRemote.OnClientEvent:Connect(function(pos, plr, isMine, maybeRarity, maybeName)
        if typeof(pos) == "Vector3" then
            local id = string.format("%.1f_%.1f_%.1f", pos.X, pos.Y, pos.Z)
            State.PlacedAnimals[id] = {
                pos = pos,
                owner = plr,
                mine = isMine == true or plr == LP,
                time = tick(),
                rarity = type(maybeRarity) == "string" and maybeRarity or nil,
                name = type(maybeName) == "string" and maybeName or nil,
            }
        end
    end)
end

if Remotes.TreadmillSessionRemote then
    Remotes.TreadmillSessionRemote.OnClientEvent:Connect(function(a, b)
        if typeof(b) == "CFrame" and not Config.TreadmillPosition then
            Config.TreadmillPosition = b.Position
        end
    end)
end

-- ============================================================
-- STEAL TARGETS = enemy placed animals only
-- ============================================================
local function isEnemyAnimal(entry)
    if not entry then return false end
    if entry.mine then return false end
    if not entry.pos then return false end
    if tick() - entry.time > 300 then return false end  -- stale
    return true
end

local function getEntryRarity(entry)
    if not entry then return nil end
    if entry.rarity then return entry.rarity end
    if entry.name and NameRarityCache[entry.name:lower()] then
        return NameRarityCache[entry.name:lower()]
    end
    -- Try to find the actual instance
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Model") or d:IsA("BasePart") then
            local pos = d:IsA("BasePart") and d.Position
                     or (d.PrimaryPart and d.PrimaryPart.Position)
            if pos and (pos - entry.pos).Magnitude < 8 then
                local r = detectRarity(d)
                if r then
                    if entry.name then NameRarityCache[entry.name:lower()] = r end
                    return r
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- STEAL FILTERS
-- ============================================================
local function parseCSV(str)
    local set = {}
    if not str or str == "" then return set end
    for token in str:gmatch("[^,]+") do
        local t = token:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if t ~= "" then set[t] = true end
    end
    return set
end

local function isOwnedInIndex(name)
    if not name then return false end
    for k, v in pairs(State.IndexState) do
        if k:lower() == name:lower() and v == "Claimed" then return true end
    end
    return false
end

local function passesFilter(entry)
    local name = (entry.name or ""):lower()

    -- Name filter
    if Config.StealFilterMode == "Whitelist" then
        local set = parseCSV(Config.StealWhitelist)
        if next(set) then
            local found = false
            for k in pairs(set) do
                if name:find(k, 1, true) then found = true break end
            end
            if not found then return false end
        end
    elseif Config.StealFilterMode == "Blacklist" then
        local set = parseCSV(Config.StealBlacklist)
        for k in pairs(set) do
            if name:find(k, 1, true) then return false end
        end
    end

    -- Rarity filter
    local rarity = getEntryRarity(entry)
    if rarity then
        local rank = RARITY_RANK[rarity:lower()] or 0
        if Config.StealMinRarity ~= "None" then
            local minRank = RARITY_RANK[Config.StealMinRarity:lower()] or 0
            if rank < minRank then return false end
        end
        if Config.StealMaxRarity ~= "None" then
            local maxRank = RARITY_RANK[Config.StealMaxRarity:lower()] or 999
            if rank > maxRank then return false end
        end
    end

    -- Ownership
    if Config.StealOnlyUnowned and isOwnedInIndex(entry.name) then
        return false
    end

    return true
end

-- ============================================================
-- PRIORITY
-- ============================================================
local function getPriorityRank(entry)
    local rarity = getEntryRarity(entry)
    return rarity and (RARITY_RANK[rarity:lower()] or 0) or 0
end

local function getBestTarget()
    local hrp = getHRP()
    if not hrp then return nil end
    local candidates = {}
    for _, entry in pairs(State.PlacedAnimals) do
        if isEnemyAnimal(entry) then
            local d = (entry.pos - hrp.Position).Magnitude
            if d <= Config.StealRange and d >= Config.StealMinDistance then
                if passesFilter(entry) then
                    table.insert(candidates, { entry = entry, dist = d })
                end
            end
        end
    end
    if #candidates == 0 then return nil end

    local mode = Config.StealPriorityMode
    if mode == "Specific Rarity" then
        local target = RARITY_RANK[Config.StealSpecificRarity:lower()] or 0
        table.sort(candidates, function(a, b)
            local ar, br = getPriorityRank(a.entry), getPriorityRank(b.entry)
            local aM = ar == target and 1 or 0
            local bM = br == target and 1 or 0
            if aM ~= bM then return aM > bM end
            if ar ~= br then return ar > br end
            return a.dist < b.dist
        end)
    elseif mode == "Lowest First" then
        table.sort(candidates, function(a, b)
            local ar, br = getPriorityRank(a.entry), getPriorityRank(b.entry)
            if ar == 0 and br ~= 0 then return false end
            if br == 0 and ar ~= 0 then return true end
            if ar ~= br then return ar < br end
            return a.dist < b.dist
        end)
    else
        table.sort(candidates, function(a, b)
            local ar, br = getPriorityRank(a.entry), getPriorityRank(b.entry)
            if ar ~= br then return ar > br end
            return a.dist < b.dist
        end)
    end
    return candidates[1].entry
end

-- ============================================================
-- STEAL ACTIONS — brute force
-- ============================================================
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

local function fireClickDetector(cd)
    if not cd or not cd.Parent then return false end
    if fireclickdetector then
        local ok = pcall(fireclickdetector, cd)
        if ok then return true end
        pcall(fireclickdetector, cd, 0)  -- ClickDetector mouse
    end
    if firetouchinterest then
        local hrp = getHRP()
        if hrp and cd.Parent and cd.Parent:IsA("BasePart") then
            pcall(function()
                firetouchinterest(hrp, cd.Parent, 0)
                task.wait(0.03)
                firetouchinterest(hrp, cd.Parent, 1)
            end)
            return true
        end
    end
    return false
end

-- Find every prompt/clickdetector within radius of a position
local function gatherInteractionObjects(pos, radius)
    radius = radius or 10
    local prompts, cds = {}, {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local parent = d.Parent
            local ppos = (parent and parent:IsA("BasePart") and parent.Position)
                       or (parent and parent:FindFirstChildWhichIsA("BasePart") and parent:FindFirstChildWhichIsA("BasePart").Position)
            if ppos and (ppos - pos).Magnitude <= radius then
                table.insert(prompts, d)
            end
        elseif d:IsA("ClickDetector") and d.Parent then
            local parent = d.Parent
            if parent:IsA("BasePart") then
                if (parent.Position - pos).Magnitude <= radius then
                    table.insert(cds, d)
                end
            end
        end
    end
    return prompts, cds
end

local function teleportToPosition(pos, height)
    height = height or 3
    local hrp = getHRP()
    if not hrp or not pos then return end
    pcall(function() hrp.CFrame = CFrame.new(pos + Vector3.new(0, height, 0)) end)
end

-- ============================================================
-- STEAL CYCLE
-- ============================================================
local function doStealCycle(target)
    if not target or not target.pos then return false end

    -- 1. Teleport to target
    teleportToPosition(target.pos, 3)
    task.wait(Config.StealWaitAfterTP)

    -- 2. Gather interaction objects at that position
    local prompts, cds = gatherInteractionObjects(target.pos, 10)

    local fired = 0
    -- 3. Fire prompts
    if Config.StealUsePrompts then
        for _, p in ipairs(prompts) do
            if firePrompt(p) then fired = fired + 1 end
            task.wait(0.05)
        end
    end
    -- 4. Fire click detectors
    if Config.StealUseClickDetector then
        for _, c in ipairs(cds) do
            if fireClickDetector(c) then fired = fired + 1 end
            task.wait(0.05)
        end
    end

    -- 5. Fallback: fire VirtualUser click at the target's screen position (last resort)
    if fired == 0 then
        pcall(function()
            local screenPos, onScreen = Camera:WorldToViewportPoint(target.pos)
            if onScreen then
                VirtualUser:CaptureController()
                VirtualUser:ClickButton1(Vector2.new(screenPos.X, screenPos.Y))
            end
        end)
    end

    task.wait(Config.ReturnDelay)

    -- 6. Return to plot
    if Config.ReturnToPlot and Config.PlotPosition then
        teleportToPosition(Config.PlotPosition, 4)
        task.wait(0.2)
    end

    return fired > 0
end

local function runAutoSteal()
    if State.StealBusy then return end
    if not Config.AutoSteal then return end
    local now = tick()
    if now - State.StealLastFire < Config.StealCooldown then return end

    local target = getBestTarget()
    if not target then
        return
    end

    State.StealBusy = true
    State.StealLastFire = now

    local rarity = getEntryRarity(target) or "?"

    task.spawn(function()
        local ok = doStealCycle(target)
        State.StealBusy = false
        if Config.Notify then
            local tn = target.name or "?"
            UI_Notify(string.format("Steal %s [%s] %s", tn, rarity, ok and "fired" or "attempted"), "success")
        end
    end)
end

Run.Heartbeat:Connect(function()
    pcall(runAutoSteal)
end)

-- ============================================================
-- AUTO PLACE
-- ============================================================
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

local lastPlaceFire = 0
local function tickAutoPlace()
    if not Config.AutoPlace then return end
    if not Config.PlotPosition then return end
    if not Remotes.PlaceAnimalRemote then return end
    local now = tick()
    if now - lastPlaceFire < Config.AutoPlaceInterval then return end

    local name, count = getBestBankedAnimal()
    if not name then return end
    lastPlaceFire = now

    local r = Config.PlaceSpreadRadius
    local offset = Vector3.new((math.random() - 0.5) * r, 0, (math.random() - 0.5) * r)
    local pos = Config.PlotPosition + offset
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LP.Character and { LP.Character } or {}
    local hit = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -50, 0), params)
    if hit then pos = hit.Position + Vector3.new(0, 1.3, 0) end

    pcall(function() Remotes.PlaceAnimalRemote:FireServer(name, pos, count) end)
end

-- ============================================================
-- TREADMILL
-- ============================================================
local function findTreadmillPart()
    if Config.TreadmillPosition then return Config.TreadmillPosition end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and (d.Name or ""):lower():find("treadmill", 1, true) then
            Config.TreadmillPosition = d.Position
            return d.Position
        end
    end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Model") and (d.Name or ""):lower():find("treadmill", 1, true) then
            local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
            if pp then
                Config.TreadmillPosition = pp.Position
                return pp.Position
            end
        end
    end
    return nil
end

local function tickTreadmill()
    if not Config.AutoTreadmill then return end
    local now = tick()
    if now - State.TreadmillLastFire < Config.TreadmillInterval then return end

    local tp = findTreadmillPart()
    if tp then
        local hrp = getHRP()
        if hrp then
            local d = (hrp.Position - tp).Magnitude
            if d > Config.TreadmillRange then
                if Config.TreadmillTeleport and now - State.TreadmillLastMove > 0.8 then
                    State.TreadmillLastMove = now
                    teleportToPosition(tp, 4)
                end
                return
            end
        end
    end

    State.TreadmillLastFire = now
    if Remotes.TreadmillSessionRemote then
        pcall(function() Remotes.TreadmillSessionRemote:FireServer() end)
    end
    if Config.AutoUnlockTreadmill and Remotes.UnlockTreadmillRequest then
        pcall(function() Remotes.UnlockTreadmillRequest:FireServer() end)
    end
end

-- ============================================================
-- INDEX + SHOPS
-- ============================================================
local lastClaimIndex, lastPickaxeBuy, lastTrailBuy = 0, 0, 0

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

Run.Heartbeat:Connect(function()
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
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
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

-- Marker for every tracked placed animal
local placedMarkers = {}
local function clearPlacedMarkers()
    for _, e in pairs(placedMarkers) do
        if e.part then pcall(function() e.part:Destroy() end) end
    end
    placedMarkers = {}
end

local function refreshPlacedMarkers()
    if not Config.PlacedAnimalESP then
        if next(placedMarkers) then clearPlacedMarkers() end
        return
    end
    for id, p in pairs(State.PlacedAnimals) do
        if tick() - p.time > 300 then
            State.PlacedAnimals[id] = nil
        else
            if not placedMarkers[id] then
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
                bb.Size = UDim2.new(0, 200, 0, 30)
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
                local ownerName = typeof(p.owner) == "Instance" and p.owner.Name or "?"
                local txt = (p.mine and "YOURS" or ownerName)
                if p.rarity then txt = txt .. " [" .. p.rarity .. "]" end
                lb.Text = txt
                lb.Parent = bb
                placedMarkers[id] = { billboard = bb, label = lb, part = part }
            end
        end
    end
    for id, e in pairs(placedMarkers) do
        if not State.PlacedAnimals[id] then
            if e.part then pcall(function() e.part:Destroy() end) end
            placedMarkers[id] = nil
        end
    end
end

Run.Heartbeat:Connect(function()
    pcall(refreshPlayerESP)
    pcall(refreshPlacedMarkers)
end)

-- ============================================================
-- HUD
-- ============================================================
local hudGui, hudTopLbl, hudInfoLbl
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
    frame.Size = UDim2.new(0, 300, 0, 116)
    frame.Position = UDim2.new(0, 12, 0, 12)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = hudGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    hudTopLbl = Instance.new("TextLabel")
    hudTopLbl.Size = UDim2.new(1, -12, 0, 20)
    hudTopLbl.Position = UDim2.new(0, 6, 0, 4)
    hudTopLbl.BackgroundTransparency = 1
    hudTopLbl.Font = Enum.Font.GothamBold
    hudTopLbl.TextSize = 14
    hudTopLbl.TextColor3 = Color3.fromRGB(120, 220, 255)
    hudTopLbl.TextXAlignment = Enum.TextXAlignment.Left
    hudTopLbl.Text = "Speed: 0"
    hudTopLbl.Parent = frame

    hudInfoLbl = Instance.new("TextLabel")
    hudInfoLbl.Size = UDim2.new(1, -12, 0, 86)
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
        if Config.HUD and hudTopLbl then
            pcall(function()
                hudTopLbl.Text = string.format("Speed: %.1f | Pickaxe: T%d", State.Speed, State.OwnedPickaxeTier)
                local total = 0
                for _, c in pairs(State.Banked) do total = total + c end
                local enemyCount = 0
                for _, p in pairs(State.PlacedAnimals) do
                    if not p.mine then enemyCount = enemyCount + 1 end
                end
                hudInfoLbl.Text = string.format(
                    "Banked: %d | Enemies: %d\nPriority: %s\nPlot: %s | Tread: %s",
                    total, enemyCount, Config.StealPriorityMode,
                    Config.PlotPosition and "set" or "NO",
                    Config.TreadmillPosition and "set" or "NO")
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
        Size = UDim2.fromOffset(660, 540),
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
local TabBase   = Window:Tab({ Title = "Plot",     Icon = "home" })
local TabShops  = Window:Tab({ Title = "Shops",    Icon = "shopping-cart" })
local TabPlayer = Window:Tab({ Title = "Player",   Icon = "user" })
local TabMove   = Window:Tab({ Title = "Move",     Icon = "feather" })
local TabESP    = Window:Tab({ Title = "ESP",      Icon = "eye" })
local TabTools  = Window:Tab({ Title = "Tools",    Icon = "wrench" })
local TabMisc   = Window:Tab({ Title = "Misc",     Icon = "settings" })

-- =================== MAIN ===================
TabMain:Section({ Title = "Auto Steal" })
TabMain:Toggle({
    Title = "Auto Steal Enemy Animals",
    Value = false,
    Callback = function(v) Config.AutoSteal = v end,
})
TabMain:Toggle({
    Title = "Return To Plot After Steal",
    Value = true,
    Callback = function(v) Config.ReturnToPlot = v end,
})
TabMain:Slider({
    Title = "Return Delay (s)",
    Value = { Min = 0.1, Max = 2, Default = 0.5 },
    Step = 0.05,
    Callback = function(v) Config.ReturnDelay = v end,
})
TabMain:Slider({
    Title = "Wait After Teleport (s)",
    Value = { Min = 0.05, Max = 1, Default = 0.2 },
    Step = 0.05,
    Callback = function(v) Config.StealWaitAfterTP = v end,
})
TabMain:Slider({
    Title = "Steal Range",
    Value = { Min = 20, Max = 5000, Default = 5000 },
    Step = 20,
    Callback = function(v) Config.StealRange = v end,
})
TabMain:Slider({
    Title = "Steal Cooldown (s)",
    Value = { Min = 0.1, Max = 3, Default = 0.4 },
    Step = 0.1,
    Callback = function(v) Config.StealCooldown = v end,
})
TabMain:Slider({
    Title = "Skip Prompts Closer Than (studs)",
    Value = { Min = 0, Max = 100, Default = 0 },
    Step = 1,
    Callback = function(v) Config.StealMinDistance = v end,
})
TabMain:Toggle({
    Title = "Use ProximityPrompt",
    Value = true,
    Callback = function(v) Config.StealUsePrompts = v end,
})
TabMain:Toggle({
    Title = "Use ClickDetector",
    Value = true,
    Callback = function(v) Config.StealUseClickDetector = v end,
})

TabMain:Section({ Title = "Priority Steal (Rarity)" })
TabMain:Dropdown({
    Title = "Priority Mode",
    Values = { "Highest First", "Lowest First", "Specific Rarity" },
    Value = "Highest First",
    Callback = function(v) Config.StealPriorityMode = v end,
})
TabMain:Dropdown({
    Title = "Specific Rarity",
    Values = RARITY_TIERS,
    Value = "Divine",
    Callback = function(v) Config.StealSpecificRarity = v end,
})

TabMain:Section({ Title = "Rarity Filter" })
TabMain:Dropdown({
    Title = "Min Rarity",
    Values = { "None", table.unpack(RARITY_TIERS) },
    Value = "None",
    Callback = function(v) Config.StealMinRarity = v end,
})
TabMain:Dropdown({
    Title = "Max Rarity",
    Values = { "None", table.unpack(RARITY_TIERS) },
    Value = "None",
    Callback = function(v) Config.StealMaxRarity = v end,
})
TabMain:Toggle({
    Title = "Only Steal Unowned",
    Value = false,
    Callback = function(v) Config.StealOnlyUnowned = v end,
})

TabMain:Section({ Title = "Name Filter" })
TabMain:Dropdown({
    Title = "Filter Mode",
    Values = { "All", "Whitelist", "Blacklist" },
    Value = "All",
    Callback = function(v) Config.StealFilterMode = v end,
})
TabMain:Input({
    Title = "Whitelist (comma-separated)",
    Value = "",
    Placeholder = "Dragon,Phoenix",
    Callback = function(v) Config.StealWhitelist = v end,
})
TabMain:Input({
    Title = "Blacklist (comma-separated)",
    Value = "",
    Placeholder = "Chicken,Bat",
    Callback = function(v) Config.StealBlacklist = v end,
})

TabMain:Section({ Title = "Manual Rarity Map" })
TabMain:Input({
    Title = "Name=Rarity (comma-separated)",
    Value = "",
    Placeholder = "Dragon=Divine,Chicken=Common",
    Callback = function(v)
        if not v or v == "" then return end
        for pair in v:gmatch("[^,]+") do
            local n, r = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
            if n and r and RARITY_RANK[r:lower()] then
                setManualRarity(n, r)
            end
        end
        UI_Notify("Rarity map updated", "success")
    end,
})

TabMain:Section({ Title = "Actions" })
TabMain:Button({
    Title = "Steal Best Now",
    Icon = "hand",
    Callback = function()
        local t = getBestTarget()
        if not t then UI_Notify("No enemy target", "error") return end
        local rarity = getEntryRarity(t) or "?"
        local ok = doStealCycle(t)
        UI_Notify(string.format("Steal %s [%s] %s", t.name or "?", rarity, ok and "fired" or "attempted"))
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

TabMain:Section({ Title = "Treadmill" })
TabMain:Toggle({
    Title = "Auto Treadmill",
    Value = false,
    Callback = function(v) Config.AutoTreadmill = v end,
})
TabMain:Toggle({
    Title = "Teleport To Treadmill",
    Value = true,
    Callback = function(v) Config.TreadmillTeleport = v end,
})
TabMain:Slider({
    Title = "Treadmill Range (studs)",
    Value = { Min = 3, Max = 40, Default = 8 },
    Step = 1,
    Callback = function(v) Config.TreadmillRange = v end,
})
TabMain:Slider({
    Title = "Treadmill Interval (s)",
    Value = { Min = 0.2, Max = 5, Default = 1.0 },
    Step = 0.1,
    Callback = function(v) Config.TreadmillInterval = v end,
})
TabMain:Toggle({
    Title = "Auto Unlock Treadmill",
    Value = false,
    Callback = function(v) Config.AutoUnlockTreadmill = v end,
})
TabMain:Button({
    Title = "Set Treadmill at Current Position",
    Icon = "map-pin",
    Callback = function()
        local hrp = getHRP()
        if hrp then
            Config.TreadmillPosition = hrp.Position
            UI_Notify("Treadmill set")
        end
    end,
})

-- =================== PLOT ===================
TabBase:Section({ Title = "Plot Position" })
TabBase:Paragraph({
    Title = "Where steals return to",
    Desc = "Stand on your plot and click Set Plot. Auto steal returns here after each steal.",
})
TabBase:Button({
    Title = "Set Plot at Current Position",
    Icon = "map-pin",
    Callback = function()
        local hrp = getHRP()
        if hrp then
            Config.PlotPosition = hrp.Position
            UI_Notify("Plot set")
        end
    end,
})
TabBase:Button({
    Title = "Teleport to Plot",
    Icon = "home",
    Callback = function()
        if Config.PlotPosition then
            teleportToPosition(Config.PlotPosition, 4)
            UI_Notify("TP → plot")
        else
            UI_Notify("No plot set", "error")
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
        if name and Config.PlotPosition and Remotes.PlaceAnimalRemote then
            local r = Config.PlaceSpreadRadius
            local offset = Vector3.new((math.random()-0.5)*r, 0, (math.random()-0.5)*r)
            Remotes.PlaceAnimalRemote:FireServer(name, Config.PlotPosition + offset, count)
            UI_Notify("Placed " .. name)
        else
            UI_Notify("No banked / no plot", "error")
        end
    end,
})
local bankedPara = TabBase:Paragraph({ Title = "Banked Animals", Desc = "…" })

-- =================== SHOPS ===================
TabShops:Section({ Title = "Pickaxe Shop" })
TabShops:Toggle({
    Title = "Auto Buy Pickaxe (next tier)",
    Value = false,
    Callback = function(v) Config.AutoBuyPickaxe = v end,
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
    Title = "Player ESP",
    Value = false,
    Callback = function(v) Config.PlayerESP = v; if not v then clearPlayerESP() end end,
})
TabESP:Toggle({
    Title = "Placed Animal ESP",
    Value = true,
    Callback = function(v) Config.PlacedAnimalESP = v; if not v then clearPlacedMarkers() end end,
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

TabTools:Section({ Title = "Debug" })
TabTools:Button({
    Title = "Print Enemy Animals to F9",
    Icon = "list",
    Callback = function()
        local hrp = getHRP()
        for id, p in pairs(State.PlacedAnimals) do
            if not p.mine then
                local d = hrp and (p.pos - hrp.Position).Magnitude or 0
                print(string.format("[ATX Enemy] id=%s owner=%s rarity=%s dist=%.0f pos=%s",
                    id,
                    typeof(p.owner) == "Instance" and p.owner.Name or "?",
                    p.rarity or "?", d, tostring(p.pos)))
            end
        end
        UI_Notify("Printed to F9")
    end,
})
TabTools:Button({
    Title = "Print Prompts Near Enemy Animals",
    Icon = "list",
    Callback = function()
        for id, p in pairs(State.PlacedAnimals) do
            if not p.mine then
                local prompts, cds = gatherInteractionObjects(p.pos, 12)
                print(string.format("[ATX] Animal %s @ %s → %d prompts, %d detectors",
                    id, tostring(p.pos), #prompts, #cds))
                for _, pr in ipairs(prompts) do
                    print(string.format("   prompt '%s' | ObjectText='%s' | Hold=%.2f | %s",
                        pr.ActionText or "", pr.ObjectText or "",
                        pr.HoldDuration or 0, pr:GetFullName()))
                end
                for _, cd in ipairs(cds) do
                    print(string.format("   clickdetector | %s", cd:GetFullName()))
                end
            end
        end
        UI_Notify("Printed to F9")
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
findTreadmillPart()
UI_Notify("ATX ready · " .. CREDIT, "success")

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
                local enemyCount = 0
                for _, p in pairs(State.PlacedAnimals) do
                    if not p.mine then enemyCount = enemyCount + 1 end
                end
                statsPara:SetDesc(string.format(
                    "Speed: %.1f\nPickaxe: T%d\nPriority: %s\nEnemy animals tracked: %d\nPlot: %s\nTreadmill: %s",
                    State.Speed, State.OwnedPickaxeTier, Config.StealPriorityMode,
                    enemyCount,
                    Config.PlotPosition and "set" or "NOT SET",
                    Config.TreadmillPosition and "set" or "NOT SET"))
            end
        end
    end
end)
