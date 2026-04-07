#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sart_preerror_speeding_analysis(trajectory, env_info, task_info):
    """
    Verifier for SART pre-error speeding analysis.
    Checks:
    1. Valid JSON Report Structure (10 pts)
    2. Correct identification of mechanical artifact cand_99 (20 pts)
    3. Correct error rates per valid candidate (20 pts)
    4. Complex rolling window logic correct for pre_ce and pre_cw (35 pts)
    5. Aggregate group mean calculation matching logic (15 pts)
    
    Pass threshold: 65 points + cand_99 exclusion
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch Ground Truth Generated During Setup
    gt_file = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    gt_path = gt_file.name
    gt_file.close()
    
    try:
        copy_from_env('/tmp/sart_ground_truth.json', gt_path)
        with open(gt_path, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)

    # 2. Fetch Agent's Report
    report_file = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report_path = report_file.name
    report_file.close()

    try:
        copy_from_env('/home/ga/pebl/analysis/sart_report.json', report_path)
        with open(report_path, 'r') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Valid JSON report found")
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Output JSON not found at /home/ga/pebl/analysis/sart_report.json"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Output file is not valid JSON"}
    finally:
        if os.path.exists(report_path):
            os.unlink(report_path)

    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[pid] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list):
            for ex in excluded_list:
                if isinstance(ex, dict) and ex.get('id') == pid:
                    return True
                elif ex == pid:
                    return True
        return False

    # 3. Artifact Exclusion Check
    excluded_cand_99 = is_excluded("cand_99")
    if excluded_cand_99:
        score += 20
        feedback_parts.append("[+20] cand_99 correctly excluded")
    else:
        feedback_parts.append("[0] cand_99 not excluded despite mechanical pattern")

    # 4. Metric Checks against Ground Truth
    correct_error_rates = 0
    correct_windowed_rts = 0
    total_valid = 0

    for pid, gt in ground_truth.items():
        if pid == "cand_99" or pid == "group_mean_speeding_effect_ms":
            continue
        total_valid += 1
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
        
        # Check simple static aggregates
        ce_rate = entry.get('commission_error_rate')
        oe_rate = entry.get('omission_error_rate')
        
        ce_ok = ce_rate is not None and abs(float(ce_rate) - gt['commission_error_rate']) <= 0.015
        oe_ok = oe_rate is not None and abs(float(oe_rate) - gt['omission_error_rate']) <= 0.015
        
        if ce_ok and oe_ok:
            correct_error_rates += 1

        # Check complex windowed aggregates
        pre_ce = entry.get('pre_ce_rt_ms')
        pre_cw = entry.get('pre_cw_rt_ms')
        
        if gt['pre_ce_rt_ms'] is None:
            ce_rt_ok = pre_ce is None
        else:
            ce_rt_ok = pre_ce is not None and abs(float(pre_ce) - gt['pre_ce_rt_ms']) <= 5.0

        if gt['pre_cw_rt_ms'] is None:
            cw_rt_ok = pre_cw is None
        else:
            cw_rt_ok = pre_cw is not None and abs(float(pre_cw) - gt['pre_cw_rt_ms']) <= 5.0

        if ce_rt_ok and cw_rt_ok:
            correct_windowed_rts += 1

    if total_valid > 0:
        if correct_error_rates >= total_valid * 0.9:
            score += 20
            feedback_parts.append(f"[+20] Error rates correct for {correct_error_rates}/{total_valid} participants")
        elif correct_error_rates > 0:
            partial = int(20 * (correct_error_rates / total_valid))
            score += partial
            feedback_parts.append(f"[+{partial}] Error rates correct for {correct_error_rates}/{total_valid} participants")
        else:
            feedback_parts.append("[0] Error rates incorrect")

        if correct_windowed_rts >= total_valid * 0.9:
            score += 35
            feedback_parts.append(f"[+35] Windowed logic correct for {correct_windowed_rts}/{total_valid} participants")
        elif correct_windowed_rts > 0:
            partial = int(35 * (correct_windowed_rts / total_valid))
            score += partial
            feedback_parts.append(f"[+{partial}] Windowed logic correct for {correct_windowed_rts}/{total_valid} participants")
        else:
            feedback_parts.append("[0] Windowed logic incorrect")

    # 5. Group Mean Verification
    group_mean = report.get('group_mean_speeding_effect_ms')
    gt_group_mean = ground_truth.get('group_mean_speeding_effect_ms', 0)
    
    if group_mean is not None and abs(float(group_mean) - gt_group_mean) <= 2.0:
        score += 15
        feedback_parts.append("[+15] Group mean calculated correctly")
    else:
        feedback_parts.append(f"[0] Group mean incorrect (got {group_mean}, expected ~{gt_group_mean:.1f})")

    # Anti-gaming: Output must exist, logic must largely be implemented, and artifact excluded
    passed = score >= 65 and excluded_cand_99
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }