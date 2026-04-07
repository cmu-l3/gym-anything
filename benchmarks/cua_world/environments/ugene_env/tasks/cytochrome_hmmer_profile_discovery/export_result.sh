#!/bin/bash
echo "=== Exporting Cytochrome C HMMER Profile Discovery results ==="

RESULTS_DIR="/home/ga/UGENE_Data/hmmer_task/results"
DISPLAY=:1 scrot /tmp/hmmer_task_end_screenshot.png 2>/dev/null || true

# We use Python here to safely read file properties and content without encountering bash string issues
python3 << PYEOF
import json
import os
import re

results_dir = "${RESULTS_DIR}"

aln_exists = False
aln_valid = False
aln_seq_count = 0

hmm_exists = False
hmm_valid = False
hmm_leng = 0

gff_exists = False
gff_has_cytc = False
gff_content = ""

report_exists = False
report_has_cytc = False
report_has_coord = False
report_content = ""

# 1. Evaluate Alignment Output
aln_path = os.path.join(results_dir, "cytc_aligned.fasta")
if os.path.isfile(aln_path) and os.path.getsize(aln_path) > 0:
    aln_exists = True
    with open(aln_path, "r") as f:
        lines = f.readlines()
        if len(lines) > 0 and lines[0].startswith(">"):
            aln_valid = True
        aln_seq_count = sum(1 for line in lines if line.startswith(">"))

# 2. Evaluate HMM Profile
hmm_path = os.path.join(results_dir, "cytc_domain.hmm")
if os.path.isfile(hmm_path) and os.path.getsize(hmm_path) > 0:
    hmm_exists = True
    with open(hmm_path, "r") as f:
        lines = f.readlines()
        if len(lines) > 0 and "HMMER3/f" in lines[0]:
            hmm_valid = True
        for line in lines:
            if line.startswith("LENG"):
                try:
                    hmm_leng = int(line.split()[1])
                except:
                    pass
                break

# 3. Evaluate GFF Hit Export
gff_path = os.path.join(results_dir, "hmm_hits.gff")
if os.path.isfile(gff_path) and os.path.getsize(gff_path) > 0:
    gff_exists = True
    with open(gff_path, "r") as f:
        gff_content = f.read()
    if "CYTC_ARATH" in gff_content or "P00056" in gff_content:
        gff_has_cytc = True

# 4. Evaluate Plain Text Report
report_path = os.path.join(results_dir, "discovery_report.txt")
if os.path.isfile(report_path) and os.path.getsize(report_path) > 0:
    report_exists = True
    with open(report_path, "r") as f:
        report_content = f.read()
    if "CYTC_ARATH" in report_content or "P00056" in report_content:
        report_has_cytc = True
    # Look for start-end coordinates like 1-112 or 12..103
    if re.search(r'\d+\s*[-–.]\s*\d+', report_content):
        report_has_coord = True

result = {
    "aln_exists": aln_exists,
    "aln_valid": aln_valid,
    "aln_seq_count": aln_seq_count,
    "hmm_exists": hmm_exists,
    "hmm_valid": hmm_valid,
    "hmm_leng": hmm_leng,
    "gff_exists": gff_exists,
    "gff_has_cytc": gff_has_cytc,
    "report_exists": report_exists,
    "report_has_cytc": report_has_cytc,
    "report_has_coord": report_has_coord,
    "report_content_snippet": report_content[:500],
    "gff_content_snippet": gff_content[:500]
}

# Export to JSON
with open("/tmp/hmmer_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="