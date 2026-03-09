#!/bin/bash
set -e
echo "=== Setting up task: install_custom_csl ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jurism is running
ensure_jurism_running

# 3. Locate Database and Profile
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
PROFILE_DIR=$(dirname "$DB_PATH")
STYLES_DIR="$PROFILE_DIR/styles"

echo "Database: $DB_PATH"
echo "Styles Dir: $STYLES_DIR"

# 4. Anti-gaming: Clean up previous state
STYLE_ID="http://www.zotero.org/styles/firm-standard-2025"
STYLE_FILENAME="firm-standard-2025.csl"

# Remove from DB
echo "Cleaning DB..."
sqlite3 "$DB_PATH" "DELETE FROM styles WHERE styleID='$STYLE_ID';" 2>/dev/null || true

# Remove from Profile Styles directory
echo "Cleaning Profile Styles..."
rm -f "$STYLES_DIR/$STYLE_FILENAME"
# Also remove any file that might contain this ID (Zotero sometimes renames imported styles)
grep -l "$STYLE_ID" "$STYLES_DIR"/*.csl 2>/dev/null | xargs -r rm -f

# 5. Create the Custom CSL file in Documents
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"

echo "Creating custom CSL file..."
cat > "$DOCS_DIR/$STYLE_FILENAME" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" default-locale="en-US">
  <info>
    <title>Firm Standard 2025</title>
    <id>$STYLE_ID</id>
    <link href="$STYLE_ID" rel="self"/>
    <author>
      <name>Firm Knowledge Management</name>
    </author>
    <updated>2025-01-01T00:00:00+00:00</updated>
  </info>
  <citation>
    <layout>
      <text variable="title" font-weight="bold"/>
      <text variable="year" prefix=" (" suffix=")"/>
    </layout>
  </citation>
  <bibliography>
    <layout>
      <text variable="title" font-weight="bold"/>
    </layout>
  </bibliography>
</style>
EOF

chmod 644 "$DOCS_DIR/$STYLE_FILENAME"
chown ga:ga "$DOCS_DIR/$STYLE_FILENAME"

# 6. Ensure UI is ready
# Dismiss any stale dialogs
wait_and_dismiss_jurism_alerts 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# 7. Initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "Custom style created at: $DOCS_DIR/$STYLE_FILENAME"
echo "=== Task setup complete ==="