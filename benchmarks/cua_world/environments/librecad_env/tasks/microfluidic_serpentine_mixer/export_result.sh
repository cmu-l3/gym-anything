#!/bin/bash
echo "=== Exporting Microfluidic Mixer Result ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/LibreCAD/microfluidic_chip.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Basic File Checks
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# DXF Analysis using Python (running inside container where ezdxf is installed)
# We embed a python script to parse the DXF and output a JSON summary
DXF_ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running internal DXF analysis..."
    DXF_ANALYSIS=$(python3 -c "
import sys
import json
try:
    import ezdxf
    doc = ezdxf.readfile('$OUTPUT_FILE')
    msp = doc.modelspace()
    
    # Analyze Layers
    layers = [layer.dxf.name for layer in doc.layers]
    
    # Analyze Substrate
    substrate_ents = msp.query('LINE LWPOLYLINE[layer==\"SUBSTRATE\"]')
    substrate_count = len(substrate_ents)
    
    # Analyze Reservoirs
    reservoirs = msp.query('CIRCLE[layer==\"RESERVOIRS\"]')
    res_data = []
    for r in reservoirs:
        res_data.append({
            'center': list(r.dxf.center)[:2],
            'radius': r.dxf.radius
        })
        
    # Analyze Channel (check for arcs/fillets)
    channel_ents = msp.query('*[layer==\"CHANNEL\"]')
    arc_count = len(msp.query('ARC[layer==\"CHANNEL\"]'))
    # Also check polyline bulges if they used polylines for fillets
    polyline_bulges = 0
    for pl in msp.query('LWPOLYLINE[layer==\"CHANNEL\"]'):
        if any(b != 0 for b in pl.get_points(format='b')):
            polyline_bulges += 1
            
    result = {
        'valid_dxf': True,
        'layers': layers,
        'substrate_entity_count': substrate_count,
        'reservoir_count': len(reservoirs),
        'reservoir_data': res_data,
        'channel_entity_count': len(channel_ents),
        'channel_arc_count': arc_count,
        'channel_polyline_bulges': polyline_bulges
    }
except ImportError:
    result = {'valid_dxf': False, 'error': 'ezdxf_not_installed'}
except Exception as e:
    result = {'valid_dxf': False, 'error': str(e)}

print(json.dumps(result))
" 2>/dev/null || echo "{\"valid_dxf\": false, \"error\": \"script_failed\"}")
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="