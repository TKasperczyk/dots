#!/bin/bash
# Adjust active window opacity via SUPER+mousewheel
# Usage: opacity.sh up|down

STEP=0.05
MIN=0.1
MAX=1.0
CACHE_DIR="/tmp/hypr-opacity"

mkdir -p "$CACHE_DIR"

ADDR=$(hyprctl activewindow -j | jq -r '.address')
[[ -z "$ADDR" || "$ADDR" == "null" ]] && exit 1

CACHE_FILE="$CACHE_DIR/$ADDR"

if [[ -f "$CACHE_FILE" ]]; then
    CURRENT=$(cat "$CACHE_FILE")
else
    CURRENT=1.0
fi

case "$1" in
    up)   NEW=$(echo "$CURRENT + $STEP" | bc) ;;
    down) NEW=$(echo "$CURRENT - $STEP" | bc) ;;
    *)    exit 1 ;;
esac

# Clamp
NEW=$(awk -v val="$NEW" -v min="$MIN" -v max="$MAX" \
    'BEGIN { if (val < min) print min; else if (val > max) print max; else printf "%.2f", val }')

hyprctl dispatch setprop active opacity "$NEW" override
echo "$NEW" > "$CACHE_FILE"
