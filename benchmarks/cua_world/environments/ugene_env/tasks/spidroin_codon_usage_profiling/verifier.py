#!/usr/bin/env python3
"""
Verifier for spidroin_codon_usage_profiling task.
"""

import json
import os
import tempfile

def verify_spidroin_codon_usage_profiling(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    res = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_res.close()
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # Load ground truth
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt.close()
    try:
        copy_from_env("/tmp/spidroin_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_len = gt.get("protein_length", 374)
    gt_top_gly = gt.get("top_gly_codon", "GGA")
    gt_top_ala = gt.get("top_ala_codon", "GCA")

    # Criterion 1: Protein FASTA exists (15 points)
    if res.get("fasta_exists") and res.get("fasta_valid"):
        score += 15
        feedback_parts.append("FASTA file valid (+15)")
    else:
        feedback_parts.append("FASTA file missing or invalid")

    # Criterion 2: Correct Translation (20 points)
    p_len = res.get("protein_length", 0)
    frac = res.get("gly_ala_fraction", 0.0)
    if p_len > 0:
        if abs(p_len - gt_len) <= 5 and frac > 0.4:
            score += 20
            feedback_parts.append(f"Translation correct ({p_len} aa, {frac*100:.1f}% Gly/Ala) (+20)")
        else:
            feedback_parts.append(f"Translation incorrect ({p_len} aa, {frac*100:.1f}% Gly/Ala)")
    else:
        feedback_parts.append("Translation missing")

    # Criterion 3: Codon Table exists (15 points)
    if res.get("codon_table_exists"):
        if res.get("codon_table_has_64"):
            score += 15
            feedback_parts.append("Codon table exported with 64 codons (+15)")
        else:
            score += 5
            feedback_parts.append("Codon table exported but appears incomplete (+5)")
    else:
        feedback_parts.append("Codon table missing")

    # Criterion 4: Report Format (10 points)
    if res.get("report_exists"):
        lines = res.get("report_lines_found", 0)
        if lines == 4:
            score += 10
            feedback_parts.append("Report has correct 4 lines format (+10)")
        elif lines > 0:
            score += 5
            feedback_parts.append(f"Report has partial formatting ({lines}/4 lines) (+5)")
        else:
            feedback_parts.append("Report exists but format incorrect")
    else:
        feedback_parts.append("Report missing")

    # Criterion 5: Identifies Glycine (10 points)
    abundant = res.get("reported_abundant_aa")
    if abundant and abundant.upper() in ["GLYCINE", "GLY", "G"]:
        score += 10
        feedback_parts.append("Glycine correctly identified (+10)")
    elif abundant:
        feedback_parts.append(f"Incorrect abundant AA reported: {abundant}")

    # Criterion 6: Correct Gly Codon (15 points)
    rep_gly = res.get("reported_gly_codon")
    if rep_gly:
        if rep_gly.replace('U', 'T') == gt_top_gly.replace('U', 'T'):
            score += 15
            feedback_parts.append(f"Correct Gly codon: {rep_gly} (+15)")
        else:
            feedback_parts.append(f"Incorrect Gly codon: {rep_gly} (expected {gt_top_gly})")

    # Criterion 7: Correct Ala Codon (15 points)
    rep_ala = res.get("reported_ala_codon")
    if rep_ala:
        if rep_ala.replace('U', 'T') == gt_top_ala.replace('U', 'T'):
            score += 15
            feedback_parts.append(f"Correct Ala codon: {rep_ala} (+15)")
        else:
            feedback_parts.append(f"Incorrect Ala codon: {rep_ala} (expected {gt_top_ala})")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }