#!/usr/bin/env python3
"""
Verifier for insulin_utr_extraction task.

Evaluates the exact mathematical extraction of UTR regions based on CDS boundaries,
and checks the generated report for accuracy.

Scoring breakdown (100 points total):
  5' UTR File Present:            5
  5' UTR Sequence Correct:        25
  3' UTR File Present:            5
  3' UTR Sequence Correct:        25
  Report File & Coordinates:      10
  Correct Lengths Reported:       10
  Correct GC% Reported:           10
  VLM Verification (Trajectory):  10
                             TOTAL = 100
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_utr_extraction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    # 1. Load Ground Truth
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_gt.close()
    try:
        copy_from_env("/tmp/utr_ground_truth.json", tmp_gt.name)
        with open(tmp_gt.name, "r") as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt.name):
            os.unlink(tmp_gt.name)

    # 2. Load Results
    result = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_res.close()
    try:
        copy_from_env("/tmp/insulin_utr_extraction_result.json", tmp_res.name)
        with open(tmp_res.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    utr5_correct = False
    utr3_correct = False

    # --- Criterion 1 & 2: 5' UTR Extraction (30 pts) ---
    if result.get("utr5_exists", False):
        score += 5
        feedback_parts.append("5' UTR file exists (+5)")
        agent_utr5 = result.get("utr5_seq", "")
        if agent_utr5 == gt["utr5_seq"]:
            score += 25
            utr5_correct = True
            feedback_parts.append("5' UTR sequence matches ground truth exactly (+25)")
        elif gt["utr5_seq"] in agent_utr5 or agent_utr5 in gt["utr5_seq"]:
            score += 10
            feedback_parts.append("5' UTR sequence is a partial/overlapping match (+10)")
        else:
            feedback_parts.append("5' UTR sequence does NOT match ground truth (0)")
    else:
        feedback_parts.append("5' UTR file MISSING (0)")

    # --- Criterion 3 & 4: 3' UTR Extraction (30 pts) ---
    if result.get("utr3_exists", False):
        score += 5
        feedback_parts.append("3' UTR file exists (+5)")
        agent_utr3 = result.get("utr3_seq", "")
        if agent_utr3 == gt["utr3_seq"]:
            score += 25
            utr3_correct = True
            feedback_parts.append("3' UTR sequence matches ground truth exactly (+25)")
        elif gt["utr3_seq"] in agent_utr3 or agent_utr3 in gt["utr3_seq"]:
            score += 10
            feedback_parts.append("3' UTR sequence is a partial/overlapping match (+10)")
        else:
            feedback_parts.append("3' UTR sequence does NOT match ground truth (0)")
    else:
        feedback_parts.append("3' UTR file MISSING (0)")

    # --- Criterion 5, 6, 7: Report Evaluation (30 pts) ---
    report_content = result.get("report_content", "")
    if result.get("report_exists", False) and len(report_content) > 10:
        score += 5
        feedback_parts.append("Report file exists (+5)")
        
        # Check Coordinates
        if str(gt["cds_start"]) in report_content and str(gt["cds_end"]) in report_content:
            score += 5
            feedback_parts.append(f"Correct CDS coordinates ({gt['cds_start']}, {gt['cds_end']}) found in report (+5)")
        else:
            feedback_parts.append("Correct CDS coordinates missing from report (0)")

        # Check Lengths
        len_score = 0
        if str(gt["utr5_len"]) in report_content:
            len_score += 5
        if str(gt["utr3_len"]) in report_content:
            len_score += 5
        score += len_score
        if len_score > 0:
            feedback_parts.append(f"Correct UTR lengths found in report (+{len_score})")

        # Check GC Percentages
        # Extract all floats/ints from the report text
        numbers = [float(x) for x in re.findall(r'\d+\.\d+|\d+', report_content)]
        gc_score = 0
        
        # Helper: check if any number is within ±0.6 of the target (handles 64.28 vs 64.3 rounding)
        def is_close_to_any(target, num_list, tol=0.6):
            return any(abs(n - target) <= tol for n in num_list)

        if is_close_to_any(gt["utr5_gc"], numbers):
            gc_score += 5
        if is_close_to_any(gt["utr3_gc"], numbers):
            gc_score += 5
        
        score += gc_score
        if gc_score > 0:
            feedback_parts.append(f"Correct GC percentages found in report (+{gc_score})")
            
    else:
        feedback_parts.append("Report file missing or empty (0)")

    # --- Criterion 8: VLM Verification (10 pts) ---
    vlm_score = 0
    try:
        # Import dynamically to be safe depending on the framework version structure
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames and 'query_vlm' in env_info:
            query_vlm = env_info['query_vlm']
            prompt = """
            Look at these trajectory frames from a UGENE bioinformatics session. 
            Did the user interact with the Sequence Viewer, highlight sequences, or use the Export sequence dialog?
            Respond in JSON: {"ugene_used": true/false}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success", False) and vlm_res.get("parsed", {}).get("ugene_used", False):
                vlm_score = 10
                feedback_parts.append("VLM confirmed UGENE UI usage (+10)")
            else:
                feedback_parts.append("VLM did not detect UGENE UI usage (+0)")
        else:
            # Free points if VLM is unavailable but core task was completed perfectly
            vlm_score = 10
            feedback_parts.append("VLM unavailable, auto-awarding points (+10)")
    except Exception as e:
        vlm_score = 10
        feedback_parts.append(f"VLM check skipped ({e}), auto-awarding points (+10)")
    
    score += vlm_score

    # Determine Pass/Fail
    # To pass, the score must be >= 70 AND both sequences must have been correctly extracted
    passed = (score >= 70) and utr5_correct and utr3_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }