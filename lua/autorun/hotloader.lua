--[[
 _   _  ___ _____ _     ___    _    ____  _____ ____
| | | |/ _ \_   _| |   / _ \  / \  |  _ \| ____|  _ \
| |_| | | | || | | |  | | | |/ _ \ | | | |  _| | |_) |
|  _  | |_| || | | |__| |_| / ___ \| |_| | |___|  _ <
|_| |_|\___/ |_| |_____\___/_/   \_\____/|_____|_| \_\

                                                        ]]

if SERVER then
    AddCSLuaFile()
end

TBH = TBH or {}

TBH.Version = "1.0.2"
TBH.NetString = "hotloader"

--------------------------------------------------------------------------------
-- Theme (neon dark green)
--------------------------------------------------------------------------------

TBH.Colors = {
    tag      = Color(124, 211, 78),   -- bright steam green
    accent   = Color(94, 168, 62),    -- mid green
    dim      = Color(58, 104, 44),    -- deep green
    text     = Color(226, 234, 226),
    textdim  = Color(148, 160, 148),
    bg       = Color(16, 20, 17),
    bgPanel  = Color(26, 33, 27),
    bgPanel2 = Color(34, 43, 36),
    outline  = Color(52, 70, 55),
    error    = Color(236, 100, 100),
    warn     = Color(236, 184, 82),
    info     = Color(110, 176, 236),
    ok       = Color(124, 211, 78),
}

TBH.FrameHooks = {}
for _, name in ipairs({
    "Think", "Tick", "HUDPaint", "HUDPaintBackground", "DrawOverlay", "PostDrawHUD", "PreDrawHUD",
    "PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables", "PreDrawTranslucentRenderables",
    "PostDrawTranslucentRenderables", "PreDrawViewModel", "PostDrawViewModel", "PostDrawViewModels",
    "RenderScene", "PreRender", "PostRender", "RenderScreenspaceEffects", "CalcView",
    "CalcViewModelView", "CreateMove", "StartCommand", "Move", "SetupMove", "FinishMove",
    "PlayerTick", "ShouldDrawLocalPlayer", "HUDShouldDraw", "PostPlayerDraw", "PrePlayerDraw",
}) do
    TBH.FrameHooks[name] = true
end

TBH.Theme = {
    bgMaterial = nil,    
    bgPath     = "",         
}

local function BgImageCandidates(raw)
    local out = {}
    local function add(p)
        if isstring(p) and p ~= "" then out[#out + 1] = p end
    end
	
    local norm = string.gsub(raw, "\\", "/")
    add(norm)

    if not string.match(norm, "^%.%./") then
        local stripped = string.gsub(norm, "^/", "")
        stripped = string.gsub(stripped, "^data/", "")
        if file.Exists(stripped, "DATA") then
            add("../data/" .. stripped)
        end
        local matrel = string.gsub(stripped, "^materials/", "")
        if matrel ~= stripped then
            add(matrel)
        end
        local low = string.lower(stripped)
        if string.match(low, "%.png$") or string.match(low, "%.jpg$") or string.match(low, "%.jpeg$") then
            add("../data/" .. stripped)
        end
    end
    local seen, uniq = {}, {}
    for i = 1, #out do
        if not seen[out[i]] then
            seen[out[i]] = true
            uniq[#uniq + 1] = out[i]
        end
    end
    return uniq
end

function TBH.LoadThemeBackground(force)
    if not CLIENT then return end

    local raw = ""
    if TBH.CVarThemeBgImage then raw = TBH.CVarThemeBgImage:GetString() or "" end
    raw = string.Trim(raw)

    if not force and raw == TBH.Theme.bgPath then return end

    TBH.Theme.bgPath = raw
    TBH.Theme.bgMaterial = nil

    if raw == "" then return end

    local candidates = BgImageCandidates(raw)

    for i = 1, #candidates do
        local ok, mat = pcall(Material, candidates[i], "ignorez")
        if ok and mat and not mat:IsError() then
            TBH.Theme.bgMaterial = mat
            TBH.Verbose("Background image loaded via '" .. candidates[i] .. "'")
            return true
        end
    end

    TBH.LogError("Theme background image FAILED to load: '" .. raw ..
        "' - tried: " .. table.concat(candidates, ", "))
    if TBH.NotifyLocally then
        TBH.NotifyLocally("Background image failed to load (see console for the paths tried)", 2, 8)
    end
    return false
end

function TBH.LoadTheme()
    if not CLIENT then return end
    TBH.Verbose("LoadTheme() called")
    if TBH.CVarThemeAccentR and TBH.CVarThemeAccentG and TBH.CVarThemeAccentB then
        local r = math.Clamp(tonumber(TBH.CVarThemeAccentR:GetString()) or 94, 0, 255)
        local g = math.Clamp(tonumber(TBH.CVarThemeAccentG:GetString()) or 168, 0, 255)
        local b = math.Clamp(tonumber(TBH.CVarThemeAccentB:GetString()) or 62, 0, 255)
        TBH.Colors.accent = Color(r, g, b)
        -- recompute dim as a darker shade of the accent (60% darker)
        TBH.Colors.dim = Color(math.floor(r * 0.35), math.floor(g * 0.35), math.floor(b * 0.35))
        -- recompute tag as a brighter shade of the accent (lighter)
        local function lighten(c) return math.min(255, math.floor(c * 1.4)) end
        TBH.Colors.tag = Color(lighten(r), lighten(g), lighten(b))
        TBH.Colors.ok = TBH.Colors.tag
        TBH.Verbose(string.format("LoadTheme accent = (%d, %d, %d)", r, g, b))
    end

    -- background image (V.1.0.4: .png/.jpg/.jpeg loader with candidate
    -- path resolution - see TBH.LoadThemeBackground above)
    TBH.LoadThemeBackground(false)
end

-- Hook convar changes so the theme live-applies as the user adjusts sliders
-- / picks colors in the Settings panel.
--
-- v1.1.8 FIX: We previously used `cvar:AddChangeCallback(fn)` after
-- `GetConVar(name)`. On some clients, `GetConVar` returns a "fake" / proxy
-- ConVar object (most notably when the convar was created via
-- `CreateClientConVar` moments earlier, or in certain GMod engine builds)
-- that does NOT expose the `AddChangeCallback` method - resulting in:
--     attempt to call method 'AddChangeCallback' (a nil value)
-- We now use the GLOBAL `cvars.AddChangeCallback(name, fn)` API, which hooks
-- by name string and is universally safe. Wrapped in pcall so a single bad
-- registration cannot break the rest of the theme system.
--
-- V.1.0.3: every theme convar callback funnels through ONE debounced reload
-- (TBH.QueueThemeReload). The accent picker writes three convars (_r/_g/_b)
-- per drag tick - without the debounce that meant three full LoadTheme +
-- UI-refresh passes for every pixel of mouse movement.
if CLIENT then
    -- V.1.0.3: coalesced theme reload. timer.Create REPLACES the pending
    -- timer, so a burst of convar changes results in exactly ONE reload,
    -- ~0.08s after the last change.
    function TBH.QueueThemeReload()
        timer.Create("TBH.ThemeReload", 0.08, 1, function()
            pcall(function()
                TBH.LoadTheme()
                -- trigger a UI refresh so the new colors paint immediately
                hook.Run("TBH.ClientListChanged")
                -- V.1.0.4: push the new accent into every open browser
                -- (Workshop-page buttons + home page re-theme live)
                if TBH.ApplyBrowserTheme then TBH.ApplyBrowserTheme() end
            end)
        end)
    end

    local function HookThemeConvar(name)
        local ok, err = pcall(cvars.AddChangeCallback, name, function()
            -- cvars.AddChangeCallback fires for ANY change - including the
            -- initial programmatic set; the debounced reload absorbs
            -- duplicate/programmatic fires safely.
            TBH.QueueThemeReload()
        end)
        if not ok then
            -- Non-fatal: theme will still load on the next manual refresh
            if TBH and TBH.LogError then
                TBH.LogError("Theme convar hook failed for " .. tostring(name) .. ": " .. tostring(err))
            end
        end
    end
    -- defer to next tick so the convars created above are registered first
    timer.Simple(0.1, function()
        HookThemeConvar("hotloader_theme_accent_r")
        HookThemeConvar("hotloader_theme_accent_g")
        HookThemeConvar("hotloader_theme_accent_b")
        HookThemeConvar("hotloader_theme_bg")
        HookThemeConvar("hotloader_theme_alpha")
        HookThemeConvar("hotloader_verbose_log")
    end)

    -- initial theme load
    timer.Simple(0.2, TBH.LoadTheme)
end

--------------------------------------------------------------------------------
-- Small shared utilities
--------------------------------------------------------------------------------

local string_find = string.find
local string_match = string.match
local string_gsub = string.gsub
local string_sub = string.sub
local string_gmatch = string.gmatch

function TBH.IsValidWSID(wsid)
    if not isstring(wsid) then return false end
    if #wsid < 6 or #wsid > 15 then return false end
    return string_match(wsid, "^%d+$") ~= nil
end

-- Extracts a workshop id from a raw id, a full workshop URL, or junk text
function TBH.ExtractWSID(input)
    if input == nil then return nil end
    if isnumber(input) then input = tostring(input) end
    if not isstring(input) then return nil end

    input = string_gsub(input, "^%s+", "")
    input = string_gsub(input, "%s+$", "")

    if input == "" then return nil end

    -- plain digits
    if string_match(input, "^%d+$") then
        if TBH.IsValidWSID(input) then return input end
        return nil
    end

    local id = string_match(input, "[?&]id=(%d+)")
    if not id then id = string_match(input, "/(%d+)/?$") end
    if not id then id = string_match(input, "/(%d+)") end

    if id and TBH.IsValidWSID(id) then return id end
    return nil
end

function TBH.WorkshopURL(wsid)
    return "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. tostring(wsid)
end

-- Extracts map names ("gm_construct" from "maps/gm_construct.bsp") from a
-- mounted file list. Capped so a map-pack with 300 maps doesn't explode the
-- net message (300 maps still works, 255 is the UInt8 cap).
function TBH.ExtractMaps(files)
    local maps = {}

    for i = 1, #files do
        local mapname = string_match(files[i], "^maps/([%w_%-%.]+)%.bsp$")

        if mapname then
            maps[#maps + 1] = mapname

            if #maps >= 255 then break end
        end
    end

    return maps
end

-- Console printing helpers
function TBH.Msg(msg, color)
    MsgC(TBH.Colors.tag, "[Hotloader] ", color or TBH.Colors.text, msg .. "\n")
end

function TBH.LogError(msg)
    TBH.Msg(msg, TBH.Colors.error)
end

-- Shared notification + chat message (client realm only does the visuals)
-- duration: seconds the on-screen notification stays (default 6)
function TBH.NotifyLocally(msg, level, duration)
    if SERVER then
        local color = TBH.Colors.text
        if level == 1 then color = TBH.Colors.ok end
        if level == 2 then color = TBH.Colors.error end
        if level == 3 then color = TBH.Colors.warn end
        TBH.Msg(msg, color)
        return
    end

    -- CLIENT
    local ntype = NOTIFY_GENERIC
    if level == 2 then ntype = NOTIFY_ERROR end

    local secs = isnumber(duration) and math.Clamp(duration, 1, 30) or 6

    notification.AddLegacy("[Hotloader] " .. msg, ntype, secs)
    MsgC(TBH.Colors.tag, "[Hotloader] ", TBH.Colors.text, msg .. "\n")

    if level == 1 then surface.PlaySound("buttons/bell1.wav") end
    if level == 2 then surface.PlaySound("buttons/button10.wav") end

    -- keep a rolling log for the spawnmenu activity feed
    TBH.StatusLog = TBH.StatusLog or {}
    TBH.StatusLog[#TBH.StatusLog + 1] = { msg = msg, level = level or 0 }

    if #TBH.StatusLog > 40 then
        table.remove(TBH.StatusLog, 1)
    end

    hook.Run("TBH.StatusLogged", msg, level)
end

--------------------------------------------------------------------------------
-- COLLECTION CRASH DIAGNOSTICS (v1.1.1)
--
-- Hotloading a collection writes a step-by-step trace to a txt file so a
-- freeze/crash can be diagnosed AFTER the fact: when the game hard-crashes
-- there is no Lua error to catch - but the last line already on disk shows
-- exactly what was running when it died.
--
--   * Logging is OFF for normal (single addon) hotloads - it only switches
--     on when a collection hotload is detected.
--   * CLIENT writes: garrysmod/data/hotloader_crash_log_client.txt
--   * SERVER writes: garrysmod/data/hotloader_crash_log_server.txt
--     (on a listen server both files appear in the same data folder;
--     on a dedicated server the _server file is on the server box)
--   * Every line is appended + the file closed IMMEDIATELY, so a hard
--     crash can lose at most the single line being written.
--   * SysTime() keeps ticking during a main-thread freeze, so the elapsed
--     timestamps expose WHERE the freeze actually happened: a big gap
--     between two lines = the frozen step.
--   * The logger itself is fully guarded - it can never break a hotload.
--------------------------------------------------------------------------------

TBH.DiagState = {
    Active = false,
    StartedAt = nil,
    CollectionConfirmed = false,
    RequestedWSID = nil,
    VerboseBannerWritten = false, -- V.1.0.1: tracks whether the verbose banner has been written this session
    Path = SERVER and "hotloader_crash_log_server.txt" or "hotloader_crash_log_client.txt",
}

-- Workshop dupes and saves download as .dupe / .sav files, not GMA addons, so
-- game.MountGMA throws "addon header invalid" at them. This looks at the file
-- before we try to mount it and returns a short human reason when it is not
-- an addon (nil means "looks fine, go ahead").
function TBH.WhyNotAnAddon(path)
    if not isstring(path) then return nil end

    local ext = string.lower(string.match(path, "%.(%w+)$") or "")

    if ext == "dupe" then
        return "that workshop item is a DUPE, not an addon. Subscribe to it on Steam and it will show up in your Dupes tab."
    elseif ext == "sav" then
        return "that workshop item is a SAVE, not an addon. Subscribe to it on Steam and it will show up in your Saves tab."
    end

    -- peek at the header too, real addons always start with "GMAD"
    local f = file.Open(path, "rb", "GAME")
    if f then
        local head = f:Read(4)
        f:Close()

        if isstring(head) and #head == 4 and head ~= "GMAD" then
            return "that workshop item isn't a GMA addon file (bad header), so it can't be hotloaded."
        end
    end

    return nil
end

function TBH.DiagStart(reason)
    if TBH.DiagState.Active then
        return TBH.Diag("(continuing the running log session: " .. tostring(reason) .. ")")
    end

    -- v1.1.2: a previous log that never got an "ended" line is CRASH
    -- EVIDENCE - preserve it instead of overwriting it with this attempt
    pcall(function()
        if file.Exists(TBH.DiagState.Path, "DATA") then
            local prev = file.Read(TBH.DiagState.Path, "DATA")

            if isstring(prev) and prev ~= "" and not string_find(prev, "diagnostics ended", 1, true) then
                local keep = "hotloader_crash_log_" .. (SERVER and "server" or "client") .. "_crashed_" .. os.time() .. ".txt"
                file.Write(keep, prev)
                TBH.Msg("Preserved an unfinished crash log -> garrysmod/data/" .. keep .. " (the last attempt never finished - it probably crashed!)", TBH.Colors.warn)
            end
        end
    end)

    TBH.DiagState.Active = true
    TBH.DiagState.StartedAt = SysTime()
    TBH.DiagState.CollectionConfirmed = false
    TBH.DiagState.RequestedWSID = nil

    local opened = false

    local ok = pcall(function()
        -- fresh file per attempt
        file.Delete(TBH.DiagState.Path)

        local f = file.Open(TBH.DiagState.Path, "w", "DATA")
        if f then
            opened = true
            f:Write("==============================================================\n")
            f:Write("HOTLOADER v" .. TBH.Version .. " COLLECTION CRASH LOG\n")
            f:Write("Realm: " .. (SERVER and "SERVER" or "CLIENT") .. " | Map: " .. game.GetMap() .. "\n")
            f:Write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(reason) .. "\n")
            f:Write("If the game crashed, the LAST lines show what was running.\n")
            f:Write("Big jumps in [+X.XXXs] elapsed time = frozen main thread.\n")
            f:Write("==============================================================\n")
            f:Close()
        end
    end)

    if not ok or not opened then
        TBH.DiagState.Active = false
        TBH.Msg("COULD NOT CREATE the crash log file garrysmod/data/" .. TBH.DiagState.Path .. " - txt file writing is blocked?!", TBH.Colors.error)
        return
    end

    TBH.Diag("diagnostics started: " .. tostring(reason))
end

function TBH.Diag(msg)
    if not TBH.DiagState.Active then return end

    -- never let the logger itself throw inside a hotload path
    pcall(function()
        local elapsed = SysTime() - (TBH.DiagState.StartedAt or SysTime())

        local line = string.format("[%s][+%.3fs] %s",
            SERVER and "SERVER" or "CLIENT", elapsed, tostring(msg))

        MsgC(TBH.Colors.info, "[HotloaderDiag] ", TBH.Colors.text, line .. "\n")

        local f = file.Open(TBH.DiagState.Path, "a", "DATA")
        if f then
            f:Write(line .. "\n")
            f:Close()
        end
    end)
end

function TBH.DiagEnd(reason)
    if not TBH.DiagState.Active then return end

    TBH.Diag("diagnostics ended: " .. tostring(reason))
    TBH.DiagState.Active = false
end

--------------------------------------------------------------------------------
-- V.1.0.1: TBH.Verbose(msg)
--
-- "Extreme" debug logging, gated by the `hotloader_verbose_log` convar (OFF by
-- default). When ON, every Verbose() call writes a timestamped line to the
-- SAME crash-log .txt file that TBH.Diag uses
-- (garrysmod/data/hotloader_crash_log_client.txt or *_server.txt).
--
-- Difference from TBH.Diag:
--   * TBH.Diag   - active only during collection hotloads (DiagStart opens
--                  the file, DiagEnd closes it). Lightly verbose.
--   * TBH.Verbose - active whenever hotloader_verbose_log is on. Writes even when
--                  no Diag session is open (opens the file in append mode,
--                  writes the line, closes it). WAY more granular - intended
--                  for "I'm chasing a bug" debugging, not normal use.
--
-- Verbose calls are placed at hot points where Diag is too coarse:
--   * every file processed during a bundle init
--   * every net message received/sent
--   * every theme reload
--   * every spawnmenu refresh queue tick
--   * every mount step
--
-- When verbose is OFF (default), this is a no-op - zero file I/O, zero
-- string formatting, returns immediately. Safe to leave the Verbose calls
-- in production.
--------------------------------------------------------------------------------
function TBH.Verbose(msg)
    -- Hot path - check the convar FIRST so we're a no-op when off.
    if not (TBH.CVarVerboseLog and TBH.CVarVerboseLog:GetBool()) then return end

    -- Never let the verbose logger itself throw inside a hot path.
    pcall(function()
        local elapsed = SysTime() - (TBH.DiagState.StartedAt or SysTime())
        local line = string.format("[VERBOSE][%s][+%.3fs] %s",
            SERVER and "SERVER" or "CLIENT", elapsed, tostring(msg))

        -- If a Diag session is open, just append to it (cheaper - file is
        -- already open, well, we re-open in append mode which is fine on
        -- GMod's file layer since each Write is its own line).
        local f = file.Open(TBH.DiagState.Path, "a", "DATA")
        if f then
            if not TBH.DiagState.Active then
                -- Standalone verbose - prepend a header so the file isn't
                -- confusing when opened cold (no DiagStart banner above).
                -- We only do this once per session of verbose - tracked
                -- by a flag on DiagState.
                if not TBH.DiagState.VerboseBannerWritten then
                    f:Write("==============================================================\n")
                    f:Write("HOTLOADER V." .. TBH.Version .. " VERBOSE DEBUG LOG\n")
                    f:Write("Realm: " .. (SERVER and "SERVER" or "CLIENT") .. " | Map: " .. game.GetMap() .. "\n")
                    f:Write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
                    f:Write("NOTE: hotloader_verbose_log is ON. This file gets BIG. Turn it\n")
                    f:Write("off in Utilities > Settings & Info when you're done.\n")
                    f:Write("==============================================================\n")
                    TBH.DiagState.VerboseBannerWritten = true
                end
            end
            f:Write(line .. "\n")
            f:Close()
        end
    end)
end

-- When verbose is toggled OFF after being on, reset the banner flag so the
-- next time it's turned back on, we get a fresh banner.
if CLIENT then
    cvars.AddChangeCallback("hotloader_verbose_log", function()
        TBH.DiagState.VerboseBannerWritten = false
    end)
end

-- v1.1.2: if the request never resolves into a collection, the log file is
-- removed again after a grace period (normal single-addon hotloads keep no
-- files) - but if the game crashes inside the window, the file survives and
-- the next attempt preserves it as *_crashed_*.txt evidence.
function TBH.DiagAutoCleanup(delay)
    timer.Create("TBH.DiagCleanup", math.Clamp(delay or 30, 5, 600), 1, function()
        if TBH.DiagState.CollectionConfirmed then
            return TBH.Diag("[diag] collection confirmed - keeping the crash log file")
        end

        if TBH.DiagState.Active then
            TBH.Diag("[diag] the request did not resolve as a collection - closing and removing the log file")
            TBH.DiagEnd("non-collection request (auto cleanup)")
        end

        pcall(file.Delete, TBH.DiagState.Path)
    end)
end

--------------------------------------------------------------------------------
-- hotloader_diagtest: verify that txt file writing works WITHOUT hotloading
-- anything. Run this in console after installing the file - if the test
-- file does not appear, file writing itself is broken on this setup.
-- NEVER touches the real crash logs (they are evidence).
--------------------------------------------------------------------------------

concommand.Add("hotloader_diagtest", function(ply)
    local testPath = "hotloader_crash_log_test.txt"

    -- never overwrite an existing crash log - it may be evidence
    if file.Exists(TBH.DiagState.Path, "DATA") and not TBH.DiagState.Active then
        TBH.Msg("KEEPING the existing garrysmod/data/" .. TBH.DiagState.Path .. " untouched (possible crash evidence from your last attempt).", TBH.Colors.warn)
        if CLIENT then
            TBH.NotifyLocally("Existing crash log found and preserved - check garrysmod/data/" .. TBH.DiagState.Path, 3, 8)
        end
    end

    local f = file.Open(testPath, "w", "DATA")

    if not f then
        TBH.Msg("FAILED to write garrysmod/data/" .. testPath .. " - txt file writing is BROKEN in this game/server!", TBH.Colors.error)
        if CLIENT then
            TBH.NotifyLocally("Crash-log self-test FAILED - this game cannot write txt files?!", 2, 8)
        end
        return
    end

    f:Write("HOTLOADER v" .. TBH.Version .. " crash-log self-test (" .. (SERVER and "SERVER" or "CLIENT") .. " realm)\n")
    f:Write("Time: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    f:Write("If you can read this, txt file writing works. The real crash logs go to:\n")
    f:Write("  garrysmod/data/hotloader_crash_log_client.txt  (your game)\n")
    f:Write("  garrysmod/data/hotloader_crash_log_server.txt  (the server / listen host)\n")
    f:Write("Crash-interrupted logs are preserved as hotloader_crash_log_*_crashed_<time>.txt\n")
    f:Close()

    TBH.Msg("Self-test OK - wrote garrysmod/data/" .. testPath .. " (the collection crash logs will appear in the same folder)", TBH.Colors.ok)
    if CLIENT then
        TBH.NotifyLocally("Crash-log self-test OK - see garrysmod/data/" .. testPath, 1, 8)
    end
end)

--------------------------------------------------------------------------------
-- ConVars
--------------------------------------------------------------------------------

local function GetOrCreateConVar(name, default, flags, help)
    if SERVER then
        return GetConVar(name) or CreateConVar(name, default, flags or { FCVAR_ARCHIVE, FCVAR_NOTIFY }, help or "")
    end
    return GetConVar(name) or CreateClientConVar(name, default, true, false, help or "")
end

-- Server settings (server-side archive convars)
-- (v1.1.9) hotloader_permission was removed: every player can hotload anything
TBH.CVarRequirements = SERVER and (GetConVar("hotloader_requirements") or CreateConVar("hotloader_requirements", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Automatically hotload an addon's Required Items")) or nil
TBH.CVarMaxFiles    = SERVER and (GetConVar("hotloader_max_files") or CreateConVar("hotloader_max_files", "20000", { FCVAR_ARCHIVE }, "Maximum files per hotloaded addon")) or nil
TBH.CVarTimeout     = SERVER and (GetConVar("hotloader_timeout") or CreateConVar("hotloader_timeout", "180", { FCVAR_ARCHIVE }, "Download watchdog timeout in seconds")) or nil
TBH.CVarCooldown    = SERVER and (GetConVar("hotloader_cooldown") or CreateConVar("hotloader_cooldown", "10", { FCVAR_ARCHIVE }, "Per-player hotload request cooldown in seconds")) or nil
TBH.CVarMaxQueue    = SERVER and (GetConVar("hotloader_max_queue") or CreateConVar("hotloader_max_queue", "10", { FCVAR_ARCHIVE }, "Maximum queued hotloads")) or nil
TBH.CVarLateSync    = SERVER and (GetConVar("hotloader_latesync") or CreateConVar("hotloader_latesync", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Sync hotloaded addons to players who join later")) or nil
TBH.CVarAnnounce    = SERVER and (GetConVar("hotloader_announce") or CreateConVar("hotloader_announce", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Chat announcements when addons get hotloaded")) or nil
TBH.CVarCleanupEmpty = SERVER and (GetConVar("hotloader_cleanup_on_empty") or CreateConVar("hotloader_cleanup_on_empty", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Wipe the hotload session registry when the last player leaves, so a new session starts completely clean")) or nil
TBH.CVarMaxCollection = SERVER and (GetConVar("hotloader_max_collection") or CreateConVar("hotloader_max_collection", "15", { FCVAR_ARCHIVE }, "Maximum addons hotloaded at once from a single Workshop collection")) or nil
TBH.CVarBatchDelay = SERVER and (GetConVar("hotloader_batch_delay") or CreateConVar("hotloader_batch_delay", "3", { FCVAR_ARCHIVE }, "Seconds between addons when a batch/collection is hotloading (stability pacing)")) or nil

--------------------------------------------------------------------------------
-- Debounced spawnmenu refresh (CLIENT)
--
-- Every bundle init used to schedule its own spawnmenu_reload. A collection
-- hotload of N addons = N FULL spawnmenu rebuilds in quick succession, each
-- recreating the DHTML/CEF browser tab - a classic GMod crash vector.
-- One shared, self-resetting timer = exactly ONE rebuild after the batch
-- settles, no matter how many addons initialized. The reload additionally
-- WAITS until the client sync queue is completely idle - never rebuilds
-- the menu while addons are still mounting.
--------------------------------------------------------------------------------

if CLIENT then
    function TBH.QueueSpawnMenuRefresh(delay)
        delay = math.Clamp(isnumber(delay) and delay or 3, 1, 15)

        timer.Create("TBH.SpawnMenuRefresh", delay, 1, function()
            -- still syncing a batch? wait for it to drain, then rebuild once
            -- (v1.1.0: Busy now also spans the frame-spread initialization,
            -- so the menu never rebuilds while an addon is still loading)
            if TBH.Client and (TBH.Client.Busy or #TBH.Client.Queue > 0) then
                TBH.QueueSpawnMenuRefresh(2)
                return
            end

            -- a host-routed download is mid-flight (module-less listen
            -- server)? its bundle init is still running - wait it out
            if TBH.Client and TBH.Client.HostLoading ~= nil then
                TBH.QueueSpawnMenuRefresh(2)
                return
            end

            -- a collection batch is still running on the server? wait for
            -- it to finish entirely - ONE reload for the whole collection
            if TBH.Client.Batch and TBH.Client.Batch.active then
                TBH.QueueSpawnMenuRefresh(2)
                return
            end

            TBH.Diag("spawnmenu_reload EXECUTING (menu rebuild - classic CEF crash point)")
            TBH.RepairTabsAfterReload = true
            RunConsoleCommand("spawnmenu_reload")
        end)
    end
end

-- Client settings
if CLIENT then
    TBH.CVarHints = GetOrCreateConVar("hotloader_hints", "1", nil, "Show Hotloader welcome hints")
    TBH.CVarLogs  = GetOrCreateConVar("hotloader_logs", "0", nil, "Verbose hotload logs in console")
    TBH.CVarAutoSubscribe = GetOrCreateConVar("hotloader_autosubscribe", "1", nil, "Subscribing to a new Workshop addon in-game automatically requests a hotload")
    TBH.CVarEnableAddons = GetOrCreateConVar("hotloader_enableaddons", "1", nil, "Enabling a disabled addon from the Addons menu automatically requests a hotload (the addon is already downloaded, so this is fast)")

    -- V.1.0.1: theme + verbose-log settings (Utilities -> Settings & Info)
    -- Default colors mirror the neon-dark-green theme defined in TBH.Colors.
    --
    -- V.1.0.2 FIX (the crash you just hit): GMod's `panel:ColorPicker(label,
    -- convar, false)` treats `convar` as a PREFIX and creates THREE separate
    -- convars `<convar>_r`, `<convar>_g`, `<convar>_b` internally via the
    -- DColorMixer:SetConVarR/G/B methods. V.1.0.1 wrongly tried to use a
    -- SINGLE `hotloader_theme_accent` convar (with "R G B" string) - the picker
    -- then called SetConVarR("hotloader_theme_accent_r") on a non-existent convar,
    -- GetConVar returned nil, Color(nil,...) crashed the mixer.
    -- We now create the 3 separate _r/_g/_b convars the picker needs.
    TBH.CVarThemeAccentR = GetOrCreateConVar("hotloader_theme_accent_r", "94",  nil, "Theme accent color red (0-255) - used by GMod's ColorPicker")
    TBH.CVarThemeAccentG = GetOrCreateConVar("hotloader_theme_accent_g", "168", nil, "Theme accent color green (0-255) - used by GMod's ColorPicker")
    TBH.CVarThemeAccentB = GetOrCreateConVar("hotloader_theme_accent_b", "62",  nil, "Theme accent color blue (0-255) - used by GMod's ColorPicker")
    TBH.CVarThemeBgImage = GetOrCreateConVar("hotloader_theme_bg", "", nil, "Optional background image - a path garrysmod can Material() (e.g. 'materials/hotloader/mybg.vmt' or '../data/hotloader_bg.png'). Empty = no background image.")
    TBH.CVarThemeAlpha   = GetOrCreateConVar("hotloader_theme_alpha", "100", nil, "Background image transparency (0 = invisible, 255 = fully opaque)")

    -- V.1.0.1: Verbose Debug Logging - writes more extreme diagnostics to
    -- the existing crash-log .txt file. OFF by default (only needed when
    -- debugging a hotload that isn't behaving).
    TBH.CVarVerboseLog = GetOrCreateConVar("hotloader_verbose_log", "0", nil, "Verbose debug logging - writes more granular diagnostics to the same crash-log .txt file. OFF by default.")
end

--------------------------------------------------------------------------------
-- Net layer
-- All traffic rides a single network string with a sub-message name header.
--------------------------------------------------------------------------------

TBH.Net = { Receivers = {} }

if SERVER then
    util.AddNetworkString(TBH.NetString)
end

net.Receive(TBH.NetString, function(len, ply)
    local name = net.ReadString()
    TBH.Verbose("net.Receive '" .. tostring(name) .. "' from " .. tostring(IsValid(ply) and ply or "console") .. " (" .. tostring(len) .. " bits)")
    local receiver = TBH.Net.Receivers[name]
    if receiver then
        local ok, err = pcall(receiver, len, ply)
        if not ok then
            ErrorNoHalt("[Hotloader] net receiver '" .. tostring(name) .. "' failed: " .. tostring(err) .. "\n")
            TBH.Verbose("net.Receive '" .. tostring(name) .. "' HANDLER FAILED: " .. tostring(err))
        end
    else
        TBH.Verbose("net.Receive UNKNOWN receiver '" .. tostring(name) .. "' - ignored")
    end
end)

function TBH.Net:Receive(name, callback)
    self.Receivers[name] = callback
end

function TBH.Net:Start(name)
    net.Start(TBH.NetString)
    net.WriteString(name)
end

--------------------------------------------------------------------------------
-- gmsv_workshop module detection (SERVER realm only)
--
-- The gmsv_workshop module (by WilliamVenner) gives DEDICATED servers the
-- steamworks.DownloadUGC + steamworks.FileInfo functions. It is loaded with
-- require("workshop") which looks for gmsv_workshop_<arch>.dll in
-- garrysmod/lua/bin (win32/win64/linux/linux64 builds exist).
--
-- Clients and listen servers can always download natively.
--------------------------------------------------------------------------------

if SERVER then
    TBH.ServerCanUGC = (steamworks ~= nil and isfunction(steamworks.DownloadUGC))

    -- calling require("workshop") with no dll installed makes the engine print
    -- "Couldn't include file includes\modules\workshop.lua" even inside a pcall,
    -- so only require it when the binary is really there
    local function BinaryModuleInstalled(name)
        if util and isfunction(util.IsBinaryModuleInstalled) then
            local okI, res = pcall(util.IsBinaryModuleInstalled, name)
            if okI then return res == true end
        end

        -- fallback: probe the DLL names directly
        local suffixes = { "win32", "win64", "linux", "linux64", "osx", "osx64" }
        for i = 1, #suffixes do
            if file.Exists("lua/bin/gmsv_" .. name .. "_" .. suffixes[i] .. ".dll", "MOD")
                or file.Exists("lua/bin/gmsv_" .. name .. "_" .. suffixes[i] .. ".dll", "GAME") then
                return true
            end
        end

        return false
    end

    TBH.BinaryModuleInstalled = BinaryModuleInstalled

    if not TBH.ServerCanUGC then
        if BinaryModuleInstalled("workshop") then
            local ok = pcall(require, "workshop")
            TBH.ServerCanUGC = ok and steamworks ~= nil and isfunction(steamworks.DownloadUGC)
        else
            TBH.ServerCanUGC = false
        end

        TBH.ModuleRequired = not TBH.ServerCanUGC -- remember that we tried and failed
    end

    TBH.ServerCanFileInfo = (steamworks ~= nil and isfunction(steamworks.FileInfo))
end

--------------------------------------------------------------------------------
-- V.1.0.6: gmaunmount module detection (FULL unload support)
--
-- GMod has game.MountGMA but NO unmount counterpart in Lua - the mounted
-- files stay until a restart (the README has said so since v1.0). The
-- optional gmaunmount binary module (gmsv_gmaunmount_win64.dll, Rust)
-- closes that gap by removing the GMA's search path from the engine
-- filesystem:
--
--   gmaunmount.Unmount("<full path to the .gma>")  -> true/false
--
-- It is 100% OPTIONAL - without it everything works exactly like before
-- (soft unload only). With it, "FULL unload" additionally unmounts the
-- addon's FILES on the server (and on any client that installed the
-- client copy of the module, gmcl_gmaunmount_win64.dll).
--
-- require() resolves by name: gmsv_gmaunmount_win64.dll in
-- garrysmod/lua/bin (server realm). Clients use the same DLL renamed to
-- gmcl_gmaunmount_win64.dll.
--------------------------------------------------------------------------------

-- V.1.0.8: returns ok, errString - the ACTUAL require() error is kept and
-- surfaced in the diagnostics commands, so a module that fails to load
-- says WHY instead of a silent generic "not loaded".

-- Safe detection (never calls require() on a DLL that is not installed, so
-- there is no engine error spam).
function TBH.DetectGmaUnmountModule()
    if gmaunmount ~= nil and isfunction(gmaunmount.Unmount) then
        return true
    end

    local realm = SERVER and "gmsv" or "gmcl"
    local installed = false

    if util and isfunction(util.IsBinaryModuleInstalled) then
        local okI, res = pcall(util.IsBinaryModuleInstalled, "gmaunmount")
        installed = okI and res == true
    end

    if not installed then
        return false, "module not installed (" .. realm .. "_gmaunmount_win64.dll in garrysmod/lua/bin)"
    end

    package.loaded["gmaunmount"] = nil
    local ok, err = pcall(require, "gmaunmount")

    if ok and gmaunmount ~= nil and isfunction(gmaunmount.Unmount) then
        return true
    end

    return false, tostring(err)
end

function TBH.ProbeGmaUnmount()
    local ok = TBH.DetectGmaUnmountModule()
    return ok == true
end

-- hotloader_unmountdiag: what the FULL Unload module sees (paste this when reporting a problem)
concommand.Add("hotloader_unmountdiag", function(ply)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end

    local ok, err = TBH.DetectGmaUnmountModule()
    local realm = SERVER and "SERVER" or "CLIENT"

    if ok then
        MsgN("[Hotloader] " .. realm .. " gmaunmount module loaded:")
        MsgN(gmaunmount.Diag())
    else
        MsgN("[Hotloader] " .. realm .. " gmaunmount module NOT loaded: " .. tostring(err))
    end
end)


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  BUNDLE SYSTEM
--
--  A "bundle" is one hotloaded addon (or a group of requirement addons).
--  It re-implements what the engine does at boot, but mid-game:
--
--    * Runs lua/autorun, lua/autorun/server, lua/autorun/client
--    * Registers ENT / SWEP / EFFECT / PANEL classes
--    * Registers toolgun STOOLs into gmod_tool (and player toolguns)
--    * Simulates gamemode lifecycle hooks (Initialize, InitPostEntity, ...)
--    * Fakes "no players/entities yet" during init like a fresh boot
--    * Sandboxes hook/timer/include/require/AddCSLuaFile/module so the
--      bundle can be tracked, and so re-loads do not fight each other
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

do
    local Bundle = {}
    Bundle.__index = Bundle
    TBH.Bundle = Bundle

    local file_Read = file.Read
    local isLinux = system.IsLinux()

    local BundleCounter = 0

    local ClassTypes = {
        entities = { Global = "ENT", Table = scripted_ents, Count = 2 },
        weapons  = { Global = "SWEP", Table = weapons, Count = 3 },
    }

    if CLIENT then
        ClassTypes.effects = { Global = "EFFECT", Table = effects, Count = 2 }
        ClassTypes.vgui    = { Global = "PANEL", Table = vgui, Count = 2 }
    end

    local function IsClientClassType(typename)
        return typename == "vgui" or typename == "effects"
    end

    ------------------------------------------------------------------------
    -- Hook tracking
    ------------------------------------------------------------------------

    function Bundle:GIDHook(event, identifier)
        return "TBH." .. tostring(self.ID) .. "." .. event .. "." .. tostring(identifier)
    end

    function Bundle:AddHook(event, identifier, callback)
        local ev = self.Hooks[event]
        if not ev then
            ev = {}
            self.Hooks[event] = ev
        end

        ev[identifier] = callback

        local gid = self:GIDHook(event, identifier)
        self.HookGIDs[event .. "\1" .. tostring(identifier)] = gid

        local registered = callback

        -- the real hook lib lets you use a table or entity as the identifier (it gets
        -- passed as arg 1 and the hook dies when it goes invalid). we used to just
        -- drop those hooks silently, which broke some addons
        if not isstring(identifier) then
            local bundle = self
            registered = function(...)
                if not IsValid(identifier) then
                    bundle:RemoveHook(event, identifier)
                    return
                end
                return callback(identifier, ...)
            end
        end

        -- same idea for the every-frame hooks: on a normal boot none of them run
        -- until the addon is completely loaded, so keep them quiet during init
        if TBH.FrameHooks[event] then
            local inner, bundle = registered, self
            registered = function(...)
                if not bundle.InitFinished then return end
                return inner(...)
            end
        end

        hook.Add(event, gid, registered)
    end

    function Bundle:RemoveHook(event, identifier)
        local key = event .. "\1" .. tostring(identifier)
        local gid = self.HookGIDs[key]

        if gid then
            hook.Remove(event, gid)
            self.HookGIDs[key] = nil
        end

        if self.Hooks[event] then
            self.Hooks[event][identifier] = nil
        end
    end

    function Bundle:CallHooks(event, ...)
        local ev = self.Hooks[event]
        if not ev then return end

        for identifier, callback in pairs(ev) do
            local ok, err
            if isstring(identifier) then
                ok, err = pcall(callback, ...)
            else
                ok, err = pcall(callback, identifier, ...)
            end
            if not ok then
                self:Error("hook '" .. tostring(event) .. "' [" .. tostring(identifier) .. "]: " .. tostring(err))
            end
        end
    end

    ------------------------------------------------------------------------
    -- Timer tracking (namespaced so bundles cannot nuke foreign timers)
    ------------------------------------------------------------------------

    function Bundle:TimerGID(name)
        return "TBH." .. tostring(self.ID) .. ".timer." .. tostring(name)
    end

    ------------------------------------------------------------------------
    -- The sandboxed environment
    ------------------------------------------------------------------------

    function Bundle:BuildEnvironment()
        local bundle = self
        local env = {}

        ----------------------------------------------------------------
        -- hook sandbox
        ----------------------------------------------------------------
        local hookSandbox = setmetatable({}, { __index = hook })

        function hookSandbox.Add(event, identifier, callback, ...)
            if not isstring(event) or identifier == nil then return end
            if callback == nil then return bundle:RemoveHook(event, identifier) end
            if not isfunction(callback) then return end
            bundle:AddHook(event, identifier, callback)
        end

        function hookSandbox.Remove(event, identifier, ...)
            if not isstring(event) or identifier == nil then return end
            bundle:RemoveHook(event, identifier)
        end

        function hookSandbox.GetTable()
            -- merged view: real table plus this bundle's entries under
            -- their original identifiers
            local real = hook.GetTable()
            local merged = {}

            for event, tab in pairs(real) do
                local copy = {}
                for id, fn in pairs(tab) do copy[id] = fn end
                merged[event] = copy
            end

            for event, tab in pairs(bundle.Hooks) do
                if not merged[event] then merged[event] = {} end
                for id, fn in pairs(tab) do
                    merged[event][id] = fn
                end
            end

            return merged
        end

        env.hook = hookSandbox

        ----------------------------------------------------------------
        -- timer sandbox
        ----------------------------------------------------------------
        local timerSandbox = setmetatable({}, { __index = timer })

        -- on a normal boot the whole addon loads inside one frame, so a
        -- timer.Simple(0, ...) in an early file only fires once EVERYTHING is
        -- loaded. our init is spread over many frames, so those timers would fire
        -- half way through (wiremod's e2descriptions hit this: E2 wasnt loaded yet
        -- -> "bad argument #1 to pairs"). so timers made while our init steps run
        -- are held back and started the moment init is finished.
        local function HoldTimers()
            return bundle.InitActive == true and not bundle.InitFinished
        end

        function timerSandbox.Simple(delay, func)
            if HoldTimers() and isfunction(func) then
                bundle.HeldTimers[#bundle.HeldTimers + 1] = function()
                    timer.Simple(delay, func)
                end
                return
            end
            return timer.Simple(delay, func)
        end

        function timerSandbox.Create(name, delay, reps, func, ...)
            if name == nil then return timer.Create(name, delay, reps, func, ...) end

            if HoldTimers() and isfunction(func) then
                local entry = { name = tostring(name) }
                entry.start = function()
                    local gid = bundle:TimerGID(name)
                    bundle.Timers[tostring(name)] = gid
                    timer.Create(gid, delay, reps, func)
                end
                bundle.HeldTimers[#bundle.HeldTimers + 1] = entry
                bundle.HeldByName[tostring(name)] = entry
                return
            end

            local gid = bundle:TimerGID(name)
            bundle.Timers[tostring(name)] = gid
            return timer.Create(gid, delay, reps, func, ...)
        end

        function timerSandbox.Remove(name)
            local held = bundle.HeldByName[tostring(name)]
            if held then
                held.cancelled = true
                bundle.HeldByName[tostring(name)] = nil
                return
            end

            local gid = bundle.Timers[tostring(name)]
            if gid then
                timer.Remove(gid)
                bundle.Timers[tostring(name)] = nil
                return
            end
            return timer.Remove(name)
        end

        function timerSandbox.Exists(name)
            local gid = bundle.Timers[tostring(name)]
            if gid and timer.Exists(gid) then return true end
            return timer.Exists(name)
        end

        env.timer = timerSandbox

        ----------------------------------------------------------------
        -- registration tracking: remember what the addon puts into the
        -- spawnmenu lists (NPCs, vehicles, weapons, ...), console commands,
        -- net receivers, convar callbacks and context-menu properties, so
        -- FULL Unload can take every one of them back out
        ----------------------------------------------------------------
        bundle.ListKeys, bundle.ListValues = bundle.ListKeys or {}, bundle.ListValues or {}
        bundle.ConCommands, bundle.NetNames = bundle.ConCommands or {}, bundle.NetNames or {}
        bundle.CVarCallbacks, bundle.PropertyNames = bundle.CVarCallbacks or {}, bundle.PropertyNames or {}

        local listSandbox = setmetatable({}, { __index = list })

        function listSandbox.Set(name, key, value)
            bundle.ListKeys[#bundle.ListKeys + 1] = { name, key }
            return list.Set(name, key, value)
        end

        function listSandbox.Add(name, value)
            bundle.ListValues[#bundle.ListValues + 1] = { name, value }
            return list.Add(name, value)
        end

        env.list = listSandbox

        local concommandSandbox = setmetatable({}, { __index = concommand })

        function concommandSandbox.Add(name, ...)
            if isstring(name) then bundle.ConCommands[#bundle.ConCommands + 1] = name end
            return concommand.Add(name, ...)
        end

        env.concommand = concommandSandbox

        local netSandbox = setmetatable({}, { __index = net })

        function netSandbox.Receive(name, ...)
            if isstring(name) then bundle.NetNames[#bundle.NetNames + 1] = name end
            return net.Receive(name, ...)
        end

        env.net = netSandbox

        local cvarsSandbox = setmetatable({}, { __index = cvars })

        function cvarsSandbox.AddChangeCallback(name, fn, id)
            bundle.CVarCallbacks[#bundle.CVarCallbacks + 1] = { name, id }
            return cvars.AddChangeCallback(name, fn, id)
        end

        env.cvars = cvarsSandbox

        if properties then
            local propertiesSandbox = setmetatable({}, { __index = properties })

            function propertiesSandbox.Add(name, tab)
                if isstring(name) then bundle.PropertyNames[#bundle.PropertyNames + 1] = name end
                return properties.Add(name, tab)
            end

            env.properties = propertiesSandbox
        end

        ----------------------------------------------------------------
        -- include / AddCSLuaFile / CompileFile / require / module
        ----------------------------------------------------------------
        env.include = function(path)
            -- note: do NOT tail-call - getfenv() cannot walk through tail
            -- call frames and Bundle:Include inspects the call stack
            local result = bundle:Include(path)
            return result
        end

        env.IncludeCS = function(path)
            if SERVER then
                bundle:AddCSLuaFileSandboxed(path)
            end
            local result = bundle:Include(path)
            return result
        end

        env.AddCSLuaFile = function(path, ...)
            bundle:AddCSLuaFileSandboxed(path)
        end

        env.CompileFile = function(path)
            local result = bundle:CompileFileSandboxed(path)
            return result
        end

        env.require = function(name, ...)
            local modpath = "includes/modules/" .. tostring(name) .. ".lua"
            local body = file_Read(modpath, "LUA") or file_Read("lua/" .. modpath, "GAME")

            if body then
                return bundle:InitializeFile(modpath)
            end

            return _G.require(name, ...)
        end

        env.module = function(name, ...)
            local callingEnv = getfenv(2)
            local moduleEnv = { TBH_IsModule = true }

            local hasSeeAll = false
            local loaders = { ... }
            for i = 1, #loaders do
                if loaders[i] == package.seeall then
                    hasSeeAll = true
                    break
                end
            end

            local M = _G[name]
            M = (istable(M) and M) or {}

            setmetatable(moduleEnv, {
                __index = function(_, key)
                    if hasSeeAll and callingEnv[key] ~= nil then
                        return callingEnv[key]
                    end
                    return M[key]
                end,
                __newindex = function(_, key, value)
                    M[key] = value
                end,
            })

            setfenv(2, moduleEnv)
            _G[name] = M
        end

        ----------------------------------------------------------------
        -- "Fresh boot" fakes until InitPostEntity is simulated.
        -- Many addons cache players/entities at load time and expect a
        -- fresh world; give them the boot-time view.
        ----------------------------------------------------------------
        -- the fake "fresh boot" values used to stay on for the whole init, which for
        -- big addons is many seconds. every hook the addon had already added (CreateMove,
        -- Think, HUDPaint...) then saw LocalPlayer() == NULL between steps, thats the
        -- GetActiveWeapon spam you got with ARC9. now they only apply while one of our
        -- own init steps is actually running
        local function FakeActive()
            return bundle.InitActive == true and not bundle.InitPostEntity
        end

        local function PostInitFake(func, retval)
            return function(...)
                if FakeActive() then
                    if retval == "emptytable" then return {} end
                    return retval
                end
                return func(...)
            end
        end

        if CLIENT then
            local realEntity = Entity

            env.Player = PostInitFake(Player, NULL)
            env.LocalPlayer = PostInitFake(LocalPlayer, NULL)

            env.Entity = function(...)
                if not FakeActive() then return realEntity(...) end
                local ent = realEntity(...)
                if IsValid(ent) and ent:IsPlayer() then return NULL end
                return ent
            end

            local playerSandbox = setmetatable({
                GetAll         = PostInitFake(player.GetAll, "emptytable"),
                GetHumans      = PostInitFake(player.GetHumans, "emptytable"),
                GetCount       = PostInitFake(player.GetCount, 0),
                GetByAccountID = PostInitFake(player.GetByAccountID, false),
                GetBySteamID   = PostInitFake(player.GetBySteamID, false),
                GetBySteamID64 = PostInitFake(player.GetBySteamID64, false),
                GetByUniqueID  = PostInitFake(player.GetByUniqueID, false),
            }, { __index = player })

            env.player = playerSandbox
        end

        local entsSandbox = setmetatable({
            GetAll   = PostInitFake(ents.GetAll, "emptytable"),
            GetCount = PostInitFake(ents.GetCount, 0),
        }, { __index = ents })

        env.ents = entsSandbox

        ----------------------------------------------------------------
        -- Global fallback: reads fall through to _G, writes go to _G
        -- (same behavior as a normally loaded addon)
        ----------------------------------------------------------------
        setmetatable(env, {
            __index = function(_, key)
                return _G[key]
            end,
            __newindex = function(_, key, value)
                rawset(env, key, value)
                _G[key] = value
            end,
        })

        self.Environment = env
    end

    ------------------------------------------------------------------------
    -- Bundle creation
    ------------------------------------------------------------------------

    function Bundle:Create(files, name)
        BundleCounter = BundleCounter + 1

        TBH.Diag("[" .. tostring(name) .. "] bundle creating (file tree from " .. #(files or {}) .. " files)")

        local bundle = setmetatable({}, Bundle)

        bundle.ID = BundleCounter
        bundle.Name = name or "unknown"
        bundle.Files = {}
        bundle.FlatFiles = files or {}
        bundle.Hooks = {}
        bundle.HookGIDs = {}
        bundle.Timers = {}
        bundle.Errors = {}
        bundle.InitPostEntity = false
        bundle.LoadMapNav = false
        bundle.Unloaded = false
        bundle.RegisteredClasses = {
            entities = {},
            weapons = {},
            effects = {},
            vgui = {},
        }
        bundle.PendingBaseClasses = {}
        bundle.InitActive = false
        bundle.InitFinished = false
        bundle.HeldTimers = {}
        bundle.HeldByName = {}

        bundle.Information = {
            models = 0,
            materials = 0,
            lua = 0,
            sound = 0,
            other = 0,
        }

        bundle:BuildEnvironment()
        bundle:BuildFileTree(files or {})

        TBH.Diag("[" .. tostring(name) .. "] file tree built")

        return bundle
    end

    ------------------------------------------------------------------------
    -- File tree (directories -> nested tables, files -> array entries)
    ------------------------------------------------------------------------

    function Bundle:BuildFileTree(files)
        for i = 1, #files do
            local filename = files[i]
            local folder = string_match(filename, "^%w+")

            if folder then
                local bucket = self.Information[folder]
                if bucket then
                    self.Information[folder] = bucket + 1
                else
                    self.Information.other = self.Information.other + 1
                end
            end

            if SERVER then
                if not self.LoadMapNav and filename == ("maps/" .. game.GetMap() .. ".nav") then
                    self.LoadMapNav = true
                end
            elseif CLIENT then
                if folder == "resource" and string_match(filename, "%.properties$") then
                    TBH.ParsePropertiesFile(filename)
                end
            end

            if folder == "lua" or folder == "gamemodes" then
                local dirs = string.Explode("/", filename)
                local curdir = self.Files

                for j = 1, #dirs do
                    local name = dirs[j]

                    if string_sub(name, -4) == ".lua" then
                        curdir[#curdir + 1] = name
                    else
                        if not curdir[name] then
                            curdir[name] = {}
                        end
                        curdir = curdir[name]
                    end
                end
            end
        end
    end

    ------------------------------------------------------------------------
    -- Tree queries
    ------------------------------------------------------------------------

    function Bundle:Find(...)
        local dirs = { ... }
        local curdir = self.Files

        for i = 1, #dirs do
            local name = dirs[i]
            if curdir[name] then
                curdir = curdir[name]
            else
                curdir = nil
                break
            end
        end

        local files, folders = {}, {}

        if curdir then
            for key, value in pairs(curdir) do
                if istable(value) then
                    folders[#folders + 1] = key
                else
                    files[#files + 1] = value
                end
            end

            -- folders used to come out of pairs() in random order. wiremod needs
            -- gmod_wire_egp loaded before gmod_wire_expression2 (E2 grabs EGP at load),
            -- so just sort them like a normal boot would
            table.sort(folders)

            table.sort(files, function(a, b)
                -- match engine load order per platform
                if isLinux then
                    return a > b
                end
                return a < b
            end)
        end

        return files, folders
    end

    function Bundle:DeepFind(...)
        local files, dirs = self:Find(...)

        if files[1] == nil and dirs[1] == nil then
            files, dirs = self:Find("gamemodes", engine.ActiveGamemode(), "entities", ...)
        end

        return files, dirs
    end

    ------------------------------------------------------------------------
    -- include() path resolution: walk the call stack, find the calling
    -- file's folder, try relative includes, canonize ../ segments
    ------------------------------------------------------------------------

    function Bundle:GetAbsolutePath(path)
        if not isstring(path) then return path end

        for i = 2, 15 do
            local callst = debug.getinfo(i, "S")
            if not callst then break end

            local source = callst.source or ""
            local _, endpos = string_find(source, "lua/")

            if endpos then
                source = string_sub(source, endpos + 1)

                local lastSlash = string_match(source, "^.*/")
                if lastSlash then
                    source = lastSlash
                else
                    source = ""
                end

                local fixedPath = source .. path

                -- canonize foo/../ away
                while string_find(fixedPath, "../", 1, true) do
                    local canonized = string_gsub(fixedPath, "[%w%._]+/../", "")
                    if canonized == fixedPath then break end
                    fixedPath = canonized
                end

                if file_Read(fixedPath, "LUA") or file_Read(fixedPath, "GAME") or file_Read("lua/" .. fixedPath, "GAME") then
                    return fixedPath
                elseif source == "autorun/client/" or source == "autorun/server/" then
                    -- autorun realm folders can include from autorun/ root
                    local canonized = "autorun/" .. path
                    if file_Read(canonized, "LUA") or file_Read(canonized, "GAME") or file_Read("lua/" .. canonized, "GAME") then
                        return canonized
                    end
                end
            end
        end

        return path
    end

    ------------------------------------------------------------------------
    -- Compiling + running files
    ------------------------------------------------------------------------

    function Bundle:CompileChunk(relpath)
        local fullpath = "lua/" .. relpath
        local body = file_Read(fullpath, "GAME") or file_Read(fullpath, "LUA")

        if not body then
            self:Error("attempted to compile a missing file: " .. fullpath)
            return nil
        end

        local fn = CompileString(body, fullpath)

        if not isfunction(fn) then
            self:Error("syntax error while compiling " .. fullpath)
            return nil
        end

        return setfenv(fn, self.Environment)
    end

    function Bundle:InitializeFile(relpath)
        local fn = self:CompileChunk(relpath)
        if not fn then return end

        local results = { pcall(fn) }

        if not results[1] then
            self:Error(tostring(results[2]))
            return
        end

        return unpack(results, 2)
    end

    function Bundle:Include(path)
        local compiled = self:CompileChunk(self:GetAbsolutePath(path))
        if not compiled then return end

        -- if include() was called inside a module() environment, keep it
        for i = 2, 16 do
            if not debug.getinfo(i, "f") then break end

            -- getfenv can throw on tail-call frames - guard it
            local okEnv, fenv = pcall(getfenv, i)

            if okEnv and istable(fenv) and rawget(fenv, "TBH_IsModule") then
                setfenv(compiled, fenv)
                break
            end
        end

        local results = { pcall(compiled) }

        if not results[1] then
            self:Error(tostring(results[2]))
            return
        end

        return unpack(results, 2)
    end

    function Bundle:CompileFileSandboxed(path)
        local fn = self:CompileChunk(self:GetAbsolutePath(path))
        if fn then
            return fn
        end
    end

    function Bundle:AddCSLuaFileSandboxed(path)
        local absolute

        if path == nil then
            local src = debug.getinfo(2, "S").source
            local _, endpos = string_find(src, "lua/")

            if endpos then
                local rel = string_sub(src, endpos + 1)
                if file_Read(rel, "LUA") or file_Read("lua/" .. rel, "GAME") then
                    absolute = rel
                end
            end
        end

        if not absolute then
            absolute = self:GetAbsolutePath(path)
        end

        if absolute then
            local ok, err = pcall(_G.AddCSLuaFile, absolute)
            if not ok then
                self:Error("AddCSLuaFile('" .. tostring(absolute) .. "') failed: " .. tostring(err))
            end
        end
    end

    ------------------------------------------------------------------------
    -- Error collection
    ------------------------------------------------------------------------

    function Bundle:Error(msg)
        msg = string_sub(tostring(msg), 1, 400)
        self.Errors[#self.Errors + 1] = msg
    end

    function Bundle:Message(msg)
        if SERVER then
            if game.IsDedicated() then
                MsgC(TBH.Colors.tag, "[Hotloader] ", TBH.Colors.textdim, msg .. "\n")
            end
        else
            if TBH.CVarLogs and TBH.CVarLogs:GetBool() then
                MsgC(TBH.Colors.tag, "[Hotloader] ", TBH.Colors.textdim, msg .. "\n")
            end
        end
    end

    ------------------------------------------------------------------------
    -- ENT / SWEP / EFFECT / PANEL registration
    ------------------------------------------------------------------------

    local function CreateNewClass(classtype)
        local dat = ClassTypes[classtype]
        if not dat then return end

        local CLASS = {}

        if classtype == "weapons" then
            CLASS.Primary = {}
            CLASS.Secondary = {}
        end

        _G[dat.Global] = CLASS

        return dat.Global, dat.Table, dat.Count
    end

    -- safeguards for the ARC9 / ArcCW / M9K style weapon bases (and their packs)
    --
    -- the projectiles from these change collision group / solidity inside
    -- PhysicsCollide, which makes the engine spam "Changing collision rules
    -- within a callback is likely to cause crashes!". while one of those callbacks
    -- runs we push those calls to the next tick, same result but no warning.
    -- also, once a family bundle is done we re-resolve all the base classes so a
    -- pack that got hotloaded before its base still ends up working.

    local CollisionGuard = { depth = 0, installed = false }
    local GuardEntityFuncs = { "SetCollisionGroup", "SetSolid", "SetSolidFlags", "SetNotSolid", "SetMoveType" }
    local GuardPhysFuncs = { "EnableCollisions" }
    local guardEntOrig, guardPhysOrig = {}, {}
    local guardWrapped = setmetatable({}, { __mode = "k" })

    local function GuardEnter()
        CollisionGuard.depth = CollisionGuard.depth + 1
        if CollisionGuard.depth > 1 then return end

        local E, P = FindMetaTable("Entity"), FindMetaTable("PhysObj")

        for i = 1, #GuardEntityFuncs do
            local name = GuardEntityFuncs[i]
            local orig = E and E[name]
            if isfunction(orig) then
                guardEntOrig[name] = orig
                E[name] = function(self, a, b, c)
                    timer.Simple(0, function()
                        if IsValid(self) then orig(self, a, b, c) end
                    end)
                end
            end
        end

        for i = 1, #GuardPhysFuncs do
            local name = GuardPhysFuncs[i]
            local orig = P and P[name]
            if isfunction(orig) then
                guardPhysOrig[name] = orig
                P[name] = function(self, a, b, c)
                    timer.Simple(0, function()
                        if IsValid(self) then orig(self, a, b, c) end
                    end)
                end
            end
        end
    end

    local function GuardLeave()
        CollisionGuard.depth = math.max(0, CollisionGuard.depth - 1)
        if CollisionGuard.depth > 0 then return end

        local E, P = FindMetaTable("Entity"), FindMetaTable("PhysObj")

        for name, orig in pairs(guardEntOrig) do
            if E then E[name] = orig end
        end
        for name, orig in pairs(guardPhysOrig) do
            if P then P[name] = orig end
        end

        guardEntOrig, guardPhysOrig = {}, {}
    end

    local function GuardCollide(fn)
        if guardWrapped[fn] then return fn end

        local wrapper = function(...)
            GuardEnter()
            local r = { pcall(fn, ...) }
            GuardLeave()

            if not r[1] then error(r[2], 0) end
            return unpack(r, 2)
        end

        guardWrapped[wrapper] = true
        guardWrapped[fn] = true

        return wrapper
    end

    local function InstallCollisionGuard()
        if CollisionGuard.installed or not SERVER then return end
        CollisionGuard.installed = true

        -- ent:AddCallback("PhysicsCollide", fn) / phys:AddCallback(...)
        for _, metaName in ipairs({ "Entity", "PhysObj" }) do
            local M = FindMetaTable(metaName)
            local old = M and M.AddCallback

            if isfunction(old) then
                M.AddCallback = function(self, hookName, fn, ...)
                    if hookName == "PhysicsCollide" and isfunction(fn) then
                        fn = GuardCollide(fn)
                    end
                    return old(self, hookName, fn, ...)
                end
            end
        end
    end

    function Bundle:DetectWeaponFamily()
        local name = string.lower(self.Name or "")
        if string_find(name, "arc9", 1, true) or string_find(name, "arccw", 1, true) or string_find(name, "m9k", 1, true) then
            return true
        end

        local files = self.FlatFiles or {}
        for i = 1, #files do
            local f = string.lower(files[i])
            if string_find(f, "arc9", 1, true) or string_find(f, "arccw", 1, true)
                or string_find(f, "m9k", 1, true) or string_find(f, "bobs_", 1, true) then
                return true
            end
        end

        return false
    end

    -- vehicle frameworks: LVS, LFS, Glide and simfphys (armed packs count as simfphys).
    -- they all work the same way for us: a base addon registers the base entity,
    -- packs derive from it. what we do for them is re-resolve every base class when
    -- they finish (a pack hotloaded before its base would otherwise stay broken),
    -- rebuild the spawnmenu so the vehicle tabs fill in, and warn if the base is
    -- missing instead of leaving you with vehicles that silently dont spawn.
    local VehicleFamilies = {
        { name = "simfphys", paths = { "simfphys" }, names = { "simfphys" }, base = "gmod_sent_vehicle_fphysics_base" },
        { name = "LVS", paths = { "lua/lvs_framework", "lua/entities/lvs_" }, names = { "%f[%w]lvs%f[%W]" }, base = "lvs_base" },
        { name = "LFS", paths = { "lunasflightschool" }, names = { "%f[%w]lfs%f[%W]" }, base = "lunasflightschool_basescript" },
        { name = "Glide", paths = { "lua/glide/", "lua/entities/base_glide", "lua/entities/glide_" }, names = { "%f[%w]glide%f[%W]" }, base = "base_glide" },
    }

    function Bundle:DetectVehicleFamilies()
        local found = {}
        local name = string.lower(self.Name or "")
        local files = self.FlatFiles or {}

        for _, fam in ipairs(VehicleFamilies) do
            local hit = false

            for _, pat in ipairs(fam.names) do
                if string_find(name, pat) then hit = true break end
            end

            if not hit then
                for i = 1, #files do
                    local f = string.lower(files[i])
                    for _, path in ipairs(fam.paths) do
                        if string_find(f, path, 1, true) then hit = true break end
                    end
                    if hit then break end
                end
            end

            if hit then found[#found + 1] = fam end
        end

        return found
    end

    function Bundle:CheckVehicleBases()
        for _, fam in ipairs(self.VehicleFamilies or {}) do
            local have = (scripted_ents and scripted_ents.GetStored and scripted_ents.GetStored(fam.base))
                or (weapons and weapons.GetStored and weapons.GetStored(fam.base))

            if not have then
                local msg = "\"" .. tostring(self.Name) .. "\" looks like a " .. fam.name ..
                    " addon but the " .. fam.name .. " base (" .. fam.base .. ") isn't loaded. Hotload the base addon first, then this one."

                if CLIENT then
                    TBH.NotifyLocally(msg, 3, 12)
                else
                    TBH.Msg(msg)
                end
            end
        end
    end

    local function RegisterNewClass(classtype, classname, tblname, basetable, registercount, bundle)
        local CLASS = _G[tblname]

        if SERVER and classtype == "entities" and TBH.CollisionGuardEnabled
            and istable(CLASS) and isfunction(CLASS.PhysicsCollide) then
            CLASS.PhysicsCollide = GuardCollide(CLASS.PhysicsCollide)
        end

        if CLASS and table.Count(CLASS) >= registercount then
            if classtype == "vgui" then
                if not basetable.GetControlTable(classname) then
                    basetable.Register(classname, CLASS, CLASS.Base)
                end
            else
                if basetable.Register then
                    local ok = pcall(basetable.Register, CLASS, classname)
                    if not ok then
                        -- try again as (name, table) order used by some libs
                        pcall(basetable.Register, classname, CLASS)
                    end

                    if not IsClientClassType(classtype) and basetable.Get then
                        if bundle and istable(bundle.PendingBaseClasses) then
                            -- resolved at the end of init (see ResolveBaseClasses)
                            bundle.PendingBaseClasses[#bundle.PendingBaseClasses + 1] = { basetable, classname }
                        else
                            timer.Simple(0.1, function()
                                pcall(function() baseclass.Set(classname, basetable.Get(classname)) end)
                            end)
                        end
                    end
                end
            end

            -- remember what we registered so a soft unload can remove it
            if bundle and istable(bundle.RegisteredClasses) then
                local list = bundle.RegisteredClasses[classtype]
                if list then
                    list[#list + 1] = classname
                end
            end
        end

        _G[tblname] = nil
    end

    ------------------------------------------------------------------------
    -- baseclass resolution, runs once after every class of the bundle exists
    ------------------------------------------------------------------------

    function Bundle:ResolveBaseClasses()
        local pending = self.PendingBaseClasses
        self.PendingBaseClasses = nil -- anything registered later falls back to the timer

        if not istable(pending) or #pending == 0 then return end

        -- two passes: bases may be listed after the classes deriving from them
        for pass = 1, 2 do
            for i = 1, #pending do
                local basetable, classname = pending[i][1], pending[i][2]

                pcall(function()
                    local tab = basetable.Get(classname)
                    if tab then
                        baseclass.Set(classname, tab)
                    end
                end)
            end
        end
    end

    -- the sandbox environment shadows globals that were assigned through it
    -- (ENT/SWEP/TOOL = ...). Clear the shadow so the real global is read again.
    function Bundle:ClearEnvGlobal(name)
        if istable(self.Environment) then
            rawset(self.Environment, name, nil)
        end
    end

    ------------------------------------------------------------------------
    -- Toolgun STOOL registration
    ------------------------------------------------------------------------

    -- Live toolgun bookkeeping. Every player's toolgun owns a PRIVATE copy of each
    -- tool (that is how gmod_tool/shared.lua works), so a tool that is hotloaded
    -- after the toolgun was created has to be pushed into the live toolgun.
    TBH.ToolTemplates = TBH.ToolTemplates or {}
    TBH.ToolPushed = TBH.ToolPushed or setmetatable({}, { __mode = "k" })

    local function PushToolToToolgun(toolname, TOOL, ply)
        if not IsValid(ply) then return end

        local toolgun = ply:GetWeapon("gmod_tool")
        if not IsValid(toolgun) or not istable(toolgun.Tool) then return end

        local pushed = TBH.ToolPushed[toolgun]
        if not pushed then
            pushed = {}
            TBH.ToolPushed[toolgun] = pushed
        end

        -- already holds this exact template
        if pushed[toolname] == TOOL then return end

        local tool = table.Copy(TOOL)

        tool.SWEP = toolgun
        tool.Weapon = toolgun
        tool.Owner = ply

        -- if Init() errors we still keep the tool, it used to get thrown away
        if isfunction(tool.Init) then
            local okInit, errInit = pcall(tool.Init, tool)
            if not okInit then
                TBH.Verbose("tool '" .. tostring(toolname) .. "' Init() failed (tool kept anyway): " .. tostring(errInit))
            end
        end

        toolgun.Tool[toolname] = tool
        pushed[toolname] = TOOL
    end

    function TBH.RepairToolguns()
        if next(TBH.ToolTemplates) == nil then return end

        for _, ply in ipairs(player.GetAll()) do
            for toolname, TOOL in pairs(TBH.ToolTemplates) do
                pcall(PushToolToToolgun, toolname, TOOL, ply)
            end
        end

        if CLIENT then
            local cv = GetConVar("gmod_toolmode")
            if cv then pcall(TBH.PushToolConVars, cv:GetString()) end
        end
    end

    -- tool settings are userinfo convars, and a convar made after you joined isnt
    -- sent to the server until its value changes. so the server read an empty model
    -- and the tool just refused to spawn anything (restart worked because the convars
    -- existed at connect). when a hotloaded tool gets selected we nudge each of its
    -- convars so the server learns the values
    if CLIENT then
        TBH.ToolConVarsSent = TBH.ToolConVarsSent or {}

        function TBH.PushToolConVars(mode)
            if not isstring(mode) or TBH.ToolConVarsSent[mode] then return end

            local TOOL = TBH.ToolTemplates[mode]
            if not istable(TOOL) or not istable(TOOL.ClientConVar) then return end

            TBH.ToolConVarsSent[mode] = true

            local list = {}
            for key in pairs(TOOL.ClientConVar) do
                local cv = GetConVar(mode .. "_" .. key)
                if cv then
                    list[#list + 1] = { name = cv:GetName(), val = cv:GetString() }
                end
            end

            for i = 1, #list do
                local e = list[i]
                timer.Simple(i * 0.03, function()
                    RunConsoleCommand(e.name, e.val .. " ")
                    timer.Simple(0.06, function()
                        RunConsoleCommand(e.name, e.val)
                    end)
                end)
            end
        end

        cvars.AddChangeCallback("gmod_toolmode", function(_, _, new)
            TBH.PushToolConVars(new)
        end, "TBH.ToolConVars")
    end

    function Bundle:InitializeTools()
        local GM = gmod.GetGamemode()

        if not GM or not GM.IsSandboxDerived then
            return
        end

        local tools = self:DeepFind("lua", "weapons", "gmod_tool", "stools")

        if #tools == 0 then return end

        local toolSWEP = weapons.GetStored("gmod_tool")

        if not toolSWEP then
            self:Error("tools: gmod_tool is not registered, cannot add stools")
            return
        end

        toolSWEP.Tool = toolSWEP.Tool or {}

        -- find the ToolObj class: preferably through a stock tool's metatable
        local ToolObj
        local axisTool = toolSWEP.Tool.axis

        if istable(axisTool) then
            ToolObj = getmetatable(axisTool)
        end

        if not (istable(ToolObj) and isfunction(ToolObj.Create)) then
            ToolObj = nil

            if istable(_G.ToolObj) and isfunction(_G.ToolObj.Create) then
                ToolObj = _G.ToolObj
            else
                for _, t in pairs(toolSWEP.Tool) do
                    local mt = istable(t) and getmetatable(t)
                    if istable(mt) and isfunction(mt.Create) then
                        ToolObj = mt
                        break
                    end
                end
            end
        end

        if not ToolObj then
            self:Error("tools: could not find the ToolObj class, stools were not added")
            return
        end

        local oldSWEP, oldTOOL, oldToolObj = _G.SWEP, _G.TOOL, _G.ToolObj
        local registered = {}

        _G.SWEP = toolSWEP
        _G.ToolObj = ToolObj

        for i = 1, #tools do
            local filename = tools[i]
            local toolname = string_sub(filename, 1, -5)

            local okTool, errTool = pcall(function()
                -- stool files can reassign TOOL (TOOL = WireToolObj:Create() and so on). the old
                -- code kept its own object and stomped the global with it afterwards, and a stale
                -- TOOL in the sandbox leaked into the next file too
                self:ClearEnvGlobal("TOOL")
                self:ClearEnvGlobal("SWEP")
                self:ClearEnvGlobal("ToolObj")

                -- snapshot: some addons (Wiremod's WireToolSetup.close()) register
                -- their tools THEMSELVES with SWEP.Tool[mode] = TOOL and then clear
                -- the global. Registering our own empty object over those is what
                -- made Wiremod's tools unusable.
                local before = {}
                for k, v in pairs(toolSWEP.Tool) do before[k] = v end

                local TOOL = ToolObj:Create()
                TOOL.Mode = toolname

                _G.TOOL = TOOL
                self:InitializeFile("weapons/gmod_tool/stools/" .. filename)

                local selfRegistered = false

                for k, v in pairs(toolSWEP.Tool) do
                    if before[k] ~= v and istable(v) then
                        selfRegistered = true
                        TBH.ToolTemplates[k] = v
                        registered[#registered + 1] = k
                    end
                end

                -- engine behaviour: whatever is left in the global IS the tool
                local final = _G.TOOL
                if istable(final) and not (selfRegistered and (final == TOOL)) then
                    if final.Mode == nil then final.Mode = toolname end

                    local okCV, errCV = pcall(function() final:CreateConVars() end)
                    if not okCV then
                        self:Error("stool '" .. toolname .. "' CreateConVars failed: " .. tostring(errCV))
                    end

                    toolSWEP.Tool[final.Mode] = final
                    TBH.ToolTemplates[final.Mode] = final
                    registered[#registered + 1] = final.Mode
                end
            end)

            if not okTool then
                self:Error("stool '" .. toolname .. "' failed to load: " .. tostring(errTool))
            end

            _G.TOOL = nil
            self:ClearEnvGlobal("TOOL")
        end

        _G.SWEP = oldSWEP
        _G.TOOL = oldTOOL
        _G.ToolObj = oldToolObj or ToolObj -- the engine leaves ToolObj global
        self:ClearEnvGlobal("TOOL")
        self:ClearEnvGlobal("SWEP")
        self:ClearEnvGlobal("ToolObj")

        -- remember for the menu/UI
        TBH.LoadedTools = TBH.LoadedTools or {}
        for i = 1, #registered do
            TBH.LoadedTools[registered[i]] = true
        end

        -- and which ones are ours, for FULL Unload
        self.RegisteredTools = registered

        -- push the new tools into every player's live toolgun now, and keep a
        -- cheap safeguard running so a toolgun that gets re-created later (or
        -- whose push raced the spawn) always ends up with every hotloaded tool
        TBH.RepairToolguns()

        if not timer.Exists("TBH.ToolRepair") then
            timer.Create("TBH.ToolRepair", 2, 0, function()
                TBH.RepairToolguns()
            end)
        end
    end

    ------------------------------------------------------------------------
    -- Soft unload: strips everything this bundle's Lua is doing.
    --
    -- CAN remove: hooks, timers, spawnmenu list entries, spawned entities
    --             (optional), held weapons of the addon's classes.
    --             spawnmenu lists the addon filled (NPCs, vehicles, ...),
    --             console commands, net receivers, toolgun tools and the
    --             weapon / entity class tables (through the registries'
    --             upvalues). The mounted FILES go through the gmaunmount
    --             module (FULL Unload).
    ------------------------------------------------------------------------

    -- finds the table a lua module keeps its registry in (weapons / scripted_ents keep
    -- theirs in a local that only their own functions can see - their upvalues)
    local function FindRegistry(getter, class)
        if not (debug and debug.getupvalue and isfunction(getter)) then return nil end

        for i = 1, 40 do
            local name, val = debug.getupvalue(getter, i)
            if name == nil then break end
            if istable(val) and rawget(val, class) ~= nil then return val end
        end
    end

    -- takes back everything this bundle registered that has an unregister path:
    -- spawnmenu lists (NPCs, vehicles...), console commands, net receivers, convar
    -- callbacks, properties, toolgun tools and the weapon / entity class tables
    function Bundle:PurgeRegistrations()
        local removed = { lists = 0, tools = 0, classes = 0 }

        for _, e in ipairs(self.ListKeys or {}) do
            local ok = false
            if isfunction(list.RemoveEntry) then ok = pcall(list.RemoveEntry, e[1], e[2]) end

            -- same thing by hand (works on any build)
            local okHand = pcall(function()
                local tab = list.GetForEdit(e[1])
                if tab[e[2]] ~= nil then tab[e[2]] = nil ok = true end
            end)

            if ok or okHand then removed.lists = removed.lists + 1 end
        end

        for _, e in ipairs(self.ListValues or {}) do
            pcall(function()
                local tab = list.GetForEdit(e[1])
                for i = #tab, 1, -1 do
                    if tab[i] == e[2] then table.remove(tab, i) removed.lists = removed.lists + 1 end
                end
            end)
        end

        for _, name in ipairs(self.ConCommands or {}) do pcall(concommand.Remove, name) end

        for _, name in ipairs(self.NetNames or {}) do
            if istable(net.Receivers) then net.Receivers[string.lower(name)] = nil end
        end

        for _, c in ipairs(self.CVarCallbacks or {}) do
            if c[2] ~= nil then pcall(cvars.RemoveChangeCallback, c[1], c[2]) end
        end

        for _, name in ipairs(self.PropertyNames or {}) do
            if properties and istable(properties.List) then properties.List[name] = nil end
        end

        -- toolgun tools: the tool panel is built from the toolgun's stored Tool table
        local toolSWEP = weapons.GetStored("gmod_tool")

        for _, mode in ipairs(self.RegisteredTools or {}) do
            if TBH.ToolTemplates then TBH.ToolTemplates[mode] = nil end
            if TBH.LoadedTools then TBH.LoadedTools[mode] = nil end
            if TBH.ToolConVarsSent then TBH.ToolConVarsSent[mode] = nil end

            if toolSWEP and istable(toolSWEP.Tool) and toolSWEP.Tool[mode] ~= nil then
                toolSWEP.Tool[mode] = nil
                removed.tools = removed.tools + 1
            end

            for _, ply in ipairs(player.GetAll()) do
                local toolgun = ply:GetWeapon("gmod_tool")

                if IsValid(toolgun) and istable(toolgun.Tool) then
                    toolgun.Tool[mode] = nil
                    local pushed = TBH.ToolPushed and TBH.ToolPushed[toolgun]
                    if pushed then pushed[mode] = nil end
                end
            end
        end

        -- if one of our tools is the selected one, fall back to a stock tool
        if CLIENT and #(self.RegisteredTools or {}) > 0 then
            local cv = GetConVar("gmod_toolmode")
            if cv then
                for _, mode in ipairs(self.RegisteredTools) do
                    if cv:GetString() == mode then
                        RunConsoleCommand("gmod_toolmode", "weld")
                        break
                    end
                end
            end
        end

        -- weapon / entity class tables (no unregister API exists, so reach into the registry)
        local function DropClasses(classes, getter)
            for i = 1, #classes do
                local class = classes[i]
                local registry = FindRegistry(getter, class)

                if registry then
                    registry[class] = nil
                    removed.classes = removed.classes + 1
                end

                if baseclass and baseclass.Set then pcall(baseclass.Set, class, nil) end
            end
        end

        DropClasses(self.RegisteredClasses.entities or {}, scripted_ents.GetStored)
        DropClasses(self.RegisteredClasses.weapons or {}, weapons.GetStored)

        return removed
    end

    function Bundle:Unload(removeEntities)
        if self.Unloaded then return end
        self.Unloaded = true
        self.InitFinished = true
        self.HeldTimers, self.HeldByName = {}, {}

        -- cancel a still-running frame-spread initialization
        self.PumpAlive = false
        self.InitActive = false

        -- 1. hooks
        for key, gid in pairs(self.HookGIDs) do
            local event = string_match(key, "^(.-)\1")
            if event then
                hook.Remove(event, gid)
            end
        end

        self.HookGIDs = {}
        self.Hooks = {}

        -- 2. timers
        for name, gid in pairs(self.Timers) do
            timer.Remove(gid)
        end

        self.Timers = {}

        -- 3. spawnmenu entries (hide from the menus even though the class
        --    tables technically remain registered)
        local entityClasses = self.RegisteredClasses.entities or {}
        local weaponClasses = self.RegisteredClasses.weapons or {}

        for i = 1, #entityClasses do
            pcall(function()
                list.RemoveEntry("SpawnableEntities", entityClasses[i])
                list.RemoveEntry("SpawnableSent", entityClasses[i])
            end)
        end

        for i = 1, #weaponClasses do
            pcall(function()
                list.RemoveEntry("Weapon", weaponClasses[i])
                list.RemoveEntry("SpawnableWeapons", weaponClasses[i])
            end)
        end

        -- 4. optionally remove entities the addon's classes spawned
        if SERVER and removeEntities then
            for i = 1, #entityClasses do
                local classname = entityClasses[i]

                for _, ent in ipairs(ents.FindByClass(classname)) do
                    if IsValid(ent) then
                        ent:Remove()
                    end
                end
            end

            -- strip held weapons of the addon's classes
            for i = 1, #weaponClasses do
                local classname = weaponClasses[i]

                for _, ply in ipairs(player.GetAll()) do
                    local wep = ply:GetWeapon(classname)

                    if IsValid(wep) then
                        ply:StripWeapon(classname)
                    end
                end
            end
        end

        -- 5. everything else that can be taken back (lists, commands, tools, class tables)
        local okPurge, purged = pcall(self.PurgeRegistrations, self)
        if okPurge then
            TBH.Verbose(string.format("[%s] unload purged %d list entries, %d tools, %d classes",
                tostring(self.Name), purged.lists, purged.tools, purged.classes))
        else
            TBH.LogError("unload purge failed for " .. tostring(self.Name) .. ": " .. tostring(purged))
        end

        if CLIENT then
            -- debounced refresh so hidden entries disappear
            TBH.QueueSpawnMenuRefresh(1)
        end

        hook.Run("TBH.BundleUnloaded", self)
    end

    ------------------------------------------------------------------------
    -- Full staged initialization (mirrors a fresh game boot)
    --
    -- v1.1.0: this is no longer one giant synchronous block. Collections
    -- used to freeze the game for every member (seconds of uninterrupted
    -- Lua + class registration per addon, 15 in a row = a multi-minute
    -- frozen main thread -> the engine dies). The work is now split into
    -- small units that are pumped across frames with a per-frame time
    -- budget, so the game keeps rendering and net messages keep flowing.
    -- Small addons still finish inside the very first pump (no added
    -- latency for them).
    --
    -- onComplete(bundle) fires when everything is done (including errors).
    ------------------------------------------------------------------------

    function Bundle:BuildInitUnits()
        local units = {}

        -- autorun files, one unit per file
        local function AddAutorunFolder(...)
            local filelist = self:Find("lua", ...)
            local prefix = table.concat({ ... }, "/")

            for i = 1, #filelist do
                units[#units + 1] = function()
                    self:InitializeFile(prefix .. "/" .. filelist[i])
                end
            end
        end

        AddAutorunFolder("autorun")

        if SERVER then
            AddAutorunFolder("autorun", "server")
        else
            AddAutorunFolder("autorun", "client")
        end

        -- scripted classes: one unit per single-file class / folder class,
        -- so a 300-entity addon registers them across many frames
        local function AddClassUnits(classtype)
            local dat = ClassTypes[classtype]
            if not dat then return end

            local files, dirs = self:DeepFind("lua", classtype)

            -- single file classes: lua/entities/foo.lua
            for i = 1, #files do
                local filename = files[i]
                local classname = string_sub(filename, 1, -5)

                units[#units + 1] = function()
                    self:ClearEnvGlobal(dat.Global)
                    local tblname, basetable, registercount = CreateNewClass(classtype)

                    _G[tblname].Folder = classtype .. "/" .. classname
                    self:InitializeFile(classtype .. "/" .. filename)

                    RegisterNewClass(classtype, classname, tblname, basetable, registercount, self)
                end
            end

            -- folder classes: lua/entities/foo/init.lua + cl_init.lua + shared.lua
            for i = 1, #dirs do
                local classname = dirs[i]

                if classtype ~= "weapons" or classname ~= "gmod_tool" then
                    units[#units + 1] = function()
                        local classfiles = self:DeepFind("lua", classtype, classname)
                        self:ClearEnvGlobal(dat.Global)
                        local tblname, basetable, registercount = CreateNewClass(classtype)

                        _G[tblname].Folder = classtype .. "/" .. classname

                        for j = 1, #classfiles do
                            local filename = classfiles[j]
                            local path = classtype .. "/" .. classname .. "/" .. filename

                            if filename == "init.lua" and (SERVER or IsClientClassType(classtype)) then
                                self:InitializeFile(path)
                            elseif filename == "cl_init.lua" and CLIENT then
                                self:InitializeFile(path)
                            elseif filename == "shared.lua" then
                                self:InitializeFile(path)
                            end
                        end

                        RegisterNewClass(classtype, classname, tblname, basetable, registercount, self)
                    end
                end
            end
        end

        AddClassUnits("vgui")
        AddClassUnits("weapons")

        -- toolgun stools (one unit - the TOOL global juggling stays atomic)
        units[#units + 1] = function()
            self:InitializeTools()
        end

        AddClassUnits("entities")
        AddClassUnits("effects")

        -- simulate the gamemode lifecycle that already happened
        units[#units + 1] = function() self:CallHooks("PreGamemodeLoaded") end
        units[#units + 1] = function() self:CallHooks("OnGamemodeLoaded") end
        units[#units + 1] = function() self:CallHooks("PostGamemodeLoaded") end
        units[#units + 1] = function() self:CallHooks("Initialize") end
        units[#units + 1] = function() self.InitPostEntity = true end
        units[#units + 1] = function() self:CallHooks("InitPostEntity") end

        if SERVER then
            units[#units + 1] = function()
                local callbacks = self.Hooks.PlayerInitialSpawn
                if callbacks and not table.IsEmpty(callbacks) then
                    for k, ply in ipairs(player.GetAll()) do
                        self:CallHooks("PlayerInitialSpawn", ply, false)
                    end
                end
            end
        end

        return units
    end

    function Bundle:Initialize(onComplete)
        if self.InitStarted then return end
        self.InitStarted = true

        self.InitStartTime = SysTime()
        self.PumpAlive = true

        self.VehicleFamilies = self:DetectVehicleFamilies()
        self.IsWeaponFamily = self:DetectWeaponFamily()
        if SERVER and self.IsWeaponFamily then
            TBH.CollisionGuardEnabled = true
            InstallCollisionGuard()
        end

        local savedENT, savedSWEP, savedPANEL, savedEFFECT =
            _G.ENT, _G.SWEP, _G.PANEL, _G.EFFECT

        local units = self:BuildInitUnits()

        self.DiagStepCount = #units

        TBH.Diag("[" .. self.Name .. "] init starting: " .. #units .. " steps (frame-spread, " ..
            string.format("%.0f", (SERVER and 0.010 or 0.008) * 1000) .. "ms budget/frame)")

        self:Message("[" .. self.Name .. "] initializing (" .. (SERVER and "server" or "client") .. ", " .. #units .. " steps)...")

        -- one coroutine, one unit per resume - the yield always happens at
        -- the coroutine's top level (never across a pcall boundary, which
        -- plain Lua 5.1 does not allow)
        local co = coroutine.create(function()
            for i = 1, #units do
                self.InitActive = true
                local ok, err = pcall(units[i])
                self.InitActive = false
                if not ok then
                    self:Error("init step failed: " .. tostring(err))
                    TBH.Diag("[" .. self.Name .. "] init step #" .. i .. " ERRORED: " .. string_sub(tostring(err), 1, 200))
                end
                coroutine.yield(true)
            end
        end)

        -- per-frame work budget: every frame stays responsive while the
        -- batch trickles through the engine
        local budget = SERVER and 0.010 or 0.008
        local resumeCount = 0

        local function Pump()
            if not self.PumpAlive then return end

            local t0 = SysTime()
            local done = (coroutine.status(co) == "dead")

            while not done and (SysTime() - t0) < budget do
                local tUnit = SysTime()

                local ok, err = coroutine.resume(co)

                resumeCount = resumeCount + 1

                -- a single monster lua file inside one step? that is a
                -- freeze the frame-budget cannot prevent - log it
                if ok and (SysTime() - tUnit) > 0.25 then
                    TBH.Diag("[" .. self.Name .. "] SLOW init step #" .. resumeCount .. " took " ..
                        string.format("%.3f", SysTime() - tUnit) .. "s (single heavy lua file - FREEZE)")
                end

                if not ok then
                    self:Error("initialization crashed: " .. tostring(err))
                    TBH.Diag("[" .. self.Name .. "] init pump CRASHED: " .. string_sub(tostring(err), 1, 200))
                    done = true
                    break
                end

                done = (coroutine.status(co) == "dead")
            end

            if done then
                self.PumpAlive = false
                self.DiagResumes = resumeCount
                self:FinishInitialize(savedENT, savedSWEP, savedPANEL, savedEFFECT, onComplete)
            else
                timer.Simple(0, Pump)
            end
        end

        -- run the first chunk right away: small addons complete instantly,
        -- big ones spread out over the following frames
        Pump()
    end

    function Bundle:FinishInitialize(savedENT, savedSWEP, savedPANEL, savedEFFECT, onComplete)
        self.InitActive = false
        self.InitPostEntity = true -- init is over: never fake the world again
        self.InitFinished = true

        -- start the timers that were held back during init
        local held = self.HeldTimers or {}
        self.HeldTimers, self.HeldByName = {}, {}
        for i = 1, #held do
            local h = held[i]
            if isfunction(h) then
                pcall(h)
            elseif istable(h) and not h.cancelled then
                pcall(h.start)
            end
        end

        -- resolve baseclass now that every class of this addon is registered, same as the
        -- engine does in weapons.OnLoaded. doing it 0.1s after each class printed the
        -- "trying to derive from non existant" errors and cached half built tables
        self:ResolveBaseClasses()

        if #(self.VehicleFamilies or {}) > 0 then
            timer.Simple(1, function()
                if self.Unloaded then return end

                if weapons and isfunction(weapons.OnLoaded) then pcall(weapons.OnLoaded) end
                if scripted_ents and isfunction(scripted_ents.OnLoaded) then pcall(scripted_ents.OnLoaded) end

                pcall(self.CheckVehicleBases, self)

                -- vehicle tabs are filled from lists, rebuild the menu so they show up
                if CLIENT then TBH.QueueSpawnMenuRefresh(2) end
            end)
        end

        if self.IsWeaponFamily then
            -- re-resolve EVERY weapon/entity base (packs hotloaded before their
            -- base, or a base that was reloaded) - the engine's own OnLoaded step
            timer.Simple(0.5, function()
                if weapons and isfunction(weapons.OnLoaded) then pcall(weapons.OnLoaded) end
                if scripted_ents and isfunction(scripted_ents.OnLoaded) then pcall(scripted_ents.OnLoaded) end
            end)
        end

        _G.ENT = savedENT
        _G.SWEP = savedSWEP
        _G.PANEL = savedPANEL
        _G.EFFECT = savedEFFECT

        if SERVER then
            if navmesh and navmesh.IsLoaded and not navmesh.IsLoaded() and self.LoadMapNav then
                navmesh.Load()
            end
        end

        local hookcount = 0
        for event, tab in pairs(self.Hooks) do
            hookcount = hookcount + table.Count(tab)
        end

        local time = math.Round(SysTime() - (self.InitStartTime or SysTime()), 3)

        TBH.Diag(string.format("[%s] init COMPLETE: %d steps, %d resumes, %d lua error(s), %.3fs total",
            tostring(self.Name), self.DiagStepCount or 0, self.DiagResumes or 0, #self.Errors, time))

        self:Message(string.format(
            "[%s] initialized in %s seconds - %d hooks, %d lua files, %d models, %d materials, %d sounds",
            self.Name, tostring(time), hookcount,
            self.Information.lua, self.Information.models,
            self.Information.materials, self.Information.sound
        ))

        hook.Run("TBH.BundleInitialized", self)
        TBH.Verbose("Bundle '" .. tostring(self.Name) .. "' (wsid " .. tostring(self.WSID) .. ") initialized: " .. tostring(self.Information.lua) .. " lua files, " .. tostring(self.Information.models) .. " models, " .. tostring(self.Information.materials) .. " materials, " .. tostring(self.Information.sound) .. " sounds")

        if isfunction(onComplete) then
            local ok, err = pcall(onComplete, self)
            if not ok then
                TBH.LogError("Bundle completion callback failed: " .. tostring(err))
            end
        end

        -- post-init reporting
        timer.Simple(1, function()
            if CLIENT then
                -- debounced: a 30-addon collection must not trigger 30 full
                -- spawnmenu rebuilds (CEF churn = crash)
                TBH.QueueSpawnMenuRefresh(3)
            end

            if self.Errors[1] ~= nil then
                local realm = SERVER and "SERVER" or "CLIENT"
                local errors = table.concat(self.Errors, "\n")

                MsgC(TBH.Colors.warn, "\n[Hotloader] " .. realm .. " errors while hotloading '" .. self.Name .. "':\n")
                MsgC(TBH.Colors.textdim, string_sub(errors, 1, 4000) .. "\n\n")

                hook.Run("TBH.BundleErrored", self, self.Errors)
            end
        end)
    end
end


--------------------------------------------------------------------------------
-- Workshop localization files (resource/localization/*.properties)
-- Lets hotloaded addons use #language.phrases like normally mounted ones.
--------------------------------------------------------------------------------

TBH.PropertiesTranslations = TBH.PropertiesTranslations or {}

function TBH.ParsePropertiesFile(filename)
    local body = file.Read(filename, "GAME")
    if not body then return end

    local lang = string_match(filename, "resource/localization/([%w_%-]+)/")
    if not lang then return end

    local translations = TBH.PropertiesTranslations[lang]
    if not translations then
        translations = {}
        TBH.PropertiesTranslations[lang] = translations
    end

    for k, line in ipairs(string.Explode("\n", body)) do
        local startpos, endpos, key = string.find(line, "([%w%-%._]+)%s*=%s*")

        if key then
            local value = string.Trim(string_sub(line, endpos + 1))
            if value ~= "" then
                translations[key] = value
            end
        end
    end
end

if CLIENT then
    -- detour language.GetPhrase once (refresh-safe)
    if not TBH.LanguageDetoured then
        TBH.LanguageDetoured = true

        local language_GetPhrase = language.GetPhrase
        local gmod_language = GetConVar("gmod_language")

        function language.GetPhrase(phrase, ...)
            -- only touch real #phrase lookups and never hand back an empty string. the old
            -- version chopped the first char off any string and could return "" for stock
            -- gmod phrases (blank labels in dupes/saves)
            if isstring(phrase) and string_sub(phrase, 1, 1) == "#" then
                local lang = gmod_language and gmod_language:GetString() or "en"
                local translations = TBH.PropertiesTranslations[lang]

                if translations then
                    local translation = translations[string_sub(phrase, 2)]
                    if isstring(translation) then
                        translation = string.Trim(translation)
                        if translation ~= "" then
                            return translation
                        end
                    end
                end
            end

            return language_GetPhrase(phrase, ...)
        end
    end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  RUNTIME AMMO TYPES
--
--  game.AddAmmoType does nothing after the game has booted, so hotloaded
--  weapons with custom ammo would have broken HUDs and no damage values.
--  This subsystem intercepts the ammo API and emulates ammo types with
--  NW2-backed counters, a reference ammo type for FireBullets, and full
--  compatibility wrappers for Give/Set/Get ammo and weapon ammo types.
--
--  (Approach adapted from Midgame Workshop Hotloader's sh_ammo.)
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

do
    local REF_AMMO = "_hotloader_refammo_ammo"

    TBH.Detours = TBH.Detours or {}

    local function Detour(basetbl, key, detourName, func)
        local storeKey = detourName .. "." .. key
        local old = TBH.Detours[storeKey] or basetbl[key]

        if old then
            basetbl[key] = function(...)
                local retval = func(...)
                if retval ~= nil then
                    return retval
                end
                return old(...)
            end

            TBH.Detours[storeKey] = old
        end
    end

    -- Register the reference ammo type (only once per boot)
    if game.GetAmmoID(REF_AMMO) == -1 then
        game.AddAmmoType({ name = REF_AMMO })
    end

    timer.Simple(0.25, function()
        local ammoTypes = {}   -- [id] = ammoData
        local isTBHAmmo = {}   -- [name] = id

        local function GetAmmoData(any)
            if isnumber(any) then
                return ammoTypes[any]
            end
            if isstring(any) then
                local id = isTBHAmmo[any]
                if id then return ammoTypes[id] end
            end
        end

        local _R = debug.getregistry()

        local Entity = _R.Entity
        local Player = _R.Player

        if CLIENT then
            TBH.Net:Receive("hotloader_ammo", function()
                hook.Run("HUDAmmoPickedUp", net.ReadString(), net.ReadInt(32))
                surface.PlaySound("items/ammo_pickup.wav")
            end)
        end

        local function QuickDetour(key, valuename)
            Detour(game, key, "game", function(id)
                local data = ammoTypes[id]
                if data then
                    return data[valuename]
                end
            end)
        end

        Detour(Player, "GiveAmmo", "Player", function(self, count, ammoType, hidePopup)
            local data = GetAmmoData(ammoType)
            if data then
                local keyname = "TBH_AmmoCount_" .. data.name
                local oldCount = self:GetNW2Int(keyname)

                self:SetNW2Int(keyname, oldCount + count)

                if not hidePopup then
                    TBH.Net:Start("hotloader_ammo")
                    net.WriteString(data.name)
                    net.WriteInt(count, 32)
                    net.Send(self)
                end
            end
        end)

        Detour(Player, "RemoveAmmo", "Player", function(self, count, ammoName)
            local data = GetAmmoData(ammoName)
            if data then
                local keyname = "TBH_AmmoCount_" .. data.name
                local newCount = self:GetNW2Int(keyname) - count
                if newCount < 0 then newCount = 0 end

                self:SetNW2Int(keyname, newCount)
            end
        end)

        Detour(Player, "SetAmmo", "Player", function(self, count, ammoType)
            local data = GetAmmoData(ammoType)
            if data then
                self:SetNW2Int("TBH_AmmoCount_" .. data.name, count)
            end
        end)

        Detour(Player, "GetAmmoCount", "Player", function(self, ammoType)
            local data = GetAmmoData(ammoType)
            if data then
                return self:GetNW2Int("TBH_AmmoCount_" .. data.name)
            end
        end)

        Detour(Player, "GetAmmo", "Player", function(self)
            local GetAmmoOriginal = TBH.Detours["Player.GetAmmo"] or Player.GetAmmo
            local ammo = GetAmmoOriginal(self)
            if not istable(ammo) then ammo = {} end

            for id, ammoData in pairs(ammoTypes) do
                local ammoCount = self:GetNW2Int("TBH_AmmoCount_" .. ammoData.name)
                if ammoCount > 0 then
                    ammo[id] = ammoCount
                end
            end

            return ammo
        end)

        QuickDetour("GetAmmoMax", "maxcarry")
        QuickDetour("GetAmmoName", "name")
        QuickDetour("GetAmmoForce", "force")
        QuickDetour("GetAmmoNPCDamage", "npcdmg")
        QuickDetour("GetAmmoDamageType", "dmgtype")
        QuickDetour("GetAmmoPlayerDamage", "plydmg")

        do
            local game_GetAmmoTypes = game.GetAmmoTypes

            Detour(game, "GetAmmoTypes", "game", function()
                local gameAmmoTypes = game_GetAmmoTypes()
                for id, ammoData in pairs(ammoTypes) do
                    gameAmmoTypes[id] = ammoData.name
                end
                return gameAmmoTypes
            end)
        end

        do
            local Weapon = _R.Weapon
            local IsScripted = Weapon.IsScripted
            local IsValidFn = Entity.IsValid

            local function WeaponQuickDetour(key, ammoTabKey)
                Detour(Weapon, key, "Weapon", function(self)
                    local tab = self[ammoTabKey]
                    if (IsValidFn(self) and IsScripted(self)) and (tab and tab.Ammo) then
                        return isTBHAmmo[tab.Ammo]
                    end
                end)
            end

            WeaponQuickDetour("GetPrimaryAmmoType", "Primary")
            WeaponQuickDetour("GetSecondaryAmmoType", "Secondary")
        end

        Detour(game, "AddAmmoType", "game", function(ammoData)
            if not istable(ammoData) or not isstring(ammoData.name) then return end

            local name = ammoData.name

            if not isTBHAmmo[name] and game.GetAmmoID(name) == -1 then
                local id = #game.GetAmmoTypes() + 1
                ammoTypes[id] = ammoData
                isTBHAmmo[name] = id
                return true
            end
        end)

        Detour(game, "GetAmmoID", "game", function(name)
            if isstring(name) then
                return isTBHAmmo[name]
            end
        end)

        Detour(game, "GetAmmoData", "game", function(id)
            return ammoTypes[id]
        end)

        Detour(Entity, "FireBullets", "Entity", function(self, bulletData)
            local ammoType = bulletData.AmmoType
            local id = isTBHAmmo[ammoType]

            if id then
                local data = ammoTypes[id]
                bulletData.AmmoType = REF_AMMO
                bulletData.Tracer = data.tracer or bulletData.Tracer
                bulletData.Force = data.force or bulletData.Force
            end
        end)

        -- weapon pickup: hand out default clips for custom ammo types
        if SERVER and GAMEMODE ~= nil and isfunction(GAMEMODE.PlayerCanPickupWeapon) then
            Detour(GAMEMODE, "PlayerCanPickupWeapon", "GAMEMODE", function(self, ply, wep)
                if IsValid(wep) and wep:IsScripted() then
                    local primary = wep.Primary
                    local secondary = wep.Secondary

                    if istable(primary) and isTBHAmmo[primary.Ammo] and primary.DefaultClip then
                        ply:GiveAmmo(primary.DefaultClip, primary.Ammo)
                    end

                    if istable(secondary) and isTBHAmmo[secondary.Ammo] and secondary.DefaultClip then
                        ply:GiveAmmo(secondary.DefaultClip, secondary.Ammo)
                    end
                end
            end)
        end
    end)
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  WORKSHOP HELPERS
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Reads the addon title straight out of a .gma file header
function TBH.GetGMATitle(path)
    local ok, title = pcall(function()
        local f = file.Open(path, "rb", "GAME")
        if not f then f = file.Open(path, "rb", "MOD") end
        if not f then return nil end

        local result = nil

        if f:Read(4) == "GMAD" then
            f:Skip(1)  -- version
            f:Skip(8)  -- steamid64
            f:Skip(8)  -- timestamp

            -- required content: null-terminated strings, ends with an empty one
            while not f:EndOfFile() do
                local str = {}
                local terminated = false

                while not f:EndOfFile() do
                    local c = f:Read(1)
                    if c == "\0" or c == "" or c == nil then
                        terminated = true
                        break
                    end
                    str[#str + 1] = c
                end

                -- an empty string marks the end of the required content block
                if terminated and #str == 0 then break end
                if f:EndOfFile() then break end
            end

            -- the addon title (null-terminated)
            local chars = {}
            while not f:EndOfFile() do
                local c = f:Read(1)
                if c == "\0" or c == "" or c == nil then break end
                chars[#chars + 1] = c
            end

            result = table.concat(chars)
        end

        f:Close()
        return result
    end)

    if ok then return title end
    return nil
end

-- Scrapes a Workshop page for its "Required Items" links, recursively
function TBH.GetRequiredAddons(wsid, callback, required, pending)
    required = required or {}
    pending = pending or {}

    pending[wsid] = true

    local function CheckDone()
        if next(pending) == nil then
            if isfunction(callback) then
                callback(table.GetKeys(required))
            end
        end
    end

    http.Fetch("https://steamcommunity.com/sharedfiles/filedetails/?id=" .. wsid, function(body)
        for id in string_gmatch(body, '<a href="https://steamcommunity%.com/workshop/filedetails/%?id=(%d+)" target="_blank">') do
            if not required[id] and table.Count(required) < 64 then
                required[id] = true
                TBH.GetRequiredAddons(id, callback, required, pending)
            end
        end

        pending[wsid] = nil
        CheckDone()
    end, function()
        pending[wsid] = nil
        CheckDone()
    end)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  SERVER PIPELINE
--
--  request -> permission check -> (requirements) -> queue ->
--  DownloadUGC (gmsv_workshop) -> MountGMA -> server bundle init ->
--  broadcast to every player -> result tracking -> late-join sync
--
--  Listen servers without the module fall back to routing downloads
--  through the host player's client (chunked file-list transfer).
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if SERVER then
    TBH.Server = {
        Queue = {},
        Current = nil,
        Mounted = {},
        FailedUntil = {},
        PlayerCooldown = {},
        HostBundles = {},
        HostPending = {},
        Sync = {},
        -- collection batch progress (drives the client HUD counter)
        Batch = { title = nil, total = 0, done = 0 },
        AckWait = nil,   -- set while waiting for client sync acks

    }

    --------------------------------------------------------------------
    -- Helpers
    --------------------------------------------------------------------

    local function StatusTo(ply, msg, level)
        if IsValid(ply) then
            TBH.Net:Start("status")
            net.WriteUInt(level or 0, 8)
            net.WriteString(string_sub(msg, 1, 220))
            net.Send(ply)
        else
            -- server console
            local color = TBH.Colors.text
            if level == 1 then color = TBH.Colors.ok end
            if level == 2 then color = TBH.Colors.error end
            if level == 3 then color = TBH.Colors.warn end
            TBH.Msg(msg, color)
        end
    end

    local function ChatBroadcast(msg, level, duration)
        if not TBH.CVarAnnounce:GetBool() then return end

        TBH.Net:Start("chatmsg")
        net.WriteUInt(level or 0, 8)
        net.WriteUInt(isnumber(duration) and math.Clamp(duration, 0, 30) or 0, 8)
        net.WriteString(string_sub(msg, 1, 240))
        net.Broadcast()
    end

    -- v1.1.9: no permission levels any more - every player (host, admin or not) can
    -- hotload, unload and switch maps. unload / map switching / pins all go through here.
    -- NOTE: hotloaded Lua runs on the server, so everyone on the server is trusted
    local function CanHotload(ply)
        return true
    end

    local function FindHostPlayer()
        for _, p in ipairs(player.GetAll()) do
            if p:IsListenServerHost() then return p end
        end
    end

    --------------------------------------------------------------------
    -- Mount + broadcast (shared by both download paths)
    --
    -- v1.1.0: the bundle initialization is frame-spread, so everything
    -- that used to happen right after it (registering the addon,
    -- broadcasting "mount", advancing the queue) moved into the
    -- completion callback - it runs only AFTER the server-side Lua fully
    -- finished initializing the addon.
    --------------------------------------------------------------------

    -- forward declarations (both defined further down; FinalizeMount's
    -- completion callback advances the queue and opens the sync gate)
    local ProcessQueue
    local WaitForClientAcks

    local function WriteMaps(maps)
        local count = istable(maps) and math.min(#maps, 255) or 0
        net.WriteUInt(count, 8)

        for i = 1, count do
            net.WriteString(maps[i])
        end
    end

    --------------------------------------------------------------------
    -- DELIVERY CHECK (v1.1.9): "did it actually reach everybody?"
    --
    -- After a hotload the server remembers every player it sent the addon to and
    -- marks them off as their client reports back. Players that stay silent are
    -- sent the addon again (after 25 s and 70 s - a client that was still loading
    -- its Lua drops messages), and the person who hotloaded it gets a clear result:
    --   * everybody has it                      -> one confirmation
    --   * somebody failed / never answered      -> names + reason, in chat too
    -- (collection members are covered by the sync gate and stay quiet)
    --------------------------------------------------------------------
    TBH.Server.Delivery = TBH.Server.Delivery or {}

    local DELIVERY_RESEND = { [25] = true, [70] = true }
    local DELIVERY_FINAL = 150 -- covers the client's own 3 retries (15 + 45 + 120 s)

    local function DeliveryCount(d)
        local ok, failed, pending = 0, 0, 0

        for _, st in pairs(d.players) do
            if st.state == "ok" then ok = ok + 1
            elseif st.state == "failed" then failed = failed + 1
            else pending = pending + 1 end
        end

        return ok, failed, pending
    end

    -- tells whoever hotloaded it (and the host, if that is somebody else)
    local function DeliveryNotify(d, msg, level)
        local told = {}

        if IsValid(d.requester) then
            StatusTo(d.requester, msg, level)
            told[d.requester] = true
        end

        for _, p in ipairs(player.GetAll()) do
            if p:IsListenServerHost() and not told[p] then StatusTo(p, msg, level) end
        end

        if not IsValid(d.requester) then StatusTo(nil, msg, level) end
    end

    local function DeliveryNames(d, state)
        local names = {}

        for _, st in pairs(d.players) do
            if st.state == state then
                local text = st.name
                if state == "failed" and st.err and st.err ~= "" then text = text .. " (" .. string_sub(st.err, 1, 60) .. ")" end
                names[#names + 1] = text
            end
        end

        table.sort(names)
        return table.concat(names, ", ")
    end

    local function DeliveryStop(wsid)
        timer.Remove("TBH.Delivery." .. wsid)
    end

    local function DeliveryReport(wsid, d, final)
        local ok, failed, pending = DeliveryCount(d)
        local total = ok + failed + pending
        local title = tostring(d.title)

        if failed == 0 and pending == 0 then
            d.finished = true
            DeliveryStop(wsid)
            TBH.Diag("[server] delivery check: '" .. title .. "' reached all " .. total .. " player(s)")
            DeliveryNotify(d, "\"" .. title .. "\" reached everyone (" .. ok .. "/" .. total .. " players have it)", 1)
            return
        end

        if not final then return end

        d.finished = true
        DeliveryStop(wsid)

        local parts = { "Delivery check for \"" .. title .. "\": " .. ok .. "/" .. total .. " players have it." }
        if pending > 0 then parts[#parts + 1] = "No answer from: " .. DeliveryNames(d, "pending") .. " (is the hotloader running for them?)." end
        if failed > 0 then parts[#parts + 1] = "Failed: " .. DeliveryNames(d, "failed") .. "." end
        parts[#parts + 1] = "They can type hotloader_resync."

        local msg = table.concat(parts, " ")
        TBH.Diag("[server] delivery check FINAL: " .. msg)
        DeliveryNotify(d, msg, 3)
        ChatBroadcast(msg, 3)
    end

    local function DeliveryResend(wsid, d, seconds)
        local targets = {}

        for ply, st in pairs(d.players) do
            if IsValid(ply) and st.state == "pending" then
                st.attempts = st.attempts + 1
                targets[#targets + 1] = ply
            end
        end

        if #targets == 0 then return end

        local mounted = TBH.Server.Mounted[wsid]

        TBH.Net:Start("mount")
        net.WriteString(wsid)
        net.WriteString(d.title)
        WriteMaps(mounted and mounted.maps or {})
        net.Send(targets)

        TBH.Diag("[server] delivery check: no answer after " .. seconds .. "s - resent '" .. tostring(d.title) .. "' to " .. #targets .. " player(s)")
    end

    local function DeliveryStart(wsid, title, requester, targets)
        local d = { wsid = wsid, title = title, requester = requester, started = CurTime(), players = {} }

        for _, p in ipairs(targets) do
            d.players[p] = { state = "pending", attempts = 1, name = p:Nick() }
        end

        TBH.Server.Delivery[wsid] = d

        local ticks = 0

        timer.Create("TBH.Delivery." .. wsid, 5, 0, function()
            ticks = ticks + 1
            local t = ticks * 5

            -- players who left are no longer expected to answer
            for ply in pairs(d.players) do
                if not IsValid(ply) then d.players[ply] = nil end
            end

            if next(d.players) == nil then
                d.finished = true
                DeliveryStop(wsid)
                return
            end

            DeliveryReport(wsid, d, false)
            if d.finished then return end

            if DELIVERY_RESEND[t] then DeliveryResend(wsid, d, t) end

            if t >= DELIVERY_FINAL then DeliveryReport(wsid, d, true) end
        end)
    end

    -- a client reported its result for an addon
    local function DeliveryOnResult(ply, wsid, ok, err)
        local d = TBH.Server.Delivery[wsid]
        if not d or d.finished then return end

        local st = d.players[ply]
        if not st then return end

        if ok then
            st.state, st.err = "ok", nil
        else
            st.state, st.err = "failed", err
        end

        DeliveryReport(wsid, d, false)
    end

    TBH.Server.DeliveryStart = DeliveryStart
    TBH.Server.DeliveryOnResult = DeliveryOnResult

    concommand.Add("hotloader_delivery", function(ply)
        local any = false

        for wsid, d in pairs(TBH.Server.Delivery) do
            local ok, failed, pending = DeliveryCount(d)
            any = true

            local line = "\"" .. tostring(d.title) .. "\" (" .. wsid .. "): " .. ok .. " ok, " .. failed .. " failed, " .. pending .. " waiting"
            if pending > 0 then line = line .. " - waiting on " .. DeliveryNames(d, "pending") end
            if failed > 0 then line = line .. " - failed: " .. DeliveryNames(d, "failed") end

            StatusTo(IsValid(ply) and ply or nil, line, (failed > 0 or pending > 0) and 3 or 1)
        end

        if not any then StatusTo(IsValid(ply) and ply or nil, "No hotload delivery to check yet", 0) end
    end)

    local function FinalizeMount(wsid, title, files, requester, skipHost, quiet)
        local cleanFiles, seen = {}, {}
        for _, f in pairs(files) do
            if not seen[f] then
                seen[f] = true
                cleanFiles[#cleanFiles + 1] = f
            end
        end

        local maps = TBH.ExtractMaps(cleanFiles)

        local bundle = TBH.Bundle:Create(cleanFiles, title)

        bundle:Initialize(function(b)
            TBH.Diag("[server] server init COMPLETE for '" .. string_sub(tostring(title), 1, 50) .. "' (" .. #b.Errors .. " lua error(s)) - registering + broadcasting")

            local ok, err = pcall(function()
                TBH.Server.Mounted[wsid] = {
                    title = title,
                    files = #cleanFiles,
                    time = os.time(),
                    errors = #b.Errors,
                    maps = maps,
                    bundle = b,
                    unloaded = false,
                }

                -- tell every player to grab it too
                local targets = {}
                for _, p in ipairs(player.GetAll()) do
                    if not (skipHost and p:IsListenServerHost()) then
                        targets[#targets + 1] = p
                    end
                end

                if #targets > 0 then
                    TBH.Net:Start("mount")
                    net.WriteString(wsid)
                    net.WriteString(title)
                    WriteMaps(maps)
                    net.Send(targets)

                    TBH.Diag("[server] mount broadcast sent to " .. #targets .. " player(s)")

                    if not quiet then
                        TBH.Server.DeliveryStart(wsid, title, requester, targets)
                    end
                else
                    TBH.Diag("[server] no players to broadcast to")
                end

                local mapInfo = ""

                if #maps > 0 then
                    local preview = maps[1]
                    if #maps > 1 then preview = preview .. " (+" .. (#maps - 1) .. " more)" end
                    mapInfo = " - contains map \"" .. preview .. "\" - hit LOAD MAP in the Q menu!"
                end

                -- collection members announce quietly (the collection itself already
                -- got one big announcement - 30 chat lines is spam, not info)
                if not quiet then
                    ChatBroadcast("Hotloaded \"" .. title .. "\" (" .. #cleanFiles .. " files)" .. mapInfo, 1)
                else
                    -- batch progress: every member completion updates the counter
                    local batch = TBH.Server.Batch
                    batch.done = (batch.done or 0) + 1

                    TBH.Diag("[server] batch progress: " .. batch.done .. "/" .. (batch.total or 0) .. " members done")

                    TBH.Net:Start("batchprog")
                    net.WriteUInt(math.Clamp(batch.done, 0, 255), 8)
                    net.WriteUInt(math.Clamp(batch.total or 0, 0, 255), 8)
                    net.WriteString(string_sub(batch.title or title, 1, 100))
                    net.Broadcast()
                end

                if #maps > 0 then
                    StatusTo(requester, "\"" .. title .. "\" hotloaded! Map(s): " .. table.concat(maps, ", "), 1)
                else
                    StatusTo(requester, "\"" .. title .. "\" hotloaded on the server!", 1)
                end

                -- result tracking (best effort summary after 90 seconds)
                TBH.Server.Sync[wsid] = { ok = 0, failed = 0, total = #targets, failedNames = {} }

                timer.Simple(90, function()
                    local track = TBH.Server.Sync[wsid]
                    if not track or track.reported then return end
                    track.reported = true

                    -- the delivery check reports (with names) for normal hotloads; this older
                    -- summary only stays for collection members
                    if track.failed > 0 and (quiet or not TBH.Server.Delivery[wsid]) then
                        ChatBroadcast(track.failed .. "/" .. track.total .. " players failed to sync \"" .. title .. "\" (see server console)", 3)
                    end
                end)

                hook.Run("TBH.ServerHotloaded", wsid, title, b)
            end)

            if not ok then
                TBH.LogError("FinalizeMount crashed: " .. tostring(err))
                TBH.Diag("[server] FinalizeMount completion CRASHED: " .. string_sub(tostring(err), 1, 200))
                StatusTo(requester, "Hotload of \"" .. title .. "\" crashed during initialization (see server console)", 2)
            end

            -- release the queue slot and advance the pipeline
            timer.Remove("TBH.AdvanceGuard." .. wsid)

            if TBH.Server.Current == wsid then
                TBH.Server.Current = nil

                -- BATCH MEMBERS: wait until EVERY client finished syncing
                -- THIS addon before the next one starts (fully sequential -
                -- one addon at a time, server and clients together)
                if quiet then
                    local settle = math.Clamp(TBH.CVarBatchDelay:GetInt(), 1, 30)
                    TBH.Diag("[server] opening client sync gate for " .. wsid .. " (next member waits for every player + " .. settle .. "s settle)")
                    WaitForClientAcks(wsid, function()
                        TBH.Diag("[server] gate passed - starting next member in " .. settle .. "s")
                        timer.Simple(settle, ProcessQueue)
                    end)
                else
                    TBH.Diag("[server] non-batch hotload done - next queue entry in 1s")
                    timer.Simple(1, ProcessQueue)
                end
            end
        end)

        return bundle
    end

    --------------------------------------------------------------------
    -- CLIENT SYNC GATE ("wait for the others to finish")
    --
    -- The server must NOT start the next collection member until every
    -- connected client has finished downloading + mounting + initializing
    -- the current one (clients report this via the "result" message).
    -- This makes batches FULLY sequential end-to-end instead of paced by
    -- guessed delays - one addon at a time, server and clients together.
    --------------------------------------------------------------------

    -- NOTE: the callback parameter must NOT be named with the C-style
    -- loop-skip keyword - GLua treats it as a reserved word even where
    -- plain Lua 5.1 accepts it as an identifier (that exact bug shipped
    -- once). The assembler now hard-fails on that token.
    WaitForClientAcks = function(wsid, proceed)
        local pending, count = {}, 0

        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and not p:IsBot() then
                pending[p:SteamID()] = true
                count = count + 1
            end
        end

        -- nobody to wait for (empty server) -> straight on
        if count == 0 then
            TBH.Diag("[server] sync gate: no human players - nothing to wait for")
            return proceed()
        end

        local finished = false

        local function Complete()
            if finished then return end
            finished = true
            timer.Remove("TBH.AckWait")
            if TBH.Server.AckWait and TBH.Server.AckWait.wsid == wsid then
                TBH.Server.AckWait = nil
            end
            proceed()
        end

        TBH.Server.AckWait = {
            wsid = wsid,
            pending = pending,
            Complete = Complete,
        }

        -- safety valve: a stuck/disconnected client must never stall the
        -- whole collection forever.
        --
        -- v1.1.0: the FULL download timeout is allowed now. Collection
        -- members can be hundreds of megabytes; the old half-timeout gave
        -- up while clients were still legitimately downloading, piled the
        -- next members onto busy clients and froze/crashed their games.
        local maxWait = math.Clamp(TBH.CVarTimeout:GetInt(), 30, 300)

        TBH.Diag("[server] sync gate OPEN for " .. wsid .. " - waiting for " .. count .. " player(s), max " .. maxWait .. "s")

        timer.Create("TBH.AckWait", maxWait, 1, function()
            if not finished then
                finished = true
                if TBH.Server.AckWait and TBH.Server.AckWait.wsid == wsid then
                    TBH.Server.AckWait = nil
                end
                TBH.Diag("[server] sync gate TIMED OUT after " .. maxWait .. "s - carrying on without the stragglers")
                TBH.Msg("Batch gate timed out after " .. maxWait .. "s waiting for client syncs - carrying on")
                proceed()
            end
        end)
    end

    -- a client reported a sync result: maybe that completes the gate.
    -- v1.1.0: the ack only counts when it is for the addon the gate is
    -- actually waiting on - results for any other addon used to open the
    -- gate early and break the one-at-a-time sequencing.
    local function FeedAck(ply, wsid)
        local ack = TBH.Server.AckWait

        if ack and IsValid(ply) and not ply:IsBot() and ack.wsid == wsid then
            ack.pending[ply:SteamID()] = nil

            local remaining = table.Count(ack.pending)

            TBH.Diag("[server] sync ack from '" .. ply:Nick() .. "' for " .. wsid .. " (" .. remaining .. " player(s) left)")

            if table.IsEmpty(ack.pending) and ack.Complete then
                TBH.Diag("[server] sync gate COMPLETE - every player synced " .. wsid)
                ack.Complete()
            end
        end
    end

    hook.Add("PlayerDisconnected", "TBH.AckPlayerLeft", function(ply)
        -- a leaving player can never ack: drop them from any open gate
        local ack = TBH.Server.AckWait

        if ack and IsValid(ply) and not ply:IsBot() then
            ack.pending[ply:SteamID()] = nil

            if table.IsEmpty(ack.pending) and ack.Complete then
                ack.Complete()
            end
        end
    end)

    --------------------------------------------------------------------
    -- Queue processing (module / native server download path)
    --------------------------------------------------------------------

    ProcessQueue = function()
        if TBH.Server.Current ~= nil then return end

        local entry = table.remove(TBH.Server.Queue, 1)

        -- queue drained + a batch was running -> collection complete
        if not entry then
            local batch = TBH.Server.Batch

            if batch and batch.total and batch.total > 0 then
                TBH.Diag("[server] queue drained - collection batch COMPLETE: " .. (batch.done or 0) .. "/" .. batch.total)

                TBH.Server.Batch = { title = nil, total = 0, done = 0 }

                TBH.Net:Start("batchend")
                net.WriteUInt(math.Clamp(batch.total, 0, 255), 8)
                net.WriteString(string_sub(batch.title or "collection", 1, 100))
                net.Broadcast()

                TBH.Msg("Collection batch complete: " .. (batch.done or 0) .. "/" .. batch.total .. " addons (" .. tostring(batch.title or "?") .. ")")

                -- keep logging briefly for late acks, then close the file
                timer.Simple(10, function()
                    TBH.DiagEnd("server batch complete")
                end)
            end

            return
        end

        local wsid = entry.wsid
        local title = entry.title or wsid
        TBH.Server.Current = wsid

        if entry.quiet then
            local done = (TBH.Server.Batch.done or 0)
            local total = (TBH.Server.Batch.total or 0)
            TBH.Diag("[server] member " .. (done + 1) .. "/" .. total .. ": '" .. string_sub(tostring(title), 1, 50) .. "' (" .. wsid .. ") - " .. #TBH.Server.Queue .. " still queued")
        else
            TBH.Diag("[server] hotload starting: '" .. string_sub(tostring(title), 1, 50) .. "' (" .. wsid .. ")")
        end

        local timeout = math.Clamp(TBH.CVarTimeout:GetInt(), 30, 900)
        local finished = false

        local function Finish(errMsg)
            if finished then return end
            finished = true

            timer.Remove("TBH.DL." .. wsid)

            if errMsg then
                TBH.Server.Current = nil

                -- LISTEN SERVER fallback (v1.1.9): the server-side downloader (gmsv_workshop)
                -- could not fetch it - on a listen server that module is unreliable, but the host
                -- player's own game is logged in to Steam and normally can. try that before
                -- giving up, so the addon still reaches everybody (collections excluded: they
                -- would hammer one client with parallel downloads)
                if not entry.quiet and not game.IsDedicated() and string.find(tostring(errMsg), "download", 1, true) then
                    local host = FindHostPlayer()

                    if IsValid(host) and not TBH.Server.HostPending[wsid] then
                        TBH.Diag("[server] server-side download failed (" .. tostring(errMsg) .. ") - FALLING BACK to the host player's game")

                        TBH.Server.HostPending[wsid] = { requester = entry.requester }
                        StatusTo(entry.requester, "The server could not download it - trying through the host player's game instead...", 3)

                        timer.Create("TBH.HostWait." .. wsid, 90, 1, function()
                            if TBH.Server.HostPending[wsid] then
                                TBH.Server.HostPending[wsid] = nil
                                TBH.Server.FailedUntil[wsid] = CurTime() + 60
                                StatusTo(entry.requester, "Host download of " .. wsid .. " timed out", 2)
                            end
                        end)

                        TBH.Net:Start("hostdl")
                        net.WriteString(wsid)
                        net.WriteString(title or "")
                        net.Send(host)

                        -- the host route runs on its own; free the queue slot
                        timer.Simple(1, ProcessQueue)
                        return
                    end
                end

                TBH.Server.FailedUntil[wsid] = CurTime() + 60
                TBH.Diag("[server] member FAILED: " .. tostring(errMsg))
                StatusTo(entry.requester, "Hotload of \"" .. title .. "\" failed: " .. errMsg, 2)
                TBH.LogError("Hotload of " .. wsid .. " failed: " .. errMsg)

                -- failed before the broadcast: no client will ever ack
                -- this one - just pace a little and carry on
                local settle = entry.quiet and math.Clamp(TBH.CVarBatchDelay:GetInt(), 1, 30) or 1
                timer.Simple(settle, ProcessQueue)
                return
            end

            -- Success: the download finished and FinalizeMount is now
            -- running its frame-spread initialization. Its completion
            -- callback owns releasing the slot and advancing the queue
            -- (for batch members: only after every client synced THIS
            -- addon). Arm a stall valve in case that completion never
            -- fires (lost timer, map change mid-init, anything).
            local function Valve()
                if TBH.Server.Current ~= wsid then return end

                -- a client-sync gate is still open - give it more time
                if TBH.Server.AckWait then
                    timer.Create("TBH.AdvanceGuard." .. wsid, 120, 1, Valve)
                    return
                end

                TBH.Server.Current = nil
                TBH.Msg("Stall valve: initialization of \"" .. title .. "\" never completed - skipping it")
                ProcessQueue()
            end

            timer.Create("TBH.AdvanceGuard." .. wsid, timeout + 300, 1, Valve)
        end

        timer.Create("TBH.DL." .. wsid, timeout, 1, function()
            Finish("download timed out after " .. timeout .. "s")
        end)

        TBH.Diag("[server] DownloadUGC CALLING for " .. wsid .. " (watchdog " .. timeout .. "s)")

        StatusTo(entry.requester, "Downloading \"" .. title .. "\" on the server...", 0)
        TBH.Msg("Downloading workshop addon " .. wsid .. " (" .. title .. ")...")

        -- SAFEGUARD: the CALL itself can throw - release the slot if so
        local okCall = pcall(steamworks.DownloadUGC, wsid, function(path, gmaFile)
            -- SAFEGUARD: an error in here must still release the queue slot
            local okCB, errCB = pcall(function()
            if finished then return end

            TBH.Diag("[server] DownloadUGC callback fired for " .. wsid)

            if not path or not gmaFile then
                return Finish("download failed (addon hidden, removed, or Steam unreachable?)")
            end

            local notAddon = TBH.WhyNotAnAddon(path)
            if notAddon then
                return Finish("skipped, " .. notAddon)
            end

            TBH.Diag("[server] MountGMA CALLING (can freeze + crash on huge addons): " .. tostring(path))

            local ok, files = game.MountGMA(path)

            if not ok or not istable(files) then
                return Finish("game.MountGMA failed")
            end

            TBH.Diag("[server] MountGMA ok: " .. #files .. " files mounted")

            -- V.1.0.6: remember the server-side GMA path - FULL unload (via
            -- the gmaunmount module) needs the exact path the engine mounted
            TBH.Server.GmaPaths = TBH.Server.GmaPaths or {}
            TBH.Server.GmaPaths[wsid] = path

            local maxFiles = TBH.CVarMaxFiles:GetInt()
            if #files > maxFiles then
                return Finish("addon has " .. #files .. " files (limit: " .. maxFiles .. ", raise hotloader_max_files)")
            end

            local gmaTitle = TBH.GetGMATitle(path)
            if gmaTitle and #gmaTitle > 0 then
                title = gmaTitle
            end

            TBH.Diag("[server] FinalizeMount CALLING (bundle create + frame-spread init) for " .. wsid)

            local okFinalize, errFinalize = pcall(FinalizeMount, wsid, title, files, entry.requester, false, entry.quiet)

            if not okFinalize then
                TBH.LogError("FinalizeMount crashed: " .. tostring(errFinalize))
                StatusTo(entry.requester, "Hotload of \"" .. title .. "\" crashed during initialization (see server console)", 2)
                return Finish("internal error: initialization crashed")
            end

            Finish(nil)
            end)

            if not okCB then
                Finish("internal error: " .. tostring(errCB))
            end
        end)

        if not okCall then
            Finish("download could not start (engine/module error?)")
        end
    end

    --------------------------------------------------------------------
    -- Queueing + requirement chains
    --------------------------------------------------------------------

    local function Enqueue(wsid, title, requester, ignoreCap, quiet)
        if not ignoreCap and #TBH.Server.Queue >= TBH.CVarMaxQueue:GetInt() then
            StatusTo(requester, "Hotload queue is full (" .. TBH.CVarMaxQueue:GetInt() .. ") - try again later", 3)
            return false
        end

        TBH.Server.Queue[#TBH.Server.Queue + 1] = {
            wsid = wsid,
            title = title,
            requester = requester,
            quiet = quiet or false,
        }

        return true
    end

    local function AlreadyKnown(wsid)
        if TBH.Server.Mounted[wsid] then
            return "already hotloaded (" .. (TBH.Server.Mounted[wsid].title or wsid) .. ")"
        end

        if TBH.Server.Current == wsid then
            return "already downloading right now"
        end

        for i = 1, #TBH.Server.Queue do
            if TBH.Server.Queue[i].wsid == wsid then
                return "already in the queue"
            end
        end

        return nil
    end

    --------------------------------------------------------------------
    -- Steam Web API helpers (v1.1.2)
    --
    -- WHY: the workshop page does not always show its collection markers
    -- (login walls, age gates, region blocks, layout changes). When that
    -- happened, a COLLECTION link was misread as a single addon and the
    -- downloader was pointed at the collection id itself - a prime crash
    -- suspect ("press hotload, freeze 5s, crash to desktop"). These
    -- keyless public API endpoints give a reliable second opinion:
    --   GetPublishedFileDetails -> file_type (2 = collection)
    --   GetCollectionDetails    -> the member list (addons only)
    --------------------------------------------------------------------

    local API_FILE_DETAILS = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
    local API_COLLECTION_DETAILS = "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/"

    local function SteamAPIRequest(endpoint, params, callback)
        -- v1.1.3: previously used http.Post(), which silently dropped the
        -- form body on listen servers - Steam would reply 400 "Required
        -- parameter 'itemcount' is missing" and our code mis-interpreted
        -- that as "the API is unreachable", which steered collection ids
        -- into steamworks.DownloadUGC (native crash). The proven fix is
        -- to call HTTP() directly with the `parameters` table field, which
        -- GMod properly URL-encodes into the POST body (Content-Type:
        -- application/x-www-form-urlencoded). This is the same pattern
        -- VLL2 / DToyBox use, and they can hotload this exact collection
        -- on listen servers - so the Steam API IS reachable from there.
        --
        -- v1.1.4: ALWAYS log a response summary line (status + bytes +
        -- 200-char preview) - even on success. Without this we had a
        -- blind spot where Steam returned 200 + unexpected JSON shape
        -- and we silently dispatched(nil) → REFUSED with no clue why.
        -- Also: check the return value of HTTP() - if it returns false
        -- (request refused to start), no callback will ever fire, so we
        -- must dispatch immediately. Also: a watchdog timer in case
        -- Steam never responds at all.
        TBH.Diag("[server] Steam Web API POST -> " .. endpoint)

        local fired = false
        local function Dispatch(result)
            if fired then return end
            fired = true
            if timer.Exists("TBH.APIWatchdog") then timer.Remove("TBH.APIWatchdog") end
            callback(result)
        end

        -- v1.1.4 watchdog: if neither success nor failed fires within
        -- 18s, force a dispatch. Without this, a hung HTTP request would
        -- leave the diag log hanging forever (no REFUSED line ever logs).
        timer.Create("TBH.APIWatchdog", 18, 1, function()
            if not fired then
                TBH.Diag("[server] Steam API WATCHDOG: no response within 18s - assuming the request hung. Dispatching nil.")
                Dispatch(nil)
            end
        end)

        local req = {
            method = "POST",
            url = endpoint,
            parameters = params,
            timeout = 15,
            headers = {
                ["User-Agent"] = "TBH-Hotloader/1.1.7",
                ["Accept"] = "application/json",
                ["Accept-Charset"] = "utf-8",
            },
            success = function(code, body, headers)
                if not isstring(body) then body = tostring(body or "") end

                -- v1.1.4: ALWAYS log a summary line so we know Steam
                -- actually responded - even when the JSON parses fine.
                local preview = string_sub(body, 1, 200)
                TBH.Diag("[server] Steam API HTTP " .. tostring(code) .. " (body " .. #body .. " bytes)")
                if preview ~= "" then
                    TBH.Diag("[server] response preview: " .. preview)
                end

                if code ~= 200 or body == "" then
                    return Dispatch(nil)
                end

                local okJson, tbl = pcall(util.JSONToTable, body)
                if not okJson or not istable(tbl) then
                    local parseErr = okJson and "table check failed" or tostring(tbl)
                    TBH.Diag("[server] Steam API JSON parse FAILED: " .. parseErr .. " (first 200 chars: " .. string_sub(body, 1, 200) .. ")")
                    return Dispatch(nil)
                end

                -- v1.1.4: log the top-level response keys so we can see
                -- what Steam actually sent back if the structure isn't
                -- what GetFileType / GetCollectionChildren expect.
                local keys = {}
                if istable(tbl) then
                    for k, _ in pairs(tbl) do
                        keys[#keys + 1] = tostring(k)
                    end
                end
                TBH.Diag("[server] Steam API JSON parsed OK - top-level keys: {" .. table.concat(keys, ", ") .. "}")

                Dispatch(tbl)
            end,
            failed = function(reason)
                TBH.Diag("[server] Steam API request FAILED (network / unreachable): " .. tostring(reason))
                Dispatch(nil)
            end,
        }

        -- v1.1.4: HTTP() returns true if the request was started, false
        -- if it refused (HTTP library unavailable, URL malformed, SSL
        -- handshake refused, etc.). When it returns false, NEITHER
        -- success NOR failed is ever called - so we must dispatch here.
        local started
        local ok, err = pcall(function() started = HTTP(req) end)

        if not ok then
            TBH.Diag("[server] HTTP() threw (GMod HTTP library unavailable?): " .. tostring(err))
            Dispatch(nil)
        elseif started == false then
            TBH.Diag("[server] HTTP() refused to start the request (returned false) - usually means: HTTP is disabled by the server, the URL is on a blocklist, or an SSL/TLS handshake was refused. No callback will fire.")
            Dispatch(nil)
        end
    end

    -- callback(file_type, title, details) - file_type nil = API unreachable/unknown.
    -- v1.1.5: the FULL details table is also returned (third arg) so callers
    -- can inspect any field Steam included - notably `hcontent_file` (GMA
    -- content hash, present for real addons, absent for collections) and
    -- `children` (present for collections via this endpoint, in some Steam
    -- responses). Steam has stopped returning `file_type` reliably for
    -- collections, so the details table is now the authoritative source.
    local function GetFileType(wsid, callback)
        SteamAPIRequest(API_FILE_DETAILS,
            { itemcount = "1", ["publishedfileids[0]"] = tostring(wsid) },
            function(tbl)
                -- v1.1.4: log EVERY structural failure so we can see what
                -- Steam actually returned. The previous build silently
                -- called callback(nil) on any unexpected shape, leaving
                -- us with no idea why a 200 OK response was rejected.
                if not istable(tbl) then
                    TBH.Diag("[server] GetFileType: Steam API returned a non-table result - cannot determine file_type")
                    return callback(nil)
                end

                if not istable(tbl.response) then
                    TBH.Diag("[server] GetFileType: Steam response had no `response` field - cannot determine file_type")
                    return callback(nil)
                end

                local pfd = tbl.response.publishedfiledetails
                if not istable(pfd) then
                    TBH.Diag("[server] GetFileType: Steam response had no `publishedfiledetails` array - cannot determine file_type (response.result=" .. tostring(tbl.response.result) .. ", message=" .. tostring(tbl.response.message) .. ")")
                    return callback(nil)
                end

                local det = pfd[1]
                if not istable(det) then
                    TBH.Diag("[server] GetFileType: Steam response `publishedfiledetails` was an empty array (0 entries)")
                    return callback(nil)
                end

                if det.result ~= 1 then
                    TBH.Diag("[server] GetFileType: publishedfiledetails[1].result = " .. tostring(det.result) .. " (expected 1) - message: " .. tostring(det.message or "(none)") .. " - this id may not exist on the workshop, or it may have been removed")
                    return callback(nil)
                end

                local ft = tonumber(det.file_type)
                -- v1.1.5: log presence of the key disambiguation fields so
                -- the diagnostic log tells the FULL story of what Steam sent.
                local hasHcontent = isstring(det.hcontent_file) and det.hcontent_file ~= ""
                local childCount = istable(det.children) and #det.children or 0
                TBH.Diag("[server] GetFileType: OK - file_type = " .. tostring(det.file_type) .. " (parsed: " .. tostring(ft) .. "), title = " .. tostring(det.title) .. ", hcontent_file = " .. (hasHcontent and ("present (" .. #det.hcontent_file .. " chars)") or "ABSENT") .. ", children = " .. (istable(det.children) and (childCount .. " entries") or "ABSENT"))
                callback(ft, isstring(det.title) and det.title or nil, det)
            end)
    end

    -- callback(children) - array of { wsid, file_type }, or nil on failure
    local function GetCollectionChildren(wsid, callback)
        SteamAPIRequest(API_COLLECTION_DETAILS,
            { collectioncount = "1", ["publishedfileids[0]"] = tostring(wsid) },
            function(tbl)
                -- v1.1.4: same diagnostic treatment as GetFileType - log
                -- every structural failure so we know exactly what Steam
                -- returned instead of silently returning nil.
                if not istable(tbl) then
                    TBH.Diag("[server] GetCollectionChildren: Steam API returned a non-table result - cannot enumerate")
                    return callback(nil)
                end

                if not istable(tbl.response) then
                    TBH.Diag("[server] GetCollectionChildren: Steam response had no `response` field - cannot enumerate")
                    return callback(nil)
                end

                local cd = tbl.response.collectiondetails
                if not istable(cd) then
                    TBH.Diag("[server] GetCollectionChildren: Steam response had no `collectiondetails` array - cannot enumerate (response.result=" .. tostring(tbl.response.result) .. ", message=" .. tostring(tbl.response.message) .. ")")
                    return callback(nil)
                end

                local det = cd[1]
                if not istable(det) then
                    TBH.Diag("[server] GetCollectionChildren: Steam response `collectiondetails` was an empty array (0 entries)")
                    return callback(nil)
                end

                if det.result ~= 1 then
                    TBH.Diag("[server] GetCollectionChildren: collectiondetails[1].result = " .. tostring(det.result) .. " (expected 1) - message: " .. tostring(det.message or "(none)") .. " - this collection may not exist or may have been removed")
                    return callback(nil)
                end

                if not istable(det.children) then
                    TBH.Diag("[server] GetCollectionChildren: collectiondetails[1] has no `children` field - the collection exists but has no members, or Steam hid them")
                    return callback(nil)
                end

                local out = {}
                for i = 1, #det.children do
                    local child = det.children[i]

                    if istable(child) and isstring(child.publishedfileid) then
                        -- v1.1.6: Steam is inconsistent here. For the PARENT
                        -- item in GetPublishedFileDetails, the field is
                        -- `file_type` (underscore). For collection CHILDREN
                        -- in GetCollectionDetails, the field is `filetype`
                        -- (NO underscore). The previous build only checked
                        -- `file_type` -> every child got file_type=-1 ->
                        -- EnumerateCollectionMembers silently dropped ALL of
                        -- them -> "API member enumeration FAILED" even though
                        -- Steam HAD returned 24 valid children. Accept BOTH
                        -- spellings. If neither is present, default to 0
                        -- (addon) - this matches VLL2's pattern of treating
                        -- every collection child as an addon to hotload.
                        local ft = tonumber(child.file_type) or tonumber(child.filetype) or 0
                        out[#out + 1] = {
                            wsid = child.publishedfileid,
                            file_type = ft,
                        }
                    end
                end

                TBH.Diag("[server] GetCollectionChildren: OK - enumerated " .. #out .. " child(ren) from collection")
                callback(out)
            end)
    end

    -- Sequentially enumerates a collection (addons only, recursing into
    -- nested collections, capped by hotloader_max_collection). callback(members)
    local function EnumerateCollectionMembers(rootId, callback)
        local members, seen, queue = {}, { [tostring(rootId)] = true }, { tostring(rootId) }
        local maxTotal = math.Clamp(TBH.CVarMaxCollection:GetInt(), 1, 100)

        local function Pump()
            local id = table.remove(queue, 1)

            if not id or #members >= maxTotal then
                return callback(members)
            end

            GetCollectionChildren(id, function(children)
                if istable(children) then
                    for i = 1, #children do
                        local child = children[i]

                        if not seen[child.wsid] then
                            seen[child.wsid] = true

                            -- v1.1.6: only recurse into children we KNOW are
                            -- collections (file_type=2). Anything else
                            -- (file_type=0 addon, or -1 unknown after the
                            -- filetype-vs-file_type fix above) is treated as
                            -- a downloadable addon and enqueued. This matches
                            -- VLL2's pattern: every collection child is
                            -- assumed to be an addon to hotload.
                            if child.file_type == 2 then
                                -- nested collection: enumerate it too
                                queue[#queue + 1] = child.wsid
                            else
                                if #members < maxTotal then
                                    members[#members + 1] = { wsid = child.wsid, title = "workshop item " .. child.wsid }
                                end
                            end
                        end
                    end
                else
                    TBH.Diag("[server] could not enumerate (nested) collection " .. tostring(id) .. " via the API - skipping it")
                end

                Pump()
            end)
        end

        Pump()
    end

    function TBH.Server.Request(ply, input, includeReqs, titleHint)
        local allowed, reason = CanHotload(ply)
        if not allowed then
            StatusTo(ply, "Permission denied: " .. tostring(reason), 2)
            return
        end

        local wsid = TBH.ExtractWSID(input)
        if not wsid then
            StatusTo(ply, "That doesn't look like a workshop id or url", 2)
            return
        end

        -- per-player cooldown
        if IsValid(ply) then
            local sid = ply:SteamID()
            local cooldownUntil = TBH.Server.PlayerCooldown[sid] or 0

            if CurTime() < cooldownUntil then
                StatusTo(ply, "Cooling down - wait " .. math.ceil(cooldownUntil - CurTime()) .. "s", 3)
                return
            end

            TBH.Server.PlayerCooldown[sid] = CurTime() + TBH.CVarCooldown:GetInt()
        end

        local known = AlreadyKnown(wsid)
        if known then
            StatusTo(ply, "Skipping " .. wsid .. ": " .. known, 3)
            return
        end

        local failUntil = TBH.Server.FailedUntil[wsid] or 0
        if CurTime() < failUntil then
            StatusTo(ply, "That addon recently failed - retry in " .. math.ceil(failUntil - CurTime()) .. "s", 3)
            return
        end

        local title = (isstring(titleHint) and titleHint ~= "") and titleHint or nil

        -- fast path: dedicated server without the download module
        if not TBH.ServerCanUGC and game.IsDedicated() then
            StatusTo(ply, "The gmsv_workshop module is not installed - dedicated servers need it to download addons!", 2)
            TBH.LogError("Hotload requested but gmsv_workshop is missing.")
            TBH.LogError("Install it from https://github.com/nooshstuff/gmsv_workshop/releases (v3.0.4+)")
            TBH.LogError("64-bit server: gmsv_workshop_win64.dll or gmsv_workshop_linux64.dll -> garrysmod/lua/bin/")
            return
        end

        --------------------------------------------------------------------
        -- COLLECTION HOTLOADING (the standout feature)
        --
        -- Paste a Workshop COLLECTION link and the entire collection
        -- hotloads. The same filedetails URL serves collections, so we
        -- fetch the page once, spot the collection markers and enqueue
        -- every member. (Neither WSHL nor DTOybox can do this.)
        --------------------------------------------------------------------

        local function HandleAddon(id, idTitle, reqs)
            ----------------------------------------------------------------
            -- Listen server fallback: host client downloads for us
            ----------------------------------------------------------------
            if not TBH.ServerCanUGC then
                TBH.Diag("[server] no gmsv_workshop module - routing the download through the HOST PLAYER's client")
                local host = FindHostPlayer()
                if not IsValid(host) then
                    StatusTo(ply, "Host player not found yet - try again in a few seconds", 3)
                    return
                end

                if reqs and TBH.CVarRequirements:GetBool() then
                    StatusTo(ply, "Note: requirement chains need the gmsv_workshop module - loading the main addon only", 3)
                end

                if TBH.Server.HostPending[id] then
                    StatusTo(ply, "Already routing that one through the host player", 3)
                    return
                end

                TBH.Server.HostPending[id] = { requester = ply }
                StatusTo(ply, "Routing download through the host player (no gmsv_workshop module)...", 0)

                timer.Create("TBH.HostWait." .. id, 90, 1, function()
                    if TBH.Server.HostPending[id] then
                        TBH.Server.HostPending[id] = nil
                        TBH.Server.FailedUntil[id] = CurTime() + 60
                        StatusTo(ply, "Host download of " .. id .. " timed out", 2)
                    end
                end)

                TBH.Net:Start("hostdl")
                net.WriteString(id)
                net.WriteString(idTitle or "")
                net.Send(host)

                return
            end

            ----------------------------------------------------------------
            -- Requirements chain
            ----------------------------------------------------------------
            if reqs and TBH.CVarRequirements:GetBool() then
                StatusTo(ply, "Checking required addons for \"" .. (idTitle or id) .. "\"...", 0)

                local fired = false

                local function Proceed(reqIds)
                    if fired then return end
                    fired = true
                    timer.Remove("TBH.ReqTimeout." .. id)

                    local toLoad = {}
                    for i = 1, #reqIds do
                        local rid = reqIds[i]
                        if not AlreadyKnown(rid) then
                            toLoad[#toLoad + 1] = rid
                        end
                    end

                    if #toLoad > 0 then
                        StatusTo(ply, "Hotloading " .. #toLoad .. " required addon(s) first", 0)
                        for i = 1, #toLoad do
                            Enqueue(toLoad[i], nil, ply)
                        end
                    end

                    Enqueue(id, idTitle, ply)
                    ProcessQueue()
                end

                timer.Create("TBH.ReqTimeout." .. id, 20, 1, function()
                    Proceed({})
                end)

                TBH.GetRequiredAddons(id, Proceed)
                return
            end

            Enqueue(id, idTitle, ply)
            ProcessQueue()
        end

        ----------------------------------------------------------------
        -- v1.1.2: the crash log starts the moment the request hits the
        -- server - BEFORE the page fetch. If the game dies anywhere from
        -- here on, the file is already on disk with the trail.
        ----------------------------------------------------------------
        TBH.DiagStart("hotload request received on the server for " .. wsid ..
            " from " .. (IsValid(ply) and ply:Nick() or "console") ..
            " - fetching the workshop page...")

        -- shared by BOTH collection detection paths below
        local function EnqueueCollectionMembers(colTitle, members)
            TBH.DiagState.CollectionConfirmed = true

            -- collections need the server-side downloader - routing 30
            -- members through the host player's client would hammer it with
            -- concurrent downloads, a crash risk we simply refuse
            if not TBH.ServerCanUGC then
                TBH.Diag("[server] collection REFUSED: the gmsv_workshop module is not installed")
                StatusTo(ply, "Collection hotloading needs the gmsv_workshop module (server-side downloads). Install it, or hotload the members individually.", 2)
                return
            end

            -- ONE COLLECTION AT A TIME: stacking a second collection onto a
            -- running batch breaks the progress tracker and hammers every
            -- client with parallel work (pile-up = the old freeze/crash)
            do
                local batch = TBH.Server.Batch
                if (batch and batch.total and batch.total > 0)
                    or TBH.Server.Current ~= nil
                    or #TBH.Server.Queue > 0 then
                    TBH.Diag("[server] collection REFUSED: another hotload is already running")
                    StatusTo(ply, "A hotload is already running - wait for it to finish before hotloading a collection", 3)
                    return
                end
            end

            -- tell the requester's client to drop its optimistic card for
            -- the collection id itself (the members get their own cards)
            if IsValid(ply) then
                TBH.Net:Start("dropentry")
                net.WriteString(wsid)
                net.Send(ply)
            end

            local queued, skipped = 0, 0

            for i = 1, #members do
                local m = members[i]

                if AlreadyKnown(m.wsid) then
                    skipped = skipped + 1
                else
                    -- collection members bypass the queue cap (capped by
                    -- hotloader_max_collection instead), skip their own
                    -- requirement chains (avoids combinatorial explosions)
                    -- and announce quietly (one collection announcement
                    -- instead of 30 chat lines)
                    Enqueue(m.wsid, m.title, ply, true, true)
                    queued = queued + 1
                end
            end

            if queued > 0 then
                -- set up the batch tracker + tell clients the counter started
                TBH.Server.Batch = { title = colTitle, total = queued, done = 0 }

                TBH.Diag("[server] batch tracker set: '" .. string_sub(tostring(colTitle), 1, 60) .. "' - queued " .. queued .. ", skipped " .. skipped)

                TBH.Net:Start("batchprog")
                net.WriteUInt(0, 8)
                net.WriteUInt(math.Clamp(queued, 0, 255), 8)
                net.WriteString(string_sub(colTitle, 1, 100))
                net.Broadcast()

                ChatBroadcast("Hotloading collection \"" .. colTitle .. "\" - " .. queued .. " addons" ..
                    (skipped > 0 and (" (" .. skipped .. " skipped)") or "") .. "...", 1)
                StatusTo(ply, "Collection \"" .. colTitle .. "\": hotloading " .. queued .. " addons" ..
                    (skipped > 0 and (" (" .. skipped .. " skipped)") or "") .. "!", 1)
            else
                TBH.Diag("[server] collection has nothing new to hotload (skipped " .. skipped .. ")")
                StatusTo(ply, "Collection \"" .. colTitle .. "\": nothing new to hotload" ..
                    (skipped > 0 and (" (" .. skipped .. " skipped)") or ""), 3)
            end

            ProcessQueue()
        end

        -- v1.1.2: the page did not prove this is a collection - get a second
        -- opinion from the Steam Web API before pointing the downloader at
        -- the id. (A hidden-collection misread used to aim DownloadUGC at
        -- the collection id itself - a hard-crash suspect.)
        local function VerifyWithAPI(reason)
            TBH.Diag("[server] " .. reason .. " - double-checking the id with the Steam Web API...")

            -- v1.1.5: DETECTION STRATEGY OVERHAUL.
            --
            -- Steam has stopped returning `file_type` reliably for collections
            -- via GetPublishedFileDetails (confirmed in user log: collection
            -- 3773160028 returned HTTP 200 + 1571 bytes + valid JSON, but
            -- `file_type` was nil). The v1.1.4 detector only checked
            -- `file_type` (2 = collection, 0 = addon), so a nil value fell
            -- straight to REFUSED even though Steam HAD just told us the
            -- title and structure of the item.
            --
            -- The new strategy mirrors VLL2 / DToyBox:
            --   1. Call GetCollectionDetails FIRST - this is THE authoritative
            --      endpoint for "is this a collection?". If it returns
            --      valid `collectiondetails[1].children`, we KNOW it's a
            --      collection and enumerate from there.
            --   2. Only if GetCollectionDetails returns no children do we fall
            --      back to GetPublishedFileDetails, where we now inspect BOTH
            --      the (unreliable) `file_type` AND the (definitive-for-addons)
            --      `hcontent_file` field. The latter is Steam's GMA content
            --      hash - present for real downloadable addons and absent for
            --      collections. If present, treat as a single addon.
            --   3. If neither signal is present, REFUSE - DownloadUGC on a
            --      real collection id crashes the game natively.
            GetCollectionChildren(wsid, function(children)
                if istable(children) and #children > 0 then
                    TBH.Diag("[server] GetCollectionDetails confirms this IS a COLLECTION (" .. #children .. " direct child(ren) returned) - the page hid its markers! Enumerating members via the API...")

                    EnumerateCollectionMembers(wsid, function(members)
                        if not istable(members) or #members == 0 then
                            TBH.Diag("[server] API member enumeration FAILED - refusing (DownloadUGC on a collection id would crash)")
                            StatusTo(ply, "Could not enumerate the members of collection '" .. (title or wsid) .. "' via the Steam API. Aborting to avoid a crash.", 2)
                            TBH.DiagAutoCleanup(30)
                            return
                        end

                        TBH.Diag("[server] API enumerated " .. #members .. " collection member(s)")
                        EnqueueCollectionMembers(title or wsid, members)
                    end)

                    return
                end

                -- v1.1.5: GetCollectionDetails returned no children (or errored).
                -- The id is EITHER a single addon OR a hidden / empty collection.
                -- Disambiguate via GetPublishedFileDetails - check both
                -- `file_type` (unreliable but still sometimes returned) AND
                -- `hcontent_file` (definitive for real addons).
                TBH.Diag("[server] GetCollectionDetails returned no children - falling back to GetPublishedFileDetails to check `file_type` and `hcontent_file`...")

                GetFileType(wsid, function(file_type, apiTitle, details)
                    -- Legacy `file_type` signals (Steam still returns these
                    -- for some items, but not reliably for collections):
                    if file_type == 2 then
                        TBH.Diag("[server] the Steam API says this IS a collection (file_type=2 from GetPublishedFileDetails - the page hid its markers!) - enumerating members via the API...")
                        EnumerateCollectionMembers(wsid, function(members)
                            if not istable(members) or #members == 0 then
                                TBH.Diag("[server] API member enumeration FAILED - refusing (DownloadUGC on a collection id would crash)")
                                StatusTo(ply, "Could not enumerate the members of collection '" .. (apiTitle or title or wsid) .. "' via the Steam API. Aborting to avoid a crash.", 2)
                                TBH.DiagAutoCleanup(30)
                                return
                            end
                            TBH.Diag("[server] API enumerated " .. #members .. " collection member(s)")
                            EnqueueCollectionMembers(apiTitle or title or wsid, members)
                        end)
                        return
                    end

                    if file_type == 0 then
                        TBH.Diag("[server] the Steam API confirms a single addon (file_type = 0) - proceeding with single-addon hotload")
                        TBH.DiagAutoCleanup(90)
                        return HandleAddon(wsid, isstring(apiTitle) and apiTitle or title, includeReqs)
                    end

                    -- v1.1.5: `file_type` is nil (Steam didn't return it -
                    -- happens for collections via GetPublishedFileDetails).
                    -- Check `hcontent_file` - this is Steam's GMA content hash,
                    -- present for real downloadable addons and absent for
                    -- collections. This is the definitive single-addon signal
                    -- when `file_type` is missing.
                    if istable(details) and isstring(details.hcontent_file) and details.hcontent_file ~= "" then
                        TBH.Diag("[server] file_type is missing from Steam's response, but `hcontent_file` is present (" .. #details.hcontent_file .. " chars) - this confirms a single downloadable addon. Proceeding with single-addon hotload.")
                        TBH.DiagAutoCleanup(90)
                        return HandleAddon(wsid, isstring(apiTitle) and apiTitle or title, includeReqs)
                    end

                    -- Truly ambiguous - REFUSE. We cannot safely call
                    -- DownloadUGC because if the id is secretly a collection,
                    -- the game crashes natively (uncatchable by pcall).
                    TBH.Diag("[server] REFUSED: cannot verify whether " .. wsid .. " is a collection or a single addon via the Steam Web API. GetCollectionDetails returned no children, and GetPublishedFileDetails had neither `file_type` nor `hcontent_file`. DownloadUGC on a collection id would crash the game natively. Aborting - see the diagnostic log above for the exact HTTP status / network error.")
                    StatusTo(ply, "Cannot verify what '" .. (title or wsid) .. "' is - the Steam Web API returned 200 OK but neither the collection endpoint nor the file details endpoint gave us a definitive answer (no children, no file_type, no hcontent_file). This id may be a hidden / private / removed collection. Aborting to avoid a native game crash. Check the diagnostic log (hotloader_crash_log_server.txt) for details.", 2)
                    TBH.DiagAutoCleanup(30)
                end)
            end)
        end

        http.Fetch(TBH.WorkshopURL(wsid), function(body, size, headers, code)
            -- v1.1.3: Steam occasionally hides the legacy `collectionChildren`
            -- marker (login wall, age gate, layout update). Try multiple
            -- collection-page fingerprints before declaring "not a collection".
            -- We also fall back to a heuristic: a collection page typically
            -- has multiple distinct `filedetails/?id=` links besides its own.
            local function PageHasCollectionMarkers(b)
                if not isstring(b) or b == "" then return false end
                if string_find(b, "collectionChildren", 1, true) then return true end
                if string_find(b, 'class="collectionBrowse"', 1, true) then return true end
                if string_find(b, 'class="collectionItems"', 1, true) then return true end
                if string_find(b, 'id="collectionItems"', 1, true) then return true end
                if string_find(b, 'class="collectionItem"', 1, true) then return true end
                if string_find(b, "workshopBrowseItems", 1, true) and string_find(b, "filedetails/?id=", 1, true) then return true end
                return false
            end

            local function CountMemberLinks(b, selfId)
                if not isstring(b) then return 0 end
                local seen, count = {}, 0
                for id in string_gmatch(b, 'filedetails/%?id=(%d+)') do
                    if id ~= selfId and not seen[id] then
                        seen[id] = true
                        count = count + 1
                    end
                end
                return count
            end

            if not isstring(body) or body == "" or (code and (code < 200 or code > 299)) then
                return VerifyWithAPI((not isstring(body) or body == "")
                    and "the workshop page came back EMPTY (Steam login wall / block?)"
                    or ("the workshop page fetch returned HTTP " .. tostring(code)))
            end

            if not PageHasCollectionMarkers(body) then
                -- Heuristic: if the page has 3+ distinct sibling addon links,
                -- treat it as a collection that hid its markers - still ask
                -- the API for a definitive answer rather than misread it.
                local siblings = CountMemberLinks(body, tostring(wsid))
                if siblings >= 3 then
                    TBH.Diag("[server] page lacks the legacy collection markers but exposes " .. siblings .. " sibling addon links - deferring to the Steam API for confirmation")
                end
                return VerifyWithAPI("the page showed no collection markers")
            end

            -- the page shows the collection listing: parse every member (id + title)
            local colTitle = string_match(body, '<div class="workshopItemTitle">([^<]-)</div>') or title or wsid
            local members, seen = {}, {}

            for id, name in string_gmatch(body, '<div class="collectionItem.-filedetails/%?id=(%d+).-workshopItemTitle[^>]*>([^<]*)<') do
                if not seen[id] and id ~= wsid then
                    seen[id] = true
                    members[#members + 1] = { wsid = id, title = string_gsub(name, "^%s+", "") }

                    if #members >= math.Clamp(TBH.CVarMaxCollection:GetInt(), 1, 100) then break end
                end
            end

            -- broader regex: any sibling link following a collectionItem div,
            -- not requiring the old ordering of attributes
            if #members == 0 then
                for id, name in string_gmatch(body, 'filedetails/%?id=(%d+).-workshopItemTitle[^>]*>([^<]*)<') do
                    if not seen[id] and id ~= wsid then
                        seen[id] = true
                        members[#members + 1] = { wsid = id, title = string_gsub(name, "^%s+", "") }

                        if #members >= math.Clamp(TBH.CVarMaxCollection:GetInt(), 1, 100) then break end
                    end
                end
            end

            if #members > 0 then
                TBH.Diag("[server] page confirmed the collection: parsed " .. #members .. " member(s) (page: " .. #body .. " bytes)")
                return EnqueueCollectionMembers(colTitle, members)
            end

            return VerifyWithAPI("the page had collection markers but 0 members parsed")
        end, function(err)
            VerifyWithAPI("the workshop page fetch FAILED: " .. tostring(err))
        end)
    end

    --------------------------------------------------------------------
    -- Net receivers
    --------------------------------------------------------------------

    TBH.Net:Receive("req", function(len, ply)
        local wsid = net.ReadString()
        local includeReqs = net.ReadBool()
        local titleHint = net.ReadString()

        TBH.Server.Request(ply, wsid, includeReqs, titleHint)
    end)

    -- FORCE ADDON RELOAD (right-click an addon -> "Force addon reload")
    TBH.Net:Receive("forcereload", function(len, ply)
        local wsid = net.ReadString()
        local titleHint = net.ReadString()

        local allowed, reason = CanHotload(ply)
        if not allowed then
            StatusTo(ply, "Permission denied: " .. tostring(reason), 2)
            return
        end

        if not TBH.IsValidWSID(wsid) then return end

        if TBH.Server.Current == wsid then
            StatusTo(ply, "That addon is being downloaded right now - wait for it to finish", 3)
            return
        end

        -- drop the server's copy (soft unload: hooks, timers, spawnmenu entries)
        local entry = TBH.Server.Mounted[wsid]
        if istable(entry) and istable(entry.bundle) and isfunction(entry.bundle.Unload) then
            pcall(entry.bundle.Unload, entry.bundle, false)
        end
        TBH.Server.Mounted[wsid] = nil
        TBH.Server.FailedUntil[wsid] = nil

        if IsValid(ply) then
            TBH.Server.PlayerCooldown[ply:SteamID()] = nil
        end

        -- every client drops its copy too, so the new mount runs for everyone
        TBH.Net:Start("forcereload")
        net.WriteString(wsid)
        net.Broadcast()

        StatusTo(ply, "Force reloading " .. ((titleHint ~= "" and titleHint) or wsid) .. "...", 0)
        TBH.Msg("Force reload of " .. wsid .. " requested")

        timer.Simple(0.5, function()
            TBH.Server.Request(ply, wsid, false, titleHint)
        end)
    end)

    --------------------------------------------------------------------
    -- V.1.0.6: pinned-addons batch ("HOTLOAD ALL PINNED" button)
    --
    -- One message = permission + cooldown applied ONCE, then every pin is
    -- enqueued individually (respecting AlreadyKnown, the fail cache and
    -- the queue cap - the same guards a manual request goes through).
    --------------------------------------------------------------------

    TBH.Net:Receive("pinsreq", function(len, ply)
        local allowed, reason = CanHotload(ply)
        if not allowed then
            StatusTo(ply, "Permission denied: " .. tostring(reason), 2)
            return
        end

        if IsValid(ply) then
            local sid = ply:SteamID()
            local cooldownUntil = TBH.Server.PlayerCooldown[sid] or 0

            if CurTime() < cooldownUntil then
                StatusTo(ply, "Cooling down - wait " .. math.ceil(cooldownUntil - CurTime()) .. "s", 3)
                return
            end

            TBH.Server.PlayerCooldown[sid] = CurTime() + TBH.CVarCooldown:GetInt()
        end

        local count = math.Clamp(net.ReadUInt(8), 0, 15)
        local queued, skipped = 0, 0

        for i = 1, count do
            local wsid = TBH.ExtractWSID(net.ReadString() or "")
            local titleHint = net.ReadString()

            if not wsid then
                skipped = skipped + 1
            elseif AlreadyKnown(wsid) then
                skipped = skipped + 1
            else
                -- enqueue directly (bypassing the per-request cooldown we
                -- already applied once above); Enqueue applies the queue cap
                local okEnqueue = pcall(function()
                    Enqueue(wsid, titleHint ~= "" and titleHint or nil, ply, true, false)
                end)

                if okEnqueue then queued = queued + 1 else skipped = skipped + 1 end
            end
        end

        TBH.Msg("Pin batch from " .. (IsValid(ply) and ply:Nick() or "console") .. ": queued " .. queued .. ", skipped " .. skipped)
        StatusTo(ply, "Pin batch: queued " .. queued .. " addon(s)" .. (skipped > 0 and (", skipped " .. skipped .. " (already mounted / invalid)") or ""), 0)
    end)

    TBH.Net:Receive("result", function(len, ply)
        local wsid = net.ReadString()
        local ok = net.ReadBool()
        local errCount = net.ReadUInt(16)
        local errSummary = net.ReadString()

        -- a client finished syncing THIS addon - maybe the batch gate opens
        FeedAck(ply, wsid)
        TBH.Server.DeliveryOnResult(ply, wsid, ok, errSummary)

        local track = TBH.Server.Sync[wsid]
        if not track then return end

        if ok then
            track.ok = track.ok + 1
        else
            track.failed = track.failed + 1
            track.failedNames[#track.failedNames + 1] = (IsValid(ply) and ply:Nick() or "?") .. ": " .. errSummary
        end
    end)

    TBH.Net:Receive("resync", function(len, ply)
        if not IsValid(ply) then return end
        TBH.Server.SendSyncList(ply)
    end)

    --------------------------------------------------------------------
    -- Listen-server host fallback receivers
    --------------------------------------------------------------------

    TBH.Net:Receive("hostchunk", function(len, ply)
        if not IsValid(ply) or not ply:IsListenServerHost() then return end

        local wsid = net.ReadString()
        local total = net.ReadUInt(8)
        local idx = net.ReadUInt(8)
        local dlen = net.ReadUInt(16)
        local data = net.ReadData(dlen)

        if total < 1 or total > 255 or idx < 1 or idx > total then return end

        local entry = TBH.Server.HostBundles[wsid]

        if not entry then
            entry = { total = total, chunks = {}, got = 0, title = "" }
            TBH.Server.HostBundles[wsid] = entry

            timer.Create("TBH.HostBundle." .. wsid, 60, 1, function()
                TBH.Server.HostBundles[wsid] = nil
            end)
        end

        if not entry.chunks[idx] then
            entry.chunks[idx] = data
            entry.got = entry.got + 1
        end
    end)

    TBH.Net:Receive("hostdone", function(len, ply)
        if not IsValid(ply) or not ply:IsListenServerHost() then return end

        local wsid = net.ReadString()
        local title = net.ReadString()
        local entry = TBH.Server.HostBundles[wsid]
        local pending = TBH.Server.HostPending[wsid]

        timer.Remove("TBH.HostBundle." .. wsid)
        timer.Remove("TBH.HostWait." .. wsid)
        TBH.Server.HostBundles[wsid] = nil
        TBH.Server.HostPending[wsid] = nil

        if not entry or entry.got < entry.total then
            TBH.Server.FailedUntil[wsid] = CurTime() + 60
            if pending then
                StatusTo(pending.requester, "Host transfer for " .. wsid .. " was incomplete", 2)
            end
            return
        end

        local buffer = {}
        for i = 1, entry.total do
            buffer[#buffer + 1] = entry.chunks[i]
        end

        local json = util.Decompress(table.concat(buffer))
        local files = json and util.JSONToTable(json)

        if not istable(files) then
            TBH.Server.FailedUntil[wsid] = CurTime() + 60
            if pending then
                StatusTo(pending.requester, "Host transfer for " .. wsid .. " was corrupt", 2)
            end
            return
        end

        local maxFiles = TBH.CVarMaxFiles:GetInt()
        if #files > maxFiles then
            TBH.Server.FailedUntil[wsid] = CurTime() + 60
            if pending then
                StatusTo(pending.requester, "Addon has " .. #files .. " files (limit: " .. maxFiles .. ")", 2)
            end
            return
        end

        if not isstring(title) or title == "" then title = wsid end

        local requester = pending and pending.requester or nil

        local okFinalize, errFinalize = pcall(FinalizeMount, wsid, title, files, requester, true)
        if not okFinalize then
            TBH.LogError("FinalizeMount crashed: " .. tostring(errFinalize))
            if requester then
                StatusTo(requester, "Hotload of \"" .. title .. "\" crashed during initialization (see server console)", 2)
            end
        end
    end)

    TBH.Net:Receive("hostfail", function(len, ply)
        if not IsValid(ply) or not ply:IsListenServerHost() then return end

        local wsid = net.ReadString()
        local pending = TBH.Server.HostPending[wsid]

        timer.Remove("TBH.HostWait." .. wsid)
        TBH.Server.HostPending[wsid] = nil
        TBH.Server.FailedUntil[wsid] = CurTime() + 60

        if pending then
            StatusTo(pending.requester, "Host download of " .. wsid .. " failed too - the addon itself may be hidden or removed from the Workshop", 2)
        end
    end)

    --------------------------------------------------------------------
    -- Late-join sync
    --------------------------------------------------------------------

    function TBH.Server.SendSyncList(ply)
        if not IsValid(ply) then return end

        -- NOTE: sent even when empty - the client prunes stale session
        -- entries against this list, so a restarted server = clean lists
        local entries = {}
        for wsid, data in pairs(TBH.Server.Mounted) do
            entries[#entries + 1] = { wsid = wsid, title = data.title or wsid, maps = data.maps }
        end

        if #entries > 400 then
            for i = #entries, 401, -1 do
                entries[i] = nil
            end
        end

        TBH.Server.LastSync = TBH.Server.LastSync or setmetatable({}, { __mode = "k" })
        TBH.Server.LastSync[ply] = CurTime()

        TBH.Net:Start("sync")
        net.WriteUInt(#entries, 16)

        for i = 1, #entries do
            net.WriteString(entries[i].wsid)
            net.WriteString(entries[i].title)
            WriteMaps(entries[i].maps)
        end

        net.Send(ply)
    end

    -- when each player last got the list (weak keys: no leak when they leave)
    TBH.Server.LastSync = TBH.Server.LastSync or setmetatable({}, { __mode = "k" })

    hook.Add("PlayerInitialSpawn", "TBH.LateSync", function(ply)
        if not TBH.CVarLateSync:GetBool() then return end

        -- fallback only: a message sent while the client is still loading its Lua is
        -- lost, so the real trigger is the client's own "hello" below. skip this one
        -- if that already synced them
        timer.Simple(4, function()
            if not IsValid(ply) then return end
            if (TBH.Server.LastSync[ply] or -100) > CurTime() - 10 then return end
            TBH.Server.SendSyncList(ply)
        end)
    end)

    -- dump failed sync details for admins
    concommand.Add("hotloader_syncstatus", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        for wsid, track in pairs(TBH.Server.Sync) do
            if track.failed > 0 then
                TBH.Msg(wsid .. ": " .. track.ok .. " ok, " .. track.failed .. " failed")
                for i = 1, #track.failedNames do
                    TBH.Msg("    " .. track.failedNames[i], TBH.Colors.textdim)
                end
            end
        end
    end)

    --------------------------------------------------------------------
    -- "Load Map": change the level to a map inside a hotloaded addon
    --
    -- Every player (and late joiners) mount the addon with the .bsp in it,
    -- so they can all join the new map.
    --------------------------------------------------------------------

    TBH.Server.CanHotload = CanHotload

    local mapChangeArmed = false

    local function LoadMap(ply, mapname)
        if mapChangeArmed then
            StatusTo(ply, "A map change is already in progress...", 3)
            return
        end

        if not isstring(mapname) or mapname == "" then
            StatusTo(ply, "No map name given", 2)
            return
        end

        -- sanitize: map names are word chars, dashes, underscores and dots
        mapname = string.match(mapname, "^([%w_%-%.]+)$")

        if not mapname then
            StatusTo(ply, "That is not a valid map name", 2)
            return
        end

        -- the map must exist: either in a hotloaded addon or on the server
        local found = file.Exists("maps/" .. mapname .. ".bsp", "GAME")

        if not found then
            StatusTo(ply, "Map \"" .. mapname .. "\" does not exist on the server (hotload the map addon first!)", 2)
            return
        end

        mapChangeArmed = true

        ChatBroadcast("Changing level to \"" .. mapname .. "\" in 5 seconds - everyone has the map!", 1)

        -- the long hint (10s on screen): big maps = long download, tell people to WAIT
        ChatBroadcast("If you get stuck on \"Establishing connection to server\" after the change, the map is DOWNLOADING - big maps can take a few minutes. Just wait, do not disconnect!", 3, 10)

        TBH.Msg("Changing level to " .. mapname .. " (requested by " .. (IsValid(ply) and ply:Nick() or "console") .. ")")

        timer.Simple(5, function()
            game.ConsoleCommand("changelevel " .. mapname .. "\n")

            -- safety: re-allow after 30s if the changelevel didn't happen
            timer.Simple(30, function()
                mapChangeArmed = false
            end)
        end)
    end

    TBH.Net:Receive("loadmap", function(len, ply)
        if not IsValid(ply) then return end

        local allowed, reason = CanHotload(ply)
        if not allowed then
            StatusTo(ply, "Permission denied: " .. tostring(reason), 2)
            return
        end

        LoadMap(ply, net.ReadString())
    end)

    concommand.Add("hotloader_loadmap", function(ply, cmd, args)
        local allowed = not IsValid(ply)

        if not allowed then
            allowed = select(1, CanHotload(ply))
        end

        if not allowed then
            StatusTo(ply, "Permission denied: map switching is not allowed", 2)
            return
        end

        LoadMap(ply, args and args[1] or "")
    end)

    --------------------------------------------------------------------
    -- Soft unload (hotloader_unload <wsid> [kill])
    --
    -- Removes everything the addon's Lua is doing: hooks, timers, spawnmenu
    -- entries, scripted classes (best effort) and optionally every entity
    -- the addon spawned. The addon's FILES (models/materials/sounds) stay
    -- mounted - GMod has no unmount API (see README, "Unloading" section).
    --------------------------------------------------------------------

    local function UnloadAddon(wsid, ply, removeEntities)
        local entry = TBH.Server.Mounted[wsid]

        if not entry then
            StatusTo(ply, "Nothing hotloaded under id " .. tostring(wsid), 2)
            return
        end

        if entry.unloaded then
            StatusTo(ply, "\"" .. (entry.title or wsid) .. "\" is already unloaded", 3)
            return
        end

        local bundle = entry.bundle

        if istable(bundle) and isfunction(bundle.Unload) then
            local ok, err = pcall(bundle.Unload, bundle, removeEntities)
            if not ok then
                TBH.LogError("Unload crashed for " .. wsid .. ": " .. tostring(err))
            end
        end

        entry.unloaded = true

        -- tell every client to unload their copy too
        TBH.Net:Start("unload")
        net.WriteString(wsid)
        net.WriteBool(removeEntities or false)
        net.Broadcast()

        ChatBroadcast("Unloaded \"" .. (entry.title or wsid) .. "\" (Lua removed; files stay mounted - see README)", 3)
        StatusTo(ply, "Unloaded \"" .. (entry.title or wsid) .. "\" - hooks/timers/entities gone, content stays mounted", 1)
        TBH.Msg("Soft-unloaded " .. wsid .. " (" .. (entry.title or "?") .. ")" .. (removeEntities and " + removed entities" or ""))
    end

    concommand.Add("hotloader_unload", function(ply, cmd, args)
        local allowed = not IsValid(ply)

        if not allowed then
            allowed = select(1, CanHotload(ply))
        end

        if not allowed then
            StatusTo(ply, "Permission denied: unloading is not allowed", 2)
            return
        end

        local wsid = TBH.ExtractWSID(args and args[1] or "")

        if not wsid then
            TBH.Msg("Usage: hotloader_unload <workshop id or url> [1 = also remove spawned entities]")
            if IsValid(ply) then
                StatusTo(ply, "Usage: hotloader_unload <id or url> [1 = remove entities]", 3)
            end
            return
        end

        UnloadAddon(wsid, ply, tobool(args[2]))
    end)

    -- client-initiated unload (right-click menu in the spawnmenu)
    TBH.Net:Receive("unloadreq", function(len, ply)
        if not IsValid(ply) then return end

        local allowed, reason = CanHotload(ply)
        if not allowed then
            StatusTo(ply, "Permission denied: " .. tostring(reason), 2)
            return
        end

        UnloadAddon(net.ReadString(), ply, net.ReadBool())
    end)

    --------------------------------------------------------------------
    -- V.1.0.6: FULL UNLOAD (your request - "we can unload addons but not
    -- fully")
    --
    -- Soft unload (hooks/timers/entities/Lua state) AND unmounting the
    -- addon's FILES from the engine filesystem - something GMod's Lua API
    -- simply cannot do (game.MountGMA has no counterpart). The actual
    -- unmount call lives in the optional Rust binary module
    -- (gmsv_gmaunmount_win64.dll, see the zip's README):
    --
    --   gmaunmount.Unmount(gmaPath) -> ok, reason
    --     ok=true,  "removed"     - search path gone, files unmounted
    --     ok=true,  "not-mounted" - no matching search path (already gone /
    --                               never mounted in this realm - fine)
    --     ok=false, ...           - module/engine problem (details)
    --
    -- Without the module this degrades to the normal soft unload with a
    -- clear message (identical to every version before V.1.0.6).
    --
    -- Every client is told to full-unload too: clients that installed the
    -- client copy (gmcl_gmaunmount_win64.dll) unmount their local files,
    -- everyone else gets the soft unload.
    --------------------------------------------------------------------

    local function FullUnloadAddon(wsid, ply, removeEntities)
        local entry = TBH.Server.Mounted[wsid]

        if not entry then
            StatusTo(ply, "Nothing hotloaded under id " .. tostring(wsid), 2)
            return
        end

        -- pick a sample file from the mounted list to VERIFY the unmount
        -- afterwards (the engine's unmount is silent about unknown ids, so
        -- we check the filesystem ourselves and report the honest truth)
        local sampleFile = nil
        if istable(entry.bundle) and istable(entry.bundle.FlatFiles) then
            for i = 1, math.min(#entry.bundle.FlatFiles, 50) do
                local f = entry.bundle.FlatFiles[i]
                if isstring(f) and file.Exists(f, "GAME") then
                    sampleFile = f
                    break
                end
            end
        end

        -- 1) soft unload (Lua state) - exactly like UnloadAddon
        if not entry.unloaded then
            local bundle = entry.bundle

            if istable(bundle) and isfunction(bundle.Unload) then
                local ok, err = pcall(bundle.Unload, bundle, removeEntities)
                if not ok then
                    TBH.LogError("Full-unload crashed for " .. wsid .. ": " .. tostring(err))
                end
            end

            entry.unloaded = true
        end

        -- 2) unmount the server-side files through the module (BY WORKSHOP ID
        -- - the engine's addon system keys its registry on the wsid it parsed
        -- out of the GMA's path at mount time)
        local moduleOk, serverRemoved, serverDetail = false, false, "no-module"

        -- V.1.0.7: re-probe on use - covers "the DLL was dropped in after
        -- boot" without waiting for the 2s boot retry
        if not TBH.ServerCanUnmount then
            TBH.ServerCanUnmount, TBH.ServerUnmountError = TBH.DetectGmaUnmountModule()
        end

        if TBH.ServerCanUnmount then
            moduleOk = true
            serverDetail = "module not called"

            local ok, dispatched, detail = pcall(gmaunmount.Unmount, wsid)

            if ok and dispatched then
                serverDetail = tostring(detail or "dispatched")

                -- verify: the sample file must be GONE from the filesystem
                if sampleFile then
                    serverRemoved = not file.Exists(sampleFile, "GAME")
                    serverDetail = serverRemoved and "files unmounted" or "files still found after unmount"
                else
                    -- no verifiable sample: trust the dispatch
                    serverRemoved = true
                    serverDetail = "unmount dispatched (no sample file to verify)"
                end
            else
                serverDetail = "module refused: " .. tostring(ok and detail or dispatched)
            end
        end

        -- 3) tell every client to full-unload their copy as well
        TBH.Net:Start("fullunload")
        net.WriteString(wsid)
        net.WriteBool(removeEntities or false)
        net.Broadcast()

        -- 4) report
        local title = entry.title or wsid

        if serverRemoved then
            ChatBroadcast("FULL-unloaded \"" .. title .. "\" - Lua AND files unmounted (server)", 1)
            StatusTo(ply, "Fully unloaded \"" .. title .. "\" - hooks, entities AND the mounted files are gone", 1)
            TBH.Msg("Full-unloaded " .. wsid .. " (" .. title .. ")" .. (removeEntities and " + removed entities" or ""))
        elseif not moduleOk then
            ChatBroadcast("Unloaded \"" .. title .. "\" (Lua removed; files stay mounted - put gmsv_gmaunmount_win64.dll in garrysmod/lua/bin for FULL Unload)", 3)
            StatusTo(ply, "Soft-unloaded \"" .. title .. "\" - the unmount module is not available on the server: " .. tostring(TBH.ServerUnmountError or "not installed") .. ". Files stay mounted until restart.", 3)
        else
            ChatBroadcast("Unloaded \"" .. title .. "\" (Lua removed; file unmount failed: " .. serverDetail .. ")", 3)
            StatusTo(ply, "Soft-unloaded \"" .. title .. "\" - unmount result: " .. serverDetail, 2)
        end
    end

    concommand.Add("hotloader_fullunload", function(ply, cmd, args)
        local allowed = not IsValid(ply)

        if not allowed then
            allowed = select(1, CanHotload(ply))
        end

        if not allowed then
            StatusTo(ply, "Permission denied: unloading is not allowed", 2)
            return
        end

        local wsid = TBH.ExtractWSID(args and args[1] or "")

        if not wsid then
            TBH.Msg("Usage: hotloader_fullunload <workshop id or url> [1 = also remove spawned entities]")
            if IsValid(ply) then
                StatusTo(ply, "Usage: hotloader_fullunload <id or url> [1 = remove entities]", 3)
            end
            return
        end

        FullUnloadAddon(wsid, ply, tobool(args[2]))
    end)

    -- client-initiated full unload (right-click menu in the spawnmenu)
    TBH.Net:Receive("fullunloadreq", function(len, ply)
        if not IsValid(ply) then return end

        local allowed, reason = CanHotload(ply)
        if not allowed then
            StatusTo(ply, "Permission denied: " .. tostring(reason), 2)
            return
        end

        FullUnloadAddon(net.ReadString(), ply, net.ReadBool())
    end)

    --------------------------------------------------------------------
    -- Session safeguard
    --
    -- Hotloaded addons ONLY live in memory: nothing is written to disk and
    -- a restart always starts brand new. This safeguard additionally wipes
    -- the session registry when the last player leaves (host included), so
    -- the next session on a long-running server starts completely clean.
    -- Nothing is permanently deleted from Steam's own download cache, but
    -- no hotloaded addon "exists" anymore until someone hotloads it again.
    --------------------------------------------------------------------

    local function WipeSession()
        TBH.Server.Mounted = {}
        TBH.Server.Queue = {}
        TBH.Server.Sync = {}
        for wsid in pairs(TBH.Server.Delivery or {}) do timer.Remove("TBH.Delivery." .. wsid) end
        TBH.Server.Delivery = {}
        TBH.Server.FailedUntil = {}
        TBH.Server.PlayerCooldown = {}
        TBH.Server.HostBundles = {}
        TBH.Server.HostPending = {}
        TBH.Server.Current = nil
    end

    TBH.Server.WipeSession = WipeSession

    hook.Add("PlayerDisconnected", "TBH.CleanupOnEmpty", function(ply)
        if not TBH.CVarCleanupEmpty:GetBool() then return end

        -- give the engine a moment to update the player list
        timer.Simple(2, function()
            if #player.GetAll() == 0 then
                WipeSession()
                TBH.Msg("Server is empty - hotload session wiped. The next session starts completely fresh.")
            end
        end)
    end)

    -- full restart = always brand new; wipe on shutdown too so nothing can
    -- ever carry over (belt and suspenders - it is all in-memory anyway)
    hook.Add("ShutDown", "TBH.Cleanup", function()
        WipeSession()
    end)

    concommand.Add("hotloader_wipe", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        WipeSession()
        TBH.Msg("Hotload session wiped by " .. (IsValid(ply) and ply:Nick() or "console") .. " - every hotloaded addon is gone until re-hotloaded.")
    end)
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  CLIENT PIPELINE
--
--  Receives "mount"/"sync" from the server, downloads each addon with the
--  native client steamworks.DownloadUGC, mounts it, and initializes all
--  client-side Lua (autorun/client, cl_init, PANELs, effects, stools...).
--
--  Listen-server hosts can additionally download on the server's behalf
--  when the gmsv_workshop module is not installed.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if CLIENT then
    TBH.Client = {
        Queue = {},
        Busy = false,
        Current = nil,  -- wsid currently downloading/initializing
        Mounted = {},   -- [wsid] = { title, files, time, errors, maps, bundle, unloaded }
        Known = {},     -- [wsid] = { title, maps }  (everything the server told us about)
        HostLoading = nil,
        AutoLoadMap = {},  -- [wsid] = true when the browser's LOAD MAP button was used
        Meta = {},          -- [wsid] = { title, author, imageFile, fetched, failed }
        GmaPaths = {},      -- V.1.0.6: [wsid] = local GMA file path (for FULL unload via the module)
    }

    ------------------------------------------------------------------------------
    -- Session reset
    --
    -- The client Lua state SURVIVES map changes and server restarts (that is
    -- exactly why hotloading works at all). Without this, the session list
    -- would keep showing addons from a previous server session until you
    -- restart your whole game. GM:InitPostEntity fires every time you spawn
    -- into a map, so we wipe the session here - a fresh map/server = a
    -- brand new session list, exactly like a full restart.
    ------------------------------------------------------------------------------

    TBH.CVarUnloadOnDisconnect = CreateClientConVar("hotloader_unload_on_disconnect", "1", true, false,
        "Fully unload (Lua + files, needs the gmaunmount module for the files) the addons hotloaded in your previous server session when you join a DIFFERENT server. Map changes on the same server keep them.")

    -- you can only be sure a session ended when the server address changes
    -- (a map change on the same server is NOT a disconnect). listen server /
    -- singleplayer is always "loopback", so those sessions are kept - use
    -- hotloader_unloadall for a manual clean sweep
    local function UnloadPreviousSession(newAddr)
        local prev = TBH.Client.SessionAddr
        TBH.Client.SessionAddr = newAddr

        if not prev or prev == newAddr then return end
        if not TBH.CVarUnloadOnDisconnect:GetBool() then return end

        TBH.UnloadAllMounted("left " .. tostring(prev))
    end

    -- fully unloads every addon this client hotloaded (Lua first, then the files)
    function TBH.UnloadAllMounted(reason)
        local ids = {}
        for wsid, entry in pairs(TBH.Client.Mounted or {}) do
            if istable(entry) and not entry.unloaded then ids[#ids + 1] = wsid end
        end

        if #ids == 0 then return 0, 0 end

        local hasModule = TBH.ProbeGmaUnmount()
        local luaCount, fileCount = 0, 0

        for _, wsid in ipairs(ids) do
            local entry = TBH.Client.Mounted[wsid]
            local bundle = entry and entry.bundle

            if istable(bundle) and isfunction(bundle.Unload) then
                local ok = pcall(bundle.Unload, bundle, false)
                if ok then luaCount = luaCount + 1 end
            end

            if entry then entry.unloaded = true end

            if hasModule then
                local ok, removed = pcall(gmaunmount.Unmount, wsid)
                if ok and removed == true then fileCount = fileCount + 1 end
            end
        end

        TBH.NotifyLocally(string.format("Unloaded %d addon(s) from the previous session (%s): Lua %d, files %d%s",
            #ids, tostring(reason or "?"), luaCount, fileCount, hasModule and "" or " - gmaunmount module missing, files stay mounted"), fileCount > 0 and 1 or 3)

        return luaCount, fileCount
    end

    concommand.Add("hotloader_unloadall", function()
        TBH.UnloadAllMounted("manual")
        hook.Run("TBH.ClientListChanged")
    end)

    hook.Add("InitPostEntity", "TBH.SessionReset", function()
        TBH.DiagEnd("session reset (map change or (re)spawn)")

        local okAddr, addr = pcall(game.GetIPAddress)
        UnloadPreviousSession(okAddr and addr or "?")

        TBH.Client.Known = {}
        TBH.Client.Queue = {}
        TBH.Client.Mounted = {}
        TBH.Client.AutoLoadMap = {}
        TBH.Client.GmaPaths = {}
        TBH.Client.Busy = false
        TBH.Client.Current = nil
        TBH.Client.HostLoading = nil
        TBH.Client.Batch = { active = false }

        hook.Run("TBH.ClientListChanged")
    end)

    ------------------------------------------------------------------------------
    -- Workshop metadata + preview thumbnails
    --
    -- v1.1.7 REWRITE: the previous flow scraped the Workshop HTML page with
    -- brittle og:image regexes. Steam's CDNs have moved, the patterns rarely
    -- matched, and "preview loading..." stayed forever on 98% of rows
    -- (failure paths didn't even set imageFailed, so the UI never gave up).
    --
    -- The new flow uses the Steam Web API's GetPublishedFileDetails, which
    -- returns the canonical `preview_url` field - the exact URL Steam
    -- itself uses for the thumbnail. Way more reliable than scraping.
    -- HTML scraping is kept as a fallback (with more robust patterns).
    --
    -- Also: meta cache is PERSISTED to data/hotloader_meta_cache.json so
    -- previously-fetched thumbnails reappear instantly on restart.
    -- Also: thumbnail is checked at PAINT TIME so it appears the moment
    -- the image arrives - no row rebuild needed.
    ------------------------------------------------------------------------------

    local metaFetching = {}   -- [wsid] = true while queued/in-flight
    local metaQueue = {}      -- ordered wsid pump queue
    local metaPumpActive = false
    local metaRetried = {}    -- [wsid] = true if we've already retried once
    local imageMatCache = {}  -- [wsid] = cached IMaterial (or nil after a definite failure)

    local META_CACHE_FILE = "hotloader_meta_cache.json"

    local function TryMaterial(path)
        -- Try with "smooth" mipmap flag first
        local ok, mat = pcall(Material, path, "smooth")
        if ok and mat and not mat:IsError() then
            return mat
        end
        -- Fallback: try without any flags (some image formats/systems
        -- fail with "smooth" but load fine without it)
        ok, mat = pcall(Material, path)
        if ok and mat and not mat:IsError() then
            return mat
        end
        return nil
    end

    -- Load persisted meta cache (called once at boot, before any row render)
    local function LoadMetaCache()
        local body = file.Read(META_CACHE_FILE, "DATA")
        if not isstring(body) or body == "" then return end

        local ok, tbl = pcall(util.JSONToTable, body)
        if not ok or not istable(tbl) then return end

        for wsid, entry in pairs(tbl) do
            if istable(entry) and TBH.IsValidWSID(wsid) then
                -- don't overwrite already-loaded in-memory entries (we may
                -- have hotloaded something fresh this session)
                if not TBH.Client.Meta[wsid] then
                    -- V.1.0.5: SELF-HEAL old entries from the broken v1.1.7
                    -- pipeline so they get re-fetched with the FIXED code
                    -- instead of sitting on "no preview available" forever:
                    --   * persisted as "fetched" but never got an image
                    --     (API/scrape URL was saved, download never ran)
                    --   * persisted an imageFile that is no longer on disk
                    --     (icons folder was cleaned) - drop it and refetch
                    if entry.imageFile and not file.Exists("hotloader_icons/" .. entry.imageFile, "DATA") then
                        entry.imageFile = nil
                    end

                    if entry.fetched and not entry.imageFile then
                        entry.fetched = nil
                    end

                    TBH.Client.Meta[wsid] = entry
                end
            end
        end
    end

    -- Debounced save - 1s after the last meta change, so 30 thumbnails
    -- arriving at once = ONE disk write, not 30.
    local function SaveMetaCache()
        timer.Remove("TBH.SaveMetaCache")
        timer.Create("TBH.SaveMetaCache", 1, 1, function()
            local snapshot = {}
            for wsid, meta in pairs(TBH.Client.Meta) do
                if istable(meta) and (meta.imageFile or meta.preview_url or meta.title) then
                    -- only persist the lightweight fields (not the IMaterial)
                    snapshot[wsid] = {
                        title       = meta.title,
                        author      = meta.author,
                        imageFile   = meta.imageFile,
                        preview_url = meta.preview_url,
                        fetched     = meta.fetched,
                    }
                end
            end

            local ok, json = pcall(util.TableToJSON, snapshot, true)
            if not ok or not isstring(json) then return end

            file.Write(META_CACHE_FILE, json)
        end)
    end

    -- Boot-load the cache immediately
    LoadMetaCache()

    ------------------------------------------------------------------------------
    -- V.1.0.6: FAVORITES / PINNED ADDONS (your request)
    --
    -- "Would be cool if it could save addons though... Like Pinning your own
    --  addons... Like a favourite thing. So you could hotload quickly."
    --
    -- Hotloaded addons live ONLY in memory - a restart wipes the session.
    -- Pinned addons are saved to data/hotloader_favorites.json on YOUR client
    -- and survive every restart. The Hotloader tab shows a PINNED ADDONS
    -- section where every pin has a one-click HOTLOAD button (and there is a
    -- HOTLOAD ALL PINNED button that queues the whole list in one go).
    --
    --   * pin/unpin with the star button on any session addon row
    --     (or via the right-click menu)
    --   * title + author are saved with the pin, so the list stays readable
    --   * the pin list is per-PLAYER (client-side file), not per-server
    ------------------------------------------------------------------------------

    local FAVORITES_FILE = "hotloader_favorites.json"

    TBH.Client.Favorites = {}

    local function LoadFavorites()
        local body = file.Read(FAVORITES_FILE, "DATA")
        if not isstring(body) or body == "" then return end

        local ok, tbl = pcall(util.JSONToTable, body)
        if not ok or not istable(tbl) then return end

        for wsid, data in pairs(tbl) do
            if istable(data) and TBH.IsValidWSID(wsid) then
                TBH.Client.Favorites[wsid] = {
                    title = isstring(data.title) and data.title or wsid,
                    author = isstring(data.author) and data.author or nil,
                    time = tonumber(data.time) or os.time(),
                    map = data.map == true or nil,
                    maps = istable(data.maps) and data.maps or nil,
                }
            end
        end
    end

    local function SaveFavorites()
        timer.Remove("TBH.SaveFavorites")
        timer.Create("TBH.SaveFavorites", 1, 1, function()
            local ok, json = pcall(util.TableToJSON, TBH.Client.Favorites, true)
            if ok and isstring(json) then
                file.Write(FAVORITES_FILE, json)
            end
        end)
    end

    LoadFavorites()

    function TBH.IsFavorite(wsid)
        return TBH.Client.Favorites[wsid] ~= nil
    end

    -- pin/unpin toggle; refreshes the pin's stored title+author from the
    -- freshest meta so the list stays readable across sessions
    function TBH.ToggleFavorite(wsid)
        if not TBH.IsValidWSID(wsid) then return false end

        if TBH.Client.Favorites[wsid] then
            TBH.Client.Favorites[wsid] = nil
            SaveFavorites()
            hook.Run("TBH.ClientListChanged")
            return false
        end

        local meta = TBH.Client.Meta and TBH.Client.Meta[wsid]
        local known = TBH.Client.Known and TBH.Client.Known[wsid]

        TBH.Client.Favorites[wsid] = {
            title = (meta and meta.title) or (known and known.title) or wsid,
            author = meta and meta.author or nil,
            time = os.time(),
            map = (known and istable(known.maps) and #known.maps > 0) or nil,
            maps = (known and istable(known.maps) and #known.maps > 0) and known.maps or nil,
        }

        SaveFavorites()
        hook.Run("TBH.ClientListChanged")
        return true
    end

    -- save an addon to the pinned list WITHOUT hotloading it. paste a link or id,
    -- it gets stored right away and the title + preview image fill in once the
    -- meta fetch comes back (see the sync hook below)
    function TBH.PinAddon(input, titleHint, isMap)
        local wsid = TBH.ExtractWSID(input)

        if not wsid then
            TBH.NotifyLocally("That doesn't look like a workshop id or url", 2)
            return false
        end

        if TBH.Client.Favorites[wsid] then
            TBH.NotifyLocally("That addon is already pinned", 0)
            return true
        end

        local meta = TBH.Client.Meta and TBH.Client.Meta[wsid]

        TBH.Client.Favorites[wsid] = {
            title = (isstring(titleHint) and titleHint ~= "" and titleHint) or (meta and meta.title) or wsid,
            author = meta and meta.author or nil,
            time = os.time(),
            map = isMap == true or nil,
        }

        SaveFavorites()
        TBH.FetchAddonMeta(wsid)
        hook.Run("TBH.ClientListChanged")

        TBH.NotifyLocally("Pinned " .. wsid .. " - it stays in your list, hit HOTLOAD on it whenever you want", 0)
        return true
    end

    -- pins saved from just an id only know their id at first. when the real title
    -- and author show up in the meta, copy them over and save
    hook.Add("TBH.ClientListChanged", "TBH.PinTitleSync", function()
        local changed = false

        for wsid, fav in pairs(TBH.Client.Favorites) do
            local meta = TBH.Client.Meta and TBH.Client.Meta[wsid]
            if meta and isstring(meta.title) and meta.title ~= "" then
                if fav.title ~= meta.title then
                    fav.title = meta.title
                    changed = true
                end
                if isstring(meta.author) and meta.author ~= "" and fav.author ~= meta.author then
                    fav.author = meta.author
                    changed = true
                end
            end
        end

        -- once a pinned addon has been hotloaded we know which maps it holds
        for wsid, fav in pairs(TBH.Client.Favorites) do
            local known = TBH.Client.Known and TBH.Client.Known[wsid]
            if known and istable(known.maps) and #known.maps > 0 and (not fav.map or not istable(fav.maps)) then
                fav.map = true
                fav.maps = known.maps
                changed = true
            end
        end

        if changed then SaveFavorites() end
    end)

    -- LOAD MAP for a pinned / installed map addon. if the addon is already hotloaded
    -- and we know its maps we switch right away, otherwise we hotload it first and
    -- the existing LOAD MAP flow switches the server as soon as it is mounted
    function TBH.LoadMapForAddon(wsid, title)
        local mounted = TBH.Client.Mounted and TBH.Client.Mounted[wsid]
        local fav = TBH.Client.Favorites and TBH.Client.Favorites[wsid]
        local known = TBH.Client.Known and TBH.Client.Known[wsid]

        local maps = (istable(mounted) and not mounted.unloaded and istable(mounted.maps) and #mounted.maps > 0 and mounted.maps)
            or (known and istable(known.maps) and #known.maps > 0 and known.maps)
            or nil

        local live = istable(mounted) and not mounted.unloaded

        if live and maps then
            if #maps == 1 then
                TBH.RequestLoadMap(maps[1])
            else
                local menu = DermaMenu()
                for i = 1, math.min(#maps, 20) do
                    menu:AddOption(maps[i], function() TBH.RequestLoadMap(maps[i]) end):SetIcon("icon16/map.png")
                end
                menu:Open()
            end
            return
        end

        TBH.NotifyLocally("Hotloading the map addon first, then switching to it...", 0)
        TBH.RequestHotload(wsid, title or (fav and fav.title) or "", true)
    end

    -- ordered pin list (newest pin first) for the UI + hotload-all
    function TBH.GetFavorites()
        local out = {}

        for wsid, data in pairs(TBH.Client.Favorites) do
            out[#out + 1] = { wsid = wsid, title = data.title or wsid, author = data.author, time = data.time or 0, map = data.map, maps = data.maps }
        end

        table.sort(out, function(a, b) return (a.time or 0) > (b.time or 0) end)
        return out
    end

    -- one-click re-hotload of every pin: sent as ONE batch message so the
    -- server applies permission + cooldown ONCE and queues the rest (the
    -- per-request cooldown would otherwise block a rapid-fire list)
    function TBH.HotloadAllFavorites()
        local pins = TBH.GetFavorites()

        if #pins == 0 then
            TBH.NotifyLocally("Nothing pinned yet - pin addons with the star button on their row.", 3)
            return
        end

        local maxSend = math.min(#pins, 15)

        TBH.Net:Start("pinsreq")
        net.WriteUInt(maxSend, 8)
        for i = 1, maxSend do
            net.WriteString(pins[i].wsid)
            net.WriteString(pins[i].title or pins[i].wsid)
        end
        net.SendToServer()

        if #pins > maxSend then
            TBH.NotifyLocally("Queuing the first " .. maxSend .. " of " .. #pins .. " pins (15 per batch).", 0)
        else
            TBH.NotifyLocally("Hotloading all " .. #pins .. " pinned addon(s)...", 0)
        end
    end

    ------------------------------------------------------------------------------
    -- CONFLICT RADAR
    --
    -- the classic gmod problem: two addons ship the same entity/weapon/lua file and
    -- one silently stomps the other (or you hotload something you already have
    -- enabled normally). right before a hotloaded addon initializes we compare it
    -- against what is already there and tell you, instead of leaving you to guess
    -- why something broke:
    --   * classes: entities/weapons it is about to (re)register that already exist,
    --     with who owns them (another hotload, or an addon loaded at boot)
    --   * files:   lua files it shares with other hotloaded addons
    ------------------------------------------------------------------------------

    TBH.Client.Conflicts = TBH.Client.Conflicts or {}

    local function ClassSetOf(bundle)
        local set = {}
        if istable(bundle) and istable(bundle.RegisteredClasses) then
            for _, list in pairs(bundle.RegisteredClasses) do
                for _, c in ipairs(list) do set[c] = true end
            end
        end
        return set
    end

    TBH.ClassSetOf = ClassSetOf
    TBH.Client.LastClasses = TBH.Client.LastClasses or {}

    function TBH.ScanConflicts(wsid, title, files)
        TBH.Client.Conflicts[wsid] = nil
        if not istable(files) then return end

        local own = TBH.Client.Mounted[wsid]
        local ownClasses = ClassSetOf(istable(own) and own.bundle or nil)

        -- classes from an earlier copy of THIS addon (force reload drops the entry
        -- but a soft unload leaves the classes registered) are not conflicts
        for c in pairs(TBH.Client.LastClasses[wsid] or {}) do ownClasses[c] = true end

        -- who owns what among the other hotloaded addons
        local classOwner, fileOwner = {}, {}
        for id, m in pairs(TBH.Client.Mounted) do
            if id ~= wsid and istable(m) and not m.unloaded and istable(m.bundle) then
                local label = m.title or id

                for c in pairs(ClassSetOf(m.bundle)) do classOwner[c] = label end

                for _, f in ipairs(m.bundle.FlatFiles or {}) do
                    local low = string.lower(f)
                    if string_sub(low, 1, 4) == "lua/" then fileOwner[low] = label end
                end
            end
        end

        local report = { files = {}, classes = {}, fileTotal = 0, classTotal = 0 }
        local seenClass = {}

        for _, f in ipairs(files) do
            local low = string.lower(f)

            if string_sub(low, 1, 4) == "lua/" then
                local other = fileOwner[low]
                if other then
                    local entry = report.files[other]
                    if not entry then
                        entry = { count = 0, samples = {} }
                        report.files[other] = entry
                    end
                    entry.count = entry.count + 1
                    report.fileTotal = report.fileTotal + 1
                    if #entry.samples < 3 then entry.samples[#entry.samples + 1] = f end
                end

                local kind, name = string.match(low, "^lua/(entities)/([^/]+)")
                if not kind then kind, name = string.match(low, "^lua/(weapons)/([^/]+)") end

                if kind and name then
                    name = string.gsub(name, "%.lua$", "")

                    if name ~= "gmod_tool" and not ownClasses[name] and not seenClass[name] then
                        seenClass[name] = true

                        local exists
                        if kind == "entities" then
                            exists = scripted_ents and scripted_ents.GetStored and scripted_ents.GetStored(name)
                        else
                            exists = weapons and weapons.GetStored and weapons.GetStored(name)
                        end

                        if exists then
                            report.classes[#report.classes + 1] = {
                                name = name,
                                kind = (kind == "entities") and "entity" or "weapon",
                                owner = classOwner[name] or "an addon that was already loaded at boot",
                            }
                            report.classTotal = report.classTotal + 1
                        end
                    end
                end
            end
        end

        if report.fileTotal == 0 and report.classTotal == 0 then return end

        report.title = title
        TBH.Client.Conflicts[wsid] = report

        local bootOnly = report.classTotal > 0
        for _, c in ipairs(report.classes) do
            if classOwner[c.name] then bootOnly = false break end
        end

        local msg
        if bootOnly and report.fileTotal == 0 then
            msg = "Conflict Radar: \"" .. tostring(title) .. "\" re-registers " .. report.classTotal ..
                " class(es) that already exist (e.g. " .. report.classes[1].name .. "). You probably have this addon enabled normally already."
        else
            msg = "Conflict Radar: \"" .. tostring(title) .. "\" overlaps other addons - " .. report.classTotal ..
                " existing class(es), " .. report.fileTotal .. " shared lua file(s). The newer copy wins, which can break either one."
        end

        TBH.NotifyLocally(msg .. " (right-click it > Conflict report)", 3, 12)
        hook.Run("TBH.ClientListChanged")
    end

    function TBH.ConflictReportText(wsid)
        local r = TBH.Client.Conflicts[wsid]
        if not r then return "No conflicts found for this addon." end

        local out = { "Conflict report for \"" .. tostring(r.title) .. "\"", "" }

        if r.classTotal > 0 then
            out[#out + 1] = "Classes that already existed (" .. r.classTotal .. "):"
            for i = 1, math.min(#r.classes, 12) do
                local c = r.classes[i]
                out[#out + 1] = "  " .. c.kind .. " " .. c.name .. "  (was from " .. c.owner .. ")"
            end
            if #r.classes > 12 then out[#out + 1] = "  ...and " .. (#r.classes - 12) .. " more" end
            out[#out + 1] = ""
        end

        if r.fileTotal > 0 then
            out[#out + 1] = "Lua files shared with other hotloaded addons (" .. r.fileTotal .. "):"
            for other, entry in pairs(r.files) do
                out[#out + 1] = "  " .. other .. ": " .. entry.count .. " file(s), e.g. " .. table.concat(entry.samples, ", ")
            end
            out[#out + 1] = ""
        end

        out[#out + 1] = "What it means: both copies cannot exist, the one loaded last wins."
        out[#out + 1] = "If you enabled this addon normally too, you do not need to hotload it."
        return table.concat(out, "\n")
    end

    concommand.Add("hotloader_conflicts", function()
        local any = false
        for wsid in pairs(TBH.Client.Conflicts) do
            any = true
            MsgC(TBH.Colors.warn, "\n" .. TBH.ConflictReportText(wsid) .. "\n")
        end
        if not any then
            MsgC(TBH.Colors.tag, "[Hotloader] ", TBH.Colors.text, "Conflict Radar: nothing found this session.\n")
        end
    end)

    concommand.Add("hotloader_pins", function()
        local pins = TBH.GetFavorites()

        MsgC(TBH.Colors.tag, "\n[Hotloader] pinned addons (" .. #pins .. "):\n")

        for i = 1, #pins do
            local p = pins[i]
            local mounted = TBH.Client.Mounted and TBH.Client.Mounted[p.wsid]
            MsgC(TBH.Colors.textdim, "  ", TBH.Colors.text, p.wsid, TBH.Colors.textdim,
                " - " .. (p.title or "?") .. (mounted and " (mounted this session)" or "") .. "\n")
        end

        if #pins == 0 then
            MsgC(TBH.Colors.textdim, "  nothing pinned yet - use the star button on an addon row\n")
        end

        MsgC(TBH.Colors.tag, "\n")
    end)

    -- Client-side Steam Web API request (mirrors the server-side helper but
    -- lives in the client scope so thumbnails can be fetched without a server
    -- round-trip). Uses HTTP() with the `parameters` table field - the same
    -- proven pattern the server uses (and the same one VLL2/DTOyBox use).
    local API_FILE_DETAILS_CLIENT = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"

    local function ClientSteamAPIRequest(endpoint, params, callback)
        local fired = false

        local function Dispatch(result)
            if fired then return end
            fired = true
            if timer.Exists("TBH.ClientAPIWatchdog") then timer.Remove("TBH.ClientAPIWatchdog") end
            callback(result)
        end

        timer.Create("TBH.ClientAPIWatchdog", 18, 1, function()
            if not fired then Dispatch(nil) end
        end)

        local req = {
            method = "POST",
            url = endpoint,
            parameters = params,
            timeout = 15,
            headers = {
                ["User-Agent"] = "TBH-Hotloader/1.1.7",
                ["Accept"] = "application/json",
            },
            success = function(code, body)
                if not isstring(body) then body = tostring(body or "") end
                if code ~= 200 or body == "" then
                    return Dispatch(nil)
                end
                local okJson, tbl = pcall(util.JSONToTable, body)
                if not okJson or not istable(tbl) then
                    return Dispatch(nil)
                end
                Dispatch(tbl)
            end,
            failed = function() Dispatch(nil) end,
        }

        local ok, err = pcall(function() HTTP(req) end)
        if not ok then Dispatch(nil) end
    end

    -- Pull preview_url, title, creator_name from GetPublishedFileDetails.
    -- callback(metaTable) - metaTable has { title, author, preview_url }
    -- or nil if the API was unreachable or returned an unexpected shape.
    local function FetchMetaViaAPI(wsid, callback)
        ClientSteamAPIRequest(API_FILE_DETAILS_CLIENT,
            { itemcount = "1", ["publishedfileids[0]"] = tostring(wsid) },
            function(tbl)
                if not istable(tbl) then return callback(nil) end
                if not istable(tbl.response) then return callback(nil) end
                if not istable(tbl.response.publishedfiledetails) then return callback(nil) end

                local det = tbl.response.publishedfiledetails[1]
                if not istable(det) then return callback(nil) end
                if det.result ~= 1 then return callback(nil) end

                local out = {}
                if isstring(det.title) and det.title ~= "" then
                    out.title = det.title
                end
                -- creators is an array of { steamid, creator } entries
                if istable(det.creators) and istable(det.creators[1]) then
                    local creator = det.creators[1].creator
                    if isstring(creator) and creator ~= "" then
                        out.author = creator
                    end
                end
                -- the canonical preview URL Steam itself uses
                if isstring(det.preview_url) and det.preview_url ~= "" then
                    out.preview_url = det.preview_url
                end

                callback(next(out) and out or nil)
            end)
    end

    -- Download a preview image URL to data/hotloader_icons/<wsid>.<ext>.
    -- callback(imageFile) - imageFile is the filename (e.g. "123.jpg") or
    -- nil on failure.
    local function DownloadPreviewImage(wsid, imgURL, callback)
        if not isstring(imgURL) or not string_match(imgURL, "^https?://") then
            return callback(nil)
        end

        imgURL = string_gsub(imgURL, "&amp;", "&")

        local ext = string_match(imgURL, "%.(%w-)%s*$") or "jpg"

        -- already cached on disk? (skip the network entirely)
        for _, tryExt in ipairs({ ext, "jpg", "png" }) do
            if (tryExt == "jpg" or tryExt == "png") and file.Exists("hotloader_icons/" .. wsid .. "." .. tryExt, "DATA") then
                return callback(wsid .. "." .. tryExt)
            end
        end

        http.Fetch(imgURL, function(imgBody, imgSize, imgHeaders, imgCode)
            if not isstring(imgBody) or imgSize == 0 or #imgBody < 128 then
                return callback(nil)
            end
            if imgCode and (imgCode < 200 or imgCode > 299) then
                return callback(nil)
            end

            -- pick the extension from the actual magic bytes
            local realExt = "jpg"
            if string_sub(imgBody, 1, 3) == string.char(0x89) .. "PN" then
                realExt = "png"
            elseif ext == "png" and string_sub(imgBody, 1, 3) ~= string.char(0xFF, 0xD8, 0xFF) then
                realExt = "png"
            end

            local outFile = wsid .. "." .. realExt
            file.CreateDir("hotloader_icons")
            file.Write("hotloader_icons/" .. outFile, imgBody)

            -- Verify the file was actually written to disk.
            -- We do NOT try to load it as a Material here - GMod's material
            -- system may not register new files immediately after file.Write.
            -- Instead, we return the filename and let GetAddonImage() handle
            -- material loading at paint time (with its own retry logic).
            if file.Exists("hotloader_icons/" .. outFile, "DATA") then
                callback(outFile)
            else
                callback(nil)
            end
        end, function()
            callback(nil)
        end)
    end

    -- v1.1.7: PAINT-TIME image lookup. The IMaterial is cached on the meta
    -- table so we never call Material() twice for the same wsid (it would
    -- create a new IMaterial each time = perf killer). The row's Paint()
    -- calls this every frame - cheap as a table lookup once cached.
    -- v1.1.8: Retry material loading for up to ~5 seconds (300 frames)
    -- before giving up. GMod's material system may need a few frames to
    -- register newly-written files from the data directory.
    function TBH.GetAddonImage(wsid)
        if not wsid then return nil end

        local meta = TBH.Client.Meta[wsid]
        if not meta then return nil end

        -- cached material? (fast path)
        if meta.imageMaterial ~= nil then return meta.imageMaterial end
        if meta.imageFailed then return nil end
        if not meta.imageFile then return nil end

        -- first lookup after imageFile was set - load + cache
        local mat = TryMaterial("../data/hotloader_icons/" .. meta.imageFile)
        if mat then
            meta.imageMaterial = mat
            meta._matRetries = nil
            return mat
        end

        -- Material() failed - but GMod may need a few frames to register
        -- a newly-written file. Retry for up to ~5 seconds (300 frames
        -- at 60fps) before permanently marking as failed.
        meta._matRetries = (meta._matRetries or 0) + 1
        if meta._matRetries > 300 then
            meta.imageFailed = true
            meta._matRetries = nil
        end

        return nil
    end

    -- Mark a meta entry as definitively failed (after retries are exhausted).
    -- Sets imageFailed so the UI shows "no preview available" instead of
    -- staying on "preview loading..." forever (the old v1.1.6 bug).
    local function MetaFail(wsid, reason)
        local meta = TBH.Client.Meta[wsid]
        if not meta then return end
        meta.imageFailed = true
        meta.fetched = true  -- don't re-queue
        TBH.Diag("[client] meta FAILED (" .. tostring(reason) .. ") for wsid " .. tostring(wsid))
        hook.Run("TBH.ClientListChanged")
        SaveMetaCache()
    end

    -- THROTTLE: a 30-addon collection used to fire 30 page fetches + 30
    -- image downloads at the same instant. The pump runs ONE metadata
    -- fetch at a time with a 0.5s gap between them.
    local function MetaPump()
        if metaPumpActive then return end

        local wsid = table.remove(metaQueue, 1)
        if not wsid then return end

        metaPumpActive = true

        local function Done()
            metaPumpActive = false
            timer.Simple(0.5, MetaPump)
        end

        local meta = TBH.Client.Meta[wsid]
        if not meta then
            TBH.Client.Meta[wsid] = {}
            meta = TBH.Client.Meta[wsid]
        end

        -- early exit: already have an image on disk for this wsid (loaded
        -- from the persistent cache on boot) - just register it.
        if meta.imageFile and not meta.imageMaterial then
            local mat = TryMaterial("../data/hotloader_icons/" .. meta.imageFile)
            if mat then
                meta.imageMaterial = mat
                meta.fetched = true
                hook.Run("TBH.ClientListChanged")
                return Done()
            end
        end

        -- ---------------------------------------------------------------
        -- PRIMARY PATH: Steam Web API -> preview_url (canonical thumbnail
        -- URL). Way more reliable than scraping Steam's HTML.
        --
        -- V.1.0.5 FIX: the v1.1.7 rewrite of this block had its control
        -- flow mangled, which is why nearly every row ended up showing
        -- "no preview available":
        --   * the entry call was DoImageDownload(nil) - so even when the
        --     Steam Web API HAD just handed us the canonical preview_url,
        --     the code ignored it and scraped the workshop page anyway
        --   * the DownloadPreviewImage() call sat INSIDE the "we have no
        --     usable URL" branch, so a valid URL could never reach it
        --   * the trailing `return DoImageDownload(meta.preview_url)`
        --     re-invoked the function with the very same URL forever -
        --     an infinite tail-call loop that froze the game whenever the
        --     page scrape DID find an image URL
        -- Net effect: the API thumbnail was never downloaded, and every
        -- path led to MetaFail (or a freeze). The flow below is the
        -- intended one, wired correctly this time:
        --   1. API gave us a preview_url -> download it
        --   2. no URL from the API        -> scrape the workshop page
        --        scrape finds a URL       -> download it
        --        scrape finds nothing      -> MetaFail ("no preview
        --                                     available", never a hang)
        -- ---------------------------------------------------------------
        FetchMetaViaAPI(wsid, function(apiMeta)
            meta.fetched = true

            if istable(apiMeta) then
                if isstring(apiMeta.title) and apiMeta.title ~= "" then
                    meta.title = apiMeta.title
                end
                if isstring(apiMeta.author) and apiMeta.author ~= "" then
                    meta.author = apiMeta.author
                end
                if isstring(apiMeta.preview_url) and apiMeta.preview_url ~= "" then
                    meta.preview_url = apiMeta.preview_url
                end
            end

            -- commit a downloaded icon file to the meta table (+ persist)
            local function AcceptImage(outFile)
                if isstring(outFile) and outFile ~= "" then
                    meta.imageFile = outFile
                    meta._matRetries = nil
                    TBH.Diag("[client] meta icon downloaded OK: " .. tostring(wsid) .. " -> " .. outFile)
                    hook.Run("TBH.ClientListChanged")
                    SaveMetaCache()
                    return true
                end
                return false
            end

            -- download the image; ONE retry after 5s on transient CDN
            -- failures, then it's a definite failure
            local function DownloadImage(imgURL)
                DownloadPreviewImage(wsid, imgURL, function(outFile)
                    if AcceptImage(outFile) then
                        return Done()
                    end

                    if not metaRetried[wsid] then
                        metaRetried[wsid] = true
                        TBH.Diag("[client] meta icon download failed for " .. tostring(wsid) .. " - retrying in 5s")

                        timer.Simple(5, function()
                            DownloadPreviewImage(wsid, imgURL, function(outFile2)
                                if not AcceptImage(outFile2) then
                                    MetaFail(wsid, "image download failed (after retry)")
                                end
                            end)
                        end)

                        -- the pump moves on; the retry finishes async
                        return Done()
                    end

                    MetaFail(wsid, "image download failed")
                    return Done()
                end)
            end

            -- FALLBACK: scrape the workshop HTML page for an image URL
            -- (this also fills in the title + author name, which the API
            -- response doesn't always provide)
            local function ScrapeForURL()
                http.Fetch(TBH.WorkshopURL(wsid), function(body, size, headers, code)
                    if not isstring(body) or body == "" or (code and (code < 200 or code > 299)) then
                        MetaFail(wsid, "page fetch failed (HTTP " .. tostring(code) .. ")")
                        return Done()
                    end

                    local pageTitle = string_match(body, '<div class="workshopItemTitle">([^<]-)</div>')
                    if isstring(pageTitle) and pageTitle ~= "" then
                        meta.title = string_gsub(pageTitle, "^%s+", "")
                    end

                    local author = string_match(body, '<div class="friendBlockContent">%s*([^<\n]+)')
                    if isstring(author) and author ~= "" then
                        meta.author = string_gsub(author, "^%s+", "")
                    end

                    -- v1.1.7 + V.1.0.5: try every plausible Steam CDN layout
                    -- and attribute order, plus the modern shared/static
                    -- CDN hosts Steam has been migrating to
                    local scraped = string_match(body, 'property="og:image"[^>]-content="([^"]+)"')
                        or string_match(body, 'content="([^"]+)"[^>]-property="og:image"')
                        or string_match(body, 'name="twitter:image"[^>]-content="([^"]+)"')
                        or string_match(body, 'content="([^"]+)"[^>]-name="twitter:image"')
                        or string_match(body, 'og:image"%s+content="([^"]+)"')
                        or string_match(body, 'id="previewImage"[^>]-src="([^"]+)"')
                        or string_match(body, 'src="([^"]+)"[^>]-id="previewImage"')
                        or string_match(body, 'https://images%.steamusercontent%.com/ugc/[%w%./%-_]+')
                        or string_match(body, 'https://steamuserimages%-a%.akamaihd%.net/ugc/[%w%./%-_]+')
                        or string_match(body, 'https://shared%.fastly%.steamusercontent%.com/[%w%./%-_]+')
                        or string_match(body, 'https://shared%.fastly%.steamstatic%.com/ugc/[%w%./%-_]+')
                        or string_match(body, 'https://shared%.akamaiusercontent%.net/ugc/[%w%./%-_]+')
                        or string_match(body, 'https://cdn%.cloudflare%.steam%.com/ugc/[%w%./%-_]+')

                    -- protocol-relative URLs: //foo.bar -> https://foo.bar
                    if isstring(scraped) and string_sub(scraped, 1, 2) == "//" then
                        scraped = "https:" .. scraped
                    end

                    if not isstring(scraped) or not string_match(scraped, "^https?://") then
                        MetaFail(wsid, "no preview URL on page (og:image not found)")
                        return Done()
                    end

                    -- the API path had no preview_url but the page had a
                    -- usable one - cache it for next time
                    meta.preview_url = scraped

                    return DownloadImage(scraped)
                end, function()
                    MetaFail(wsid, "page fetch onFailed")
                    return Done()
                end)
            end

            -- PRIMARY: the API's preview_url, when we have one
            if isstring(meta.preview_url) and meta.preview_url ~= "" then
                return DownloadImage(meta.preview_url)
            end

            -- API gave us no preview_url - try the HTML scrape fallback
            return ScrapeForURL()
        end)
    end

    function TBH.FetchAddonMeta(wsid)
        if not TBH.IsValidWSID(wsid) then return end

        local meta = TBH.Client.Meta[wsid]

        -- already done (or failed permanently)?
        if meta and (meta.fetched or meta.imageFailed or meta.failed) then return end
        if metaFetching[wsid] then return end

        metaFetching[wsid] = true
        TBH.Client.Meta[wsid] = meta or {}

        metaQueue[#metaQueue + 1] = wsid
        MetaPump()
    end

    ------------------------------------------------------------------------------
    -- Auto-hotload on Steam subscribe / addon enable
    --
    -- Snapshots the local addon list at boot. When the game reports content
    -- changes (a new subscription finishing its download, or the player
    -- enabling a previously disabled addon), the new id is sent to the server
    -- as a hotload request. The server still applies its own permission
    -- check, cooldown and queue - this only fires the request.
    ------------------------------------------------------------------------------

    TBH.SubWatch = { All = {}, Unmounted = {}, Downloading = {} }

    do
        local addons = engine.GetAddons()

        for i = 1, #addons do
            local addon = addons[i]
            local id = addon.wsid

            if id and id ~= "" then
                TBH.SubWatch.All[id] = true

                if not addon.mounted then
                    TBH.SubWatch.Unmounted[id] = true
                end
            end
        end
    end

    -- mark a wsid as known so our own hotload mounts don't re-trigger the watch
    function TBH.MarkWatched(wsid)
        TBH.SubWatch.All[wsid] = true
        TBH.SubWatch.Unmounted[wsid] = nil
    end

    hook.Add("GameContentChanged", "TBH.AutoSubscribe", function()
        local wantSubs = TBH.CVarAutoSubscribe and TBH.CVarAutoSubscribe:GetBool()
        local wantEnable = TBH.CVarEnableAddons and TBH.CVarEnableAddons:GetBool()

        if not wantSubs and not wantEnable then return end

        -- give Steam a moment to update the addon list
        timer.Simple(1, function()
            local wantSubsNow = TBH.CVarAutoSubscribe and TBH.CVarAutoSubscribe:GetBool()
            local wantEnableNow = TBH.CVarEnableAddons and TBH.CVarEnableAddons:GetBool()

            if not wantSubsNow and not wantEnableNow then return end

            local addons = engine.GetAddons()
            local fresh = {}

            for i = 1, #addons do
                local addon = addons[i]
                local id = addon.wsid

                if id and id ~= "" and TBH.IsValidWSID(id) then
                    local mounted = addon.mounted and true or false
                    local known = TBH.SubWatch.All[id]
                    local knownUnmounted = TBH.SubWatch.Unmounted[id]
                    local wasDownloading = TBH.SubWatch.Downloading[id]

                    if wasDownloading and mounted then
                        -- a subscription we saw mid-download just finished
                        TBH.SubWatch.Downloading[id] = nil
                        if wantSubsNow then fresh[#fresh + 1] = id end
                    elseif not known then
                        -- first time we ever see this id
                        if mounted then
                            if knownUnmounted then
                                -- was disabled before we tracked it -> enable
                                if wantEnableNow then fresh[#fresh + 1] = id end
                            else
                                -- arrived fully mounted -> new subscription
                                if wantSubsNow then fresh[#fresh + 1] = id end
                            end
                        else
                            -- brand new, still downloading - remember it so the
                            -- completion event fires as a SUBSCRIBE
                            TBH.SubWatch.Downloading[id] = true
                        end
                    elseif knownUnmounted and mounted then
                        -- previously disabled addon got enabled
                        if wantEnableNow then fresh[#fresh + 1] = id end
                    end

                    -- keep the tracking tables in sync (also marks seen-but-
                    -- not-fired addons so they never re-fire later)
                    TBH.SubWatch.All[id] = true

                    if mounted then
                        TBH.SubWatch.Unmounted[id] = nil
                    else
                        TBH.SubWatch.Unmounted[id] = true
                    end
                end
            end

            -- cap the burst so nobody spams 50 subscriptions at once
            local count = math.min(#fresh, 5)

            for i = 1, count do
                local wsid = fresh[i]

                TBH.NotifyLocally("New addon detected (subscribe/enable) - requesting hotload...", 0)
                TBH.RequestHotload(wsid, "")
            end
        end)
    end)

    --------------------------------------------------------------------
    -- Result reporting
    --------------------------------------------------------------------

    local function ReportResult(wsid, ok, errCount, errSummary)
        TBH.Diag("[client] reporting result to server: " .. tostring(wsid) .. " ok=" .. tostring(ok) ..
            ((errCount or 0) > 0 and (" errors=" .. tostring(errCount) .. " " .. string_sub(tostring(errSummary or ""), 1, 100)) or ""))

        TBH.Net:Start("result")
        net.WriteString(wsid)
        net.WriteBool(ok)
        net.WriteUInt(math.Clamp(errCount or 0, 0, 65535), 16)
        net.WriteString(string_sub(tostring(errSummary or ""), 1, 180))
        net.SendToServer()
    end
    TBH.ClientReportResult = ReportResult

    --------------------------------------------------------------------
    -- Download queue
    --------------------------------------------------------------------

    -- download progress bar (top of the screen)
    --
    -- the engine draws its own "Downloading..." popup at the bottom and lua cant
    -- hide it, so we show our own. steamworks.DownloadUGC has no progress callback,
    -- so if we can find the half written file on disk the bar follows its real size,
    -- otherwise its just an estimate (shown with a ~) that never hits 100% until
    -- the download is really done

    TBH.DLToasts = TBH.DLToasts or {}

    local function FmtMB(bytes)
        return string.format("%.1f MB", (bytes or 0) / 1048576)
    end

    local function LayoutDLToasts()
        local y = 16
        for wsid, t in pairs(TBH.DLToasts) do
            if IsValid(t) then
                t:SetPos((ScrW() - t:GetWide()) / 2, y)
                y = y + t:GetTall() + 6
            end
        end
    end

    function TBH.DLToastStart(wsid, title)
        if not CLIENT then return end
        if IsValid(TBH.DLToasts[wsid]) then return end

        local okMake, toast = pcall(function()
            local panel = vgui.Create("DPanel")
            panel:SetSize(440, 62)
            panel:SetAlpha(0)
            panel:AlphaTo(255, 0.2, 0)

            panel.WSID = wsid
            panel.Title = tostring(title or wsid)
            panel.StartTime = SysTime()
            panel.Total = 0
            panel.Real = false
            panel.Progress = 0
            panel.Shown = 0
            panel.Done = false
            panel.Failed = false

            local function Detect()
                local candidates = {
                    "cache/workshop/" .. wsid .. ".gma",
                    "cache/workshop/" .. wsid .. ".cache",
                    "download/workshop/" .. wsid .. ".gma",
                }
                for i = 1, #candidates do
                    local size = file.Size(candidates[i], "MOD")
                    if size and size > 0 then return size end
                end
            end

            if steamworks and isfunction(steamworks.FileInfo) then
                pcall(steamworks.FileInfo, wsid, function(res)
                    if IsValid(panel) and istable(res) and tonumber(res.size) then
                        panel.Total = tonumber(res.size)
                    end
                end)
            end

            panel.Think = function(self)
                if self.Done then
                    self.Progress = self.Failed and self.Progress or 1
                else
                    local elapsed = SysTime() - self.StartTime
                    local est

                    local size = Detect()
                    if size and self.Total > 0 then
                        self.Real = true
                        est = math.min(0.99, size / self.Total)
                    else
                        -- assume roughly 6 MB/s when we know the size, else 60 s
                        local expected = (self.Total > 0) and math.max(3, self.Total / (6 * 1048576)) or 60
                        est = math.min(0.95, 1 - math.exp(-2.2 * elapsed / expected))
                    end

                    self.Progress = math.max(self.Progress, est)
                end

                self.Shown = Lerp(FrameTime() * 8, self.Shown, self.Progress)
            end

            panel.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                draw.RoundedBoxEx(6, 0, 0, 5, h, self.Failed and TBH.Colors.error or TBH.Colors.accent, true, false, true, false)

                local title = self.Title
                if #title > 48 then title = string_sub(title, 1, 48) .. "..." end

                draw.SimpleText((self.Done and (self.Failed and "DOWNLOAD FAILED" or "DOWNLOADED") or "DOWNLOADING"),
                    "TBH.Small", 16, 8, self.Failed and TBH.Colors.error or TBH.Colors.tag)
                draw.SimpleText(title, "TBH.Body", 16, 22, TBH.Colors.text)

                local bx, by, bw, bh = 16, h - 16, w - 32 - 76, 8
                draw.RoundedBox(4, bx, by, bw, bh, TBH.Colors.bg)
                if self.Shown > 0.005 then
                    draw.RoundedBox(4, bx, by, math.max(8, bw * math.Clamp(self.Shown, 0, 1)), bh,
                        self.Failed and TBH.Colors.error or TBH.Colors.accent)
                end

                local pct = math.floor(math.Clamp(self.Shown, 0, 1) * 100 + 0.5)
                local prefix = (self.Real or self.Done) and "" or "~"
                draw.SimpleText(prefix .. pct .. "%", "TBH.Small", w - 16, by + bh / 2, TBH.Colors.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

                if self.Total > 0 then
                    draw.SimpleText(FmtMB(self.Total), "TBH.Small", w - 16, 10, TBH.Colors.textdim, TEXT_ALIGN_RIGHT)
                end
            end

            return panel
        end)

        if okMake and IsValid(toast) then
            TBH.DLToasts[wsid] = toast
            LayoutDLToasts()
        end
    end

    function TBH.DLToastDone(wsid, ok)
        local t = TBH.DLToasts[wsid]
        if not IsValid(t) then
            TBH.DLToasts[wsid] = nil
            return
        end

        t.Done = true
        t.Failed = not ok

        t:AlphaTo(0, 0.4, ok and 1.2 or 3, function()
            if IsValid(t) then t:Remove() end
            TBH.DLToasts[wsid] = nil
            LayoutDLToasts()
        end)
    end

    -- steamworks.DownloadUGC with the progress bar attached
    function TBH.DownloadUGCTracked(wsid, title, callback)
        if not title or title == "" or title == wsid then
            local meta = TBH.Client.Meta and TBH.Client.Meta[wsid]
            local known = TBH.Client.Known and TBH.Client.Known[wsid]
            title = (meta and meta.title) or (known and known.title) or wsid
        end

        TBH.DLToastStart(wsid, title)

        return steamworks.DownloadUGC(wsid, function(path, gmaFile)
            TBH.DLToastDone(wsid, path ~= nil and gmaFile ~= nil)
            return callback(path, gmaFile)
        end)
    end

    ----------------------------------------------------------------
    -- Content refresh (v1.1.9): entities that were created BEFORE this client
    -- mounted an addon (another player's hotloaded playermodel, props, NPCs,
    -- weapons...) were built with the error model / error materials and keep
    -- them until something reloads them - that is why late downloaders used to
    -- see an invisible or ERROR playermodel until they reconnected. After a
    -- mount we precache the addon's models, re-apply them to every entity that
    -- already uses one, and reload the materials.
    ----------------------------------------------------------------
    TBH.CVarRefreshContent = CreateClientConVar("hotloader_refresh_content", "1", true, false,
        "After a hotloaded addon is mounted, re-apply its models and reload its materials on entities that were created before it (fixes invisible / ERROR playermodels without reconnecting)")
    TBH.CVarRefreshMaterials = CreateClientConVar("hotloader_refresh_materials", "1", true, false,
        "Part of hotloader_refresh_content: also reload the addon's materials (can hitch for a moment on big addons)")

    TBH.Client.RefreshModels = TBH.Client.RefreshModels or {}
    TBH.Client.RefreshVMTs = TBH.Client.RefreshVMTs or {}

    function TBH.RefreshContent(files)
        if not TBH.CVarRefreshContent:GetBool() or not istable(files) then return end

        local any = false

        for _, f in ipairs(files) do
            local lf = string.lower(tostring(f))

            if string_sub(lf, -4) == ".mdl" then
                TBH.Client.RefreshModels[lf] = true
                pcall(util.PrecacheModel, lf)
                any = true
            elseif string_sub(lf, -4) == ".vmt" and string_sub(lf, 1, 10) == "materials/" then
                TBH.Client.RefreshVMTs[#TBH.Client.RefreshVMTs + 1] = string_sub(lf, 11, -5)
                any = true
            end
        end

        if not any then return end

        -- debounced: a whole collection finishing in a row refreshes once
        timer.Create("TBH.ContentRefresh", 1.5, 1, function()
            local models = TBH.Client.RefreshModels
            local vmts = TBH.Client.RefreshVMTs
            TBH.Client.RefreshModels, TBH.Client.RefreshVMTs = {}, {}

            if TBH.CVarRefreshMaterials:GetBool() and #vmts > 0 then
                if #vmts <= 12 then
                    for _, name in ipairs(vmts) do RunConsoleCommand("mat_reloadmaterial", name) end
                else
                    RunConsoleCommand("mat_reloadallmaterials")
                end
            end

            local refreshed = 0

            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) then
                    local m = ent:GetModel()

                    if isstring(m) and models[string.lower(m)] then
                        ent:SetModel(m)
                        ent:InvalidateBoneCache()
                        ent:SetupBones()
                        refreshed = refreshed + 1
                    end
                end
            end

            if refreshed > 0 then
                TBH.Diag("[client] content refresh: re-applied models on " .. refreshed .. " entity(ies)")
            end
        end)
    end

    -- a download that failed (Steam hiccup, busy queue...) is retried a few times
    -- instead of waiting for a reconnect
    TBH.Client.Retries = TBH.Client.Retries or {}

    function TBH.ClientScheduleRetry(wsid, title)
        local n = (TBH.Client.Retries[wsid] or 0) + 1

        if n > 3 then
            TBH.NotifyLocally("Gave up on \"" .. tostring(title or wsid) .. "\" after 3 retries - type hotloader_resync to try again", 3, 8)
            return
        end

        TBH.Client.Retries[wsid] = n
        local delay = ({ 15, 45, 120 })[n]

        TBH.NotifyLocally("Will retry \"" .. tostring(title or wsid) .. "\" in " .. delay .. "s (attempt " .. n .. "/3)", 3)

        timer.Create("TBH.ClientRetry." .. wsid, delay, 1, function()
            if TBH.Client.Mounted[wsid] then return end
            if not TBH.Client.Known[wsid] then return end -- the server no longer has it

            TBH.Diag("[client] retrying " .. tostring(wsid) .. " (attempt " .. n .. ")")
            TBH.ClientEnqueue(wsid, title)
        end)
    end

    function TBH.ClientEnqueue(wsid, title)
        for i = 1, #TBH.Client.Queue do
            if TBH.Client.Queue[i].wsid == wsid then return end
        end

        if TBH.Client.Mounted[wsid] then return end

        -- already downloading/initializing this exact addon?
        if TBH.Client.Current == wsid then
            TBH.Diag("[client] enqueue skipped (already in flight): " .. tostring(wsid))
            return
        end

        -- hard cap: a runaway flood must never stack unbounded work
        if #TBH.Client.Queue >= 40 then
            TBH.Diag("[client] enqueue REFUSED - queue full (40): " .. tostring(wsid))
            TBH.NotifyLocally("Sync queue is full (40) - skipping " .. tostring(title or wsid), 3)
            -- v1.1.0: tell the server we gave up on this one, otherwise
            -- its collection gate waits for an ack that never comes
            ReportResult(wsid, false, 1, "client sync queue full")
            return
        end

        -- prevent our own mounts from re-triggering the subscribe watcher
        TBH.MarkWatched(wsid)

        TBH.Client.Queue[#TBH.Client.Queue + 1] = { wsid = wsid, title = title }
        TBH.Diag("[client] enqueued '" .. string_sub(tostring(title or wsid), 1, 50) .. "' (" .. tostring(wsid) .. ") - queue depth " .. #TBH.Client.Queue)
        TBH.ProcessClientQueue()
    end

    function TBH.ProcessClientQueue()
        if TBH.Client.Busy then return end

        local entry = table.remove(TBH.Client.Queue, 1)
        if not entry then
            hook.Run("TBH.ClientListChanged")
            return
        end

        TBH.Client.Busy = true
        TBH.Client.Current = entry.wsid

        local wsid = entry.wsid
        local title = entry.title or wsid
        local finished = false

        local function Finish(ok, errCount, errSummary)
            if finished then return end
            finished = true

            timer.Remove("TBH.ClientDL." .. wsid)
            TBH.Client.Busy = false
            TBH.Client.Current = nil

            TBH.Diag("[client] sync finished " .. (ok and "OK" or ("FAILED: " .. tostring(errSummary))) ..
                " - " .. (#TBH.Client.Queue > 0 and ("next in " .. ((TBH.ServerInfo and TBH.ServerInfo.batchDelay) or 3) .. "s") or "queue empty"))

            if ok then
                TBH.Client.Retries[wsid] = nil

                local inBatch = TBH.Client.Batch and TBH.Client.Batch.active
                if not inBatch then
                    TBH.NotifyLocally("\"" .. title .. "\" hotloaded!", 1)
                end
                -- mid-batch: no per-addon fanfare, the HUD counter covers it
            else
                TBH.NotifyLocally("Failed to sync \"" .. title .. "\": " .. tostring(errSummary or "unknown error"), 2)

                -- never got mounted here -> try again later on its own
                if not TBH.Client.Mounted[wsid] then
                    TBH.ClientScheduleRetry(wsid, title)
                end
            end

            hook.Run("TBH.ClientListChanged")

            -- adaptive pacing: when a batch (collection) is still queued,
            -- give the engine real time to digest each mount - the batch
            -- delay is synced from the server (hotloader_batch_delay)
            local batchDelay = 3
            if TBH.ServerInfo and TBH.ServerInfo.batchDelay then
                batchDelay = math.Clamp(TBH.ServerInfo.batchDelay, 1, 30)
            end

            local nextDelay = (#TBH.Client.Queue > 0) and batchDelay or 0.5
            timer.Simple(nextDelay, TBH.ProcessClientQueue)
        end

        -- during batches the HUD counter tracks progress; no per-member spam
        if TBH.Client.Batch and TBH.Client.Batch.active then
            -- quiet: the counter + session cards tell the story
        else
            TBH.NotifyLocally("Downloading \"" .. title .. "\"...", 0)
        end

        -- v1.1.0: 240s could cut off legitimate multi-hundred-MB collection
        -- members and desync the whole batch - big addons get big time.
        -- The watchdog is split in two phases: one window for the download,
        -- then a FRESH window for the frame-spread initialization - and a
        -- timeout during init kills the pump, so a stalled addon can never
        -- interleave its Lua with the next queue entry.
        local watchdog = { bundle = nil }

        local function WatchdogFire(reason)
            if watchdog.bundle then
                watchdog.bundle.PumpAlive = false
            end
            Finish(false, 1, reason)
        end

        timer.Create("TBH.ClientDL." .. wsid, 600, 1, function()
            WatchdogFire("download timed out")
        end)

        TBH.Diag("[client] DownloadUGC CALLING for '" .. string_sub(tostring(title), 1, 50) .. "' (" .. tostring(wsid) .. ") - download watchdog armed (600s)")

        -- SAFEGUARD: the CALL itself can throw (nil function / engine
        -- hiccup) - that must release the queue too, not just callback errors
        local okCall = pcall(TBH.DownloadUGCTracked, wsid, title, function(path, gmaFile)
            -- SAFEGUARD: any error inside here must still release the queue
            -- (otherwise Busy stays true forever and the hotloader jams)
            local okCB, errCB = pcall(function()
            if finished then return end

            TBH.Diag("[client] DownloadUGC callback fired for " .. tostring(wsid))

            if not path or not gmaFile then
                TBH.Diag("[client] DownloadUGC FAILED (no path/gmaFile) for " .. tostring(wsid))
                ReportResult(wsid, false, 1, "download failed")
                return Finish(false, 1, "download failed (hidden/removed addon or Steam offline?)")
            end

            local notAddon = TBH.WhyNotAnAddon(path)
            if notAddon then
                TBH.Diag("[client] not an addon file: " .. tostring(path))
                TBH.NotifyLocally(notAddon, 3, 8)
                ReportResult(wsid, false, 1, "not an addon")
                return Finish(false, 1, notAddon)
            end

            TBH.Diag("[client] MountGMA CALLING (can freeze + crash on huge addons): " .. tostring(path))

            local ok, files = game.MountGMA(path)

            if not ok or not istable(files) then
                TBH.Diag("[client] MountGMA FAILED for " .. tostring(wsid))
                ReportResult(wsid, false, 1, "mount failed")
                return Finish(false, 1, "could not mount the addon")
            end

            TBH.Diag("[client] MountGMA ok: " .. #files .. " files mounted")

            -- V.1.0.6: remember the local GMA path - FULL unload (via the
            -- gmaunmount module) needs the exact path the engine mounted
            TBH.Client.GmaPaths[wsid] = path

            local cleanFiles, seen = {}, {}
            for _, f in pairs(files) do
                if not seen[f] then
                    seen[f] = true
                    cleanFiles[#cleanFiles + 1] = f
                end
            end

            local gmaTitle = TBH.GetGMATitle(path)
            if gmaTitle and #gmaTitle > 0 then
                title = gmaTitle
            end

            -- small delay so the filesystem catch-up + UI don't fight each
            -- other; longer while a batch is still queued
            local initDelay = (#TBH.Client.Queue > 0) and 0.8 or 0.3
            TBH.Diag("[client] scheduling client init in " .. initDelay .. "s (filesystem catch-up)")

            timer.Simple(initDelay, function()
                if finished then return end

                -- download made it: start a FRESH watchdog window that
                -- covers the initialization phase and kills the pump on
                -- timeout (no zombie init, no interleaving)
                timer.Create("TBH.ClientDL." .. wsid, 600, 1, function()
                    WatchdogFire("initialization timed out")
                end)

                TBH.Diag("[client] Bundle:Create CALLING (" .. #cleanFiles .. " files) - init watchdog re-armed (600s)")

                pcall(TBH.ScanConflicts, wsid, title, cleanFiles)

                local okCreate, bundle = pcall(TBH.Bundle.Create, TBH.Bundle, cleanFiles, title)
                bundle = (okCreate and istable(bundle)) and bundle or nil

                if not bundle then
                    TBH.Client.Mounted[wsid] = {
                        title = title,
                        files = #cleanFiles,
                        time = os.time(),
                        errors = 1,
                    }
                    ReportResult(wsid, false, 1, "client initialization crashed")
                    return Finish(false, 1, "client initialization crashed")
                end

                watchdog.bundle = bundle

                TBH.Diag("[client] client init starting (frame-spread): '" .. string_sub(tostring(title), 1, 50) .. "'")

                -- v1.1.0: frame-spread initialization - the addon's Lua
                -- trickles in over several frames instead of one giant
                -- freeze; the result is reported when it truly finished
                local okInit = pcall(bundle.Initialize, bundle, function(b)
                    if finished then return end

                    TBH.Diag("[client] client init COMPLETE: " .. #b.Errors .. " lua error(s)")

                    local okDone, errDone = pcall(function()
                        TBH.Client.Mounted[wsid] = {
                            title = title,
                            files = #cleanFiles,
                            time = os.time(),
                            errors = #b.Errors,
                            maps = TBH.ExtractMaps(cleanFiles),
                            bundle = b,
                            unloaded = false,
                        }

                        pcall(TBH.RefreshContent, cleanFiles)

                        local okResult = (#b.Errors == 0)
                        ReportResult(wsid, okResult, #b.Errors, b.Errors[1])
                        Finish(okResult, #b.Errors, b.Errors[1])
                    end)

                    if not okDone then
                        TBH.Client.Mounted[wsid] = TBH.Client.Mounted[wsid] or {
                            title = title,
                            files = #cleanFiles,
                            time = os.time(),
                            errors = 1,
                        }
                        ReportResult(wsid, false, 1, "client initialization crashed")
                        Finish(false, 1, "client initialization crashed: " .. string_sub(tostring(errDone), 1, 120))
                    end
                end)

                if not okInit then
                    TBH.Client.Mounted[wsid] = {
                        title = title,
                        files = #cleanFiles,
                        time = os.time(),
                        errors = 1,
                    }
                    ReportResult(wsid, false, 1, "client initialization crashed")
                    Finish(false, 1, "client initialization crashed")
                end
            end)
            end)

            if not okCB then
                Finish(false, 1, "download callback error: " .. tostring(errCB))
            end
        end)

        if not okCall then
            Finish(false, 1, "download could not start (engine error?)")
        end
    end

    --------------------------------------------------------------------
    -- Server messages
    --------------------------------------------------------------------

    local function ReadMaps()
        local count = net.ReadUInt(8)
        local maps = {}

        for i = 1, count do
            maps[#maps + 1] = net.ReadString()
        end

        return maps
    end

    -- the server is force-reloading this addon: drop our copy (soft unload) so the
    -- "mount" message that follows runs the whole sync + init again
    TBH.Net:Receive("forcereload", function()
        local wsid = net.ReadString()
        local entry = TBH.Client.Mounted[wsid]

        if istable(entry) and istable(entry.bundle) and isfunction(entry.bundle.Unload) then
            TBH.Client.LastClasses = TBH.Client.LastClasses or {}
            if TBH.ClassSetOf then TBH.Client.LastClasses[wsid] = TBH.ClassSetOf(entry.bundle) end
            pcall(entry.bundle.Unload, entry.bundle, false)
        end

        TBH.Client.Mounted[wsid] = nil
        TBH.Diag("[client] force reload: dropped our copy of " .. tostring(wsid))
        hook.Run("TBH.ClientListChanged")
    end)

    TBH.Net:Receive("mount", function()
        local wsid = net.ReadString()
        local title = net.ReadString()
        local maps = ReadMaps()

        TBH.Diag("[client] mount received: " .. tostring(wsid) .. " '" .. string_sub(tostring(title), 1, 50) .. "'")

        -- v1.1.2: the server mounted the EXACT id we asked for and no
        -- collection was announced -> it was treated as a single addon
        -- (its collection markers were not detected server-side!)
        if TBH.DiagState.Active and wsid == TBH.DiagState.RequestedWSID and not TBH.DiagState.CollectionConfirmed then
            TBH.DiagState.RequestedWSID = nil
            TBH.Diag("[client] WARNING: the server is hotloading our request as a SINGLE addon (its collection markers were not detected!) - following that flow")
            TBH.DiagAutoCleanup(120)
        end

        TBH.Client.Known[wsid] = { title = title, time = os.time(), maps = maps }
        TBH.FetchAddonMeta(wsid)
        hook.Run("TBH.ClientListChanged")

        -- the browser's LOAD MAP button was used on this addon: once the
        -- server has it mounted (that's what this message means), switch!
        if TBH.Client.AutoLoadMap[wsid] then
            TBH.Client.AutoLoadMap[wsid] = nil

            timer.Simple(3, function()
                if istable(maps) and #maps == 1 then
                    TBH.NotifyLocally("Map addon is on the server - switching to \"" .. maps[1] .. "\"... (players still syncing download it from the server)", 0)
                    TBH.RequestLoadMap(maps[1])
                elseif istable(maps) and #maps > 1 then
                    TBH.NotifyLocally("That addon contains " .. #maps .. " maps - right-click it in the Hotloader tab to pick one", 3)
                else
                    TBH.NotifyLocally("That addon turned out to contain no maps!", 2)
                end
            end)
        end

        if TBH.Client.Mounted[wsid] then
            TBH.Diag("[client] already mounted - acking immediately: " .. tostring(wsid))
            ReportResult(wsid, true, 0, "already mounted")
            return
        end

        TBH.ClientEnqueue(wsid, title)
    end)

    TBH.Net:Receive("sync", function()
        local count = net.ReadUInt(16)
        local pending = 0

        local serverList = {}

        for i = 1, count do
            local wsid = net.ReadString()
            local title = net.ReadString()
            local maps = ReadMaps()

            serverList[wsid] = true
            TBH.Client.Known[wsid] = { title = title, time = os.time(), maps = maps }
            TBH.FetchAddonMeta(wsid)

            if not TBH.Client.Mounted[wsid] then
                TBH.ClientEnqueue(wsid, title)
                pending = pending + 1
            end
        end

        -- prune stale entries: things we requested/queued earlier that the
        -- server now says it doesn't have (denied, failed, or a restarted
        -- server). Never touch entries that are mounted or still queued.
        for wsid, entry in pairs(TBH.Client.Known) do
            if not serverList[wsid] and not TBH.Client.Mounted[wsid] then
                local queued = false

                for i = 1, #TBH.Client.Queue do
                    if TBH.Client.Queue[i].wsid == wsid then queued = true break end
                end

                if not queued then
                    TBH.Client.Known[wsid] = nil
                end
            end
        end

        if pending > 0 then
            TBH.NotifyLocally("Syncing " .. pending .. " hotloaded addon(s) - sit tight...", 0)
        end

        hook.Run("TBH.ClientListChanged")
    end)

    TBH.Net:Receive("status", function()
        local level = net.ReadUInt(8)
        local msg = net.ReadString()
        TBH.Diag("[client] server status: " .. msg)
        TBH.NotifyLocally(msg, level)
    end)

    ------------------------------------------------------------------------------
    -- Collection batch progress (the DTOybox-style counter)
    ------------------------------------------------------------------------------

    TBH.Client.Batch = TBH.Client.Batch or { active = false }

    TBH.Net:Receive("batchprog", function()
        local done = net.ReadUInt(8)
        local total = net.ReadUInt(8)
        local title = net.ReadString()

        if not TBH.DiagState.Active then
            TBH.DiagStart("collection batch announced by server: '" .. string_sub(tostring(title), 1, 60) .. "' (" .. total .. " addons)")
        else
            TBH.Diag("[client] batch progress: " .. done .. "/" .. total)
        end

        TBH.DiagState.CollectionConfirmed = true

        TBH.Client.Batch = {
            active = true,
            done = done,
            total = total,
            title = title,
        }
    end)

    TBH.Net:Receive("batchend", function()
        local total = net.ReadUInt(8)
        local title = net.ReadString()

        TBH.Diag("[client] collection COMPLETE: " .. total .. " addons - rebuilding spawnmenu once")

        TBH.Client.Batch = { active = false }

        if total > 0 then
            TBH.NotifyLocally("Collection \"" .. title .. "\" complete - " .. total .. " addons hotloaded!", 1, 8)
        end

        -- the whole collection settled: NOW do the single menu rebuild
        TBH.QueueSpawnMenuRefresh(1)

        -- keep logging a little longer so the spawnmenu rebuild (a classic
        -- crash point) is captured too, then close the log file
        timer.Simple(10, function()
            TBH.DiagEnd("collection complete + menu rebuild settled")
        end)
    end)

    -- compact on-screen progress counter while a collection is hotloading
    hook.Add("HUDPaint", "TBH.BatchProgress", function()
        local b = TBH.Client.Batch

        if not b or not b.active or (b.total or 0) <= 0 then return end

        local w, h = 300, 66
        local x = ScrW() - w - 24
        local y = ScrH() - h - 80

        draw.RoundedBox(6, x, y, w, h, Color(16, 20, 17, 235))
        draw.RoundedBoxEx(6, x, y, 5, h, TBH.Colors.accent, true, false, true, false)

        draw.SimpleText("HOTLOADING COLLECTION", "TBH.Small", x + 14, y + 8, TBH.Colors.tag)
        draw.SimpleText(string_sub(b.title or "?", 1, 36), "TBH.Body", x + 14, y + 24, TBH.Colors.text)
        draw.SimpleText((b.done or 0) .. " / " .. b.total, "TBH.Body", x + w - 14, y + 8, TBH.Colors.tag, TEXT_ALIGN_RIGHT)

        -- progress bar
        local bw = w - 28
        local frac = math.Clamp((b.done or 0) / math.max(b.total or 1, 1), 0, 1)

        draw.RoundedBox(2, x + 14, y + 46, bw, 8, TBH.Colors.bgPanel2)

        if frac > 0 then
            draw.RoundedBox(2, x + 14, y + 46, bw * frac, 8, TBH.Colors.tag)
        end
    end)

    -- server resolved a collection: drop our optimistic card for the
    -- collection id itself (the members get their own cards)
    TBH.Net:Receive("dropentry", function()
        local wsid = net.ReadString()

        if not TBH.DiagState.Active then
            TBH.DiagStart("server resolved our request as a COLLECTION (" .. tostring(wsid) .. ")")
        end

        TBH.DiagState.CollectionConfirmed = true

        TBH.Diag("[client] dropping optimistic card for collection id " .. tostring(wsid))

        if TBH.Client.Known[wsid] and not TBH.Client.Mounted[wsid] then
            TBH.Client.Known[wsid] = nil
            hook.Run("TBH.ClientListChanged")
        end
    end)

    -- server unloaded an addon: unload our client-side copy too
    TBH.Net:Receive("unload", function()
        local wsid = net.ReadString()
        local removeEntities = net.ReadBool()

        local entry = TBH.Client.Mounted[wsid]

        if istable(entry) then
            local bundle = entry.bundle

            if istable(bundle) and isfunction(bundle.Unload) then
                local ok, err = pcall(bundle.Unload, bundle, removeEntities)
                if not ok then
                    MsgC(TBH.Colors.error, "[Hotloader] unload crashed: " .. tostring(err) .. "\n")
                end
            end

            entry.unloaded = true
        end

        if istable(TBH.Client.Known[wsid]) then
            TBH.Client.Known[wsid].unloaded = true
        end

        hook.Run("TBH.ClientListChanged")
    end)

    --------------------------------------------------------------------
    -- V.1.0.8: client-realm probe. Only SUCCESS is cached - a failure may
    -- just be a DLL the user drops into lua/bin later, so it re-probes on
    -- every use. package.loaded is cleared before each attempt (GMod's
    -- require caches module loads - an old silently-failing DLL would
    -- otherwise poison every future require until restart).
    --------------------------------------------------------------------

    local function ClientHasUnmountModule()
        if TBH.ClientCanUnmount then return true end

        local ok, err = TBH.DetectGmaUnmountModule()
        if ok then
            TBH.ClientCanUnmount = true
            TBH.ClientUnmountError = nil
            return true
        end

        TBH.ClientUnmountError = err
        return false
    end

    TBH.Net:Receive("fullunload", function()
        local wsid = net.ReadString()
        local removeEntities = net.ReadBool()

        -- pick a sample file to verify the local unmount afterwards
        local entry = TBH.Client.Mounted[wsid]
        local sampleFile = nil

        if istable(entry) and istable(entry.bundle) and istable(entry.bundle.FlatFiles) then
            for i = 1, math.min(#entry.bundle.FlatFiles, 50) do
                local f = entry.bundle.FlatFiles[i]
                if isstring(f) and file.Exists(f, "GAME") then
                    sampleFile = f
                    break
                end
            end
        end

        -- soft unload first (same as the normal "unload" receiver)
        if istable(entry) then
            local bundle = entry.bundle

            if istable(bundle) and isfunction(bundle.Unload) then
                local ok, err = pcall(bundle.Unload, bundle, removeEntities)
                if not ok then
                    MsgC(TBH.Colors.error, "[Hotloader] full-unload crashed: " .. tostring(err) .. "\n")
                end
            end

            entry.unloaded = true
        end

        if istable(TBH.Client.Known[wsid]) then
            TBH.Client.Known[wsid].unloaded = true
        end

        -- then unmount the local files (needs the client module copy)
        if ClientHasUnmountModule() then
            local ok, dispatched, detail = pcall(gmaunmount.Unmount, wsid)
            local removed = ok and dispatched == true

            if removed and sampleFile then
                removed = not file.Exists(sampleFile, "GAME")
            end

            if removed then
                TBH.NotifyLocally("Fully unloaded \"" .. (entry and entry.title or wsid) .. "\" - Lua AND files unmounted", 1)
            else
                TBH.NotifyLocally("Soft-unloaded \"" .. (entry and entry.title or wsid) .. "\" - local files stayed mounted (" .. tostring(ok and detail or dispatched) .. ")", 3)
            end
        else
            -- V.1.0.7: include the ACTUAL error so the problem is diagnosable
            TBH.NotifyLocally("Unloaded \"" .. (entry and entry.title or wsid) .. "\" (Lua removed; local files stay mounted - client module: " .. tostring(TBH.ClientUnmountError or "") .. ")", 3)
        end

        TBH.Client.GmaPaths[wsid] = nil
        hook.Run("TBH.ClientListChanged")
    end)

    TBH.Net:Receive("chatmsg", function()
        local level = net.ReadUInt(8)
        local duration = net.ReadUInt(8)
        local msg = net.ReadString()

        local color = TBH.Colors.text
        if level == 1 then color = Color(190, 240, 160) end
        if level == 3 then color = TBH.Colors.warn end

        chat.AddText(TBH.Colors.tag, "[Hotloader] ", color, msg)

        -- long announcements (like the map-change wait hint) also pop up as
        -- an on-screen notification so nobody misses them
        if isnumber(duration) and duration > 0 then
            notification.AddLegacy("[Hotloader] " .. string_sub(msg, 1, 140), NOTIFY_GENERIC, math.Clamp(duration, 1, 30))
        end
    end)

    --------------------------------------------------------------------
    -- Listen host fallback: download on the server's behalf
    --------------------------------------------------------------------

    -- SAFEGUARD: only ONE host-routed download at a time. Concurrent UGC
    -- downloads on the host client (multiple quick requests on a module-less
    -- listen server) are heavy - anything arriving mid-download waits in a
    -- retry queue and runs directly when the current one finishes.
    local StartHostDownload

    local function PumpHostRetry()
        if TBH.Client.HostLoading ~= nil then return end
        if not TBH.Client.HostRetry then return end

        local nextUp = table.remove(TBH.Client.HostRetry, 1)
        if not nextUp then return end

        timer.Simple(1, function()
            if TBH.Client.HostLoading ~= nil then
                -- still busy - put it back at the front
                table.insert(TBH.Client.HostRetry, 1, nextUp)
                return
            end

            if isfunction(StartHostDownload) then
                TBH.NotifyLocally("Starting queued host download \"" .. (nextUp.title ~= "" and nextUp.title or nextUp.wsid) .. "\"...", 0)
                StartHostDownload(nextUp.wsid, nextUp.title or "")
            end
        end)
    end

    StartHostDownload = function(wsid, titleHint)
        -- prevent our own mounts from re-triggering the subscribe watcher
        TBH.MarkWatched(wsid)

        TBH.Diag("[client] host download starting: " .. tostring(wsid))

        if TBH.Client.Mounted[wsid] then return end
        if TBH.Client.HostLoading == wsid then return end

        TBH.Client.HostLoading = wsid

        local function HostFail(reason)
            if TBH.Client.HostLoading ~= wsid then return end
            TBH.Client.HostLoading = nil
            PumpHostRetry()

            TBH.Diag("[client] host download FAILED: " .. tostring(reason))
            TBH.NotifyLocally("Host download of " .. wsid .. " failed: " .. tostring(reason), 2)

            TBH.Net:Start("hostfail")
            net.WriteString(wsid)
            net.SendToServer()
        end

        TBH.Diag("[client] host DownloadUGC CALLING for " .. tostring(wsid) .. " (if this id is secretly a COLLECTION, this is a crash suspect!)")

        TBH.DownloadUGCTracked(wsid, titleHint, function(path, gmaFile)
            if TBH.Client.HostLoading ~= wsid then return end

            if not path or not gmaFile then
                return HostFail("download failed")
            end

            local notAddon = TBH.WhyNotAnAddon(path)
            if notAddon then
                return HostFail(notAddon)
            end

            TBH.Diag("[client] host MountGMA CALLING (can freeze + crash on huge addons): " .. tostring(path))

            local ok, files = game.MountGMA(path)

            if not ok or not istable(files) then
                return HostFail("mount failed")
            end

            TBH.Diag("[client] host MountGMA ok: " .. #files .. " files mounted")

            -- V.1.0.6: remember the local GMA path (host flow) for FULL unload
            TBH.Client.GmaPaths[wsid] = path

            local cleanFiles, seen = {}, {}
            for _, f in pairs(files) do
                if not seen[f] then
                    seen[f] = true
                    cleanFiles[#cleanFiles + 1] = f
                end
            end

            local title = TBH.GetGMATitle(path) or titleHint
            if not isstring(title) or title == "" then title = wsid end

            -- ship the file list to the server in <=60KB chunks
            local compressed = util.Compress(util.TableToJSON(cleanFiles))

            if not compressed then
                return HostFail("could not package the file list")
            end

            local total = math.ceil(#compressed / 60000)

            if total < 1 or total > 255 then
                return HostFail("addon file list too big")
            end

            for i = 1, total do
                local chunk = string_sub(compressed, (i - 1) * 60000 + 1, i * 60000)

                TBH.Net:Start("hostchunk")
                net.WriteString(wsid)
                net.WriteUInt(total, 8)
                net.WriteUInt(i, 8)
                net.WriteUInt(#chunk, 16)
                net.WriteData(chunk, #chunk)
                net.SendToServer()
            end

            TBH.Net:Start("hostdone")
            net.WriteString(wsid)
            net.WriteString(title)
            net.SendToServer()

            TBH.Client.HostLoading = nil
            PumpHostRetry()

            -- give the server a moment to initialize first, then run the
            -- client-side files (mirrors boot order: server before client)
            timer.Simple(1.5, function()
                pcall(TBH.ScanConflicts, wsid, title, cleanFiles)

                local okCreate, bundle = pcall(TBH.Bundle.Create, TBH.Bundle, cleanFiles, title)
                bundle = (okCreate and istable(bundle)) and bundle or nil

                if not bundle then
                    TBH.Client.Mounted[wsid] = {
                        title = title,
                        files = #cleanFiles,
                        time = os.time(),
                        errors = 1,
                        maps = TBH.ExtractMaps(cleanFiles),
                        unloaded = false,
                    }
                    TBH.NotifyLocally("Client init of \"" .. title .. "\" crashed (see console)", 2)
                    hook.Run("TBH.ClientListChanged")
                    return
                end

                -- v1.1.0: frame-spread initialization (no main-thread freeze)
                local okInit = pcall(bundle.Initialize, bundle, function(b)
                    local okDone, errDone = pcall(function()
                        TBH.Client.Mounted[wsid] = {
                            title = title,
                            files = #cleanFiles,
                            time = os.time(),
                            errors = #b.Errors,
                            maps = TBH.ExtractMaps(cleanFiles),
                            bundle = b,
                            unloaded = false,
                        }
                    end)

                    if not okDone then
                        TBH.Client.Mounted[wsid] = {
                            title = title,
                            files = #cleanFiles,
                            time = os.time(),
                            errors = 1,
                            maps = TBH.ExtractMaps(cleanFiles),
                            unloaded = false,
                        }
                        TBH.NotifyLocally("Client init of \"" .. title .. "\" crashed (see console)", 2)
                    elseif #b.Errors > 0 then
                        TBH.NotifyLocally("\"" .. title .. "\" hotloaded with " .. #b.Errors .. " Lua error(s) (see console)", 3)
                    else
                        TBH.NotifyLocally("\"" .. title .. "\" hotloaded!", 1)
                    end

                    hook.Run("TBH.ClientListChanged")
                end)

                if not okInit then
                    TBH.Client.Mounted[wsid] = {
                        title = title,
                        files = #cleanFiles,
                        time = os.time(),
                        errors = 1,
                        maps = TBH.ExtractMaps(cleanFiles),
                        unloaded = false,
                    }
                    TBH.NotifyLocally("Client init of \"" .. title .. "\" crashed (see console)", 2)
                    hook.Run("TBH.ClientListChanged")
                end
            end)
        end)
    end

    TBH.Net:Receive("hostdl", function()
        local wsid = net.ReadString()
        local titleHint = net.ReadString()

        TBH.Diag("[client] server routed a download through us (no gmsv_workshop module): " .. tostring(wsid))

        TBH.MarkWatched(wsid)

        if TBH.Client.Mounted[wsid] then return end
        if TBH.Client.HostLoading == wsid then return end

        -- another host download already in flight? queue it for later
        if TBH.Client.HostLoading ~= nil then
            TBH.Client.HostRetry = TBH.Client.HostRetry or {}
            TBH.Client.HostRetry[#TBH.Client.HostRetry + 1] = { wsid = wsid, title = titleHint }
            TBH.NotifyLocally("Another host download is running - \"" .. (titleHint ~= "" and titleHint or wsid) .. "\" queued next", 3)
            return
        end

        StartHostDownload(wsid, titleHint)
    end)

    --------------------------------------------------------------------
    -- Client-side request helpers (used by menu + browser + concommands)
    --------------------------------------------------------------------

    -- ask the server to switch to a map (must exist on the server, e.g.
    -- inside a hotloaded map addon)
    function TBH.RequestLoadMap(mapname)
        if not isstring(mapname) or mapname == "" then return end

        surface.PlaySound("buttons/button15.wav")
        TBH.NotifyLocally("Requesting map change to \"" .. mapname .. "\"...", 0)

        TBH.Net:Start("loadmap")
        net.WriteString(mapname)
        net.SendToServer()
    end

    -- ask the server to soft-unload a hotloaded addon
    function TBH.RequestUnload(wsid, removeEntities)
        if not TBH.IsValidWSID(wsid) then return end

        TBH.Net:Start("unloadreq")
        net.WriteString(wsid)
        net.WriteBool(removeEntities or false)
        net.SendToServer()
    end

    -- V.1.0.6: ask the server to FULL-unload (soft unload + unmount files
    -- through the gmaunmount module; the server tells every client to do the same)
    function TBH.RequestFullUnload(wsid, removeEntities)
        if not TBH.IsValidWSID(wsid) then return end

        TBH.Net:Start("fullunloadreq")
        net.WriteString(wsid)
        net.WriteBool(removeEntities or false)
        net.SendToServer()
    end

    -- FORCE ADDON RELOAD: asks the server to unload its copy of the addon,
    -- tells every player to drop theirs, then hotloads it again for everybody.
    -- Use it when an addon is bugged or a player on the server can't see it.
    function TBH.RequestForceReload(wsid, titleHint)
        if not TBH.IsValidWSID(wsid) then return false end

        -- (the server answers with its own "Force reloading..." status line)
        surface.PlaySound("buttons/button15.wav")

        TBH.Net:Start("forcereload")
        net.WriteString(wsid)
        net.WriteString(string_sub(tostring(titleHint or ""), 1, 100))
        net.SendToServer()

        return true
    end

    function TBH.RequestHotload(input, titleHint, autoLoadMap)
        local wsid = TBH.ExtractWSID(input)

        if not wsid then
            TBH.NotifyLocally("That doesn't look like a workshop id or url", 2)
            return false
        end

        -- v1.1.2: the crash log starts the MOMENT the button is pressed.
        -- If the game dies anywhere in the pipeline (even before the server
        -- confirms what the id is), the file is already on disk.
        TBH.DiagStart("hotload request submitted for " .. wsid .. (autoLoadMap and " (LOAD MAP button)" or ""))
        TBH.DiagState.RequestedWSID = wsid
        TBH.DiagAutoCleanup(30)

        -- track it in the session list right away so the player sees what
        -- they requested/hothotloaded/enabled the moment they click
        if not TBH.Client.Known[wsid] then
            TBH.Client.Known[wsid] = {
                title = (titleHint ~= nil and titleHint ~= "" and titleHint) or wsid,
                time = os.time(),
                requested = true,
            }
            TBH.FetchAddonMeta(wsid)
            hook.Run("TBH.ClientListChanged")
        end

        -- remember that this was a LOAD MAP click: when the server finishes
        -- mounting, we automatically ask it to switch levels
        if autoLoadMap then
            TBH.Client.AutoLoadMap[wsid] = true
        end

        surface.PlaySound("buttons/button15.wav")

        TBH.NotifyLocally("Requesting hotload of \"" .. (titleHint ~= "" and titleHint or wsid) .. "\"...", 0)

        TBH.Net:Start("req")
        net.WriteString(wsid)
        net.WriteBool(true)
        net.WriteString(string_sub(tostring(titleHint or ""), 1, 100))
        net.SendToServer()

        return true
    end
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  EMBEDDED WEB BROWSER
--
--  A full in-game browser (DHTML/CEF). Whenever you open a Steam Workshop
--  addon page, JavaScript gets injected that drops a big accent-colored
--  HOTLOAD button right next to the Subscribe button. Clicking it sends the
--  addon straight into the hotload pipeline. (V.1.0.4: the button's palette
--  derives from your accent color and re-themes live.)
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if CLIENT then
    ------------------------------------------------------------------------------
    -- Injected JavaScript (runs on every page the browser loads)
    ------------------------------------------------------------------------------

    local BROWSER_JS = [==[
(function(){
    // V.1.0.4: PALETTE FIRST (before the __tbhBoys guard) so re-injection
    // refreshes the accent color even on a page where the button logic
    // already ran. The whole palette derives from the (r, g, b) Hotloader
    // passes in: initial values are baked in by Lua (TBH.BrowserJS()),
    // live updates arrive via window.__tbhSetAccent from Lua.
    function clamp255(x) { x = Math.round(x); return x < 0 ? 0 : (x > 255 ? 255 : x); }
    function rgb(a) { return 'rgb(' + a[0] + ',' + a[1] + ',' + a[2] + ')'; }
    function rgba(a, al) { return 'rgba(' + a[0] + ',' + a[1] + ',' + a[2] + ',' + al + ')'; }

    window.__tbhSetAccent = function(r, g, b) {
        try {
            r = clamp255(r); g = clamp255(g); b = clamp255(b);
            var acc    = [r, g, b];
            var bright = [clamp255(r * 1.45), clamp255(g * 1.45), clamp255(b * 1.45)];
            var mid    = [clamp255(r * 0.67), clamp255(g * 0.67), clamp255(b * 0.67)];
            var dark   = [clamp255(r * 0.10 + 4), clamp255(g * 0.10 + 4), clamp255(b * 0.10 + 4)];
            var light  = [clamp255(r + (255 - r) * 0.72), clamp255(g + (255 - g) * 0.72), clamp255(b + (255 - b) * 0.72)];

            var css = document.getElementById('hotloader_style');
            if (!css) {
                css = document.createElement('style');
                css.id = 'hotloader_style';
                (document.head || document.documentElement).appendChild(css);
            }
            css.textContent = ''
                + '#hotloader_hotload_btn{display:inline-block;cursor:pointer;margin:6px 0 4px 0;'
                + 'background:linear-gradient(to bottom,' + rgb(bright) + ' 0%,' + rgb(acc) + ' 100%);color:' + rgb(dark) + ';font-weight:bold;'
                + 'font-family:"Motiva Sans",Arial,sans-serif;font-size:12px;text-transform:uppercase;letter-spacing:.6px;'
                + 'padding:0 14px;height:22px;line-height:22px;border-radius:2px;border:1px solid ' + rgb(mid) + ';'
                + 'text-decoration:none !important;box-shadow:0 0 8px ' + rgba(bright, .35) + ';}'
                + '#hotloader_hotload_btn:hover{filter:brightness(1.15);box-shadow:0 0 14px ' + rgba(bright, .6) + ';}'
                + '#hotloader_hotload_btn_fixed{position:fixed;top:10px;right:10px;z-index:999999;display:inline-block;cursor:pointer;'
                + 'background:linear-gradient(to bottom,' + rgb(bright) + ' 0%,' + rgb(acc) + ' 100%);color:' + rgb(dark) + ';font-weight:bold;'
                + 'font-family:"Motiva Sans",Arial,sans-serif;font-size:13px;text-transform:uppercase;letter-spacing:.6px;'
                + 'padding:0 18px;height:28px;line-height:28px;border-radius:3px;border:1px solid ' + rgb(mid) + ';'
                + 'text-decoration:none !important;box-shadow:0 0 16px ' + rgba(bright, .5) + ';}'
                + '#hotloader_hotload_btn_fixed:hover{filter:brightness(1.15);}'
                + '#hotloader_flash{position:fixed;top:46px;right:10px;z-index:999999;background:' + rgb(dark) + ';color:' + rgb(light) + ';'
                + 'padding:8px 12px;border-radius:3px;font:12px Arial;border:1px solid ' + rgb(acc) + ';}';
        } catch(e) {}
    };
    window.__tbhSetAccent(@@R@@, @@G@@, @@B@@);

    if (window.__tbhBoys) { return; }
    window.__tbhBoys = true;

    function report() {
        try { tbh.url(location.href, document.title || ''); } catch(e) {}
    }
    report();

    function wsid() {
        var m = (location.href || '').match(/[?&]id=(\d+)/);
        return m ? m[1] : null;
    }

    function cleanTitle() {
        return (document.title || '').replace(/^Steam\s*Workshop::?\s*/, '');
    }

    // a workshop page is a "map addon" when it is tagged Map / Maps / Map Pack
    function isMapPage() {
        try {
            var nodes = document.querySelectorAll('.workshopTags a, .workshopTag, a.tag, .workshopTags');
            for (var i = 0; i < nodes.length; i++) {
                var t = (nodes[i].textContent || '').trim().toLowerCase();
                if (t === 'map' || t === 'maps' || t === 'map pack') return true;
            }
            if (document.querySelector('a[href*="requiredtags%5B%5D=Map"]')) return true;
            if (document.querySelector('a[href*="requiredtags[]=Map"]')) return true;
        } catch(e) {}
        return false;
    }

    function flash(msg) {
        try {
            var d = document.createElement('div');
            d.id = 'hotloader_flash';
            d.textContent = msg;
            document.body.appendChild(d);
            setTimeout(function(){ if (d.parentNode) { d.parentNode.removeChild(d); } }, 2200);
        } catch(e) {}
    }

    function makeButton(fixed) {
        var a = document.createElement('a');
        a.id = fixed ? 'hotloader_hotload_btn_fixed' : 'hotloader_hotload_btn';
        a.href = 'javascript:void(0)';
        a.title = 'Download and mount this addon instantly with Hotloader';

        a.updateLabel = function() {
            var map = isMapPage();
            a._tbhMap = map;
            a.innerHTML = map
                ? '<span style="font-size:14px">&#128506;</span> LOAD MAP'
                : '<span style="font-size:14px">&#9889;</span> HOTLOAD';
            a.title = map
                ? 'Hotload this map addon and switch the server to it - everyone gets the map'
                : 'Download and mount this addon instantly with Hotloader';
        };
        a.updateLabel();

        a.addEventListener('click', function(ev) {
            ev.preventDefault();
            ev.stopPropagation();
            var id = wsid();
            if (!id) { flash('No addon id found on this page'); return; }
            var map = a._tbhMap || isMapPage();
            try { tbh.hotload(id, cleanTitle(), map); } catch(e) {}
            flash(map ? 'Load-map requested! Switch back to the game.' : 'Hotload requested! Switch back to the game.');
        });
        return a;
    }

    function placedInPage() {
        if (!wsid()) { return false; }
        if (document.getElementById('hotloader_hotload_btn')) { return true; }

        var sub = document.querySelector('.general_btn.subscribe') || document.querySelector('#SubscribeItemBtn');
        var host = null;

        if (sub && sub.parentNode) { host = sub.parentNode; }
        if (!host) {
            var rdb = document.querySelector('.rightDetailsBlock');
            if (rdb) { host = rdb; }
        }
        if (!host) {
            var wis = document.querySelector('.workshopItemSubscription');
            if (wis) { host = wis; }
        }

        if (host) {
            var wrap = document.createElement('div');
            wrap.style.margin = '6px 0 4px 0';
            wrap.appendChild(makeButton(false));
            host.appendChild(wrap);
            return true;
        }

        return false;
    }

    var ok = false;
    try { ok = placedInPage(); } catch(e) {}

    if (!ok) {
        setTimeout(function() {
            try {
                if (!document.getElementById('hotloader_hotload_btn') &&
                    !document.getElementById('hotloader_hotload_btn_fixed') &&
                    wsid() && document.body) {
                    document.body.appendChild(makeButton(true));
                }
            } catch(e) {}
        }, 2500);
    }

    // re-inject when Steam re-renders parts of the page (throttled)
    var last = 0;
    try {
        var mo = new MutationObserver(function() {
            var n = Date.now();
            if (n - last < 600) { return; }
            last = n;
            try { placedInPage(); } catch(e) {}
        });
        mo.observe(document.documentElement, { childList: true, subtree: true });
    } catch(e) {}

    // heartbeat + url change reporting back to Lua
    var lastHref = location.href;
    setInterval(function() {
        if (location.href !== lastHref) {
            lastHref = location.href;
            try { placedInPage(); } catch(e) {}
        }
        // keep the button label in sync (map tag vs regular addon)
        try {
            var b = document.getElementById('hotloader_hotload_btn') || document.getElementById('hotloader_hotload_btn_fixed');
            if (b && b.updateLabel) { b.updateLabel(); }
        } catch(e) {}
        report();
    }, 3000);
})();
]==]

    -- V.1.0.4: BROWSER_JS is a TEMPLATE - the current accent color gets
    -- baked in every time we inject it (OnDocumentReady + the 1.5s
    -- re-inject timer below keep open pages in sync with accent changes).
    function TBH.BrowserJS()
        local c = TBH.Colors.accent or Color(94, 168, 62)
        return (string.gsub(BROWSER_JS, "@@(%w+)@@", {
            R = tostring(c.r), G = tostring(c.g), B = tostring(c.b),
        }))
    end

    ------------------------------------------------------------------------------
    -- Home page (Workshop hub)
    ------------------------------------------------------------------------------

    local HOME_HTML = [==[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Hotloader Browser</title>
<style>
    body { background:@@BG@@; color:@@TEXT@@; font-family:"Motiva Sans",Arial,sans-serif; margin:0; }
    .hero { text-align:center; padding:38px 20px 22px; }
    .hero h1 { font-size:34px; margin:0 0 8px; color:@@BRIGHT@@; letter-spacing:3px; text-transform:uppercase; text-shadow:0 0 18px @@GLOW@@; }
    .hero p { color:@@TEXTDIM@@; margin:0; font-size:13px; }
    .search { text-align:center; margin:26px 0 8px; }
    .search input { width:440px; max-width:72%; padding:10px 14px; font-size:15px; background:@@PANEL@@; color:#fff; border:1px solid @@BORDER@@; border-radius:3px; outline:none; }
    .search input:focus { border-color:@@ACCENT@@; }
    .search button { padding:10px 18px; font-size:15px; background:linear-gradient(to bottom,@@BRIGHT@@,@@ACCENT@@); color:@@DARK@@; border:none; border-radius:3px; font-weight:bold; cursor:pointer; }
    .links { max-width:640px; margin:26px auto; }
    .links a { display:block; background:@@PANEL@@; border:1px solid @@LBORDER@@; border-radius:4px; padding:14px 16px; text-decoration:none; margin-bottom:10px; }
    .links a:hover { border-color:@@ACCENT@@; background:@@HOVER@@; }
    .links b { color:@@TEXT@@; font-size:14px; display:block; margin-bottom:4px; }
    .links span { color:#8b978b; font-size:12px; }
    .tip { max-width:640px; margin:20px auto 40px; background:@@TIPBG@@; border:1px dashed @@MID@@; border-radius:4px; padding:14px; font-size:13px; color:@@LIGHT@@; text-align:center; line-height:1.6; }
    .bolt { color:@@BRIGHT@@; }
    a { color:@@BRIGHT@@; }
</style>
</head>
<body>
<div class="hero">
    <h1>&#9889; Hotloader Browser</h1>
    <p>Browse the Steam Workshop without leaving the game.</p>
</div>
<div class="search">
    <form onsubmit="location.href='https://steamcommunity.com/workshop/browse/?appid=4000&searchtext='+encodeURIComponent(this.q.value); return false;">
        <input name="q" placeholder="Search the Garry's Mod Workshop...">
        <button type="submit">Search</button>
    </form>
</div>
<div id="hotloader_featured"></div>
<div class="links">
    <a href="https://steamcommunity.com/workshop/browse/?appid=4000"><b>&#128218; Browse the Workshop</b><span>Every Garry's Mod addon on Steam</span></a>
    <a href="https://steamcommunity.com/workshop/browse/?appid=4000&amp;browsesort=friendactivity&amp;section=readytouseitems"><b>&#129309; Friends Uploads</b><span>Addons published by your Steam friends - hotload them like any other</span></a>
    <a href="https://steamcommunity.com/workshop/browse/?appid=4000&amp;browsesort=mysubscriptions&amp;section=readytouseitems"><b>&#128276; My Subscriptions</b><span>Everything you're subscribed to - enable and hotload instantly</span></a>
    <a href="https://steamcommunity.com/workshop/browse/?appid=4000&amp;browsesort=totaluniquesubscribers&amp;section=readytouseitems"><b>&#128293; Most Popular</b><span>All-time most subscribed addons</span></a>
    <a href="https://steamcommunity.com/workshop/browse/?appid=4000&amp;section=collections"><b>&#128230; Collections</b><span>Curated addon packs - paste a collection link to hotload the WHOLE thing</span></a>
</div>
<div class="tip">
    <script>
    (function(){
        var pool = [
            { id: '160250458',  name: 'Wiremod',              desc: 'Wire everything to everything' },
            { id: '104548572',  name: 'Playable Piano',       desc: 'The classic piano' },
            { id: '104607228',  name: 'Fire Extinguisher',    desc: 'A fire extinguisher. It extinguishes.' },
            { id: '3787100606', name: 'Featured Favorite',    desc: 'Community pick - watch the HOTLOAD button appear' }
        ];
        var picks = [];
        var copy = pool.slice();
        for (var i = 0; i < 2 && copy.length > 0; i++) {
            picks.push(copy.splice(Math.floor(Math.random() * copy.length), 1)[0]);
        }
        var host = document.getElementById('hotloader_featured');
        if (host) {
            var html = '<div class="links">';
            for (var j = 0; j < picks.length; j++) {
                var a = picks[j];
                html += '<a href="https://steamcommunity.com/sharedfiles/filedetails/?id=' + a.id + '">'
                     + '<b>&#9889; ' + a.name + '</b><span>' + a.desc + '</span></a>';
            }
            html += '</div>';
            host.innerHTML = html;
        }
    })();
    </script>
    <span class="bolt">&#9889;</span> Open any addon page (<b>steamcommunity.com/sharedfiles/filedetails/?id=...</b>)<br>
    including your <b>friends' addons</b> and whole <b>collections</b> - they all get the <b>HOTLOAD</b> button.<br>
    It appears next to Subscribe, colored to match your accent. Click it and the addon<br>
    downloads + mounts on the whole server instantly. You can also paste a URL or a raw addon ID into the address bar.<br><br>
    <span style="color:#8b978b">Pages looking broken or empty? GMod's built-in web engine is ancient.<br>
    Install <a href="https://github.com/solsticegamestudios/GModPatchTool" target="_self">GModPatchTool</a> (optional) for a modern web engine so the browser looks way better.</span>
</div>
</body>
</html>
]==]

    -- V.1.0.4: HOME_HTML is a TEMPLATE too - the whole palette derives
    -- from the current accent color (see TBH.LoadTheme).
    function TBH.HomeHTML()
        local c = TBH.Colors.accent or Color(94, 168, 62)

        local function cl(v) return math.Clamp(math.floor(v), 0, 255) end
        local function hex(t) return string.format("#%02x%02x%02x", t[1], t[2], t[3]) end
        local function rgba(t, a) return string.format("rgba(%d,%d,%d,%s)", t[1], t[2], t[3], a) end

        local bright  = { cl(c.r * 1.45), cl(c.g * 1.45), cl(c.b * 1.45) }
        local mid     = { cl(c.r * 0.67), cl(c.g * 0.67), cl(c.b * 0.67) }
        local dark    = { cl(c.r * 0.10 + 4), cl(c.g * 0.10 + 4), cl(c.b * 0.10 + 4) }
        local light   = { cl(c.r + (255 - c.r) * 0.72), cl(c.g + (255 - c.g) * 0.72), cl(c.b + (255 - c.b) * 0.72) }
        local bg      = { cl(c.r * 0.11 + 7),  cl(c.g * 0.11 + 9),  cl(c.b * 0.11 + 7) }
        local panel   = { cl(c.r * 0.14 + 12), cl(c.g * 0.14 + 14), cl(c.b * 0.14 + 12) }
        local hover   = { cl(c.r * 0.17 + 14), cl(c.g * 0.17 + 16), cl(c.b * 0.17 + 14) }
        local tipbg   = { cl(c.r * 0.12 + 9),  cl(c.g * 0.12 + 11), cl(c.b * 0.12 + 9) }
        local border  = { cl(c.r * 0.22 + 20), cl(c.g * 0.22 + 22), cl(c.b * 0.22 + 20) }
        local lborder = { cl(c.r * 0.25 + 18), cl(c.g * 0.25 + 20), cl(c.b * 0.25 + 18) }

        local map = {
            ACCENT  = string.format("#%02x%02x%02x", cl(c.r), cl(c.g), cl(c.b)),
            BRIGHT  = hex(bright),
            MID     = hex(mid),
            DARK    = hex(dark),
            LIGHT   = hex(light),
            BG      = hex(bg),
            PANEL   = hex(panel),
            HOVER   = hex(hover),
            TIPBG   = hex(tipbg),
            BORDER  = hex(border),
            LBORDER = hex(lborder),
            GLOW    = rgba(bright, ".35"),
            TEXT    = "#e2eae2",
            TEXTDIM = "#94a094",
        }

        return (string.gsub(HOME_HTML, "@@(%w+)@@", map))
    end

    ------------------------------------------------------------------------------
    -- URL helpers
    ------------------------------------------------------------------------------

    function TBH.NormalizeURL(text)
        text = string.Trim(tostring(text or ""))
        if text == "" then return nil end

        -- raw workshop id
        if string_match(text, "^%d+$") then
            return "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. text
        end

        -- full url
        if string_match(text, "^https?://") then
            return text
        end

        -- workshop url without scheme
        if string_match(text, "^steamcommunity%.com") or string_match(text, "^www%.steamcommunity%.com") then
            return "https://" .. text
        end

        -- looks like a domain
        if string_match(text, "^[%w%-%_%.]+%.[%a]+$") or string_match(text, "^[%w%-%_%.]+%.[%a]+/") then
            return "https://" .. text
        end

        -- treat as workshop search terms
        local q = string_gsub(text, "[^%w%s%-%_%%%+%.]", "")
        q = string_gsub(q, "%s+", "+")

        if q == "" then return nil end

        return "https://steamcommunity.com/workshop/browse/?appid=4000&searchtext=" .. q
    end

    function TBH.CleanWorkshopTitle(title)
        if not isstring(title) then return nil end
        local cleaned = string_match(title, "^Steam%s*Workshop::?%s*(.+)$") or title
        cleaned = string_gsub(cleaned, "%s+$", "")
        cleaned = string_gsub(cleaned, "^%s+", "")
        if cleaned == "" then return nil end
        return string_sub(cleaned, 1, 100)
    end

    ------------------------------------------------------------------------------
    -- Browser view panel (toolbar + HTML + status bar, no window chrome)
    --
    -- Used in two places:
    --   * embedded inside the spawnmenu "Hotloader Browser" creation tab
    --   * wrapped inside the popup TBH.Browser DFrame (hotloader_browser command)
    ------------------------------------------------------------------------------

    local BrowserCount = 0

    local PANEL = {}

    function PANEL:Init()
        BrowserCount = BrowserCount + 1
        self.BrowserID = BrowserCount

        self.CurrentURL = ""
        self.CurrentTitle = ""

        -- V.1.0.4: registry so accent changes can re-theme every open
        -- browser (Workshop-page buttons + home page) live
        TBH.BrowserViews = TBH.BrowserViews or {}
        TBH.BrowserViews[self] = true

        ----------------------------------------------------------------
        -- Toolbar
        ----------------------------------------------------------------
        local bar = vgui.Create("DPanel", self)
        bar:Dock(TOP)
        bar:SetTall(36)
        bar:DockPadding(4, 5, 4, 5)
        bar.Paint = function(_, w, h)
            draw.RoundedBox(0, 0, 0, w, h, TBH.Colors.bgPanel)
        end

        local function ToolButton(parent, icon, tooltip, text)
            local btn = vgui.Create("DButton", parent)
            btn:SetImage("icon16/" .. icon .. ".png")
            btn:Dock(LEFT)
            btn:SetWide(34)
            btn:SetTooltip(tooltip)
            btn:SetText(text or "")
            btn:SetColor(TBH.Colors.text)
            btn.Paint = function(_, w, h)
                if _:IsHovered() then
                    draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
                end
            end
            return btn
        end

        local back = ToolButton(bar, "arrow_left", "Back")
        back.DoClick = function() self:JS("history.back()") end

        local fwd = ToolButton(bar, "arrow_right", "Forward")
        fwd.DoClick = function() self:JS("history.forward()") end

        local refresh = ToolButton(bar, "arrow_refresh", "Reload page")
        refresh.DoClick = function()
            if IsValid(self.HTML) then
                local ok = pcall(function() self.HTML:Refresh() end)
                if not ok then self:JS("location.reload()") end
            end
        end

        local home = ToolButton(bar, "house", "Home (Workshop hub)")
        home.DoClick = function() self:LoadHome() end

        local popout = ToolButton(bar, "application_put", "Open in a separate window (works while the spawnmenu is closed)")
        popout.DoClick = function() TBH.OpenBrowser(self.CurrentURL ~= "" and self.CurrentURL or nil) end

        -- thin divider between the navigation buttons and the address bar
        local function Divider(parent, dock)
            local d = vgui.Create("DPanel", parent)
            d:Dock(dock)
            d:SetWide(9)
            d.Paint = function(_, w, h)
                draw.RoundedBox(0, 4, 4, 1, h - 8, TBH.Colors.outline)
            end
            return d
        end

        Divider(bar, LEFT)

        local pinBtn = vgui.Create("DButton", bar)
        pinBtn:Dock(RIGHT)
        pinBtn:SetWide(70)
        pinBtn:DockMargin(4, 0, 0, 0)
        pinBtn:SetText("+ PIN")
        pinBtn:SetFont("TBH.Body")
        pinBtn:SetColor(TBH.Colors.text)
        pinBtn:SetTooltip("Save the addon on this page to your pinned list without hotloading it")
        pinBtn.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
            if _:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline) end
        end
        pinBtn.DoClick = function()
            local id = TBH.ExtractWSID(self.CurrentURL or "")
            if id then
                TBH.PinAddon(id, self.CurrentTitle)
            else
                TBH.NotifyLocally("Open an addon page first, then press + PIN", 3)
            end
        end

        local hotload = vgui.Create("DButton", bar)
        hotload:Dock(RIGHT)
        hotload:SetWide(120)
        hotload:SetText("HOTLOAD")
        hotload:SetTooltip("Hotload the addon currently open in this page")
        hotload:SetFont("Trebuchet18")
        hotload:SetColor(Color(14, 26, 12))
        hotload.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.accent)
            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.tag)
            end
        end
        hotload.DoClick = function() self:HotloadCurrentPage() end
        hotload:DockMargin(4, 0, 0, 0)

        self.URL = vgui.Create("DTextEntry", bar)
        self.URL:Dock(FILL)
        self.URL:DockMargin(6, 0, 6, 0)
        self.URL:SetPlaceholderText("Paste a Workshop URL / addon ID, or type search terms and press Enter...")
        self.URL.OnEnter = function(s)
            self:Navigate(s:GetText())
        end

        ----------------------------------------------------------------
        -- Quick links row (chips)
        ----------------------------------------------------------------
        local chips = vgui.Create("DPanel", self)
        chips:Dock(TOP)
        chips:SetTall(28)
        chips:DockPadding(4, 3, 4, 3)
        chips.Paint = function(_, w, h)
            draw.RoundedBox(0, 0, 0, w, h, TBH.Colors.bg)
            draw.RoundedBox(0, 0, h - 1, w, 1, TBH.Colors.outline)
        end

        local base = "https://steamcommunity.com/workshop/browse/?appid=4000&browsesort="
        local links = {
            { "Home", nil },
            { "Trending", base .. "trend" },
            { "Most popular", base .. "totaluniquesubscribers" },
            { "Newest", base .. "mostrecent" },
            { "Collections", "https://steamcommunity.com/workshop/browse/?appid=4000&section=collections" },
            { "Maps", base .. "trend&requiredtags%5B%5D=Map" },
            { "Dupes", base .. "trend&requiredtags%5B%5D=Dupe" },
        }

        for _, link in ipairs(links) do
            local chip = vgui.Create("DButton", chips)
            chip:Dock(LEFT)
            chip:DockMargin(0, 0, 4, 0)
            chip:SetText(link[1])
            chip:SetFont("TBH.Small")
            chip:SetColor(TBH.Colors.textdim)
            surface.SetFont("TBH.Small")
            chip:SetWide(surface.GetTextSize(link[1]) + 22)
            chip.Paint = function(_, w, h)
                draw.RoundedBox(h / 2, 0, 0, w, h, _:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bgPanel)
            end
            chip.DoClick = function()
                if link[2] then self:Navigate(link[2]) else self:LoadHome() end
            end
        end

        ----------------------------------------------------------------
        -- HTML view
        ----------------------------------------------------------------
        self.HTML = vgui.Create("DHTML", self)
        self.HTML:Dock(FILL)

        pcall(function()
            self.HTML:AddFunction("tbh", "url", function(url, title)
                self:OnPageURL(url, title)
            end)

            self.HTML:AddFunction("tbh", "hotload", function(id, title, isMap)
                self:OnHotloadID(id, title, isMap)
            end)
        end)

        -- HTML panel callbacks (inherited from the HTML panel class)
        self.HTML.OnDocumentReady = function(_, url)
            self:SetStatus("Page loaded: " .. tostring(url))
            self:JS(TBH.BrowserJS())
        end

        self.HTML.OnChangeAddressBar = function(_, url)
            if isstring(url) and string_match(url, "^https?://") then
                self.URL:SetText(url)
                self.CurrentURL = url
            end
        end

        self.HTML.OnChangeTitle = function(_, title)
            if isstring(title) and title ~= "" then
                self.CurrentTitle = title

                if isfunction(self.OnTitleChange) then
                    self:OnTitleChange(title)
                end
            end
        end

        self.HTML.OnFinishLoadingDocument = function(_, url)
            if isstring(url) then
                self:SetStatus("Ready - " .. url)
            end
        end

        ----------------------------------------------------------------
        -- Status bar
        ----------------------------------------------------------------
        local status = vgui.Create("DPanel", self)
        status:Dock(BOTTOM)
        status:SetTall(24)
        status.Paint = function(_, w, h)
            draw.RoundedBox(0, 0, 0, w, h, TBH.Colors.bgPanel)
            draw.RoundedBox(0, 0, 0, w, 1, TBH.Colors.outline)
        end

        self.StatusLabel = vgui.Create("DLabel", status)
        self.StatusLabel:Dock(FILL)
        self.StatusLabel:DockMargin(8, 0, 8, 0)
        self.StatusLabel:SetText("Ready")
        self.StatusLabel:SetColor(TBH.Colors.textdim)
        self.StatusLabel:SetFont("DermaDefault")

        self.WorkshopLabel = vgui.Create("DLabel", status)
        self.WorkshopLabel:Dock(RIGHT)
        self.WorkshopLabel:SetText("Hotloader")
        self.WorkshopLabel:SetColor(TBH.Colors.dim)
        self.WorkshopLabel:SizeToContents()
        self.WorkshopLabel:DockMargin(0, 0, 8, 0)

        ----------------------------------------------------------------
        -- Keep bindings + injection alive across page navigations
        ----------------------------------------------------------------
        timer.Create("TBH.Browser" .. self.BrowserID, 1.5, 0, function()
            if not IsValid(self) or not IsValid(self.HTML) then
                timer.Remove("TBH.Browser" .. self.BrowserID)
                return
            end

            pcall(function()
                self.HTML:AddFunction("tbh", "url", function(url, title)
                    self:OnPageURL(url, title)
                end)

                self.HTML:AddFunction("tbh", "hotload", function(id, title, isMap)
                    self:OnHotloadID(id, title, isMap)
                end)
            end)

            self.HTML:QueueJavascript(TBH.BrowserJS())
        end)

        self:LoadHome()
    end

    function PANEL:OnRemove()
        timer.Remove("TBH.Browser" .. self.BrowserID)
        if TBH.BrowserViews then TBH.BrowserViews[self] = nil end
    end

    ------------------------------------------------------------------
    -- V.1.0.5: DHTML keyboard focus - WHY YOU COULDN'T TYPE IN THE
    -- "Search the Garry's Mod Workshop" BOX (your report)
    --
    -- GMod's spawnmenu opens with KEYBOARD INPUT DISABLED on its root
    -- panel (spawnmenu.lua PANEL:Open() calls SetKeyboardInputEnabled
    -- (false)) - that's why your player still walks around with WASD
    -- while the Q menu is open. Keyboard input is only switched on when
    -- a TEXT ENTRY gains focus: DTextEntry fires the OnTextEntryGetFocus
    -- hook, the sandbox's listener calls g_SpawnMenu:StartKeyFocus(panel)
    -- and THAT enables keyboard input (and HangOpen) on the menu. That's
    -- why typing in the URL bar works.
    --
    -- The Workshop search box is an HTML <input> inside a DHTML panel -
    -- not a text entry. Clicking it never triggered the focus handshake,
    -- so every keystroke kept going to the game instead of the page:
    -- "i can't type anything in that tab".
    --
    -- THE FIX: when the user clicks into the web page we perform the
    -- exact handshake a DTextEntry does (this is the officially
    -- recommended pattern - garrysmod's own vgui/dtextentry.lua says:
    -- "If you make a control for the spawnmenu that requires keyboard
    -- input you should have these 3 functions in your panel"):
    --   * enable keyboard input on the DHTML itself + RequestFocus it
    --   * call StartKeyFocus on the spawnmenu panel - enables keyboard
    --     input on the menu root AND sets HangOpen, so releasing Q won't
    --     yank the menu away mid-sentence either
    --   * clicking outside the page (or hiding the tab/menu) does the
    --     reverse: EndKeyFocus + give the keyboard back to the game
    -- Works in the popup browser window too (there it just focuses the
    -- DHTML - StartKeyFocus is only needed inside the spawnmenu).
    ------------------------------------------------------------------

    function PANEL:AcquireHTMLFocus()
        if not IsValid(self.HTML) then return end
        self._htmlHasFocus = true

        pcall(function()
            self.HTML:SetKeyboardInputEnabled(true)
            self.HTML:RequestFocus()
        end)

        -- replicate DTextEntry's focus handshake with the spawnmenu -
        -- ONLY when this view actually lives inside the spawnmenu (the
        -- popup browser window already gets keyboard input via MakePopup)
        local sm = TBH.GetSpawnMenuPanel and TBH.GetSpawnMenuPanel(self)
        if IsValid(sm) and self.HTML:HasParent(sm) then
            pcall(function() sm:StartKeyFocus(self.HTML) end)
        end
    end

    function PANEL:ReleaseHTMLFocus()
        if not self._htmlHasFocus then return end
        self._htmlHasFocus = false

        if IsValid(self.HTML) then
            pcall(function()
                -- only kill it if the DHTML still actually holds focus -
                -- e.g. clicking the URL bar already moved it elsewhere
                if vgui.GetKeyboardFocus() == self.HTML then
                    self.HTML:KillFocus()
                end
            end)
        end

        local sm = TBH.GetSpawnMenuPanel and TBH.GetSpawnMenuPanel(self)
        if IsValid(sm) and IsValid(self.HTML) and self.HTML:HasParent(sm) then
            pcall(function()
                sm:EndKeyFocus(self.HTML)

                -- V.1.0.7 FIX (the "menu won't close via Q" bug): the focus
                -- handshake above ALSO armed the spawnmenu's HangOpen flag -
                -- that is how GMod keeps the menu open while you type, and
                -- GMod's own EndKeyFocus never clears it. Leaving it armed
                -- swallowed the next Q release (felt like the menu was
                -- permanently stuck until the first hotload reset things).
                -- Clear it here; if the browser tab is still the active tab
                -- the pin timer re-arms it within 0.1s, so this is always
                -- safe - it just guarantees no STALE swallow once the web
                -- page no longer holds the keyboard.
                sm:SetHangOpen(false)
            end)
        end
    end

    function PANEL:Think()
        if not IsValid(self.HTML) then return end

        -- the browser view got hidden (tab switched away / menu closed /
        -- popup closed): hand the keyboard back immediately
        if self._htmlHasFocus and not self:IsVisible() then
            self:ReleaseHTMLFocus()
            return
        end

        local mouseDown = input.IsMouseDown(MOUSE_LEFT)

        if mouseDown and self.HTML:IsHovered() then
            -- clicking INTO the web page: make sure the DHTML holds
            -- keyboard focus and run the spawnmenu handshake, so HTML
            -- <input> elements (the Workshop search box etc.) finally
            -- receive key events. Re-checks on every click into the page,
            -- so a focus steal by another panel self-heals.
            if vgui.GetKeyboardFocus() ~= self.HTML then
                self:AcquireHTMLFocus()
            end
        elseif self._htmlHasFocus and mouseDown and not self.HTML:IsHovered() then
            -- clicking somewhere OUTSIDE the web page: hand the keyboard
            -- back (so movement keys go to the game again)
            self:ReleaseHTMLFocus()
        end
    end

    ------------------------------------------------------------------
    -- V.1.0.4: re-theme this browser with the CURRENT accent color
    -- (called by TBH.ApplyBrowserTheme whenever the theme reloads)
    ------------------------------------------------------------------

    function PANEL:ApplyTheme()
        if not IsValid(self.HTML) then return end

        local c = TBH.Colors.accent or Color(94, 168, 62)
        self:JS(string.format("if(window.__tbhSetAccent){window.__tbhSetAccent(%d,%d,%d);}", c.r, c.g, c.b))

        -- the home page is generated from the accent - rebuild it if it's
        -- the page currently showing
        if self.CurrentURL == "" then
            self.HTML:SetHTML(TBH.HomeHTML())
        end
    end

    ------------------------------------------------------------------
    -- Navigation
    ------------------------------------------------------------------

    function PANEL:JS(code)
        if IsValid(self.HTML) then
            self.HTML:RunJavascript(code)
        end
    end

    function PANEL:SetStatus(text)
        if IsValid(self.StatusLabel) then
            self.StatusLabel:SetText(string_sub(tostring(text), 1, 120))
        end
    end

    function PANEL:LoadHome()
        self.CurrentURL = ""
        self:SetStatus("Home - Workshop hub")

        if isfunction(self.OnTitleChange) then
            self:OnTitleChange("Hotloader Browser")
        end

        if IsValid(self.HTML) then
            self.HTML:SetHTML(TBH.HomeHTML())
        end

        if IsValid(self.URL) then
            self.URL:SetText("")
        end
    end

    function PANEL:Navigate(text)
        local url = TBH.NormalizeURL(text)

        if not url then
            self:SetStatus("Only http/https pages can be opened here")
            return
        end

        if not string_match(url, "^https?://") then
            self:SetStatus("Only http/https pages can be opened here")
            return
        end

        self.CurrentURL = url
        self:SetStatus("Loading " .. url .. " ...")

        if IsValid(self.HTML) then
            self.HTML:OpenURL(url)
        end

        if IsValid(self.URL) then
            self.URL:SetText(url)
        end
    end

    ------------------------------------------------------------------
    -- JS callbacks
    ------------------------------------------------------------------

    function PANEL:OnPageURL(url, title)
        if isstring(url) and string_match(url, "^https?://") then
            self.CurrentURL = url
            self.URL:SetText(url)

            if isstring(title) and title ~= "" then
                self.CurrentTitle = title

                if isfunction(self.OnTitleChange) then
                    self:OnTitleChange(title)
                end
            end
        end
    end

    function PANEL:OnHotloadID(id, title, isMap)
        local wsid = TBH.ExtractWSID(id)

        if not wsid then
            TBH.NotifyLocally("Browser: could not find an addon id on that page", 2)
            return
        end

        local clean = TBH.CleanWorkshopTitle(title)
        TBH.RequestHotload(wsid, clean or "", isMap == true)
    end

    function PANEL:HotloadCurrentPage()
        local wsid = TBH.ExtractWSID(self.CurrentURL) or TBH.ExtractWSID(self.URL:GetText())

        if not wsid then
            TBH.NotifyLocally("Open a Workshop addon page first!", 2)
            return
        end

        local clean = TBH.CleanWorkshopTitle(self.CurrentTitle)
        TBH.RequestHotload(wsid, clean or "")
    end

    vgui.Register("TBH.BrowserPanel", PANEL, "EditablePanel")

    ------------------------------------------------------------------------------
    -- Popup browser window (wraps the browser view in a DFrame)
    ------------------------------------------------------------------------------

    local FRAME = {}

    function FRAME:Init()
        self:SetTitle("  Hotloader Browser")
        self:SetSize(math.min(ScrW() - 60, 1060), math.min(ScrH() - 60, 700))
        self:Center()
        self:SetSizable(true)
        self:SetMinWidth(620)
        self:SetMinHeight(400)
        self:MakePopup()

        self.View = vgui.Create("TBH.BrowserPanel", self)
        self.View:Dock(FILL)

        self.View.OnTitleChange = function(_, title)
            self:SetTitle("  " .. string_sub(title, 1, 60))
        end
    end

    function FRAME:Navigate(text)
        if IsValid(self.View) then
            self.View:Navigate(text)
        end
    end

    function FRAME:OnRemove()
        if TBH.BrowserPanel == self then
            TBH.BrowserPanel = nil
        end
    end

    vgui.Register("TBH.Browser", FRAME, "DFrame")

    ------------------------------------------------------------------------------
    -- Browser openers
    ------------------------------------------------------------------------------

    -- V.1.0.4: push the current accent color into every open browser
    -- (Workshop-page HOTLOAD buttons + home page). Called by the theme
    -- reload debounce (TBH.QueueThemeReload) and by hotloader_reload_theme.
    function TBH.ApplyBrowserTheme()
        for view in pairs(TBH.BrowserViews or {}) do
            if IsValid(view) then
                pcall(function() view:ApplyTheme() end)
            else
                TBH.BrowserViews[view] = nil
            end
        end
    end

    function TBH.OpenBrowser(url)
        if IsValid(TBH.BrowserPanel) then
            TBH.BrowserPanel:SetVisible(true)
            TBH.BrowserPanel:MoveToFront()

            if url then
                TBH.BrowserPanel:Navigate(url)
            end

            return TBH.BrowserPanel
        end

        local frame = vgui.Create("TBH.Browser")
        TBH.BrowserPanel = frame

        if url then
            frame:Navigate(url)
        end

        return frame
    end

    -- opens the popup browser from inside the spawnmenu (buttons, context
    -- menus): closes the spawnmenu first so the window is front and center
    function TBH.OpenBrowserFromMenu(url)
        -- the spawnmenu has the browser built into the Hotloader tab, use that
        if IsValid(TBH.HotloaderTab) then
            TBH.HotloaderTab:ShowBrowser(url)
            return TBH.HotloaderTab.Browser
        end

        gui.HideGameUI()

        local frame = TBH.OpenBrowser(url)

        if IsValid(frame) then
            frame:MoveToFront()
        end

        return frame
    end
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  SPAWNMENU UI + SETTINGS + COMMANDS + HINTS
--
--  * Q menu creation tab: "Hotloader"
--  * Utilities -> Hotloader -> Settings & Info
--  * Console commands, welcome hints, boot messages
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if CLIENT then
    ------------------------------------------------------------------------------
    -- Fonts
    ------------------------------------------------------------------------------

    surface.CreateFont("TBH.Hero", { font = "Roboto Bk", size = 34, weight = 900, extended = true })
    surface.CreateFont("TBH.Header", { font = "Roboto Bk", size = 20, weight = 900, extended = true })
    surface.CreateFont("TBH.Body", { font = "Roboto", size = 15, weight = 500, extended = true })
    surface.CreateFont("TBH.Small", { font = "Roboto", size = 13, weight = 400, extended = true })
    surface.CreateFont("TBH.Mono", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("TBH.Status", { font = "Roboto", size = 14, weight = 400, extended = true })

    ------------------------------------------------------------------------------
    -- Server info handshake (module status, permission level, ...)
    ------------------------------------------------------------------------------

    TBH.ServerInfo = nil

    timer.Simple(5, function()
        TBH.Net:Start("hello")
        net.SendToServer()
    end)

    TBH.Net:Receive("info", function()
        TBH.ServerInfo = {
            permission = net.ReadUInt(8),
            requirements = net.ReadBool(),
            module = net.ReadBool(),
            mounted = net.ReadUInt(16),
            version = net.ReadString(),
            batchDelay = net.ReadUInt(8),
            -- V.1.0.6: FULL-unload module status (server-side gmaunmount)
            unmount = net.ReadBool(),
        }
        hook.Run("TBH.ClientListChanged")
    end)

    ------------------------------------------------------------------------------
    -- The main menu page (used in the spawnmenu tab AND the hotloader_menu window)
    ------------------------------------------------------------------------------

    local PageCount = 0

    local PANEL = {}

    function PANEL:Init()
        PageCount = PageCount + 1
        self.PageID = PageCount

        -- NOTE: this panel is based on EditablePanel (a raw panel, NOT a
        -- DPanel) - it has no SetPaintBackground/SetPaintBorder methods, and
        -- raw panels paint no background by default, so nothing to disable.

        self.RefreshHook = "TBH.MenuPage" .. self.PageID

        -- v1.1.7: optional background image (Utilities -> Settings & Info).
        -- Painted FIRST so every child panel sits on top of it. The image is
        -- cached on TBH.Theme.bgMaterial (reloaded by TBH.LoadTheme when the
        -- path convar changes). Transparency is read live so the slider
        -- works without re-painting the material.
        self.Paint = function(_, w, h)
            -- solid dark backdrop first (in case the image has alpha or is
            -- stretched smaller than the panel)
            draw.RoundedBox(0, 0, 0, w, h, TBH.Colors.bg)

            if TBH.Theme and TBH.Theme.bgMaterial then
                local alpha = 255
                if TBH.CVarThemeAlpha then
                    alpha = math.Clamp(TBH.CVarThemeAlpha:GetInt() or 100, 0, 255)
                end

                surface.SetMaterial(TBH.Theme.bgMaterial)
                surface.SetDrawColor(255, 255, 255, alpha)

                -- stretch to fill (keep aspect ratio off - this is a
                -- desktop wallpaper style, users want it filling the panel)
                surface.DrawTexturedRect(0, 0, w, h)
            end
        end

        -- DEBOUNCED list refresh: a 30-addon collection fires dozens of
        -- list-changed events (one per addon + one per thumbnail arrival).
        -- Rebuilding every card row on each event = thousands of vgui
        -- panels created/destroyed in quick succession = crash city.
        -- One shared 0.25s debounce = a handful of rebuilds, and the LAST
        -- state is always what you see.
        hook.Add("TBH.ClientListChanged", self.RefreshHook, function()
            if not IsValid(self) then return end

            timer.Create(self.RefreshHook .. ".Refresh", 0.25, 1, function()
                if IsValid(self) then self:RefreshList() end
            end)
        end)

        hook.Add("TBH.StatusLogged", self.RefreshHook, function()
            if IsValid(self) then self:RefreshStatus() end
        end)

        ----------------------------------------------------------------
        -- Hero header
        ----------------------------------------------------------------
        local hero = vgui.Create("DPanel", self)
        hero:Dock(TOP)
        hero:SetTall(84)
        hero:DockMargin(0, 0, 0, 8)
        hero.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)

            -- accent corner
            draw.RoundedBoxEx(6, 0, 0, 6, h, TBH.Colors.accent, true, false, true, false)

            draw.SimpleText("HOTLOADER", "TBH.Hero", 22, 16, TBH.Colors.tag, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Hotload any Workshop addon mid-game. No restart. No reboot.", "TBH.Body", 22, 50, TBH.Colors.textdim)
            draw.SimpleText("v" .. TBH.Version, "TBH.Small", w - 14, 12, TBH.Colors.dim, TEXT_ALIGN_RIGHT)
        end

        ----------------------------------------------------------------
        -- Hotload input row
        ----------------------------------------------------------------
        local row = vgui.Create("DPanel", self)
        row:Dock(TOP)
        row:SetTall(42)
        row:DockMargin(0, 0, 0, 8)
        row.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
        end

        self.Input = vgui.Create("DTextEntry", row)
        self.Input:Dock(FILL)
        self.Input:DockMargin(8, 8, 8, 8)
        self.Input:SetPlaceholderText("Paste a Workshop URL or addon ID - HOTLOAD loads it now, + PIN just saves it to your list")
        self.Input:SetFont("TBH.Body")
        self.Input.OnEnter = function(s)
            self:SubmitHotload()
        end

        local go = vgui.Create("DButton", row)
        go:Dock(RIGHT)
        go:SetWide(140)
        go:DockMargin(0, 8, 8, 8)
        go:SetText("HOTLOAD")
        go:SetFont("TBH.Header")
        go:SetColor(Color(14, 26, 12))
        go.DoClick = function() self:SubmitHotload() end
        go.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.accent)
            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.tag)
            end
        end

        local pinBtn = vgui.Create("DButton", row)
        local browserBtn = vgui.Create("DButton", row)
        browserBtn:Dock(RIGHT)
        browserBtn:SetWide(130)
        browserBtn:DockMargin(0, 8, 0, 8)
        browserBtn:SetText("  WEB BROWSER")
        browserBtn:SetImage("icon16/world.png")
        browserBtn:SetFont("TBH.Body")
        browserBtn:SetColor(TBH.Colors.text)
        browserBtn:SetTooltip("Open the built-in browser - visit any addon page for a HOTLOAD button")
        browserBtn.DoClick = function() TBH.OpenBrowserFromMenu() end
        browserBtn.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline)
            end
        end

        pinBtn:Dock(RIGHT)
        pinBtn:SetWide(78)
        pinBtn:DockMargin(0, 8, 6, 8)
        pinBtn:SetText("+ PIN")
        pinBtn:SetFont("TBH.Body")
        pinBtn:SetColor(TBH.Colors.text)
        pinBtn:SetTooltip("Save this addon to your pinned list WITHOUT hotloading it. The list survives restarts, hotload it from there any time.")
        pinBtn.DoClick = function() self:SubmitPin() end
        pinBtn.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline)
            end
        end

        ----------------------------------------------------------------
        -- Auto-hotload checkboxes (each says exactly what it does -
        -- hover a checkbox for the full explanation)
        ----------------------------------------------------------------
        local checks = vgui.Create("DPanel", self)
        checks:Dock(TOP)
        checks:SetTall(58)
        checks:DockMargin(0, 0, 0, 8)
        checks.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
        end

        local function StyleCheckbox(cb, text, convar, tooltip)
            cb:Dock(TOP)
            cb:SetTall(22)
            cb:DockMargin(12, 6, 12, 0)
            cb:SetText(text)
            cb:SetConVar(convar)
            cb:SetTooltip(tooltip)

            -- label styling (different Derma versions expose these differently)
            pcall(function() cb:SetFont("TBH.Small") end)
            pcall(function() cb:SetTextColor(TBH.Colors.text) end)

            if cb.Label then
                pcall(function() cb.Label:SetFont("TBH.Small") end)
                pcall(function() cb.Label:SetTextColor(TBH.Colors.text) end)
            end
        end

        local sub = vgui.Create("DCheckBoxLabel", checks)
        StyleCheckbox(sub, "Auto-Hotload on Subscribe", "hotloader_autosubscribe",
            "When ON: subscribing to a NEW Workshop addon while in-game (Steam overlay or the browser) automatically requests a hotload. The addon downloads first, then the request fires. The server's cooldown and limits still apply.")

        local ena = vgui.Create("DCheckBoxLabel", checks)
        StyleCheckbox(ena, "Enable Addons", "hotloader_enableaddons",
            "When ON: ticking an addon back ON in the main menu 'Addons' list (or the in-game Addons menu) automatically hotloads it. The addon is already downloaded on your PC, so this is nearly instant - it just mounts it and syncs it to everyone. The server's cooldown and limits still apply.")

        ----------------------------------------------------------------
        -- Layout helper (used by every fixed section below)
        ----------------------------------------------------------------
        local function TopPanel(parent, tall)
            local p = vgui.Create("DPanel", parent)
            p:Dock(TOP)
            p:SetTall(tall)
            -- no skin background: the default DPanel paint is light grey and showed
            -- up as a bright bar on the dark theme (the empty pinned strip)
            p.Paint = function() end
            return p
        end

        -- one look for every section title: accent bar + title + dim hint on the right
        local function SectionHeader(title, hint)
            local hdr = TopPanel(self, 28)
            hdr:DockMargin(0, 8, 0, 2)
            hdr.Paint = function(_, w, h)
                draw.RoundedBox(2, 0, 6, 3, h - 10, TBH.Colors.accent)
                draw.SimpleText(title, "TBH.Body", 12, h / 2 - 1, TBH.Colors.tag, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if hint then
                    draw.SimpleText(hint, "TBH.Small", w - 8, h / 2, TBH.Colors.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
            return hdr
        end

        ----------------------------------------------------------------
        -- V.1.0.6: PINNED ADDONS (your request - "save addons so you can
        -- hotload quickly")
        --
        -- Saved per-player in data/hotloader_favorites.json - survives
        -- restarts. Shown as its own scroll (max ~3 rows visible, scrolls
        -- for more) between the checkboxes and the activity feed.
        ----------------------------------------------------------------
        SectionHeader("PINNED ADDONS", "saved addons - they survive restarts, hit HOTLOAD whenever you want one")

        local pinHeaderBtns = TopPanel(self, 26)

        self.PinScroll = vgui.Create("DScrollPanel", self)
        self.PinScroll:Dock(TOP)
        self.PinScroll:SetTall(0) -- sized dynamically by RefreshPins

        self.PinPanel = TopPanel(self.PinScroll, 0)
        self.PinPanel.Paint = function() end

        local pinAll = vgui.Create("DButton", pinHeaderBtns)
        pinAll:Dock(FILL)
        pinAll:DockMargin(0, 0, 0, 2)
        pinAll:SetText("")
        pinAll:SetTooltip("Hotload EVERY pinned addon at once (one batch - permission + cooldown apply once). The pins survive restarts, this is the one-click 'give me my addons back' button.")
        pinAll.Paint = function(_, w, h)
            if w < 10 then return end

            local pins = TBH.Client.Favorites or {}
            local n = 0
            for _ in pairs(pins) do n = n + 1 end

            if n == 0 then
                draw.SimpleText("Nothing pinned yet. Paste a link above and press + PIN, or use the star on a row below.", "TBH.Small", 10, 4, TBH.Colors.textdim)
                return
            end

            local label = "HOTLOAD ALL PINNED (" .. n .. ")"
            if n > 15 then label = "HOTLOAD PINNED (first 15 of " .. n .. ")" end

            draw.RoundedBox(4, 0, 0, math.min(w, 210), h - 2, TBH.Colors.accent)

            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, math.min(w, 210), h - 2, TBH.Colors.tag)
            end

            draw.SimpleText(label, "TBH.Small", math.min(w, 210) / 2, (h - 2) / 2, Color(14, 26, 12), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("saved to data/hotloader_favorites.json - yours forever, on any server (hotloader_pins lists them)", "TBH.Small", 222, (h - 2) / 2, TBH.Colors.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        pinAll.DoClick = function() TBH.HotloadAllFavorites() end

        ----------------------------------------------------------------
        -- Layout
        --
        -- FIXED at the top: hero / input row / checkboxes / pinned addons /
        -- activity feed.
        -- FILL below: the session list scroll. The list has its OWN
        -- DScrollPanel, so as soon as you hotload enough addons that the
        -- cards no longer fit, a scrollbar appears on the list itself.
        -- (All children everywhere are docked TOP - bottom-docking inside a
        -- scroll canvas breaks the scroll extent.)
        ----------------------------------------------------------------

        ----------------------------------------------------------------
        -- Status feed (fixed)
        ----------------------------------------------------------------
        SectionHeader("ACTIVITY", "what the hotloader is doing right now")

        self.StatusPanel = TopPanel(self, 80)
        self.StatusPanel:DockMargin(0, 0, 0, 8)
        self.StatusPanel.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
            self:PaintStatus(w, h)
        end

        ----------------------------------------------------------------
        -- Session list
        ----------------------------------------------------------------
        SectionHeader("YOUR ADDONS THIS SESSION", "everything you hotload, enable or request shows up here")

        -- the session list scroll: scrollbar appears automatically once
        -- the addon cards outgrow the visible area (2+ big cards, etc.)
        self.ListScroll = vgui.Create("DScrollPanel", self)
        self.ListScroll:Dock(FILL)

        self.ListPanel = TopPanel(self.ListScroll, 10)
        self.ListPanel.Paint = function() end

        ----------------------------------------------------------------
        -- Footer
        ----------------------------------------------------------------
        local footer = TopPanel(self.ListScroll, 52)
        footer:DockMargin(0, 8, 0, 0)
        footer.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)

            -- counted from our own list. the server's number is only sent once
            -- at join, so it stayed at 0 after hotloading things
            local n = 0
            for _, m in pairs(TBH.Client.Mounted or {}) do
                if istable(m) and not m.unloaded then n = n + 1 end
            end
            draw.SimpleText(n .. " addon(s) hotloaded this session", "TBH.Small", 12, 8, TBH.Colors.textdim)

            draw.SimpleText("Arch. inspired by Midgame Workshop Hotloader (Xalalau) - rewritten from scratch", "TBH.Small", 12, h - 20, TBH.Colors.dim)
            draw.SimpleText("hotloader_browser | hotloader_hotload <id> | hotloader_resync | hotloader_pins", "TBH.Small", w - 12, 8, TBH.Colors.dim, TEXT_ALIGN_RIGHT)
        end

        self:RefreshStatus()
        self:RefreshList()
    end

    function PANEL:OnRemove()
        hook.Remove("TBH.ClientListChanged", self.RefreshHook)
        hook.Remove("TBH.StatusLogged", self.RefreshHook)
        timer.Remove(self.RefreshHook .. ".Refresh")
    end

    function PANEL:SubmitPin()
        if TBH.PinAddon(self.Input:GetText()) then
            self.Input:SetText("")
        end
    end

    function PANEL:SubmitHotload()
        local text = self.Input:GetText()
        TBH.RequestHotload(text, "")

        if TBH.ExtractWSID(text) then
            self.Input:SetText("")
        end
    end

    ------------------------------------------------------------------
    -- Status feed painting
    ------------------------------------------------------------------

    function PANEL:PaintStatus(w, h)
        local log = TBH.StatusLog or {}
        local shown = math.min(#log, 5)
        if shown == 0 then
            draw.SimpleText("Nothing yet - paste an addon URL above, or open the Hotloader Browser and go hunting.", "TBH.Status", 12, h / 2 - 8, TBH.Colors.textdim)
            return
        end

        local y = 8
        for i = #log - shown + 1, #log do
            local entry = log[i]
            local color = TBH.Colors.text

            if entry.level == 1 then color = TBH.Colors.ok end
            if entry.level == 2 then color = TBH.Colors.error end
            if entry.level == 3 then color = TBH.Colors.warn end

            local msg = entry.msg or ""
            if #msg > 90 then msg = string_sub(msg, 1, 90) .. "..." end

            draw.SimpleText("> " .. msg, "TBH.Status", 12, y, color)
            y = y + 17
        end
    end

    function PANEL:RefreshStatus()
        -- the paint function reads TBH.StatusLog live; just force repaint
        if IsValid(self.StatusPanel) then
            self.StatusPanel:InvalidateLayout(true)
        end
    end

    ------------------------------------------------------------------
    -- Session list
    ------------------------------------------------------------------

    function PANEL:RefreshList()
        if not IsValid(self.ListPanel) then return end

        -- V.1.0.6: pins refresh with the list (pin toggles fire
        -- TBH.ClientListChanged, and mount state changes affect the pins'
        -- status text)
        self:RefreshPins()

        self.ListPanel:Clear()

        local entries = {}

        for wsid, data in pairs(TBH.Client.Known or {}) do
            entries[#entries + 1] = {
                wsid = wsid,
                title = data.title or wsid,
                time = data.time or 0,
            }
        end

        table.sort(entries, function(a, b) return (a.time or 0) > (b.time or 0) end)

        if #entries == 0 then
            local empty = vgui.Create("DPanel", self.ListPanel)
            empty:Dock(TOP)
            empty:SetTall(72)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                draw.SimpleText("No addons hotloaded yet.", "TBH.Body", w / 2, 14, TBH.Colors.textdim, TEXT_ALIGN_CENTER)
                draw.SimpleText("Be the first. Paste a URL above or raid the Workshop with the browser.", "TBH.Small", w / 2, 36, TBH.Colors.dim, TEXT_ALIGN_CENTER)
            end
            self.ListPanel:SetTall(56)
            return
        end

        local height = 0
        local maxRows = 12

        for i = 1, math.min(#entries, maxRows) do
            local entry = entries[i]
            local row = self:CreateAddonRow(entry, self.ListPanel)
            row:Dock(TOP)
            height = height + row:GetTall() + 4
        end

        if #entries > maxRows then
            height = height + 24
            local more = vgui.Create("DPanel", self.ListPanel)
            more:Dock(TOP)
            more:SetTall(20)
            more.Paint = function(_, w, h)
                draw.SimpleText("...and " .. (#entries - maxRows) .. " more (hotloader_list prints everything)", "TBH.Small", 10, 2, TBH.Colors.dim)
            end
        end

        self.ListPanel:SetTall(math.max(height, 10))
    end

    ------------------------------------------------------------------
    -- V.1.0.6: PINNED rows ("favorites" - saved across restarts)
    --
    -- Compact rows (52px) with a one-click HOTLOAD button; unpin with
    -- the X. The whole list persists in data/hotloader_favorites.json,
    -- so a fresh session starts with every pin right here.
    ------------------------------------------------------------------

    function PANEL:CreatePinRow(pin, parent)
        local row = vgui.Create("DPanel", parent)
        row:SetTall(68)
        row.wsid = pin.wsid
        row.title = pin.title or pin.wsid

        local mounted = TBH.Client.Mounted and TBH.Client.Mounted[pin.wsid]
        local isMounted = istable(mounted) and not mounted.unloaded

        row.Paint = function(selfRow, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)

            if selfRow:IsHovered() then
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel2)
            end

            local title = selfRow.title or selfRow.wsid
            if #title > 50 then title = string_sub(title, 1, 50) .. "..." end

            draw.SimpleText(title, "TBH.Body", 116, 12, TBH.Colors.text)

            if pin.map or (istable(pin.maps) and #pin.maps > 0) then
                surface.SetFont("TBH.Body")
                local tw = surface.GetTextSize(title)
                draw.RoundedBox(8, 116 + tw + 8, 13, 34, 16, TBH.Colors.accent)
                draw.SimpleText("MAP", "TBH.Small", 116 + tw + 25, 21, Color(14, 26, 12), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            local sub = "wsid " .. selfRow.wsid
            if isstring(pin.author) and pin.author ~= "" then
                sub = "By " .. pin.author .. "  -  " .. sub
            end

            draw.SimpleText(sub, "TBH.Small", 116, 36, TBH.Colors.textdim)

            -- session status on the right, next to the buttons
            local stateText, stateColor = "saved - not mounted yet", TBH.Colors.textdim

            if isMounted then
                stateText = "mounted this session"
                stateColor = TBH.Colors.ok
            elseif istable(mounted) and mounted.unloaded then
                stateText = "unloaded"
                stateColor = TBH.Colors.warn
            end

            -- the HOTLOAD + UNPIN buttons take ~176px on the right, keep the text clear of them
            draw.SimpleText(stateText, "TBH.Small", w - 184, h / 2, stateColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        -- preview image (same cached material the session rows use)
        TBH.FetchAddonMeta(pin.wsid)

        local thumb = vgui.Create("DPanel", row)
        thumb:Dock(LEFT)
        thumb:SetWide(96)
        thumb:DockMargin(8, 8, 0, 8)
        thumb.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)

            local mat = TBH.GetAddonImage(pin.wsid)
            if mat then
                surface.SetMaterial(mat)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(0, 0, w, h)
            else
                draw.SimpleText("no preview", "TBH.Small", w / 2, h / 2, TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        local hot = vgui.Create("DButton", row)
        hot:Dock(RIGHT)
        hot:SetWide(96)
        hot:DockMargin(0, 8, 8, 8)
        local isMapPin = pin.map or (istable(pin.maps) and #pin.maps > 0)
        hot:SetText(isMapPin and "LOAD MAP" or (isMounted and "AGAIN" or "HOTLOAD"))
        hot:SetFont("TBH.Small")
        hot:SetColor(Color(14, 26, 12))
        hot:SetTooltip(isMapPin and "Hotload this map addon (if needed) and switch the server to the map" or "Hotload this pinned addon right now")
        hot.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.accent)
            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.tag)
            end
        end
        hot.DoClick = function()
            if isMapPin then
                TBH.LoadMapForAddon(row.wsid, row.title)
            else
                TBH.RequestHotload(row.wsid, row.title)
            end
        end

        local unpin = vgui.Create("DButton", row)
        unpin:Dock(RIGHT)
        unpin:SetWide(64)
        unpin:DockMargin(0, 8, 0, 8)
        unpin:SetText("UNPIN")
        unpin:SetFont("TBH.Small")
        unpin:SetColor(TBH.Colors.textdim)
        unpin:SetTooltip("Remove this addon from your pinned favorites (the addon itself is untouched)")
        unpin.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
            if _:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline)
            end
        end
        unpin.DoClick = function()
            TBH.ToggleFavorite(row.wsid)
        end

        row.OnMousePressed = function(selfRow, code)
            if code == MOUSE_RIGHT then
                local menu = DermaMenu()

                menu:AddOption("Show Content In Addon", function()
                    TBH.FS.ShowContentByWSID(selfRow.wsid, selfRow.title)
                end):SetIcon("icon16/folder_explore.png")

                menu:AddOption("Copy Workshop ID", function()
                    SetClipboardText(selfRow.wsid)
                    TBH.NotifyLocally("Workshop ID copied", 0)
                end):SetIcon("icon16/page_copy.png")

                menu:AddOption("Open page in Hotloader Browser", function()
                    TBH.OpenBrowserFromMenu(TBH.WorkshopURL(selfRow.wsid))
                end):SetIcon("icon16/world.png")

                menu:AddOption(isMapPin and "Hotload only (don't switch map)" or "Hotload now", function()
                    TBH.RequestHotload(selfRow.wsid, selfRow.title)
                end):SetIcon("icon16/lightning.png")

                menu:AddSpacer()

                menu:AddOption("Unpin", function()
                    TBH.ToggleFavorite(selfRow.wsid)
                end):SetIcon("icon16/delete.png")

                menu:Open()
            end
        end

        row:SetTooltip("Your saved favorite - right click for options")

        return row
    end

    function PANEL:RefreshPins()
        if not IsValid(self.PinPanel) or not IsValid(self.PinScroll) then return end

        self.PinPanel:Clear()

        local pins = TBH.GetFavorites and TBH.GetFavorites() or {}
        local shown = math.min(#pins, 20)

        if shown == 0 then
            self.PinPanel:SetTall(2)
            self.PinScroll:SetTall(2)
            self.PinPanel:SetVisible(false)
            self.PinScroll:SetVisible(false)
            return
        end

        self.PinPanel:SetVisible(true)
        self.PinScroll:SetVisible(true)

        local height = 2

        for i = 1, shown do
            local pinRow = self:CreatePinRow(pins[i], self.PinPanel)
            pinRow:Dock(TOP)
            height = height + pinRow:GetTall() + 4
        end

        if #pins > shown then
            height = height + 20

            local more = vgui.Create("DPanel", self.PinPanel)
            more:Dock(TOP)
            more:SetTall(18)
            more.Paint = function(_, w, h)
                draw.SimpleText("...and " .. (#pins - shown) .. " more pinned (hotloader_pins prints everything)", "TBH.Small", 10, 0, TBH.Colors.dim)
            end
        end

        self.PinPanel:SetTall(height)

        -- show ~3 rows, scroll for more
        self.PinScroll:SetTall(math.Clamp(height, 10, 3 * 72 + 12))
    end

    function PANEL:CreateAddonRow(entry, parent)
        local row = vgui.Create("DPanel", parent)
        row:SetTall(86)
        row.wsid = entry.wsid
        row.title = entry.title
        row.RightPad = 12

        local meta = TBH.Client.Meta and TBH.Client.Meta[entry.wsid]
        local displayTitle = (meta and meta.title) or entry.title or entry.wsid
        row.title = displayTitle

        local mounted = TBH.Client.Mounted and TBH.Client.Mounted[entry.wsid]
        local maps = (istable(mounted) and istable(mounted.maps) and #mounted.maps > 0 and mounted.maps)
            or (istable(entry.maps) and #entry.maps > 0 and entry.maps)
            or nil

        local function OpenUnloadDialogFromRow(selfRow)
            Derma_Query(
                "Unload \"" .. selfRow.title .. "\"?\n\n" ..
                "Unload: removes its hooks, timers, tools and spawnmenu entries (NPCs, weapons, entities...). Its files stay mounted." .. "\n\n" ..
                "FULL Unload: the same, and its files are unmounted too (needs the gmaunmount module).",
                "Hotloader",
                "Unload", function()
                    TBH.RequestUnload(selfRow.wsid, false)
                end,
                "Unload + remove its entities", function()
                    TBH.RequestUnload(selfRow.wsid, true)
                end,
                "FULL Unload", function()
                    TBH.RequestFullUnload(selfRow.wsid, false)
                end,
                "Cancel", function() end
            )
        end

        ----------------------------------------------------------------
        -- Thumbnail (workshop preview image, downloaded + cached)
        -- v1.1.7: paint-time image lookup - the thumbnail appears the
        -- moment the image arrives, NO row rebuild needed. The IMaterial
        -- is cached in TBH.Client.Meta[wsid].imageMaterial so we never
        -- call Material() twice for the same wsid.
        ----------------------------------------------------------------
        local thumb = vgui.Create("DPanel", row)
        thumb:Dock(LEFT)
        thumb:SetWide(124)
        thumb:DockMargin(8, 8, 0, 8)

        thumb.Paint = function(_, w, h)
            -- background tile
            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
            draw.RoundedBoxEx(4, 0, 0, 4, h, TBH.Colors.dim, true, false, true, false)

            -- v1.1.7: PAINT-TIME material lookup - re-fetches the meta
            -- entry every paint so when the async image download finishes
            -- (possibly long after this row was built), we'll pick up the
            -- material THIS frame and paint it. GetAddonImage() is cheap
            -- (it returns a cached IMaterial on the meta table).
            local mat = TBH.GetAddonImage(entry.wsid)

            if mat then
                -- V.1.0.6: STRETCH TO FILL (your request) - the preview now
                -- fills the whole thumbnail tile instead of letterboxing
                -- inside it. Workshop previews are 512x512 (or 16:9), the
                -- tile is 124x70, so keeping the aspect ratio left black
                -- bars on every row.
                surface.SetMaterial(mat)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(0, 0, w, h)
            else
                -- placeholder (still loading, OR permanently failed)
                local meta = TBH.Client.Meta and TBH.Client.Meta[entry.wsid]
                local sub = "preview loading..."

                if meta and (meta.imageFailed or meta.failed) then
                    sub = "no preview available"
                elseif meta and meta.fetched and not meta.imageFile and not meta.preview_url then
                    -- V.1.0.5: fetched, finished, but nothing usable came
                    -- back (old persisted failures) - don't pretend it's
                    -- still loading
                    sub = "no preview available"
                end

                draw.SimpleText(string_sub(displayTitle, 1, 14), "TBH.Small", w / 2, h / 2 - 8, TBH.Colors.textdim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(sub, "TBH.Small", w / 2, h / 2 + 10, TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        -- (removed the old static DImage child - paint handles it now)

        ----------------------------------------------------------------
        -- Buttons
        ----------------------------------------------------------------
        if maps and not (istable(mounted) and mounted.unloaded) then
            local mapBtn = vgui.Create("DButton", row)
            mapBtn:Dock(RIGHT)
            mapBtn:SetWide(100)
            mapBtn:DockMargin(0, 8, 8, 8)
            mapBtn:SetText(#maps == 1 and "LOAD MAP" or "MAPS (" .. #maps .. ")")
            mapBtn:SetFont("TBH.Small")
            mapBtn:SetColor(Color(14, 26, 12))
            mapBtn:SetTooltip(#maps == 1
                and ("Switch the server to the map \"" .. maps[1] .. "\" - everyone has it!")
                or "Pick a map to switch the server to")
            mapBtn.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.accent)
                if _:IsHovered() then
                    draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.tag)
                end
            end
            mapBtn.DoClick = function()
                if #maps == 1 then
                    TBH.RequestLoadMap(maps[1])
                else
                    local menu = DermaMenu()
                    menu:AddSpacer()

                    for i = 1, math.min(#maps, 20) do
                        menu:AddOption(maps[i], function()
                            TBH.RequestLoadMap(maps[i])
                        end):SetIcon("icon16/map.png")
                    end

                    menu:Open()
                end
            end

            row.RightPad = row.RightPad + 108
        end
        ----------------------------------------------------------------
        -- V.1.0.6: PIN button (star) - toggles this addon in your saved
        -- favorites. Pinned addons survive restarts in
        -- data/hotloader_favorites.json and get their own PINNED section
        -- with one-click hotload + HOTLOAD ALL PINNED.
        ----------------------------------------------------------------
        do
            local pinBtn = vgui.Create("DButton", row)
            pinBtn:Dock(RIGHT)
            pinBtn:SetWide(38)
            pinBtn:DockMargin(0, 8, 6, 8)
            pinBtn:SetText("")
            pinBtn:SetTooltip("Pin this addon to your favorites (survives restarts - the PINNED section above gives one-click hotload)")
            pinBtn.Paint = function(_, w, h)
                local pinned = TBH.IsFavorite(entry.wsid)

                draw.RoundedBox(4, 0, 0, w, h, pinned and TBH.Colors.accent or TBH.Colors.bgPanel2)

                if _:IsHovered() then
                    draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline)
                end

                -- star glyph, accent-colored when pinned
                draw.SimpleText("*", "TBH.Header", w / 2, h / 2 + 1,
                    pinned and Color(14, 26, 12) or TBH.Colors.textdim,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            pinBtn.DoClick = function()
                local nowPinned = TBH.ToggleFavorite(entry.wsid)
                TBH.NotifyLocally(nowPinned
                    and ("Pinned \"" .. (row.title or entry.wsid) .. "\" - it survives restarts now (PINNED section / hotloader_pins)")
                    or ("Unpinned \"" .. (row.title or entry.wsid) .. "\""), 0, 4)
            end

            row.RightPad = row.RightPad + 44
        end

        ----------------------------------------------------------------
        -- Card painting
        ----------------------------------------------------------------
        row.Paint = function(selfRow, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)

            if selfRow:IsHovered() then
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel2)
            end

            local mounted = TBH.Client.Mounted and TBH.Client.Mounted[selfRow.wsid]
            local queued = false
            if TBH.Client.Queue then
                for i = 1, #TBH.Client.Queue do
                    if TBH.Client.Queue[i].wsid == selfRow.wsid then queued = true break end
                end
            end

            local dotColor, stateText

            if istable(mounted) and mounted.unloaded then
                dotColor = TBH.Colors.textdim
                stateText = "Unloaded"
            elseif mounted then
                dotColor = TBH.Colors.ok
                stateText = mounted.files .. " files"

                if istable(mounted.maps) and #mounted.maps > 0 then
                    stateText = #mounted.maps .. " map(s)"
                end

                if (mounted.errors or 0) > 0 then
                    dotColor = TBH.Colors.warn
                    stateText = stateText .. " - " .. mounted.errors .. " errors"
                end
            elseif queued then
                dotColor = TBH.Colors.info
                stateText = "downloading..."
            elseif istable(TBH.Client.Known[selfRow.wsid]) and TBH.Client.Known[selfRow.wsid].requested then
                dotColor = TBH.Colors.info
                stateText = "requested - waiting for server..."
            else
                dotColor = TBH.Colors.warn
                stateText = "not synced yet"
            end

            local left = 142
            local rightX = w - (selfRow.RightPad or 12)

            draw.RoundedBox(4, left, 10, 8, 8, dotColor)

            draw.SimpleText(displayTitle, "TBH.Body", left + 16, 8, TBH.Colors.text)

            -- author line ("By <author>" from the workshop page)
            local meta = TBH.Client.Meta and TBH.Client.Meta[selfRow.wsid]
            local authorText = "wsid " .. selfRow.wsid

            if meta and meta.author then
                authorText = "By " .. meta.author .. "  -  " .. authorText
            end

            draw.SimpleText(authorText, "TBH.Small", left, 30, TBH.Colors.textdim)

            draw.SimpleText(stateText, "TBH.Small", rightX, 12, dotColor, TEXT_ALIGN_RIGHT)

            local conflict = TBH.Client.Conflicts and TBH.Client.Conflicts[selfRow.wsid]
            if conflict then
                local n = conflict.classTotal + conflict.fileTotal
                draw.SimpleText("radar: " .. n .. " conflict(s)", "TBH.Small", rightX, 48, TBH.Colors.warn, TEXT_ALIGN_RIGHT)
            end

            if mounted and not mounted.unloaded then
                local t = os.date("%H:%M", mounted.time or os.time())
                draw.SimpleText(t, "TBH.Small", rightX, 30, TBH.Colors.dim, TEXT_ALIGN_RIGHT)
            end
        end

        row.OnMousePressed = function(selfRow, code)
            if code == MOUSE_LEFT then
                SetClipboardText(selfRow.wsid)
                TBH.NotifyLocally("Workshop ID " .. selfRow.wsid .. " copied to clipboard", 0)
            elseif code == MOUSE_RIGHT then
                local menu = DermaMenu()

                menu:AddOption("Show Content In Addon", function()
                    TBH.FS.ShowContentByWSID(selfRow.wsid, selfRow.title)
                end):SetIcon("icon16/folder_explore.png")

                menu:AddOption("Copy Workshop ID", function()
                    SetClipboardText(selfRow.wsid)
                    TBH.NotifyLocally("Workshop ID copied", 0)
                end):SetIcon("icon16/page_copy.png")

                menu:AddOption("Copy Workshop URL", function()
                    SetClipboardText(TBH.WorkshopURL(selfRow.wsid))
                    TBH.NotifyLocally("Workshop URL copied", 0)
                end):SetIcon("icon16/link.png")

                menu:AddOption("Open page in Hotloader Browser", function()
                    TBH.OpenBrowserFromMenu(TBH.WorkshopURL(selfRow.wsid))
                end):SetIcon("icon16/world.png")

                menu:AddOption("Force addon reload", function()
                    TBH.RequestForceReload(selfRow.wsid, selfRow.title)
                end):SetIcon("icon16/arrow_refresh.png")

                -- V.1.0.6: pin/unpin favorite
                if TBH.IsFavorite(selfRow.wsid) then
                    menu:AddOption("Unpin from favorites", function()
                        TBH.ToggleFavorite(selfRow.wsid)
                    end):SetIcon("icon16/delete.png")
                else
                    menu:AddOption("Pin to favorites (survives restarts)", function()
                        TBH.ToggleFavorite(selfRow.wsid)
                    end):SetIcon("icon16/star.png")
                end

                local rowMounted = TBH.Client.Mounted and TBH.Client.Mounted[selfRow.wsid]
                local rowMaps = (istable(rowMounted) and istable(rowMounted.maps) and #rowMounted.maps > 0 and rowMounted.maps)
                    or (istable(entry.maps) and #entry.maps > 0 and entry.maps)
                    or nil

                if rowMaps then
                    menu:AddSpacer()

                    for i = 1, math.min(#rowMaps, 20) do
                        menu:AddOption("Load map: " .. rowMaps[i], function()
                            TBH.RequestLoadMap(rowMaps[i])
                        end):SetIcon("icon16/map.png")
                    end
                end

                if TBH.Client.Conflicts and TBH.Client.Conflicts[selfRow.wsid] then
                    menu:AddSpacer()
                    menu:AddOption("Conflict report...", function()
                        Derma_Message(TBH.ConflictReportText(selfRow.wsid), "Conflict Radar", "OK")
                    end):SetIcon("icon16/error.png")
                end

                if not (istable(rowMounted) and rowMounted.unloaded) then
                    menu:AddSpacer()

                    menu:AddOption("Unload...", function()
                        OpenUnloadDialogFromRow(selfRow)
                    end):SetIcon("icon16/cross.png")

                    -- V.1.0.6: FULL unload (needs the gmaunmount module on
                    -- the server; falls back to soft unload with a message)
                    menu:AddOption("FULL Unload", function()
                        TBH.RequestFullUnload(selfRow.wsid, false)
                    end):SetIcon("icon16/bin_closed.png")
                end

                menu:Open()
            end
        end

        row:SetTooltip("Left click: copy ID - Right click: options")

        return row
    end

    vgui.Register("TBH.MenuPage", PANEL, "EditablePanel")

    ------------------------------------------------------------------------------
    -- Spawnmenu creation tabs (top tab row: Spawnlists/Weapons/.../Saves)
    --
    -- The creation menu reads spawnmenu.GetCreationTabs() when the spawnmenu
    -- is BUILT, so tabs must be registered BEFORE that. Two paths:
    --   1. file scope (if the spawnmenu module is loaded already)
    --   2. the AddToolMenuTabs hook - guaranteed to run inside
    --      CreateSpawnMenu() BEFORE the CreationMenu is populated, and it
    --      re-runs on every spawnmenu_reload. (There is NO "PopulateSpawnMenu"
    --      hook in GMod - that was a dead end.)
    -- Re-registering is safe: tabs are keyed by name.
    ------------------------------------------------------------------------------

    ------------------------------------------------------------------------------
    ------------------------------------------------------------------------------
    -- V.1.0.5 / V.1.0.8: KEEP THE SPAWNMENU OPEN WHILE THE "HOTLOADER BROWSER"
    -- TAB IS THE ACTIVE TAB ("pin" it - your original request).
    --
    -- While the Hotloader Browser tab is the SELECTED tab:
    --   * the spawnmenu stays PINNED open: releasing Q, tapping Q or holding
    --     Q never closes it - you can browse and type freely
    --   * clicking ANY other tab in the top tab row closes the spawnmenu
    --     immediately ("it won't close unless you click a tab")
    --   * ESC (main menu) still closes it too
    --
    -- V.1.0.8 REDESIGN (your report: "still cant close it"). Previous versions
    -- kept GMod's HangOpen flag continuously re-armed - a flag that GMod's OWN
    -- text-entry focus handshake ALSO arms and never clears, which made stuck
    -- states possible and debugging miserable. The redesign has ZERO cached
    -- state and ONE live signal:
    --
    --   * hook OnSpawnMenuClose: swallow the Q release ONLY IF the browser
    --     page is valid and IsVisible() RIGHT NOW (the live signal). The
    --     moment you click any other tab, the page is not visible -> the hook
    --     stops swallowing -> Q closes the menu normally. There is NO flag
    --     that can stick, because there is no flag.
    --   * a slim timer still closes the menu the moment you switch AWAY from
    --     the browser tab (your "wont close unless you click a tab" behavior)
    --     and clears HangOpen as hygiene.
    --   * SpawnMenuClosed clears leftover state as hygiene.
    --   * the typing search-box still keeps the menu open while it holds
    --     keyboard focus (vanilla GMod behavior) and releasing that focus
    --     clears HangOpen (V.1.0.7 fix kept).
    --
    -- Worst case failure is now structurally impossible: a swallowed release
    -- can only ever happen while the browser tab is genuinely on screen.
    ------------------------------------------------------------------------------

    -- track the browser tab's page so the close-hook can live-check it
    TBH.BrowserTabPage = nil

    -- is the Hotloader Browser tab the tab on screen RIGHT NOW?
    local function BrowserTabLiveVisible()
        local page = TBH.BrowserTabPage
        return IsValid(page) and page:IsVisible() or false
    end

    -- hold on to the spawnmenu panel. SpawnMenuCreated fires on boot and
    -- after every spawnmenu_reload.
    hook.Add("SpawnMenuCreated", "TBH.FindSpawnMenu", function(smenu)
        if IsValid(smenu) then
            TBH.SpawnMenu = smenu
        end
    end)

    -- find the spawnmenu panel even if it was created before this file
    -- loaded (walks the parent chain from any panel, e.g. our browser tab)
    function TBH.GetSpawnMenuPanel(from)
        if IsValid(TBH.SpawnMenu) then return TBH.SpawnMenu end

        local node = from
        while IsValid(node) do
            if node.GetClassName and node:GetClassName() == "SpawnMenu" then
                TBH.SpawnMenu = node
                return node
            end
            node = node:GetParent()
        end

        return nil
    end

    -- V.1.0.9 FIX: Removed the OnSpawnMenuClose hook that swallowed the Q release.
    -- Returning true in OnSpawnMenuClose happens too late in the input pipeline,
    -- causing the engine to release/move the mouse before the close is cancelled,
    -- resulting in the "mouse moves left and menu doesn't close" glitch.
    -- The spawnmenu will now close normally when Q is released.
    hook.Remove("OnSpawnMenuClose", "TBH.PinBrowserTab")

    -- hygiene: after ANY successful close, drop any leftover HangOpen
    hook.Add("SpawnMenuClosed", "TBH.BrowserTabUnpin", function()
        local sm = TBH.GetSpawnMenuPanel()

        if IsValid(sm) then
            pcall(function() sm:SetHangOpen(false) end)
        end
    end)

    ------------------------------------------------------------------------------
    -- INSTALLED ADDONS tab
    --
    -- your main menu "Addons" list as a card grid: workshop preview, status, a
    -- HOTLOAD button on the ones that arent loaded, and LOAD MAP on map addons
    -- (found through their workshop tags). previews are fetched one at a time in
    -- the background, cards fill in as they arrive.
    --
    -- the grid positions its cards by hand and sets its own height. the earlier
    -- DIconLayout version kept a stale height after a search, which is why the
    -- list looked broken / nearly empty once you cleared the search box.
    ------------------------------------------------------------------------------
    do
        local PANEL = {}
        local CARD_W, CARD_H, GAP, PAGE = 196, 214, 8, 60

        local function Hotloaded(wsid)
            local m = TBH.Client.Mounted and TBH.Client.Mounted[wsid]
            return istable(m) and not m.unloaded
        end

        local function HasMapTag(tags)
            if not isstring(tags) then return false end
            local padded = "," .. string.gsub(string.lower(tags), "%s", "") .. ","
            return string.find(padded, ",map,", 1, true) ~= nil
        end

        -- very small word wrap, two lines max
        local function Wrap2(text, maxChars)
            if #text <= maxChars then return text, "" end

            local cut = maxChars
            local space = string.find(string.sub(text, 1, maxChars), " [^ ]*$")
            if space and space > maxChars * 0.5 then cut = space end

            local first = string.Trim(string.sub(text, 1, cut))
            local second = string.Trim(string.sub(text, cut + 1))
            if #second > maxChars then second = string.sub(second, 1, maxChars - 3) .. "..." end

            return first, second
        end

        function PANEL:Init()
            self.Filter = "all"
            self.Search = ""
            self.Limit = PAGE
            self.Cards = {}
            self.RefreshHook = "TBH.InstalledPage" .. tostring(self)

            self.Paint = function(_, w, h)
                draw.RoundedBox(0, 0, 0, w, h, TBH.Colors.bg)

                if TBH.Theme and TBH.Theme.bgMaterial then
                    local alpha = TBH.CVarThemeAlpha and math.Clamp(TBH.CVarThemeAlpha:GetInt() or 100, 0, 255) or 255
                    surface.SetMaterial(TBH.Theme.bgMaterial)
                    surface.SetDrawColor(255, 255, 255, alpha)
                    surface.DrawTexturedRect(0, 0, w, h)
                end
            end

            -- top bar: title + filter chips + search
            local bar = vgui.Create("DPanel", self)
            bar:Dock(TOP)
            bar:SetTall(48)
            bar:DockMargin(0, 0, 0, 8)
            bar.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                draw.RoundedBoxEx(6, 0, 0, 5, h, TBH.Colors.accent, true, false, true, false)
                draw.SimpleText("INSTALLED ADDONS", "TBH.Header", 18, 5, TBH.Colors.tag)
                draw.SimpleText(self.CountText or "", "TBH.Small", 18, 29, TBH.Colors.textdim)
            end

            local search = vgui.Create("DTextEntry", bar)
            search:Dock(RIGHT)
            search:SetWide(220)
            search:DockMargin(0, 11, 12, 11)
            search:SetFont("TBH.Small")
            search:SetPlaceholderText("search by name or id...")
            search.OnChange = function(entry)
                self.Search = string.lower(entry:GetText())
                self.Limit = PAGE
                -- debounced, one rebuild after you stop typing
                timer.Create(self.RefreshHook .. ".search", 0.25, 1, function()
                    if IsValid(self) then self:Refresh() end
                end)
            end

            -- the chips start after the title, measured, so they never touch the text
            surface.SetFont("TBH.Header")
            local titleW = surface.GetTextSize("INSTALLED ADDONS")
            surface.SetFont("TBH.Small")

            local chipBox = vgui.Create("DPanel", bar)
            chipBox:Dock(FILL)
            chipBox:DockMargin(18 + titleW + 30, 11, 10, 11)
            chipBox.Paint = function() end

            local chips = {
                { "all", "All" },
                { "off", "Not loaded" },
                { "on", "Enabled" },
                { "hot", "Hotloaded" },
                { "map", "Maps" },
            }

            for _, c in ipairs(chips) do
                local chip = vgui.Create("DButton", chipBox)
                chip:Dock(LEFT)
                chip:DockMargin(0, 0, 6, 0)
                chip:SetText(c[2])
                chip:SetFont("TBH.Small")
                surface.SetFont("TBH.Small")
                chip:SetWide(surface.GetTextSize(c[2]) + 26)
                chip.Paint = function(btn, w, h)
                    local active = self.Filter == c[1]
                    draw.RoundedBox(h / 2, 0, 0, w, h, active and TBH.Colors.accent or (btn:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bg))
                    btn:SetColor(active and Color(14, 26, 12) or TBH.Colors.textdim)
                end
                chip.DoClick = function()
                    self.Filter = c[1]
                    self.Limit = PAGE
                    self:Refresh()
                end
            end

            self.Scroll = vgui.Create("DScrollPanel", self)
            self.Scroll:Dock(FILL)

            self.Grid = vgui.Create("DPanel", self.Scroll)
            self.Grid:Dock(TOP)
            self.Grid:SetTall(10)
            self.Grid.Paint = function() end
            self.Grid.PerformLayout = function(grid, w, h)
                local cols = math.max(1, math.floor((w + GAP) / (CARD_W + GAP)))

                for i, card in ipairs(self.Cards) do
                    if IsValid(card) then
                        card:SetPos(((i - 1) % cols) * (CARD_W + GAP), math.floor((i - 1) / cols) * (CARD_H + GAP))
                    end
                end

                local rows = math.ceil(#self.Cards / cols)
                local want = math.max(10, rows * (CARD_H + GAP))
                if grid:GetTall() ~= want then grid:SetTall(want) end
            end

            self.Footer = vgui.Create("DPanel", self.Scroll)
            self.Footer:Dock(TOP)
            self.Footer:SetTall(0)
            self.Footer.Paint = function() end

            -- keep statuses fresh (hotloaded / unloaded changes), debounced
            hook.Add("TBH.ClientListChanged", self.RefreshHook, function()
                if not IsValid(self) then return end
                timer.Create(self.RefreshHook, 0.4, 1, function()
                    if IsValid(self) then self:Refresh() end
                end)
            end)

            self:Refresh()
        end

        function PANEL:OnRemove()
            hook.Remove("TBH.ClientListChanged", self.RefreshHook)
            timer.Remove(self.RefreshHook)
            timer.Remove(self.RefreshHook .. ".search")
        end

        function PANEL:Collect()
            local out = {}

            for _, a in ipairs((engine and engine.GetAddons and engine.GetAddons()) or {}) do
                local id = tostring(a.wsid or "")
                if TBH.IsValidWSID(id) then
                    out[#out + 1] = {
                        wsid = id,
                        title = tostring(a.title or id),
                        enabled = a.mounted == true,
                        isMap = HasMapTag(a.tags),
                        file = a.file,
                    }
                end
            end

            return out
        end

        function PANEL:Refresh()
            if not (IsValid(self.Grid) and IsValid(self.Footer)) then return end

            local ok, err = pcall(function() self:DoRefresh() end)
            if not ok then
                TBH.LogError("Installed Addons refresh failed: " .. tostring(err))
            end
        end

        function PANEL:DoRefresh()
            for _, card in ipairs(self.Cards) do
                if IsValid(card) then card:Remove() end
            end
            self.Cards = {}
            self.Footer:Clear()
            self.Footer:SetTall(0)

            local all = self:Collect()
            local list = {}
            local q = self.Search or ""

            for _, a in ipairs(all) do
                local hot = Hotloaded(a.wsid)
                local pass = (self.Filter == "all")
                    or (self.Filter == "off" and not a.enabled and not hot)
                    or (self.Filter == "on" and a.enabled)
                    or (self.Filter == "hot" and hot)
                    or (self.Filter == "map" and a.isMap)

                if pass and (q == "" or string.find(string.lower(a.title), q, 1, true) or string.find(a.wsid, q, 1, true)) then
                    list[#list + 1] = a
                end
            end

            -- the ones you can actually hotload first, then by name. sort keys are
            -- computed once so the comparison stays consistent
            for _, a in ipairs(list) do
                a._open = (not a.enabled and not Hotloaded(a.wsid)) and 0 or 1
                a._name = string.lower(a.title)
            end

            table.sort(list, function(x, y)
                if x._open ~= y._open then return x._open < y._open end
                if x._name ~= y._name then return x._name < y._name end
                return x.wsid < y.wsid
            end)

            self.CountText = #list .. " of " .. #all .. " addons shown"

            local shown = math.min(#list, self.Limit)
            for i = 1, shown do
                self.Cards[#self.Cards + 1] = self:MakeCard(list[i])
            end

            if #list == 0 then
                self.Footer:SetTall(44)
                self.Footer.Paint = function(_, w, h)
                    draw.SimpleText("No addons match this filter.", "TBH.Body", 6, h / 2, TBH.Colors.textdim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            elseif #list > shown then
                self.Footer:SetTall(46)
                self.Footer.Paint = function() end

                local more = vgui.Create("DButton", self.Footer)
                more:SetPos(0, 6)
                more:SetSize(260, 34)
                more:SetText("")
                more.Paint = function(btn, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, btn:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bgPanel)
                    draw.SimpleText("show " .. math.min(PAGE, #list - shown) .. " more (" .. (#list - shown) .. " left)", "TBH.Small", w / 2, h / 2, TBH.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                more.DoClick = function()
                    self.Limit = self.Limit + PAGE
                    self:Refresh()
                end
            end

            self.Grid:InvalidateLayout(true)
            self.Scroll:InvalidateLayout(true)
        end

        function PANEL:MakeCard(a)
            local card = vgui.Create("DPanel", self.Grid)
            card:SetSize(CARD_W, CARD_H)

            TBH.FetchAddonMeta(a.wsid) -- queued, one at a time

            local line1, line2 = Wrap2(a.title, 25)

            card.Paint = function(c, w, h)
                draw.RoundedBox(8, 0, 0, w, h, c:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bgPanel)

                -- preview image (16:9)
                local iw, ih = w - 12, math.floor((w - 12) * 9 / 16)
                draw.RoundedBox(4, 6, 6, iw, ih, TBH.Colors.bg)

                local mat = TBH.GetAddonImage(a.wsid)
                if mat then
                    surface.SetMaterial(mat)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(6, 6, iw, ih)
                else
                    draw.SimpleText("loading preview...", "TBH.Small", w / 2, 6 + ih / 2, TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end

                if a.isMap then
                    draw.RoundedBox(8, 12, 12, 36, 18, TBH.Colors.accent)
                    draw.SimpleText("MAP", "TBH.Small", 30, 21, Color(14, 26, 12), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end

                local ty = 6 + ih + 6
                draw.SimpleText(line1, "TBH.Body", 8, ty, TBH.Colors.text)
                if line2 ~= "" then draw.SimpleText(line2, "TBH.Body", 8, ty + 16, TBH.Colors.text) end

                local status, color = "not loaded", TBH.Colors.textdim
                if Hotloaded(a.wsid) then
                    status, color = "hotloaded this session", TBH.Colors.ok
                elseif a.enabled then
                    status, color = "enabled normally", TBH.Colors.info
                end

                draw.RoundedBox(4, 8, h - 55, 8, 8, color)
                draw.SimpleText(status, "TBH.Small", 22, h - 59, color)
            end

            -- pin star (top right of the image)
            local star = vgui.Create("DButton", card)
            star:SetPos(CARD_W - 34, 10)
            star:SetSize(24, 24)
            star:SetText("")
            star:SetTooltip("Pin to your Hotloader list")
            star.Paint = function(btn, w, h)
                local pinned = TBH.Client.Favorites and TBH.Client.Favorites[a.wsid]
                draw.RoundedBox(12, 0, 0, w, h, Color(0, 0, 0, btn:IsHovered() and 200 or 140))
                draw.SimpleText("*", "TBH.Header", w / 2, h / 2 + 3, pinned and TBH.Colors.warn or TBH.Colors.textdim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            star.DoClick = function()
                if TBH.Client.Favorites and TBH.Client.Favorites[a.wsid] then
                    TBH.ToggleFavorite(a.wsid)
                else
                    TBH.PinAddon(a.wsid, a.title, a.isMap)
                end
            end

            -- button row at the bottom: HOTLOAD, and LOAD MAP on map addons
            local live = Hotloaded(a.wsid)
            local buttons = {}

            if a.isMap and not a.enabled then
                buttons[#buttons + 1] = { "LOAD MAP", function() TBH.LoadMapForAddon(a.wsid, a.title) end, true }
            end
            if not a.enabled and not live then
                buttons[#buttons + 1] = { "HOTLOAD", function() TBH.RequestHotload(a.wsid, a.title) end, not a.isMap }
            end

            local count = #buttons
            if count > 0 then
                local bw = math.floor((CARD_W - 16 - (count - 1) * 6) / count)
                for i, def in ipairs(buttons) do
                    local btn = vgui.Create("DButton", card)
                    btn:SetPos(8 + (i - 1) * (bw + 6), CARD_H - 34)
                    btn:SetSize(bw, 26)
                    btn:SetText(def[1])
                    btn:SetFont("TBH.Small")
                    btn:SetColor(def[3] and Color(14, 26, 12) or TBH.Colors.text)
                    btn.Paint = function(b, w, h)
                        if def[3] then
                            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.accent)
                            if b:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.tag) end
                        else
                            draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
                            if b:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline) end
                        end
                    end
                    btn.DoClick = def[2]
                end
            end

            card.OnMousePressed = function(_, code)
                if code ~= MOUSE_RIGHT then return end

                local menu = DermaMenu()
                menu:AddOption("Show Content In Addon", function()
                    TBH.FS.ShowAddonContent(a.title, a.wsid, a.file or TBH.FS.FindGMA(a.wsid), true)
                end):SetIcon("icon16/folder_explore.png")
                menu:AddOption("Copy Workshop ID", function() SetClipboardText(a.wsid) end):SetIcon("icon16/page_copy.png")
                menu:AddOption("Open page in the Workshop browser", function()
                    TBH.OpenBrowserFromMenu(TBH.WorkshopURL(a.wsid))
                end):SetIcon("icon16/world.png")
                menu:Open()
            end

            return card
        end

        vgui.Register("TBH.InstalledPage", PANEL, "EditablePanel")
    end

    TBH.FS = TBH.FS or {}

    -- "Show Content In Addon": a window with the addon's lua / materials / sound / models /
    -- particles... browsable with the same viewers as the filesystem tab
    function TBH.FS.OpenContentWindow(title, wsid, files, note)
        local frame = vgui.Create("DFrame")
        frame:SetSize(math.min(ScrW() - 60, 1300), math.min(ScrH() - 60, 780))
        frame:Center()
        frame:SetTitle("Content - " .. tostring(title) .. "  (" .. #files .. " files)")
        frame:SetSizable(true)
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bg)
            draw.RoundedBoxEx(6, 0, 0, w, 24, TBH.Colors.bgPanel, true, true, false, false)
        end

        local page = vgui.Create("TBH.FilesystemPage", frame)
        page:Dock(FILL)
        page:DockMargin(0, 0, 0, 0)
        page:SetVirtual(files, tostring(title), "ws_" .. tostring(wsid), note)
    end

    function TBH.FS.ShowAddonContent(title, wsid, gmaPath, mounted)
        wsid = tostring(wsid)

        -- the engine does not always report a file for an addon, so also try where
        -- workshop items normally live (gmpublisher.gma or <id>_legacy.bin)
        local paths = {}
        if isstring(gmaPath) and gmaPath ~= "" then paths[#paths + 1] = gmaPath end
        for _, g in ipairs({
            "content/4000/" .. wsid .. "/gmpublisher.gma",
            "content/4000/" .. wsid .. "/" .. wsid .. "_legacy.bin",
            "cache/workshop/" .. wsid .. ".gma",
            "cache/workshop/" .. wsid .. ".cache",
        }) do
            paths[#paths + 1] = g
        end

        local lastErr
        for _, path in ipairs(paths) do
            local files, err = TBH.FS.ListGMA(path)
            if files then
                TBH.FS.OpenContentWindow(title, wsid, files, nil)
                return
            end
            lastErr = err
        end

        TBH.Msg("Show content: " .. tostring(lastErr))

        -- last resort: let the engine mount it, MountGMA hands back the list of files
        Derma_Query("Lua is not allowed to read this addon's .gma directly:\n" .. tostring(paths[1])
            .. "\n\nThe engine can mount it instead, which also gives the file list. On huge addons that can freeze the game for a while. Try it?",
            "Hotloader", "Mount and list",
            function()
                for _, path in ipairs(paths) do
                    local ok, success, list = pcall(game.MountGMA, path)
                    if ok and success and istable(list) then
                        local out = {}
                        for _, f in ipairs(list) do
                            out[#out + 1] = { path = string.lower(f), size = file.Size(f, "GAME") or 0 }
                        end
                        table.sort(out, function(x, y) return x.path < y.path end)

                        TBH.FS.OpenContentWindow(title, wsid, out, "listed through the engine")
                        return
                    end
                end

                TBH.NotifyLocally("Could not find or read a .gma for " .. tostring(title) .. " (tried " .. #paths .. " locations). Is it still subscribed / downloaded?", 2, 8)
            end,
            "Cancel", function() end)
    end

    -- finds the .gma of a workshop id: installed addons first, then the cache that
    -- hotloaded downloads land in
    function TBH.FS.FindGMA(wsid)
        wsid = tostring(wsid)

        for _, a in ipairs((engine and engine.GetAddons and engine.GetAddons()) or {}) do
            if tostring(a.wsid) == wsid and isstring(a.file) and a.file ~= "" then return a.file end
        end

        for _, c in ipairs({ "cache/workshop/" .. wsid .. ".gma", "download/workshop/" .. wsid .. ".gma" }) do
            if (file.Size(c, "MOD") or 0) > 0 then return c end
        end

        -- subscribed items live in <steam>/steamapps/workshop/content/4000/<id>/<name>.gma
        for _, id in ipairs({ "WORKSHOP", "GAME", "MOD", "DOWNLOAD" }) do
            local ok, found = pcall(file.Find, "content/4000/" .. wsid .. "/*.gma", id)
            if ok and found and found[1] then return "content/4000/" .. wsid .. "/" .. found[1] end
        end
    end

    function TBH.FS.ShowContentByWSID(wsid, title)
        local path = TBH.FS.FindGMA(wsid)
        if not path then
            TBH.NotifyLocally("Could not find the .gma for " .. tostring(wsid) .. " (is it downloaded?)", 3, 6)
            return
        end

        local mounted = TBH.Client and TBH.Client.Mounted and TBH.Client.Mounted[wsid]
        TBH.FS.ShowAddonContent(title or wsid, wsid, path, true)
    end

    ------------------------------------------------------------------------------
    -- HOTLOADER TAB WRAPPER
    --
    -- one tab with two views, switched from a bar at the top:
    --   HOTLOADER         the addon list, pins, activity feed
    --   WORKSHOP BROWSER  the Workshop browser (created the first time you open it,
    --                     so the web view isnt loaded until you want it)
    ------------------------------------------------------------------------------
    do
        local PANEL = {}

        function PANEL:Init()
            self.Mode = "home"

            local bar = vgui.Create("DPanel", self)
            bar:Dock(TOP)
            bar:SetTall(38)
            bar:DockMargin(0, 0, 0, 6)
            bar.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
            end

            local function Segment(mode, text, icon, wide)
                local btn = vgui.Create("DButton", bar)
                btn:Dock(LEFT)
                btn:SetWide(wide)
                btn:DockMargin(5, 5, 0, 5)
                btn:SetText("")
                local iconMat = Material(icon)
                btn.Paint = function(b, w, h)
                    local active = self.Mode == mode
                    draw.RoundedBox(5, 0, 0, w, h, active and TBH.Colors.accent or (b:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bg))

                    local col = active and Color(14, 26, 12) or TBH.Colors.textdim
                    if iconMat and not iconMat:IsError() then
                        surface.SetMaterial(iconMat)
                        surface.SetDrawColor(255, 255, 255, active and 255 or 170)
                        surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
                    end
                    draw.SimpleText(text, "TBH.Body", 36, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                btn.DoClick = function() self:SetMode(mode) end
                return btn
            end

            Segment("home", "HOTLOADER", "icon16/lightning.png", 150)
            Segment("browser", "WORKSHOP BROWSER", "icon16/world.png", 200)

            bar.PaintOver = function(_, w, h)
                local hint = (self.Mode == "browser")
                    and "browse the Workshop - every addon page has a HOTLOAD button"
                    or "paste a link, pin addons, hotload them"
                draw.SimpleText(hint, "TBH.Small", w - 12, h / 2, TBH.Colors.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            self.Home = vgui.Create("TBH.MenuPage", self)
            self.Home:Dock(FILL)
            self.Home:DockPadding(8, 8, 8, 8)

            TBH.HotloaderTab = self
        end

        function PANEL:EnsureBrowser()
            if IsValid(self.BrowserHolder) then return end

            self.BrowserHolder = vgui.Create("EditablePanel", self)
            self.BrowserHolder:Dock(FILL)
            self.BrowserHolder:DockPadding(4, 4, 4, 4)
            self.BrowserHolder:SetVisible(false)

            self.Browser = vgui.Create("TBH.BrowserPanel", self.BrowserHolder)
            self.Browser:Dock(FILL)

            TBH.BrowserTabPage = self.BrowserHolder
        end

        function PANEL:SetMode(mode)
            self.Mode = mode

            if mode == "browser" then
                self:EnsureBrowser()
                self.Home:SetVisible(false)
                self.BrowserHolder:SetVisible(true)
            else
                self.Home:SetVisible(true)
                if IsValid(self.BrowserHolder) then self.BrowserHolder:SetVisible(false) end
            end

            self:InvalidateLayout(true)
        end

        function PANEL:ShowBrowser(url)
            self:SetMode("browser")

            if url and IsValid(self.Browser) then
                self.Browser:Navigate(url)
            end
        end

        function PANEL:OnRemove()
            if TBH.HotloaderTab == self then TBH.HotloaderTab = nil end
            if TBH.BrowserTabPage == self.BrowserHolder then TBH.BrowserTabPage = nil end
        end

        vgui.Register("TBH.HotloaderTab", PANEL, "EditablePanel")
    end

    ------------------------------------------------------------------------------
    -- FILESYSTEM ADDONS  (v1.0.2: a real file browser)
    --
    -- browse garrysmod/addons (and garrysmod/data) folder by folder:
    --   * .wav .mp3 .ogg   -> audio player (seek, volume, loop, spectrum)
    --   * .lua .txt .vmt   -> code editor. SAVE (Ctrl+S) compiles + runs the file live
    --                         on your client, or on the server (RUN SERVER).
    --                         .vmt files are applied to the in-game material live
    --   * .vtf .png .jpg   -> image viewer with pan/zoom and a paint mode. painting
    --                         can be applied to the in-game material live
    --
    -- GMod's Lua can ONLY write inside garrysmod/data. so files from addons/ are never
    -- overwritten: edits are saved as copies in data/hotloader_fs/ and applied at runtime
    -- (code is re-run, materials get their texture swapped). files you open from the
    -- DATA root are saved in place.
    ------------------------------------------------------------------------------
    TBH.FS = TBH.FS or {}

    TBH.CVarFSAutoApply = GetOrCreateConVar("hotloader_fs_autoapply", "1", nil, "Re-apply your saved painted materials (data/hotloader_fs/paint) when you join a server")

    do
        local FS = TBH.FS

        FS.DataDir = "hotloader_fs"
        FS.Applied = FS.Applied or {}       -- [matRel] = { orig = ITexture }  (so we can put the original back)
        FS.PaintState = FS.PaintState or {} -- [matRel] = { strokes = {}, live = bool }
        FS.Counter = FS.Counter or 0
        FS.IconCache = FS.IconCache or {}

        surface.CreateFont("TBH.Code", { font = "Courier New", size = 15, weight = 500, extended = true })

        local TEXT_EXT = {
            lua = true, txt = true, json = true, vmt = true, cfg = true, properties = true, md = true,
            ini = true, vdf = true, qc = true, csv = true, xml = true, html = true, js = true, css = true,
            log = true, kv = true, res = true, lst = true, rad = true, vmf = true, scenes = true, yml = true,
        }
        local AUDIO_EXT = { wav = true, mp3 = true, ogg = true }
        local IMAGE_EXT = { vtf = true, png = true, jpg = true, jpeg = true }

        local ICONS = {
            lua = "icon16/page_white_code.png", vmt = "icon16/page_white_gear.png",
            vtf = "icon16/picture.png", png = "icon16/picture.png", jpg = "icon16/picture.png", jpeg = "icon16/picture.png",
            wav = "icon16/sound.png", mp3 = "icon16/sound.png", ogg = "icon16/sound.png",
            mdl = "icon16/box.png", gma = "icon16/package.png",
        }

        function FS.Ext(name)
            return string.lower(string_match(name or "", "%.([%w_]+)$") or "")
        end

        function FS.Icon(ext, isDir)
            local path = isDir and "icon16/folder.png" or (ICONS[ext] or (TEXT_EXT[ext] and "icon16/page_white_text.png") or "icon16/page_white.png")
            if not FS.IconCache[path] then FS.IconCache[path] = Material(path) end
            return FS.IconCache[path]
        end

        function FS.FormatSize(n)
            n = tonumber(n) or 0
            if n < 1024 then return n .. " B" end
            if n < 1048576 then return string.format("%.1f KB", n / 1024) end
            return string.format("%.1f MB", n / 1048576)
        end

        -- file.Write only accepts a short whitelist of extensions (no .lua!). anything else
        -- gets ".txt" appended, e.g. foo.lua -> foo.lua.txt
        local WRITABLE_EXT = { txt = true, dat = true, json = true, xml = true, csv = true, jpg = true, jpeg = true, png = true, vtf = true, vmt = true, mp3 = true, wav = true, ogg = true }

        function FS.WritablePath(path)
            if WRITABLE_EXT[FS.Ext(path)] then return path end
            return path .. ".txt"
        end

        -- shortens text so it fits maxW pixels
        function FS.Fit(font, text, maxW)
            text = tostring(text or "")
            surface.SetFont(font)
            if surface.GetTextSize(text) <= maxW then return text end

            while #text > 4 and surface.GetTextSize(text .. "...") > maxW do
                text = string_sub(text, 1, #text - math.max(1, math.floor(#text * 0.06)))
            end

            return text .. "..."
        end

        function FS.SafeName(path)
            path = string_gsub(path, "%.%.+", "_")
            return (string_gsub(path, "[^%w_%-%./]", "_"))
        end

        -- creates data/<path> and every parent folder
        function FS.EnsureDir(dirPath)
            local cur = ""
            for part in string_gmatch(dirPath, "[^/]+") do
                cur = (cur == "") and part or (cur .. "/" .. part)
                if not file.IsDir(cur, "DATA") then file.CreateDir(cur) end
            end
        end

        function FS.Notify(msg, level)
            TBH.NotifyLocally(msg, level or 0, 5)
        end

        function FS.Button(parent, text, wide, doClick, primary)
            local b = vgui.Create("DButton", parent)
            b:Dock(LEFT)
            b:SetWide(wide)
            b:DockMargin(0, 0, 6, 0)
            b:SetText(text)
            b:SetFont("TBH.Small")
            b:SetColor(primary and Color(14, 26, 12) or TBH.Colors.text)
            b.Paint = function(btn, w, h)
                local col = primary and TBH.Colors.accent or TBH.Colors.bgPanel2
                if not btn:IsEnabled() then col = TBH.Colors.bg end
                draw.RoundedBox(4, 0, 0, w, h, col)
                if btn.Active then draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255, 40)) end
                if btn:IsHovered() and btn:IsEnabled() then draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255, 20)) end
            end
            b.DoClick = doClick
            return b
        end

        function FS.Toolbar(parent, height)
            local bar = vgui.Create("DPanel", parent)
            bar:Dock(TOP)
            bar:SetTall(height or 36)
            bar:DockPadding(6, 5, 6, 5)
            bar.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
            end
            return bar
        end

        -- a toggle that looks like the buttons (returns the button, state in b.On)
        function FS.Toggle(parent, text, wide, default, onChange)
            local b
            b = FS.Button(parent, text, wide, function()
                b.On = not b.On
                b.Active = b.On
                if onChange then onChange(b.On) end
            end, false)
            b.On = default and true or false
            b.Active = b.On
            return b
        end

        ----------------------------------------------------------------------
        -- reads the file table of a .gma (path, size) without extracting anything
        ----------------------------------------------------------------------
        -- workshop gmas are reported as "content/4000/<id>/<name>.gma", which lives in the
        -- steam workshop folder, so try every search path (and a few prefixes) until one opens it
        FS.GMA_IDS = { "GAME", "MOD", "WORKSHOP", "DOWNLOAD", "THIRDPARTY", "BASE_PATH" }

        function FS.OpenGMA(path)
            local variants = { path, "workshop/" .. path, "steamapps/workshop/" .. path }

            for _, p in ipairs(variants) do
                for _, id in ipairs(FS.GMA_IDS) do
                    local ok, f = pcall(file.Open, p, "rb", id)
                    if ok and f then return f, id, p end
                end
            end
        end

        function FS.ListGMA(path)
            local f = FS.OpenGMA(path)
            if not f then
                return nil, "Lua cannot open " .. tostring(path) .. " (tried the GAME, MOD, WORKSHOP, DOWNLOAD, THIRDPARTY and BASE_PATH search paths)"
            end

            local function Str()
                local t = {}
                while not f:EndOfFile() do
                    local c = f:Read(1)
                    if c == nil or c == "" or c == "\0" then break end
                    t[#t + 1] = c
                end
                return table.concat(t)
            end

            local ok, res = pcall(function()
                if f:Read(4) ~= "GMAD" then error("not a gma file") end
                f:Skip(1 + 8 + 8) -- version, steamid, timestamp

                while not f:EndOfFile() do -- required content
                    if Str() == "" then break end
                end

                Str() Str() Str() -- title, description, author
                f:Skip(4)         -- addon version

                local list = {}
                while not f:EndOfFile() and #list < 200000 do
                    local num = f:ReadULong()
                    if num == 0 then break end
                    local name = Str()
                    local lo, hi = f:ReadULong(), f:ReadULong()
                    f:Skip(4) -- crc
                    list[#list + 1] = { path = string.lower(name), size = lo + hi * 4294967296 }
                end

                table.sort(list, function(a, b) return a.path < b.path end)
                return list
            end)

            f:Close()
            if not ok then return nil, tostring(res) end
            return res
        end

        ----------------------------------------------------------------------
        -- saved paint index (data/hotloader_fs/edits.json)
        ----------------------------------------------------------------------
        function FS.LoadEdits()
            local raw = file.Read(FS.DataDir .. "/edits.json", "DATA")
            local tbl = isstring(raw) and util.JSONToTable(raw) or nil
            if not istable(tbl) then tbl = {} end
            tbl.paints = istable(tbl.paints) and tbl.paints or {}
            return tbl
        end

        function FS.SaveEdits(tbl)
            FS.EnsureDir(FS.DataDir)
            file.Write(FS.DataDir .. "/edits.json", util.TableToJSON(tbl, true))
        end

        function FS.PaintPath(matRel)
            return FS.DataDir .. "/paint/" .. string_gsub(matRel, "[^%w_%-]", "_") .. ".png"
        end

        -- swap a real in-game material's $basetexture
        function FS.ApplyTexture(matRel, tex)
            local m = Material(matRel)
            if not m or m:IsError() then return false, "material '" .. matRel .. "' is not loaded" end

            if not FS.Applied[matRel] then
                FS.Applied[matRel] = { orig = m:GetTexture("$basetexture") }
            end

            m:SetTexture("$basetexture", tex)
            return true
        end

        function FS.RestoreTexture(matRel)
            local a = FS.Applied[matRel]
            if not a then return false end

            local m = Material(matRel)
            if m and not m:IsError() and a.orig then
                m:SetTexture("$basetexture", a.orig)
            end

            FS.Applied[matRel] = nil
            return true
        end

        function FS.ApplySavedPaints()
            local edits = FS.LoadEdits()
            local n = 0

            for matRel, png in pairs(edits.paints) do
                if isstring(png) and file.Exists(png, "DATA") then
                    local ok = pcall(function()
                        local src = Material("../data/" .. png, "smooth")
                        if not src or src:IsError() then return end
                        local tex = src:GetTexture("$basetexture")
                        if tex and FS.ApplyTexture(matRel, tex) then n = n + 1 end
                    end)
                    if not ok then TBH.Verbose("FS: saved paint failed for " .. tostring(matRel)) end
                end
            end

            return n
        end

        timer.Simple(5, function()
            if TBH.CVarFSAutoApply and TBH.CVarFSAutoApply:GetBool() then
                local n = FS.ApplySavedPaints()
                if n > 0 then TBH.Msg("Re-applied " .. n .. " saved painted material(s)") end
            end
        end)

        concommand.Add("hotloader_fs_applypaints", function()
            FS.Notify("Re-applied " .. FS.ApplySavedPaints() .. " saved painted material(s)", 1)
        end)

        ----------------------------------------------------------------------
        -- apply a .vmt text to the loaded in-game material, live
        ----------------------------------------------------------------------
        local TEXTURE_KEYS = {
            ["$basetexture"] = true, ["$basetexture2"] = true, ["$bumpmap"] = true, ["$bumpmap2"] = true,
            ["$normalmap"] = true, ["$detail"] = true, ["$envmap"] = true, ["$envmapmask"] = true,
            ["$lightwarptexture"] = true, ["$phongexponenttexture"] = true, ["$selfillummask"] = true,
            ["$blendmodulatetexture"] = true, ["$texture2"] = true, ["$iris"] = true, ["$lightmap"] = true,
        }

        function FS.ApplyVMT(matRel, text)
            local m = Material(matRel)
            if not m or m:IsError() then return false, "material '" .. matRel .. "' is not loaded in the game" end

            local kv = util.KeyValuesToTable(text, false, true)
            if not istable(kv) then return false, "vmt could not be parsed" end

            -- the table has the shader as its only key
            local params
            for _, v in pairs(kv) do
                if istable(v) then params = v break end
            end
            if not params then return false, "vmt has no shader block" end

            local count = 0
            for key, value in pairs(params) do
                key = string.lower(tostring(key))
                if string_sub(key, 1, 1) == "$" or string_sub(key, 1, 1) == "%" then
                    local okSet = pcall(function()
                        if TEXTURE_KEYS[key] and isstring(value) then
                            m:SetTexture(key, value)
                        elseif istable(value) then
                            return -- proxies etc, not settable at runtime
                        elseif isstring(value) and (string_match(value, "^%s*%[.+%]%s*$") or string_match(value, "^%s*{.+}%s*$")) then
                            local nums = {}
                            for n in string_gmatch(value, "[%-%.%d]+") do nums[#nums + 1] = tonumber(n) or 0 end
                            if #nums >= 3 then m:SetVector(key, Vector(nums[1], nums[2], nums[3])) end
                        elseif tonumber(value) then
                            local num = tonumber(value)
                            if num == math.floor(num) then m:SetInt(key, num) else m:SetFloat(key, num) end
                        elseif isstring(value) then
                            m:SetString(key, value)
                        end
                    end)
                    if okSet then count = count + 1 end
                end
            end

            pcall(m.Recompute, m)
            return true, "applied " .. count .. " parameter(s) to " .. matRel
        end

        ----------------------------------------------------------------------
        -- small slider (volume, brush size, seek)
        ----------------------------------------------------------------------
        do
            local SL = {}

            function SL:Init()
                self.Min, self.Max, self.Value = 0, 1, 0
                self:SetCursor("hand")
            end

            function SL:SetRange(a, b) self.Min, self.Max = a, b end
            function SL:SetValue(v) self.Value = math.Clamp(v, self.Min, self.Max) end
            function SL:GetValue() return self.Value end

            function SL:Update()
                local x = self:CursorPos()
                local frac = math.Clamp(x / math.max(1, self:GetWide()), 0, 1)
                local v = self.Min + (self.Max - self.Min) * frac
                if self.Step then v = math.Round(v / self.Step) * self.Step end
                self.Value = v
                if self.OnValue then self:OnValue(v) end
            end

            function SL:OnMousePressed()
                self.Drag = true
                self:MouseCapture(true)
                self:Update()
            end

            function SL:OnMouseReleased()
                self.Drag = false
                self:MouseCapture(false)
                if self.OnRelease then self:OnRelease(self.Value) end
            end

            function SL:OnCursorMoved()
                if self.Drag then self:Update() end
            end

            function SL:Paint(w, h)
                local frac = (self.Max > self.Min) and ((self.Value - self.Min) / (self.Max - self.Min)) or 0
                draw.RoundedBox(3, 0, h / 2 - 3, w, 6, TBH.Colors.bg)
                draw.RoundedBox(3, 0, h / 2 - 3, math.max(6, w * frac), 6, TBH.Colors.accent)
                draw.RoundedBox(6, w * frac - 6, h / 2 - 6, 12, 12, TBH.Colors.tag)
            end

            vgui.Register("TBH.FSSlider", SL, "DPanel")
        end

        ----------------------------------------------------------------------
        -- EDITOR  (lua / vmt / text)
        ----------------------------------------------------------------------
        do
            local ED = {}
            local MAX_EDIT = 200000

            function ED:Init()
                self.Dirty = false
                self.ReadOnly = false
                self.Status = ""
                self.StatusLevel = 0
                self.HookId = "TBH.FSEditor" .. tostring(self)

                self.Bar = FS.Toolbar(self, 36)
                self.Bar:DockMargin(0, 0, 0, 6)

                self.BtnSave = FS.Button(self.Bar, "SAVE  (Ctrl+S)", 110, function() self:Save() end, true)
                self.BtnRun = FS.Button(self.Bar, "RUN CLIENT", 90, function() self:Run("client") end)
                self.BtnSrv = FS.Button(self.Bar, "RUN SERVER", 90, function() self:Run("server") end)
                self.TglSave = FS.Toggle(self.Bar, "Run on save", 90, false)
                self.TglLive = FS.Toggle(self.Bar, "Live typing", 90, false, function(on)
                    if on then self:ScheduleLive() end
                end)
                self.BtnFind = FS.Button(self.Bar, "Find", 50, function() self:ToggleFind() end)
                self.BtnOrig = FS.Button(self.Bar, "Original", 70, function() self:LoadOriginal() end)

                self.Foot = vgui.Create("DPanel", self)
                self.Foot:Dock(BOTTOM)
                self.Foot:SetTall(24)
                self.Foot:DockMargin(0, 6, 0, 0)
                self.Foot.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel)
                    local col = TBH.Colors.textdim
                    if self.StatusLevel == 1 then col = TBH.Colors.ok
                    elseif self.StatusLevel == 2 then col = TBH.Colors.error
                    elseif self.StatusLevel == 3 then col = TBH.Colors.warn end

                    local right = self.PosText or ""
                    surface.SetFont("TBH.Small")
                    local rw = surface.GetTextSize(right)

                    draw.SimpleText(right, "TBH.Small", w - 10, h / 2, TBH.Colors.textdim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(FS.Fit("TBH.Small", self.Status, w - rw - 40), "TBH.Small", 10, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                    -- hover the bar for the full message
                    if self.TipFor ~= self.Status then
                        self.TipFor = self.Status
                        self.Foot:SetTooltip(self.Status ~= "" and self.Status or nil)
                    end
                end

                self.FindBar = vgui.Create("DPanel", self)
                self.FindBar:Dock(BOTTOM)
                self.FindBar:SetTall(30)
                self.FindBar:DockMargin(0, 6, 0, 0)
                self.FindBar:DockPadding(4, 4, 4, 4)
                self.FindBar:SetVisible(false)
                self.FindBar.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel) end

                self.FindEntry = vgui.Create("DTextEntry", self.FindBar)
                self.FindEntry:Dock(LEFT)
                self.FindEntry:SetWide(260)
                self.FindEntry:SetFont("TBH.Small")
                self.FindEntry:SetPlaceholderText("find...")
                self.FindEntry.OnEnter = function() self:FindNext() end
                FS.Button(self.FindBar, "Next", 60, function() self:FindNext() end):DockMargin(6, 0, 6, 0)

                self.Entry = vgui.Create("DTextEntry", self)
                self.Entry:Dock(FILL)
                self.Entry:SetMultiline(true)
                self.Entry:SetFont("TBH.Code")
                self.Entry:SetUpdateOnType(true)
                self.Entry:SetEnterAllowed(true)
                if self.Entry.SetMaximumCharCount then self.Entry:SetMaximumCharCount(MAX_EDIT + 20000) end

                self.Entry.Paint = function(e, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(12, 15, 13))
                    e:DrawTextEntryText(TBH.Colors.text, TBH.Colors.accent, TBH.Colors.tag)
                end

                local oldKey = self.Entry.OnKeyCodeTyped
                self.Entry.OnKeyCodeTyped = function(e, code)
                    if input.IsControlDown() then
                        if code == KEY_S then self:Save() return true end
                        if code == KEY_F then self:ToggleFind(true) return true end
                    end

                    if code == KEY_TAB and not self.ReadOnly then
                        local text = e:GetText()
                        local pos = e:GetCaretPos()
                        e:SetText(string_sub(text, 1, pos) .. "    " .. string_sub(text, pos + 1))
                        e:SetCaretPos(pos + 4)
                        self:OnEdited()
                        return true
                    end

                    if oldKey then return oldKey(e, code) end
                end

                self.Entry.OnChange = function() self:OnEdited() end
            end

            function ED:SetStatus(msg, level)
                self.Status = msg or ""
                self.StatusLevel = level or 0
            end

            function ED:IsDirty() return self.Dirty end

            function ED:Think()
                if not IsValid(self.Entry) then return end
                if (self.NextPos or 0) > CurTime() then return end
                self.NextPos = CurTime() + 0.2

                local text = self.Entry:GetText()
                local okC, caret = pcall(self.Entry.GetCaretPos, self.Entry)
                if okC and isnumber(caret) then
                    local before = string_sub(text, 1, caret)
                    local _, lines = string_gsub(before, "\n", "")
                    local col = #before - (string_find(before, "\n[^\n]*$") or 0)
                    self.PosText = "Ln " .. (lines + 1) .. ", Col " .. (col + 1) .. "   |   " .. #text .. " chars"
                else
                    self.PosText = #text .. " chars"
                end
            end

            -- info = { path, id, name, ext, root, writable, inner, addon }
            function ED:Load(info)
                self.Info = info
                self.IsLua = (info.ext == "lua") or (string_sub(string.lower(info.name or ""), -8) == ".lua.txt") -- saved edits are stored as .lua.txt
                self.IsVMT = info.ext == "vmt"

                local size = file.Size(info.path, info.id) or 0
                local raw = file.Read(info.path, info.id)

                if not isstring(raw) then
                    self.Entry:SetText("")
                    self.Entry:SetEditable(false)
                    self.ReadOnly = true
                    self:SetStatus("Could not read " .. info.path, 2)
                    return
                end

                self.Original = raw
                self.EditPath = nil

                if not info.writable then
                    local relName = (info.root == "addons") and (string_gsub(info.path, "^addons/", "")) or ((info.tag or "addon") .. "/" .. info.path)
                    self.EditPath = FS.WritablePath(FS.DataDir .. "/edits/" .. FS.SafeName(relName))
                end

                self.OutPath = info.writable and FS.WritablePath(info.path) or self.EditPath

                local shown = raw
                local note = ""
                if self.EditPath and file.Exists(self.EditPath, "DATA") then
                    local saved = file.Read(self.EditPath, "DATA")
                    if isstring(saved) then
                        shown = saved
                        note = "  -  showing your saved edit (Original button = the addon's file)"
                    end
                end

                self.SavedShown = (note ~= "")
                self.BtnOrig:SetVisible(self.SavedShown)

                self.ReadOnly = size > MAX_EDIT
                self.Entry:SetText(self.ReadOnly and string_sub(shown, 1, MAX_EDIT) or shown)
                self.Entry:SetEditable(not self.ReadOnly)

                if self.ReadOnly then
                    self:SetStatus("File is " .. FS.FormatSize(size) .. " - too big for the editor, showing the first " .. FS.FormatSize(MAX_EDIT) .. " read-only", 3)
                elseif #self.Entry:GetText() ~= #shown then
                    -- the text box cut something off: never allow saving that
                    self.ReadOnly = true
                    self.Entry:SetEditable(false)
                    self:SetStatus("The text box could not hold the whole file - opened read-only", 3)
                else
                    local where = info.writable and ("saves to data/" .. self.OutPath)
                        or ("addon file - SAVE writes a copy to data/" .. self.EditPath)
                    self:SetStatus(where .. note, 0)
                end

                self.Dirty = false
                self.BtnSave:SetEnabled(not self.ReadOnly)
                self.BtnRun:SetVisible(self.IsLua)
                self.BtnSrv:SetVisible(self.IsLua)
                self.TglLive:SetVisible(self.IsLua or self.IsVMT)
                self.TglSave:SetText(self.IsVMT and "Apply on save" or "Run on save")
                self.TglSave:SetVisible(self.IsLua or self.IsVMT)
                self.TglSave:SetWide(self.IsVMT and 100 or 90)

                if self.IsLua or self.IsVMT then self:Check() end
            end

            function ED:LoadOriginal()
                if not self.Original then return end
                self.Entry:SetText(self.Original)
                self.Dirty = true
                self:SetStatus("Original text loaded (not saved yet)", 3)
            end

            function ED:LuaRel()
                local inner = self.Info.inner
                return inner and string_match(inner, "^lua/(.+)$") or nil
            end

            function ED:MatRel()
                local inner = self.Info.inner
                return inner and string_match(inner, "^materials/(.+)%.vmt$") or nil
            end

            -- compile check (lua only) so errors show while you type
            function ED:Check()
                if not self.IsLua then return true end
                local code = self.Entry:GetText()
                local fn = CompileString(code, "hotloader_fs", false)

                if isstring(fn) then
                    self:SetStatus(fn, 2)
                    return false, fn
                end

                self:SetStatus("syntax OK", 1)
                return true
            end

            function ED:OnEdited()
                self.Dirty = true
                if (self.IsLua or self.IsVMT) then
                    timer.Create(self.HookId .. "c", 0.35, 1, function()
                        if IsValid(self) then
                            self:Check()
                            if self.TglLive.On then self:ApplyNow(true) end
                        end
                    end)
                end
            end

            function ED:ScheduleLive()
                if IsValid(self) and self.TglLive.On then self:ApplyNow(true) end
            end

            function ED:Save()
                if self.ReadOnly then FS.Notify("This file is open read-only", 3) return end

                local info = self.Info
                local text = self.Entry:GetText()
                local out = self.OutPath

                local dir = string_match(out, "^(.*)/[^/]+$")
                if dir then FS.EnsureDir(dir) end

                file.Write(out, text)
                self.Dirty = false

                if file.Exists(out, "DATA") then
                    local hint = ""
                    if (self.IsLua or self.IsVMT) and not self.TglSave.On then
                        hint = self.IsLua and "  (saved only - RUN CLIENT / RUN SERVER to execute)" or "  (saved only)"
                    end
                    self:SetStatus("Saved -> data/" .. out .. hint, 1)
                    self.BtnOrig:SetVisible(not info.writable)
                else
                    self:SetStatus("Save FAILED: could not write data/" .. out, 2)
                    return
                end

                if self.TglSave.On and (self.IsLua or self.IsVMT) then self:ApplyNow(false) end
            end

            -- run (lua) / apply (vmt) on this client
            function ED:ApplyNow(quiet)
                local text = self.Entry:GetText()

                if self.IsVMT then
                    local matRel = self:MatRel()
                    if not matRel then
                        if not quiet then self:SetStatus("Only .vmt files under addons/<name>/materials can be applied live", 3) end
                        return
                    end

                    local ok, msg = FS.ApplyVMT(matRel, text)
                    self:SetStatus(msg, ok and 1 or 2)
                    return
                end

                self:Run("client", quiet)
            end

            function ED:Run(realm, quiet)
                if not self.IsLua then return end

                local okSyntax, err = self:Check()
                if not okSyntax then return end

                local text = self.Entry:GetText()
                local rel = self:LuaRel()

                if realm == "server" then
                    if not rel then
                        self:SetStatus("Only files under addons/<name>/lua/ can be sent to the server", 3)
                        return
                    end

                    local ok, msg = FS.SendToServer(rel, text)
                    self:SetStatus(msg, ok and 0 or 2)
                    return
                end

                local ok, msg = TBH.FS.RunLua(rel or ("data/" .. self.Info.path), text)
                self:SetStatus((ok and "CLIENT: " or "CLIENT ERROR: ") .. tostring(msg), ok and 1 or 2)
            end

            function ED:ToggleFind(show)
                local vis = (show ~= nil) and show or not self.FindBar:IsVisible()
                self.FindBar:SetVisible(vis)
                self:InvalidateLayout(true)
                if vis then
                    self.FindEntry:RequestFocus()
                else
                    self.Entry:RequestFocus()
                end
            end

            function ED:FindNext()
                local term = self.FindEntry:GetText()
                if term == "" then return end

                local text = self.Entry:GetText()
                local okC, caret = pcall(self.Entry.GetCaretPos, self.Entry)
                caret = (okC and caret) or 0

                local pos = string_find(text, term, caret + 1, true) or string_find(text, term, 1, true)
                if not pos then
                    self:SetStatus("'" .. term .. "' not found", 3)
                    return
                end

                local before = string_sub(text, 1, pos)
                local _, lines = string_gsub(before, "\n", "")
                self.Entry:RequestFocus()
                self.Entry:SetCaretPos(pos - 1 + #term)
                self:SetStatus("'" .. term .. "' found on line " .. (lines + 1), 1)
            end

            function ED:OnRemove()
                timer.Remove(self.HookId .. "c")
            end

            vgui.Register("TBH.FSEditor", ED, "EditablePanel")
        end

        ----------------------------------------------------------------------
        -- AUDIO PLAYER
        ----------------------------------------------------------------------
        do
            local AU = {}

            function AU:Init()
                self.Volume = 0.8
                self.Pitch = 1
                self.Loop = false
                self.Status = "loading..."
                self.FFTData = {}
                self.Bars = {}

                local bar = FS.Toolbar(self, 44)
                bar:DockMargin(0, 0, 0, 6)
                bar:DockPadding(8, 7, 8, 7)

                self.BtnPlay = FS.Button(bar, "PLAY", 70, function() self:TogglePlay() end, true)
                FS.Button(bar, "STOP", 60, function() self:StopPlayback(true) end)
                FS.Button(bar, "< Prev", 60, function() if self.OnStep then self.OnStep(-1) end end)
                FS.Button(bar, "Next >", 60, function() if self.OnStep then self.OnStep(1) end end)
                self.TglLoop = FS.Toggle(bar, "Loop", 55, false, function(on)
                    self.Loop = on
                    if IsValid(self.Channel) then pcall(self.Channel.EnableLooping, self.Channel, on) end
                end)

                local bar2 = FS.Toolbar(self, 36)
                self.BtnGlobal = FS.Button(bar2, "GLOBAL PLAY", 110, function() self:GlobalPlay() end, true)
                self.BtnGlobal:SetTooltip("Plays this sound for EVERYONE on the server (with your volume + pitch). Players need the same file, e.g. the same addon")
                FS.Button(bar2, "STOP GLOBAL", 100, function() FS.GlobalStop() end)

                self.Seek = vgui.Create("TBH.FSSlider", self)
                self.Seek:Dock(TOP)
                self.Seek:SetTall(22)
                self.Seek:DockMargin(8, 8, 8, 0)
                self.Seek.OnValue = function(_, v)
                    if IsValid(self.Channel) then pcall(self.Channel.SetTime, self.Channel, v) end
                end

                local function SliderRow(label, min, max, value, fmt, onValue, step)
                    local row = vgui.Create("DPanel", self)
                    row:Dock(TOP)
                    row:SetTall(26)
                    row:DockMargin(8, 4, 8, 0)
                    row.Paint = function(_, w, h)
                        draw.SimpleText(label, "TBH.Small", 0, h / 2, TBH.Colors.textdim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText(fmt(row.Slider:GetValue()), "TBH.Small", w - 40, h / 2, TBH.Colors.textdim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    end

                    local reset = vgui.Create("DButton", row)
                    reset:Dock(RIGHT)
                    reset:SetWide(34)
                    reset:DockMargin(0, 2, 0, 2)
                    reset:SetText("")
                    reset:SetTooltip("reset")
                    reset.Paint = function(btn, w, h)
                        draw.RoundedBox(4, 0, 0, w, h, btn:IsHovered() and TBH.Colors.outline or TBH.Colors.bgPanel2)
                        draw.SimpleText("R", "TBH.Small", w / 2, h / 2, TBH.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end

                    local sl = vgui.Create("TBH.FSSlider", row)
                    sl:Dock(FILL)
                    sl:DockMargin(60, 2, 96, 2)
                    sl:SetRange(min, max)
                    sl.Step = step
                    sl:SetValue(value)
                    sl.OnValue = function(_, v) onValue(v) end
                    row.Slider = sl

                    reset.DoClick = function()
                        sl:SetValue(value)
                        onValue(value)
                    end
                    return row
                end

                SliderRow("Volume", 0, 1, self.Volume, function(v) return math.floor(v * 100 + 0.5) .. "%" end, function(v)
                    self.Volume = v
                    if IsValid(self.Channel) then pcall(self.Channel.SetVolume, self.Channel, v) end
                end)

                SliderRow("Pitch", 0.25, 2, 1, function(v) return string.format("%.2fx", v) end, function(v)
                    self.Pitch = v
                    if IsValid(self.Channel) then pcall(self.Channel.SetPlaybackRate, self.Channel, v) end
                end, 0.01)
            end

            function AU:Load(info)
                self.Info = info

                local candidates = {}
                if info.root == "data" then
                    candidates[#candidates + 1] = "data/" .. info.path
                else
                    candidates[#candidates + 1] = info.path
                    if info.inner and info.inner ~= info.path then candidates[#candidates + 1] = info.inner end -- "sound/..." through the search paths
                end

                self:TryPlay(candidates, 1)
            end

            function AU:TryPlay(list, i)
                local path = list[i]

                if not path then
                    self.Status = "Could not stream this file (unsupported format, or it lives inside a mounted GMA)"
                    self.CanFallback = true
                    return
                end

                sound.PlayFile(path, "noplay", function(ch, errCode, errName)
                    if not IsValid(self) then
                        if IsValid(ch) then ch:Stop() end
                        return
                    end

                    if IsValid(ch) then
                        self.Channel = ch
                        pcall(ch.SetVolume, ch, self.Volume)
                        pcall(ch.SetPlaybackRate, ch, self.Pitch)
                        pcall(ch.EnableLooping, ch, self.Loop)
                        self.Length = ch:GetLength() or 0
                        self.Seek:SetRange(0, math.max(self.Length, 0.01))
                        self.Status = "ready  -  " .. path
                        ch:Play()
                    else
                        self:TryPlay(list, i + 1)
                    end
                end)
            end

            function AU:GlobalPlay()
                local inner = self.Info and self.Info.inner
                if not inner or string_sub(inner, 1, 6) ~= "sound/" then
                    FS.Notify("Global play needs a file in a sound/ folder of an addon (files in your data folder only exist on your PC)", 3)
                    return
                end

                FS.GlobalPlay(inner, self.Volume, self.Pitch)
                self.Status = "sent to the server - playing for everyone"
            end

            function AU:TogglePlay()
                local ch = self.Channel

                if not IsValid(ch) then
                    if self.CanFallback and self.Info and self.Info.inner then
                        surface.PlaySound(string_sub(self.Info.inner, 7)) -- fire and forget, no controls
                    end
                    return
                end

                if ch:GetState() == GMOD_CHANNEL_PLAYING then ch:Pause() else ch:Play() end
            end

            function AU:StopPlayback(rewind)
                if IsValid(self.Channel) then
                    self.Channel:Pause()
                    if rewind then pcall(self.Channel.SetTime, self.Channel, 0) end
                end
            end

            function AU:Think()
                local ch = self.Channel
                if not IsValid(ch) then return end

                self.BtnPlay:SetText(ch:GetState() == GMOD_CHANNEL_PLAYING and "PAUSE" or "PLAY")

                if not self.Seek.Drag then
                    self.Seek:SetValue(ch:GetTime() or 0)
                end
            end

            function AU:Paint(w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)

                local y0 = 196
                local name = self.Info and self.Info.name or ""
                draw.SimpleText(name, "TBH.Header", 16, y0, TBH.Colors.tag)

                local ch = self.Channel
                local cur, len = 0, self.Length or 0
                if IsValid(ch) then cur = ch:GetTime() or 0 end

                local function fmt(t) return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60)) end
                draw.SimpleText(fmt(cur) .. " / " .. fmt(len), "TBH.Body", w - 16, y0 + 4, TBH.Colors.text, TEXT_ALIGN_RIGHT)
                draw.SimpleText(self.Status, "TBH.Small", 16, y0 + 28, TBH.Colors.textdim)

                -- spectrum
                local top = y0 + 58
                local areaH = h - top - 16
                if areaH < 20 then return end

                draw.RoundedBox(6, 12, top, w - 24, areaH, TBH.Colors.bg)

                if IsValid(ch) and ch:GetState() == GMOD_CHANNEL_PLAYING then
                    local okF = pcall(ch.FFT, ch, self.FFTData, FFT_512)
                    if okF then
                        for b = 1, 64 do
                            local sum = 0
                            for k = 0, 3 do sum = sum + (self.FFTData[(b - 1) * 2 + k + 1] or 0) end
                            local target = math.min(1, (sum / 4) * 6)
                            self.Bars[b] = Lerp(FrameTime() * 14, self.Bars[b] or 0, target)
                        end
                    end
                else
                    for b = 1, 64 do self.Bars[b] = Lerp(FrameTime() * 8, self.Bars[b] or 0, 0) end
                end

                local bw = (w - 40) / 64
                for b = 1, 64 do
                    local bh = math.max(2, (self.Bars[b] or 0) * (areaH - 12))
                    draw.RoundedBox(2, 20 + (b - 1) * bw, top + areaH - 6 - bh, bw - 2, bh, TBH.Colors.accent)
                end
            end

            function AU:OnRemove()
                if IsValid(self.Channel) then self.Channel:Stop() end
            end

            vgui.Register("TBH.FSAudio", AU, "EditablePanel")
        end

        ----------------------------------------------------------------------
        -- IMAGE VIEWER + PAINTER (.vtf .png .jpg)
        --
        -- painting goes into a render target, strokes are kept as a list so UNDO just
        -- replays them. LIVE APPLY swaps the real in-game material's $basetexture to
        -- that render target, so everything using the material changes immediately.
        -- SAVE PNG writes data/hotloader_fs/paint/<material>.png (and data/<file> in
        -- place when you opened a png from the DATA root). saved paints are
        -- re-applied automatically on join (hotloader_fs_autoapply)
        ----------------------------------------------------------------------
        do
            local IMG = {}
            local MAX_RT = 4096

            function IMG:Init()
                self.Zoom = 1
                self.OX, self.OY = 0, 0
                self.Mode = "view"
                self.Tool = "brush"
                self.Strokes = {}
                self.Queue = {}
                self.BrushSize = 12
                self.BrushColor = Color(255, 60, 60, 255)
                self.Status = ""
                self.StatusLevel = 0

                self.Bar = FS.Toolbar(self, 36)
                self.Bar:DockMargin(0, 0, 0, 6)

                self.BtnView = FS.Button(self.Bar, "VIEW", 60, function() self:SetMode("view") end)
                self.BtnPaint = FS.Button(self.Bar, "PAINT", 60, function() self:SetMode("paint") end)
                FS.Button(self.Bar, "Fit", 40, function() self:Fit() end)
                FS.Button(self.Bar, "1:1", 40, function() self:SetZoom(1) end)
                self.BtnView.Active = true

                self.Foot = vgui.Create("DPanel", self)
                self.Foot:Dock(BOTTOM)
                self.Foot:SetTall(24)
                self.Foot:DockMargin(0, 6, 0, 0)
                self.Foot.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel)
                    local col = TBH.Colors.textdim
                    if self.StatusLevel == 1 then col = TBH.Colors.ok
                    elseif self.StatusLevel == 2 then col = TBH.Colors.error
                    elseif self.StatusLevel == 3 then col = TBH.Colors.warn end
                    local right = self.InfoText or ""
                    surface.SetFont("TBH.Small")
                    local rw = surface.GetTextSize(right)

                    draw.SimpleText(right, "TBH.Small", w - 10, h / 2, TBH.Colors.textdim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(FS.Fit("TBH.Small", self.Status, w - rw - 40), "TBH.Small", 10, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                    if self.TipFor ~= self.Status then
                        self.TipFor = self.Status
                        self.Foot:SetTooltip(self.Status ~= "" and self.Status or nil)
                    end
                end

                self.Side = vgui.Create("DScrollPanel", self)
                self.Side:Dock(RIGHT)
                self.Side:SetWide(196)
                self.Side:DockMargin(6, 0, 0, 0)
                self.Side:SetVisible(false)
                self.Side.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel) end

                self:BuildSide()

                self.Canvas = vgui.Create("DPanel", self)
                self.Canvas:Dock(FILL)
                self.Canvas:SetCursor("crosshair")
                self.Canvas.Paint = function(c, w, h) self:PaintCanvas(c, w, h) end
                self.Canvas.OnMousePressed = function(c, code) self:CanvasPressed(code) end
                self.Canvas.OnMouseReleased = function(c, code) self:CanvasReleased(code) end
                self.Canvas.OnMouseWheeled = function(c, delta) self:CanvasWheel(delta) end
                self.Canvas.OnCursorMoved = function(c, x, y) self:CanvasMoved(x, y) end
                self.Canvas.OnCursorExited = function() self.Hover = nil end
            end

            function IMG:SetStatus(msg, level)
                self.Status = msg or ""
                self.StatusLevel = level or 0
            end

            function IMG:BuildSide()
                local side = self.Side

                local function Label(text)
                    local l = vgui.Create("DLabel", side)
                    l:Dock(TOP)
                    l:SetTall(20)
                    l:DockMargin(8, 8, 8, 0)
                    l:SetFont("TBH.Small")
                    l:SetTextColor(TBH.Colors.tag)
                    l:SetText(text)
                    return l
                end

                local function Row()
                    local r = vgui.Create("DPanel", side)
                    r:Dock(TOP)
                    r:SetTall(28)
                    r:DockMargin(8, 4, 2, 0)
                    r.Paint = nil
                    return r
                end

                Label("TOOL")
                self.ToolButtons = {}
                local tools = { { "brush", "Brush" }, { "line", "Line" }, { "rect", "Rect" }, { "restore", "Restore" }, { "pick", "Pick" } }
                local row
                for i, t in ipairs(tools) do
                    if (i - 1) % 2 == 0 then row = Row() end
                    local b = FS.Button(row, t[2], 80, function() self:SetTool(t[1]) end)
                    self.ToolButtons[t[1]] = b
                end
                self:SetTool("brush")

                Label("COLOR")
                self.Mixer = vgui.Create("DColorMixer", side)
                self.Mixer:Dock(TOP)
                self.Mixer:SetTall(150)
                self.Mixer:DockMargin(8, 4, 8, 0)
                self.Mixer:SetPalette(false)
                self.Mixer:SetAlphaBar(true)
                self.Mixer:SetWangs(false)
                self.Mixer:SetColor(self.BrushColor)
                self.Mixer.ValueChanged = function(_, col) self.BrushColor = Color(col.r, col.g, col.b, col.a) end

                Label("SIZE")
                local sz = vgui.Create("TBH.FSSlider", side)
                sz:Dock(TOP)
                sz:SetTall(20)
                sz:DockMargin(8, 4, 8, 0)
                sz:SetRange(1, 128)
                sz.Step = 1
                sz:SetValue(self.BrushSize)
                sz.OnValue = function(_, v) self.BrushSize = v end

                Label("EDIT")
                local r1 = Row()
                FS.Button(r1, "Undo", 80, function() self:Undo() end)
                FS.Button(r1, "Reset", 80, function() self:ResetPaint() end)

                Label("IN-GAME MATERIAL")
                self.LiveRow = Row()
                self.LiveBtn = FS.Toggle(self.LiveRow, "Live apply", 168, false, function(on) self:SetLive(on) end)

                local r2 = Row()
                self.BtnSavePNG = FS.Button(r2, "SAVE PNG", 80, function() self:SavePNG() end, true)
                self.BtnSaveVTF = FS.Button(r2, "SAVE VTF", 80, function() self:SaveVTF() end, true)
                self.BtnSaveVTF:SetTooltip("writes a real .vtf into data/hotloader_fs/export/<addon>/materials/... - copy that folder over the addon's files")

                local r3 = Row()
                self.BtnLoadSaved = FS.Button(r3, "Load saved", 80, function() self:LoadSaved() end)
                self.BtnForget = FS.Button(r3, "Forget", 80, function() self:ForgetSaved() end)
            end

            function IMG:SetTool(name)
                self.Tool = name
                for k, b in pairs(self.ToolButtons or {}) do b.Active = (k == name) end
            end

            -- info = { path, id, name, ext, root, writable, inner }
            function IMG:Load(info)
                self.Info = info
                FS.Counter = FS.Counter + 1

                self.MatRel = nil
                if info.inner then
                    self.MatRel = string_match(info.inner, "^materials/(.+)%.[%w]+$")
                end

                self.IsVTF = (info.ext == "vtf")
                local base = self.MatRel

                if self.IsVTF and base then
                    self.Mat = CreateMaterial("hlfs_view_" .. FS.Counter, "UnlitGeneric", {
                        ["$basetexture"] = base, ["$translucent"] = 1, ["$vertexalpha"] = 1,
                        ["$vertexcolor"] = 1, ["$nolod"] = 1, ["$pointsamplemagfilter"] = 1,
                    })
                elseif info.root ~= "data" and base then
                    self.Mat = Material(base .. "." .. info.ext, "smooth")
                elseif info.root == "data" then
                    self.Mat = Material("../data/" .. info.path, "smooth")
                end

                if not self.Mat or self.Mat:IsError() then
                    self.Mat = nil
                    self:SetStatus("Could not load this image (" .. info.path .. ")", 2)
                    return
                end

                local tex = self.Mat:GetTexture("$basetexture")
                local w = (tex and not tex:IsError() and tex:Width()) or self.Mat:Width()
                local h = (tex and not tex:IsError() and tex:Height()) or self.Mat:Height()
                self.W, self.H = math.max(1, w or 1), math.max(1, h or 1)

                if tex and tex:IsError() then
                    self:SetStatus("The engine could not load this texture (shows as the error texture)", 3)
                end

                self.InfoText = self.W .. " x " .. self.H .. "  -  " .. FS.FormatSize(file.Size(info.path, info.id))

                -- target material for live apply: the sibling .vmt of a vtf
                self.TargetKey = nil
                if self.MatRel and (info.ext == "vtf" or info.ext == "vmt") then
                    if file.Exists("materials/" .. self.MatRel .. ".vmt", "GAME") then
                        self.TargetKey = self.MatRel
                    end
                end

                self.SavePath = nil
                if info.writable and info.ext == "png" then
                    self.PNGOut = info.path -- DATA root: in place
                else
                    self.PNGOut = FS.PaintPath(self.MatRel or string_gsub(info.path, "^addons/", ""))
                end

                -- restore this file's strokes from earlier in the session
                local key = self.TargetKey or info.path
                self.StateKey = key
                local state = FS.PaintState[key]
                if state then
                    self.Strokes = state.strokes
                end

                self:RefreshButtons()
                self:Fit()
                self:SetStatus(self.TargetKey and ("in-game material: " .. self.TargetKey) or "view only - live apply needs a .vmt next to the .vtf", 0)

                if state and (#state.strokes > 0 or state.live) then
                    self:SetMode("paint")
                    if state.live then self.LiveBtn.On = true self.LiveBtn.Active = true end
                end
            end

            function IMG:RefreshButtons()
                local saved = file.Exists(self.PNGOut or "", "DATA")
                self.BtnLoadSaved:SetEnabled(saved and self.TargetKey ~= nil)
                self.BtnForget:SetEnabled(self.TargetKey ~= nil and (saved or FS.Applied[self.TargetKey] ~= nil))
                self.LiveBtn:SetEnabled(self.TargetKey ~= nil)
                self.LiveBtn:SetTooltip(self.TargetKey and "swap the real material's texture for your painting, live" or "needs a .vmt with the same name next to the .vtf")
            end

            ----------------------------------------------------------------------
            -- view transform
            ----------------------------------------------------------------------
            function IMG:Fit()
                if not self.W then return end
                local cw, ch = self.Canvas:GetSize()
                if cw < 10 or ch < 10 then
                    -- not laid out yet
                    timer.Simple(0, function() if IsValid(self) then self:Fit() end end)
                    return
                end
                local z = math.min((cw - 20) / self.W, (ch - 20) / self.H)
                self.Zoom = math.Clamp(z, 0.05, 32)
                self.OX = (cw - self.W * self.Zoom) / 2
                self.OY = (ch - self.H * self.Zoom) / 2
            end

            function IMG:SetZoom(z)
                local cw, ch = self.Canvas:GetSize()
                local cx, cy = (cw / 2 - self.OX) / self.Zoom, (ch / 2 - self.OY) / self.Zoom
                self.Zoom = math.Clamp(z, 0.05, 32)
                self.OX = cw / 2 - cx * self.Zoom
                self.OY = ch / 2 - cy * self.Zoom
            end

            function IMG:ToImage(lx, ly)
                return (lx - self.OX) / self.Zoom, (ly - self.OY) / self.Zoom
            end

            function IMG:CanvasWheel(delta)
                if not self.W then return end
                local lx, ly = self.Canvas:CursorPos()
                local ix, iy = self:ToImage(lx, ly)
                self.Zoom = math.Clamp(self.Zoom * (1.18 ^ delta), 0.05, 32)
                self.OX = lx - ix * self.Zoom
                self.OY = ly - iy * self.Zoom
            end

            ----------------------------------------------------------------------
            -- mouse
            ----------------------------------------------------------------------
            function IMG:CanvasPressed(code)
                if not self.W then return end
                local lx, ly = self.Canvas:CursorPos()

                local panning = (code == MOUSE_MIDDLE) or (code == MOUSE_RIGHT) or (self.Mode == "view" and code == MOUSE_LEFT)
                if panning then
                    self.Pan = { lx = lx, ly = ly, ox = self.OX, oy = self.OY }
                    self.Canvas:MouseCapture(true)
                    return
                end

                if code ~= MOUSE_LEFT or self.Mode ~= "paint" or not self.RT then return end

                local ix, iy = self:ToImage(lx, ly)

                if self.Tool == "pick" then
                    self.PickAt = { math.floor(ix), math.floor(iy) }
                    return
                end

                local c = self.BrushColor
                local stroke = {
                    tool = (self.Tool == "rect") and "rect" or (self.Tool == "restore" and "restore" or "brush"),
                    r = c.r, g = c.g, b = c.b, a = c.a, size = self.BrushSize, pts = { ix, iy }, done = 0,
                }

                self.Drawing = stroke
                self.DrawKind = self.Tool
                self.StartPt = { ix, iy }
                self.Canvas:MouseCapture(true)

                if self.Tool == "brush" or self.Tool == "restore" then
                    self.Strokes[#self.Strokes + 1] = stroke
                    self.Queue[#self.Queue + 1] = stroke
                end
            end

            function IMG:CanvasMoved(x, y)
                self.Hover = { x, y }

                if self.Pan then
                    local lx, ly = self.Canvas:CursorPos()
                    self.OX = self.Pan.ox + (lx - self.Pan.lx)
                    self.OY = self.Pan.oy + (ly - self.Pan.ly)
                    return
                end

                local s = self.Drawing
                if not s then return end

                local ix, iy = self:ToImage(x, y)

                if self.DrawKind == "brush" or self.DrawKind == "restore" then
                    local pts = s.pts
                    local n = #pts
                    if math.abs(pts[n - 1] - ix) >= 0.5 or math.abs(pts[n] - iy) >= 0.5 then
                        pts[n + 1] = ix
                        pts[n + 2] = iy
                    end
                else
                    -- line / rect: only the end point moves (previewed in the overlay)
                    s.pts[3] = ix
                    s.pts[4] = iy
                end
            end

            function IMG:CanvasReleased(code)
                if self.Pan then
                    self.Pan = nil
                    self.Canvas:MouseCapture(false)
                    return
                end

                local s = self.Drawing
                if not s then return end

                self.Drawing = nil
                self.Canvas:MouseCapture(false)

                if self.DrawKind == "line" or self.DrawKind == "rect" then
                    if s.pts[3] then
                        self.Strokes[#self.Strokes + 1] = s
                        self.Queue[#self.Queue + 1] = s
                    end
                end

                self:StoreState()
            end

            function IMG:StoreState()
                FS.PaintState[self.StateKey or "?"] = { strokes = self.Strokes, live = self.LiveBtn.On }
            end

            ----------------------------------------------------------------------
            -- modes + render target
            ----------------------------------------------------------------------
            function IMG:SetMode(mode)
                if mode == "paint" then
                    if not self.Mat then return end
                    if not self:EnsureRT() then return end
                end

                self.Mode = mode
                self.BtnView.Active = (mode == "view")
                self.BtnPaint.Active = (mode == "paint")
                self.Side:SetVisible(mode == "paint")
                self.Canvas:SetCursor(mode == "paint" and "crosshair" or "sizeall")
                self:InvalidateLayout(true)
                self:RefreshButtons()
            end

            function IMG:EnsureRT()
                if self.RT then return true end

                if self.W > MAX_RT or self.H > MAX_RT then
                    self:SetStatus("Image is bigger than " .. MAX_RT .. "px - painting is disabled for it", 3)
                    return false
                end

                local name = "hlfs_rt_" .. util.CRC((self.StateKey or "x") .. self.W .. "x" .. self.H)
                local okRT, rt = pcall(GetRenderTargetEx, name, self.W, self.H, RT_SIZE_LITERAL,
                    MATERIAL_RT_DEPTH_NONE, 4 + 8 + 256, 0, IMAGE_FORMAT_RGBA8888)

                if not okRT or not rt then
                    self:SetStatus("Could not create a render target for this size", 2)
                    return false
                end

                self.RT = rt
                self.RTMat = CreateMaterial("hlfs_rtmat_" .. FS.Counter .. "_" .. name, "UnlitGeneric", {
                    ["$basetexture"] = rt:GetName(), ["$translucent"] = 1, ["$vertexalpha"] = 1,
                    ["$vertexcolor"] = 1, ["$nolod"] = 1, ["$pointsamplemagfilter"] = 1,
                })

                self.BaseMat = self.Mat
                self.NeedFull = true
                FS.ActiveImage = self
                return true
            end

            function IMG:Undo()
                if #self.Strokes == 0 then return end
                table.remove(self.Strokes)
                self.NeedFull = true
                self:StoreState()
            end

            function IMG:ResetPaint()
                self.Strokes = {}
                self.BaseMat = self.Mat
                self.NeedFull = true
                self:StoreState()
                self:SetStatus("Painting reset to the original texture", 0)
            end

            function IMG:SetLive(on)
                if not self.TargetKey then return end

                if on then
                    if not self.RT then
                        if not self:EnsureRT() then self.LiveBtn.On = false self.LiveBtn.Active = false return end
                    end
                    local ok, err = FS.ApplyTexture(self.TargetKey, self.RT)
                    if not ok then
                        self.LiveBtn.On = false
                        self.LiveBtn.Active = false
                        self:SetStatus(err, 2)
                        return
                    end
                    self:SetStatus("LIVE: '" .. self.TargetKey .. "' now shows your painting everywhere it is used", 1)
                else
                    FS.RestoreTexture(self.TargetKey)
                    self:SetStatus("Original texture put back on '" .. self.TargetKey .. "'", 0)
                end

                self:StoreState()
                self:RefreshButtons()
            end

            function IMG:SavePNG()
                if not self.RT then self:SetStatus("Switch to PAINT first", 3) return end
                self.SavePending = true
                self:SetStatus("Saving...", 0)
            end

            function IMG:SaveVTF()
                if not self.RT then self:SetStatus("Switch to PAINT first", 3) return end
                if self.VTF then return end

                local info = self.Info
                local out
                if self.MatRel then
                    out = FS.DataDir .. "/export/" .. FS.SafeName(info.addon or info.tag or "addon") .. "/materials/" .. FS.SafeName(self.MatRel) .. ".vtf"
                else
                    out = FS.DataDir .. "/vtf/" .. FS.SafeName((string_gsub(info.path, "%.[%w]+$", ""))) .. ".vtf"
                end

                self.VTF = { y = 0, parts = {}, out = out }
                self:SetStatus("Exporting VTF...", 0)
            end

            -- reads a few rows of the render target per frame (runs inside the RT context)
            function IMG:StepVTF()
                local v = self.VTF
                local W, H = self.W, self.H

                render.CapturePixels()
                local rows = math.max(1, math.floor(150000 / W))
                local last = math.min(H, v.y + rows)

                for y = v.y, last - 1 do
                    local t, n = {}, 0
                    for x = 0, W - 1 do
                        local r, g, b, a = render.ReadPixel(x, y)
                        t[n + 1] = r or 0 t[n + 2] = g or 0 t[n + 3] = b or 0 t[n + 4] = a or 255
                        n = n + 4
                    end

                    local parts = {}
                    for i = 1, n, 4000 do
                        parts[#parts + 1] = string.char(unpack(t, i, math.min(n, i + 3999)))
                    end
                    v.parts[#v.parts + 1] = table.concat(parts)
                end

                v.y = last
                self:SetStatus(string.format("Exporting VTF... %d%%", math.floor(last / H * 100)), 0)

                if last >= H then
                    self.VTFDone = v
                    self.VTF = nil
                end
            end

            function IMG:FinishVTF()
                local v = self.VTFDone
                self.VTFDone = nil

                local function U16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
                local function U32(n)
                    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
                end

                local half = "\0\0\0\63"       -- 0.5f
                local one = "\0\0\128\63"      -- 1.0f

                -- VTF 7.2, one frame, no mipmaps, no thumbnail, RGBA8888 pixel data
                local header = "VTF\0" .. U32(7) .. U32(2) .. U32(80)
                    .. U16(self.W) .. U16(self.H) .. U32(0x2100) -- NOMIP + EIGHTBITALPHA
                    .. U16(1) .. U16(0) .. "\0\0\0\0"
                    .. half .. half .. half .. "\0\0\0\0"
                    .. one .. U32(0)      -- bumpmap scale, format 0 = RGBA8888
                    .. "\1" .. U32(0xFFFFFFFF) .. "\0\0" .. U16(1)
                header = header .. string.rep("\0", 80 - #header)

                local dir = string_match(v.out, "^(.*)/[^/]+$")
                if dir then FS.EnsureDir(dir) end

                file.Write(v.out, header .. table.concat(v.parts))

                if file.Exists(v.out, "DATA") then
                    self:SetStatus("VTF saved: garrysmod/data/" .. v.out .. "  (copy it into the addon to use it)", 1)
                else
                    self:SetStatus("Writing data/" .. v.out .. " failed", 2)
                end
            end

            function IMG:LoadSaved()
                local png = self.PNGOut
                if not (png and file.Exists(png, "DATA")) then return end

                local m = Material("../data/" .. png, "smooth")
                if not m or m:IsError() then self:SetStatus("Could not load the saved png", 2) return end

                if not self:EnsureRT() then return end
                self.Strokes = {}
                self.BaseMat = m
                self.NeedFull = true
                self:StoreState()
                self:SetStatus("Continuing from your saved painting", 1)
            end

            function IMG:ForgetSaved()
                if not self.TargetKey then return end

                FS.RestoreTexture(self.TargetKey)
                self.LiveBtn.On = false
                self.LiveBtn.Active = false

                local edits = FS.LoadEdits()
                local png = edits.paints[self.TargetKey]
                edits.paints[self.TargetKey] = nil
                FS.SaveEdits(edits)
                if png and file.Exists(png, "DATA") then file.Delete(png) end

                self:RefreshButtons()
                self:SetStatus("Saved painting removed, original texture restored", 1)
            end

            ----------------------------------------------------------------------
            -- render target work. runs from the PostRender hook (below), never from Paint
            ----------------------------------------------------------------------
            local function Dot(x, y, r, col)
                if r <= 1.5 then
                    surface.SetDrawColor(col)
                    surface.DrawRect(x - r, y - r, r * 2, r * 2)
                else
                    draw.RoundedBox(r, x - r, y - r, r * 2, r * 2, col)
                end
            end

            function IMG:DrawStrokePart(s)
                local pts = s.pts
                local n = math.floor(#pts / 2)
                local from = s.done or 0

                if s.tool == "rect" then
                    if n >= 2 and from < 2 then
                        local x1, y1, x2, y2 = pts[1], pts[2], pts[3], pts[4]
                        surface.SetDrawColor(s.r, s.g, s.b, s.a)
                        surface.DrawRect(math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1), math.abs(y2 - y1))
                        s.done = 2
                    end
                    return
                end

                local radius = math.max(0.5, s.size / 2)
                local col = Color(s.r, s.g, s.b, s.a)
                local restore = (s.tool == "restore")
                local step = math.max(1, s.size * (restore and 0.5 or 0.2))

                local function Stamp(x, y)
                    if restore then
                        render.SetScissorRect(x - radius, y - radius, x + radius, y + radius, true)
                        surface.SetMaterial(self.Mat)
                        surface.SetDrawColor(255, 255, 255, 255)
                        surface.DrawTexturedRect(0, 0, self.W, self.H)
                        render.SetScissorRect(0, 0, 0, 0, false)
                    else
                        Dot(x, y, radius, col)
                    end
                end

                for i = from + 1, n do
                    local x, y = pts[i * 2 - 1], pts[i * 2]

                    if i == 1 then
                        Stamp(x, y)
                    else
                        local px, py = pts[i * 2 - 3], pts[i * 2 - 2]
                        local dist = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
                        local count = math.max(1, math.ceil(dist / step))
                        for k = 1, count do
                            local t = k / count
                            Stamp(px + (x - px) * t, py + (y - py) * t)
                        end
                    end
                end

                s.done = n
            end

            function IMG:RenderOps()
                local w, h = self.W, self.H

                if self.NeedFull then
                    render.Clear(0, 0, 0, 0)
                    surface.SetMaterial(self.BaseMat or self.Mat)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(0, 0, w, h)

                    for _, s in ipairs(self.Strokes) do
                        s.done = 0
                        self:DrawStrokePart(s)
                    end

                    self.Queue = {}
                    self.NeedFull = false
                else
                    for _, s in ipairs(self.Queue) do self:DrawStrokePart(s) end

                    -- strokes that are still being drawn keep growing
                    local cur = self.Drawing
                    if cur and (self.DrawKind == "brush" or self.DrawKind == "restore") then
                        self:DrawStrokePart(cur)
                    end

                    -- a finished stroke is drawn once more only if it grew since
                    self.Queue = {}
                end
            end

            function IMG:ProcessRT()
                local needSave = self.SavePending
                local needPick = self.PickAt

                local busy = self.NeedFull or #self.Queue > 0 or needSave or needPick or self.VTF
                    or (self.Drawing and (self.DrawKind == "brush" or self.DrawKind == "restore"))
                if not busy then return end

                render.PushRenderTarget(self.RT)
                cam.Start2D()
                render.SetWriteDepthToDestAlpha(false)

                local ok, err = pcall(self.RenderOps, self)

                cam.End2D()

                if ok and self.VTF then
                    local okV, errV = pcall(self.StepVTF, self)
                    if not okV then
                        self.VTF = nil
                        self:SetStatus("VTF export failed: " .. tostring(errV), 2)
                    end
                end

                if ok and needPick then
                    local okP, r, g, b, a = pcall(function()
                        render.CapturePixels()
                        return render.ReadPixel(self.PickAt[1], self.PickAt[2])
                    end)
                    self.PickAt = nil
                    if okP and r then
                        self.BrushColor = Color(r, g, b, a or 255)
                        if IsValid(self.Mixer) then self.Mixer:SetColor(self.BrushColor) end
                        self:SetTool("brush")
                    end
                end

                local data
                if ok and needSave then
                    local okC, res = pcall(render.Capture, { format = "png", x = 0, y = 0, w = self.W, h = self.H, alpha = true })
                    if okC then data = res end
                    self.SavePending = nil
                end

                render.PopRenderTarget()

                if not ok then
                    self.Queue = {}
                    self.NeedFull = false
                    TBH.LogError("FS paint failed: " .. tostring(err))
                    self:SetStatus("Paint error: " .. tostring(err), 2)
                end

                if needSave then
                    self:FinishSave(data)
                end

                if self.VTFDone then self:FinishVTF() end
            end

            function IMG:FinishSave(data)
                if not isstring(data) or #data < 16 then
                    self:SetStatus("Could not capture the render target (render.Capture failed)", 2)
                    return
                end

                local out = self.PNGOut
                local dir = string_match(out, "^(.*)/[^/]+$")
                if dir then FS.EnsureDir(dir) end

                file.Write(out, data)
                if not file.Exists(out, "DATA") then self:SetStatus("Writing data/" .. out .. " failed", 2) return end

                if self.TargetKey then
                    local edits = FS.LoadEdits()
                    edits.paints[self.TargetKey] = out
                    FS.SaveEdits(edits)
                end

                self:SetStatus("Saved data/" .. out .. " (" .. FS.FormatSize(#data) .. ")" .. (self.TargetKey and "  -  re-applied automatically when you join" or ""), 1)
                self:RefreshButtons()
            end

            ----------------------------------------------------------------------
            -- drawing the canvas
            ----------------------------------------------------------------------
            function IMG:PaintCanvas(c, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(10, 12, 11))

                if not self.Mat then
                    draw.SimpleText(self.Status ~= "" and self.Status or "No image", "TBH.Body", w / 2, h / 2, TBH.Colors.textdim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    return
                end

                local x, y = self.OX, self.OY
                local iw, ih = self.W * self.Zoom, self.H * self.Zoom

                -- checkerboard behind the image (only the visible part of it)
                local x0, y0 = math.max(0, x), math.max(0, y)
                local x1, y1 = math.min(w, x + iw), math.min(h, y + ih)
                if x1 > x0 and y1 > y0 then
                    surface.SetDrawColor(46, 50, 47)
                    surface.DrawRect(x0, y0, x1 - x0, y1 - y0)

                    surface.SetDrawColor(66, 72, 68)
                    local t = 12
                    for ty = 0, math.ceil((y1 - y0) / t) do
                        for tx = 0, math.ceil((x1 - x0) / t) do
                            if (tx + ty) % 2 == 0 then
                                local rx, ry = x0 + tx * t, y0 + ty * t
                                surface.DrawRect(rx, ry, math.min(t, x1 - rx), math.min(t, y1 - ry))
                            end
                        end
                    end
                end

                local mat = (self.Mode == "paint" and self.RTMat) or self.Mat
                surface.SetMaterial(mat)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(x, y, iw, ih)

                surface.SetDrawColor(TBH.Colors.outline)
                surface.DrawOutlinedRect(x - 1, y - 1, iw + 2, ih + 2)

                if self.Mode ~= "paint" then return end

                -- preview of line / rect while dragging
                local s = self.Drawing
                if s and s.pts[3] and (self.DrawKind == "line" or self.DrawKind == "rect") then
                    local ax, ay = s.pts[1] * self.Zoom + x, s.pts[2] * self.Zoom + y
                    local bx, by = s.pts[3] * self.Zoom + x, s.pts[4] * self.Zoom + y

                    if self.DrawKind == "line" then
                        surface.SetDrawColor(s.r, s.g, s.b, math.max(120, s.a))
                        surface.DrawLine(ax, ay, bx, by)
                    else
                        surface.SetDrawColor(s.r, s.g, s.b, 110)
                        surface.DrawRect(math.min(ax, bx), math.min(ay, by), math.abs(bx - ax), math.abs(by - ay))
                    end
                end

                -- brush outline under the cursor
                if self.Hover and not self.Pan and (self.Tool == "brush" or self.Tool == "line" or self.Tool == "restore") then
                    surface.DrawCircle(self.Hover[1], self.Hover[2], math.max(2, self.BrushSize * self.Zoom / 2), 255, 255, 255, 200)
                end
            end

            function IMG:OnRemove()
                if FS.ActiveImage == self then FS.ActiveImage = nil end
                self:StoreState()
            end

            vgui.Register("TBH.FSImage", IMG, "EditablePanel")

            hook.Add("PostRender", "TBH.FSPaint", function()
                local p = FS.ActiveImage
                if not (IsValid(p) and p.RT and p.Mat) then return end
                p:ProcessRT()
            end)
        end

        ----------------------------------------------------------------------
        -- MODEL PREVIEW (.mdl): orbit with the mouse, zoom with the wheel
        ----------------------------------------------------------------------
        do
            local MD = {}
            local WIRE = Material("models/wireframe")

            function MD:Init()
                self.Yaw, self.Pitch = 35, 12
                self.Status = ""
                self.StatusLevel = 0

                local bar = FS.Toolbar(self, 36)
                bar:DockMargin(0, 0, 0, 6)
                FS.Button(bar, "Reset view", 90, function() self:ResetView() end)
                self.TglWire = FS.Toggle(bar, "Wireframe", 90, false, function(on) self.Wire = on end)
                self.TglAnim = FS.Toggle(bar, "Animate", 80, true)
                FS.Button(bar, "Spawn", 70, function() self:Spawn() end, true)
                FS.Button(bar, "Copy path", 90, function()
                    SetClipboardText(self.ModelPath or "")
                    FS.Notify("Model path copied", 0)
                end)

                self.Foot = vgui.Create("DPanel", self)
                self.Foot:Dock(BOTTOM)
                self.Foot:SetTall(24)
                self.Foot:DockMargin(0, 6, 0, 0)
                self.Foot.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel)
                    local col = (self.StatusLevel == 2) and TBH.Colors.error or ((self.StatusLevel == 3) and TBH.Colors.warn or TBH.Colors.textdim)
                    draw.SimpleText(FS.Fit("TBH.Small", self.Status, w - 20), "TBH.Small", 10, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                self.Side = vgui.Create("DScrollPanel", self)
                self.Side:Dock(RIGHT)
                self.Side:SetWide(270)
                self.Side:DockMargin(6, 0, 0, 0)
                self.Side.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel) end

                local m = vgui.Create("DModelPanel", self)
                self.Model = m
                m:Dock(FILL)
                m:SetFOV(40)
                m:SetCursor("sizeall")

                local oldPaint = m.Paint
                m.Paint = function(p, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, Color(14, 17, 15))
                    if oldPaint then oldPaint(p, w, h) end
                end

                m.LayoutEntity = function(p, ent)
                    if self.TglAnim.On and p.RunAnimation then pcall(p.RunAnimation, p) end
                end

                m.PreDrawModel = function(p, ent)
                    if self.Wire then render.ModelMaterialOverride(WIRE) end
                end
                m.PostDrawModel = function(p, ent)
                    if self.Wire then render.ModelMaterialOverride(nil) end
                end

                m.OnMousePressed = function(p, code)
                    local x, y = p:CursorPos()
                    self.Drag = { x = x, y = y }
                    p:MouseCapture(true)
                end
                m.OnMouseReleased = function(p)
                    self.Drag = nil
                    p:MouseCapture(false)
                end
                m.OnCursorMoved = function(p, x, y)
                    local d = self.Drag
                    if not d then return end
                    self.Yaw = self.Yaw - (x - d.x) * 0.5
                    self.Pitch = math.Clamp(self.Pitch + (y - d.y) * 0.4, -85, 85)
                    d.x, d.y = x, y
                end
                m.OnMouseWheeled = function(p, delta)
                    if not self.Dist then return end
                    self.Dist = math.Clamp(self.Dist * (0.9 ^ delta), self.MinDist, self.MaxDist)
                end
            end

            function MD:SetStatus(msg, level)
                self.Status = msg or ""
                self.StatusLevel = level or 0
            end

            function MD:ResetView()
                self.Yaw, self.Pitch = 35, 12
                if self.DefDist then self.Dist = self.DefDist end
            end

            function MD:Spawn()
                if not self.ModelPath then return end
                RunConsoleCommand("gm_spawn", self.ModelPath)
                FS.Notify("Spawning " .. self.ModelPath, 0)
            end

            function MD:Think()
                if not (self.Focus and self.Dist) then return end

                local p, y = math.rad(self.Pitch), math.rad(self.Yaw)
                local dir = Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p))
                self.Model:SetCamPos(self.Focus + dir * self.Dist)
                self.Model:SetLookAt(self.Focus)
            end

            function MD:Row(text, parent)
                local l = vgui.Create("DLabel", parent or self.Side)
                l:Dock(TOP)
                l:SetTall(20)
                l:DockMargin(10, 8, 10, 0)
                l:SetFont("TBH.Small")
                l:SetTextColor(TBH.Colors.tag)
                l:SetText(text)
                return l
            end

            -- one compact row: name on the left, slider in the middle, "value / max" on the right
            function MD:Control(label, maxv, value, onValue)
                local row = vgui.Create("DPanel", self.Side)
                row:Dock(TOP)
                row:SetTall(26)
                row:DockMargin(8, 3, 14, 0)
                row.Value = value or 0

                row.Paint = function(r, w, h)
                    draw.SimpleText(FS.Fit("TBH.Small", label, 96), "TBH.Small", 2, h / 2, TBH.Colors.tag, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(r.Value .. " / " .. maxv, "TBH.Small", w - 2, h / 2, TBH.Colors.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end

                local sl = vgui.Create("TBH.FSSlider", row)
                sl:Dock(FILL)
                sl:DockMargin(104, 4, 50, 4)
                sl:SetRange(0, maxv)
                sl.Step = 1
                sl:SetValue(value or 0)
                sl.OnValue = function(_, v)
                    v = math.floor(v + 0.5)
                    row.Value = v
                    onValue(v)
                end

                return sl
            end

            function MD:BuildSide(ent)
                self.Side:Clear()

                -- sequences
                local count = math.min(ent:GetSequenceCount() or 0, 600)
                if count > 1 then
                    self:Row("SEQUENCE (" .. count .. ")")
                    local combo = vgui.Create("DComboBox", self.Side)
                    combo:Dock(TOP)
                    combo:SetTall(22)
                    combo:DockMargin(10, 4, 10, 0)
                    combo:SetSortItems(false)

                    local startIdx
                    for i = 0, count - 1 do
                        local name = ent:GetSequenceName(i) or ("seq " .. i)
                        combo:AddChoice(name, i)
                        if not startIdx and (name == "idle" or name == "idle_all_01" or name == "ragdoll" or name == "reference") then
                            startIdx = i
                        end
                    end

                    combo.OnSelect = function(_, _, _, i) if IsValid(ent) then ent:ResetSequence(i) end end
                    startIdx = startIdx or 0
                    combo:ChooseOptionID(startIdx + 1)
                    ent:ResetSequence(startIdx)
                end

                -- skins
                local skins = ent:SkinCount() or 1
                if skins > 1 then
                    self:Control("SKIN", skins - 1, ent:GetSkin() or 0, function(v) if IsValid(ent) then ent:SetSkin(v) end end)
                end

                -- bodygroups
                for i = 0, (ent:GetNumBodyGroups() or 0) - 1 do
                    local c = ent:GetBodygroupCount(i) or 0
                    if c > 1 then
                        self:Control(string.upper(ent:GetBodygroupName(i) or ("bodygroup " .. i)), c - 1, ent:GetBodygroup(i) or 0,
                            function(v) if IsValid(ent) then ent:SetBodygroup(i, v) end end)
                    end
                end

                -- room at the bottom so the last slider can always be scrolled fully into view
                local pad = vgui.Create("DPanel", self.Side)
                pad:Dock(TOP)
                pad:SetTall(14)
                pad.Paint = nil
                self.Side:InvalidateLayout(true)
            end

            function MD:LoadInner(info)
                self.Info = info
                -- try every path the game could know this model by; whichever exists wins, and if
                -- none does we still hand the first one to the engine and report what it says
                local candidates = {}
                local function add(c)
                    if not isstring(c) or c == "" then return end
                    c = string.lower(string.gsub(c, "\\", "/"))
                    for _, x in ipairs(candidates) do if x == c then return end end
                    candidates[#candidates + 1] = c
                end

                local tail = string_match(string.lower(string.gsub(info.path or "", "\\", "/")), "(models/.+)$")
                add(info.inner)
                add(tail)
                add(info.path)
                if info.name and not tail then add("models/" .. info.name) end

                local mdl
                for _, c in ipairs(candidates) do
                    if file.Exists(c, "GAME") then mdl = c break end
                end

                local guessed = false
                if not mdl then
                    mdl = tail or candidates[1]
                    guessed = true
                end

                if not mdl then
                    self:SetStatus("No usable model path for this file", 2)
                    return
                end

                self.ModelPath = mdl

                -- (util.IsValidModel only says yes for models the client already loaded, so don't use it)
                pcall(util.PrecacheModel, mdl)

                self.Model:SetModel(mdl)
                local ent = self.Model:GetEntity()
                if not IsValid(ent) then
                    self:SetStatus("The game refused to create this model (missing .vvd/.vtx/.phy files or a broken .mdl)", 2)
                    return
                end

                local warned = false
                if string.lower(ent:GetModel() or "") ~= string.lower(mdl) then
                    warned = true
                    self:SetStatus("The game loaded a different model than requested (" .. tostring(ent:GetModel()) .. ")", 3)
                elseif guessed then
                    warned = true
                    self:SetStatus("Loaded " .. mdl .. " (path guessed - the file is not in the game's mounted content, the engine accepted it anyway)", 3)
                end

                local mn, mx = ent:GetModelRenderBounds()
                if not mn or (mx - mn):Length() < 1 then mn, mx = ent:GetRenderBounds() end
                if not mn or (mx - mn):Length() < 1 then mn, mx = Vector(-16, -16, 0), Vector(16, 16, 72) end

                self.Focus = (mn + mx) / 2
                local radius = math.max(8, (mx - mn):Length() / 2)
                self.DefDist = radius / math.tan(math.rad(20)) * 1.05
                self.Dist = self.DefDist
                self.MinDist = radius * 0.25
                self.MaxDist = radius * 14

                if self.Model.SetFarZ then self.Model:SetFarZ(radius * 60) end
                if self.Model.SetNearZ then self.Model:SetNearZ(math.max(0.5, radius * 0.01)) end

                self:BuildSide(ent)

                if not warned then
                    self:SetStatus(string.format("%s  -  %s  |  %d sequences, %d skins, %d bodygroups  |  drag = orbit, wheel = zoom",
                        mdl, FS.FormatSize(file.Size(info.path, info.id) or 0), ent:GetSequenceCount() or 0,
                        ent:SkinCount() or 1, ent:GetNumBodyGroups() or 0), 0)
                end
            end

            function MD:Load(info)
                local ok, err = pcall(self.LoadInner, self, info)
                if not ok then
                    self.Focus = nil
                    self:SetStatus("Model preview failed: " .. tostring(err), 2)
                end
            end

            vgui.Register("TBH.FSModel", MD, "EditablePanel")
        end

        ----------------------------------------------------------------------
        -- plain info page for everything else
        ----------------------------------------------------------------------
        do
            local INFO = {}

            function INFO:Load(info, extra)
                self.Info = info
                self.Extra = extra or ""
                self.Size = file.Size(info.path, info.id) or 0

                if info.ext == "mdl" then
                    self.Extra = "Models can't be previewed here. Spawn it with the spawnmenu or  'prop_physics' + 'prop_dynamic' console commands:  " .. string_gsub(info.inner or info.path, "^addons/[^/]+/", "")
                end
            end

            function INFO:Paint(w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                local i = self.Info
                if not i then return end

                draw.SimpleText(i.name, "TBH.Header", 16, 14, TBH.Colors.tag)
                draw.SimpleText(i.path, "TBH.Small", 16, 44, TBH.Colors.textdim)
                draw.SimpleText(FS.FormatSize(self.Size), "TBH.Body", 16, 66, TBH.Colors.text)

                local msg = self.Extra ~= "" and self.Extra or "No viewer for this file type. Right click it in the list for more."
                draw.DrawText(msg, "TBH.Body", 16, 100, TBH.Colors.textdim)
            end

            vgui.Register("TBH.FSInfo", INFO, "EditablePanel")
        end

        FS.TEXT_EXT, FS.AUDIO_EXT, FS.IMAGE_EXT = TEXT_EXT, AUDIO_EXT, IMAGE_EXT
    end

    ------------------------------------------------------------------------------
    -- FILESYSTEM PAGE (browser on the left, viewer on the right)
    ------------------------------------------------------------------------------
    do
        local PANEL = {}
        local ROW_H = 30
        local ADDON_ROW_H = 70
        local MAX_ROWS = 700
        local CONTENT_DIRS = { "lua", "models", "materials", "sound", "maps", "particles", "scripts", "resource", "gamemodes" }

        function PANEL:Init()
            self.Search = ""
            self.Entries = {}
            self.Root = "addons"
            self.PathID = "MOD"
            self.Dir = ""

            self.Paint = function(_, w, h)
                draw.RoundedBox(0, 0, 0, w, h, TBH.Colors.bg)

                if TBH.Theme and TBH.Theme.bgMaterial then
                    local alpha = TBH.CVarThemeAlpha and math.Clamp(TBH.CVarThemeAlpha:GetInt() or 100, 0, 255) or 255
                    surface.SetMaterial(TBH.Theme.bgMaterial)
                    surface.SetDrawColor(255, 255, 255, alpha)
                    surface.DrawTexturedRect(0, 0, w, h)
                end
            end

            local bar = vgui.Create("DPanel", self)
            bar:Dock(TOP)
            bar:SetTall(48)
            bar:DockMargin(0, 0, 0, 8)
            bar.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                draw.RoundedBoxEx(6, 0, 0, 5, h, TBH.Colors.accent, true, false, true, false)
                draw.SimpleText(self.Virtual and "ADDON CONTENT" or "FILESYSTEM", "TBH.Header", 18, 5, TBH.Colors.tag)
                local crumb = self.Virtual and ((self.VTitle or "addon") .. "/" .. self.Dir)
                    or ("garrysmod/" .. ((self.Root == "data") and "data/" or "") .. self.Dir)
                if #crumb > 32 then crumb = "..." .. string_sub(crumb, -29) end
                draw.SimpleText(crumb, "TBH.Small", 18, 29, TBH.Colors.textdim)
            end

            local rootBox = vgui.Create("DPanel", bar)
            self.RootBox = rootBox
            rootBox:Dock(LEFT)
            rootBox:SetWide(170)
            rootBox:DockMargin(190, 9, 0, 9)
            rootBox.Paint = nil
            self.BtnAddons = TBH.FS.Button(rootBox, "ADDONS", 76, function() self:SetRoot("addons") end)
            self.BtnData = TBH.FS.Button(rootBox, "DATA", 60, function() self:SetRoot("data") end)
            self.BtnData:SetTooltip("garrysmod/data - files here are read/write, saved in place")

            local refresh = vgui.Create("DButton", bar)
            refresh:Dock(RIGHT)
            refresh:SetWide(80)
            refresh:DockMargin(0, 11, 12, 11)
            refresh:SetText("Rescan")
            refresh:SetFont("TBH.Small")
            refresh:SetColor(TBH.Colors.text)
            refresh:SetTooltip("Read this folder again")
            refresh.Paint = function(btn, w, h)
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel2)
                if btn:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.outline) end
            end
            refresh.DoClick = function() self:Scan() self:Populate() end

            local search = vgui.Create("DTextEntry", bar)
            search:Dock(RIGHT)
            search:SetWide(150)
            search:DockMargin(0, 11, 8, 11)
            search:SetFont("TBH.Small")
            search:SetPlaceholderText("filter this folder...")
            search.OnChange = function(entry)
                self.Search = string.lower(entry:GetText())
                self:Populate()
            end

            -- left: the file list
            self.Left = vgui.Create("DPanel", self)
            self.Left:Dock(LEFT)
            self.Left:SetWide(380)
            self.Left:DockMargin(0, 0, 8, 0)
            self.Left.Paint = nil

            self.CountBar = vgui.Create("DPanel", self.Left)
            self.CountBar:Dock(BOTTOM)
            self.CountBar:SetTall(20)
            self.CountBar.Paint = function(_, w, h)
                draw.SimpleText(self.CountText or "", "TBH.Small", 4, h / 2, TBH.Colors.textdim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            self.Scroll = vgui.Create("DScrollPanel", self.Left)
            self.Scroll:Dock(FILL)

            -- right: the viewer
            self.Viewer = vgui.Create("DPanel", self)
            self.Viewer:Dock(FILL)
            self.Viewer.Paint = function(_, w, h)
                if IsValid(self.Current) then return end
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                draw.SimpleText("Pick a file on the left", "TBH.Header", w / 2, h / 2 - 40, TBH.Colors.textdim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(".wav .mp3 .ogg  -  play it", "TBH.Body", w / 2, h / 2 - 8, TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(".lua .vmt .txt  -  edit it, saving applies it live", "TBH.Body", w / 2, h / 2 + 14, TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(".vtf .png .jpg  -  view it, paint on it, apply it to the game", "TBH.Body", w / 2, h / 2 + 36, TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            self:Scan()
            self:Populate()
            self:RefreshRootButtons()
        end

        -- turns this page into a browser for one addon's file list (from its .gma)
        function PANEL:SetVirtual(files, title, tag, note)
            self.Virtual = files
            self.VTitle = title
            self.VTag = tag
            self.VNote = note
            self.Root = "addon"
            self.PathID = "GAME"
            self.Dir = ""
            if IsValid(self.RootBox) then self.RootBox:SetVisible(false) end
            self:Scan()
            self:Populate()
        end

        function PANEL:RefreshRootButtons()
            self.BtnAddons.Active = (self.Root == "addons")
            self.BtnData.Active = (self.Root == "data")
        end

        function PANEL:SetRoot(root)
            self.Root = root
            self.PathID = (root == "data") and "DATA" or "MOD"
            self.Dir = ""
            self.Search = ""
            self:RefreshRootButtons()
            self:Scan()
            self:Populate()
        end

        function PANEL:GoTo(dir)
            self.Dir = dir
            self:Scan()
            self:Populate()
            self.Scroll:GetVBar():SetScroll(0)
        end

        function PANEL:GoUp()
            local parent = string_match(self.Dir, "^(.*)/[^/]+$") or ""
            if self.Root == "addons" and parent == "addons" then parent = "" end
            self:GoTo(parent)
        end

        -- reads the current folder
        function PANEL:Scan()
            local out = {}

            if self.Virtual then
                -- contents of one .gma, listed from its file table
                local prefix = (self.Dir == "") and "" or (self.Dir .. "/")
                local plen = #prefix
                local seen = {}

                for _, f in ipairs(self.Virtual) do
                    local fp = f.path
                    if plen == 0 or string_sub(fp, 1, plen) == prefix then
                        local rest = string_sub(fp, plen + 1)
                        local slash = string_find(rest, "/", 1, true)
                        if slash then
                            local d = string_sub(rest, 1, slash - 1)
                            if not seen[d] then
                                seen[d] = true
                                out[#out + 1] = { name = d, path = prefix .. d, kind = "dir" }
                            end
                        else
                            out[#out + 1] = { name = rest, path = fp, kind = "file", ext = TBH.FS.Ext(rest), size = f.size }
                        end
                    end
                end
            elseif self.Root == "addons" and self.Dir == "" then
                -- the addon list: folders first, loose .gma files after
                local _, dirs = file.Find("addons/*", "MOD")
                for _, name in ipairs(dirs or {}) do
                    local base = "addons/" .. name
                    local entry = { name = name, path = base, kind = "addon", parts = {} }

                    for _, sub in ipairs(CONTENT_DIRS) do
                        if file.IsDir(base .. "/" .. sub, "MOD") then
                            entry.parts[#entry.parts + 1] = string.upper(sub)
                        end
                    end

                    local json = file.Read(base .. "/addon.json", "MOD")
                    if isstring(json) and json ~= "" then
                        local okJ, tbl = pcall(util.JSONToTable, json)
                        if okJ and istable(tbl) and isstring(tbl.title) and tbl.title ~= "" then
                            entry.title = tbl.title
                        end
                    end

                    out[#out + 1] = entry
                end

                for _, f in ipairs((file.Find("addons/*.gma", "MOD")) or {}) do
                    out[#out + 1] = {
                        name = f, path = "addons/" .. f, kind = "gma", parts = {},
                        size = file.Size("addons/" .. f, "MOD"),
                    }
                end
            else
                local pattern = (self.Dir == "") and "*" or (self.Dir .. "/*")
                local files, dirs = file.Find(pattern, self.PathID)

                for _, name in ipairs(dirs or {}) do
                    out[#out + 1] = { name = name, path = (self.Dir == "") and name or (self.Dir .. "/" .. name), kind = "dir" }
                end

                for _, name in ipairs(files or {}) do
                    local p = (self.Dir == "") and name or (self.Dir .. "/" .. name)
                    out[#out + 1] = { name = name, path = p, kind = "file", ext = TBH.FS.Ext(name), size = file.Size(p, self.PathID) }
                end
            end

            local rank = { addon = 0, dir = 0, file = 1, gma = 2 }
            for _, e in ipairs(out) do e._low = string.lower(e.name) end
            table.sort(out, function(a, b)
                if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
                return a._low < b._low
            end)

            self.Entries = out
        end

        function PANEL:Populate()
            self.Scroll:Clear()

            local q = self.Search or ""
            local shown, total = 0, #self.Entries

            if self.Dir ~= "" then self:AddUpRow() end

            for _, e in ipairs(self.Entries) do
                if q == "" or string.find(e._low, q, 1, true)
                    or (e.title and string.find(string.lower(e.title), q, 1, true)) then
                    shown = shown + 1
                    if shown <= MAX_ROWS then self:AddRow(e) end
                end
            end

            if shown > MAX_ROWS then
                local more = vgui.Create("DPanel", self.Scroll)
                more:Dock(TOP)
                more:SetTall(30)
                more.Paint = function(_, w, h)
                    draw.SimpleText("+ " .. (shown - MAX_ROWS) .. " more - use the filter box", "TBH.Small", 8, h / 2, TBH.Colors.warn, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end

            if total == 0 then
                local empty = vgui.Create("DPanel", self.Scroll)
                empty:Dock(TOP)
                empty:SetTall(50)
                empty.Paint = function(_, w, h)
                    draw.SimpleText("Nothing here.", "TBH.Body", 6, h / 2, TBH.Colors.textdim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end

            self.CountText = shown .. " of " .. total .. " shown" .. (self.VNote and ("  -  " .. self.VNote) or "")
        end

        function PANEL:AddUpRow()
            local row = vgui.Create("DButton", self.Scroll)
            row:Dock(TOP)
            row:SetTall(ROW_H)
            row:DockMargin(0, 0, 0, 3)
            row:SetText("")
            row.Paint = function(r, w, h)
                draw.RoundedBox(5, 0, 0, w, h, r:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bgPanel)
                draw.SimpleText(".. (up)", "TBH.Body", 14, h / 2, TBH.Colors.tag, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            row.DoClick = function() self:GoUp() end
        end

        function PANEL:InfoFor(e)
            local path = e.path
            local info = {
                path = path, id = self.PathID, name = e.name, ext = e.ext or TBH.FS.Ext(e.name),
                root = self.Root, writable = (self.Root == "data"),
            }

            if self.Root == "addons" then
                info.addon = string_match(path, "^addons/([^/]+)/")
                info.inner = string_match(path, "^addons/[^/]+/(.+)$")
            elseif self.Root == "addon" then
                info.inner = path
                info.tag = self.VTag
            end

            return info
        end

        function PANEL:ClearViewer(thenDo)
            local cur = self.Current
            if IsValid(cur) and cur.IsDirty and cur:IsDirty() then
                Derma_Query("You have unsaved changes in this file.", "Hotloader",
                    "Discard them", function() cur:Remove() self.Current = nil thenDo() end,
                    "Cancel", function() end)
                return
            end

            if IsValid(cur) then cur:Remove() end
            self.Current = nil
            thenDo()
        end

        function PANEL:OpenFile(e)
            local info = self:InfoFor(e)
            local ext = info.ext
            local FS = TBH.FS
            self.CurrentEntry = e

            self:ClearViewer(function()
                local panel

                if FS.AUDIO_EXT[ext] then
                    panel = vgui.Create("TBH.FSAudio", self.Viewer)
                    panel:Dock(FILL)
                    panel.OnStep = function(delta) self:StepAudio(delta) end
                    panel:Load(info)
                elseif ext == "mdl" then
                    panel = vgui.Create("TBH.FSModel", self.Viewer)
                    panel:Dock(FILL)
                    panel:Load(info)
                elseif FS.IMAGE_EXT[ext] then
                    panel = vgui.Create("TBH.FSImage", self.Viewer)
                    panel:Dock(FILL)
                    panel:Load(info)
                elseif FS.TEXT_EXT[ext] then
                    panel = vgui.Create("TBH.FSEditor", self.Viewer)
                    panel:Dock(FILL)
                    panel:Load(info)
                else
                    panel = vgui.Create("TBH.FSInfo", self.Viewer)
                    panel:Dock(FILL)
                    panel:Load(info)
                end

                self.Current = panel
                self.Viewer:InvalidateLayout(true)
                if panel.Fit and panel.W then timer.Simple(0.05, function() if IsValid(panel) then panel:Fit() end end) end
            end)
        end

        -- prev / next audio file in the folder
        function PANEL:StepAudio(delta)
            local list = {}
            local at = 0

            for _, e in ipairs(self.Entries) do
                if e.kind == "file" and TBH.FS.AUDIO_EXT[e.ext] then
                    list[#list + 1] = e
                    if self.CurrentEntry == e then at = #list end
                end
            end

            if #list == 0 then return end
            local nextI = ((at - 1 + delta) % #list) + 1
            self:OpenFile(list[nextI])
        end

        function PANEL:AddRow(e)
            local isAddon = (e.kind == "addon" or e.kind == "gma")
            local row = vgui.Create("DButton", self.Scroll)
            row:Dock(TOP)
            row:SetTall(isAddon and ADDON_ROW_H or ROW_H)
            row:DockMargin(0, 0, 0, 3)
            row:SetText("")

            local isUs = isAddon and string_sub(e._low, 1, 10) == "hotloader_"
            local icon = TBH.FS.Icon(e.ext, e.kind == "dir" or e.kind == "addon")
            if e.kind == "gma" then icon = TBH.FS.Icon("gma") end

            row.Paint = function(r, w, h)
                local selected = (self.CurrentEntry == e)
                local col = TBH.Colors.bgPanel
                if r:IsHovered() then col = TBH.Colors.bgPanel2 end
                draw.RoundedBox(5, 0, 0, w, h, col)
                if selected then draw.RoundedBoxEx(5, 0, 0, 4, h, TBH.Colors.tag, true, false, true, false) end

                if icon and not icon:IsError() then
                    surface.SetMaterial(icon)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
                end

                local name = e.name
                local maxc = isAddon and 34 or 40
                if #name > maxc then name = string_sub(name, 1, maxc) .. "..." end

                if isAddon then
                    draw.SimpleText(name, "TBH.Body", 38, 8, TBH.Colors.text)

                    local sub = e.title or ""
                    if e.kind == "gma" and e.size then sub = TBH.FS.FormatSize(e.size) .. " - cannot be browsed" end
                    if #sub > 48 then sub = string_sub(sub, 1, 48) .. "..." end
                    draw.SimpleText(sub, "TBH.Small", 38, 27, TBH.Colors.textdim)

                    -- content chips along the bottom right
                    local x = w - 8
                    surface.SetFont("TBH.Small")
                    local chips = {}
                    if isUs then chips[#chips + 1] = { "THIS ADDON", true } end
                    for i = #e.parts, 1, -1 do chips[#chips + 1] = { e.parts[i], false } end

                    for _, c in ipairs(chips) do
                        local tw = surface.GetTextSize(c[1])
                        local cw = tw + 12
                        x = x - cw
                        if x < 40 then break end
                        draw.RoundedBox(7, x, h - 22, cw, 15, c[2] and TBH.Colors.accent or TBH.Colors.bg)
                        draw.SimpleText(c[1], "TBH.Small", x + cw / 2, h - 14.5, c[2] and Color(14, 26, 12) or TBH.Colors.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        x = x - 4
                    end
                else
                    draw.SimpleText(name, "TBH.Body", 38, h / 2, e.kind == "dir" and TBH.Colors.tag or TBH.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    if e.kind == "file" and e.size then
                        draw.SimpleText(TBH.FS.FormatSize(e.size), "TBH.Small", w - 10, h / 2, TBH.Colors.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    end
                end
            end

            row.DoClick = function()
                if e.kind == "addon" or e.kind == "dir" then
                    self:GoTo(e.path)
                elseif e.kind == "file" then
                    self:OpenFile(e)
                end
            end

            row.DoRightClick = function()
                local menu = DermaMenu()
                menu:AddOption("Copy name", function() SetClipboardText(e.name) end):SetIcon("icon16/page_copy.png")
                menu:AddOption("Copy path", function()
                    SetClipboardText(self.Virtual and e.path or ("garrysmod/" .. ((self.Root == "data") and "data/" or "") .. e.path))
                end):SetIcon("icon16/page_copy.png")

                if e.kind == "file" then
                    menu:AddOption("Open as text", function()
                        local info = self:InfoFor(e)
                        self:ClearViewer(function()
                            local ed = vgui.Create("TBH.FSEditor", self.Viewer)
                            ed:Dock(FILL)
                            ed:Load(info)
                            self.Current = ed
                            self.CurrentEntry = e
                            self.Viewer:InvalidateLayout(true)
                        end)
                    end):SetIcon("icon16/page_white_text.png")
                end

                if self.Root == "data" and (e.kind == "file" or e.kind == "dir") then
                    menu:AddSpacer()
                    menu:AddOption("Delete", function()
                        Derma_Query("Delete " .. e.path .. " ?", "Hotloader",
                            "Delete", function()
                                if e.kind == "file" then file.Delete(e.path) else
                                    local function wipe(dir)
                                        local fs, ds = file.Find(dir .. "/*", "DATA")
                                        for _, f in ipairs(fs or {}) do file.Delete(dir .. "/" .. f) end
                                        for _, d in ipairs(ds or {}) do wipe(dir .. "/" .. d) end
                                        file.Delete(dir)
                                    end
                                    wipe(e.path)
                                end
                                self:Scan()
                                self:Populate()
                            end,
                            "Cancel", function() end)
                    end):SetIcon("icon16/delete.png")
                end

                menu:Open()
            end
        end

        function PANEL:OnRemove()
            if IsValid(self.Current) then self.Current:Remove() end
        end

        vgui.Register("TBH.FilesystemPage", PANEL, "EditablePanel")
    end

    ------------------------------------------------------------------------------
    -- INSTALLED ADDONS TAB WRAPPER: WORKSHOP ADDONS | FILESYSTEM ADDONS
    ------------------------------------------------------------------------------
    do
        local PANEL = {}

        function PANEL:Init()
            self.Mode = "workshop"

            local bar = vgui.Create("DPanel", self)
            bar:Dock(TOP)
            bar:SetTall(38)
            bar:DockMargin(0, 0, 0, 6)
            bar.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
            end

            local function Segment(mode, text, iconPath, wide)
                local btn = vgui.Create("DButton", bar)
                btn:Dock(LEFT)
                btn:SetWide(wide)
                btn:DockMargin(5, 5, 0, 5)
                btn:SetText("")

                local iconMat = Material(iconPath)
                btn.Paint = function(b, w, h)
                    local active = self.Mode == mode
                    draw.RoundedBox(5, 0, 0, w, h, active and TBH.Colors.accent or (b:IsHovered() and TBH.Colors.bgPanel2 or TBH.Colors.bg))

                    if iconMat and not iconMat:IsError() then
                        surface.SetMaterial(iconMat)
                        surface.SetDrawColor(255, 255, 255, active and 255 or 170)
                        surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
                    end

                    draw.SimpleText(text, "TBH.Body", 36, h / 2, active and Color(14, 26, 12) or TBH.Colors.textdim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                btn.DoClick = function() self:SetMode(mode) end
            end

            Segment("workshop", "WORKSHOP ADDONS", "icon16/package.png", 190)
            Segment("filesystem", "FILESYSTEM ADDONS", "icon16/folder.png", 200)

            bar.PaintOver = function(_, w, h)
                local hint = (self.Mode == "filesystem")
                    and "browse folders, play sounds, edit lua live, paint materials"
                    or "your main menu Addons list - hotload any of them"
                draw.SimpleText(hint, "TBH.Small", w - 12, h / 2, TBH.Colors.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            self.Workshop = vgui.Create("TBH.InstalledPage", self)
            self.Workshop:Dock(FILL)
            self.Workshop:DockPadding(8, 8, 8, 8)
        end

        function PANEL:SetMode(mode)
            self.Mode = mode

            if mode == "filesystem" then
                if not IsValid(self.Filesystem) then
                    self.Filesystem = vgui.Create("TBH.FilesystemPage", self)
                    self.Filesystem:Dock(FILL)
                    self.Filesystem:DockPadding(8, 8, 8, 8)
                end

                self.Workshop:SetVisible(false)
                self.Filesystem:SetVisible(true)
            else
                self.Workshop:SetVisible(true)
                if IsValid(self.Filesystem) then self.Filesystem:SetVisible(false) end
            end

            self:InvalidateLayout(true)
        end

        vgui.Register("TBH.InstalledTab", PANEL, "EditablePanel")
    end

    -- the Dupes and Saves tabs are web pages (DHTML). after a spawnmenu_reload their
    -- page can come back half initialised - the Save buttons turn into "..." and do
    -- nothing. this finds those tabs and reloads their pages. it runs by itself
    -- after every reload we trigger, or by hand with hotloader_fix_tabs
    local function FindHTMLPanels(panel, out, depth)
        if not IsValid(panel) or depth > 12 then return end

        if panel.GetClassName and panel:GetClassName() == "DHTML" then
            out[#out + 1] = panel
        end

        for _, child in ipairs(panel:GetChildren()) do
            FindHTMLPanels(child, out, depth + 1)
        end
    end

    function TBH.RepairSpawnTabs()
        local sm = TBH.GetSpawnMenuPanel()
        if not (IsValid(sm) and IsValid(sm.CreateMenu)) then return 0 end

        local fixed = 0
        local okItems, items = pcall(sm.CreateMenu.GetItems, sm.CreateMenu)
        if not okItems or not istable(items) then return 0 end

        for _, item in ipairs(items) do
            local name = ""
            if IsValid(item.Tab) and item.Tab.GetText then
                name = string.lower(tostring(item.Tab:GetText() or ""))
            end

            if string_find(name, "dupe", 1, true) or string_find(name, "save", 1, true) then
                local htmls = {}
                FindHTMLPanels(item.Panel, htmls, 0)

                for _, html in ipairs(htmls) do
                    if pcall(function() html:Refresh() end) then fixed = fixed + 1 end
                end
            end
        end

        return fixed
    end

    hook.Add("SpawnMenuCreated", "TBH.RepairTabs", function()
        if not TBH.RepairTabsAfterReload then return end
        TBH.RepairTabsAfterReload = false

        -- give the pages a moment to finish loading before we poke them
        timer.Simple(2, function()
            local n = TBH.RepairSpawnTabs()
            TBH.Diag("repaired " .. n .. " dupes/saves page(s) after the spawnmenu reload")
        end)
    end)

    concommand.Add("hotloader_fix_tabs", function()
        local n = TBH.RepairSpawnTabs()
        TBH.Msg("Reloaded " .. n .. " Dupes/Saves page(s). Open the spawnmenu and check the Save buttons.")
    end)

    local function RegisterSpawnTabs()
        spawnmenu.AddCreationTab("Hotloader", function()
            local page = vgui.Create("TBH.HotloaderTab")
            page:DockPadding(0, 0, 0, 0)
            return page
        end, "icon16/lightning.png", 300, "Hotloader - hotload any Workshop addon mid-game, browse the Workshop, pin addons and maps")

        spawnmenu.AddCreationTab("Installed Addons", function()
            local page = vgui.Create("TBH.InstalledTab")
            return page
        end, "icon16/package.png", 302, "Installed Addons - your Workshop addons (hotload any of them) and the folders in garrysmod/addons")
    end

    -- V.1.0.8: pin diagnostics - if the menu ever misbehaves again, this one
    -- command prints the entire live state that drives the pin
    concommand.Add("hotloader_pin_debug", function()
        local page = TBH.BrowserTabPage
        local sm = TBH.GetSpawnMenuPanel()

        local pageVis = IsValid(page) and page:IsVisible() or false
        local smVis = IsValid(sm) and sm:IsVisible() or false

        local hangOpen = "?"
        if IsValid(sm) then
            local ok, v = pcall(sm.GetHangOpen, sm)
            if ok then hangOpen = tostring(v) end
        end

        local kbFocus = "none"
        local focused = vgui.GetKeyboardFocus()

        if IsValid(focused) then
            kbFocus = tostring(focused:GetClassName())
        end

        local activeTab = "?"

        if IsValid(sm) and IsValid(sm.CreateMenu) then
            local okT, tab = pcall(sm.CreateMenu.GetActiveTab, sm.CreateMenu)

            if okT and IsValid(tab) then
                local okN, name = pcall(tab.GetText, tab)
                if okN and isstring(name) then activeTab = name end
            end
        end

        TBH.Msg("pin debug: browserPageValid=" .. tostring(IsValid(page)) ..
            " | pageVisible=" .. tostring(pageVis) ..
            " | spawnmenuValid=" .. tostring(IsValid(sm)) ..
            " | menuVisible=" .. tostring(smVis) ..
            " | hangOpen=" .. hangOpen ..
            " | keyboardFocus=" .. kbFocus ..
            " | activeCreationTab=" .. activeTab)
        TBH.Msg("  (Q release is swallowed ONLY while pageVisible=true; click any other tab or ESC to close. Run this while the menu is open on the tab that misbehaves.)")
    end)
    pcall(RegisterSpawnTabs)

    -- path 2: guaranteed slot (runs before the creation menu is built, every
    -- time - initial load AND spawnmenu_reload)
    hook.Add("AddToolMenuTabs", "TBH.SpawnMenuTab", RegisterSpawnTabs)

    ------------------------------------------------------------------------------
    -- Utilities settings
    ------------------------------------------------------------------------------

    hook.Add("AddToolMenuCategories", "TBH.ToolCategories", function()
        spawnmenu.AddToolCategory("Utilities", "Hotloader", "Hotloader")
    end)

    -- Settings & Info, grouped into collapsible sections so you can find things
    hook.Add("PopulateToolMenu", "TBH.ToolMenuOptions", function()
        spawnmenu.AddToolMenuOption("Utilities", "Hotloader", "hotloader_settings", "Settings & Info", "", "", function(panel)
            panel:ClearControls()

            local function Section(title, open)
                local form = vgui.Create("DForm", panel)
                form:SetName(title)
                form:SetExpanded(open and true or false)
                panel:AddItem(form)
                return form
            end

            --------------------------------------------------------------
            -- 1. status
            --------------------------------------------------------------
            local status = Section("Status", true)
            status:Help("Hotloader V." .. TBH.Version .. " - hotload any Workshop addon mid-game.")

            local hotloaded = 0
            for _, m in pairs(TBH.Client.Mounted or {}) do
                if istable(m) and not m.unloaded then hotloaded = hotloaded + 1 end
            end

            local info = TBH.ServerInfo
            if info then
                local permText = "everyone"
                if info.permission == 1 then permText = "admins" end
                if info.permission == 2 then permText = "superadmins" end

                status:Help("Server: hotloading allowed for " .. permText .. ", requirement chains " ..
                    (info.requirements and "ON" or "OFF") .. ".")
            else
                status:Help("Waiting for server info...")
            end

            status:Help(hotloaded .. " addon(s) hotloaded this session.")
            status:ControlHelp("Server owners can change these with: hotloader_requirements, hotloader_max_files, hotloader_timeout, hotloader_cooldown, hotloader_latesync, hotloader_announce")

            --------------------------------------------------------------
            -- 2. quick actions
            --------------------------------------------------------------
            local actions = Section("Quick actions", true)
            actions:Button("Open the Workshop browser in a window", "hotloader_browser")
            actions:Button("Re-sync all hotloaded addons", "hotloader_resync")
            actions:Button("Show conflict report", "hotloader_conflicts")
            actions:Button("Fix Dupes / Saves tabs (reload their pages)", "hotloader_fix_tabs")
            actions:Button("Show welcome hints again", "hotloader_give_hints")

            --------------------------------------------------------------
            -- 3. automation
            --------------------------------------------------------------
            local auto = Section("Automation", true)
            auto:CheckBox("Auto-Hotload on Subscribe", "hotloader_autosubscribe")
            auto:ControlHelp("Subscribing to a NEW addon in-game requests a hotload for it.")
            auto:CheckBox("Enable Addons", "hotloader_enableaddons")
            auto:ControlHelp("Turning an addon back ON in the Addons menu hotloads it (already downloaded, so it is fast).")
            auto:CheckBox("Welcome hints", "hotloader_hints")

            --------------------------------------------------------------
            -- 4. appearance: accent color
            -- (plain DColorMixer with NO convar binding on purpose: the stock
            -- convar-bound mixer fights the user and snaps back while dragging.
            -- every change is committed by us: the three convars + ONE debounced
            -- theme reload)
            --------------------------------------------------------------
            local look = Section("Appearance - accent color", true)
            look:Help("Pick an accent color. The whole UI re-themes as you pick: the tabs, the Browser and the hint toasts.")

            local mixer = vgui.Create("DColorMixer", look)
            mixer:SetPalette(false)
            mixer:SetAlphaBar(false)
            mixer:SetWangs(true)
            mixer:Dock(TOP)
            mixer:SetTall(180)
            look:AddItem(mixer)

            local cur = TBH.Colors.accent or Color(94, 168, 62)
            local seeding = true
            mixer:SetColor(Color(cur.r, cur.g, cur.b))
            seeding = false

            mixer.ValueChanged = function(_, col)
                if seeding or not istable(col) then return end
                local r = math.floor(math.Clamp(tonumber(col.r) or 0, 0, 255))
                local g = math.floor(math.Clamp(tonumber(col.g) or 0, 0, 255))
                local b = math.floor(math.Clamp(tonumber(col.b) or 0, 0, 255))
                RunConsoleCommand("hotloader_theme_accent_r", r)
                RunConsoleCommand("hotloader_theme_accent_g", g)
                RunConsoleCommand("hotloader_theme_accent_b", b)
                TBH.QueueThemeReload()
            end

            local resetAccent = look:Button("Reset to default neon-green")
            resetAccent.DoClick = function()
                RunConsoleCommand("hotloader_theme_accent_r", 94)
                RunConsoleCommand("hotloader_theme_accent_g", 168)
                RunConsoleCommand("hotloader_theme_accent_b", 62)
                seeding = true
                mixer:SetColor(Color(94, 168, 62))
                seeding = false
                TBH.QueueThemeReload()
            end

            --------------------------------------------------------------
            -- 5. appearance: background image
            --------------------------------------------------------------
            local bg = Section("Appearance - background image", false)
            bg:Help("Recommended size: 1920x1080 (16:9). It is stretched to fill the menu, so keep it 16:9 to avoid distortion. 1280x720 up to 2048 wide works, 4096 max.")
            bg:ControlHelp("Put a .png or .jpg in garrysmod/data and press Browse, or type its path (mybg.png, subfolder/bg.jpg). Leave it empty and press Apply to remove the background.")

            local bgEntry = bg:TextEntry("Image path")
            if TBH.CVarThemeBgImage and IsValid(bgEntry) then
                bgEntry:SetText(TBH.CVarThemeBgImage:GetString() or "")
            end

            local function ApplyBackground()
                local txt = string.Trim(bgEntry:GetText() or "")

                if TBH.CVarThemeBgImage then
                    RunConsoleCommand("hotloader_theme_bg", txt)
                end

                -- force=true re-reads even the same path (the file may have
                -- been replaced on disk since it was last loaded)
                TBH.LoadThemeBackground(true)
                hook.Run("TBH.ClientListChanged")

                if txt == "" then
                    TBH.NotifyLocally("Background image removed.", 0, 5)
                elseif TBH.Theme.bgMaterial then
                    TBH.NotifyLocally("Background image applied!", 1, 5)
                end
            end

            local browseBtn = bg:Button("Browse .png / .jpg in garrysmod/data...")
            browseBtn.DoClick = function()
                TBH.OpenBgImagePicker(function(picked)
                    if IsValid(bgEntry) then bgEntry:SetText(picked) end
                end)
            end

            local applyBg = bg:Button("Apply background image")
            applyBg.DoClick = ApplyBackground

            bg:NumSlider("Transparency (0 = invisible, 255 = solid)", "hotloader_theme_alpha", 0, 255, 0)

            --------------------------------------------------------------
            -- 6. diagnostics
            --------------------------------------------------------------
            local diag = Section("Diagnostics", false)
            diag:CheckBox("Verbose hotload logs in console", "hotloader_logs")
            diag:CheckBox("Verbose debug log to .txt file", "hotloader_verbose_log")
            diag:ControlHelp("Off by default. Writes much more detail to garrysmod/data/hotloader_crash_log_client.txt, so the file gets big. Only turn it on while chasing a misbehaving hotload.")

            --------------------------------------------------------------
            -- 7. tips
            --------------------------------------------------------------
            local tips = Section("Tips", false)
            tips:Help("Hotloaded tools show up in the tool menu after the spawnmenu refreshes, new weapons and entities in their spawn tabs. If a tool is missing you can still select it with: gmod_tool <toolname>")
            tips:Help("GModPatchTool gives GMod a modern web engine so the Hotloader Browser renders every page properly: github.com/solsticegamestudios/GModPatchTool")
        end)
    end)

    -- V.1.0.1: hotloader_reload_theme console command - manually re-applies the
    -- theme (useful when the live-convar-callback path didn't trigger)
    concommand.Add("hotloader_reload_theme", function()
        TBH.LoadTheme()
        hook.Run("TBH.ClientListChanged")
        if TBH.ApplyBrowserTheme then TBH.ApplyBrowserTheme() end
        TBH.Msg("Theme reloaded.")
    end)

    ------------------------------------------------------------------------------
    -- V.1.0.4: data-folder image picker for the background option
    -- (DFileBrowser rooted at garrysmod/data, filtered to .png/.jpg/.jpeg)
    ------------------------------------------------------------------------------

    -- the old picker used DFileBrowser with SetPath("data") and a ';' separated
    -- filter, neither works (path has to be "DATA" and file.Find only takes one
    -- wildcard). this is a small picker on plain file.Find, folders + images only

    function TBH.OpenBgImagePicker(onPick)
        if IsValid(TBH.BgPickerFrame) then
            TBH.BgPickerFrame:Remove()
        end

        local frame = vgui.Create("DFrame")
        TBH.BgPickerFrame = frame
        frame:SetTitle("Pick a background image (garrysmod/data)")
        frame:SetSize(700, 480)
        frame:Center()
        frame:MakePopup()
        frame:SetDeleteOnClose(true)

        local ok, err = pcall(function()
            local currentFolder = "" -- relative to garrysmod/data, no trailing slash
            local selectedPath = nil
            local previewMat = nil

            local pathLabel = vgui.Create("DLabel", frame)
            pathLabel:Dock(TOP)
            pathLabel:SetTall(20)
            pathLabel:DockMargin(0, 0, 0, 4)

            local bottom = vgui.Create("DPanel", frame)
            bottom:Dock(BOTTOM)
            bottom:SetTall(32)
            bottom:DockMargin(0, 6, 0, 0)
            bottom.Paint = nil

            local preview = vgui.Create("DPanel", frame)
            preview:Dock(RIGHT)
            preview:SetWide(240)
            preview:DockMargin(6, 0, 0, 0)
            preview.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, TBH.Colors.bgPanel)

                if previewMat then
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.SetMaterial(previewMat)
                    surface.DrawTexturedRect(4, 4, w - 8, h - 8)
                else
                    draw.SimpleText("select an image", "TBH.Small", w / 2, h / 2, TBH.Colors.textdim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            local list = vgui.Create("DListView", frame)
            list:Dock(FILL)
            list:SetMultiSelect(false)
            list:AddColumn("Name")
            local typeCol = list:AddColumn("Type")
            typeCol:SetFixedWidth(70)

            local function IsImageName(name)
                local low = string.lower(name or "")
                return string.match(low, "%.png$") ~= nil
                    or string.match(low, "%.jpg$") ~= nil
                    or string.match(low, "%.jpeg$") ~= nil
            end

            local function SetPreview(path)
                previewMat = nil
                if not path then return end

                local okM, mat = pcall(Material, "../data/" .. path)
                if okM and mat and not mat:IsError() then
                    previewMat = mat
                end
            end

            local Populate

            local function OpenFolder(folder)
                currentFolder = folder or ""
                selectedPath = nil
                previewMat = nil
                Populate()
            end

            function Populate()
                list:Clear()
                pathLabel:SetText("  garrysmod/data/" .. currentFolder)

                local base = (currentFolder == "") and "" or (currentFolder .. "/")

                if currentFolder ~= "" then
                    local up = list:AddLine("[ .. up ]", "")
                    up.TBHUp = true
                end

                local files, dirs = file.Find(base .. "*", "DATA", "nameasc")

                for _, d in ipairs(dirs or {}) do
                    local line = list:AddLine("[ " .. d .. " ]", "folder")
                    line.TBHDir = base .. d
                end

                local count = 0
                for _, f in ipairs(files or {}) do
                    if IsImageName(f) then
                        local line = list:AddLine(f, string.upper(string.match(f, "%.(%w+)$") or ""))
                        line.TBHFile = base .. f
                        count = count + 1
                    end
                end

                if count == 0 and #(dirs or {}) == 0 and currentFolder == "" then
                    list:AddLine("(no .png / .jpg files in garrysmod/data yet)", "")
                end
            end

            local function Activate(line)
                if not IsValid(line) then return end

                if line.TBHUp then
                    local parent = string.match(currentFolder, "^(.*)/[^/]+$") or ""
                    OpenFolder(parent)
                elseif line.TBHDir then
                    OpenFolder(line.TBHDir)
                elseif line.TBHFile then
                    if isfunction(onPick) then onPick(line.TBHFile) end
                    if IsValid(frame) then frame:Close() end
                end
            end

            list.OnRowSelected = function(_, _, line)
                if line.TBHFile then
                    selectedPath = line.TBHFile
                    SetPreview(selectedPath)
                else
                    selectedPath = nil
                    previewMat = nil
                end
            end

            list.DoDoubleClick = function(_, _, line)
                Activate(line)
            end

            local selectBtn = vgui.Create("DButton", bottom)
            selectBtn:Dock(RIGHT)
            selectBtn:SetWide(120)
            selectBtn:DockMargin(6, 0, 0, 0)
            selectBtn:SetText("Select image")
            selectBtn.DoClick = function()
                if selectedPath then
                    if isfunction(onPick) then onPick(selectedPath) end
                    if IsValid(frame) then frame:Close() end
                else
                    TBH.NotifyLocally("Click an image in the list first (double-click opens folders).", 3, 5)
                end
            end

            local cancelBtn = vgui.Create("DButton", bottom)
            cancelBtn:Dock(RIGHT)
            cancelBtn:SetWide(90)
            cancelBtn:SetText("Cancel")
            cancelBtn.DoClick = function()
                if IsValid(frame) then frame:Close() end
            end

            Populate()
        end)

        if not ok then
            TBH.LogError("Image file browser failed to open: " .. tostring(err))
            if IsValid(frame) then frame:Remove() end
            TBH.NotifyLocally("File browser unavailable on this client - type the image path manually (e.g. mybg.png).", 3, 8)
        end
    end

    ------------------------------------------------------------------------------
    -- Console commands (client side)
    ------------------------------------------------------------------------------

    concommand.Add("hotloader_browser", function(ply, cmd, args)
        local url = table.concat(args or {}, " ")
        TBH.OpenBrowser(url ~= "" and url or nil)
    end)

    concommand.Add("hotloader_menu", function()
        local frame = vgui.Create("DFrame")
        frame:SetTitle("  Hotloader V." .. TBH.Version)
        frame:SetSize(math.min(ScrW() - 60, 760), math.min(ScrH() - 60, 640))
        frame:Center()
        frame:MakePopup()
        frame:SetSizable(true)
        frame:SetDeleteOnClose(true)

        local page = vgui.Create("TBH.MenuPage", frame)
        page:Dock(FILL)
        page:DockPadding(10, 10, 10, 10)
    end)

    concommand.Add("hotloader_list", function()
        local known = TBH.Client.Known or {}
        local count = 0

        MsgC(TBH.Colors.tag, "\n[Hotloader] session addons:\n")

        for wsid, data in pairs(known) do
            count = count + 1
            local mounted = TBH.Client.Mounted and TBH.Client.Mounted[wsid]
            local state = mounted and ("mounted, " .. mounted.files .. " files") or "not synced"
            MsgC(TBH.Colors.textdim, "  ", TBH.Colors.text, wsid, TBH.Colors.textdim, " - " .. (data.title or "?") .. " (" .. state .. ")\n")
        end

        if count == 0 then
            MsgC(TBH.Colors.textdim, "  nothing yet\n")
        end

        MsgC(TBH.Colors.tag, "\n")
    end)

    concommand.Add("hotloader_resync", function()
        TBH.Net:Start("resync")
        net.SendToServer()
        TBH.NotifyLocally("Requesting the addon list from the server...", 0)
    end)

    ------------------------------------------------------------------------------
    -- Welcome hints (shared by the boot sequence and hotloader_give_hints)
    --
    -- V.1.0.4: hints now pop as ACCENT-COLORED TOAST CARDS (bottom-right,
    -- stacked upward, auto-fade) instead of GMod's gray notification boxes,
    -- so they match the rest of the themed UI. Falls back to the classic
    -- notification if anything goes wrong - a hint is never lost.
    ------------------------------------------------------------------------------

    local HINTS = {
        "Welcome to Hotloader V." .. TBH.Version .. "! Press Q - the 'Hotloader' and 'Hotloader Browser' tabs are in the top tab row (next to Saves).",
        "SERVER OWNERS: on a DEDICATED server the gmsv_workshop module must be installed for hotloading (gmsv_workshop_win64.dll or gmsv_workshop_linux64.dll into garrysmod/lua/bin, v3.0.4+). Get it at github.com/nooshstuff/gmsv_workshop/releases. Listen servers and singleplayer do NOT need it.",
        "GModPatchTool is needed for the Hotloader Browser to show every website correctly. Without it GMod's old built-in web engine (CEF) can render Steam pages with missing images, empty lists or broken buttons. Install it (free): github.com/solsticegamestudios/GModPatchTool",
        "Something broken, or a player can't see an addon? RIGHT-CLICK it in the Hotloader tab and choose FORCE ADDON RELOAD - it unloads the addon for everyone and hotloads it again.",
        "A progress bar at the top of the screen shows addon downloads. The percentage is an estimate (shown with ~) unless the file can be tracked on disk. GMod's own Downloading popup at the bottom can't be hidden by addons.",
        "Custom menu background: put a 1920x1080 (16:9) .png or .jpg in garrysmod/data and pick it with Browse in Utilities > Hotloader > Settings & Info.",
        "Vehicle addons (LVS, LFS, Glide, simfphys and the armed packs): hotload the BASE addon first, then the packs. The hotloader re-links the base classes when each one finishes and warns you if a base is missing.",
        "Paste a Workshop link and press + PIN to save it to your Hotloader tab without hotloading it. It keeps its preview image, survives restarts, and you can hit HOTLOAD on it any time.",
        "CONFLICT RADAR: before an addon loads, the hotloader checks if it re-registers entities/weapons that already exist or shares lua files with another hotloaded addon, and tells you who owns them. Rows get a 'radar' badge, right-click > Conflict report, or run hotloader_conflicts.",
        "PIN your favorite addons with the star button on their row - pins are saved forever (data/hotloader_favorites.json) and the PINNED section re-hotloads them with one click after any restart.",
        "The WORKSHOP BROWSER switch at the top of the Hotloader tab surfs the Workshop - every addon page gets a HOTLOAD button (or LOAD MAP on map addons), colored to match your accent. The + PIN button there saves the page's addon to your list.",
        "Subscribe to a Workshop addon in the Steam overlay and it hotloads automatically (hotloader_autosubscribe).",
        "Turn an addon back ON in the Addons menu and it hotloads instantly (hotloader_enableaddons) - it's already downloaded.",
        "Hotloaded a map addon? Hit LOAD MAP - the server switches and everyone gets the map. You can pin maps too: a pinned map gets its own LOAD MAP button that hotloads it and switches for you.",
        "NEW: paste a Workshop COLLECTION link and the whole collection hotloads in one go!",
        "The UNLOAD button on each addon removes its hooks/timers/menus (files stay mounted - GMod can't unmount)",
        "Right-click an addon in the session list for more options (pin, copy id, open page, unload...). Disable hints with hotloader_hints 0.",
        "Utilities > Settings & Info lets you pick an accent color (the browser + these hints match it), set a background image (.png/.jpg), and toggle verbose debug logging.",
    }

    TBH.HintToasts = TBH.HintToasts or {}

    -- repositions the toast stack (bottom-right, newest at the bottom)
    function TBH.LayoutHintToasts()
        -- drop dead entries first
        for i = #TBH.HintToasts, 1, -1 do
            if not IsValid(TBH.HintToasts[i]) then
                table.remove(TBH.HintToasts, i)
            end
        end

        -- cap the stack at 6 - oldest gets dropped
        while #TBH.HintToasts > 6 do
            local old = table.remove(TBH.HintToasts, 1)
            if IsValid(old) then old:Remove() end
        end

        local x = math.max(8, ScrW() - 368)
        local y = ScrH() - 20

        for i = #TBH.HintToasts, 1, -1 do
            local t = TBH.HintToasts[i]
            y = y - t:GetTall() - 6
            t:SetPos(x, y)
        end
    end

    function TBH.ShowHint(text)
        if SERVER then return end
        if not isstring(text) or text == "" then return end

        local ok, err = pcall(function()
            -- escape markup-sensitive characters so the hint text always
            -- parses (hints contain > and & in their wording)
            local esc = string.gsub(text, "&", "&amp;")
            esc = string.gsub(esc, "<", "&lt;")
            esc = string.gsub(esc, ">", "&gt;")

            local mp = markup.Parse("<font=TBH.Body>" .. esc .. "</font>", 328)

            local toast = vgui.Create("DPanel")
            toast:SetSize(360, mp:GetHeight() + 40)
            toast:SetAlpha(0)
            toast.Paint = function(_, w, h)
                -- reads TBH.Colors LIVE, so an accent change re-themes
                -- toasts that are still on screen
                draw.RoundedBox(6, 0, 0, w, h, TBH.Colors.bgPanel)
                draw.RoundedBoxEx(6, 0, 0, 5, h, TBH.Colors.accent, true, false, true, false)
                draw.SimpleText("HOTLOADER", "TBH.Small", 16, 9, TBH.Colors.tag)
                mp:Draw(16, 27)
            end

            local life = 8
            toast:AlphaTo(255, 0.25, 0, nil)
            toast:AlphaTo(0, 0.5, life - 0.5, function()
                if IsValid(toast) then toast:Remove() end
            end)

            function toast:OnRemove()
                TBH.LayoutHintToasts()
            end

            TBH.HintToasts[#TBH.HintToasts + 1] = toast
            TBH.LayoutHintToasts()
        end)

        if not ok then
            -- never lose a hint because the themed toast failed
            TBH.LogError("Hint toast failed: " .. tostring(err))
            notification.AddLegacy("[Hotloader] " .. text, NOTIFY_GENERIC, 8)
        end
    end

    concommand.Add("hotloader_give_hints", function()
        for i = 1, #HINTS do
            -- slight cascade so the toasts stack up one after another
            timer.Simple((i - 1) * 0.25, function()
                TBH.ShowHint(HINTS[i])
            end)
        end
    end)

    if TBH.CVarHints and TBH.CVarHints:GetBool() then
        local schedule = { 8, 16, 24, 32, 40, 50, 60, 70 }

        for i = 1, #HINTS do
            local delay = schedule[i] or (8 + i * 9)

            timer.Simple(delay, function()
                if TBH.CVarHints and TBH.CVarHints:GetBool() then
                    surface.PlaySound("buttons/button15.wav")
                    TBH.ShowHint(HINTS[i])
                end
            end)
        end
    end

    ------------------------------------------------------------------------------
    -- Client boot message
    ------------------------------------------------------------------------------

    timer.Simple(6, function()
        MsgC(TBH.Colors.tag, "\n[Hotloader] v" .. TBH.Version .. " loaded (CLIENT)\n")
        MsgC(TBH.Colors.text, "[Hotloader] Q -> 'Hotloader' + 'Installed Addons' tabs (top row) | hotloader_browser | hotloader_hotload <id> | subscribe/enable = auto-hotload | maps = LOAD MAP\n\n")
    end)
end

--------------------------------------------------------------------------------
-- FILESYSTEM tab: live lua runner (shared) + "RUN SERVER" push
--
-- RunLua(rel, code) is what the editor calls when you save / press RUN. rel is the path
-- relative to lua/ (e.g. "weapons/my_swep/shared.lua").
--   * weapons / entities / effects get re-registered (their entry file for THIS realm
--     is run in a private environment so SWEP / ENT is the table, include() reads the
--     other files, and your unsaved text wins over the file on disk). functions of the
--     new table are also pushed into entities that already exist, so they update live
--   * everything else is compiled and run as a plain chunk
--------------------------------------------------------------------------------
TBH.FS = TBH.FS or {}

do
    local FS = TBH.FS

    FS.ServerLuaCVar = SERVER and (GetConVar("hotloader_fs_serverlua") or CreateConVar("hotloader_fs_serverlua", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Let superadmins push lua from the Filesystem tab editor to the server (RUN SERVER). The listen server host is always allowed. 0 = off")) or nil

    function FS.Classify(rel)
        for _, kind in ipairs({ "weapons", "entities", "effects" }) do
            local single = string.match(rel, "^" .. kind .. "/([^/]+)%.lua$")
            if single then return kind, single, nil end

            local cls, sub = string.match(rel, "^" .. kind .. "/([^/]+)/(.+)$")
            if cls then return kind, cls, sub end
        end
    end

    local function ReadLua(path, overrides)
        if overrides[path] then return overrides[path] end
        return file.Read(path, "LUA")
    end

    local function RunPlain(rel, code)
        local fn = CompileString(code, "hotloader_fs/" .. rel, false)
        if isstring(fn) then return false, fn end

        local ok, err = pcall(fn)
        if not ok then return false, tostring(err) end

        return true, "ran " .. rel
    end

    local function RunScripted(kind, class, sub, rel, code)
        local overrides = { [rel] = code }
        local entry

        if not sub then
            entry = rel
        else
            local dir = kind .. "/" .. class .. "/"
            local list = SERVER and { "init.lua", "shared.lua" } or { "cl_init.lua", "shared.lua" }
            if kind == "effects" then list = { "init.lua", "cl_init.lua" } end

            for _, name in ipairs(list) do
                if overrides[dir .. name] or file.Exists(dir .. name, "LUA") then
                    entry = dir .. name
                    break
                end
            end

            if not entry then return false, "no " .. (SERVER and "init.lua" or "cl_init.lua") .. " / shared.lua found for " .. class end
        end

        if kind == "effects" and SERVER then return false, "effects only exist on the client" end

        local tbl
        local global
        if kind == "weapons" then
            tbl = { Primary = {}, Secondary = {}, Folder = "weapons/" .. class, ClassName = class }
            global = "SWEP"
        elseif kind == "entities" then
            tbl = { Folder = "entities/" .. class, ClassName = class }
            global = "ENT"
        else
            tbl = {}
            global = "EFFECT"
        end

        local env = setmetatable({}, { __index = _G })
        env[global] = tbl
        env.AddCSLuaFile = function() end

        local curDir = string.match(entry, "^(.*/)[^/]+$") or ""
        local depth = 0

        local function RunFile(path)
            depth = depth + 1
            if depth > 12 then error("include depth too deep: " .. path) end

            local src = ReadLua(path, overrides)
            if not src then
                depth = depth - 1
                error("include: could not read " .. path)
            end

            local fn = CompileString(src, "hotloader_fs/" .. path, false)
            if isstring(fn) then
                depth = depth - 1
                error(fn, 0)
            end

            setfenv(fn, env)

            local prevDir = curDir
            curDir = string.match(path, "^(.*/)[^/]+$") or ""
            local res = fn()
            curDir = prevDir
            depth = depth - 1

            return res
        end

        env.include = function(name)
            local try = { curDir .. name, name }
            for _, p in ipairs(try) do
                if ReadLua(p, overrides) then return RunFile(p) end
            end
            return include(name)
        end

        local ok, err = pcall(RunFile, entry)
        if not ok then return false, tostring(err) end

        if kind == "weapons" then
            weapons.Register(tbl, class)
            if weapons.OnLoaded then weapons.OnLoaded() end
        elseif kind == "entities" then
            scripted_ents.Register(tbl, class)
            if scripted_ents.OnLoaded then scripted_ents.OnLoaded() end
        else
            effects.Register(tbl, class)
        end

        -- entities that already exist keep their own copy of the functions: refresh those
        local refreshed = 0
        if kind ~= "effects" then
            for _, ent in ipairs(ents.FindByClass(class)) do
                for k, v in pairs(tbl) do
                    if isfunction(v) then ent[k] = v end
                end
                refreshed = refreshed + 1
            end
        end

        return true, "re-registered " .. kind .. "/" .. class .. " (" .. entry .. "), " .. refreshed .. " existing entit" .. (refreshed == 1 and "y" or "ies") .. " updated"
    end

    function FS.RunLua(rel, code)
        local kind, class, sub = FS.Classify(rel)
        local ok, res, msg = pcall(function()
            if kind then return RunScripted(kind, class, sub, rel, code) end
            return RunPlain(rel, code)
        end)

        if not ok then return false, tostring(res) end
        return res, msg
    end

    if CLIENT then
        local MAX_COMPRESSED = 60000

        function FS.SendToServer(rel, code)
            local comp = util.Compress(code)
            if not comp or #comp > MAX_COMPRESSED then
                return false, "file is too big to send in one message (" .. (comp and #comp or 0) .. " bytes compressed, max " .. MAX_COMPRESSED .. ")"
            end

            TBH.Net:Start("fsrun")
            net.WriteString(rel)
            net.WriteUInt(#comp, 32)
            net.WriteData(comp, #comp)
            net.SendToServer()

            return true, "sent to the server, waiting for the result..."
        end

        TBH.Net:Receive("fsresult", function()
            local ok = net.ReadBool()
            local msg = net.ReadString()
            TBH.NotifyLocally("SERVER: " .. msg, ok and 1 or 2, 6)
        end)
    end

    if SERVER then
        local function Reply(ply, ok, msg)
            if not IsValid(ply) then
                TBH.Msg("FS: " .. msg, ok and TBH.Colors.ok or TBH.Colors.error)
                return
            end

            TBH.Net:Start("fsresult")
            net.WriteBool(ok)
            net.WriteString(string.sub(msg, 1, 400))
            net.Send(ply)
        end

        TBH.Net:Receive("fsrun", function(len, ply)
            local rel = net.ReadString()
            local size = net.ReadUInt(32)

            if not IsValid(ply) then return end

            local allowed = ply:IsListenServerHost()
                or (ply:IsSuperAdmin() and FS.ServerLuaCVar:GetBool())

            if not allowed then
                Reply(ply, false, "permission denied (superadmin + hotloader_fs_serverlua 1 needed)")
                return
            end

            if size == 0 or size > 60000 then
                Reply(ply, false, "bad message size")
                return
            end

            local comp = net.ReadData(size)
            local code = util.Decompress(comp)

            if not isstring(code) or #code > 400000 then
                Reply(ply, false, "could not decompress the file (or it is too big)")
                return
            end

            if #rel > 260 or string.find(rel, "..", 1, true) or string.sub(rel, -4) ~= ".lua" then
                Reply(ply, false, "invalid path: " .. string.sub(rel, 1, 80))
                return
            end

            local ok, msg = FS.RunLua(rel, code)
            TBH.Msg("FS: " .. ply:Nick() .. " ran " .. rel .. " -> " .. tostring(msg), ok and TBH.Colors.ok or TBH.Colors.error)
            Reply(ply, ok, tostring(msg))
        end)
    end
end

--------------------------------------------------------------------------------
-- FILESYSTEM tab: GLOBAL PLAY (audio player plays a sound for everyone)
--
-- the client sends the game path ("sound/...") to the server, the server checks the
-- sender and broadcasts it, every client streams its own copy of the file. players
-- who don't have the file simply hear nothing.
-- hotloader_fs_globalsound: 0 = off, 1 = admins (default), 2 = superadmins. the
-- listen server host is always allowed
--------------------------------------------------------------------------------
do
    local FS = TBH.FS
    FS.GlobalChannels = FS.GlobalChannels or {}

    local function StopAll()
        for _, ch in ipairs(FS.GlobalChannels) do
            if IsValid(ch) then ch:Stop() end
        end
        FS.GlobalChannels = {}
    end

    if CLIENT then
        function FS.GlobalPlay(path, vol, pitch)
            TBH.Net:Start("fsglobalplay")
            net.WriteString(path)
            net.WriteFloat(vol)
            net.WriteFloat(pitch)
            net.SendToServer()
        end

        function FS.GlobalStop()
            TBH.Net:Start("fsglobalstop")
            net.SendToServer()
        end

        TBH.Net:Receive("fsglobalplay", function()
            local path = net.ReadString()
            local vol = math.Clamp(net.ReadFloat(), 0, 1)
            local pitch = math.Clamp(net.ReadFloat(), 0.1, 3)

            if not file.Exists(path, "GAME") then return end

            for i = #FS.GlobalChannels, 1, -1 do
                if not IsValid(FS.GlobalChannels[i]) then table.remove(FS.GlobalChannels, i) end
            end

            if #FS.GlobalChannels >= 8 then
                local old = table.remove(FS.GlobalChannels, 1)
                if IsValid(old) then old:Stop() end
            end

            sound.PlayFile(path, "", function(ch)
                if not IsValid(ch) then return end
                ch:SetVolume(vol)
                ch:SetPlaybackRate(pitch)
                FS.GlobalChannels[#FS.GlobalChannels + 1] = ch
            end)
        end)

        TBH.Net:Receive("fsglobalstop", StopAll)
    end

    if SERVER then
        local cvar = GetConVar("hotloader_fs_globalsound") or CreateConVar("hotloader_fs_globalsound", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Who may use GLOBAL PLAY in the Filesystem tab audio player. 0 = nobody, 1 = admins, 2 = superadmins (listen server host always allowed)")
        local last = {}

        local function Allowed(ply)
            if not IsValid(ply) then return false end
            if ply:IsListenServerHost() then return true end

            local level = cvar:GetInt()
            if level <= 0 then return false end
            if level >= 2 then return ply:IsSuperAdmin() end
            return ply:IsAdmin()
        end

        TBH.Net:Receive("fsglobalplay", function(len, ply)
            local path = string.lower(net.ReadString())
            local vol = net.ReadFloat()
            local pitch = net.ReadFloat()

            if not Allowed(ply) then
                TBH.Net:Start("fsresult")
                net.WriteBool(false)
                net.WriteString("global play is not allowed for you (hotloader_fs_globalsound)")
                net.Send(ply)
                return
            end

            if (last[ply] or 0) > CurTime() then return end
            last[ply] = CurTime() + 0.75

            local ext = string.match(path, "%.(%w+)$")
            if #path > 200 or string.sub(path, 1, 6) ~= "sound/" or string.find(path, "..", 1, true)
                or not (ext == "wav" or ext == "mp3" or ext == "ogg") then
                return
            end

            TBH.Msg("FS: " .. ply:Nick() .. " played " .. path .. " for everyone")

            TBH.Net:Start("fsglobalplay")
            net.WriteString(path)
            net.WriteFloat(math.Clamp(vol, 0, 1))
            net.WriteFloat(math.Clamp(pitch, 0.1, 3))
            net.Broadcast()
        end)

        TBH.Net:Receive("fsglobalstop", function(len, ply)
            if not Allowed(ply) then return end
            TBH.Net:Start("fsglobalstop")
            net.Broadcast()
        end)
    end
end

--------------------------------------------------------------------------------
-- Shared console commands (server-realm parts)
--------------------------------------------------------------------------------

if SERVER then
    concommand.Add("hotloader_hotload", function(ply, cmd, args)
        local input = args and args[1]

        if not input or input == "" then
            TBH.Msg("Usage: hotloader_hotload <workshop id or url>")
            return
        end

        TBH.Server.Request(ply, input, true, "")
    end)

    concommand.Add("hotloader_list", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local count = 0
        MsgC(TBH.Colors.tag, "\n[Hotloader] server hotload registry:\n")

        for wsid, data in pairs(TBH.Server.Mounted) do
            count = count + 1
            MsgC(TBH.Colors.textdim, "  ", TBH.Colors.text, wsid, TBH.Colors.textdim,
                " - " .. (data.title or "?") .. " (" .. data.files .. " files, " ..
                tostring(data.errors) .. " errors, " .. os.date("%H:%M", data.time) .. ")\n")
        end

        if count == 0 then
            MsgC(TBH.Colors.textdim, "  nothing yet\n")
        end

        MsgC(TBH.Colors.tag, "\n")
    end)

    concommand.Add("hotloader_resync", function(ply)
        if IsValid(ply) then return end -- players use the client command

        for _, p in ipairs(player.GetAll()) do
            TBH.Server.SendSyncList(p)
        end

        TBH.Msg("Re-synced every player.")
    end)

    TBH.Net:Receive("hello", function(len, ply)
        if not IsValid(ply) then return end

        TBH.Net:Start("info")
        net.WriteUInt(0, 8) -- permission level: 0 = everyone
        net.WriteBool(TBH.CVarRequirements:GetBool())
        net.WriteBool(TBH.ServerCanUGC or false)
        net.WriteUInt(math.Clamp(table.Count(TBH.Server.Mounted), 0, 65535), 16)
        net.WriteString(TBH.Version)
        net.WriteUInt(math.Clamp(TBH.CVarBatchDelay:GetInt(), 0, 255), 8)
        net.WriteBool(TBH.ServerCanUnmount or false)
        net.Send(ply)

        -- the client only says hello once its Lua is up and its receivers exist, so THIS
        -- is the moment a late joiner can actually receive the addon list
        if TBH.CVarLateSync:GetBool() then
            timer.Simple(0.5, function()
                if IsValid(ply) then TBH.Server.SendSyncList(ply) end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Client console command for hotloading (routes through the server)
--------------------------------------------------------------------------------

if CLIENT then
    concommand.Add("hotloader_hotload", function(ply, cmd, args)
        local input = args and args[1]

        if not input or input == "" then
            TBH.NotifyLocally("Usage: hotloader_hotload <workshop id or url>", 3)
            return
        end

        TBH.RequestHotload(input, "")
    end)
end

--------------------------------------------------------------------------------
-- Server boot banner
--------------------------------------------------------------------------------

if SERVER then
    timer.Simple(3, function()
        MsgC(TBH.Colors.tag, "\n")
        MsgC(TBH.Colors.tag, "  ============================================================\n")
        MsgC(TBH.Colors.tag, "   HOTLOADER v" .. TBH.Version .. " (SERVER)\n")
        MsgC(TBH.Colors.tag, "  ============================================================\n")

        if TBH.ServerCanUGC then
            MsgC(TBH.Colors.ok, "   gmsv_workshop module: LOADED - server-side downloads enabled\n")
        elseif game.IsDedicated() then
            MsgC(TBH.Colors.error, "   gmsv_workshop module: MISSING (dedicated server!)\n")
            MsgC(TBH.Colors.error, "   Hotloading will NOT work until you install it:\n")
            MsgC(TBH.Colors.text, "     1. Download gmsv_workshop v3.0.4+ (win64/linux64) from\n")
            MsgC(TBH.Colors.text, "        https://github.com/nooshstuff/gmsv_workshop/releases\n")
            MsgC(TBH.Colors.text, "     2. Drop it into garrysmod/lua/bin/ (create the folder)\n")
            MsgC(TBH.Colors.text, "     3. Restart the server (use srcds_run_x64 for 64-bit!)\n")
        else
            MsgC(TBH.Colors.warn, "   gmsv_workshop module: not installed (listen server)\n")
            MsgC(TBH.Colors.text, "   Downloads will be routed through the host player instead.\n")
        end

        MsgC(TBH.Colors.text, "   Console: hotloader_hotload <id or url> | hotloader_loadmap | hotloader_list | hotloader_resync | hotloader_wipe | hotloader_pins\n")
        MsgC(TBH.Colors.tag, "  ============================================================\n\n")
    end)
end