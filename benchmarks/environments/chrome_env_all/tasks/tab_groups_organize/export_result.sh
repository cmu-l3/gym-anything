#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Groups Organization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick xdotool wmctrl || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take screenshot of Chrome window showing tab bar
echo "Capturing Chrome window screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/chrome_fullscreen.png" 2>/dev/null || true
    
    # Also capture just the top portion with tab bar
    if [ -f /tmp/chrome_fullscreen.png ]; then
        convert /tmp/chrome_fullscreen.png -crop 1920x100+0+0 /tmp/chrome_tabbar.png 2>/dev/null || true
        echo "✓ Tab bar screenshot saved to /tmp/chrome_tabbar.png"
    fi
fi

# Capture all tabs via CDP
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/chrome_page_tabs.json > /tmp/tab_list.txt
    
    echo "Tab information:"
    cat /tmp/tab_list.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_list.txt
fi

# Try to extract tab group information using Chrome's internal state
echo "Attempting to extract tab group information..."

# Method 1: Try to use Chrome DevTools Protocol to inject script
# Note: This requires Chrome Extensions API access which may not be directly available via CDP
# We'll try an alternative approach by parsing session data

# Method 2: Check Chrome session storage for tab groups
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
SESSION_DIR="$CHROME_PROFILE/Sessions"

if [ -d "$SESSION_DIR" ]; then
    echo "Found Chrome session directory"
    # Copy session files for analysis (they contain tab group data but are binary)
    mkdir -p /tmp/chrome_sessions
    cp -r "$SESSION_DIR"/* /tmp/chrome_sessions/ 2>/dev/null || true
fi

# Method 3: Create a simple marker file approach
# If the agent properly creates groups, we can detect them indirectly through:
# - Screenshot analysis showing colored tab bars
# - Changes in tab organization patterns
# - Presence of group metadata in various Chrome state files

# Create a lightweight extension manifest that could extract group info
mkdir -p /tmp/tab_group_extractor
cat > /tmp/tab_group_extractor/manifest.json << 'EOF'
{
  "manifest_version": 3,
  "name": "Tab Group Info Extractor",
  "version": "1.0",
  "description": "Extracts tab group information for verification",
  "permissions": ["tabGroups", "tabs"],
  "background": {
    "service_worker": "background.js"
  }
}
EOF

cat > /tmp/tab_group_extractor/background.js << 'EOF'
// Extract tab group information and write to a file-like output
chrome.runtime.onInstalled.addListener(async () => {
  try {
    const groups = await chrome.tabGroups.query({});
    const tabs = await chrome.tabs.query({});
    
    const result = {
      groups: groups.map(g => ({
        id: g.id,
        title: g.title,
        color: g.color,
        collapsed: g.collapsed
      })),
      tabs: tabs.map(t => ({
        id: t.id,
        groupId: t.groupId,
        url: t.url,
        title: t.title
      }))
    };
    
    // Log to console (can be captured via CDP)
    console.log("TAB_GROUP_DATA:", JSON.stringify(result));
  } catch (error) {
    console.error("Error extracting tab groups:", error);
  }
});

// Also provide an immediate query
setTimeout(async () => {
  try {
    const groups = await chrome.tabGroups.query({});
    const tabs = await chrome.tabs.query({});
    
    const result = {
      groups: groups.map(g => ({
        id: g.id,
        title: g.title,
        color: g.color,
        collapsed: g.collapsed
      })),
      tabs: tabs.map(t => ({
        id: t.id,
        groupId: t.groupId,
        url: t.url,
        title: t.title
      })),
      timestamp: new Date().toISOString()
    };
    
    console.log("TAB_GROUP_DATA:", JSON.stringify(result));
  } catch (error) {
    console.error("Error in delayed extraction:", error);
  }
}, 2000);
EOF

echo "✓ Created tab group extractor extension"

# Try to load the extension (this would require Chrome to be restarted with --load-extension flag)
# Since we can't easily reload Chrome mid-task, we'll rely on other verification methods

# Method 4: Parse Chrome Preferences for any group-related settings
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json 2>/dev/null || true
    echo "✓ Copied Chrome Preferences"
fi

# Method 5: Create a summary file with all available information
cat > /tmp/tab_groups_summary.txt << EOF
=== Tab Groups Organization Task Summary ===
Timestamp: $(date -Iseconds)
Tab Count: $TAB_COUNT

Available verification artifacts:
- CDP Tab Data: /tmp/chrome_page_tabs.json
- Tab List: /tmp/tab_list.txt
- Screenshot: /tmp/chrome_fullscreen.png
- Tab Bar Screenshot: /tmp/chrome_tabbar.png
- Chrome Preferences: /tmp/chrome_preferences.json
- Session Directory: $([ -d /tmp/chrome_sessions ] && echo "Available" || echo "Not found")

Note: Tab group information is primarily stored in:
1. Chrome session files (binary Protocol Buffer format)
2. Accessible via Chrome Extensions API (tabGroups)
3. Visible in screenshots as colored vertical bars on tabs

Verification will use a combination of:
- Screenshot analysis for colored group indicators
- CDP tab data for organization patterns
- Heuristics for group detection
EOF

cat /tmp/tab_groups_summary.txt

# Final screenshot just before export completes
sleep 1
su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true

echo "✅ Export complete"
echo "All verification artifacts saved to /tmp/"