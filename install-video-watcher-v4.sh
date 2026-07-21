#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Please run this installer as your normal Ubuntu user, not with sudo."
  echo "The installer will ask for sudo only when it needs to install packages."
  exit 1
fi

echo "Video Watcher installer v4 for Ubuntu + Firefox/Chrome"
echo

read -rp "First name: " FIRSTNAME
read -rp "Last name: " LASTNAME

SLUG="$(echo "${FIRSTNAME}-${LASTNAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
WATCHER_NAME="${FIRSTNAME} ${LASTNAME}"

echo
echo "Removing any previous Video Watcher installation..."

# Stop and disable an older user service if it exists. Errors are harmless on a first install.
systemctl --user stop video-watch.service 2>/dev/null || true
systemctl --user disable video-watch.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/default.target.wants/video-watch.service"
rm -f "$HOME/.config/systemd/user/video-watch.service"
rm -f "$HOME/.local/bin/video-watch.sh"
rm -f "$HOME/.config/video-watch/config"

# Preserve existing CSV reports and internal weekly data so an upgrade does not lose viewing history.

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user reset-failed video-watch.service 2>/dev/null || true

echo
echo "Installing required package: playerctl"
sudo apt update
sudo apt install -y playerctl

mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/video-watch"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.local/state/video-watch"
mkdir -p "$HOME/video-watch-reports"

cat > "$HOME/.config/video-watch/config" <<EOF
WATCHER_NAME="$WATCHER_NAME"
WATCHER_SLUG="$SLUG"
REPORT_DIR="$HOME/video-watch-reports"
STATE_DIR="$HOME/.local/state/video-watch"
EOF

cat > "$HOME/.local/bin/video-watch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/video-watch/config"

mkdir -p "$REPORT_DIR" "$STATE_DIR"

LAST_STATE="$STATE_DIR/last-state"
ACTIVE_PERIOD_FILE="$STATE_DIR/active-period"

csv_escape() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

current_period_date() {
  local dow hour days
  dow=$(date +%u)      # Monday=1 ... Friday=5 ... Sunday=7
  hour=$(date +%H)
  days=$(( (dow + 2) % 7 ))

  # Before 17:00 on Friday, continue using the previous Friday's report.
  if [[ "$dow" -eq 5 ]] && (( 10#$hour < 17 )); then
    days=7
  fi

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

      # Keep the summary valid CSV while making it easy to spot at the bottom.
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
  local period="$1"
  local total_minutes hours minutes summary_text

  [[ -n "$period" ]] || return 0
  set_report_files "$period"

  # Do this only once, even though the monitor checks every minute.
  [[ -f "$SUMMARY_FILE" ]] && return 0

  if [[ -f "$TSV" ]]; then
    total_minutes="$(awk -F '\t' '{ total += $4 } END { print total + 0 }' "$TSV")"
  else
    total_minutes=0
  fi

  hours=$(( total_minutes / 60 ))
  minutes=$(( total_minutes % 60 ))
  summary_text="this week you have watched ${hours} hours and ${minutes} minutes"

  printf '%s\t%s\n' "$total_minutes" "$summary_text" > "$SUMMARY_FILE"
  render_csv_for_period "$period"
}

prepare_current_period() {
  local current previous
  current="$(current_period_date)"
  previous=""

  if [[ -f "$ACTIVE_PERIOD_FILE" ]]; then
    previous="$(cat "$ACTIVE_PERIOD_FILE")"
  fi

  if [[ -n "$previous" && "$previous" != "$current" ]]; then
    finalize_period "$previous"
  fi

  printf '%s\n' "$current" > "$ACTIVE_PERIOD_FILE"
  ensure_report_exists "$current"
  CURRENT_PERIOD="$current"
}

add_minute() {
  local date="$1"
  local watcher="$2"
  local title="$3"

  set_report_files "$CURRENT_PERIOD"

  awk -F '\t' -v OFS='\t' \
    -v d="$date" \
    -v w="$watcher" \
    -v t="$title" '
    $1 == d && $2 == w && $3 == t {
      $4 = $4 + 1
      found = 1
    }
    { print }
    END {
      if (!found) {
        print d, w, t, 1
      }
    }
  ' "$TSV" > "$TSV.tmp"

  mv "$TSV.tmp" "$TSV"
  render_csv_for_period "$CURRENT_PERIOD"
}

is_allowed_video_url() {
  local url="${1,,}"

  # Only record videos opened from these two approved websites.
  [[ "$url" =~ ^https?://([a-z0-9-]+\.)*learning\.oreilly\.com([/:?#]|$) ]] ||
    [[ "$url" =~ ^https?://event\.on24\.com([/:?#]|$) ]]
}

get_supported_browser_player() {
  local player status url

  # Check every active Firefox/Chrome/Chromium media session. This prevents an
  # unrelated playing tab from hiding a valid O'Reilly or ON24 video.
  while IFS= read -r player; do
    [[ -z "$player" ]] && continue

    status="$(playerctl -p "$player" status 2>/dev/null || true)"
    [[ "$status" == "Playing" ]] || continue

    url="$(playerctl -p "$player" metadata xesam:url 2>/dev/null || true)"
    url="${url//$'\n'/ }"
    url="${url//$'\r'/ }"

    if is_allowed_video_url "$url"; then
      printf '%s\n' "$player"
      return 0
    fi
  done < <(playerctl -l 2>/dev/null | grep -Ei 'firefox|chrome|chromium' || true)

  return 0
}

while true; do
  prepare_current_period

  PLAYER="$(get_supported_browser_player)"

  if [[ -n "$PLAYER" ]]; then
    STATUS="$(playerctl -p "$PLAYER" status 2>/dev/null || true)"
    TITLE="$(playerctl -p "$PLAYER" metadata xesam:title 2>/dev/null || echo "Unknown browser video")"
    URL="$(playerctl -p "$PLAYER" metadata xesam:url 2>/dev/null || true)"
    POS="$(playerctl -p "$PLAYER" position 2>/dev/null | cut -d. -f1 || echo "")"

    TITLE="${TITLE//$'\n'/ }"
    TITLE="${TITLE//$'\r'/ }"
    URL="${URL//$'\n'/ }"
    URL="${URL//$'\r'/ }"

    LAST_TITLE=""
    LAST_URL=""
    LAST_POS=""

    if [[ -f "$LAST_STATE" ]]; then
      LAST_TITLE="$(grep '^title=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
      LAST_URL="$(grep '^url=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
      LAST_POS="$(grep '^pos=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
    fi

    if [[ "$STATUS" == "Playing" && "$POS" =~ ^[0-9]+$ ]]; then
      if [[ "$TITLE" != "$LAST_TITLE" || "$URL" != "$LAST_URL" ]]; then
        add_minute "$(date +%F)" "$WATCHER_NAME" "$TITLE"
      elif [[ "$LAST_POS" =~ ^[0-9]+$ && "$POS" -gt "$LAST_POS" ]]; then
        add_minute "$(date +%F)" "$WATCHER_NAME" "$TITLE"
      fi
    fi

    {
      echo "title=$TITLE"
      echo "url=$URL"
      echo "pos=$POS"
    } > "$LAST_STATE"
  fi

  sleep 60
done
EOF

chmod +x "$HOME/.local/bin/video-watch.sh"

cat > "$HOME/.config/systemd/user/video-watch.service" <<EOF
[Unit]
Description=Video watch monitor for Firefox and Chrome

[Service]
ExecStart=$HOME/.local/bin/video-watch.sh
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now video-watch.service

if ! systemctl --user is-active --quiet video-watch.service; then
  echo
  echo "ERROR: The Video Watcher service could not be started."
  echo "Diagnostic information follows:"
  systemctl --user status video-watch.service --no-pager || true
  journalctl --user -u video-watch.service -n 50 --no-pager || true
  exit 1
fi

echo
echo "Trying to enable 24/7 background service..."
sudo loginctl enable-linger "$USER" || true

cat > "$HOME/video-watch-reports/README.txt" <<EOF
Every week, email the newest CSV file from this folder:

$HOME/video-watch-reports

The file name looks like this:

${SLUG}-video-play-report-YYYY-MM-DD.csv

A new weekly file is started every Friday at 17:00.
At rollover, the previous CSV receives a WEEKLY SUMMARY line showing hours and minutes watched.
EOF

echo
echo "Installation complete. The video-watch.service is active and running."
echo
echo "Reports are stored in:"
echo "$HOME/video-watch-reports"
echo
echo "Check status with:"
echo "systemctl --user status video-watch.service"
echo
echo "View log with:"
echo "journalctl --user -u video-watch.service -f"
