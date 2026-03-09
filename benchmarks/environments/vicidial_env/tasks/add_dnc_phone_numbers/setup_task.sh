#!/bin/bash
set -e

echo "=== Setting up DNC phone number upload task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# ------------------------------------------------------------------
# Prepare Data: Extract 10 phone numbers from senators lead data
# ------------------------------------------------------------------
DATA_DIR="/home/ga/Documents/VicidialData"
mkdir -p "$DATA_DIR"
SENATORS_FILE="$DATA_DIR/us_senators_vicidial_standard_format_list9001_2026-02-14.txt"
DNC_FILE="$DATA_DIR/dnc_optout_requests.txt"
EXPECTED_NUMBERS_FILE="/tmp/expected_dnc_numbers.txt"

# If txt file doesn't exist, try CSV, or fallback to asset
if [ ! -f "$SENATORS_FILE" ]; then
    if [ -f "$DATA_DIR/us_senators_vicidial_standard_format_list9001_2026-02-14.csv" ]; then
        SENATORS_FILE="$DATA_DIR/us_senators_vicidial_standard_format_list9001_2026-02-14.csv"
    elif [ -f "/workspace/assets/us_senators_vicidial_standard_format_list9001_2026-02-14.txt" ]; then
        cp "/workspace/assets/us_senators_vicidial_standard_format_list9001_2026-02-14.txt" "$SENATORS_FILE"
    fi
fi

if [ ! -f "$SENATORS_FILE" ]; then
  echo "ERROR: Senators data file not found. Creating dummy data."
  # Fallback dummy data if asset missing
  for i in {1..10}; do echo "99955500$i"; done > "$DNC_FILE"
else
  # Vicidial standard format is TAB-delimited; phone_number is field 7 in TXT, usually field 8 in CSV depending on header
  # We'll just grep for 10 digit numbers to be safe and simple
  grep -oE '[0-9]{10}' "$SENATORS_FILE" | head -10 > "$DNC_FILE"
fi

# Save expected numbers for verification (hidden from agent)
cp "$DNC_FILE" "$EXPECTED_NUMBERS_FILE"
chmod 600 "$EXPECTED_NUMBERS_FILE"
chown ga:ga "$DNC_FILE"

NUM_PHONES=$(wc -l < "$DNC_FILE")
echo "Extracted $NUM_PHONES phone numbers to $DNC_FILE"

# ------------------------------------------------------------------
# Database Cleanup & Initial State
# ------------------------------------------------------------------
# Clear these specific numbers from DNC if they already exist to ensure a clean start
echo "Cleaning up target numbers from DNC list..."
while IFS= read -r phone; do
  [ -z "$phone" ] && continue
  docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_dnc WHERE phone_number='$phone';" 2>/dev/null || true
done < "$EXPECTED_NUMBERS_FILE"

# Record initial DNC count
INITIAL_DNC_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_dnc;" 2>/dev/null || echo "0")
echo "$INITIAL_DNC_COUNT" > /tmp/initial_dnc_count.txt

# ------------------------------------------------------------------
# Browser Setup
# ------------------------------------------------------------------
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to Admin Login
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|Mozilla\|Vicidial" 30

# Maximize and focus
focus_firefox
maximize_active_window
sleep 2

# Pre-fill login if on login screen (optional, helps agent start faster)
# But description says credentials provided, so agent can do it.
# We'll just leave it at the login screen or prompt.

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== DNC upload task setup complete ==="