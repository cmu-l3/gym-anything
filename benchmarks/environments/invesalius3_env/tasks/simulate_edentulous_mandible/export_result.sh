#!/bin/bash
set -e
echo "=== Exporting simulate_edentulous_mandible result ==="

source /workspace/scripts/task_utils.sh

# Capture Final State
take_screenshot /tmp/task_final.png

# Paths
STL_PATH="/home/ga/Documents/edentulous_skull.stl"
PNG_PATH="/home/ga/Documents/edentulous_view.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper function to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

STL_INFO=$(get_file_info "$STL_PATH")
PNG_INFO=$(get_file_info "$PNG_PATH")

# Analyze STL content (Volume & Triangles) using embedded Python
# This ensures we don't depend on external libraries being pre-installed, checking binary STL manually
STL_ANALYSIS=$(python3 -c "
import struct, sys, json

def signed_vol(p1, p2, p3):
    v321 = p3[0]*p2[1]*p1[2]
    v231 = p2[0]*p3[1]*p1[2]
    v312 = p3[0]*p1[1]*p2[2]
    v132 = p1[0]*p3[1]*p2[2]
    v213 = p2[0]*p1[1]*p3[2]
    v123 = p1[0]*p2[1]*p3[2]
    return (1.0/6.0)*(-v321 + v231 + v312 - v132 - v213 + v123)

result = {\"valid_binary\": False, \"triangles\": 0, \"volume\": 0.0}
path = \"$STL_PATH\"

try:
    with open(path, 'rb') as f:
        header = f.read(80)
        count_bytes = f.read(4)
        if len(count_bytes) == 4:
            count = struct.unpack('<I', count_bytes)[0]
            # Sanity check size
            f.seek(0, 2)
            filesize = f.tell()
            expected = 84 + count * 50
            if abs(filesize - expected) < 1000: # Allow some padding
                result['valid_binary'] = True
                result['triangles'] = count
                
                # Calculate volume
                f.seek(84)
                vol = 0.0
                for _ in range(count):
                    buf = f.read(50)
                    if len(buf) < 50: break
                    # floats at 12, 24, 36
                    v1 = struct.unpack('<fff', buf[12:24])
                    v2 = struct.unpack('<fff', buf[24:36])
                    v3 = struct.unpack('<fff', buf[36:48])
                    vol += signed_vol(v1, v2, v3)
                result['volume'] = abs(vol)
except Exception as e:
    pass

print(json.dumps(result))
")

# Combine into one JSON
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "stl_file": $STL_INFO,
  "png_file": $PNG_INFO,
  "stl_analysis": $STL_ANALYSIS,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json
echo "Export complete. Result:"
cat /tmp/task_result.json