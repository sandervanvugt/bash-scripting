#!/usr/bin/env bash
set -euo pipefail

echo "Video Watcher installer for Ubuntu + Firefox"
echo

read -rp "First name: " FIRSTNAME
read -rp "Last name: " LASTNAME

SLUG="$(echo "${FIRSTNAME}-${LASTNAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
WATCHER_NAME="${FIRSTNAME} ${LASTNAME}"

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
LOGFILE="$STATE_DIR/video-watch.log"

csv_escape() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

current_period_date() {
  local dow hour min days
  dow=$(date +%u)      # Monday=1 ... Friday=5 ... Sunday=7
  hour=$(date +%H)
  min=$(date +%M)

  days=$(( (dow + 2) % 7 ))

  if [[ "$dow" -eq 5 ]]; then
    if (( 10#$hour < 17 )); then
      days=7
    fi
  fi

  date -d "$days days ago" +%F
}

current_report_files() {
  local period
  period="$(current_period_date)"
  TSV="$STATE_DIR/${WATCHER_SLUG}-video-play-report-${period}.tsv"
  CSV="$REPORT_DIR/${WATCHER_SLUG}-video-play-report-${period}.csv"
}

ensure_report_exists() {
  current_report_files

  if [[ ! -f "$TSV" ]]; then
    : > "$TSV"
  fi

  if [[ ! -f "$CSV" ]]; then
    echo "watcher,date,title,minutes" > "$CSV"
  fi
}

render_csv() {
  {
    echo "watcher,date,title,minutes"
    while IFS=$'\t' read -r date watcher title minutes; do
      [[ -z "${date:-}" ]] && continue
      printf '%s,%s,%s,%s\n' \
        "$(csv_escape "$watcher")" \
        "$(csv_escape "$date")" \
        "$(csv_escape "$title")" \
        "$minutes"
    done < "$TSV"
  } > "$CSV.tmp"

  mv "$CSV.tmp" "$CSV"
}

add_minute() {
  local date="$1"
  local watcher="$2"
  local title="$3"

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
  render_csv
}

get_firefox_player() {
  playerctl -l 2>/dev/null | grep -i firefox | head -n 1 || true
}

while true; do
  ensure_report_exists

  PLAYER="$(get_firefox_player)"

  if [[ -n "$PLAYER" ]]; then
    STATUS="$(playerctl -p "$PLAYER" status 2>/dev/null || true)"
    TITLE="$(playerctl -p "$PLAYER" metadata xesam:title 2>/dev/null || echo "Unknown Firefox video")"
    POS="$(playerctl -p "$PLAYER" position 2>/dev/null | cut -d. -f1 || echo "")"

    TITLE="${TITLE//$'\n'/ }"
    TITLE="${TITLE//$'\r'/ }"

    LAST_TITLE=""
    LAST_POS=""

    if [[ -f "$LAST_STATE" ]]; then
      LAST_TITLE="$(grep '^title=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
      LAST_POS="$(grep '^pos=' "$LAST_STATE" 2>/dev/null | cut -d= -f2- || true)"
    fi

    if [[ "$STATUS" == "Playing" && "$POS" =~ ^[0-9]+$ ]]; then
      if [[ "$TITLE" != "$LAST_TITLE" ]]; then
        add_minute "$(date +%F)" "$WATCHER_NAME" "$TITLE"
      elif [[ "$LAST_POS" =~ ^[0-9]+$ && "$POS" -gt "$LAST_POS" ]]; then
        add_minute "$(date +%F)" "$WATCHER_NAME" "$TITLE"
      fi
    fi

    {
      echo "title=$TITLE"
      echo "pos=$POS"
    } > "$LAST_STATE"
  fi

  sleep 60
done
EOF

chmod +x "$HOME/.local/bin/video-watch.sh"

cat > "$HOME/.config/systemd/user/video-watch.service" <<EOF
[Unit]
Description=Video watch monitor for Firefox

[Service]
ExecStart=$HOME/.local/bin/video-watch.sh
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now video-watch.service

echo
echo "Trying to enable 24/7 background service..."
sudo loginctl enable-linger "$USER" || true

cat > "$HOME/video-watch-reports/README.txt" <<EOF
Every week, email the newest CSV file from this folder:

$HOME/video-watch-reports

The file name looks like this:

${SLUG}-video-play-report-YYYY-MM-DD.csv

A new weekly file is started every Friday at 17:00.
EOF

echo
echo "Installation complete."
echo
echo "Reports are stored in:"
echo "$HOME/video-watch-reports"
echo
echo "Check status with:"
echo "systemctl --user status video-watch.service"
echo
echo "View log with:"
echo "journalctl --user -u video-watch.service -f"
