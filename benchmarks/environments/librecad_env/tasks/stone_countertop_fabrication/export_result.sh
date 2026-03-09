#!/bin/bash
echo "=== Exporting Stone Countertop Result ==="

# Define paths
OUTPUT_DXF="/home/ga/Documents/LibreCAD/countertop.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_DXF" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_DXF")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_DXF")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze DXF content using Python (running inside container where ezdxf is installed)
# We create a temporary python script to perform the analysis
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
import math

def analyze_dxf(file_path):
    result = {
        "valid_dxf": False,
        "layers": {},
        "stone_geometry": {"valid_bbox": False, "has_fillet": False},
        "cutouts": {"sink_found": False, "cooktop_found": False, "count": 0}
    }

    try:
        doc = ezdxf.readfile(file_path)
        result["valid_dxf"] = True
    except Exception as e:
        result["error"] = str(e)
        return result

    msp = doc.modelspace()

    # Check Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name] = layer.dxf.color

    # Analyze STONE layer
    stone_entities = msp.query('OnLayer("STONE")')
    if len(stone_entities) > 0:
        # Check bounding box
        bbox = ezdxf.bbox.extents(stone_entities)
        # Expected: roughly (0,0) to (3000, 2400)
        # Allow some tolerance
        if (abs(bbox.extmin.x) < 10 and abs(bbox.extmin.y) < 10 and 
            abs(bbox.extmax.x - 3000) < 50 and abs(bbox.extmax.y - 2400) < 50):
            result["stone_geometry"]["valid_bbox"] = True
        
        # Check Fillet (Arc near 600,600 with radius 50)
        # Iterate Arcs
        for e in stone_entities:
            if e.dxftype() == 'ARC':
                center = e.dxf.center
                radius = e.dxf.radius
                if (abs(center.x - 600) < 5 and abs(center.y - 600) < 5 and abs(radius - 50) < 2):
                    result["stone_geometry"]["has_fillet"] = True
            # Also check Polylines for bulge (advanced, but basic check is ARC usually created by Fillet tool)
            # If LibreCAD fillet tool explodes or trims, it often leaves an ARC.

    # Analyze CUTOUTS layer
    cutout_entities = msp.query('OnLayer("CUTOUTS")')
    result["cutouts"]["count"] = len(cutout_entities)
    
    # Simple centroid/bbox check for cutouts
    # We look for entities that roughly match the sink and cooktop locations
    
    sink_found = False
    cooktop_found = False
    
    # Helper to check if entity is roughly at location
    for e in cutout_entities:
        try:
            # Get bounding box of individual entity
            ebbox = ezdxf.bbox.extents([e])
            center_x = (ebbox.extmin.x + ebbox.extmax.x) / 2
            center_y = (ebbox.extmin.y + ebbox.extmax.y) / 2
            width = ebbox.extmax.x - ebbox.extmin.x
            height = ebbox.extmax.y - ebbox.extmin.y
            
            # Check Sink (1500, 300) 800x450
            if (abs(center_x - 1500) < 20 and abs(center_y - 300) < 20 and
                abs(width - 800) < 20 and abs(height - 450) < 20):
                sink_found = True
                
            # Check Cooktop (300, 1500) 500x500
            if (abs(center_x - 300) < 20 and abs(center_y - 1500) < 20 and
                abs(width - 500) < 20 and abs(height - 500) < 20):
                cooktop_found = True
        except:
            continue
            
    result["cutouts"]["sink_found"] = sink_found
    result["cutouts"]["cooktop_found"] = cooktop_found

    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file provided"}))
        sys.exit(1)
        
    analysis = analyze_dxf(sys.argv[1])
    print(json.dumps(analysis))
EOF

# Run the analysis
DXF_ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_DXF")
fi

# 4. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="