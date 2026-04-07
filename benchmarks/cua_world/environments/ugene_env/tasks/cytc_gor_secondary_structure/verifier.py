#!/usr/bin/env python3
"""Verifier for cytc_gor_secondary_structure task.

Scoring breakdown (100 points total):
  Human sequence isolated (FASTA):      15
  GFF Annotation Export:                25
  Longest Helix Extraction (FASTA):     25
  Valid Subsequence check:              15
  Summary Report Accuracy:              20
                                TOTAL = 100
"""

import json
import os
import re
import tempfile
import base64

def decode_b64(b64_str):
    if not b64_str:
        return ""
    try:
        return base64.b64decode(b64_str).decode('utf-8', errors='replace')
    except Exception:
        return ""

def parse_fasta(fasta_text):
    """Returns list of tuples: (header, sequence)"""
    sequences = []
    header = ""
    seq = []
    for line in fasta_text.splitlines():
        line = line.strip()
        if not line: continue
        if line.startswith(">"):
            if header:
                sequences.append((header, "".join(seq)))
            header = line[1:]
            seq = []
        else:
            seq.append(line)
    if header:
        sequences.append((header, "".join(seq)))
    return sequences

def parse_gff(gff_text):
    """Returns tuple (helices, sheets) as lists of (start, end) tuples."""
    helices = []
    sheets = []
    for line in gff_text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split('\t')
        if len(parts) >= 9:
            ftype = parts[2].lower()
            try:
                start = int(parts[3])
                end = int(parts[4])
                
                # UGENE GOR annotations: 'helix', 'alpha_helix', 'sheet', 'strand', 'beta_strand'
                if 'helix' in ftype:
                    helices.append((start, end))
                elif 'sheet' in ftype or 'strand' in ftype:
                    sheets.append((start, end))
            except ValueError:
                pass
    return helices, sheets

def verify_cytc_gor_secondary_structure(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results JSON
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/cytc_gor_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        os.unlink(tmp.name)

    human_data = result.get('human_fasta', {})
    gff_data = result.get('gff_file', {})
    helix_data = result.get('helix_fasta', {})
    report_data = result.get('report_file', {})

    anti_gaming_passed = (
        human_data.get('created_during_task', False) or 
        gff_data.get('created_during_task', False)
    )

    if not anti_gaming_passed:
        feedback_parts.append("WARNING: Output files were not created during the session (Anti-gaming triggered)")

    human_seq_str = ""

    # --- Criterion 1: Human sequence isolated (15 points) ---
    c1 = 0
    if human_data.get('exists') and human_data.get('created_during_task'):
        content = decode_b64(human_data.get('content_b64', ''))
        seqs = parse_fasta(content)
        if len(seqs) == 1:
            header, seq = seqs[0]
            if "P99999" in header:
                human_seq_str = seq
                c1 += 15
                feedback_parts.append("Human sequence (P99999) correctly isolated (+15)")
            else:
                c1 += 5
                feedback_parts.append("Single sequence isolated, but missing P99999 in header (+5)")
                human_seq_str = seq
        elif len(seqs) > 1:
            feedback_parts.append(f"human_cytc.fasta contains multiple sequences ({len(seqs)}) instead of 1 (0)")
    else:
        feedback_parts.append("human_cytc.fasta missing or not created during task (0)")
    score += c1

    # --- Criterion 2: GFF Annotation Export (25 points) ---
    c2 = 0
    helices, sheets = [], []
    if gff_data.get('exists') and gff_data.get('created_during_task'):
        c2 += 10
        content = decode_b64(gff_data.get('content_b64', ''))
        if "\t" in content and "##gff" in content.lower() or "\t" in content:
            c2 += 5
            helices, sheets = parse_gff(content)
            if len(helices) > 0:
                c2 += 5
            if len(sheets) > 0:
                c2 += 5
            feedback_parts.append(f"GFF valid with {len(helices)} helices and {len(sheets)} sheets (+25)")
        else:
            feedback_parts.append("GFF file exists but format is invalid (+10)")
    else:
        feedback_parts.append("GFF file missing (0)")
    score += c2

    # Identify longest helix mathematically from GFF
    expected_longest_helix = None
    expected_helix_len = 0
    if helices:
        expected_longest_helix = max(helices, key=lambda x: x[1] - x[0] + 1)
        expected_helix_len = expected_longest_helix[1] - expected_longest_helix[0] + 1

    # --- Criterion 3: Longest Helix Extraction (25 points) ---
    c3 = 0
    extracted_helix_seq = ""
    if helix_data.get('exists') and helix_data.get('created_during_task'):
        content = decode_b64(helix_data.get('content_b64', ''))
        seqs = parse_fasta(content)
        if len(seqs) >= 1:
            c3 += 10
            extracted_helix_seq = seqs[0][1]
            if expected_helix_len > 0 and len(extracted_helix_seq) == expected_helix_len:
                c3 += 15
                feedback_parts.append(f"Longest helix FASTA matches expected length {expected_helix_len} (+25)")
            else:
                c3 += 5
                feedback_parts.append(f"Longest helix FASTA length {len(extracted_helix_seq)} != expected {expected_helix_len} (+15)")
        else:
            feedback_parts.append("longest_helix.fasta is not a valid FASTA file (0)")
    else:
        feedback_parts.append("longest_helix.fasta missing (0)")
    score += c3

    # --- Criterion 4: Valid Subsequence (15 points) ---
    c4 = 0
    if extracted_helix_seq and human_seq_str:
        # GOR IV annotations are 1-indexed and inclusive. We can directly check if the extracted seq
        # is a substring of the full human sequence.
        if extracted_helix_seq.upper() in human_seq_str.upper():
            c4 += 15
            feedback_parts.append("Extracted helix is a valid continuous substring of the human sequence (+15)")
        else:
            feedback_parts.append("Extracted helix is NOT a substring of the human sequence (0)")
    elif extracted_helix_seq:
        c4 += 5
        feedback_parts.append("Extracted helix exists but could not validate against human sequence (+5)")
    score += c4

    # --- Criterion 5: Summary Report Accuracy (20 points) ---
    c5 = 0
    if report_data.get('exists') and report_data.get('created_during_task'):
        content = decode_b64(report_data.get('content_b64', ''))
        
        # Regex search for counts
        h_match = re.search(r'(?i)(?:helices|helix|alpha[ -]helix).*?(\d+)', content)
        s_match = re.search(r'(?i)(?:sheets|sheet|strands|strand|beta[ -]strand).*?(\d+)', content)
        l_match = re.search(r'(?i)(?:length|amino acids|aa).*?(\d+)', content)

        rep_helices = int(h_match.group(1)) if h_match else -1
        rep_sheets = int(s_match.group(1)) if s_match else -1
        rep_length = int(l_match.group(1)) if l_match else -1

        sub_c5 = 5  # Base 5 pts for existing with content
        if len(helices) > 0 and rep_helices == len(helices):
            sub_c5 += 5
        if len(sheets) > 0 and rep_sheets == len(sheets):
            sub_c5 += 5
        if expected_helix_len > 0 and rep_length == expected_helix_len:
            sub_c5 += 5
        
        c5 = min(20, sub_c5)
        feedback_parts.append(f"Summary report evaluation: H({rep_helices}/{len(helices)}), S({rep_sheets}/{len(sheets)}), L({rep_length}/{expected_helix_len}) (+{c5})")
    else:
        feedback_parts.append("Summary report missing or not created during task (0)")
    score += c5

    passed = score >= 75 and anti_gaming_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }