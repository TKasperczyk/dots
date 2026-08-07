-- Tint the terminal background + statusline accent so parallel sessions are
-- identifiable at a glance. The project (the shell's cwd) deterministically
-- picks a hue; live sessions coordinate through claim files so any two panes
-- keep a minimum perceptual distance -- across projects, not just within one.
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

-- Background shade slots (OKLab L, chroma C), farthest-first in L. All dark
-- enough for light foreground text; C stays low so no hue can be loud.
local SHADES = {
    { L = 0.30, C = 0.060 },
    { L = 0.45, C = 0.085 },
    { L = 0.37, C = 0.045 },
    { L = 0.26, C = 0.075 },
    { L = 0.42, C = 0.060 },
    { L = 0.33, C = 0.090 },
}

-- Statusline accent per shade slot: same hue, bright and vivid. The block is
-- the loud identifier; the background wash is only ambience.
local ACCENT_L = { 0.68, 0.80, 0.74, 0.62, 0.77, 0.65 }
local ACCENT_C = 0.16

-- Minimum OKLab distance any new pane must keep from every live pane. When a
-- project's own preferred shades can't satisfy it, the allocator walks the
-- whole candidate grid for the farthest option instead of duplicating.
local MIN_DELTA = 0.09

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

local function oklab_from_rgb(r8, g8, b8)
    local r, g, b = srgb_to_linear(r8), srgb_to_linear(g8), srgb_to_linear(b8)
    local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
    local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
    local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
           1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
           0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
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

local function delta_e(hex1, hex2)
    local function lab(hex)
        return oklab_from_rgb(
            tonumber(hex:sub(2, 3), 16),
            tonumber(hex:sub(4, 5), 16),
            tonumber(hex:sub(6, 7), 16))
    end
    local L1, a1, b1 = lab(hex1)
    local L2, a2, b2 = lab(hex2)
    return math.sqrt((L1 - L2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

-- ---- project identity ------------------------------------------------------

-- The project identity is the *shell's* cwd, not nvim's: nvim is launched
-- from $HOME and the shell inside the terminal then cds to the project.
-- /proc/<pid>/cwd follows the shell's cd live and comes back symlink-resolved
-- by the kernel, so ~/Programming and /mnt/Programming agree for free.
local function family_for_cwd()
    local dir
    local pid = vim.b.terminal_job_pid
    if pid then
        dir = (vim.uv or vim.loop).fs_readlink("/proc/" .. pid .. "/cwd")
    end
    if not dir then
        local cwd = vim.fn.getcwd()
        dir = (vim.uv or vim.loop).fs_realpath(cwd) or cwd
    end
    return hash(dir) % N_FAMILIES
end

-- ---- claims ----------------------------------------------------------------

local function claim_path()
    return CLAIM_DIR .. "/" .. vim.fn.getpid()
end

local function pid_alive(pid)
    return (vim.uv or vim.loop).fs_stat("/proc/" .. pid) ~= nil
end

-- Colours of other *live* panes. Claims from dead pids are deleted on sight.
local function live_colors()
    local colors = {}
    local ok, entries = pcall(vim.fn.readdir, CLAIM_DIR)
    if not ok or type(entries) ~= "table" then return colors end

    local mypid = vim.fn.getpid()
    for _, name in ipairs(entries) do
        local path = CLAIM_DIR .. "/" .. name
        local pid = tonumber(name)
        if pid and pid ~= mypid then
            if not pid_alive(pid) then
                pcall(vim.fn.delete, path)
            else
                local read_ok, lines = pcall(vim.fn.readfile, path)
                local hex = read_ok and lines and lines[3]
                if hex and hex:match("^#%x%x%x%x%x%x$") then
                    colors[#colors + 1] = hex
                end
            end
        end
    end
    return colors
end

function M.color_for(family, shade_idx)
    local shade = SHADES[shade_idx]
    return oklch_hex(shade.L, shade.C, FAMILY_HUES[family + 1])
end

-- Preferred order: own family, shades farthest-first -- deterministic when
-- uncontended, so a project keeps its colour launch after launch. The first
-- candidate that keeps MIN_DELTA from every live pane wins. If none does
-- (many panes, or a perceptually-adjacent family is already on screen -- the
-- teal-next-to-blue case), fall back to the whole grid and take the candidate
-- farthest from its nearest neighbour.
local function pick_color(family)
    local taken = live_colors()
    local function min_delta(hex)
        local d = math.huge
        for _, other in ipairs(taken) do
            d = math.min(d, delta_e(hex, other))
        end
        return d
    end

    for i = 1, #SHADES do
        local hex = M.color_for(family, i)
        if min_delta(hex) >= MIN_DELTA then return hex, family, i end
    end

    local best_hex, best_fam, best_shade, best_d = M.color_for(family, 1), family, 1, -1
    for fam = 0, N_FAMILIES - 1 do
        for i = 1, #SHADES do
            local hex = M.color_for(fam, i)
            local d = min_delta(hex)
            if d > best_d then best_hex, best_fam, best_shade, best_d = hex, fam, i, d end
        end
    end
    return best_hex, best_fam, best_shade
end

-- ---- application -----------------------------------------------------------

-- OSC to the outer terminal. v.stderr is the tty nvim's UI writes to; the
-- sequence passes through nvim's terminal layer untouched.
local function osc(seq)
    pcall(vim.fn.chansend, vim.v.stderr, seq)
end

-- applied_family is the PROJECT's family (idempotence key: re-pick only when
-- the shell changes project). Under contention the allocator may render a
-- different family's colour, so the accent derives from render_family --
-- otherwise a grid-fallback pane would get an orange wash with a blue block.
local applied_family, applied_color
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
-- when the family actually changes (new session, or cd into another project).
function M.apply()
    local family = family_for_cwd()
    if family == applied_family then return applied_color end

    local color, fam_used, shade_idx = pick_color(family)
    pcall(vim.fn.writefile, { tostring(fam_used), tostring(shade_idx), color }, claim_path())
    osc("\x1b]11;" .. color .. "\x07")

    applied_family, applied_color = family, color
    render_family, render_shade = fam_used, shade_idx
    return color
end

-- The emulator keeps an OSC 11 background after nvim exits; OSC 111 puts its
-- configured default back. Runs from the 500ms poll for every non-terminal
-- buffer, so the not-tinted path must stay free of disk and tty work.
function M.reset()
    if not applied_family and vim.fn.filereadable(claim_path()) == 0 then return end

    applied_family, applied_color = nil, nil
    render_family, render_shade = nil, nil
    pcall(vim.fn.delete, claim_path())
    osc("\x1b]111\x07")
end

return M
