#!/bin/bash
set -e

echo "=== Exporting task results ==="

# Output paths
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/airfoils/s1223_modified.dat"
INPUT_MD5_FILE="/tmp/input_file.md5"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze the airfoil file
# This is much more robust than bash for floating point geometry checks
cat > /tmp/analyze_airfoil.py << 'EOF'
import sys
import json
import os
import math

def analyze_airfoil(file_path, start_time):
    result = {
        "exists": False,
        "valid_format": False,
        "is_new": False,
        "panel_count": 0,
        "x_min": 0.0,
        "x_max": 0.0,
        "y_te_upper": 0.0,
        "y_te_lower": 0.0,
        "te_gap": 0.0,
        "te_center_y": 0.0,
        "is_normalized": False,
        "is_derotated": False
    }

    if not os.path.exists(file_path):
        return result
    
    result["exists"] = True
    
    # Check modification time
    try:
        mtime = os.path.getmtime(file_path)
        if mtime > float(start_time):
            result["is_new"] = True
    except:
        pass

    coords = []
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
            
        # Skip header lines (usually first line in QBlade/Selig format)
        # We assume coordinate lines start with numbers
        for line in lines:
            parts = line.strip().split()
            if len(parts) >= 2:
                try:
                    x = float(parts[0])
                    y = float(parts[1])
                    coords.append((x, y))
                except ValueError:
                    continue
        
        if len(coords) > 10:
            result["valid_format"] = True
            result["panel_count"] = len(coords)
            
            # Analyze geometry
            xs = [p[0] for p in coords]
            ys = [p[1] for p in coords]
            
            result["x_min"] = min(xs)
            result["x_max"] = max(xs)
            
            # Identify Trailing Edge (TE) points
            # QBlade usually exports airfoils starting at TE, going to LE, and back to TE
            # So coords[0] and coords[-1] are near TE
            
            # Robust TE finding: look for max x points
            # Assuming Selig format (Upper surface TE -> LE -> Lower surface TE)
            # But standardized airfoils are typically [1,0] -> [0,0] -> [1,0]
            
            te_upper = coords[0]
            te_lower = coords[-1]
            
            # If coordinates are ordered standardly (TE->LE->TE)
            # Point 0 is usually Upper TE, Point -1 is Lower TE
            
            result["y_te_upper"] = te_upper[1]
            result["y_te_lower"] = te_lower[1]
            
            result["te_gap"] = abs(te_upper[1] - te_lower[1])
            result["te_center_y"] = (te_upper[1] + te_lower[1]) / 2.0
            
            # Check Normalization
            # x range should be approx [0, 1]
            if 0.99 <= (result["x_max"] - result["x_min"]) <= 1.01 and \
               -0.01 <= result["x_min"] <= 0.01:
                result["is_normalized"] = True
                
            # Check De-rotation
            # TE center should be near y=0 (assuming LE is at 0,0 which is checked by x_min/normalization)
            if abs(result["te_center_y"]) < 0.01:
                result["is_derotated"] = True

    except Exception as e:
        print(f"Error analyzing file: {e}", file=sys.stderr)
        
    return result

if __name__ == "__main__":
    file_path = sys.argv[1]
    start_time = sys.argv[2]
    stats = analyze_airfoil(file_path, start_time)
    print(json.dumps(stats))
EOF

# Run analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_airfoil.py "$OUTPUT_FILE" "$TASK_START")

# Check if app was running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "analysis": $ANALYSIS_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json