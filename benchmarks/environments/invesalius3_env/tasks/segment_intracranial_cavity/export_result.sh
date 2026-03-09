#!/bin/bash
# Export result for segment_intracranial_cavity task

echo "=== Exporting segment_intracranial_cavity result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/brain_model.stl"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the STL file using Python to calculate volume
# This avoids needing heavy VTK dependencies by implementing a simple mesh volume calc
python3 << 'PYEOF'
import struct
import os
import json
import numpy as np

output_file = "/home/ga/Documents/brain_model.stl"
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_binary_stl": False,
    "triangle_count": 0,
    "calculated_volume_ml": 0.0,
    "bounding_box_diag_mm": 0.0,
    "error": None
}

def calculate_signed_volume(v1, v2, v3):
    """Calculate signed volume of tetrahedron with origin."""
    return np.dot(v1, np.cross(v2, v3)) / 6.0

if os.path.isfile(output_file):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_file)

    try:
        # Check for Binary STL (80 bytes header + 4 bytes count)
        if result["file_size_bytes"] >= 84:
            with open(output_file, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                count = struct.unpack("<I", count_bytes)[0]
                
                # Verify file size matches triangle count expectation
                expected_size = 80 + 4 + count * 50
                # Allow some slack for extra footer bytes sometimes appended
                if abs(expected_size - result["file_size_bytes"]) <= 1024:
                    result["is_binary_stl"] = True
                    result["triangle_count"] = count
                    
                    # Read triangles efficiently using numpy
                    # 50 bytes per triangle: 12 floats (normal + 3 vertices) + 2 bytes attribute
                    dtype = np.dtype([
                        ('normal', np.float32, (3,)),
                        ('v1', np.float32, (3,)),
                        ('v2', np.float32, (3,)),
                        ('v3', np.float32, (3,)),
                        ('attr', np.uint16)
                    ])
                    
                    # Read data
                    data = np.fromfile(f, dtype=dtype, count=count)
                    
                    v1 = data['v1']
                    v2 = data['v2']
                    v3 = data['v3']
                    
                    # Calculate volume
                    # Cross product of v2 and v3
                    cross = np.cross(v2, v3)
                    # Dot product with v1
                    dots = np.sum(v1 * cross, axis=1)
                    total_vol = np.sum(dots) / 6.0
                    
                    # Convert cubic mm to mL (1 cm^3 = 1000 mm^3 = 1 mL)
                    # wait, 1 mL = 1 cm^3 = 1000 mm^3 is WRONG
                    # 1 mL = 1 cm^3 = 10 mm * 10 mm * 10 mm = 1000 mm^3
                    result["calculated_volume_ml"] = abs(total_vol) / 1000.0
                    
                    # Calculate bounding box
                    all_verts = np.concatenate((v1, v2, v3), axis=0)
                    min_coords = np.min(all_verts, axis=0)
                    max_coords = np.max(all_verts, axis=0)
                    dims = max_coords - min_coords
                    result["bounding_box_diag_mm"] = np.linalg.norm(dims)
                    result["bounding_box_dims"] = dims.tolist()

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/segment_intracranial_cavity_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="