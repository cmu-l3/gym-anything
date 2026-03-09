#!/bin/bash
# Do NOT use set -e

echo "=== Exporting us_executive_branch_orgchart result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/us_executive_branch.drawio"
PNG_FILE="/home/ga/Desktop/us_executive_branch.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check file existence and modification
DRAWIO_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Run python script to analyze the drawio XML content
python3 << 'PYEOF' > /tmp/orgchart_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/us_executive_branch.drawio"
result = {
    "num_shapes": 0, "num_edges": 0, "num_pages": 0,
    "departments_found": [],
    "agencies_found": [],
    "years_found": 0,
    "officers_found": [],
    "distinct_colors": 0,
    "error": None
}

DEPARTMENTS = [
    "state", "treasury", "defense", "justice", "interior", "agriculture",
    "commerce", "labor", "health", "housing", "transportation", "energy",
    "education", "veterans", "homeland"
]
OFFICERS = ["president", "vice"]
AGENCIES = ["nasa", "epa", "cia", "fcc", "sec", "ssa", "sba", "usps", "nsf", "fema"]

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except:
        try:
            from urllib.parse import unquote
            decoded_str = unquote(content.strip())
            if decoded_str.startswith('<'): return ET.fromstring(decoded_str)
        except: pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages) or 1 # If no diagram tag, might be raw graph

        all_cells = []
        if pages:
            for page in pages:
                # Try compressed text
                inner = decompress_diagram(page.text or '')
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))
                else:
                    # Try inline
                    all_cells.extend(list(page.iter('mxCell')))
        else:
            # Maybe simple file
            all_cells = list(root.iter('mxCell'))

        colors = set()
        
        # Analyze cells
        for cell in all_cells:
            val = str(cell.get('value') or '').lower()
            style = str(cell.get('style') or '')
            
            # Simple HTML stripping
            val_clean = re.sub(r'<[^>]+>', ' ', val)
            
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                
                # Check departments
                for dept in DEPARTMENTS:
                    if dept in val_clean and dept not in result["departments_found"]:
                        # avoid partial matches like "state" matching "united states" generically
                        # but "department of state" is expected.
                        # Simple substring check is risky, but combined with "department" check usually safe.
                        # Stricter: check for "department" AND the keyword
                        if dept == "justice":
                            if "justice" in val_clean or "attorney" in val_clean:
                                result["departments_found"].append(dept)
                        elif dept == "health":
                            if "health" in val_clean or "hhs" in val_clean:
                                result["departments_found"].append(dept)
                        elif dept == "housing":
                            if "housing" in val_clean or "hud" in val_clean:
                                result["departments_found"].append(dept)
                        elif dept == "veterans":
                            if "veteran" in val_clean or "va " in val_clean:
                                result["departments_found"].append(dept)
                        elif dept == "homeland":
                            if "homeland" in val_clean or "dhs" in val_clean:
                                result["departments_found"].append(dept)
                        else:
                            if dept in val_clean:
                                result["departments_found"].append(dept)
                
                # Check officers
                for off in OFFICERS:
                    if off in val_clean and off not in result["officers_found"]:
                        result["officers_found"].append(off)
                        
                # Check agencies
                for ag in AGENCIES:
                    # Match exact words or abbreviations
                    if re.search(r'\b' + ag + r'\b', val_clean):
                        if ag not in result["agencies_found"]:
                            result["agencies_found"].append(ag)
                            
                # Check years (1789-2010)
                if re.search(r'1[789]\d{2}|20[01]\d', val_clean):
                    result["years_found"] += 1
                
                # Check colors
                # extract fillColor=#XXXXXX
                color_match = re.search(r'fillColor=(#[0-9a-fA-F]{6}|[a-zA-Z]+)', style)
                if color_match:
                    c = color_match.group(1).lower()
                    if c != 'none' and c != '#ffffff':
                        colors.add(c)
                        
            elif cell.get('edge') == '1':
                result["num_edges"] += 1

        result["distinct_colors"] = len(colors)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $DRAWIO_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/orgchart_analysis.json)
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="