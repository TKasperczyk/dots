-- Tint the terminal background so parallel sessions are identifiable at a
-- glance. The project (the shell's cwd) deterministically picks a hue family,
-- so every session in mic_cms is a shade of the same colour on every launch;
-- shades within a family are handed out farthest-first, so two siblings start
-- maximally far apart and only grow similar as sessions accumulate.
--
-- Emulator-agnostic on purpose: the colour is set with OSC 11 (and reset with
-- OSC 111) written straight to the outer tty, the same passthrough trick
-- osc52_clipboard.lua uses -- kitty, VTE/Terminator, alacritty and wezterm all
-- honour it. No remote-control protocol, no per-emulator config.

local M = {}

-- Hand-picked hue families. NOT uniform 30-degree steps: hue discrimination
-- is wildly non-uniform -- 90/120/150 are chartreuse/green/spring-green and
-- all read as "green" at a glance, while 30 degrees around orange is a
-- different colour outright. Eight nameable hues beat twelve adjacent ones;
-- projects that collide on a family still get farthest-first shades against
-- each other, so the collision costs similarity, not identity.
-- Which family a project gets is pure hash(cwd) -- deterministic across
-- launches, machines, and sessions.
local FAMILY_HUES = { 0, 28, 55, 115, 172, 225, 270, 315 }
local N_FAMILIES = #FAMILY_HUES

-- Shade slots within a family, farthest-first. Shades are defined by target
-- LUMA (perceived brightness, 0-255), not HSL lightness: yellow at a given
-- lightness has ~3x the luminance of blue at the same lightness, so an
-- L-based palette makes yellow families glow while blue ones stay dark.
-- Every colour is scaled to its slot's luma, so all families read equally
-- dark. The band tops out at 42 -- deep enough for light-on-dark text even
-- when the emulator composites the colour over a bright wallpaper.
-- dh nudges stay small: with hand-picked family hues a large offset would
-- push a shade into the neighbouring family's colour.
-- l generates the colour; luma_cap only ever scales DOWN. Equalizing luma in
-- both directions was a mistake: blue carries ~7% of luma per channel unit
-- versus yellow's ~92%, so scaling blue UP to a shared target maxes the blue
-- channel into neon. Dark-native hues (blue, violet) get their spread from l;
-- glow-prone hues (yellow, green, cyan) generate bright and get clamped to
-- the cap, which becomes their spread instead.
local SHADES = {
    { l = 0.13, luma_cap = 22, s = 0.60, dh = 0,   accent_l = 0.45 },
    { l = 0.34, luma_cap = 55, s = 0.85, dh = 12,  accent_l = 0.70 },
    { l = 0.22, luma_cap = 38, s = 0.55, dh = -10, accent_l = 0.57 },
    { l = 0.28, luma_cap = 46, s = 0.95, dh = 6,   accent_l = 0.63 },
    { l = 0.17, luma_cap = 30, s = 0.70, dh = 16,  accent_l = 0.51 },
    { l = 0.09, luma_cap = 14, s = 1.00, dh = -6,  accent_l = 0.38 },
}

-- The dark wash alone is deliberately subtle -- dark colours converge
-- perceptually, and the emulator may blend wallpaper on top. The loud,
-- instantly-identifiable signal is the ACCENT: the same family hue at full
-- vividness, rendered as a solid block in the statusline where it sits under
-- no body text. accent_l spreads siblings farthest-first in lightness, so two
-- sessions in one project get e.g. a dark-green block and a lime block.
local ACCENT_S = 0.90

-- Live panes publish their family + shade here so siblings pick a free slot.
-- Files are named by nvim pid: unique everywhere, and a claim whose pid is
-- dead can be reaped instead of leaking a slot.
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

local function hsl_to_rgb(h, s, l)
    h = (h % 360) / 360
    local function f(n)
        local k = (n + h * 12) % 12
        local a = s * math.min(l, 1 - l)
        local c = l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
        return c * 255
    end
    return f(0), f(8), f(4)
end

-- Generate at the shade's lightness, then clamp Rec.709 luma to the cap --
-- scaling down only. Uniform scaling preserves the hue and saturation
-- ratios, so this darkens without greying.
local function hue_capped(h, s, l, luma_cap)
    local r, g, b = hsl_to_rgb(h, s, l)
    local luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    local scale = math.min(1, luma_cap / math.max(luma, 1))
    local function q(v) return math.floor(v * scale + 0.5) end
    return string.format("#%02x%02x%02x", q(r), q(g), q(b))
end

-- The project identity is the *shell's* cwd, not nvim's: nvim is launched from
-- $HOME and the shell inside the terminal then cds to the project, so
-- getcwd() would put every session on this machine in the same family.
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

local function claim_path()
    return CLAIM_DIR .. "/" .. vim.fn.getpid()
end

local function pid_alive(pid)
    return (vim.uv or vim.loop).fs_stat("/proc/" .. pid) ~= nil
end

-- Shade slots held by other *live* panes of the given family. Claims from
-- dead pids are deleted on sight, so crashes cannot leak slots for long.
local function taken_shades(family)
    local taken = {}
    local ok, entries = pcall(vim.fn.readdir, CLAIM_DIR)
    if not ok or type(entries) ~= "table" then return taken end

    local mypid = vim.fn.getpid()
    for _, name in ipairs(entries) do
        local path = CLAIM_DIR .. "/" .. name
        local pid = tonumber(name)
        if pid and pid ~= mypid then
            if not pid_alive(pid) then
                pcall(vim.fn.delete, path)
            else
                local read_ok, lines = pcall(vim.fn.readfile, path)
                local fam, shade = nil, nil
                if read_ok and lines then
                    fam, shade = tonumber(lines[1]), tonumber(lines[2])
                end
                if fam == family and shade then
                    taken[shade] = true
                end
            end
        end
    end
    return taken
end

-- First free slot in farthest-first order; with everything taken, wrap around
-- to the unavoidable duplicate.
local function pick_shade(family)
    local taken = taken_shades(family)
    for i = 1, #SHADES do
        if not taken[i] then return i end
    end
    return 1
end

function M.color_for(family, shade_idx)
    local shade = SHADES[shade_idx]
    return hue_capped(FAMILY_HUES[family + 1] + shade.dh, shade.s, shade.l, shade.luma_cap)
end

-- OSC to the outer terminal. v.stderr is the tty nvim's UI writes to; the
-- sequence passes through nvim's terminal layer untouched.
local function osc(seq)
    pcall(vim.fn.chansend, vim.v.stderr, seq)
end

local applied_family, applied_shade, applied_color

-- The statusline block colour for the current session, or nil when untinted.
-- Returns { bg, fg }: fg flips black/white on the accent's own luma so the
-- topic text stays readable on any hue.
function M.accent()
    if not applied_family then return nil end

    local shade = SHADES[applied_shade]
    local h = FAMILY_HUES[applied_family + 1] + shade.dh
    local r, g, b = hsl_to_rgb(h, ACCENT_S, shade.accent_l)
    local luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return {
        bg = string.format("#%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)),
        fg = luma > 110 and "#000000" or "#ffffff",
    }
end

-- Idempotent: called from the title poll, but only touches disk and the tty
-- when the family actually changes (new session, or cd into another project).
function M.apply()
    local family = family_for_cwd()
    if family == applied_family then return applied_color end

    local shade_idx = pick_shade(family)
    local color = M.color_for(family, shade_idx)

    pcall(vim.fn.writefile, { tostring(family), tostring(shade_idx), color }, claim_path())
    osc("\x1b]11;" .. color .. "\x07")

    applied_family, applied_shade, applied_color = family, shade_idx, color
    return color
end

-- The emulator keeps an OSC 11 background after nvim exits; OSC 111 puts its
-- configured default back. Runs from the 500ms poll for every non-terminal
-- buffer, so the not-tinted path must stay free of disk and tty work.
function M.reset()
    if not applied_family and vim.fn.filereadable(claim_path()) == 0 then return end

    applied_family, applied_shade, applied_color = nil, nil, nil
    pcall(vim.fn.delete, claim_path())
    osc("\x1b]111\x07")
end

return M
