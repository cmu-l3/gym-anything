#!/usr/bin/env python3
"""
Verifier for matrix_reasoning_ctt_analysis task.

Scoring (100 pts total):
  1. Output file exists and parses as JSON                   (10 pts)
  2. Speeding participant correctly identified and excluded  (15 pts)
  3. Miskeyed item correctly identified (negative CITC)      (20 pts)
  4. Cronbach's alpha within ±0.015 of ground truth          (25 pts)
  5. Item stats match ground truth for ≥28 items             (30 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile

PASS_THRESHOLD = 60
TOLERANCE = 0.015

def verify_matrix_reasoning_ctt_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Execution environment missing copy_from_env"}

    # --- Load Ground Truth ---
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        tmp_gt_path = tmp_gt.name

    try:
        copy_from_env('/tmp/ground_truth.json', tmp_gt_path)
        with open(tmp_gt_path, encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt_path):
            os.unlink(tmp_gt_path)

    # --- Load Agent Report ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_rep:
        tmp_rep_path = tmp_rep.name

    try:
        copy_from_env('/home/ga/pebl/analysis/item_analysis_report.json', tmp_rep_path)
        with open(tmp_rep_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/item_analysis_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file is not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(tmp_rep_path):
            os.unlink(tmp_rep_path)

    # --- Criterion 2: Excluded Participants ---
    gt_excluded = set(gt.get('excluded_participants', []))
    ag_excluded = set(report.get('excluded_participants', []))
    
    if gt_excluded == ag_excluded and len(gt_excluded) > 0:
        score += 15
        feedback_parts.append(f"[+15] Speeding participant {list(gt_excluded)} correctly excluded.")
    else:
        feedback_parts.append(f"[0] Excluded participants incorrect. Expected {list(gt_excluded)}, got {list(ag_excluded)}.")

    # --- Criterion 3: Miskeyed Item Identified ---
    gt_bad_item = gt.get('bad_item', {}).get('item_id')
    ag_bad_item_obj = report.get('bad_item', {})
    
    # Handle if agent provided dict or just int
    if isinstance(ag_bad_item_obj, dict):
        ag_bad_item = ag_bad_item_obj.get('item_id')
    else:
        ag_bad_item = ag_bad_item_obj

    if gt_bad_item and str(ag_bad_item) == str(gt_bad_item):
        score += 20
        feedback_parts.append(f"[+20] Miskeyed Item {gt_bad_item} correctly identified.")
    else:
        feedback_parts.append(f"[0] Miskeyed item incorrect. Expected {gt_bad_item}, got {ag_bad_item}.")

    # --- Criterion 4: Cronbach's Alpha ---
    gt_alpha = float(gt.get('cronbach_alpha', 0))
    ag_alpha = report.get('cronbach_alpha')
    
    if ag_alpha is not None:
        try:
            diff = abs(float(ag_alpha) - gt_alpha)
            if diff <= TOLERANCE:
                score += 25
                feedback_parts.append(f"[+25] Cronbach's alpha ({float(ag_alpha):.3f}) within tolerance.")
            else:
                feedback_parts.append(f"[0] Cronbach's alpha {ag_alpha} out of bounds (expected {gt_alpha}).")
        except (ValueError, TypeError):
            feedback_parts.append("[0] Cronbach's alpha is not a valid number.")
    else:
        feedback_parts.append("[0] Cronbach's alpha missing from report.")

    # --- Criterion 5: Item Statistics ---
    correct_items = 0
    ag_items_list = report.get('items', [])
    if isinstance(ag_items_list, list):
        ag_items = {str(item.get('item_id')): item for item in ag_items_list if isinstance(item, dict)}
        
        for gt_item in gt.get('items', []):
            item_id = str(gt_item['item_id'])
            ag_item = ag_items.get(item_id)
            if not ag_item:
                continue
            
            try:
                diff_ok = abs(float(ag_item.get('difficulty', -99)) - gt_item['difficulty']) <= TOLERANCE
                citc_ok = abs(float(ag_item.get('corrected_item_total_correlation', -99)) - gt_item['corrected_item_total_correlation']) <= TOLERANCE
                if diff_ok and citc_ok:
                    correct_items += 1
            except (TypeError, ValueError):
                pass

    if correct_items >= 28:
        score += 30
        feedback_parts.append(f"[+30] Item statistics correct for {correct_items}/30 items.")
    elif correct_items >= 15:
        score += 15
        feedback_parts.append(f"[+15] Item statistics correct for {correct_items}/30 items (partial).")
    else:
        feedback_parts.append(f"[0] Item statistics correct for only {correct_items}/30 items.")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }