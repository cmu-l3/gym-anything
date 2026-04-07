#!/usr/bin/env python3
"""
Verifier for corsi_spatial_span_analysis task.

Scoring (100 pts total):
  1. Output file exists and was created during task (anti-gaming)  (10 pts)
  2. sub-X99 correctly identified and excluded                     (20 pts)
  3. All 20 real participants present in report                    (10 pts)
  4. Forward spans within ±1 for ≥16 of 20 participants            (20 pts)
  5. Backward spans within ±1 for ≥16 of 20 participants           (15 pts)
  6. Forward product scores within ±10 for ≥14 of 20 participants  (10 pts)
  7. Backward product scores within ±10 for ≥14 of 20 participants (5 pts)
  8. Group mean forward span correct (±0.5)                        (5 pts)
  9. Group mean backward span correct (±0.5)                       (5 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED_ID = "sub-X99"
EXPECTED_REAL_COUNT = 20

def verify_corsi_spatial_span_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load export metadata (for anti-gaming check)
    metadata = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_meta_path = tmp.name
    try:
        copy_from_env('/tmp/task_export_metadata.json', tmp_meta_path)
        with open(tmp_meta_path, 'r') as f:
            metadata = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export metadata: {e}")
    finally:
        if os.path.exists(tmp_meta_path):
            os.unlink(tmp_meta_path)

    if not metadata.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not metadata.get("file_created_during_task", False):
        feedback_parts.append("[0] File exists but was not created/modified during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 2. Load Ground Truth
    gt_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_gt_path = tmp.name
    try:
        copy_from_env('/tmp/corsi_ground_truth.json', tmp_gt_path)
        with open(tmp_gt_path, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt_path):
            os.unlink(tmp_gt_path)
            
    group_means_gt = gt_data.pop("_GROUP_MEANS", {})

    # 3. Load Agent's Report
    report_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_report_path = tmp.name
    try:
        copy_from_env('/home/ga/pebl/analysis/corsi_span_report.json', tmp_report_path)
        with open(tmp_report_path, 'r') as f:
            report_data = json.load(f)
        score += 10
        feedback_parts.append("[+10] Report is valid JSON and created during task.")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Report is not valid JSON: {e}"}
    finally:
        if os.path.exists(tmp_report_path):
            os.unlink(tmp_report_path)

    # Convert participant list to map
    part_map = {}
    for entry in report_data.get("participants", []):
        pid = entry.get("id") or entry.get("participant_id")
        if pid:
            part_map[str(pid)] = entry

    # Function to check exclusion
    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get("excluded") in (True, "true", 1, "yes"):
            return True
        top_excluded = report_data.get("excluded", [])
        if isinstance(top_excluded, list) and pid in top_excluded:
            return True
        return False

    # Criterion: Check sub-X99 exclusion
    if is_excluded(CONTAMINATED_ID):
        score += 20
        feedback_parts.append(f"[+20] {CONTAMINATED_ID} correctly excluded.")
    else:
        feedback_parts.append(f"[0] {CONTAMINATED_ID} not excluded despite impossible data.")

    # Criterion: All 20 real participants present
    real_pids = set(gt_data.keys())
    present_pids = set(part_map.keys()).intersection(real_pids)
    if len(present_pids) == EXPECTED_REAL_COUNT:
        score += 10
        feedback_parts.append(f"[+10] All {EXPECTED_REAL_COUNT} valid participants included.")
    else:
        feedback_parts.append(f"[0] Only {len(present_pids)}/{EXPECTED_REAL_COUNT} valid participants included.")

    # Track metrics
    correct_f_span = 0
    correct_b_span = 0
    correct_f_prod = 0
    correct_b_prod = 0

    for pid in real_pids:
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
        
        gt = gt_data.get(pid, {})
        
        # Safe extraction function
        def extract_val(keys):
            for k in keys:
                if k in entry and entry[k] is not None:
                    try:
                        return float(entry[k])
                    except (ValueError, TypeError):
                        pass
            return None

        # Check Forward Span
        f_span = extract_val(["forward_span", "f_span", "span_forward"])
        if f_span is not None and abs(f_span - gt.get("forward_span", 0)) <= 1.0:
            correct_f_span += 1
            
        # Check Backward Span
        b_span = extract_val(["backward_span", "b_span", "span_backward"])
        if b_span is not None and abs(b_span - gt.get("backward_span", 0)) <= 1.0:
            correct_b_span += 1
            
        # Check Forward Product
        f_prod = extract_val(["forward_product_score", "forward_product", "f_product"])
        if f_prod is not None and abs(f_prod - gt.get("forward_product_score", 0)) <= 10.0:
            correct_f_prod += 1
            
        # Check Backward Product
        b_prod = extract_val(["backward_product_score", "backward_product", "b_product"])
        if b_prod is not None and abs(b_prod - gt.get("backward_product_score", 0)) <= 10.0:
            correct_b_prod += 1

    # Apply scores
    if correct_f_span >= 16:
        score += 20
        feedback_parts.append(f"[+20] Forward spans correct for {correct_f_span}/20.")
    elif correct_f_span >= 10:
        score += 10
        feedback_parts.append(f"[+10] Forward spans correct for {correct_f_span}/20 (partial).")
    else:
        feedback_parts.append(f"[0] Forward spans correct for {correct_f_span}/20.")

    if correct_b_span >= 16:
        score += 15
        feedback_parts.append(f"[+15] Backward spans correct for {correct_b_span}/20.")
    elif correct_b_span >= 10:
        score += 7
        feedback_parts.append(f"[+7] Backward spans correct for {correct_b_span}/20 (partial).")
    else:
        feedback_parts.append(f"[0] Backward spans correct for {correct_b_span}/20.")

    if correct_f_prod >= 14:
        score += 10
        feedback_parts.append(f"[+10] Forward products correct for {correct_f_prod}/20.")
    else:
        feedback_parts.append(f"[0] Forward products correct for {correct_f_prod}/20.")

    if correct_b_prod >= 14:
        score += 5
        feedback_parts.append(f"[+5] Backward products correct for {correct_b_prod}/20.")
    else:
        feedback_parts.append(f"[0] Backward products correct for {correct_b_prod}/20.")

    # Group Means
    def get_group_mean(keys):
        for k in keys:
            if k in report_data and report_data[k] is not None:
                try:
                    return float(report_data[k])
                except (ValueError, TypeError):
                    pass
        return None

    g_f_span = get_group_mean(["group_forward_span_mean", "mean_forward_span"])
    if g_f_span is not None and abs(g_f_span - group_means_gt.get("group_forward_span_mean", 0)) <= 0.5:
        score += 5
        feedback_parts.append("[+5] Group forward span mean correct.")
    else:
        feedback_parts.append("[0] Group forward span mean incorrect/missing.")

    g_b_span = get_group_mean(["group_backward_span_mean", "mean_backward_span"])
    if g_b_span is not None and abs(g_b_span - group_means_gt.get("group_backward_span_mean", 0)) <= 0.5:
        score += 5
        feedback_parts.append("[+5] Group backward span mean correct.")
    else:
        feedback_parts.append("[0] Group backward span mean incorrect/missing.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }