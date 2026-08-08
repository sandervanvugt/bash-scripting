#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "Please run this installer as your normal Ubuntu user, not with sudo."
    exit 1
fi

read -rp "First name: " FIRSTNAME
read -rp "Last name: " LASTNAME

echo "1) Firefox"
echo "2) Chrome or Chromium"
while true; do
    read -rp "Enter 1 or 2: " BROWSER_CHOICE
    case "$BROWSER_CHOICE" in
        1) BROWSER_NAME="Firefox"; BROWSER_PATTERN='^firefox([.]|$)'; break ;;
        2) BROWSER_NAME="Chrome/Chromium"; BROWSER_PATTERN='^(chrome|chromium|google-chrome)([.]|$)'; break ;;
        *) echo "Invalid choice." ;;
    esac
done

SLUG="$(printf '%s-%s' "$FIRSTNAME" "$LASTNAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
WATCHER_NAME="$FIRSTNAME $LASTNAME"

systemctl --user disable --now video-watch.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/video-watch.service"
rm -f "$HOME/.local/bin/video-watch.sh" "$HOME/.local/bin/video-watch-diagnostics"
rm -f "$HOME/.config/video-watch/config"
rm -rf "$HOME/.local/state/video-watch" "$HOME/video-watch-reports"

sudo apt update
sudo apt install -y playerctl

mkdir -p "$HOME/.local/bin" "$HOME/.config/video-watch" "$HOME/.config/systemd/user" \
         "$HOME/.local/state/video-watch" "$HOME/video-watch-reports"

cat > "$HOME/.config/video-watch/config" <<CFG
WATCHER_NAME=$(printf '%q' "$WATCHER_NAME")
WATCHER_SLUG=$(printf '%q' "$SLUG")
REPORT_DIR=$(printf '%q' "$HOME/video-watch-reports")
STATE_DIR=$(printf '%q' "$HOME/.local/state/video-watch")
BROWSER_NAME=$(printf '%q' "$BROWSER_NAME")
BROWSER_PATTERN=$(printf '%q' "$BROWSER_PATTERN")
CFG

cat > "$HOME/.local/bin/video-watch.sh" <<'WATCHER'
#!/usr/bin/env bash
set -euo pipefail
source "$HOME/.config/video-watch/config"

mkdir -p "$REPORT_DIR" "$STATE_DIR"
LAST_STATE="$STATE_DIR/last-state"
ACTIVE_PERIOD_FILE="$STATE_DIR/active-period"
NO_PLAYER_WARNING="$STATE_DIR/no-player-warning"

csv_escape() {
    local value="$1"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//\"/\"\"}"
    printf '"%s"' "$value"
}

current_period_date() {
    local dow hour days
    dow="$(date +%u)"
    hour="$(date +%H)"
    days=$(( (10#$dow + 2) % 7 ))
    if [[ "$dow" -eq 5 ]] && (( 10#$hour < 17 )); then days=7; fi
    date -d "$days days ago" +%F
}

set_report_files() {
    local period="$1"
    TSV="$STATE_DIR/${WATCHER_SLUG}-video-play-report-${period}.tsv"
    CSV="$REPORT_DIR/${WATCHER_SLUG}-video-play-report-${period}.csv"
    SUMMARY_FILE="$STATE_DIR/${WATCHER_SLUG}-video-play-report-${period}.summary"
}

render_csv_for_period() {
    local period="$1"
    set_report_files "$period"
    {
        echo "watcher,date,title,minutes"
        if [[ -f "$TSV" ]]; then
            while IFS=$'\t' read -r date watcher title minutes; do
                [[ -z "${date:-}" ]] && continue
                printf '%s,%s,%s,%s\n' \
                    "$(csv_escape "$watcher")" \
                    "$(csv_escape "$date")" \
                    "$(csv_escape "$title")" \
                    "$minutes"
            done < "$TSV"
        fi
        if [[ -f "$SUMMARY_FILE" ]]; then
            local total_minutes summary_text
            total_minutes="$(cut -f1 "$SUMMARY_FILE")"
            summary_text="$(cut -f2- "$SUMMARY_FILE")"
            printf '%s,%s,%s,%s\n' \
                "$(csv_escape "WEEKLY SUMMARY")" \
                "$(csv_escape "$period")" \
                "$(csv_escape "$summary_text")" \
                "$total_minutes"
        fi
    } > "$CSV.tmp"
    mv "$CSV.tmp" "$CSV"
}

ensure_report_exists() {
    local period="$1"
    set_report_files "$period"
    [[ -f "$TSV" ]] || : > "$TSV"
    render_csv_for_period "$period"
}

finalize_period() {
    local period="$1" total_minutes hours minutes summary_text
    [[ -n "$period" ]] || return 0
    set_report_files "$period"
    [[ -f "$SUMMARY_FILE" ]] && return 0
    total_minutes="$(awk -F '\t' '{ total += $4 } END { print total + 0 }' "$TSV" 2>/dev/null || echo 0)"
    hours=$(( total_minutes / 60 ))
    minutes=$(( total_minutes % 60 ))
    summary_text="this week you have watched ${hours} hours and ${minutes} minutes"
    printf '%s\t%s\n' "$total_minutes" "$summary_text" > "$SUMMARY_FILE"
    render_csv_for_period "$period"
}

prepare_current_period() {
    local current previous=""
    current="$(current_period_date)"
    [[ -f "$ACTIVE_PERIOD_FILE" ]] && previous="$(cat "$ACTIVE_PERIOD_FILE")"
    if [[ -n "$previous" && "$previous" != "$current" ]]; then finalize_period "$previous"; fi
    printf '%s\n' "$current" > "$ACTIVE_PERIOD_FILE"
    ensure_report_exists "$current"
    CURRENT_PERIOD="$current"
}

add_minute() {
    local date="$1" watcher="$2" title="$3"
    set_report_files "$CURRENT_PERIOD"
    awk -F '\t' -v OFS='\t' -v d="$date" -v w="$watcher" -v t="$title" '
        $1 == d && $2 == w && $3 == t { $4++; found=1 }
        { print }
        END { if (!found) print d,w,t,1 }
    ' "$TSV" > "$TSV.tmp"
    mv "$TSV.tmp" "$TSV"
    render_csv_for_period "$CURRENT_PERIOD"
}

list_selected_players() {
    playerctl -l 2>/dev/null | grep -Ei "$BROWSER_PATTERN" || true
}

get_playing_browser_player() {
    local player status
    while IFS= read -r player; do
        [[ -z "$player" ]] && continue
        status="$(playerctl -p "$player" status 2>/dev/null || true)"
        if [[ "$status" == "Playing" ]]; then
            printf '%s\n' "$player"
            return 0
        fi
    done < <(list_selected_players)
    return 1
}

while true; do
    prepare_current_period
    PLAYER="$(get_playing_browser_player || true)"

    if [[ -z "$PLAYER" ]]; then
        rm -f "$LAST_STATE"
        if ! list_selected_players | grep -q .; then
            if [[ ! -f "$NO_PLAYER_WARNING" ]]; then
                echo "WARNING: No MPRIS player is visible for $BROWSER_NAME. Run: video-watch-diagnostics"
                touch "$NO_PLAYER_WARNING"
            fi
        fi
        sleep 60
        continue
    fi

    rm -f "$NO_PLAYER_WARNING"
    STATUS="$(playerctl -p "$PLAYER" status 2>/dev/null || true)"
    TITLE="$(playerctl -p "$PLAYER" metadata xesam:title 2>/dev/null || true)"
    [[ -n "$TITLE" ]] || TITLE="Unknown browser video"
    TITLE="${TITLE//$'\n'/ }"
    TITLE="${TITLE//$'\r'/ }"

    if [[ "$STATUS" == "Playing" ]]; then
        NOW="$(date +%s)"
        TITLE_HASH="$(printf '%s' "$PLAYER|$TITLE" | sha256sum | awk '{print $1}')"
        LAST_HASH=""; LAST_SEEN=""
        if [[ -f "$LAST_STATE" ]]; then
            LAST_HASH="$(grep '^title_hash=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
            LAST_SEEN="$(grep '^last_seen=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
        fi

        if [[ "$TITLE_HASH" == "$LAST_HASH" && "$LAST_SEEN" =~ ^[0-9]+$ ]]; then
            ELAPSED=$(( NOW - LAST_SEEN ))
            if (( ELAPSED >= 45 && ELAPSED <= 90 )); then
                add_minute "$(date +%F)" "$WATCHER_NAME" "$TITLE"
            fi
        fi

        printf 'title_hash=%s\nlast_seen=%s\n' "$TITLE_HASH" "$NOW" > "$LAST_STATE"
    else
        rm -f "$LAST_STATE"
    fi

    sleep 60
done
WATCHER
chmod +x "$HOME/.local/bin/video-watch.sh"

cat > "$HOME/.local/bin/video-watch-diagnostics" <<'DIAG'
#!/usr/bin/env bash
set -u
source "$HOME/.config/video-watch/config"

echo "Video Watcher diagnostics"
echo "Selected browser: $BROWSER_NAME"
echo
echo "All MPRIS players:"
playerctl -l 2>&1 || true

echo
echo "Matching players:"
MATCHES="$(playerctl -l 2>/dev/null | grep -Ei "$BROWSER_PATTERN" || true)"
if [[ -z "$MATCHES" ]]; then
    echo "(none)"
    if [[ "$BROWSER_NAME" == "Firefox" ]]; then
        echo
        echo "Firefox is not publishing an MPRIS player."
        echo "Open about:config and verify:"
        echo "  media.hardwaremediakeys.enabled = true"
        echo "Then start an audible video and run this diagnostic again."
    fi
    exit 1
fi

while IFS= read -r player; do
    [[ -z "$player" ]] && continue
    echo
    echo "Player:   $player"
    echo "Status:   $(playerctl -p "$player" status 2>/dev/null || echo unavailable)"
    echo "Title:    $(playerctl -p "$player" metadata xesam:title 2>/dev/null || echo unavailable)"
    echo "Position: $(playerctl -p "$player" position 2>/dev/null || echo unavailable)"
done <<< "$MATCHES"

echo
echo "Service status:"
systemctl --user --no-pager --full status video-watch.service 2>&1 || true
DIAG
chmod +x "$HOME/.local/bin/video-watch-diagnostics"

cat > "$HOME/.config/systemd/user/video-watch.service" <<EOF_SERVICE
[Unit]
Description=Video watch monitor for the selected browser

[Service]
ExecStart=$HOME/.local/bin/video-watch.sh
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF_SERVICE

systemctl --user daemon-reload
systemctl --user enable --now video-watch.service
sudo loginctl enable-linger "$USER" || true

cat > "$HOME/video-watch-reports/README.txt" <<EOF_README
Selected monitored browser: $BROWSER_NAME

This version uses MPRIS PlaybackStatus=Playing and does NOT require a usable
playerctl playback position. This improves Firefox compatibility.

Reports: $HOME/video-watch-reports
New reporting period: every Friday at 17:00.

Diagnostics:
  video-watch-diagnostics

Service status:
  systemctl --user status video-watch.service
EOF_README

echo
echo "Installation complete."
echo "Monitored browser: $BROWSER_NAME"
echo "If Firefox does not log, run: video-watch-diagnostics"
