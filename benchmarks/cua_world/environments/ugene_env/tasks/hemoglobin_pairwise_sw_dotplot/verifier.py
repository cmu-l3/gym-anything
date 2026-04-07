#!/usr/bin/env python3
"""Verifier for hemoglobin_pairwise_sw_dotplot task.

Scoring breakdown:
  Human FASTA extracted:       10
  Chicken FASTA extracted:     10
  Correct sequence lengths:    10
  Alignment file exists:       10
  Alignment has 2 sequences:   10
  Alignment contains gaps:     5
  Dotplot image exists:        10
  Report file exists:          5
  Report has sequence lengths: 5
  Report has identity %:       10
  Report has gap count:        5
  Report has interpretation:   10
                       TOTAL = 100
"""

import json
import os
import re
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_b64(b64_str):
    try:
        return base64.b64decode(b64_str).decode('utf-8')
    except Exception:
        return ""

def count_fasta_sequences(content):
    return len(re.findall(r'^>', content, re.MULTILINE))

def extract_fasta_sequence(content):
    lines = content.strip().split('\n')
    seq = ""
    for line in lines:
        if not line.startswith(">"):
            seq += line.strip()
    return seq

def count_alignment_sequences(content):
    # Try ClustalW format (also matches MUSCLE, MAFFT generated formats)
    if "CLUSTAL" in content.upper() or "MUSCLE" in content.upper() or "MAFFT" in content.upper():
        seq_names = set()
        for line in content.split('\n'):
            line = line.strip()
            if line and not line.startswith("CLUSTAL") and not line.startswith("MUSCLE") and not line.startswith("MAFFT") and not line.startswith("*") and not line.startswith(" "):
                parts = line.split()
                if len(parts) >= 2:
                    seq_names.add(parts[0])
        if len(seq_names) > 0:
            return len(seq_names)
            
    # Try FASTA alignment format or MEGA format
    count = count_fasta_sequences(content)
    if count > 0:
        return count
        
    return 0

def has_gap_character(content):
    return "-" in content or "." in content

def verify_hemoglobin_pairwise_sw_dotplot(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read the exported result JSON
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}. Agent likely did not complete the task."
        }
        
    # --- Check Human FASTA (10 pts) ---
    human_fasta_exists = result.get('human_fasta_exists', False)
    human_fasta_content = decode_b64(result.get('human_fasta_content_b64', ''))
    human_seq = extract_fasta_sequence(human_fasta_content)
    human_len = len(re.sub(r'[^a-zA-Z]', '', human_seq))
    
    if human_fasta_exists:
        if "P68871" in human_fasta_content or "HBB_HUMAN" in human_fasta_content:
            score += 10
            feedback_parts.append("Human FASTA extracted correctly (+10)")
        elif human_len > 0:
            score += 5
            feedback_parts.append("Human FASTA extracted but missing correct header (+5)")
        else:
            feedback_parts.append("Human FASTA is empty (0)")
    else:
        feedback_parts.append("Human FASTA missing (0)")
        
    # --- Check Chicken FASTA (10 pts) ---
    chicken_fasta_exists = result.get('chicken_fasta_exists', False)
    chicken_fasta_content = decode_b64(result.get('chicken_fasta_content_b64', ''))
    chicken_seq = extract_fasta_sequence(chicken_fasta_content)
    chicken_len = len(re.sub(r'[^a-zA-Z]', '', chicken_seq))
    
    if chicken_fasta_exists:
        if "P02112" in chicken_fasta_content or "HBB_CHICK" in chicken_fasta_content:
            score += 10
            feedback_parts.append("Chicken FASTA extracted correctly (+10)")
        elif chicken_len > 0:
            score += 5
            feedback_parts.append("Chicken FASTA extracted but missing correct header (+5)")
        else:
            feedback_parts.append("Chicken FASTA is empty (0)")
    else:
        feedback_parts.append("Chicken FASTA missing (0)")
        
    # --- Check Sequence Lengths (10 pts) ---
    if human_len > 0 and chicken_len > 0:
        if 140 <= human_len <= 155 and 140 <= chicken_len <= 155:
            score += 10
            feedback_parts.append(f"Correct sequence lengths (Human={human_len}, Chicken={chicken_len}) (+10)")
        else:
            feedback_parts.append(f"Incorrect sequence lengths (Human={human_len}, Chicken={chicken_len}) (0)")
    else:
        feedback_parts.append("Cannot verify sequence lengths (0)")
        
    # --- Check Alignment File (10 + 10 + 5 pts) ---
    aln_exists = result.get('aln_exists', False)
    aln_content = decode_b64(result.get('aln_content_b64', ''))
    
    if aln_exists and aln_content.strip():
        score += 10
        feedback_parts.append("Alignment file exists (+10)")
        
        num_seqs = count_alignment_sequences(aln_content)
        if num_seqs == 2:
            score += 10
            feedback_parts.append("Alignment has exactly 2 sequences (+10)")
        elif num_seqs > 2:
            score += 5
            feedback_parts.append(f"Alignment has {num_seqs} sequences (expected 2) (+5)")
        else:
            feedback_parts.append("Alignment sequence count could not be verified (0)")
            
        if has_gap_character(aln_content):
            score += 5
            feedback_parts.append("Alignment contains gaps (+5)")
        else:
            feedback_parts.append("No gaps found in alignment (0)")
    else:
        feedback_parts.append("Alignment file missing or empty (0)")
        
    # --- Check Dotplot Image (10 pts) ---
    dotplot_exists = result.get('dotplot_exists', False)
    dotplot_size = result.get('dotplot_size_bytes', 0)
    
    if dotplot_exists:
        if dotplot_size > 5000:  # > 5KB to exclude trivial icons or empty images
            score += 10
            feedback_parts.append(f"Dotplot image exists and is valid size ({dotplot_size} bytes) (+10)")
        else:
            score += 5
            feedback_parts.append(f"Dotplot image exists but is very small ({dotplot_size} bytes) (+5)")
    else:
        feedback_parts.append("Dotplot image missing (0)")
        
    # --- Check Report File (5 + 5 + 10 + 5 + 10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = decode_b64(result.get('report_content_b64', '')).lower()
    
    if report_exists and report_content.strip():
        score += 5
        feedback_parts.append("Report file exists (+5)")
        
        # Check lengths mentioned
        if "147" in report_content or "146" in report_content or "length" in report_content:
            score += 5
            feedback_parts.append("Report mentions sequence lengths (+5)")
        
        # Check identity
        if "identit" in report_content or "similarity" in report_content or "%" in report_content:
            # Look for numbers between 55 and 80 followed by optional %
            identity_match = re.search(r'([5-8][0-9](?:\.[0-9]+)?)\s*%', report_content)
            if identity_match:
                val = float(identity_match.group(1))
                if 55 <= val <= 80:
                    score += 10
                    feedback_parts.append(f"Report has correct identity % ({val}%) (+10)")
                else:
                    score += 5
                    feedback_parts.append(f"Report has identity % but outside expected range ({val}%) (+5)")
            else:
                score += 5
                feedback_parts.append("Report mentions identity but no clear % found (+5)")
        else:
            feedback_parts.append("Report missing identity % (0)")
        
        # Check gaps
        if "gap" in report_content or "insertion" in report_content or "deletion" in report_content or "indel" in report_content:
            score += 5
            feedback_parts.append("Report mentions gaps (+5)")
            
        # Check interpretation
        interpretation_words = ["conserved", "collinear", "similar", "homolog", "alignment", "score", "blosum", "diagonal"]
        word_count = sum(1 for word in interpretation_words if word in report_content)
        if word_count >= 2:
            score += 10
            feedback_parts.append("Report has sufficient interpretation (+10)")
        elif word_count == 1:
            score += 5
            feedback_parts.append("Report has minimal interpretation (+5)")
        else:
            feedback_parts.append("Report lacks interpretation (0)")
    else:
        feedback_parts.append("Report file missing or empty (0)")
        
    passed = score >= 60 and aln_exists and (human_fasta_exists or chicken_fasta_exists)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }