#!/bin/bash
echo "=== Exporting mt_trna_extraction_alignment results ==="

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/mitochondria/results"
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Run Python script to securely parse FASTA files and report into JSON
python3 << 'PYEOF'
import os
import json
import time

results_dir = "/home/ga/UGENE_Data/mitochondria/results"
extracted_fasta = os.path.join(results_dir, "human_mt_tRNAs.fasta")
aligned_fasta = os.path.join(results_dir, "mt_tRNA_alignment.fasta")
report_txt = os.path.join(results_dir, "tRNA_report.txt")

def read_fasta(filepath):
    seqs = {}
    curr_header = None
    if not os.path.exists(filepath):
        return seqs
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                curr_header = line[1:]
                seqs[curr_header] = ""
            elif curr_header:
                seqs[curr_header] += line
    return seqs

def get_file_mtime(filepath):
    if os.path.exists(filepath):
        return int(os.path.getmtime(filepath))
    return 0

# Parse extracted FASTA
extracted_seqs = read_fasta(extracted_fasta)
extracted_count = len(extracted_seqs)
extracted_lengths = [len(seq) for seq in extracted_seqs.values()]
extracted_max_len = max(extracted_lengths) if extracted_lengths else 0
extracted_min_len = min(extracted_lengths) if extracted_lengths else 0

# Parse aligned FASTA
aligned_seqs = read_fasta(aligned_fasta)
aligned_count = len(aligned_seqs)
aligned_lengths = [len(seq) for seq in aligned_seqs.values()]
aligned_unique_lengths = list(set(aligned_lengths))
aligned_contains_gaps = any("-" in seq for seq in aligned_seqs.values())

# Parse report
report_content = ""
if os.path.exists(report_txt):
    with open(report_txt, 'r') as f:
        report_content = f.read().strip()

result = {
    "task_start_time": int(open("/tmp/task_start_time").read().strip()) if os.path.exists("/tmp/task_start_time") else 0,
    "extracted_exists": os.path.exists(extracted_fasta),
    "extracted_mtime": get_file_mtime(extracted_fasta),
    "extracted_count": extracted_count,
    "extracted_max_len": extracted_max_len,
    "extracted_min_len": extracted_min_len,
    
    "aligned_exists": os.path.exists(aligned_fasta),
    "aligned_mtime": get_file_mtime(aligned_fasta),
    "aligned_count": aligned_count,
    "aligned_lengths_equal": len(aligned_unique_lengths) == 1 if aligned_count > 0 else False,
    "aligned_contains_gaps": aligned_contains_gaps,
    
    "report_exists": os.path.exists(report_txt),
    "report_mtime": get_file_mtime(report_txt),
    "report_content": report_content
}

# Write out safely
import tempfile
import shutil
fd, temp_path = tempfile.mkstemp(suffix=".json")
with os.fdopen(fd, 'w') as f:
    json.dump(result, f)

# Move to final destination
shutil.copy(temp_path, "/tmp/mt_trna_result.json")
os.chmod("/tmp/mt_trna_result.json", 0o666)
os.unlink(temp_path)
PYEOF

echo "Result JSON written to /tmp/mt_trna_result.json"
cat /tmp/mt_trna_result.json