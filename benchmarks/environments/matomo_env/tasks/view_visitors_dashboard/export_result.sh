#!/bin/bash
# Export script for View Visitors Dashboard task

echo "=== Exporting View Visitors Dashboard Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Analyze the current page by checking the Firefox window title and URL
echo "Analyzing current browser state..."

# Get the Firefox window title
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | cut -d' ' -f5-)
echo "Browser window title: $WINDOW_TITLE"

# Try to get the current URL from Firefox (more reliable than window title)
# Use xdotool to focus Firefox and copy URL from address bar
CURRENT_URL=""
if command -v xdotool &> /dev/null; then
    # Focus Firefox window
    FIREFOX_WID=$(DISPLAY=:1 xdotool search --name "Firefox" 2>/dev/null | head -1)
    if [ -n "$FIREFOX_WID" ]; then
        DISPLAY=:1 xdotool windowactivate --sync "$FIREFOX_WID" 2>/dev/null
        sleep 0.3
        # Press Ctrl+L to select address bar, then Ctrl+C to copy
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.2
        # Use xclip to get URL if available
        if command -v xclip &> /dev/null; then
            DISPLAY=:1 xdotool key ctrl+c
            sleep 0.2
            CURRENT_URL=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null | head -1)
        fi
        # Click away from address bar
        DISPLAY=:1 xdotool key Escape
    fi
fi
echo "Current URL: $CURRENT_URL"

# Check if we're on the Visitors Overview page by looking at common indicators
VISITORS_SECTION="false"
OVERVIEW_PAGE="false"
DATE_RANGE_CHANGED="false"
URL_INDICATES_VISITORS="false"

# Check URL for module=VisitsSummary or similar patterns (most reliable)
if echo "$CURRENT_URL" | grep -qi "module=VisitsSummary\|module=VisitorInterest\|action=index.*visitor"; then
    URL_INDICATES_VISITORS="true"
    VISITORS_SECTION="true"
    echo "Visitors section detected from URL"
fi

# Check window title for Visitors/Overview keywords (fallback)
if echo "$WINDOW_TITLE" | grep -qi "visitor"; then
    VISITORS_SECTION="true"
    echo "Visitors section detected in window title"
fi

if echo "$WINDOW_TITLE" | grep -qi "overview"; then
    OVERVIEW_PAGE="true"
    echo "Overview page detected in window title"
fi

# Check URL for overview action
if echo "$CURRENT_URL" | grep -qi "action=index"; then
    OVERVIEW_PAGE="true"
    echo "Overview page detected from URL"
fi

# Check if URL contains date range indicators (strict patterns only)
# Avoid matching arbitrary numbers like dates (e.g., 2030-01-15)
if echo "$CURRENT_URL" | grep -qi "period=range\|date=last30\|period=month"; then
    DATE_RANGE_CHANGED="true"
    echo "Date range change detected in URL"
fi

# Check if title contains date range indicators (strict patterns only)
# Require explicit "last 30" or "30 days" phrases, not just the number 30
if echo "$WINDOW_TITLE" | grep -qi "last 30\|30 days\|30 day"; then
    DATE_RANGE_CHANGED="true"
    echo "Date range change detected in window title"
fi

# Take a screenshot-based verification approach
# We'll check the page content via the browser's localStorage/sessionStorage if possible
# For now, we rely on visual/title-based detection

# Additional checks - get page source via screenshot analysis would require VLM
# For this task, we'll use a combination of window title and task completion signals

# If Matomo is properly configured, we can check if the visitors module is accessed
# by looking at URL patterns (unfortunately, we can't easily get the URL without more tools)

# Create a navigation success score based on detected indicators
NAVIGATION_SCORE=0
if [ "$VISITORS_SECTION" = "true" ]; then
    NAVIGATION_SCORE=$((NAVIGATION_SCORE + 30))
fi
if [ "$OVERVIEW_PAGE" = "true" ]; then
    NAVIGATION_SCORE=$((NAVIGATION_SCORE + 25))
fi
if [ "$DATE_RANGE_CHANGED" = "true" ]; then
    NAVIGATION_SCORE=$((NAVIGATION_SCORE + 30))
fi

# If we got a reasonable score from title analysis, mark navigation as completed
NAVIGATION_COMPLETED="false"
if [ $NAVIGATION_SCORE -ge 50 ]; then
    NAVIGATION_COMPLETED="true"
fi

# For tasks without database changes, we rely more heavily on visual verification
# The VLM-based verification in the verifier will provide additional confidence

# Create result JSON
TEMP_JSON=$(mktemp /tmp/visitors_dashboard_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "window_title": "$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g')",
    "current_url": "$(echo "$CURRENT_URL" | sed 's/"/\\"/g')",
    "url_indicates_visitors": $URL_INDICATES_VISITORS,
    "visitors_section_visible": $VISITORS_SECTION,
    "overview_page_loaded": $OVERVIEW_PAGE,
    "date_range_changed": $DATE_RANGE_CHANGED,
    "navigation_completed": $NAVIGATION_COMPLETED,
    "navigation_score": $NAVIGATION_SCORE,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/visitors_dashboard_result.json 2>/dev/null || sudo rm -f /tmp/visitors_dashboard_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/visitors_dashboard_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/visitors_dashboard_result.json
chmod 666 /tmp/visitors_dashboard_result.json 2>/dev/null || sudo chmod 666 /tmp/visitors_dashboard_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/visitors_dashboard_result.json"
cat /tmp/visitors_dashboard_result.json

echo ""
echo "=== Export Complete ==="
