#!/usr/bin/env python3
"""
Verifier for audiovisual_toj_psychometric_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                   (10 pts)
  2. Degenerate sub-99 correctly excluded                   (15 pts)
  3. PSS accuracy (±5.0ms) for ≥12 valid participants       (20 pts)
  4. JND accuracy (±5.0ms) for ≥12 valid participants       (15 pts)
  5. Group means (PSS and JND) within ±2.0ms                (15 pts)
  6. VLM Trajectory (shows code execution & curve fitting)  (25 pts)

Pass threshold: 60 pts AND key criteria met.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED = 'sub-99'
TOLERANCE_MS = 5.0
GROUP_TOLERANCE_MS = 2.0
PASS_THRESHOLD = 60

VLM_PROMPT = """You are verifying an agent completing a data analysis task. The agent was required to fit nonlinear logistic psychometric curves to behavioral data to extract PSS and JND thresholds.

Review these trajectory screenshots sampled chronologically from the task execution.
Determine if the agent actually wrote and executed code (e.g., Python, R) to perform the curve fitting.

Look for:
- Text editors or IDEs containing optimization/fitting logic (like `scipy.optimize.curve_fit`, `statsmodels`, or custom gradient descent).
- Terminals showing code execution or output logs with parameter estimates.
- Plots showing psychometric curves (S-shaped curves) or raw data points.

Respond ONLY in valid JSON format:
{
    "code_execution_visible": true/false,
    "curve_fitting_logic_present": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what was observed"
}"""

def verify_toj_psychometric_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # --- Load Ground Truth ---
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_tmp_path = tmp.name
    try:
        copy_from_env('/tmp/toj_ground_truth.json', gt_tmp_path)
        with open(gt_tmp_path, encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(gt_tmp_path): os.unlink(gt_tmp_path)

    # --- Criterion 1: Output File is Valid JSON (10 pts) ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        rep_tmp_path = tmp.name
    try:
        copy_from_env('/home/ga/pebl/analysis/toj_report.json', rep_tmp_path)
        with open(rep_tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback.append("[+10] Output file found and is valid JSON.")
    except FileNotFoundError:
        feedback.append("[0] Output file /home/ga/pebl/analysis/toj_report.json not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback.append(f"[0] Output file is not valid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    finally:
        if os.path.exists(rep_tmp_path): os.unlink(rep_tmp_path)

    part_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'): return True
        return False

    # --- Criterion 2: Exclude degenerate sub-99 (15 pts) ---
    if is_excluded(CONTAMINATED) or CONTAMINATED not in part_map:
        score += 15
        feedback.append("[+15] sub-99 correctly excluded (degenerate flat responding).")
    else:
        feedback.append("[0] sub-99 not marked as excluded despite flat distribution.")

    # --- Criteria 3 & 4: PSS and JND Accuracy (20 pts, 15 pts) ---
    correct_pss = 0
    correct_jnd = 0
    total_valid = 15

    for pid in gt_data:
        if pid == 'group_means': continue
        
        gt_pss = gt_data[pid]['pss']
        gt_jnd = gt_data[pid]['jnd']
        
        entry = part_map.get(pid)
        if entry and not is_excluded(pid):
            pss = entry.get('pss_ms') or entry.get('pss')
            jnd = entry.get('jnd_ms') or entry.get('jnd')
            
            try:
                if pss is not None and abs(float(pss) - gt_pss) <= TOLERANCE_MS:
                    correct_pss += 1
                if jnd is not None and abs(float(jnd) - gt_jnd) <= TOLERANCE_MS:
                    correct_jnd += 1
            except (TypeError, ValueError):
                pass

    if correct_pss >= 12:
        score += 20
        feedback.append(f"[+20] PSS values accurate for {correct_pss}/15 valid participants.")
    elif correct_pss >= 6:
        score += 10
        feedback.append(f"[+10] PSS values accurate for {correct_pss}/15 (partial).")
    else:
        feedback.append(f"[0] PSS values accurate for only {correct_pss}/15 participants.")

    if correct_jnd >= 12:
        score += 15
        feedback.append(f"[+15] JND values accurate for {correct_jnd}/15 valid participants.")
    elif correct_jnd >= 6:
        score += 7
        feedback.append(f"[+7] JND values accurate for {correct_jnd}/15 (partial).")
    else:
        feedback.append(f"[0] JND values accurate for only {correct_jnd}/15 participants.")

    # --- Criterion 5: Group Means (15 pts) ---
    gt_group = gt_data['group_means']
    rpt_mean_pss = report.get('group_mean_pss_ms') or report.get('group_mean_pss')
    rpt_mean_jnd = report.get('group_mean_jnd_ms') or report.get('group_mean_jnd')
    
    means_score = 0
    try:
        if rpt_mean_pss is not None and abs(float(rpt_mean_pss) - gt_group['pss_ms']) <= GROUP_TOLERANCE_MS:
            means_score += 7.5
        if rpt_mean_jnd is not None and abs(float(rpt_mean_jnd) - gt_group['jnd_ms']) <= GROUP_TOLERANCE_MS:
            means_score += 7.5
    except (TypeError, ValueError):
        pass

    score += means_score
    if means_score == 15:
        feedback.append("[+15] Both group means (PSS and JND) accurate.")
    elif means_score == 7.5:
        feedback.append("[+7.5] Partial group means accurate.")
    else:
        feedback.append("[0] Group means missing or inaccurate.")

    # --- Criterion 6: VLM Trajectory Verification (25 pts) ---
    vlm_score = 0
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(trajectory, n=4)
        final = get_final_screenshot(trajectory)
        if final:
            frames.append(final)
            
        res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if res and res.get('success'):
            parsed = res.get('parsed', {})
            if parsed.get('code_execution_visible') and parsed.get('curve_fitting_logic_present'):
                vlm_score = 25
                feedback.append("[+25] VLM verified genuine code execution and curve fitting workflow.")
            else:
                feedback.append("[0] VLM did not observe genuine curve fitting logic. (Anti-gaming triggered)")
        else:
            feedback.append("[0] VLM query failed or returned no success.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback.append(f"[0] VLM check encountered an error: {e}")

    score += int(vlm_score)

    key_criteria_met = (correct_pss >= 8) or (correct_jnd >= 8)
    passed = (score >= PASS_THRESHOLD) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }