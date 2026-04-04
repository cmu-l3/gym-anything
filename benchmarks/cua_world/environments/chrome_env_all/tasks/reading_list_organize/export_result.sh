#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Task Export: reading_list_organize@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time to ensure Reading List is synced
echo "Focusing Chrome to sync Reading List..."
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 2

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Save all tab URLs for debugging
    jq -r '.[] | select(.type == "page") | .url' /tmp/chrome_tabs.json > /tmp/all_tab_urls.txt
    echo "All tab URLs saved to /tmp/all_tab_urls.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# CRITICAL: Gracefully close Chrome to ensure Reading List database is persisted to disk
echo "Closing Chrome to save Reading List database..."
pkill -TERM -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Additional wait to ensure database writes are flushed
sleep 1

# Export Reading List database to temporary location for verification
echo "Exporting Chrome Reading List database..."

# Create verification directory
VERIFY_DIR="/tmp/reading_list_verification"
mkdir -p "$VERIFY_DIR"

# Try both possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

READING_LIST_FOUND=false

for PROFILE_PATH in "${CHROME_PROFILES[@]}"; do
    READING_LIST_DB="$PROFILE_PATH/Reading List"
    
    if [ -f "$READING_LIST_DB" ]; then
        echo "✓ Found Reading List database at: $READING_LIST_DB"
        
        # Copy database to verification directory
        cp "$READING_LIST_DB" "$VERIFY_DIR/reading_list.db"
        
        # Also copy to /tmp for easier access
        cp "$READING_LIST_DB" "/tmp/reading_list.db"
        
        # Get file size and modification time for debugging
        ls -lh "$READING_LIST_DB"
        stat "$READING_LIST_DB" || true
        
        # Quick SQLite integrity check
        if command -v sqlite3 &> /dev/null; then
            echo "Running SQLite integrity check..."
            sqlite3 "$READING_LIST_DB" "PRAGMA integrity_check;" || echo "⚠ Warning: Database integrity check failed"
            
            # Try to get table list
            echo "Database tables:"
            sqlite3 "$READING_LIST_DB" ".tables" || echo "⚠ Warning: Could not list tables"
            
            # Try to get schema
            echo "Database schema:"
            sqlite3 "$READING_LIST_DB" ".schema" > "$VERIFY_DIR/schema.txt" 2>&1 || echo "⚠ Warning: Could not get schema"
            
            # Try to count entries
            echo "Attempting to count Reading List entries..."
            ENTRY_COUNT=$(sqlite3 "$READING_LIST_DB" "SELECT COUNT(*) FROM reading_list;" 2>/dev/null || echo "unknown")
            echo "Entry count: $ENTRY_COUNT"
            echo "$ENTRY_COUNT" > "$VERIFY_DIR/entry_count.txt"
        fi
        
        READING_LIST_FOUND=true
        echo "$PROFILE_PATH" > "$VERIFY_DIR/source_profile.txt"
        break
    else
        echo "⚠ Reading List database not found at: $READING_LIST_DB"
    fi
done

if [ "$READING_LIST_FOUND" = false ]; then
    echo "✗ ERROR: Reading List database not found in any profile location"
    echo "Searched locations:"
    for PROFILE_PATH in "${CHROME_PROFILES[@]}"; do
        echo "  - $PROFILE_PATH/Reading List"
    done
    
    # List contents of profile directories for debugging
    for PROFILE_PATH in "${CHROME_PROFILES[@]}"; do
        if [ -d "$PROFILE_PATH" ]; then
            echo "Contents of $PROFILE_PATH:"
            ls -la "$PROFILE_PATH" | head -20
        fi
    done
    
    echo "none" > "$VERIFY_DIR/reading_list_status.txt"
else
    echo "found" > "$VERIFY_DIR/reading_list_status.txt"
fi

# Export additional Chrome state for debugging
echo "Exporting additional Chrome state..."

# Try to copy Bookmarks file (Reading List was sometimes stored there in older Chrome versions)
for PROFILE_PATH in "${CHROME_PROFILES[@]}"; do
    if [ -f "$PROFILE_PATH/Bookmarks" ]; then
        cp "$PROFILE_PATH/Bookmarks" "$VERIFY_DIR/bookmarks.json" 2>/dev/null || true
        break
    fi
done

# Try to copy Preferences file
for PROFILE_PATH in "${CHROME_PROFILES[@]}"; do
    if [ -f "$PROFILE_PATH/Preferences" ]; then
        cp "$PROFILE_PATH/Preferences" "$VERIFY_DIR/preferences.json" 2>/dev/null || true
        break
    fi
done

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"