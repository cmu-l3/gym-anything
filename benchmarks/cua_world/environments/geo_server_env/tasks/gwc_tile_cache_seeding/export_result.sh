#!/bin/bash
# Export script for gwc_tile_cache_seeding task

echo "=== Exporting gwc_tile_cache_seeding Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/gwc_tile_cache_seeding_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_NONCE=$(get_result_nonce)
GUI_INTERACTION=$(check_gui_interaction)

# Base URL for GWC REST API
GWC_REST="http://localhost:8080/geoserver/gwc/rest"
GS_AUTH="admin:Admin123!"

# ----- Fetch GWC tile layer configuration -----
GWC_LAYER_JSON=$(curl -s -u "$GS_AUTH" \
    "${GWC_REST}/layers/ne:ne_countries.json" 2>/dev/null || echo "")

GWC_ANALYSIS=$(echo "$GWC_LAYER_JSON" | python3 << 'PYEOF'
import sys, json

content = sys.stdin.read().strip()
if not content:
    print("gwc_found=false")
    print("has_epsg4326=false")
    print("has_epsg900913=false")
    print("has_png=false")
    print("metatile_x=1")
    print("metatile_y=1")
    exit()

try:
    d = json.loads(content)
except:
    print("gwc_found=false")
    exit()

# Check for layer configuration
# GWC JSON can be either flat or nested under "GeoServerTileLayer" or "wmsLayer"
layer = d.get('GeoServerTileLayer') or d.get('wmsLayer') or d

if not layer:
    print("gwc_found=false")
    exit()

print("gwc_found=true")

# Check gridSubsets (gridsets)
grid_subsets = layer.get('gridSubsets') or []
gridset_names = []
if isinstance(grid_subsets, list):
    for gs in grid_subsets:
        if isinstance(gs, dict):
            name = gs.get('gridSetName') or gs.get('name') or ''
            if name:
                gridset_names.append(name)
        elif isinstance(gs, str):
            gridset_names.append(gs)
elif isinstance(grid_subsets, dict):
    # Sometimes wrapped: {"gridSubset": [...]}
    inner = grid_subsets.get('gridSubset', [])
    if isinstance(inner, list):
        for gs in inner:
            if isinstance(gs, dict):
                name = gs.get('gridSetName') or gs.get('name') or ''
                if name:
                    gridset_names.append(name)
    elif isinstance(inner, str):
        gridset_names.append(inner)

print(f"has_epsg4326={'true' if 'EPSG:4326' in gridset_names else 'false'}")
print(f"has_epsg900913={'true' if any('900913' in n or '3857' in n for n in gridset_names) else 'false'}")
print(f"gridsets={'|'.join(gridset_names)}")

# Check mime formats
mime_formats = layer.get('mimeFormats') or layer.get('mimeFormats') or []
format_list = []
if isinstance(mime_formats, list):
    format_list = mime_formats
elif isinstance(mime_formats, dict):
    inner = mime_formats.get('string', [])
    if isinstance(inner, list):
        format_list = inner
    elif inner:
        format_list = [inner]

has_png = any('png' in f.lower() for f in format_list)
print(f"has_png={'true' if has_png else 'false'}")
print(f"formats={'|'.join(format_list)}")

# Check metatile
meta_width = layer.get('metaWidthHeight') or layer.get('metaTilingX') or 1
meta_height = layer.get('metaWidthHeight') or layer.get('metaTilingY') or 1
if isinstance(meta_width, list):
    meta_val = meta_width[0] if meta_width else 1
    print(f"metatile_x={meta_val}")
    print(f"metatile_y={meta_width[1] if len(meta_width) > 1 else meta_val}")
else:
    print(f"metatile_x={meta_width}")
    print(f"metatile_y={meta_height}")
PYEOF
)

GWC_FOUND=$(echo "$GWC_ANALYSIS" | grep '^gwc_found=' | cut -d= -f2)
HAS_EPSG4326=$(echo "$GWC_ANALYSIS" | grep '^has_epsg4326=' | cut -d= -f2)
HAS_EPSG900913=$(echo "$GWC_ANALYSIS" | grep '^has_epsg900913=' | cut -d= -f2)
HAS_PNG=$(echo "$GWC_ANALYSIS" | grep '^has_png=' | cut -d= -f2)
GRIDSETS=$(echo "$GWC_ANALYSIS" | grep '^gridsets=' | cut -d= -f2)
FORMATS=$(echo "$GWC_ANALYSIS" | grep '^formats=' | cut -d= -f2)
METATILE_X=$(echo "$GWC_ANALYSIS" | grep '^metatile_x=' | cut -d= -f2)
METATILE_Y=$(echo "$GWC_ANALYSIS" | grep '^metatile_y=' | cut -d= -f2)

# ----- Check seed status -----
SEED_JSON=$(curl -s -u "$GS_AUTH" \
    "${GWC_REST}/seed/ne:ne_countries.json" 2>/dev/null || echo "")

SEED_STATUS=$(echo "$SEED_JSON" | python3 << 'PYEOF'
import sys, json

content = sys.stdin.read().strip()
if not content or content.startswith('Error') or '{' not in content:
    print("seed_triggered=false")
    print("seed_status=unknown")
    exit()

try:
    d = json.loads(content)
except:
    print("seed_triggered=false")
    print("seed_status=parse_error")
    exit()

# GWC seed status response: {"long-array-array": [[tiles_processed, tiles_total, estimated_time, task_id, status]]}
arr = d.get('long-array-array', [])
if not arr:
    print("seed_triggered=false")
    print("seed_status=no_tasks")
    exit()

print("seed_triggered=true")
# Status codes: -1=abort, 0=pending, 1=running, 2=done
tasks = []
for row in arr:
    if isinstance(row, list) and len(row) >= 5:
        tiles_proc = row[0]
        tiles_total = row[1]
        status = row[4]
        status_str = {-1: 'aborted', 0: 'pending', 1: 'running', 2: 'done'}.get(status, f'status_{status}')
        tasks.append(f"{status_str}:{tiles_proc}/{tiles_total}")

print(f"seed_status={'|'.join(tasks) if tasks else 'found_but_empty'}")
PYEOF
)

SEED_TRIGGERED=$(echo "$SEED_STATUS" | grep '^seed_triggered=' | cut -d= -f2)
SEED_TASK_STATUS=$(echo "$SEED_STATUS" | grep '^seed_status=' | cut -d= -f2)

# Also check for seed activity in GeoServer access log (POST to /geoserver/gwc/rest/seed)
SEED_LOG_CHECK=$(check_gui_interaction 2>/dev/null || echo "false")
# Additionally look for GWC seed API calls directly
LOG_FILE=$(cat /tmp/access_log_file 2>/dev/null || echo "")
SNAPSHOT_COUNT=$(cat /tmp/access_log_snapshot 2>/dev/null || echo "0")
if [ -n "$LOG_FILE" ]; then
    NEW_ENTRIES=$(docker exec gs-app tail -n +$((SNAPSHOT_COUNT + 1)) "$LOG_FILE" 2>/dev/null || echo "")
    SEED_API_CALL=$(echo "$NEW_ENTRIES" | grep -c '"POST.*/gwc/' 2>/dev/null; echo "" | head -1)
    [ -z "$SEED_API_CALL" ] && SEED_API_CALL=0
else
    SEED_API_CALL=0
fi

TMPFILE=$(mktemp /tmp/gwc_tile_cache_seeding_result_XXXXXX.json)
python3 << PYEOF
import json

result = {
    "result_nonce": "${RESULT_NONCE}",
    "task_start": ${TASK_START},
    "gui_interaction_detected": $([ "$GUI_INTERACTION" = "true" ] && echo "True" || echo "False"),

    "gwc_found": $([ "$GWC_FOUND" = "true" ] && echo "True" || echo "False"),
    "has_epsg4326": $([ "$HAS_EPSG4326" = "true" ] && echo "True" || echo "False"),
    "has_epsg900913": $([ "$HAS_EPSG900913" = "true" ] && echo "True" || echo "False"),
    "has_png": $([ "$HAS_PNG" = "true" ] && echo "True" || echo "False"),
    "gridsets": "${GRIDSETS}",
    "formats": "${FORMATS}",
    "metatile_x": ${METATILE_X:-1},
    "metatile_y": ${METATILE_Y:-1},

    "seed_triggered": $([ "$SEED_TRIGGERED" = "true" ] && echo "True" || echo "False"),
    "seed_task_status": "${SEED_TASK_STATUS}",
    "seed_api_calls": ${SEED_API_CALL:-0}
}

with open("${TMPFILE}", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

safe_write_result "$TMPFILE" "/tmp/gwc_tile_cache_seeding_result.json"

echo "=== Export Complete ==="
