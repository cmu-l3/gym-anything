#!/bin/bash
set -e

echo "=== Exporting contaminated alignment QC results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Parse the generated files and compile results into JSON
python3 << 'PYEOF'
import os
import json

RESULTS_DIR = "/home/ga/UGENE_Data/qc_analysis/results"
FASTA_PATH = os.path.join(RESULTS_DIR, "cleaned_alignment.fasta")
ALN_PATH = os.path.join(RESULTS_DIR, "cleaned_alignment.aln")
REPORT_PATH = os.path.join(RESULTS_DIR, "qc_report.txt")
START_TS_FILE = "/tmp/qc_task_start_time.txt"

start_ts = 0
if os.path.exists(START_TS_FILE):
    try:
        start_ts = float(open(START_TS_FILE).read().strip())
    except:
        pass

def is_new_file(path):
    if not os.path.exists(path):
        return False
    return os.path.getmtime(path) >= start_ts

result = {
    "fasta_exists": False,
    "fasta_created_during_task": False,
    "fasta_accessions": [],
    "fasta_seq_lengths": [],
    "aln_exists": False,
    "aln_created_during_task": False,
    "aln_is_clustal": False,
    "report_exists": False,
    "report_created_during_task": False,
    "report_content": ""
}

# Check FASTA
if os.path.exists(FASTA_PATH) and os.path.getsize(FASTA_PATH) > 0:
    result["fasta_exists"] = True
    result["fasta_created_during_task"] = is_new_file(FASTA_PATH)
    accs = []
    seqs = []
    curr_seq = ""
    with open(FASTA_PATH) as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr_seq: seqs.append(curr_seq.replace("-", "")) # Store ungapped length if needed, or total length
                curr_seq = ""
                # Handle possible UGENE header formats
                raw_header = line[1:].split()[0]
                acc = raw_header.split("|")[-1] if "|" in raw_header else raw_header
                accs.append(acc)
            else:
                curr_seq += line
    if curr_seq: seqs.append(curr_seq)
    
    result["fasta_accessions"] = accs
    # Record actual lengths (including gaps) to verify they are aligned
    result["fasta_seq_lengths"] = [len(s) for s in seqs]

# Check ALN (ClustalW)
if os.path.exists(ALN_PATH) and os.path.getsize(ALN_PATH) > 0:
    result["aln_exists"] = True
    result["aln_created_during_task"] = is_new_file(ALN_PATH)
    with open(ALN_PATH) as f:
        first_line = f.readline().upper()
        # Clustal, Muscle, or Mafft header formats
        if "CLUSTAL" in first_line or "MUSCLE" in first_line or "MAFFT" in first_line:
            result["aln_is_clustal"] = True

# Check Report
if os.path.exists(REPORT_PATH) and os.path.getsize(REPORT_PATH) > 0:
    result["report_exists"] = True
    result["report_created_during_task"] = is_new_file(REPORT_PATH)
    with open(REPORT_PATH, 'r', encoding='utf-8', errors='ignore') as f:
        result["report_content"] = f.read().strip()

# Save payload for verifier
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported results to /tmp/task_result.json")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="