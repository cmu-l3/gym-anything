#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a robust Python script to calculate the bounding box of the STL
# This avoids transferring large binary files to the host via copy_from_env
cat > /tmp/analyze_stl.py << 'EOF'
import struct
import sys
import json
import os
import re

def get_stl_info(filepath):
    if not os.path.exists(filepath):
        return {"exists": False}
    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            count_bytes = f.read(4)
            
            # Check if it's an ASCII STL by looking for "solid" keyword at start
            if header[0:5].lower() == b'solid':
                f.seek(0)
                content = f.read(4096).decode('utf-8', errors='ignore')
                if 'facet normal' in content or 'vertex' in content:
                    # Parse ASCII STL with regex
                    f.seek(0)
                    full_content = f.read().decode('utf-8', errors='ignore')
                    vertices = re.findall(r'vertex\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)', full_content)
                    if not vertices:
                        return {"exists": True, "error": "No vertices found in ASCII STL"}
                    
                    xs = [float(v[0]) for v in vertices]
                    ys = [float(v[1]) for v in vertices]
                    zs = [float(v[2]) for v in vertices]
                    return {
                        "exists": True,
                        "is_ascii": True,
                        "dx": max(xs) - min(xs),
                        "dy": max(ys) - min(ys),
                        "dz": max(zs) - min(zs),
                        "num_tris": len(vertices) // 3
                    }

            # Otherwise, parse as Binary STL (SolveSpace default)
            if len(count_bytes) < 4:
                return {"exists": True, "error": "Invalid binary STL format"}

            num_tris = struct.unpack('<I', count_bytes)[0]
            if num_tris == 0 or num_tris > 10000000:
                return {"exists": True, "num_tris": num_tris, "error": "Suspicious triangle count"}

            min_v = [float('inf'), float('inf'), float('inf')]
            max_v = [float('-inf'), float('-inf'), float('-inf')]

            for _ in range(num_tris):
                f.read(12) # skip normal vector
                for _ in range(3):
                    data = f.read(12)
                    if len(data) < 12: break
                    v = struct.unpack('<3f', data)
                    for i in range(3):
                        min_v[i] = min(min_v[i], v[i])
                        max_v[i] = max(max_v[i], v[i])
                f.read(2) # skip attribute byte count

            return {
                "exists": True,
                "is_ascii": False,
                "dx": max_v[0] - min_v[0],
                "dy": max_v[1] - min_v[1],
                "dz": max_v[2] - min_v[2],
                "num_tris": num_tris
            }
    except Exception as e:
        return {"exists": True, "error": str(e)}

if __name__ == "__main__":
    filepath = sys.argv[1] if len(sys.argv) > 1 else ""
    print(json.dumps(get_stl_info(filepath)))
EOF

# Extract SLVS info
SLVS_EXISTS="false"
SLVS_MTIME="0"
SLVS_PATH="/home/ga/Documents/SolveSpace/stair_stringer.slvs"

if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
fi

# Extract STL info
STL_PATH="/home/ga/Documents/SolveSpace/stair_stringer.stl"
STL_INFO=$(python3 /tmp/analyze_stl.py "$STL_PATH" 2>/dev/null || echo '{"exists": false}')

# Combine into task result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_mtime": $SLVS_MTIME,
    "stl_info": $STL_INFO
}
EOF

# Securely move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="