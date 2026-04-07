#!/bin/bash
echo "=== Exporting recombinant_cloning_design results ==="

# Record task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/cloning_design/results"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check UGENE status
UGENE_RUNNING="false"
if pgrep -f "ugene" > /dev/null 2>&1; then
    UGENE_RUNNING="true"
fi

# 3. Collect results using Python
python3 << 'PYEOF'
import json
import os
import re

RESULTS_DIR = "/home/ga/UGENE_Data/cloning_design/results"
TASK_START = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

result = {
    "task_start_ts": TASK_START,
}

# --- Check pET28a_annotated.gb ---
vec_gb_path = os.path.join(RESULTS_DIR, "pET28a_annotated.gb")
result["vector_gb_exists"] = os.path.exists(vec_gb_path)
result["vector_gb_size"] = os.path.getsize(vec_gb_path) if result["vector_gb_exists"] else 0
result["vector_restriction_site_count"] = 0
result["vector_orf_count"] = 0

if result["vector_gb_exists"]:
    with open(vec_gb_path, "r", encoding="utf-8", errors="ignore") as f:
        vec_content = f.read()

    # Count restriction site annotations in FEATURES section
    features_section = vec_content.split("ORIGIN")[0] if "ORIGIN" in vec_content else vec_content
    # Look for restriction site feature entries
    result["vector_restriction_site_count"] = len(re.findall(
        r'misc_feature.*\n\s*/label="[^"]*[Rr]estriction|/note="[^"]*cut|/label="[A-Z][a-z]+[IVX]+',
        features_section
    ))
    # Also count by common enzyme name patterns
    enzyme_names = set(re.findall(r'\b(BamHI|EcoRI|SacI|SalI|HindIII|NotI|XhoI|NdeI|NcoI|BglII|XbaI|PstI|SphI|ClaI|KpnI)\b', features_section))
    result["vector_distinct_enzymes"] = len(enzyme_names)
    result["vector_enzyme_names"] = sorted(list(enzyme_names))

    # Count ORF/CDS annotations
    result["vector_orf_count"] = len(re.findall(r'^\s+(CDS|gene)\s+', features_section, re.MULTILINE))

    # Copy file to /tmp for verifier access
    with open("/tmp/pET28a_annotated.gb", "w") as f:
        f.write(vec_content)
    os.chmod("/tmp/pET28a_annotated.gb", 0o666)

# --- Check epo_annotated.gb ---
epo_gb_path = os.path.join(RESULTS_DIR, "epo_annotated.gb")
result["epo_gb_exists"] = os.path.exists(epo_gb_path)
result["epo_gb_size"] = os.path.getsize(epo_gb_path) if result["epo_gb_exists"] else 0
result["epo_restriction_site_count"] = 0

if result["epo_gb_exists"]:
    with open(epo_gb_path, "r", encoding="utf-8", errors="ignore") as f:
        epo_content = f.read()
    features_section = epo_content.split("ORIGIN")[0] if "ORIGIN" in epo_content else epo_content
    enzyme_names = set(re.findall(r'\b(BamHI|EcoRI|SacI|SalI|HindIII|NotI|XhoI|NdeI|NcoI|BglII|XbaI|PstI|SphI|ClaI|KpnI)\b', features_section))
    result["epo_distinct_enzymes"] = len(enzyme_names)
    result["epo_enzyme_names"] = sorted(list(enzyme_names))

    with open("/tmp/epo_annotated.gb", "w") as f:
        f.write(epo_content)
    os.chmod("/tmp/epo_annotated.gb", 0o666)

# --- Check vector_map.svg ---
svg_path = os.path.join(RESULTS_DIR, "vector_map.svg")
result["svg_exists"] = os.path.exists(svg_path)
result["svg_size"] = os.path.getsize(svg_path) if result["svg_exists"] else 0
result["svg_valid"] = False

if result["svg_exists"]:
    with open(svg_path, "r", encoding="utf-8", errors="ignore") as f:
        svg_head = f.read(2000)
    result["svg_valid"] = "<svg" in svg_head.lower() or "<?xml" in svg_head.lower()

# Also check for common alternative extensions/names
for alt in ["vector_map.svg.svg", "vector_map.svg.png", "vector_map.png"]:
    alt_path = os.path.join(RESULTS_DIR, alt)
    if os.path.exists(alt_path) and not result["svg_exists"]:
        result["svg_alt_found"] = alt
        result["svg_alt_size"] = os.path.getsize(alt_path)

# --- Check cloning_report.txt ---
report_path = os.path.join(RESULTS_DIR, "cloning_report.txt")
result["report_exists"] = os.path.exists(report_path)
result["report_size"] = os.path.getsize(report_path) if result["report_exists"] else 0
result["report_content"] = ""

if result["report_exists"]:
    with open(report_path, "r", encoding="utf-8", errors="ignore") as f:
        result["report_content"] = f.read(5000)

# Also check for alternative report locations
for alt_dir in ["/home/ga/UGENE_Data/cloning_design", "/home/ga", "/home/ga/Desktop"]:
    for alt_name in ["cloning_report.txt", "report.txt", "cloning_strategy.txt"]:
        alt_path = os.path.join(alt_dir, alt_name)
        if os.path.exists(alt_path) and not result["report_exists"]:
            result["report_alt_found"] = alt_path
            with open(alt_path, "r", encoding="utf-8", errors="ignore") as f:
                result["report_alt_content"] = f.read(5000)

# --- List all files in results directory ---
result["results_dir_contents"] = []
if os.path.exists(RESULTS_DIR):
    for fname in os.listdir(RESULTS_DIR):
        fpath = os.path.join(RESULTS_DIR, fname)
        result["results_dir_contents"].append({
            "name": fname,
            "size": os.path.getsize(fpath) if os.path.isfile(fpath) else 0,
            "mtime": int(os.path.getmtime(fpath)) if os.path.isfile(fpath) else 0
        })

# Write result JSON atomically
import tempfile
tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', dir='/tmp',
                                  prefix='cloning_result_', delete=False)
json.dump(result, tmp, indent=2)
tmp.close()

# Move to final location
os.replace(tmp.name, "/tmp/task_result.json")
os.chmod("/tmp/task_result.json", 0o666)

print("Results exported to /tmp/task_result.json")
print(json.dumps(result, indent=2))

PYEOF

echo "=== Export complete ==="
