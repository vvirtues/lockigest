#!/usr/bin/env bash
# lockigest.sh - Wayland/Hyprland patched for quickshell
# Dependencies: hyprctl, jq, ydotool, systemd (loginctl)

set -euo pipefail

# Config
IDLE_SECONDS=${IDLE_SECONDS:-5}       # idle time to arm trap
COUNTDOWN_SECONDS=${COUNTDOWN_SECONDS:-2} # seconds before lock after movement
CHECK_INTERVAL=${CHECK_INTERVAL:-0.5}   # polling interval
SAFE_RADIUS=${SAFE_RADIUS:-80}          # safe area radius (px)
SAFE_X=${SAFE_X:-1}
SAFE_Y=${SAFE_Y:-1}

# -------------------------
# Functions
# -------------------------

# Get cursor X Y
get_cursor_pos() {
    hyprctl cursorpos -j 2>/dev/null | jq -r '"\(.x) \(.y)"' || return 1
}

# Squared distance between two points
squared_distance() {
    local dx=$(( $1 - $2 ))
    local dy=$(( $3 - $4 ))
    echo $(( dx*dx + dy*dy ))
}

# -------------------------
# Init
# -------------------------
initial_pos="$(get_cursor_pos)" || { echo "Failed to read cursor position. Make sure hyprctl is available."; exit 1; }
read -r initial_x initial_y <<<"$initial_pos"

if [ -z "$SAFE_X" ] || [ -z "$SAFE_Y" ]; then
    SAFE_X=$initial_x
    SAFE_Y=$initial_y
fi

last_x=$initial_x
last_y=$initial_y
stationary_since=$(date +%s)
trap_armed=0

echo "Initial cursor: $initial_x,$initial_y"
echo "Safe area: $SAFE_X,$SAFE_Y (radius ${SAFE_RADIUS}px)"
echo "Idle timeout: ${IDLE_SECONDS}s, countdown: ${COUNTDOWN_SECONDS}s"

# -------------------------
# Main loop
# -------------------------
while true; do
    cur_pos="$(get_cursor_pos)" || { sleep "$CHECK_INTERVAL"; continue; }
    read -r cur_x cur_y <<<"$cur_pos"

    if [ "$cur_x" -eq "$last_x" ] && [ "$cur_y" -eq "$last_y" ]; then
        # Still stationary
        now=$(date +%s)
        elapsed=$(( now - stationary_since ))

        if [ $trap_armed -eq 0 ] && [ $elapsed -ge $IDLE_SECONDS ]; then
            trap_armed=1
            echo "$(date +"%F %T") - Trap ARMED (cursor stationary for ${elapsed}s)"
        fi
    else
        # Cursor moved
        if [ $trap_armed -eq 1 ]; then
            echo "$(date +"%F %T") - Movement detected while trap ARMED. Countdown ${COUNTDOWN_SECONDS}s."
            locked=1
            for ((i=COUNTDOWN_SECONDS; i>0; i--)); do
                cur_pos2="$(get_cursor_pos)" || break
                read -r cur_x2 cur_y2 <<<"$cur_pos2"
                dist2=$(squared_distance "$cur_x2" "$SAFE_X" "$cur_y2" "$SAFE_Y")
                if [ "$dist2" -le $(( SAFE_RADIUS * SAFE_RADIUS )) ]; then
                    echo "$(date +"%F %T") - Cursor reached safe area; cancelling lock."
                    trap_armed=0
                    last_x=$cur_x2
                    last_y=$cur_y2
                    stationary_since=$(date +%s)
                    locked=0
                    break
                fi
                sleep 1
            done

            if [ "$locked" -eq 1 ]; then
                echo "$(date +"%F %T") - Countdown expired — locking session."
                loginctl lock-session
                exit 0
            fi
        fi

        # Update last position and stationary timer
        last_x=$cur_x
        last_y=$cur_y
        stationary_since=$(date +%s)
    fi

    sleep "$CHECK_INTERVAL"
done


