#!/bin/bash
# Export result for export_negative_mold_stl task

echo "=== Exporting export_negative_mold_stl result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/negative_mold.stl"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the STL file using Python to check geometry
# We need to verify it's the FULL VOLUME (large bbox) and has internal detail (high triangle count)
python3 << 'PYEOF'
import struct
import os
import json
import math

output_file = "/home/ga/Documents/negative_mold.stl"
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_binary_stl": False,
    "triangle_count": 0,
    "bbox_x_extent": 0.0,
    "bbox_y_extent": 0.0,
    "bbox_z_extent": 0.0,
    "is_full_volume": False,
    "has_internal_cavity": False,
    "error": None
}

if os.path.isfile(output_file):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_file)

    try:
        # Check binary STL header
        if result["file_size_bytes"] >= 84:
            with open(output_file, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    count = struct.unpack("<I", count_bytes)[0]
                    expected_size = 84 + count * 50
                    
                    # Allow small file size mismatch (some exporters add footers)
                    if abs(expected_size - result["file_size_bytes"]) <= 1024:
                        result["is_binary_stl"] = True
                        result["triangle_count"] = count
                        
                        # Read vertices to calculate bounding box
                        # This can be slow for huge files, so we'll sample or limit if it's massive
                        # But for InVesalius exports (<1M triangles), it's usually fine in <5 sec
                        min_x, max_x = float('inf'), float('-inf')
                        min_y, max_y = float('inf'), float('-inf')
                        min_z, max_z = float('inf'), float('-inf')
                        
                        # We iterate through triangles
                        # Format: normal (3f), v1 (3f), v2 (3f), v3 (3f), attr (H) = 50 bytes
                        # We only need vertices
                        f.seek(84)
                        
                        # Optimization: If count is huge, read in chunks
                        chunk_size = 1000
                        struct_fmt = "<12fH" * chunk_size
                        chunk_bytes = 50 * chunk_size
                        
                        for _ in range(0, count, chunk_size):
                            # Read a chunk
                            n_items = min(chunk_size, count - _)
                            data = f.read(n_items * 50)
                            if len(data) < n_items * 50:
                                break
                                
                            # Parse floats
                            # This is still CPU intensive in pure Python.
                            # Faster Approach: Read bytes directly and unpack only min/max candidates?
                            # Let's just do a simpler scan for this environment
                            for i in range(n_items):
                                offset = i * 50
                                # Vertices are at offsets 12, 24, 36
                                # v1
                                vx1, vy1, vz1 = struct.unpack_from("<3f", data, offset + 12)
                                # v2
                                vx2, vy2, vz2 = struct.unpack_from("<3f", data, offset + 24)
                                # v3
                                vx3, vy3, vz3 = struct.unpack_from("<3f", data, offset + 36)
                                
                                min_x = min(min_x, vx1, vx2, vx3)
                                max_x = max(max_x, vx1, vx2, vx3)
                                min_y = min(min_y, vy1, vy2, vy3)
                                max_y = max(max_y, vy1, vy2, vy3)
                                min_z = min(min_z, vz1, vz2, vz3)
                                max_z = max(max_z, vz1, vz2, vz3)

                        if min_x != float('inf'):
                            result["bbox_x_extent"] = max_x - min_x
                            result["bbox_y_extent"] = max_y - min_y
                            result["bbox_z_extent"] = max_z - min_z
                            
                            # CT Cranium is ~490mm wide. A skull is ~150mm.
                            # Threshold: > 400mm indicates full volume.
                            if result["bbox_x_extent"] > 400 or result["bbox_y_extent"] > 400:
                                result["is_full_volume"] = True
                            
                            # A solid cube has 12 triangles. A mold with a skull hole has thousands.
                            if count > 5000:
                                result["has_internal_cavity"] = True

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/export_negative_mold_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="