#!/usr/bin/env python3
"""
Verifier for HBB Intron Extraction task.

Scoring system (100 points total):
  - Annotated GenBank Exists: 10 pts
  - Intron Annotations Present: 15 pts
  - Coordinate Arithmetic Correct: 25 pts (Checks calculated boundaries)
  - Intron 1 FASTA Content: 15 pts (Exact sequence match)
  - Intron 2 FASTA Content: 15 pts (Exact sequence match)
  - Statistics Report Accuracy: 20 pts (Checks length and GC% computation)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hbb_intron_extraction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported results
    result = {}
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_res.close()
        copy_from_env("/tmp/hbb_intron_extraction_result.json", tmp_res.name)
        with open(tmp_res.name, "r") as f:
            result = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}. Export failed or agent did no work."
        }

    # 2. Load Ground Truth metrics
    gt = {}
    try:
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_gt.close()
        copy_from_env("/tmp/hbb_intron_gt.json", tmp_gt.name)
        with open(tmp_gt.name, "r") as f:
            gt = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read Ground Truth metrics: {e}. Framework error."
        }

    # --- Criterion 1: Annotated GenBank Exists (10 pts) ---
    c1 = 0
    if result.get("gb_exists"):
        c1 = 10
        feedback_parts.append("GenBank file exported successfully (+10)")
    else:
        feedback_parts.append("GenBank file missing (0)")
    score += c1
    subscores["gb_exists"] = c1

    # --- Criterion 2: Intron Annotations Present (15 pts) ---
    c2 = 0
    gb_content = result.get("gb_content", "")
    if result.get("has_intron_keyword"):
        c2 = 15
        feedback_parts.append("'intron' annotations found in GB file (+15)")
    else:
        feedback_parts.append("No 'intron' annotations found in GB file (0)")
    score += c2
    subscores["intron_annotations"] = c2

    # --- Criterion 3: Coordinate Arithmetic Correct (25 pts) ---
    c3 = 0
    i1_target = f"{gt['i1_start']}..{gt['i1_end']}"
    i2_target = f"{gt['i2_start']}..{gt['i2_end']}"

    # Verify both calculated coordinate blocks actually exist in the GB file
    has_i1_coords = i1_target in gb_content
    has_i2_coords = i2_target in gb_content

    if has_i1_coords and has_i2_coords:
        c3 = 25
        feedback_parts.append("Both intron coordinate boundaries perfectly calculated and annotated (+25)")
    elif has_i1_coords or has_i2_coords:
        c3 = 12
        feedback_parts.append("Only one intron coordinate boundary accurately calculated (+12)")
    else:
        feedback_parts.append("Coordinate arithmetic incorrect; expected boundaries not found (0)")
    score += c3
    subscores["coordinate_arithmetic"] = c3

    # --- Criterion 4: Intron 1 FASTA Content (15 pts) ---
    c4 = 0
    f1_seq = result.get("fasta1_seq", "")
    if f1_seq == gt["i1_seq"].upper():
        c4 = 15
        feedback_parts.append("Intron 1 exact sequence matched (+15)")
    elif f1_seq:
        c4 = 5
        feedback_parts.append("Intron 1 FASTA generated but sequence does not perfectly match (+5)")
    else:
        feedback_parts.append("Intron 1 FASTA missing or empty (0)")
    score += c4
    subscores["fasta1"] = c4

    # --- Criterion 5: Intron 2 FASTA Content (15 pts) ---
    c5 = 0
    f2_seq = result.get("fasta2_seq", "")
    if f2_seq == gt["i2_seq"].upper():
        c5 = 15
        feedback_parts.append("Intron 2 exact sequence matched (+15)")
    elif f2_seq:
        c5 = 5
        feedback_parts.append("Intron 2 FASTA generated but sequence does not perfectly match (+5)")
    else:
        feedback_parts.append("Intron 2 FASTA missing or empty (0)")
    score += c5
    subscores["fasta2"] = c5

    # --- Criterion 6: Statistics Report Accuracy (20 pts) ---
    c6 = 0
    report_content = result.get("report_content", "")
    if result.get("report_exists") and report_content.strip():
        # Parse numbers from the report
        numbers_str = re.findall(r'\d+\.?\d*', report_content)
        floats = [float(n) for n in numbers_str]

        has_len1 = any(abs(f - gt["i1_len"]) < 0.1 for f in floats)
        has_len2 = any(abs(f - gt["i2_len"]) < 0.1 for f in floats)
        has_gc1 = any(abs(f - gt["i1_gc"]) <= 1.5 for f in floats)  # Allow small rounding differences
        has_gc2 = any(abs(f - gt["i2_gc"]) <= 1.5 for f in floats)

        c6_sub = sum([has_len1 * 5, has_len2 * 5, has_gc1 * 5, has_gc2 * 5])
        c6 = int(c6_sub)
        feedback_parts.append(f"Statistics report found with score {c6}/20 (+{c6})")
    else:
        feedback_parts.append("Statistics report missing or empty (0)")
    score += c6
    subscores["statistics_report"] = c6

    # --- Final Pass/Fail evaluation ---
    # Require at least one sequence to be 100% extracted properly, plus good coordinate math
    key_criteria_met = (c3 >= 12) and (c4 == 15 or c5 == 15)
    passed = (score >= 75) and key_criteria_met

    if not passed and score >= 75:
        feedback_parts.append("FAILED: Key criteria not met (Requires correct arithmetic and at least one perfect sequence extraction).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }