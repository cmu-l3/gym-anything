#!/bin/bash
echo "=== Exporting sickle_cell_rflp_genotyping results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse results and output to JSON
python3 << 'PYEOF'
import json
import os
import re

wt_gb = "/home/ga/UGENE_Data/rflp_genotyping/results/hbb_wildtype_ddei.gb"
mut_gb = "/home/ga/UGENE_Data/rflp_genotyping/results/hbb_mutant_ddei.gb"
report = "/home/ga/UGENE_Data/rflp_genotyping/results/genotyping_report.txt"

res = {
    "wt_gb_exists": os.path.exists(wt_gb),
    "mut_gb_exists": os.path.exists(mut_gb),
    "report_exists": os.path.exists(report),
    "wt_ddei_count": 0,
    "mut_ddei_count": 0,
    "report_content": "",
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

def count_ddei(filepath):
    if not os.path.exists(filepath): return 0
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    # Only search within features section, before origin
    features = content.split("ORIGIN")[0] if "ORIGIN" in content else content
    return len(re.findall(r'Dde\s*I', features, re.IGNORECASE))

res["wt_ddei_count"] = count_ddei(wt_gb)
res["mut_ddei_count"] = count_ddei(mut_gb)

if res["report_exists"]:
    with open(report, "r", encoding="utf-8", errors="ignore") as f:
        res["report_content"] = f.read()

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
PYEOF

# Fix permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="