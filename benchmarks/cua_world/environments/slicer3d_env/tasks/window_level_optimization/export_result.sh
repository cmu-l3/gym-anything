#!/bin/bash
echo "=== Exporting Window/Level Optimization Result ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_LUNG="$LIDC_DIR/lung_window.png"
OUTPUT_SOFT="$LIDC_DIR/soft_tissue_window.png"
OUTPUT_BONE="$LIDC_DIR/bone_window.png"
OUTPUT_REPORT="$LIDC_DIR/window_level_report.json"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/wl_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Function to check screenshot validity
check_screenshot() {
    local path="$1"
    local name="$2"
    
    if [ -f "$path" ]; then
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local created_during_task="false"
        
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        
        echo "{\"exists\": true, \"size_bytes\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size_bytes\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Check all screenshots
LUNG_INFO=$(check_screenshot "$OUTPUT_LUNG" "lung")
SOFT_INFO=$(check_screenshot "$OUTPUT_SOFT" "soft_tissue")
BONE_INFO=$(check_screenshot "$OUTPUT_BONE" "bone")

# Check report file
REPORT_EXISTS="false"
REPORT_CONTENT="{}"
REPORT_VALID="false"

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    # Validate JSON and extract values
    REPORT_CONTENT=$(python3 << PYEOF
import json
import sys

try:
    with open("$OUTPUT_REPORT", 'r') as f:
        data = json.load(f)
    
    # Extract values if they exist
    result = {
        "valid": True,
        "lung_width": data.get("lung_window", {}).get("width", None),
        "lung_level": data.get("lung_window", {}).get("level", None),
        "soft_tissue_width": data.get("soft_tissue_window", {}).get("width", None),
        "soft_tissue_level": data.get("soft_tissue_window", {}).get("level", None),
        "bone_width": data.get("bone_window", {}).get("width", None),
        "bone_level": data.get("bone_window", {}).get("level", None)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
    REPORT_VALID=$(echo "$REPORT_CONTENT" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('valid', False)).lower())")
else
    REPORT_CONTENT='{"valid": false}'
fi

# Analyze screenshots for histogram characteristics (if they exist)
analyze_screenshot() {
    local path="$1"
    
    python3 << PYEOF
import json
import sys

try:
    from PIL import Image
    import numpy as np
    
    img = Image.open("$path").convert('L')  # Convert to grayscale
    pixels = np.array(img).flatten()
    
    # Calculate histogram statistics
    mean_val = float(np.mean(pixels))
    std_val = float(np.std(pixels))
    dark_fraction = float(np.sum(pixels < 50) / len(pixels))
    bright_fraction = float(np.sum(pixels > 200) / len(pixels))
    mid_fraction = float(np.sum((pixels >= 50) & (pixels <= 200)) / len(pixels))
    
    result = {
        "analyzed": True,
        "mean": round(mean_val, 2),
        "std": round(std_val, 2),
        "dark_fraction": round(dark_fraction, 4),
        "bright_fraction": round(bright_fraction, 4),
        "mid_fraction": round(mid_fraction, 4),
        "width": img.width,
        "height": img.height
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"analyzed": False, "error": str(e)}))
PYEOF
}

# Analyze each screenshot if it exists
LUNG_ANALYSIS='{"analyzed": false}'
SOFT_ANALYSIS='{"analyzed": false}'
BONE_ANALYSIS='{"analyzed": false}'

if [ -f "$OUTPUT_LUNG" ]; then
    LUNG_ANALYSIS=$(analyze_screenshot "$OUTPUT_LUNG")
fi

if [ -f "$OUTPUT_SOFT" ]; then
    SOFT_ANALYSIS=$(analyze_screenshot "$OUTPUT_SOFT")
fi

if [ -f "$OUTPUT_BONE" ]; then
    BONE_ANALYSIS=$(analyze_screenshot "$OUTPUT_BONE")
fi

# Copy screenshots for verification
mkdir -p /tmp/wl_screenshots
cp "$OUTPUT_LUNG" /tmp/wl_screenshots/lung_window.png 2>/dev/null || true
cp "$OUTPUT_SOFT" /tmp/wl_screenshots/soft_tissue_window.png 2>/dev/null || true
cp "$OUTPUT_BONE" /tmp/wl_screenshots/bone_window.png 2>/dev/null || true
cp "$OUTPUT_REPORT" /tmp/wl_screenshots/window_level_report.json 2>/dev/null || true
chmod -R 755 /tmp/wl_screenshots 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "lung_screenshot": $LUNG_INFO,
    "lung_analysis": $LUNG_ANALYSIS,
    "soft_tissue_screenshot": $SOFT_INFO,
    "soft_tissue_analysis": $SOFT_ANALYSIS,
    "bone_screenshot": $BONE_INFO,
    "bone_analysis": $BONE_ANALYSIS,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_content": $REPORT_CONTENT,
    "screenshot_exists": $([ -f "/tmp/wl_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/wl_task_result.json 2>/dev/null || sudo rm -f /tmp/wl_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/wl_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/wl_task_result.json
chmod 666 /tmp/wl_task_result.json 2>/dev/null || sudo chmod 666 /tmp/wl_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/wl_task_result.json
echo ""
echo "=== Export Complete ==="