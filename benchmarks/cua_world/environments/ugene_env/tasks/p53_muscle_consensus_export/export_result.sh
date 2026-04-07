#!/bin/bash
echo "=== Exporting p53_muscle_consensus_export results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# We will use Python to perform robust text/sequence extraction and write the result JSON.
python3 << 'PYEOF'
import json
import os
import re

start_ts = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_ts = int(f.read().strip())
except Exception:
    pass

def file_status(path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return True, os.path.getmtime(path) > start_ts
    return False, False

def parse_fasta(path):
    seqs = []
    headers = []
    curr_seq = ""
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                headers.append(line)
                if curr_seq:
                    seqs.append(curr_seq)
                curr_seq = ""
            else:
                curr_seq += line
        if curr_seq:
            seqs.append(curr_seq)
    return headers, seqs

res = {}

# 1. Stockholm Alignment
sto_path = "/home/ga/UGENE_Data/p53/results/p53_alignment.sto"
sto_exists, sto_new = file_status(sto_path)
res['sto_exists'] = sto_exists
res['sto_new'] = sto_new
res['sto_valid'] = False
if sto_exists:
    try:
        with open(sto_path) as f:
            first_line = f.readline().strip()
            if "STOCKHOLM" in first_line:
                res['sto_valid'] = True
    except:
        pass

# 2. FASTA Alignment
fasta_path = "/home/ga/UGENE_Data/p53/results/p53_alignment.fasta"
fa_exists, fa_new = file_status(fasta_path)
res['fa_exists'] = fa_exists
res['fa_new'] = fa_new
res['fa_seq_count'] = 0
res['fa_same_length'] = False
res['fa_alignment_len'] = 0
if fa_exists:
    try:
        headers, seqs = parse_fasta(fasta_path)
        res['fa_seq_count'] = len(seqs)
        if len(seqs) > 0:
            lens = [len(s) for s in seqs]
            res['fa_same_length'] = len(set(lens)) == 1
            res['fa_alignment_len'] = lens[0]
            # Must contain gaps to be an alignment
            if res['fa_same_length'] and any('-' in s for s in seqs):
                pass
            elif res['fa_same_length'] and not any('-' in s for s in seqs):
                # Unlikely to be a real alignment if absolutely no gaps, but let's just mark it same length
                pass
    except:
        pass

# 3. Consensus Sequence
cons_path = "/home/ga/UGENE_Data/p53/results/p53_consensus.fasta"
cons_exists, cons_new = file_status(cons_path)
res['cons_exists'] = cons_exists
res['cons_new'] = cons_new
res['cons_has_consensus_header'] = False
res['cons_seq_len'] = 0
if cons_exists:
    try:
        headers, seqs = parse_fasta(cons_path)
        if len(headers) == 1:
            res['cons_seq_len'] = len(seqs[0])
            if "consensus" in headers[0].lower():
                res['cons_has_consensus_header'] = True
    except:
        pass

# 4. Conservation Report
rep_path = "/home/ga/UGENE_Data/p53/results/p53_conservation_report.txt"
rep_exists, rep_new = file_status(rep_path)
res['rep_exists'] = rep_exists
res['rep_new'] = rep_new
res['rep_has_8'] = False
res['rep_has_align_len'] = False
res['rep_has_conserved_pos'] = False
res['rep_has_regions'] = False
if rep_exists:
    try:
        with open(rep_path) as f:
            text = f.read().lower()
            res['rep_has_8'] = "8" in text or "eight" in text
            # Alignment length is likely 400-600
            res['rep_has_align_len'] = bool(re.search(r'\b(3[8-9]\d|4\d{2}|5\d{2}|6\d{2})\b', text))
            # Conserved positions likely 50-300
            res['rep_has_conserved_pos'] = bool(re.search(r'\b([2-9]\d|[1-2]\d{2}|300)\b', text))
            # Regions
            res['rep_has_regions'] = bool(re.search(r'(terminal|binding|domain|motif|region|core)', text))
    except:
        pass

with open("/tmp/p53_task_result.json", "w") as f:
    json.dump(res, f, indent=2)

print("Export logic complete, JSON saved.")
PYEOF

chmod 666 /tmp/p53_task_result.json
echo "=== Export complete ==="