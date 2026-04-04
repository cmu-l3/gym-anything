#!/bin/bash
# Export result for export_skull_stl task

echo "=== Exporting export_skull_stl result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/skull_model.stl"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyse the STL file using Python
python3 << 'PYEOF'
import struct, os, json, sys

output_file = "/home/ga/Documents/skull_model.stl"
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_binary_stl": False,
    "is_ascii_stl": False,
    "triangle_count": 0,
    "stl_valid": False,
}

if os.path.isfile(output_file):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_file)

    with open(output_file, "rb") as f:
        header = f.read(80)

    # Check binary STL
    if result["file_size_bytes"] >= 84:
        with open(output_file, "rb") as f:
            f.read(80)  # skip header
            count_bytes = f.read(4)
            if len(count_bytes) == 4:
                count = struct.unpack("<I", count_bytes)[0]
                expected_size = 80 + 4 + count * 50
                if abs(expected_size - result["file_size_bytes"]) <= 512:
                    result["is_binary_stl"] = True
                    result["triangle_count"] = count
                    result["stl_valid"] = True

    # Check ASCII STL (fallback)
    if not result["is_binary_stl"]:
        try:
            with open(output_file, "r", errors="replace") as f:
                first_line = f.readline().strip().lower()
            if first_line.startswith("solid"):
                # Count facet lines
                count = 0
                with open(output_file, "r", errors="replace") as f:
                    for line in f:
                        if line.strip().lower().startswith("facet normal"):
                            count += 1
                if count > 0:
                    result["is_ascii_stl"] = True
                    result["triangle_count"] = count
                    result["stl_valid"] = True
        except Exception:
            pass

with open("/tmp/export_skull_stl_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
