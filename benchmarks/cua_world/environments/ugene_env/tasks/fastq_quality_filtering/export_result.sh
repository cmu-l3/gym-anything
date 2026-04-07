#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/UGENE_Data/ngs/results"
RAW_FILE="/home/ga/UGENE_Data/ngs/raw_reads.fastq"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract file timestamps
FQ_CREATED="false"
FA_CREATED="false"
REP_CREATED="false"

if [ -f "${RESULTS_DIR}/filtered_reads.fastq" ]; then
    if [ $(stat -c %Y "${RESULTS_DIR}/filtered_reads.fastq") -ge $TASK_START ]; then
        FQ_CREATED="true"
    fi
fi

if [ -f "${RESULTS_DIR}/high_quality_reads.fasta" ]; then
    if [ $(stat -c %Y "${RESULTS_DIR}/high_quality_reads.fasta") -ge $TASK_START ]; then
        FA_CREATED="true"
    fi
fi

if [ -f "${RESULTS_DIR}/qc_report.txt" ]; then
    if [ $(stat -c %Y "${RESULTS_DIR}/qc_report.txt") -ge $TASK_START ]; then
        REP_CREATED="true"
    fi
fi

# Run Python script within container to evaluate file contents safely
python3 << PYEOF
import json
import os

raw_path = "${RAW_FILE}"
fq_path = "${RESULTS_DIR}/filtered_reads.fastq"
fa_path = "${RESULTS_DIR}/high_quality_reads.fasta"
rep_path = "${RESULTS_DIR}/qc_report.txt"

results = {
    "raw_reads": 0,
    "fq_exists": os.path.exists(fq_path),
    "fq_created_during_task": "${FQ_CREATED}" == "true",
    "fq_reads": 0,
    "fq_all_qual_pass": True,
    "fa_exists": os.path.exists(fa_path),
    "fa_created_during_task": "${FA_CREATED}" == "true",
    "fa_reads": 0,
    "fa_is_valid": True,
    "rep_exists": os.path.exists(rep_path),
    "rep_created_during_task": "${REP_CREATED}" == "true",
    "rep_mentions_20": False
}

# 1. Count original raw reads
if os.path.exists(raw_path):
    with open(raw_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        results["raw_reads"] = len(lines) // 4

# 2. Evaluate Filtered FASTQ
if results["fq_exists"]:
    try:
        with open(fq_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            results["fq_reads"] = len(lines) // 4
            # Verify mathematical quality condition (avg >= 20)
            for i in range(3, len(lines), 4):
                qual_str = lines[i].strip()
                if qual_str:
                    avg_q = sum(ord(c) - 33 for c in qual_str) / len(qual_str)
                    if avg_q < 20:
                        results["fq_all_qual_pass"] = False
                        break
    except Exception:
        results["fq_all_qual_pass"] = False

# 3. Evaluate High Quality FASTA
if results["fa_exists"]:
    try:
        with open(fa_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            results["fa_reads"] = content.count('>')
            
            # Anti-gaming: Ensure it's not just a renamed FASTQ file.
            # FASTA shouldn't contain quality delimiter lines ('+')
            lines = content.splitlines()
            plus_lines = [l for l in lines if l.startswith('+')]
            if len(plus_lines) > results["fa_reads"] // 2:
                results["fa_is_valid"] = False
    except Exception:
        results["fa_is_valid"] = False

# 4. Evaluate QC Report
if results["rep_exists"]:
    try:
        with open(rep_path, 'r', encoding='utf-8', errors='ignore') as f:
            txt = f.read()
            if '20' in txt:
                results["rep_mentions_20"] = True
    except Exception:
        pass

with open("/tmp/fastq_quality_filtering_result.json", "w") as f:
    json.dump(results, f)
PYEOF

echo "Result saved to /tmp/fastq_quality_filtering_result.json"
echo "=== Export complete ==="