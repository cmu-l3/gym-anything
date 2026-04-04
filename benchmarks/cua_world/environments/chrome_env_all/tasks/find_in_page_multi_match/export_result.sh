#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Find in Page Task Export: find_in_page_multi_match@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab information via CDP
echo "Capturing active tab state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Get the active page tab
    ACTIVE_TAB=$(jq '[.[] | select(.type == "page")][0]' /tmp/chrome_tabs.json)
    echo "$ACTIVE_TAB" > /tmp/active_tab_info.json
    
    # Extract webSocketDebuggerUrl for JavaScript execution
    WS_URL=$(echo "$ACTIVE_TAB" | jq -r '.webSocketDebuggerUrl // ""')
    echo "$WS_URL" > /tmp/ws_debugger_url.txt
    
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_TITLE" > /tmp/final_title.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "{}" > /tmp/active_tab_info.json
    echo "" > /tmp/ws_debugger_url.txt
    echo "" > /tmp/final_url.txt
    echo "" > /tmp/final_title.txt
fi

# Execute JavaScript via CDP to capture page state and selection
echo "Executing JavaScript to capture find state..."

# Create JavaScript to execute
cat > /tmp/capture_find_state.js << 'JSEOF'
(function() {
    try {
        // Get current text selection
        const selection = window.getSelection();
        const selectedText = selection ? selection.toString() : '';
        
        // Count occurrences of 'example' in page body text
        const bodyText = document.body.innerText || document.body.textContent || '';
        const searchTerm = 'example';
        const regex = new RegExp(searchTerm, 'gi');
        const matches = bodyText.match(regex);
        const matchCount = matches ? matches.length : 0;
        
        // Get scroll position
        const scrollY = window.scrollY || window.pageYOffset || 0;
        
        // Check if any text is selected that matches our search term
        const hasRelevantSelection = selectedText.toLowerCase().includes(searchTerm.toLowerCase());
        
        // Try to detect if find bar might be open (heuristic: text is selected)
        const likelyFindBarOpen = selectedText.length > 0 && hasRelevantSelection;
        
        return {
            success: true,
            selectedText: selectedText,
            matchCount: matchCount,
            searchTerm: searchTerm,
            hasRelevantSelection: hasRelevantSelection,
            likelyFindBarOpen: likelyFindBarOpen,
            scrollY: scrollY,
            bodyTextLength: bodyText.length
        };
    } catch (e) {
        return {
            success: false,
            error: e.toString()
        };
    }
})();
JSEOF

# Execute the JavaScript using CDP HTTP API
if [ -f /tmp/active_tab_info.json ]; then
    TAB_ID=$(jq -r '.id // ""' /tmp/active_tab_info.json)
    
    if [ -n "$TAB_ID" ] && [ "$TAB_ID" != "null" ]; then
        # Use Runtime.evaluate via CDP
        JS_CODE=$(cat /tmp/capture_find_state.js | jq -Rs .)
        
        curl -s -X POST "http://localhost:9222/json/new" > /dev/null 2>&1 || true
        
        # Try to get list of pages and find active one
        PAGE_LIST=$(curl -s "http://localhost:9222/json/list" 2>/dev/null || echo "[]")
        FIRST_PAGE_URL=$(echo "$PAGE_LIST" | jq -r '[.[] | select(.type == "page")][0].devtoolsFrontendUrl // ""' | sed 's|.*ws=||' | sed 's|/devtools.*||')
        
        # For simplicity, write the JavaScript code to a file for the verifier to execute
        cp /tmp/capture_find_state.js /tmp/find_state_script.js
        echo "✓ Find state capture script saved for verifier"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
echo "Files available for verification:"
echo "  - /tmp/active_tab_info.json (CDP tab information)"
echo "  - /tmp/final_url.txt (Active page URL)"
echo "  - /tmp/find_state_script.js (JavaScript for state verification)"