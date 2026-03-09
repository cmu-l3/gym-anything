#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FCSTD_PATH="/home/ga/Documents/FreeCAD/parametric_bracket.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$FCSTD_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FCSTD_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FCSTD_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Run Headless FreeCAD Inspection Script
# We run this INSIDE the container to leverage the FreeCAD python API
# The result is written to a temporary JSON file

INSPECTION_JSON="{}"

if [ "$FILE_EXISTS" = "true" ]; then
    cat > /tmp/inspect_parametric.py << 'PYEOF'
import sys
import json
import FreeCAD

results = {
    "has_spreadsheet": False,
    "aliases_found": [],
    "alias_values": {},
    "has_body": False,
    "has_pad": False,
    "expression_count": 0,
    "bbox": None,
    "inspection_error": None
}

try:
    doc = FreeCAD.openDocument(sys.argv[1])
    
    # Check for Spreadsheet
    for obj in doc.Objects:
        if obj.TypeId == "Spreadsheet::Sheet":
            results["has_spreadsheet"] = True
            
            # Check aliases
            for alias_name in ["base_length", "base_width", "upright_height", "thickness"]:
                try:
                    val = obj.get(alias_name)
                    if val is not None:
                        results["aliases_found"].append(alias_name)
                        results["alias_values"][alias_name] = float(val)
                except Exception:
                    pass
            
            # Fallback: check cells if aliases aren't directly retrievable by name
            if not results["aliases_found"]:
                # Simple scan of top-left area
                for c in ["A", "B"]:
                    for r in range(1, 10):
                        try:
                            alias = obj.getAlias(f"{c}{r}")
                            if alias in ["base_length", "base_width", "upright_height", "thickness"]:
                                if alias not in results["aliases_found"]:
                                    results["aliases_found"].append(alias)
                                    val = obj.get(f"{c}{r}")
                                    results["alias_values"][alias] = float(val) if val is not None else 0.0
                        except:
                            pass

    # Check for Body and Pad
    for obj in doc.Objects:
        type_id = getattr(obj, "TypeId", "")
        if "PartDesign::Body" in type_id:
            results["has_body"] = True
        if "PartDesign::Pad" in type_id:
            results["has_pad"] = True
            
    # Check for Expressions
    for obj in doc.Objects:
        try:
            exprs = obj.ExpressionEngine
            if exprs:
                for prop, expr in exprs:
                    if "Spreadsheet" in expr or "spreadsheet" in expr.lower():
                        results["expression_count"] += 1
        except:
            pass

    # Check Bounding Box (of the final shape)
    # We look for the Body's shape
    for obj in doc.Objects:
        if "PartDesign::Body" in getattr(obj, "TypeId", ""):
            if hasattr(obj, "Shape") and obj.Shape.isValid():
                bb = obj.Shape.BoundBox
                # Only record if it has volume
                if bb.XLength > 0 and bb.YLength > 0:
                    results["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]

except Exception as e:
    results["inspection_error"] = str(e)

print(json.dumps(results))
PYEOF

    # Run the script using freecadcmd
    # Note: freecadcmd might print startup banners, so we grep for the JSON line
    RAW_OUTPUT=$(freecadcmd /tmp/inspect_parametric.py "$FCSTD_PATH" 2>/dev/null)
    INSPECTION_JSON=$(echo "$RAW_OUTPUT" | grep "^{.*}" | tail -n 1 || echo "{}")
fi

# 3. Combine everything into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "inspection": $INSPECTION_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="