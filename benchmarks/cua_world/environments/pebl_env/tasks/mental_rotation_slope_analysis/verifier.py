#!/usr/bin/env python3
"""
Verifier for mental_rotation_slope_analysis task.

Verification Strategy (100 points total):
1. Output file exists and valid JSON (10 pts)
2. Contaminated participant s99 is excluded (15 pts)
3. 20 valid participants are present in the report (10 pts)
4. Individual slopes match exact ground truth calculation (25 pts)
5. Group mean slope matches ground truth (10 pts)
6. Group mean accuracy matches ground truth (10 pts)
7. VLM verification of trajectory (evidence of analysis work) (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mental_rotation_slope_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Load Ground Truth Data
    # ---------------------------------------------------------
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_path = tmp.name

    try:
        copy_from_env('/var/lib/pebl_ground_truth/mental_rotation_gt.json', gt_path)
        with open(gt_path, 'r', encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)

    # ---------------------------------------------------------
    # 2. Load Agent's Report
    # ---------------------------------------------------------
    report_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        report_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/mental_rotation_report.json', report_path)
        with open(report_path, 'r', encoding='utf-8') as f:
            report_data = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output JSON found and valid.")
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    except (json.JSONDecodeError, ValueError) as e:
        return {"passed": False, "score": 0, "feedback": f"Output is not valid JSON: {e}"}
    finally:
        if os.path.exists(report_path):
            os.unlink(report_path)

    # ---------------------------------------------------------
    # 3. Analyze Participants & Exclusions
    # ---------------------------------------------------------
    participants_list = report_data.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            ex_list = report_data.get('excluded', [])
            if isinstance(ex_list, list) and pid in ex_list:
                return True
        return False

    # Check s99 exclusion
    if is_excluded('s99'):
        score += 15
        feedback_parts.append("[+15] Participant s99 correctly excluded.")
    else:
        feedback_parts.append("[0] s99 not excluded despite flat RT.")

    # Check 20 valid participants present
    valid_pids = [f"s{i}" for i in range(1, 21)]
    present_valid = sum(1 for pid in valid_pids if pid in part_map and not is_excluded(pid))
    
    if present_valid == 20:
        score += 10
        feedback_parts.append("[+10] All 20 real participants analyzed.")
    else:
        feedback_parts.append(f"[0] Found {present_valid}/20 valid participants.")

    # ---------------------------------------------------------
    # 4. Check Individual Slopes (Tolerance ±1.5 ms/deg)
    # ---------------------------------------------------------
    correct_slopes = 0
    for pid in valid_pids:
        entry = part_map.get(pid)
        if entry and not is_excluded(pid):
            slope = entry.get('slope_ms_per_deg') or entry.get('slope')
            if slope is not None:
                try:
                    gt_slope = gt_data[pid]['slope_ms_per_deg']
                    if abs(float(slope) - gt_slope) <= 1.5:
                        correct_slopes += 1
                except (ValueError, TypeError, KeyError):
                    pass

    if correct_slopes >= 15:
        score += 25
        feedback_parts.append(f"[+25] Individual slopes highly accurate ({correct_slopes}/20).")
    elif correct_slopes >= 5:
        score += 10
        feedback_parts.append(f"[+10] Individual slopes partially accurate ({correct_slopes}/20).")
    else:
        feedback_parts.append(f"[0] Slopes mostly incorrect ({correct_slopes}/20 match GT).")

    # ---------------------------------------------------------
    # 5. Check Group Statistics
    # ---------------------------------------------------------
    gt_stats = gt_data.get('GROUP_STATS', {})
    
    # Group mean slope (Tolerance ±0.8)
    group_slope = report_data.get('group_mean_slope_ms_per_deg') or report_data.get('group_mean_slope')
    if group_slope is not None:
        try:
            if abs(float(group_slope) - gt_stats['group_mean_slope_ms_per_deg']) <= 0.8:
                score += 10
                feedback_parts.append("[+10] Group mean slope correct.")
            else:
                feedback_parts.append(f"[0] Group mean slope incorrect (Expected ~{gt_stats['group_mean_slope_ms_per_deg']}, got {group_slope}).")
        except ValueError:
            pass
            
    # Group mean accuracy (Tolerance ±0.08)
    group_acc = report_data.get('group_mean_accuracy') or report_data.get('group_accuracy')
    if group_acc is not None:
        try:
            if abs(float(group_acc) - gt_stats['group_mean_accuracy']) <= 0.08:
                score += 10
                feedback_parts.append("[+10] Group mean accuracy correct.")
            else:
                feedback_parts.append(f"[0] Group mean accuracy incorrect.")
        except ValueError:
            pass

    # ---------------------------------------------------------
    # 6. VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(trajectory, n=4)
        final = get_final_screenshot(trajectory)
        if frames and final:
            all_frames = frames + [final]
            prompt = """You are verifying an agent performing data analysis on a CSV file.
The agent needs to filter trials, compute regressions/slopes, and generate a JSON report.
Look at this chronological sequence of screenshots.
Does the sequence show genuine analytical work?
1. Using Python, R, LibreOffice, or terminal scripts to process the CSV data?
2. Is there code or commands written to filter "same" trials or compute slopes?
3. Is a JSON report eventually written/generated?

Respond in JSON:
{
    "shows_analysis_tools": true/false,
    "shows_script_or_formulas": true/false,
    "shows_json_creation": true/false
}"""
            result = query_vlm(prompt=prompt, images=all_frames)
            if result and result.get("success"):
                parsed = result.get("parsed", {})
                if parsed.get("shows_analysis_tools") and parsed.get("shows_script_or_formulas"):
                    vlm_score += 10
                if parsed.get("shows_json_creation"):
                    vlm_score += 10
                    
            if vlm_score > 0:
                score += vlm_score
                feedback_parts.append(f"[+{vlm_score}] VLM verified analysis trajectory.")
            else:
                feedback_parts.append("[0] VLM did not observe analysis workflow.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Graceful fallback: grant points if exact mathematical answers were achieved
        if correct_slopes >= 15:
            score += 20
            feedback_parts.append("[+20] VLM skipped, granted based on mathematical exactness.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }