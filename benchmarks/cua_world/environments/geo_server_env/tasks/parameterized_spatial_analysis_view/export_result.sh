#!/bin/bash
# Export script for parameterized_spatial_analysis_view task

echo "=== Exporting parameterized_spatial_analysis_view Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/parameterized_spatial_analysis_view_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_WORKSPACE_COUNT=$(cat /tmp/initial_workspace_count 2>/dev/null || echo "0")
INITIAL_LAYER_COUNT=$(cat /tmp/initial_layer_count 2>/dev/null || echo "0")
INITIAL_STYLE_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
RESULT_NONCE=$(get_result_nonce)
GUI_INTERACTION=$(check_gui_interaction)

# ----- Check workspace -----
WS_JSON=$(gs_rest_get "workspaces/spatial_analytics.json" 2>/dev/null || echo "")
WS_FOUND=false
WS_NAME=""
WS_NAMESPACE=""
if echo "$WS_JSON" | grep -q '"name"'; then
    WS_FOUND=true
    WS_NAME=$(echo "$WS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('workspace',{}).get('name',''))" 2>/dev/null || echo "")
fi

# Get namespace URI
NS_JSON=$(gs_rest_get "namespaces/spatial_analytics.json" 2>/dev/null || echo "")
if echo "$NS_JSON" | grep -q '"uri"'; then
    WS_NAMESPACE=$(echo "$NS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('namespace',{}).get('uri',''))" 2>/dev/null || echo "")
fi

# ----- Check datastore -----
DS_FOUND=false
DS_NAME=""
DS_IS_POSTGIS=false

DS_JSON=$(gs_rest_get "workspaces/spatial_analytics/datastores.json" 2>/dev/null || echo "")
DS_COUNT=$(echo "$DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
print(len(stores))
" 2>/dev/null || echo "0")

if [ "$DS_COUNT" != "0" ]; then
    DS_FOUND=true
    DS_NAME=$(echo "$DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
for s in stores:
    print(s.get('name',''))
    break
" 2>/dev/null || echo "")
fi

# Check if datastore is PostGIS type
if [ "$DS_FOUND" = "true" ] && [ -n "$DS_NAME" ]; then
    DS_DETAIL=$(gs_rest_get "workspaces/spatial_analytics/datastores/${DS_NAME}.json" 2>/dev/null || echo "")
    if echo "$DS_DETAIL" | grep -qi "postgis\|PostGIS"; then
        DS_IS_POSTGIS=true
    fi
fi

# ----- Check layer continental_city_stats -----
LAYER_FOUND=false
LAYER_NAME=""
LAYER_SRS=""
HAS_SQL_VIEW=false
SQL_HAS_ST_CONTAINS=false
SQL_HAS_GROUP_BY=false
SQL_HAS_LEFT_JOIN=false
HAS_PARAM=false
PARAM_NAME=""
PARAM_DEFAULT=""
GEOM_TYPE=""
GEOM_SRID=""
ATTR_NAMES=""

# Search in all datastores of spatial_analytics workspace
if [ "$DS_FOUND" = "true" ] && [ -n "$DS_NAME" ]; then
    FT_ANALYSIS=$(python3 -c '
import subprocess, json, sys
ds = sys.argv[1]
r = subprocess.run(["curl", "-s", "-u", "admin:Admin123!", "-H", "Accept: application/json",
    "http://localhost:8080/geoserver/rest/workspaces/spatial_analytics/datastores/" + ds + "/featuretypes/continental_city_stats.json"],
    capture_output=True, text=True)
try:
    d = json.loads(r.stdout)
except: sys.exit()
ft = d.get("featureType", {})
print("srs=" + ft.get("srs", ""))
metadata = ft.get("metadata", {})
entries = metadata.get("entry", [])
if not isinstance(entries, list):
    entries = [entries] if entries else []
sql_text = ""
for entry in entries:
    if isinstance(entry, dict) and entry.get("@key") == "JDBC_VIRTUAL_TABLE":
        vt = entry.get("virtualTable", {})
        sql_text = vt.get("sql", "")
        g = vt.get("geometry", {})
        print("geom_type=" + str(g.get("type", "")))
        print("geom_srid=" + str(g.get("srid", "")))
        params = vt.get("parameter", [])
        if not isinstance(params, list):
            params = [params] if params else []
        for p in params:
            print("param_name=" + p.get("name", ""))
            print("param_default=" + p.get("defaultValue", ""))
        print("has_sql_view=True")
        break
else:
    print("has_sql_view=False")
print("sql_has_st_contains=" + ("true" if "st_contains" in sql_text.lower() else "false"))
print("sql_has_group_by=" + ("true" if "group by" in sql_text.lower() else "false"))
print("sql_has_left_join=" + ("true" if "left join" in sql_text.lower() or "left outer join" in sql_text.lower() else "false"))
attrs = ft.get("attributes", {}).get("attribute", [])
if not isinstance(attrs, list):
    attrs = [attrs] if attrs else []
print("attr_names=" + "|".join([a.get("name","") for a in attrs]))
' "$DS_NAME" 2>/dev/null)
    if echo "$FT_ANALYSIS" | grep -q 'srs='; then
        LAYER_FOUND=true
        LAYER_NAME="continental_city_stats"
        LAYER_SRS=$(echo "$FT_ANALYSIS" | grep '^srs=' | cut -d= -f2)
        HAS_SQL_VIEW_VAL=$(echo "$FT_ANALYSIS" | grep '^has_sql_view=' | cut -d= -f2)
        [ "$HAS_SQL_VIEW_VAL" = "True" ] && HAS_SQL_VIEW=true
        SQL_HAS_ST_CONTAINS_VAL=$(echo "$FT_ANALYSIS" | grep '^sql_has_st_contains=' | cut -d= -f2)
        [ "$SQL_HAS_ST_CONTAINS_VAL" = "true" ] && SQL_HAS_ST_CONTAINS=true
        SQL_HAS_GROUP_BY_VAL=$(echo "$FT_ANALYSIS" | grep '^sql_has_group_by=' | cut -d= -f2)
        [ "$SQL_HAS_GROUP_BY_VAL" = "true" ] && SQL_HAS_GROUP_BY=true
        SQL_HAS_LEFT_JOIN_VAL=$(echo "$FT_ANALYSIS" | grep '^sql_has_left_join=' | cut -d= -f2)
        [ "$SQL_HAS_LEFT_JOIN_VAL" = "true" ] && SQL_HAS_LEFT_JOIN=true
        GEOM_TYPE=$(echo "$FT_ANALYSIS" | grep '^geom_type=' | cut -d= -f2)
        GEOM_SRID=$(echo "$FT_ANALYSIS" | grep '^geom_srid=' | cut -d= -f2)
        PARAM_NAME=$(echo "$FT_ANALYSIS" | grep '^param_name=' | head -1 | cut -d= -f2)
        PARAM_DEFAULT=$(echo "$FT_ANALYSIS" | grep '^param_default=' | head -1 | cut -d= -f2)
        ATTR_NAMES=$(echo "$FT_ANALYSIS" | grep '^attr_names=' | cut -d= -f2)
        [ -n "$PARAM_NAME" ] && HAS_PARAM=true
    fi
fi

# Fallback: try direct featuretype endpoint
if [ "$LAYER_FOUND" = "false" ]; then
    FT_DIRECT=$(gs_rest_get "workspaces/spatial_analytics/featuretypes/continental_city_stats.json" 2>/dev/null || echo "")
    if echo "$FT_DIRECT" | grep -q '"name"'; then
        LAYER_FOUND=true
        LAYER_NAME="continental_city_stats"
    fi
fi

# ----- Check default style for the layer -----
DEFAULT_STYLE=""
DEFAULT_STYLE_MATCH=false
if [ "$LAYER_FOUND" = "true" ]; then
    LYR_JSON=$(gs_rest_get "layers/spatial_analytics:continental_city_stats.json" 2>/dev/null || echo "")
    DEFAULT_STYLE=$(echo "$LYR_JSON" | python3 -c "
import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))
" 2>/dev/null || echo "")
    if echo "$DEFAULT_STYLE" | grep -qi "urban_density_gradient"; then
        DEFAULT_STYLE_MATCH=true
    fi
fi

# ----- Check SLD style urban_density_gradient -----
SLD_FOUND=false
SLD_HAS_CITY_COUNT=false
SLD_RULE_COUNT=0
SLD_DISTINCT_COLORS=0
SLD_HAS_CORRECT_COLORS=false
SLD_HAS_STROKE=false
SLD_COLORS=""

for SCOPE in "workspaces/spatial_analytics/styles" "styles"; do
    SLD_STATUS=$(gs_rest_status "${SCOPE}/urban_density_gradient.json" 2>/dev/null || echo "404")
    if [ "$SLD_STATUS" = "200" ]; then
        SLD_FOUND=true
        SLD_ANALYSIS=$(python3 -c '
import subprocess, re, sys
scope = sys.argv[1]
r = subprocess.run(["curl", "-s", "-u", "admin:Admin123!", "-H", "Accept: application/xml",
    "http://localhost:8080/geoserver/rest/" + scope + "/urban_density_gradient.sld"],
    capture_output=True, text=True)
content = r.stdout
if not content: sys.exit()
rule_count = len(re.findall(r"<(?:sld:)?Rule\b", content, re.IGNORECASE))
has_city_count = bool(re.search(r"city_count", content, re.IGNORECASE))
fill_colors = set()
for m in re.finditer(r"<(?:sld:)?CssParameter\s+name=[\"'"'"'\"]fill[\"'"'"'\"][^>]*>\s*(#[0-9A-Fa-f]{6})\s*</(?:sld:)?CssParameter>", content):
    fill_colors.add(m.group(1).upper())
expected = {"#D3D3D3", "#AEC7E8", "#2CA02C", "#FF7F0E", "#D62728"}
matched = expected.intersection(fill_colors)
has_correct = len(matched) >= 4
has_stroke = bool(re.search(r"#333333", content, re.IGNORECASE))
print("rules=" + str(rule_count))
print("has_city_count=" + ("true" if has_city_count else "false"))
print("distinct_colors=" + str(len(fill_colors)))
print("colors=" + "|".join(sorted(fill_colors)))
print("has_correct_colors=" + ("true" if has_correct else "false"))
print("has_stroke=" + ("true" if has_stroke else "false"))
' "$SCOPE" 2>/dev/null)
        if [ -n "$SLD_ANALYSIS" ]; then
            SLD_RULE_COUNT=$(echo "$SLD_ANALYSIS" | grep '^rules=' | cut -d= -f2)
            SLD_HAS_CITY_COUNT_VAL=$(echo "$SLD_ANALYSIS" | grep '^has_city_count=' | cut -d= -f2)
            [ "$SLD_HAS_CITY_COUNT_VAL" = "true" ] && SLD_HAS_CITY_COUNT=true
            SLD_DISTINCT_COLORS=$(echo "$SLD_ANALYSIS" | grep '^distinct_colors=' | cut -d= -f2)
            SLD_COLORS=$(echo "$SLD_ANALYSIS" | grep '^colors=' | cut -d= -f2)
            SLD_HAS_CORRECT_COLORS_VAL=$(echo "$SLD_ANALYSIS" | grep '^has_correct_colors=' | cut -d= -f2)
            [ "$SLD_HAS_CORRECT_COLORS_VAL" = "true" ] && SLD_HAS_CORRECT_COLORS=true
            SLD_HAS_STROKE_VAL=$(echo "$SLD_ANALYSIS" | grep '^has_stroke=' | cut -d= -f2)
            [ "$SLD_HAS_STROKE_VAL" = "true" ] && SLD_HAS_STROKE=true
        fi
        break
    fi
done

# ----- Check output files -----
EUROPE_IMG_EXISTS=false
EUROPE_IMG_SIZE=0
EUROPE_IMG_VALID=false
ASIA_IMG_EXISTS=false
ASIA_IMG_SIZE=0
ASIA_IMG_VALID=false

if [ -f "/home/ga/output/europe_density.png" ]; then
    EUROPE_IMG_EXISTS=true
    EUROPE_IMG_SIZE=$(stat -c %s "/home/ga/output/europe_density.png" 2>/dev/null || echo "0")
    # Check it's a valid image, not an XML error
    if ! grep -q "ServiceException" "/home/ga/output/europe_density.png" 2>/dev/null && \
       ! grep -q "<?xml" "/home/ga/output/europe_density.png" 2>/dev/null; then
        if [ "$EUROPE_IMG_SIZE" -gt 1000 ]; then
            EUROPE_IMG_VALID=true
        fi
    fi
fi

if [ -f "/home/ga/output/asia_density.png" ]; then
    ASIA_IMG_EXISTS=true
    ASIA_IMG_SIZE=$(stat -c %s "/home/ga/output/asia_density.png" 2>/dev/null || echo "0")
    if ! grep -q "ServiceException" "/home/ga/output/asia_density.png" 2>/dev/null && \
       ! grep -q "<?xml" "/home/ga/output/asia_density.png" 2>/dev/null; then
        if [ "$ASIA_IMG_SIZE" -gt 1000 ]; then
            ASIA_IMG_VALID=true
        fi
    fi
fi

# ----- Try WMS GetMap to verify layer works -----
WMS_TEST_SUCCESS=false
WMS_TEST_OUTPUT="/tmp/wms_test_psav_output.png"
rm -f "$WMS_TEST_OUTPUT"
HTTP_CODE=$(curl -s -o "$WMS_TEST_OUTPUT" -w "%{http_code}" \
    "http://localhost:8080/geoserver/spatial_analytics/wms?service=WMS&version=1.1.1&request=GetMap&layers=spatial_analytics:continental_city_stats&styles=&bbox=-180,-90,180,90&width=100&height=50&srs=EPSG:4326&format=image/png&viewparams=target_continent:Europe" \
    2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] && [ -f "$WMS_TEST_OUTPUT" ]; then
    if ! grep -q "ServiceException" "$WMS_TEST_OUTPUT" 2>/dev/null; then
        WMS_TEST_SUCCESS=true
    fi
fi

# ----- Count current entities -----
CURRENT_WORKSPACE_COUNT=$(get_workspace_count)
CURRENT_LAYER_COUNT=$(get_layer_count)
CURRENT_STYLE_COUNT=$(get_style_count)

# ----- Write result JSON -----
TMPFILE="/tmp/parameterized_spatial_analysis_view_result_$$.json"
python3 << PYEOF
import json

result = {
    "result_nonce": "${RESULT_NONCE}",
    "task_start": ${TASK_START},
    "gui_interaction_detected": $([ "$GUI_INTERACTION" = "true" ] && echo "True" || echo "False"),

    "workspace_found": $([ "$WS_FOUND" = "true" ] && echo "True" || echo "False"),
    "workspace_name": "${WS_NAME}",
    "workspace_namespace": "${WS_NAMESPACE}",

    "datastore_found": $([ "$DS_FOUND" = "true" ] && echo "True" || echo "False"),
    "datastore_name": "${DS_NAME}",
    "datastore_is_postgis": $([ "$DS_IS_POSTGIS" = "true" ] && echo "True" || echo "False"),

    "layer_found": $([ "$LAYER_FOUND" = "true" ] && echo "True" || echo "False"),
    "layer_name": "${LAYER_NAME}",
    "layer_srs": "${LAYER_SRS}",

    "has_sql_view": $([ "$HAS_SQL_VIEW" = "true" ] && echo "True" || echo "False"),
    "sql_has_st_contains": $([ "$SQL_HAS_ST_CONTAINS" = "true" ] && echo "True" || echo "False"),
    "sql_has_group_by": $([ "$SQL_HAS_GROUP_BY" = "true" ] && echo "True" || echo "False"),
    "sql_has_left_join": $([ "$SQL_HAS_LEFT_JOIN" = "true" ] && echo "True" || echo "False"),

    "has_parameter": $([ "$HAS_PARAM" = "true" ] && echo "True" || echo "False"),
    "param_name": "${PARAM_NAME}",
    "param_default": "${PARAM_DEFAULT}",

    "geom_type": "${GEOM_TYPE}",
    "geom_srid": "${GEOM_SRID}",
    "attr_names": "${ATTR_NAMES}",

    "default_style": "${DEFAULT_STYLE}",
    "default_style_match": $([ "$DEFAULT_STYLE_MATCH" = "true" ] && echo "True" || echo "False"),

    "sld_found": $([ "$SLD_FOUND" = "true" ] && echo "True" || echo "False"),
    "sld_rule_count": ${SLD_RULE_COUNT:-0},
    "sld_has_city_count": $([ "$SLD_HAS_CITY_COUNT" = "true" ] && echo "True" || echo "False"),
    "sld_distinct_colors": ${SLD_DISTINCT_COLORS:-0},
    "sld_has_correct_colors": $([ "$SLD_HAS_CORRECT_COLORS" = "true" ] && echo "True" || echo "False"),
    "sld_has_stroke": $([ "$SLD_HAS_STROKE" = "true" ] && echo "True" || echo "False"),
    "sld_colors": "${SLD_COLORS}",

    "europe_img_exists": $([ "$EUROPE_IMG_EXISTS" = "true" ] && echo "True" || echo "False"),
    "europe_img_size": ${EUROPE_IMG_SIZE:-0},
    "europe_img_valid": $([ "$EUROPE_IMG_VALID" = "true" ] && echo "True" || echo "False"),
    "asia_img_exists": $([ "$ASIA_IMG_EXISTS" = "true" ] && echo "True" || echo "False"),
    "asia_img_size": ${ASIA_IMG_SIZE:-0},
    "asia_img_valid": $([ "$ASIA_IMG_VALID" = "true" ] && echo "True" || echo "False"),

    "wms_test_success": $([ "$WMS_TEST_SUCCESS" = "true" ] && echo "True" || echo "False"),

    "initial_workspace_count": ${INITIAL_WORKSPACE_COUNT},
    "current_workspace_count": ${CURRENT_WORKSPACE_COUNT},
    "initial_layer_count": ${INITIAL_LAYER_COUNT},
    "current_layer_count": ${CURRENT_LAYER_COUNT},
    "initial_style_count": ${INITIAL_STYLE_COUNT},
    "current_style_count": ${CURRENT_STYLE_COUNT}
}

with open("${TMPFILE}", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written successfully")
PYEOF

safe_write_result "$TMPFILE" "/tmp/parameterized_spatial_analysis_view_result.json"

echo "=== Export Complete ==="
