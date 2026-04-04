#!/bin/bash
echo "=== Exporting anaglyph_stereo_terrain task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Capture final screenshot FIRST (before any state changes)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
    FINAL_SIZE="0"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
fi
echo "Google Earth running: $GE_RUNNING (PID: $GE_PID)"

# Get current window info
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi
echo "Window title: $GE_WINDOW_TITLE"

# Check for Options dialog (indicates settings were accessed)
OPTIONS_VISIBLE="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Options\|Preferences\|Settings"; then
    OPTIONS_VISIBLE="true"
fi
echo "Options dialog visible: $OPTIONS_VISIBLE"

# Try to detect anaglyph setting from config files
ANAGLYPH_IN_CONFIG="unknown"
CONFIG_FILE="/home/ga/.config/Google/GoogleEarthPro.conf"
if [ -f "$CONFIG_FILE" ]; then
    if grep -qi "anaglyph.*true\|anaglyph.*1\|UseAnaglyph=1" "$CONFIG_FILE" 2>/dev/null; then
        ANAGLYPH_IN_CONFIG="true"
    elif grep -qi "anaglyph.*false\|anaglyph.*0\|UseAnaglyph=0" "$CONFIG_FILE" 2>/dev/null; then
        ANAGLYPH_IN_CONFIG="false"
    fi
fi
echo "Anaglyph in config: $ANAGLYPH_IN_CONFIG"

# Analyze the screenshot for red-cyan color separation (basic check)
ANAGLYPH_DETECTED="false"
COLOR_ANALYSIS=""
if [ -f /tmp/task_final.png ]; then
    # Use Python to do basic color analysis
    COLOR_ANALYSIS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    import numpy as np
    
    img = Image.open('/tmp/task_final.png').convert('RGB')
    arr = np.array(img)
    
    # Extract channels
    red = arr[:, :, 0].astype(float)
    green = arr[:, :, 1].astype(float)
    blue = arr[:, :, 2].astype(float)
    
    # Look for red-dominant and cyan-dominant pixels
    # In anaglyph mode, edges show red on one side, cyan on other
    red_dominant = (red > 150) & (green < 100) & (blue < 100)
    cyan_dominant = (red < 100) & ((green > 100) | (blue > 100))
    
    red_ratio = np.sum(red_dominant) / red.size
    cyan_ratio = np.sum(cyan_dominant) / cyan.size
    
    # Calculate color separation metric
    # Both red and cyan should be present in significant amounts for anaglyph
    min_ratio = min(red_ratio, cyan_ratio)
    anaglyph_score = min_ratio * 1000
    
    # Also check for edge color fringing (characteristic of anaglyph)
    # Compare horizontal gradients between channels
    red_grad = np.abs(np.diff(red, axis=1)).mean()
    cyan_grad = np.abs(np.diff((green + blue) / 2, axis=1)).mean()
    edge_diff = abs(red_grad - cyan_grad)
    
    result = {
        "red_dominant_ratio": float(red_ratio),
        "cyan_dominant_ratio": float(cyan_ratio),
        "anaglyph_score": float(anaglyph_score),
        "red_edge_gradient": float(red_grad),
        "cyan_edge_gradient": float(cyan_grad),
        "edge_difference": float(edge_diff),
        "likely_anaglyph": anaglyph_score > 1.5 or edge_diff > 3.0
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "likely_anaglyph": False}))
PYEOF
)
    
    if echo "$COLOR_ANALYSIS" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('likely_anaglyph', False) else 1)" 2>/dev/null; then
        ANAGLYPH_DETECTED="true"
    fi
fi
echo "Color analysis: $COLOR_ANALYSIS"
echo "Anaglyph detected: $ANAGLYPH_DETECTED"

# Check if screenshots changed (detect "do nothing")
SCREENSHOTS_DIFFERENT="false"
if [ -f /tmp/task_initial.png ] && [ -f /tmp/task_final.png ]; then
    # Compare screenshots using ImageMagick or Python
    DIFF_RESULT=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    import numpy as np
    
    img1 = Image.open('/tmp/task_initial.png').convert('RGB')
    img2 = Image.open('/tmp/task_final.png').convert('RGB')
    
    arr1 = np.array(img1).astype(float)
    arr2 = np.array(img2).astype(float)
    
    # Calculate mean absolute difference
    if arr1.shape == arr2.shape:
        diff = np.abs(arr1 - arr2).mean()
        different = diff > 5.0  # Threshold for "significant" change
    else:
        different = True  # Different sizes = different images
        diff = 999.0
    
    print(json.dumps({"different": different, "mean_diff": float(diff)}))
except Exception as e:
    print(json.dumps({"different": True, "error": str(e)}))
PYEOF
)
    
    if echo "$DIFF_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('different', True) else 1)" 2>/dev/null; then
        SCREENSHOTS_DIFFERENT="true"
    fi
fi
echo "Screenshots different: $SCREENSHOTS_DIFFERENT"

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "window_title": "$GE_WINDOW_TITLE",
    "options_dialog_visible": $OPTIONS_VISIBLE,
    "anaglyph_in_config": "$ANAGLYPH_IN_CONFIG",
    "anaglyph_detected_in_screenshot": $ANAGLYPH_DETECTED,
    "color_analysis": $COLOR_ANALYSIS,
    "screenshots_different": $SCREENSHOTS_DIFFERENT,
    "initial_screenshot": "/tmp/task_initial.png",
    "final_screenshot": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json