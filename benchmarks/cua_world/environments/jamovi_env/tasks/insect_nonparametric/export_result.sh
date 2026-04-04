#!/bin/bash
echo "=== Exporting insect_nonparametric results ==="

# -----------------------------------------------------------
# Take a final screenshot of the Jamovi window
# -----------------------------------------------------------
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_end_screenshot.png" 2>/dev/null || true

# -----------------------------------------------------------
# Locate the saved .omv file
# -----------------------------------------------------------
OMV_FILE="/home/ga/Documents/Jamovi/InsectSprayAnalysis.omv"

if [ ! -f "$OMV_FILE" ]; then
    echo "Expected .omv file not found at $OMV_FILE"
    echo "Searching for any .omv files..."
    find /home/ga -name "*.omv" -type f 2>/dev/null | head -5
    # Try common alternative locations
    for alt in /home/ga/Documents/Jamovi/*.omv /home/ga/Documents/*.omv /home/ga/Desktop/*.omv /home/ga/*.omv /tmp/*.omv; do
        if ls $alt 2>/dev/null | head -1 > /dev/null; then
            OMV_FILE=$(ls $alt 2>/dev/null | head -1)
            echo "Found alternative: $OMV_FILE"
            break
        fi
    done
fi

# -----------------------------------------------------------
# Parse the .omv file (ZIP archive) and extract index.html
# -----------------------------------------------------------
python3 << 'PYEOF'
import json
import os
import sys
import zipfile
import re

OMV_FILE = "/home/ga/Documents/Jamovi/InsectSprayAnalysis.omv"

# Search for alternative .omv files if primary not found
if not os.path.isfile(OMV_FILE):
    import glob
    candidates = []
    for pattern in [
        "/home/ga/Documents/Jamovi/*.omv",
        "/home/ga/Documents/*.omv",
        "/home/ga/Desktop/*.omv",
        "/home/ga/*.omv",
        "/tmp/*.omv",
    ]:
        candidates.extend(glob.glob(pattern))
    if candidates:
        # Prefer the most recently modified
        candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        OMV_FILE = candidates[0]
        print(f"Using alternative .omv file: {OMV_FILE}")

result = {
    "omv_file_found": False,
    "omv_file_path": OMV_FILE,
    "omv_file_size": 0,
    "index_html_found": False,
    "index_html_content": "",
    "zip_contents": [],
    "has_descriptives": False,
    "has_descriptives_split_spray": False,
    "has_shapiro_wilk": False,
    "has_kruskal_wallis": False,
    "has_kruskal_wallis_count": False,
    "has_kruskal_wallis_spray": False,
    "has_pairwise": False,
    "has_count_var": False,
    "has_spray_var": False,
    "error": None,
}

try:
    if not os.path.isfile(OMV_FILE):
        result["error"] = f"No .omv file found at {OMV_FILE}"
        raise FileNotFoundError(result["error"])

    result["omv_file_found"] = True
    result["omv_file_size"] = os.path.getsize(OMV_FILE)

    with zipfile.ZipFile(OMV_FILE, 'r') as zf:
        namelist = zf.namelist()
        result["zip_contents"] = namelist

        # ---------------------------------------------------
        # Extract and parse index.html
        # ---------------------------------------------------
        if "index.html" in namelist:
            result["index_html_found"] = True
            raw = zf.read("index.html")
            # Try utf-8-sig first to handle BOM, then utf-8, then latin-1
            for enc in ("utf-8-sig", "utf-8", "latin-1"):
                try:
                    html = raw.decode(enc)
                    break
                except (UnicodeDecodeError, ValueError):
                    html = ""
            result["index_html_content"] = html[:50000]  # truncate for safety
            html_lower = html.lower()

            # ----- Check for Descriptives -----
            if "descriptives" in html_lower or "descriptive statistics" in html_lower:
                result["has_descriptives"] = True

            # ----- Check for Descriptives split by spray -----
            # Jamovi renders split-by as separate group rows/columns in the table
            if result["has_descriptives"] and "spray" in html_lower:
                result["has_descriptives_split_spray"] = True

            # ----- Check for Shapiro-Wilk normality test -----
            if "shapiro" in html_lower or "shapiro-wilk" in html_lower:
                result["has_shapiro_wilk"] = True

            # ----- Check for Kruskal-Wallis test -----
            if "kruskal" in html_lower or "kruskal-wallis" in html_lower:
                result["has_kruskal_wallis"] = True

            # ----- Check if Kruskal-Wallis uses count variable -----
            if result["has_kruskal_wallis"] and "count" in html_lower:
                result["has_kruskal_wallis_count"] = True

            # ----- Check if Kruskal-Wallis uses spray variable -----
            if result["has_kruskal_wallis"] and "spray" in html_lower:
                result["has_kruskal_wallis_spray"] = True

            # ----- Check for pairwise comparisons -----
            pairwise_keywords = ["dscf", "dwass", "steel", "critchlow", "fligner",
                                 "pairwise", "dunn", "post hoc", "post-hoc"]
            for kw in pairwise_keywords:
                if kw in html_lower:
                    result["has_pairwise"] = True
                    break

            # ----- Check for variable names -----
            if "count" in html_lower:
                result["has_count_var"] = True
            if "spray" in html_lower:
                result["has_spray_var"] = True

except FileNotFoundError:
    pass
except Exception as e:
    result["error"] = str(e)

# Write the result JSON for the verifier
with open("/tmp/insect_nonparametric_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
