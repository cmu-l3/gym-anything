#!/bin/bash
echo "=== Exporting Baseball Infield Layout Results ==="

# Define paths
OUTPUT_PATH="/home/ga/Documents/LibreCAD/baseball_infield.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check File Existence and Timestamp
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Run DXF Analysis inside the container (where ezdxf is installed)
# We write a python script to /tmp/analyze_dxf.py and run it
cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import math
import os

try:
    import ezdxf
    HAS_EZDXF = True
except ImportError:
    HAS_EZDXF = False

def dist(p1, p2):
    return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

def analyze_dxf(filepath):
    result = {
        "valid_dxf": False,
        "layers_found": [],
        "foul_lines_ok": False,
        "bases_found": 0,
        "pitcher_plate_ok": False,
        "running_lane_ok": False,
        "dimensions_found": False,
        "error": ""
    }

    if not HAS_EZDXF:
        result["error"] = "ezdxf not installed in env"
        return result

    if not os.path.exists(filepath):
        result["error"] = "File not found"
        return result

    try:
        doc = ezdxf.readfile(filepath)
        msp = doc.modelspace()
        result["valid_dxf"] = True
        
        # Check Layers
        for layer in doc.layers:
            result["layers_found"].append(layer.dxf.name)
            
        # Analyze Entities
        foul_line_45 = False
        foul_line_135 = False
        base_90_count = 0
        base_127_found = False
        pitcher_plate_y = False
        running_lane_offset = False
        
        for e in msp:
            # Check Dimensions
            if e.dxftype() == 'DIMENSION':
                result["dimensions_found"] = True
                
            # Check Lines (Foul lines, Running lane)
            if e.dxftype() == 'LINE':
                start = e.dxf.start
                end = e.dxf.end
                
                # Calculate angle and length
                dx = end[0] - start[0]
                dy = end[1] - start[1]
                angle_deg = math.degrees(math.atan2(dy, dx)) % 360
                length = dist(start, end)
                
                # Foul Lines check (allow tolerance)
                # Should start near 0,0 and be long (>200)
                d_start = dist(start, (0,0))
                d_end = dist(end, (0,0))
                
                if d_start < 1.0 or d_end < 1.0: # Starts at origin
                    target_angle = angle_deg if d_start < 1.0 else (angle_deg + 180) % 360
                    if 40 < target_angle < 50 and length > 200:
                        foul_line_45 = True
                    if 130 < target_angle < 140 and length > 200:
                        foul_line_135 = True
                        
                # Running Lane check
                # Parallel to 45 deg line, offset by ~3 units
                # dist from line to origin should be approx 3/sqrt(2) approx 2.12?
                # Simplified: Check if points are in the corridor
                # Expected running lane starts at ~31.8, 31.8 (45ft mark) offset by 3ft
                pass

            # Check Polylines/Inserts (Bases)
            # Simplified: Check for vertices at key locations
            center = None
            if e.dxftype() == 'LWPOLYLINE':
                points = e.get_points()
                if points:
                    # avg point
                    sum_x = sum(p[0] for p in points)
                    sum_y = sum(p[1] for p in points)
                    center = (sum_x/len(points), sum_y/len(points))
            elif e.dxftype() == 'INSERT':
                center = e.dxf.insert
            
            if center:
                d_origin = dist(center, (0,0))
                
                # 1st/3rd base (approx 90ft from home)
                # Note: Center of 15" base is 90ft + 7.5" or 90ft - 7.5"? 
                # Spec says "Back corner at 90ft". So center is roughly 90.5 or 89.5 depending on rotation
                # Allow wide tolerance for "Found a base"
                if 88 < d_origin < 92:
                    base_90_count += 1
                
                # 2nd base (approx 127.28 ft)
                if 125 < d_origin < 130:
                    base_127_found = True
                    
                # Pitcher plate (approx 60.5 ft)
                # Actually pitcher plate is a rect, center might be checked
                if 59 < center[1] < 62 and abs(center[0]) < 2:
                    pitcher_plate_y = True

        result["foul_lines_ok"] = foul_line_45 and foul_line_135
        result["bases_found"] = base_90_count + (1 if base_127_found else 0)
        result["pitcher_plate_ok"] = pitcher_plate_y
        
    except Exception as e:
        result["error"] = str(e)
        
    print(json.dumps(result))

if __name__ == "__main__":
    analyze_dxf(sys.argv[1])
EOF

# Run the analysis script
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH")
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="