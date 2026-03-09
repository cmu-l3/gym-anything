#!/bin/bash
echo "=== Exporting generate_hurricane_track_line result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_PATH="/home/ga/gvsig_data/exports/katrina_track.shp"
ANALYSIS_SCRIPT="/tmp/analyze_shapefile.py"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create Python analysis script to parse Shapefile binary (no external deps required)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import sys
import struct
import math
import json
import os

def read_shapefile(filepath):
    result = {
        "exists": False,
        "valid_header": False,
        "shape_type": 0,
        "feature_count": 0,
        "bbox": [0,0,0,0],
        "total_length": 0.0,
        "error": ""
    }
    
    if not os.path.exists(filepath):
        return result
    
    result["exists"] = True
    
    try:
        with open(filepath, "rb") as f:
            # --- READ HEADER (100 bytes) ---
            header = f.read(100)
            if len(header) < 100:
                result["error"] = "File too short"
                return result
                
            # File Code (Big Endian 9994)
            file_code = struct.unpack(">I", header[0:4])[0]
            if file_code != 9994:
                result["error"] = f"Invalid file code: {file_code}"
                return result
                
            result["valid_header"] = True
            
            # File Length (Big Endian, 16-bit words)
            file_length = struct.unpack(">I", header[24:28])[0] * 2
            
            # Shape Type (Little Endian)
            # 1=Point, 3=Polyline, 5=Polygon
            shape_type = struct.unpack("<i", header[32:36])[0]
            result["shape_type"] = shape_type
            
            # Bounding Box (Little Endian doubles)
            xmin, ymin, xmax, ymax = struct.unpack("<dddd", header[36:68])
            result["bbox"] = [xmin, ymin, xmax, ymax]
            
            # --- READ RECORDS ---
            f.seek(100)
            feature_count = 0
            total_dist = 0.0
            
            while f.tell() < file_length:
                # Record Header (8 bytes)
                rec_header = f.read(8)
                if len(rec_header) < 8: break
                
                rec_num, content_len = struct.unpack(">II", rec_header)
                # content_len is in 16-bit words
                bytes_to_read = content_len * 2
                
                # Read Content
                content = f.read(bytes_to_read)
                if len(content) < bytes_to_read: break
                
                feature_count += 1
                
                # Parse Polyline (Type 3)
                # int ShapeType, double Box[4], int NumParts, int NumPoints, int Parts[NumParts], Point Points[NumPoints]
                # 4 + 32 + 4 + 4 = 44 bytes minimum header
                if shape_type == 3 or shape_type == 23: # Polyline or PolylineZ
                    try:
                        rec_shape_type = struct.unpack("<i", content[0:4])[0]
                        num_parts = struct.unpack("<i", content[36:40])[0]
                        num_points = struct.unpack("<i", content[40:44])[0]
                        
                        # Points start after Parts array
                        # Parts is int[num_parts] -> 4 * num_parts bytes
                        points_start = 44 + (4 * num_parts)
                        
                        # Points are double[2] (x,y) -> 16 bytes per point
                        points_data = content[points_start : points_start + (16 * num_points)]
                        
                        points = []
                        for i in range(num_points):
                            offset = i * 16
                            px, py = struct.unpack("<dd", points_data[offset : offset+16])
                            points.append((px, py))
                            
                        # Calculate length of this feature
                        # Simple Euclidean sum for verification
                        feat_len = 0.0
                        for i in range(len(points) - 1):
                            x1, y1 = points[i]
                            x2, y2 = points[i+1]
                            feat_len += math.sqrt((x2-x1)**2 + (y2-y1)**2)
                        
                        total_dist += feat_len
                        
                    except Exception as e:
                        result["error"] = f"Error parsing feature {feature_count}: {str(e)}"
                        
            result["feature_count"] = feature_count
            result["total_length"] = total_dist
            
    except Exception as e:
        result["error"] = str(e)
        
    return result

# Run analysis
info = read_shapefile(sys.argv[1])
print(json.dumps(info))
PYEOF

# Run the analysis
ANALYSIS_JSON="{}"
if [ -f "$OUTPUT_PATH" ]; then
    ANALYSIS_JSON=$(python3 "$ANALYSIS_SCRIPT" "$OUTPUT_PATH")
fi

# Check timestamps
FILE_CREATED="false"
OUTPUT_SIZE=0
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created_during_task": $FILE_CREATED,
    "file_size": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="