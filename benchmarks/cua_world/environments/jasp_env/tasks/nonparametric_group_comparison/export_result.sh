#!/bin/bash
echo "=== Exporting nonparametric_group_comparison results ==="

# -----------------------------------------------------------
# Take a final screenshot of the JASP window
# -----------------------------------------------------------
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_end_screenshot.png" 2>/dev/null || true

# -----------------------------------------------------------
# Locate the saved .jasp file
# -----------------------------------------------------------
JASP_FILE="/home/ga/Documents/JASP/heart_rate_nonparametric.jasp"

if [ ! -f "$JASP_FILE" ]; then
    echo "Expected .jasp file not found at $JASP_FILE"
    echo "Searching for any .jasp files..."
    find /home/ga -name "*.jasp" -type f 2>/dev/null | head -5
    # Try common alternative locations
    for alt in /home/ga/Documents/*.jasp /home/ga/Desktop/*.jasp /home/ga/*.jasp /tmp/*.jasp; do
        if ls $alt 2>/dev/null | head -1 > /dev/null; then
            JASP_FILE=$(ls $alt 2>/dev/null | head -1)
            echo "Found alternative: $JASP_FILE"
            break
        fi
    done
fi

# -----------------------------------------------------------
# Parse the .jasp file (ZIP archive) and extract analyses.json
# -----------------------------------------------------------
python3 << 'PYEOF'
import json
import os
import sys
import zipfile
import tempfile

JASP_FILE = "/home/ga/Documents/JASP/heart_rate_nonparametric.jasp"

# Search for alternative .jasp files if primary not found
if not os.path.isfile(JASP_FILE):
    import glob
    candidates = []
    for pattern in [
        "/home/ga/Documents/JASP/*.jasp",
        "/home/ga/Documents/*.jasp",
        "/home/ga/Desktop/*.jasp",
        "/home/ga/*.jasp",
        "/tmp/*.jasp",
    ]:
        candidates.extend(glob.glob(pattern))
    if candidates:
        # Prefer the most recently modified
        candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        JASP_FILE = candidates[0]
        print(f"Using alternative .jasp file: {JASP_FILE}")

result = {
    "jasp_file_found": False,
    "jasp_file_path": JASP_FILE,
    "jasp_file_size": 0,
    "analyses_json_found": False,
    "analyses": [],
    "num_analyses": 0,
    "has_kruskal_wallis": False,
    "has_mann_whitney": False,
    "has_descriptives": False,
    "analysis_types": [],
    "resource_files": [],
    "has_results": False,
    "error": None,
}

try:
    if not os.path.isfile(JASP_FILE):
        result["error"] = f"No .jasp file found at {JASP_FILE}"
        raise FileNotFoundError(result["error"])

    result["jasp_file_found"] = True
    result["jasp_file_size"] = os.path.getsize(JASP_FILE)

    with zipfile.ZipFile(JASP_FILE, 'r') as zf:
        namelist = zf.namelist()
        result["resource_files"] = namelist

        # ---------------------------------------------------
        # Extract and parse analyses.json
        # ---------------------------------------------------
        if "analyses.json" in namelist:
            result["analyses_json_found"] = True
            analyses_raw = zf.read("analyses.json").decode("utf-8")
            analyses_data = json.loads(analyses_raw)

            # analyses.json can be a list or a dict with "analyses" key
            if isinstance(analyses_data, list):
                analyses_list = analyses_data
            elif isinstance(analyses_data, dict):
                analyses_list = analyses_data.get("analyses", [])
            else:
                analyses_list = []

            result["num_analyses"] = len(analyses_list)
            result["analyses"] = analyses_data  # preserve full structure

            for analysis in analyses_list:
                aname = analysis.get("name", "").lower()
                amodule = analysis.get("module", "").lower()
                opts = analysis.get("options", {})

                # Record analysis type info
                analysis_info = {
                    "name": analysis.get("name", ""),
                    "module": analysis.get("module", ""),
                    "options_keys": list(opts.keys()) if isinstance(opts, dict) else [],
                }
                result["analysis_types"].append(analysis_info)

                # Detect Kruskal-Wallis
                if any(kw in aname for kw in ["kruskal", "anova_nonparametric", "anovnonpar"]):
                    result["has_kruskal_wallis"] = True
                elif "kruskal" in json.dumps(opts).lower():
                    result["has_kruskal_wallis"] = True

                # Detect Mann-Whitney
                if any(kw in aname for kw in ["mann", "whitney", "ttestis_nonparametric", "ttestindsamples"]):
                    result["has_mann_whitney"] = True
                elif "mann" in json.dumps(opts).lower() or "whitney" in json.dumps(opts).lower():
                    result["has_mann_whitney"] = True

                # Detect Descriptives
                if any(kw in aname for kw in ["descriptiv", "descriptivestatistics"]):
                    result["has_descriptives"] = True

        # ---------------------------------------------------
        # Check for computed results in resources/
        # ---------------------------------------------------
        result_files = [f for f in namelist if "jaspResults" in f or "results" in f.lower()]
        if result_files:
            result["has_results"] = True
            # Check that at least one result file has meaningful content
            for rf in result_files[:5]:
                try:
                    content = zf.read(rf)
                    if len(content) > 50:
                        result["has_results"] = True
                        break
                except Exception:
                    pass

except FileNotFoundError:
    pass
except Exception as e:
    result["error"] = str(e)

# Write the result JSON for the verifier
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
