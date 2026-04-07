#!/bin/bash
echo "=== Exporting Residential Floor Plan Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output file status
OUTPUT_PATH="/home/ga/Documents/LibreCAD/apartment_plan.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run DXF analysis inside the container using ezdxf
DXF_ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    cat > /tmp/analyze_floor_plan.py << 'PYEOF'
#!/usr/bin/env python3
"""Analyze the apartment floor plan DXF for verification."""
import json
import sys
import math

try:
    import ezdxf
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf", "-q"])
    import ezdxf

def analyze(dxf_path):
    result = {
        "valid_dxf": False,
        "layers": {},
        "entity_counts_by_layer": {},
        "entity_types_by_layer": {},
        "total_entities": 0,
        "walls_line_count": 0,
        "doors_arc_count": 0,
        "windows_line_count": 0,
        "fixtures_entity_count": 0,
        "dimension_count": 0,
        "text_contents": [],
        "bbox": None,
        "walls_bbox": None
    }

    try:
        doc = ezdxf.readfile(dxf_path)
        result["valid_dxf"] = True
    except Exception as e:
        result["error"] = str(e)
        return result

    msp = doc.modelspace()

    # Collect layer info
    for layer in doc.layers:
        name = layer.dxf.name
        result["layers"][name] = {
            "color": layer.color,
            "linetype": layer.dxf.linetype if hasattr(layer.dxf, 'linetype') else "Continuous"
        }

    # Analyze entities
    min_x, min_y = float('inf'), float('inf')
    max_x, max_y = float('-inf'), float('-inf')
    w_min_x, w_min_y = float('inf'), float('inf')
    w_max_x, w_max_y = float('-inf'), float('-inf')
    has_walls_geom = False

    for entity in msp:
        layer_name = entity.dxf.layer
        etype = entity.dxftype()

        # Count by layer
        if layer_name not in result["entity_counts_by_layer"]:
            result["entity_counts_by_layer"][layer_name] = 0
            result["entity_types_by_layer"][layer_name] = {}
        result["entity_counts_by_layer"][layer_name] += 1
        result["entity_types_by_layer"][layer_name][etype] = \
            result["entity_types_by_layer"][layer_name].get(etype, 0) + 1
        result["total_entities"] += 1

        # Layer-specific counts
        if layer_name == "WALLS" and etype == "LINE":
            result["walls_line_count"] += 1
        elif layer_name == "DOORS" and etype == "ARC":
            result["doors_arc_count"] += 1
        elif layer_name == "WINDOWS" and etype == "LINE":
            result["windows_line_count"] += 1
        elif layer_name == "FIXTURES":
            result["fixtures_entity_count"] += 1
        elif etype in ("DIMENSION", "ALIGNED_DIMENSION", "LINEAR_DIMENSION",
                       "ANGULAR_DIMENSION", "RADIAL_DIMENSION",
                       "DIAMETRIC_DIMENSION", "ORDINATE_DIMENSION"):
            result["dimension_count"] += 1

        # Collect text content
        if etype in ("TEXT", "MTEXT"):
            try:
                text_val = entity.dxf.text if etype == "TEXT" else entity.text
                if text_val:
                    result["text_contents"].append({
                        "text": text_val.strip(),
                        "layer": layer_name,
                        "type": etype
                    })
            except Exception:
                pass

        # Update bounding box from LINE entities
        if etype == "LINE":
            try:
                sx, sy = entity.dxf.start.x, entity.dxf.start.y
                ex, ey = entity.dxf.end.x, entity.dxf.end.y
                min_x = min(min_x, sx, ex)
                max_x = max(max_x, sx, ex)
                min_y = min(min_y, sy, ey)
                max_y = max(max_y, sy, ey)
                if layer_name == "WALLS":
                    w_min_x = min(w_min_x, sx, ex)
                    w_max_x = max(w_max_x, sx, ex)
                    w_min_y = min(w_min_y, sy, ey)
                    w_max_y = max(w_max_y, sy, ey)
                    has_walls_geom = True
            except Exception:
                pass

        # Update bbox from ARC and CIRCLE
        if etype == "CIRCLE":
            try:
                cx, cy = entity.dxf.center.x, entity.dxf.center.y
                r = entity.dxf.radius
                min_x = min(min_x, cx - r)
                max_x = max(max_x, cx + r)
                min_y = min(min_y, cy - r)
                max_y = max(max_y, cy + r)
            except Exception:
                pass

        if etype == "ARC":
            try:
                cx, cy = entity.dxf.center.x, entity.dxf.center.y
                r = entity.dxf.radius
                min_x = min(min_x, cx - r)
                max_x = max(max_x, cx + r)
                min_y = min(min_y, cy - r)
                max_y = max(max_y, cy + r)
            except Exception:
                pass

    if min_x != float('inf'):
        result["bbox"] = {
            "min_x": round(min_x, 2), "min_y": round(min_y, 2),
            "max_x": round(max_x, 2), "max_y": round(max_y, 2),
            "width": round(max_x - min_x, 2),
            "height": round(max_y - min_y, 2)
        }

    if has_walls_geom:
        result["walls_bbox"] = {
            "min_x": round(w_min_x, 2), "min_y": round(w_min_y, 2),
            "max_x": round(w_max_x, 2), "max_y": round(w_max_y, 2),
            "width": round(w_max_x - w_min_x, 2),
            "height": round(w_max_y - w_min_y, 2)
        }

    return result

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    if path:
        data = analyze(path)
    else:
        data = {"error": "No path provided"}
    print(json.dumps(data))
PYEOF

    DXF_ANALYSIS=$(python3 /tmp/analyze_floor_plan.py "$OUTPUT_PATH" 2>/dev/null || echo '{"error": "analysis script failed"}')
    rm -f /tmp/analyze_floor_plan.py
fi

# 4. Check if app was running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis": $DXF_ANALYSIS
}
EOF

# 6. Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
