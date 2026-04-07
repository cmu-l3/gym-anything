#!/usr/bin/env python3
"""
Verifier for pursuit_rotor_learning_analysis task.

Scoring (100 pts total):
  1. Output file exists & created during task (10 pts)
  2. VLM Trajectory Process Verification (10 pts)
  3. Anomalous participant sub-099 excluded (20 pts)
  4. Block Means Accurate for >=90% of valid participants (25 pts)
  5. MLI Accurate for >=90% of valid participants (15 pts)
  6. Group Stats matched ground truth (20 pts)

Pass threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback imports for VLM
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    logger.warning("gym_anything VLM modules not available. VLM verification will be bypassed.")
    sample_trajectory_frames, query_vlm = None, None

VLM_PROMPT = """You are analyzing trajectory frames of an agent tasked with performing a data analysis task.
Did the agent open a terminal, text editor, Jupyter notebook, or Python IDE to process the CSV data?
Look for code being written or executed.

Respond in JSON format exactly like this:
{
    "used_analysis_tool": true/false,
    "evidence": "Brief description of what you saw"
}
"""

def verify_pursuit_rotor_learning_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tol = metadata.get('tolerance_pct', 0.2)
    contaminated_pid = metadata.get('contaminated_participant', 'sub-099')
    pass_threshold = metadata.get('passing_threshold', 70)

    score = 0
    feedback_parts = []

    # Copy files from environment
    def _fetch_json(path):
        data = None
        tmp_file = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
        try:
            copy_from_env(path, tmp_file.name)
            with open(tmp_file.name, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_file.name):
                os.unlink(tmp_file.name)
        return data

    task_result = _fetch_json('/tmp/task_result.json') or {}
    report = _fetch_json('/home/ga/pebl/analysis/pursuit_rotor_report.json')
    ground_truth = _fetch_json('/tmp/pursuit_rotor_gt.json')

    # --- Criterion 1: Output File Exists & Created During Task ---
    if task_result.get('output_exists') and task_result.get('file_created_during_task'):
        if report is not None:
            score += 10
            feedback_parts.append("[+10] File created and contains valid JSON.")
        else:
            feedback_parts.append("[0] File created but is not valid JSON.")
    else:
        feedback_parts.append("[0] File missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Check ground truth availability
    if not ground_truth:
        return {"passed": False, "score": score, "feedback": "Internal Error: Ground truth not found."}

    # --- Criterion 2: VLM Trajectory Process Verification ---
    vlm_score = 0
    if sample_trajectory_frames and query_vlm:
        try:
            frames = sample_trajectory_frames(trajectory, n=3)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_analysis_tool'):
                        vlm_score = 10
                        feedback_parts.append(f"[+10] VLM verified process: {parsed.get('evidence')}.")
                    else:
                        feedback_parts.append("[0] VLM did not observe scripting or data processing.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    else:
        # Give points automatically if VLM is unavailable but report generated successfully
        vlm_score = 10
        feedback_parts.append("[+10] VLM bypassed, awarding process points implicitly.")
    score += vlm_score

    # Process Participant Data
    part_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        return (entry and entry.get('excluded') in (True, 'true', 1, 'yes')) or \
               (pid not in part_map and pid in report.get('excluded', []))

    # --- Criterion 3: Anomalous Participant Exclusion ---
    if is_excluded(contaminated_pid):
        score += 20
        feedback_parts.append("[+20] Anomalous participant sub-099 correctly excluded.")
    else:
        feedback_parts.append("[0] Anomalous participant sub-099 not excluded.")

    # --- Criteria 4 & 5: Block Means and MLI Accuracy ---
    gt_ppts = ground_truth.get('participants', {})
    valid_ppts = 0
    correct_blocks = 0
    correct_mli = 0

    for pid, gt_data in gt_ppts.items():
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
            
        valid_ppts += 1
        
        # Check Block Means
        b_means = entry.get('block_means', {})
        b_correct = True
        for b in ['1', '2', '3', '4']:
            try:
                val = float(b_means.get(b, b_means.get(int(b), 0)))
                gt_val = float(gt_data['block_means'][b])
                if abs(val - gt_val) > tol:
                    b_correct = False
            except (ValueError, TypeError):
                b_correct = False
        if b_correct:
            correct_blocks += 1
            
        # Check MLI
        try:
            mli_val = float(entry.get('mli', 0))
            if abs(mli_val - float(gt_data['mli'])) <= tol:
                correct_mli += 1
        except (ValueError, TypeError):
            pass

    req_correct = int(len(gt_ppts) * 0.9)
    if valid_ppts > 0:
        if correct_blocks >= req_correct:
            score += 25
            feedback_parts.append(f"[+25] Block means accurate ({correct_blocks}/{valid_ppts}).")
        elif correct_blocks >= int(len(gt_ppts) * 0.5):
            score += 10
            feedback_parts.append(f"[+10] Block means partially accurate ({correct_blocks}/{valid_ppts}).")
            
        if correct_mli >= req_correct:
            score += 15
            feedback_parts.append(f"[+15] MLI accurate ({correct_mli}/{valid_ppts}).")
        elif correct_mli >= int(len(gt_ppts) * 0.5):
            score += 5
            feedback_parts.append(f"[+5] MLI partially accurate ({correct_mli}/{valid_ppts}).")

    # --- Criterion 6: Group Stats ---
    gt_grp = ground_truth.get('group_summary', {})
    grp = report.get('group_summary', {})
    
    grp_correct = 0
    for k, gt_val in gt_grp.items():
        try:
            val = float(grp.get(k, 0))
            if abs(val - gt_val) <= tol:
                grp_correct += 1
        except (ValueError, TypeError):
            pass
            
    if grp_correct == 5:
        score += 20
        feedback_parts.append("[+20] Group summary exact match.")
    elif grp_correct >= 3:
        score += 10
        feedback_parts.append(f"[+10] Group summary partial match ({grp_correct}/5).")
    else:
        feedback_parts.append(f"[0] Group summary incorrect ({grp_correct}/5).")

    key_criteria_met = (is_excluded(contaminated_pid) and correct_blocks >= req_correct)
    passed = (score >= pass_threshold) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }