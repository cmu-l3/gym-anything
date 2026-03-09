#!/bin/bash
echo "=== Exporting configure_wfs_limits_precision result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We will use a Python script inside the container to verify the WFS behavior
# This ensures we are testing the actual service response

cat > /tmp/verify_wfs.py << 'EOF'
import requests
import json
import re
import sys

GS_URL = "http://localhost:8080/geoserver"
WFS_URL = f"{GS_URL}/wfs"
REST_URL = f"{GS_URL}/rest"
AUTH = ("admin", "Admin123!")

results = {
    "pop_places_count": 0,
    "pop_places_precision": -1,
    "countries_count": 0,
    "global_precision_setting": -1,
    "layer_limit_setting": -1,
    "error": None
}

try:
    # 1. Check Feature Count for ne:ne_populated_places
    # We ask for JSON to easily parse count, but GML is default.
    # Note: GeoServer WFS 2.0.0 might page. We use 1.1.0 for simpler default behavior or check numberReturned
    params = {
        "service": "WFS",
        "version": "1.1.0",
        "request": "GetFeature",
        "typeName": "ne:ne_populated_places",
        "outputFormat": "application/json"
    }
    r = requests.get(WFS_URL, params=params)
    if r.status_code == 200:
        data = r.json()
        results["pop_places_count"] = len(data.get("features", []))
        
        # 2. Check Coordinate Precision
        # Look at the first coordinate of the first feature
        if results["pop_places_count"] > 0:
            coords = data["features"][0]["geometry"]["coordinates"]
            # Flatten to find a float
            def find_float(x):
                if isinstance(x, float): return x
                if isinstance(x, list):
                    for i in x:
                        val = find_float(i)
                        if val is not None: return val
                return None
            
            val = find_float(coords)
            if val is not None:
                # Convert to string and count decimals
                # str(val) might use scientific notation or truncate, 
                # but usually works for simple precision checks.
                # Better: check the raw text response for the pattern
                pass

    # Precision check via raw text analysis to avoid Python float rounding
    r_text = requests.get(WFS_URL, params={**params, "outputFormat": "gml3"}).text
    # Find coordinates pattern like 12.345 or 12.345678
    # Regex to find numbers with decimal points
    matches = re.findall(r'-?\d+\.(\d+)', r_text)
    if matches:
        # Check the length of the fractional part of a few matches
        lengths = [len(m) for m in matches[:20]]
        # usage of mode or max? If precision is 3, max should be 3 (unless trailing zeros are dropped)
        # GeoServer usually drops trailing zeros. So we look for the MAX length found.
        # If precision is 3, we shouldn't see 4.
        results["pop_places_precision"] = max(lengths) if lengths else 0

    # 3. Check Feature Count for ne:ne_countries (Control Group)
    params["typeName"] = "ne:ne_countries"
    r = requests.get(WFS_URL, params=params)
    if r.status_code == 200:
        data = r.json()
        results["countries_count"] = len(data.get("features", []))

    # 4. Check REST Global Settings
    # /rest/services/wfs/settings.json
    r = requests.get(f"{REST_URL}/services/wfs/settings.json", auth=AUTH)
    if r.status_code == 200:
        settings = r.json()
        # Navigate wfs -> maxFeatures (global) or numDecimals
        # Structure varies by version, usually wfs -> numDecimals
        wfs = settings.get("wfs", {})
        if "numDecimals" in wfs:
            results["global_precision_setting"] = wfs["numDecimals"]
    
    # 5. Check Layer Settings
    # /rest/layers/ne:ne_populated_places.json
    r = requests.get(f"{REST_URL}/layers/ne:ne_populated_places.json", auth=AUTH)
    if r.status_code == 200:
        layer = r.json()
        # resource -> ...
        # Actually feature limits are usually in the FeatureType resource, specifically "maxFeatures"
        # Let's check the resource link
        resource_href = layer.get("layer", {}).get("resource", {}).get("href")
        if resource_href:
            r2 = requests.get(resource_href, auth=AUTH)
            if r2.status_code == 200:
                ft = r2.json().get("featureType", {})
                results["layer_limit_setting"] = ft.get("maxFeatures", 0)

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
EOF

# Execute the python verification script
VERIFY_OUTPUT=$(python3 /tmp/verify_wfs.py)

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "verification_data": $VERIFY_OUTPUT,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_wfs_limits_precision_result.json"

echo "=== Export complete ==="