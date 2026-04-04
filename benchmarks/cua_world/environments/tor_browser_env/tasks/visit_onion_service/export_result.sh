#!/bin/bash
# export_result.sh - Post-task hook for visit_onion_service task
# Exports browsing data for verification

echo "=== Exporting visit_onion_service task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Get initial counts and task start timestamp
INITIAL_HISTORY_COUNT=$(cat /tmp/initial_history_count 2>/dev/null || echo "0")
ONION_ALREADY_VISITED=$(cat /tmp/onion_already_visited 2>/dev/null || echo "false")
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "Task start timestamp: $TASK_START_TIMESTAMP"

# Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Using Tor Browser profile: $PROFILE_DIR"
        break
    fi
done

PLACES_DB="$PROFILE_DIR/places.sqlite"

# Initialize result variables
CURRENT_HISTORY_COUNT=0
ONION_URL_VISITED="false"
SEARCH_PERFORMED="false"
VISITED_URL=""
PAGE_TITLE=""
NEW_HISTORY_COUNT=0
VISIT_TIMESTAMP=0
VISIT_AFTER_TASK_START="false"

if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    # Copy database to avoid lock issues
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null

    if [ -f "$TEMP_DB" ]; then
        # Get current history count
        CURRENT_HISTORY_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_historyvisits;" 2>/dev/null || echo "0")

        # Calculate new history entries
        NEW_HISTORY_COUNT=$((CURRENT_HISTORY_COUNT - INITIAL_HISTORY_COUNT))

        # Check for DuckDuckGo onion visit with timestamp verification
        # Firefox stores visit_date as microseconds since Unix epoch
        DUCKDUCKGO_RESULT=$(sqlite3 "$TEMP_DB" "
            SELECT p.url, p.title, h.visit_date
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE LOWER(p.url) LIKE '%duckduckgo%onion%'
            ORDER BY h.visit_date DESC
            LIMIT 1;
        " 2>/dev/null || echo "")

        if [ -n "$DUCKDUCKGO_RESULT" ]; then
            ONION_URL_VISITED="true"
            VISITED_URL=$(echo "$DUCKDUCKGO_RESULT" | cut -d'|' -f1)
            PAGE_TITLE=$(echo "$DUCKDUCKGO_RESULT" | cut -d'|' -f2)
            # Convert Firefox microseconds to Unix seconds
            VISIT_DATE_MICRO=$(echo "$DUCKDUCKGO_RESULT" | cut -d'|' -f3)
            if [ -n "$VISIT_DATE_MICRO" ] && [ "$VISIT_DATE_MICRO" != "" ]; then
                VISIT_TIMESTAMP=$((VISIT_DATE_MICRO / 1000000))
                echo "Visit timestamp: $VISIT_TIMESTAMP (task start: $TASK_START_TIMESTAMP)"

                # TIMESTAMP VERIFICATION: Ensure visit happened after task started
                # This prevents adversarial attacks where entries are inserted from previous runs
                if [ "$VISIT_TIMESTAMP" -gt "$TASK_START_TIMESTAMP" ]; then
                    VISIT_AFTER_TASK_START="true"
                    echo "Visit verified: occurred after task start"
                else
                    echo "WARNING: Visit timestamp ($VISIT_TIMESTAMP) is before task start ($TASK_START_TIMESTAMP)"
                fi
            fi
            echo "Found DuckDuckGo onion visit: $VISITED_URL"

            # Check if a search was performed (URL contains q= parameter)
            if echo "$VISITED_URL" | grep -qiE "q=.*tor"; then
                SEARCH_PERFORMED="true"
                echo "Search for 'Tor' was performed"
            fi
        fi

        # Get recent history for debugging
        RECENT_HISTORY=$(sqlite3 "$TEMP_DB" "
            SELECT p.url, p.title
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            ORDER BY h.visit_date DESC
            LIMIT 10;
        " 2>/dev/null || echo "")

        rm -f "$TEMP_DB"
    fi
else
    echo "WARNING: places.sqlite not found at $PLACES_DB"
fi

# Check Tor Browser window for visual confirmation
TOR_BROWSER_RUNNING="false"
TOR_WINDOW_TITLE=""
CURRENT_URL=""
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_BROWSER_RUNNING="true"
    TOR_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | cut -d' ' -f5-)

    # Try to extract URL from address bar using xdotool
    # Focus Tor Browser window
    TOR_WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
    if [ -n "$TOR_WINDOW_ID" ]; then
        DISPLAY=:1 wmctrl -i -a "$TOR_WINDOW_ID" 2>/dev/null || true
        sleep 0.5

        # Try to get URL via Ctrl+L (focus address bar) then Ctrl+A, Ctrl+C
        # First, use xdotool to get URL from clipboard
        DISPLAY=:1 xdotool key --window "$TOR_WINDOW_ID" ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key --window "$TOR_WINDOW_ID" ctrl+a 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool key --window "$TOR_WINDOW_ID" ctrl+c 2>/dev/null || true
        sleep 0.3
        CURRENT_URL=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")

        # Press Escape to deselect
        DISPLAY=:1 xdotool key --window "$TOR_WINDOW_ID" Escape 2>/dev/null || true

        echo "Extracted URL from address bar: $CURRENT_URL"
    fi
fi

# Fallback: Check window title AND clipboard URL for DuckDuckGo onion indicators
# SECURITY: We MUST verify the .onion domain is in the actual URL, not just window title
# Window title alone is NOT sufficient - agent could visit regular duckduckgo.com
if [ "$ONION_URL_VISITED" = "false" ]; then
    # CRITICAL: Only use window title fallback if clipboard URL contains .onion
    # This prevents adversarial bypass where agent visits duckduckgo.com instead of .onion
    if [ -n "$CURRENT_URL" ] && echo "$CURRENT_URL" | grep -qiE "\.onion"; then
        echo "Clipboard URL contains .onion domain: $CURRENT_URL"

        # Now check if it's the DuckDuckGo onion specifically
        if echo "$CURRENT_URL" | grep -qiE "duckduckgo.*\.onion"; then
            ONION_URL_VISITED="true"
            VISITED_URL="$CURRENT_URL"
            PAGE_TITLE="$TOR_WINDOW_TITLE"
            echo "Using verified .onion URL from address bar: $VISITED_URL"

            # Check for search query in URL
            if echo "$VISITED_URL" | grep -qiE "q=.*tor"; then
                SEARCH_PERFORMED="true"
                echo "Search for 'Tor' detected in URL"
            fi
        else
            echo "WARNING: URL contains .onion but not DuckDuckGo: $CURRENT_URL"
        fi
    else
        # No .onion URL in clipboard - cannot verify onion visit
        echo "WARNING: Could not verify .onion domain visit"
        echo "Window title: $TOR_WINDOW_TITLE"
        echo "Clipboard URL: $CURRENT_URL"
        echo "REJECTING: .onion verification required but not found"
    fi
fi

# Escape special characters for JSON
escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

VISITED_URL_ESCAPED=$(escape_json "$VISITED_URL")
PAGE_TITLE_ESCAPED=$(escape_json "$PAGE_TITLE")
TOR_WINDOW_TITLE_ESCAPED=$(escape_json "$TOR_WINDOW_TITLE")
RECENT_HISTORY_ESCAPED=$(escape_json "$RECENT_HISTORY")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_history_count": $INITIAL_HISTORY_COUNT,
    "current_history_count": $CURRENT_HISTORY_COUNT,
    "new_history_entries": $NEW_HISTORY_COUNT,
    "onion_already_visited": $ONION_ALREADY_VISITED,
    "onion_url_visited": $ONION_URL_VISITED,
    "search_performed": $SEARCH_PERFORMED,
    "visited_url": "$VISITED_URL_ESCAPED",
    "page_title": "$PAGE_TITLE_ESCAPED",
    "visit_timestamp": $VISIT_TIMESTAMP,
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "visit_after_task_start": $VISIT_AFTER_TASK_START,
    "tor_browser_running": $TOR_BROWSER_RUNNING,
    "tor_window_title": "$TOR_WINDOW_TITLE_ESCAPED",
    "recent_history": "$RECENT_HISTORY_ESCAPED",
    "places_db_exists": $([ -f "$PLACES_DB" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Result exported to /tmp/task_result.json ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
