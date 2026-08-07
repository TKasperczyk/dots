-- Tint the terminal background + statusline accent so parallel sessions are
-- identifiable at a glance. The model: a PROJECT (the shell's cwd) owns a
-- hue, deterministically from its hash; panes of that project are shades of
-- it, farthest-first, and are allowed to resemble each other -- similarity
-- within a project is information. Live projects coordinate through claim
-- files so two different projects never sit on nearby hues.
--
-- All colour math happens in OKLab/OKLCH, not HSL/luma. Every earlier model
-- broke on a different hue because RGB-adjacent spaces are perceptually
-- non-uniform (equal HSL lightness made yellow glow, equal Rec.709 luma made
-- blue neon and green lurid). In OKLab, equal L is equally dark and equal C
-- is equally muted for every hue, and Euclidean distance is roughly perceived
-- difference -- the three properties this feature actually needs.
--
-- Emulator-agnostic: colours go out as OSC 11 / OSC 111 on the tty (the
-- osc52_clipboard.lua passthrough trick). No remote-control protocols.

local M = {}

-- 8 OKLCH hue angles picked for nameability: red, orange, yellow, green,
-- teal, blue, violet, magenta. hash(cwd) -> hue is deterministic across
-- launches and machines.
local FAMILY_HUES = { 25, 60, 100, 140, 180, 240, 290, 340 }
local N_FAMILIES = #FAMILY_HUES

-- Background shade slots (OKLab L, chroma C), farthest-first in L. The band
-- is calibrated to the brightness that was already accepted in the pre-OKLab
-- iteration: its gamma-luma cap of 55 corresponds to OKLab L 0.34, so that is
-- the ceiling -- anything higher reads as glare over a bright wallpaper.
-- The compressed band leaves room for only ~2 distinct shades per family;
-- beyond that the allocator crosses families, which is the intended trade
-- (distinctness beats hue loyalty).
-- C is a whisper on purpose -- the wash is ambience, the accent is the
-- identifier. Chroma cuts are the one monotonic knob: lower C is less
-- saturated for every hue identically, converging on "no wash" at zero.
local SHADES = {
    { L = 0.23, C = 0.028 },
    { L = 0.29, C = 0.040 },
    { L = 0.26, C = 0.022 },
    { L = 0.21, C = 0.036 },
    { L = 0.28, C = 0.026 },
    { L = 0.24, C = 0.045 },
}

-- Statusline accent per shade slot: same hue, bright and vivid. The block is
-- the loud identifier; the background wash is only ambience.
local ACCENT_L = { 0.68, 0.80, 0.74, 0.62, 0.77, 0.65 }
local ACCENT_C = 0.16

-- Minimum OKLCH hue separation between two different live PROJECTS. Panes of
-- one project deliberately share a hue -- similarity within a project is
-- information, not a defect -- so coordination happens per project: a new
-- project whose preferred hue sits closer than this to a live one takes the
-- farthest free family hue instead.
local MIN_HUE_DIST = 80

local CLAIM_DIR = (vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/nvim-pane-tint"
pcall(vim.fn.mkdir, CLAIM_DIR, "p")

-- djb2. Deliberately not using bit ops: doubles hold h * 33 exactly well below
-- 2^53, so this stays portable and needs no luajit `bit` dependency.
local function hash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return h
end

-- ---- OKLab <-> sRGB (Björn Ottosson's reference coefficients) -------------

local function srgb_to_linear(c)
    c = c / 255
    return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function linear_to_srgb(c)
    c = math.max(0, math.min(1, c))
    local v = c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055
    return math.floor(v * 255 + 0.5)
end

-- Returns r,g,b in 0-255, or nil when the OKLab point is outside sRGB.
local function rgb_from_oklab(L, a, b)
    local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
    local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
    local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
    local r  =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    local g  = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    local b2 = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    if r < -0.001 or r > 1.001 or g < -0.001 or g > 1.001 or b2 < -0.001 or b2 > 1.001 then
        return nil
    end
    return linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(b2)
end

-- OKLCH -> hex, shrinking chroma until the colour fits sRGB. Dark saturated
-- corners of the gamut are exactly where our shades live, so the clamp runs
-- often and must preserve L and hue, sacrificing only vividness.
local function oklch_hex(L, C, H)
    local rad = math.rad(H)
    for _ = 1, 12 do
        local r, g, b = rgb_from_oklab(L, C * math.cos(rad), C * math.sin(rad))
        if r then return string.format("#%02x%02x%02x", r, g, b) end
        C = C * 0.82
    end
    local r, g, b = rgb_from_oklab(L, 0, 0)
    return string.format("#%02x%02x%02x", r or 40, g or 40, b or 40)
end

-- ---- project identity ------------------------------------------------------

-- The project identity is the *shell's* cwd, not nvim's: nvim is launched
-- from $HOME and the shell inside the terminal then cds to the project.
-- /proc/<pid>/cwd follows the shell's cd live and comes back symlink-resolved
-- by the kernel, so ~/Programming and /mnt/Programming agree for free.
local function project_id()
    local dir
    local pid = vim.b.terminal_job_pid
    if pid then
        dir = (vim.uv or vim.loop).fs_readlink("/proc/" .. pid .. "/cwd")
    end
    if not dir then
        local cwd = vim.fn.getcwd()
        dir = (vim.uv or vim.loop).fs_realpath(cwd) or cwd
    end
    local h = hash(dir)
    return tostring(h), h % N_FAMILIES
end

-- ---- claims ----------------------------------------------------------------

local function claim_path()
    return CLAIM_DIR .. "/" .. vim.fn.getpid()
end

local function pid_alive(pid)
    return (vim.uv or vim.loop).fs_stat("/proc/" .. pid) ~= nil
end

-- Live claims from other panes: { project, family, shade } each. Claims from
-- dead pids are deleted on sight.
local function live_claims()
    local claims = {}
    local ok, entries = pcall(vim.fn.readdir, CLAIM_DIR)
    if not ok or type(entries) ~= "table" then return claims end

    local mypid = vim.fn.getpid()
    for _, name in ipairs(entries) do
        local path = CLAIM_DIR .. "/" .. name
        local pid = tonumber(name)
        if pid and pid ~= mypid then
            if not pid_alive(pid) then
                pcall(vim.fn.delete, path)
            else
                local read_ok, lines = pcall(vim.fn.readfile, path)
                if read_ok and lines and lines[1] and tonumber(lines[2]) and tonumber(lines[3]) then
                    claims[#claims + 1] = {
                        project = lines[1],
                        family  = tonumber(lines[2]),
                        shade   = tonumber(lines[3]),
                    }
                end
            end
        end
    end
    return claims
end

function M.color_for(family, shade_idx)
    local shade = SHADES[shade_idx]
    return oklch_hex(shade.L, shade.C, FAMILY_HUES[family + 1])
end

local function hue_dist(fam_a, fam_b)
    local d = math.abs(FAMILY_HUES[fam_a + 1] - FAMILY_HUES[fam_b + 1]) % 360
    return math.min(d, 360 - d)
end

-- Family: panes of a live project follow its existing choice; a new project
-- takes its hash-preferred hue unless a DIFFERENT live project sits within
-- MIN_HUE_DIST of it (the teal-next-to-blue case), in which case it takes the
-- family farthest from every hue in use. Shade: farthest-first slot unused by
-- this project's own panes, cycling once exhausted -- same-project siblings
-- may end up similar, which is intended.
local function pick_color(project, preferred)
    local claims = live_claims()

    local family
    local used = {}
    for _, c in ipairs(claims) do
        if c.project == project then
            family = family or c.family
        else
            used[c.family] = true
        end
    end

    if not family then
        local function min_dist(fam)
            local d = math.huge
            for other in pairs(used) do
                d = math.min(d, hue_dist(fam, other))
            end
            return d
        end
        if min_dist(preferred) >= MIN_HUE_DIST then
            family = preferred
        else
            -- Bumped project. Taking the single farthest hue makes EVERY
            -- bumped project a deterministic function of the live set alone,
            -- so Downloads and Projects/GEN render identically. Instead,
            -- collect all families within tolerance of the best separation
            -- and index into them by project hash -- still deterministic per
            -- project, but different bumped projects spread out.
            local scored = {}
            local best_d = -1
            for fam = 0, N_FAMILIES - 1 do
                local d = min_dist(fam)
                scored[#scored + 1] = { fam = fam, d = d }
                best_d = math.max(best_d, d)
            end
            table.sort(scored, function(a, b)
                if a.d ~= b.d then return a.d > b.d end
                return a.fam < b.fam
            end)
            local floor = math.max(best_d - 25, 35)
            local pool = {}
            for _, s in ipairs(scored) do
                if s.d >= floor then pool[#pool + 1] = s.fam end
            end
            if #pool == 0 then pool = { scored[1].fam } end
            family = pool[(tonumber(project) % #pool) + 1]
        end
    end

    local my_shades, my_count = {}, 0
    for _, c in ipairs(claims) do
        if c.project == project then
            my_shades[c.shade] = true
            my_count = my_count + 1
        end
    end
    local shade
    for i = 1, #SHADES do
        if not my_shades[i] then shade = i break end
    end
    shade = shade or (my_count % #SHADES) + 1

    return M.color_for(family, shade), family, shade
end

-- ---- application -----------------------------------------------------------

-- OSC to the outer terminal. v.stderr is the tty nvim's UI writes to; the
-- sequence passes through nvim's terminal layer untouched.
local function osc(seq)
    pcall(vim.fn.chansend, vim.v.stderr, seq)
end

-- applied_project is the idempotence key: re-pick only when the shell changes
-- project. Under contention the allocator may render a different family than
-- the project's hash-preferred one, so the accent derives from render_family.
local applied_project, applied_color
local render_family, render_shade

-- The statusline block colour for the current session, or nil when untinted.
-- fg flips black/white on the accent's own L so the topic stays readable.
function M.accent()
    if not render_family then return nil end

    local L = ACCENT_L[render_shade]
    return {
        bg = oklch_hex(L, ACCENT_C, FAMILY_HUES[render_family + 1]),
        fg = L > 0.65 and "#000000" or "#ffffff",
    }
end

-- Idempotent: called from the title poll, but only touches disk and the tty
-- when the shell actually changes project (new session, or cd elsewhere).
function M.apply()
    local project, preferred = project_id()
    if project == applied_project then return applied_color end

    local color, fam_used, shade_idx = pick_color(project, preferred)
    pcall(vim.fn.writefile,
        { project, tostring(fam_used), tostring(shade_idx), color }, claim_path())
    osc("\x1b]11;" .. color .. "\x07")

    applied_project, applied_color = project, color
    render_family, render_shade = fam_used, shade_idx
    return color
end

-- The emulator keeps an OSC 11 background after nvim exits; OSC 111 puts its
-- configured default back. Runs from the 500ms poll for every non-terminal
-- buffer, so the not-tinted path must stay free of disk and tty work.
function M.reset()
    if not applied_project and vim.fn.filereadable(claim_path()) == 0 then return end

    applied_project, applied_color = nil, nil
    render_family, render_shade = nil, nil
    pcall(vim.fn.delete, claim_path())
    osc("\x1b]111\x07")
end

return M
