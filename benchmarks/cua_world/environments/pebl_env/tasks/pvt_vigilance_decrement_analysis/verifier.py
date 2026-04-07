#!/usr/bin/env python3
"""
Verifier for pvt_vigilance_decrement_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON (10 pts)
  2. P00 correctly excluded with relevant reason (15 pts)
  3. All 15 real participants present with both conditions (10 pts)
  4. Mean RT (rested) within ±25ms for ≥12 of 15 participants (10 pts)
  5. Mean RT (deprived) within ±40ms for ≥12 of 15 participants (10 pts)
  6. Lapse counts within ±3 for ≥12 of 15 participants (10 pts)
  7. Vigilance slope (rested) within ±5 ms/q for ≥10 of 15 participants (10 pts)
  8. Vigilance slope (deprived) within ±10 ms/q for ≥10 of 15 participants (10 pts)
  9. Group mean RT (rested) within ±15ms of ground truth (5 pts)
  10. Group mean RT (deprived) within ±25ms of ground truth (5 pts)
  11. Sleep deprivation effect within ±20ms of ground truth (5 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_value_from_dict(d, keys, default=None):
    for k in keys:
        if k in d:
            return d[k]
    return default

def verify_pvt_vigilance_decrement(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # ---------------------------------------------------------
    # Retrieve dynamic Ground Truth
    # ---------------------------------------------------------
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_gt_path = tmp.name

    try:
        copy_from_env('/tmp/.pvt_gt.json', tmp_gt_path)
        with open(tmp_gt_path, encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt_path):
            os.unlink(tmp_gt_path)

    # ---------------------------------------------------------
    # Retrieve Agent's Report
    # ---------------------------------------------------------
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_report_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/pvt_report.json', tmp_report_path)
        with open(tmp_report_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output file found and is valid JSON.")
    except FileNotFoundError:
        feedback_parts.append("[0] Output file /home/ga/pebl/analysis/pvt_report.json not found.")
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f"[0] Output file exists but is not valid JSON: {e}")
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback_parts)}
    finally:
        if os.path.exists(tmp_report_path):
            os.unlink(tmp_report_path)

    # ---------------------------------------------------------
    # Build Participant Map
    # ---------------------------------------------------------
    part_map = {}
    for entry in report.get('participants', []):
        pid = get_value_from_dict(entry, ['id', 'participant_id', 'participant'])
        if pid:
            part_map[str(pid)] = entry

    # ---------------------------------------------------------
    # Criterion 2: P00 Excluded (15 pts)
    # ---------------------------------------------------------
    p00_entry = part_map.get("P00", {})
    is_excluded = p00_entry.get('excluded') in (True, 'true', 1, 'yes')
    reason = str(p00_entry.get('reason', '')).lower()
    
    valid_reasons = ['sd', 'var', 'standard deviation', 'auto', 'fabricat', 'fake', 'impossib', 'consist']
    has_valid_reason = any(w in reason for w in valid_reasons)

    if is_excluded and has_valid_reason:
        score += 15
        feedback_parts.append("[+15] P00 correctly excluded with valid variance/fabrication reason.")
    elif is_excluded:
        score += 5
        feedback_parts.append("[+5] P00 excluded, but reason lacks specific mention of low variability/fabrication.")
    else:
        feedback_parts.append("[0] P00 not marked as excluded despite impossible SD < 5ms.")

    # ---------------------------------------------------------
    # Counters for participant-level metrics
    # ---------------------------------------------------------
    real_participants = [f"P{i:02d}" for i in range(1, 16)]
    
    present_count = 0
    rested_rt_correct = 0
    deprived_rt_correct = 0
    lapses_correct = 0
    rested_slope_correct = 0
    deprived_slope_correct = 0

    for p in real_participants:
        entry = part_map.get(p)
        if not entry or entry.get('excluded'):
            continue
        
        rested = entry.get('rested', {})
        deprived = entry.get('deprived', {})
        
        if rested and deprived:
            present_count += 1
        
        gt_p = gt.get(p, {})
        
        # Helper to parse floats safely
        def safe_float(val):
            try: return float(val)
            except (TypeError, ValueError): return None

        # Check Rested RT (±25ms)
        agt_rested_rt = safe_float(get_value_from_dict(rested, ['mean_rt_ms', 'mean_rt']))
        if agt_rested_rt is not None and abs(agt_rested_rt - gt_p['rested']['mean_rt_ms']) <= 25.0:
            rested_rt_correct += 1
            
        # Check Deprived RT (±40ms)
        agt_deprived_rt = safe_float(get_value_from_dict(deprived, ['mean_rt_ms', 'mean_rt']))
        if agt_deprived_rt is not None and abs(agt_deprived_rt - gt_p['deprived']['mean_rt_ms']) <= 40.0:
            deprived_rt_correct += 1

        # Check Lapses (±3)
        agt_rested_lapses = safe_float(rested.get('lapses'))
        agt_deprived_lapses = safe_float(deprived.get('lapses'))
        if agt_rested_lapses is not None and agt_deprived_lapses is not None:
            if abs(agt_rested_lapses - gt_p['rested']['lapses']) <= 3 and abs(agt_deprived_lapses - gt_p['deprived']['lapses']) <= 3:
                lapses_correct += 1

        # Check Slopes
        agt_rested_slope = safe_float(get_value_from_dict(rested, ['vigilance_slope_ms_per_quintile', 'vigilance_slope']))
        if agt_rested_slope is not None and abs(agt_rested_slope - gt_p['rested']['vigilance_slope']) <= 5.0:
            rested_slope_correct += 1
            
        agt_deprived_slope = safe_float(get_value_from_dict(deprived, ['vigilance_slope_ms_per_quintile', 'vigilance_slope']))
        if agt_deprived_slope is not None and abs(agt_deprived_slope - gt_p['deprived']['vigilance_slope']) <= 10.0:
            deprived_slope_correct += 1

    # ---------------------------------------------------------
    # Apply Participant-Level Scores
    # ---------------------------------------------------------
    if present_count == 15:
        score += 10; feedback_parts.append("[+10] All 15 valid participants present.")
    elif present_count > 0:
        score += 5; feedback_parts.append(f"[+5] Partial: {present_count}/15 valid participants present.")

    if rested_rt_correct >= 12:
        score += 10; feedback_parts.append(f"[+10] Rested mean RT accurate for {rested_rt_correct}/15 participants.")
    elif rested_rt_correct >= 8:
        score += 5; feedback_parts.append(f"[+5] Partial rested RT accurate for {rested_rt_correct}/15.")

    if deprived_rt_correct >= 12:
        score += 10; feedback_parts.append(f"[+10] Deprived mean RT accurate for {deprived_rt_correct}/15 participants.")
    elif deprived_rt_correct >= 8:
        score += 5; feedback_parts.append(f"[+5] Partial deprived RT accurate for {deprived_rt_correct}/15.")

    if lapses_correct >= 12:
        score += 10; feedback_parts.append(f"[+10] Lapses accurate for {lapses_correct}/15 participants.")
    elif lapses_correct >= 8:
        score += 5; feedback_parts.append(f"[+5] Partial lapses accurate for {lapses_correct}/15.")

    if rested_slope_correct >= 10:
        score += 10; feedback_parts.append(f"[+10] Rested vigilance slope accurate for {rested_slope_correct}/15.")
    
    if deprived_slope_correct >= 10:
        score += 10; feedback_parts.append(f"[+10] Deprived vigilance slope accurate for {deprived_slope_correct}/15.")

    # ---------------------------------------------------------
    # Group-Level Scores
    # ---------------------------------------------------------
    def safe_float_from_dict(d, keys):
        if not d: return None
        try: return float(get_value_from_dict(d, keys))
        except (TypeError, ValueError): return None

    group_means = report.get('group_means', {})
    agt_gm_rested = safe_float_from_dict(group_means.get('rested'), ['mean_rt_ms', 'mean_rt'])
    agt_gm_deprived = safe_float_from_dict(group_means.get('deprived'), ['mean_rt_ms', 'mean_rt'])
    agt_effect = safe_float_from_dict(report, ['sleep_deprivation_effect_ms', 'sleep_deprivation_effect'])

    gt_gm_rested = gt['group_means']['rested']['mean_rt_ms']
    gt_gm_deprived = gt['group_means']['deprived']['mean_rt_ms']
    gt_effect = gt['sleep_deprivation_effect_ms']

    if agt_gm_rested is not None and abs(agt_gm_rested - gt_gm_rested) <= 15.0:
        score += 5; feedback_parts.append("[+5] Group mean rested RT accurate.")
    
    if agt_gm_deprived is not None and abs(agt_gm_deprived - gt_gm_deprived) <= 25.0:
        score += 5; feedback_parts.append("[+5] Group mean deprived RT accurate.")

    if agt_effect is not None and abs(agt_effect - gt_effect) <= 20.0:
        score += 5; feedback_parts.append("[+5] Sleep deprivation effect accurate.")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }