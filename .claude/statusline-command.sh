#!/usr/bin/env bash
# Claude Code statusLine
# Mirrors p10k lean prompt: cwd + git branch
# Plus: model, gradient context %, and 5h/7d OAuth usage from ~/claude_usage.py cache

input=$(cat)

cwd=$(jq -r '.cwd // .workspace.current_dir // ""' <<<"$input")
model=$(jq -r '.model.display_name // ""' <<<"$input")
used_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")

# Shorten home directory like p10k does
short_cwd="${cwd/#$HOME/~}"

# Git branch (skip optional locks to avoid interfering with concurrent git ops)
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# Truecolor gradient: 0% bright green -> 50% yellow -> 100% bright red
# Outputs an ANSI 24-bit SGR escape.
gradient() {
  local pct=$1
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local r g b=0
  if (( pct <= 50 )); then
    # (40, 200, 0) -> (220, 200, 0)
    r=$(( 40 + (220 - 40) * pct / 50 ))
    g=200
  else
    # (220, 200, 0) -> (255, 40, 0)
    local p=$(( pct - 50 ))
    r=$(( 220 + (255 - 220) * p / 50 ))
    g=$(( 200 - (200 - 40) * p / 50 ))
  fi
  printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Fixed per-icon colors so each metric is visually distinct
# regardless of how full the gradient bars are.
COLOR_BRAIN=$'\033[38;2;200;130;255m'    # lavender / purple
COLOR_CLOCK=$'\033[38;2;100;180;255m'    # sky blue
COLOR_CALENDAR=$'\033[38;2;255;180;80m'  # warm orange

# Dim vertical bar between the per-conversation ctx section and
# the account-wide 5h/7d usage section.
SEP=" ${DIM}│${RESET} "

# Nerd Font icons (FontAwesome range). Encoded via \u escapes so they
# survive any tooling that strips non-ASCII bytes.
ICON_BRAIN='󰧑'        # nf-md-brain (U+F09D1) -- context window
ICON_CLOCK=$''       # nf-fa-clock_o      -- 5h rolling window
ICON_CALENDAR=$''    # nf-fa-calendar_o   -- 7d window

parts=""

# Directory (cyan, like p10k DIR_FOREGROUND=31)
parts+="$(printf '%b%s%b' "$CYAN" "$short_cwd" "$RESET")"

# Git branch (green, like p10k vcs clean color)
if [ -n "$branch" ]; then
  parts+=" $(printf '%b %s%b' "$GREEN" "$branch" "$RESET")"
fi

# Model name (dimmed)
if [ -n "$model" ]; then
  parts+=" $(printf '%b%s%b' "$DIM" "$model" "$RESET")"
fi

# Context window with gradient (brain icon)
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  parts+=" ${COLOR_BRAIN}${ICON_BRAIN}${RESET} $(gradient "$used_int")${used_int}%${RESET}"
fi

# ---- 5h / 7d Claude usage from ~/claude_usage.py cache ----
CACHE_FILE="$HOME/.cache/eww/claude_usage.json"
CACHE_TTL=300              # match claude_usage.py
LOCK_FILE="/tmp/claude_usage.statusline.lock"

ts=0; h5=""; d7=""; err="false"
if [ -r "$CACHE_FILE" ]; then
  read -r ts h5 d7 err <<<"$(jq -r '"\(._ts // 0) \(.h5 // 0) \(.d7 // 0) \(.error // false)"' "$CACHE_FILE" 2>/dev/null)"
fi

now=$(date +%s)
age=$(( now - ${ts%.*} ))

# Fire background refresh if cache is missing or stale.
# nohup + & detaches from CC's process group so SIGHUP on statusline exit
# doesn't kill the in-flight HTTP fetch. flock prevents pile-up on slow fetches.
if [ ! -r "$CACHE_FILE" ] || (( age >= CACHE_TTL )); then
  nohup bash -c "exec 9>'$LOCK_FILE'; flock -n 9 || exit 0; python3 '$HOME/.claude/scripts/claude_usage.py' >/dev/null 2>&1" \
    >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null
fi

# Display whatever's in the cache (even if stale -- background refresh will catch up)
if [ -n "$h5" ] && [ "$h5" != "0" -o "$d7" != "0" -o "$err" = "false" ]; then
  if [ "$err" = "true" ]; then
    # API/auth error -- flat red on numbers, icons keep their own colors
    parts+="${SEP}${COLOR_CLOCK}${ICON_CLOCK}${RESET} ${RED}${h5}%${RESET} ${COLOR_CALENDAR}${ICON_CALENDAR}${RESET} ${RED}${d7}%${RESET}"
  else
    parts+="${SEP}${COLOR_CLOCK}${ICON_CLOCK}${RESET} $(gradient "$h5")${h5}%${RESET} ${COLOR_CALENDAR}${ICON_CALENDAR}${RESET} $(gradient "$d7")${d7}%${RESET}"
  fi
fi

printf '%s' "$parts"
