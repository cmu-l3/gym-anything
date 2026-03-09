#!/bin/bash
echo "=== Exporting STL Export Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ============================================================
# CAPTURE TIMING AND STATE
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task start: $TASK_START"
echo "Task end: $TASK_END"

EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
EXPECTED_OUTPUT="$EXPORT_DIR/tumor_model.stl"
RESULT_FILE="/tmp/stl_export_result.json"

# ============================================================
# CAPTURE FINAL SCREENSHOT
# ============================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_SIZE" -gt 1000 ]; then
        SCREENSHOT_EXISTS="true"
        echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    fi
fi

# ============================================================
# CHECK IF SLICER IS RUNNING
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ============================================================
# CHECK FOR STL OUTPUT FILE
# ============================================================
echo ""
echo "Checking for STL output file..."

STL_EXISTS="false"
STL_SIZE=0
STL_MOD_TIME=0
STL_CREATED_DURING_TASK="false"

# Check expected output location
if [ -f "$EXPECTED_OUTPUT" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    STL_MOD_TIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    echo "Found STL at expected location: $EXPECTED_OUTPUT"
    echo "  Size: $STL_SIZE bytes"
    echo "  Modified: $STL_MOD_TIME"
    
    # Check if file was created during task (anti-gaming)
    if [ "$STL_MOD_TIME" -gt "$TASK_START" ]; then
        STL_CREATED_DURING_TASK="true"
        echo "  Created during task: YES"
    else
        echo "  Created during task: NO (suspicious)"
    fi
else
    # Search for any STL files in export directory
    echo "Searching for STL files in $EXPORT_DIR..."
    STL_FOUND=$(find "$EXPORT_DIR" -maxdepth 1 -name "*.stl" -type f 2>/dev/null | head -1)
    
    if [ -n "$STL_FOUND" ]; then
        echo "Found alternate STL: $STL_FOUND"
        STL_EXISTS="true"
        STL_SIZE=$(stat -c%s "$STL_FOUND" 2>/dev/null || echo "0")
        STL_MOD_TIME=$(stat -c%Y "$STL_FOUND" 2>/dev/null || echo "0")
        
        if [ "$STL_MOD_TIME" -gt "$TASK_START" ]; then
            STL_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location for easier verification
        cp "$STL_FOUND" "$EXPECTED_OUTPUT" 2>/dev/null || true
    else
        # Also check home directory and Desktop
        for search_dir in "/home/ga" "/home/ga/Desktop" "/home/ga/Documents"; do
            STL_FOUND=$(find "$search_dir" -maxdepth 2 -name "*.stl" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
            if [ -n "$STL_FOUND" ]; then
                echo "Found STL in alternate location: $STL_FOUND"
                STL_EXISTS="true"
                STL_SIZE=$(stat -c%s "$STL_FOUND" 2>/dev/null || echo "0")
                STL_MOD_TIME=$(stat -c%Y "$STL_FOUND" 2>/dev/null || echo "0")
                STL_CREATED_DURING_TASK="true"
                cp "$STL_FOUND" "$EXPECTED_OUTPUT" 2>/dev/null || true
                break
            fi
        done
    fi
fi

if [ "$STL_EXISTS" = "false" ]; then
    echo "No STL file found"
fi

# ============================================================
# PARSE AND VALIDATE STL FILE
# ============================================================
STL_VALID="false"
STL_FORMAT="unknown"
TRIANGLE_COUNT=0
VERTEX_COUNT=0
BBOX_X=0
BBOX_Y=0
BBOX_Z=0
STL_PARSE_ERROR=""

if [ "$STL_EXISTS" = "true" ] && [ "$STL_SIZE" -gt 100 ]; then
    echo ""
    echo "Parsing STL file..."
    
    python3 << 'PYEOF'
import struct
import json
import os
import sys

stl_file = os.environ.get("EXPECTED_OUTPUT", "/home/ga/Documents/SlicerData/Exports/tumor_model.stl")
output_file = "/tmp/stl_parse_result.json"

result = {
    "valid": False,
    "format": "unknown",
    "triangles": 0,
    "vertices": 0,
    "bbox": [0, 0, 0],
    "error": None
}

try:
    with open(stl_file, 'rb') as f:
        header = f.read(80)
        
        # Check if ASCII STL (starts with "solid")
        f.seek(0)
        first_bytes = f.read(6)
        
        if first_bytes.lower().startswith(b'solid'):
            # Might be ASCII STL - check further
            f.seek(0)
            content = f.read().decode('ascii', errors='ignore')
            
            # True ASCII STL should have "facet normal" after "solid"
            if 'facet normal' in content.lower():
                result["format"] = "ascii"
                
                # Count triangles
                import re
                triangles = len(re.findall(r'facet\s+normal', content, re.IGNORECASE))
                result["triangles"] = triangles
                result["vertices"] = triangles * 3
                
                # Parse vertices for bounding box
                vertices = re.findall(r'vertex\s+([-\d.e+]+)\s+([-\d.e+]+)\s+([-\d.e+]+)', content, re.IGNORECASE)
                if vertices:
                    xs = [float(v[0]) for v in vertices]
                    ys = [float(v[1]) for v in vertices]
                    zs = [float(v[2]) for v in vertices]
                    result["bbox"] = [
                        round(max(xs) - min(xs), 2),
                        round(max(ys) - min(ys), 2),
                        round(max(zs) - min(zs), 2)
                    ]
                
                result["valid"] = triangles > 0
            else:
                # Not ASCII, try binary
                result["format"] = "binary"
        
        if result["format"] in ["unknown", "binary"]:
            # Binary STL format
            result["format"] = "binary"
            f.seek(80)  # Skip header
            triangle_count_bytes = f.read(4)
            
            if len(triangle_count_bytes) == 4:
                triangle_count = struct.unpack('<I', triangle_count_bytes)[0]
                result["triangles"] = triangle_count
                result["vertices"] = triangle_count * 3
                
                # Read triangles for bounding box (sample if too many)
                min_x, min_y, min_z = float('inf'), float('inf'), float('inf')
                max_x, max_y, max_z = float('-inf'), float('-inf'), float('-inf')
                
                sample_count = min(triangle_count, 50000)
                
                for i in range(sample_count):
                    try:
                        # Normal (12 bytes)
                        f.read(12)
                        # 3 vertices (36 bytes total)
                        for _ in range(3):
                            vertex = struct.unpack('<3f', f.read(12))
                            min_x = min(min_x, vertex[0])
                            max_x = max(max_x, vertex[0])
                            min_y = min(min_y, vertex[1])
                            max_y = max(max_y, vertex[1])
                            min_z = min(min_z, vertex[2])
                            max_z = max(max_z, vertex[2])
                        # Attribute (2 bytes)
                        f.read(2)
                    except Exception:
                        break
                
                if min_x != float('inf'):
                    result["bbox"] = [
                        round(max_x - min_x, 2),
                        round(max_y - min_y, 2),
                        round(max_z - min_z, 2)
                    ]
                
                result["valid"] = triangle_count > 0

except Exception as e:
    result["error"] = str(e)
    print(f"Error parsing STL: {e}", file=sys.stderr)

# Write results
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"STL Parse Result:")
print(f"  Valid: {result['valid']}")
print(f"  Format: {result['format']}")
print(f"  Triangles: {result['triangles']}")
print(f"  Bounding Box: {result['bbox']}")
if result['error']:
    print(f"  Error: {result['error']}")
PYEOF

    # Export environment variable for Python script
    export EXPECTED_OUTPUT
    
    # Read parse results
    if [ -f /tmp/stl_parse_result.json ]; then
        STL_VALID=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(str(d.get('valid', False)).lower())" 2>/dev/null || echo "false")
        STL_FORMAT=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(d.get('format', 'unknown'))" 2>/dev/null || echo "unknown")
        TRIANGLE_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(d.get('triangles', 0))" 2>/dev/null || echo "0")
        VERTEX_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(d.get('vertices', 0))" 2>/dev/null || echo "0")
        BBOX_X=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(d.get('bbox', [0,0,0])[0])" 2>/dev/null || echo "0")
        BBOX_Y=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(d.get('bbox', [0,0,0])[1])" 2>/dev/null || echo "0")
        BBOX_Z=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); print(d.get('bbox', [0,0,0])[2])" 2>/dev/null || echo "0")
        STL_PARSE_ERROR=$(python3 -c "import json; d=json.load(open('/tmp/stl_parse_result.json')); e=d.get('error'); print(e if e else '')" 2>/dev/null || echo "")
    fi
fi

# ============================================================
# CALCULATE FILE SIZE IN KB
# ============================================================
STL_SIZE_KB=0
if [ "$STL_SIZE" -gt 0 ]; then
    STL_SIZE_KB=$((STL_SIZE / 1024))
fi

# ============================================================
# CREATE RESULT JSON
# ============================================================
echo ""
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "stl_file_exists": $STL_EXISTS,
    "stl_file_path": "$EXPECTED_OUTPUT",
    "stl_file_size_bytes": $STL_SIZE,
    "stl_file_size_kb": $STL_SIZE_KB,
    "stl_mod_time": $STL_MOD_TIME,
    "stl_created_during_task": $STL_CREATED_DURING_TASK,
    "stl_valid_format": $STL_VALID,
    "stl_format": "$STL_FORMAT",
    "stl_triangle_count": $TRIANGLE_COUNT,
    "stl_vertex_count": $VERTEX_COUNT,
    "stl_bbox_x_mm": $BBOX_X,
    "stl_bbox_y_mm": $BBOX_Y,
    "stl_bbox_z_mm": $BBOX_Z,
    "stl_parse_error": "$STL_PARSE_ERROR",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result Summary ==="
cat "$RESULT_FILE"

echo ""
echo "=== Export Complete ==="