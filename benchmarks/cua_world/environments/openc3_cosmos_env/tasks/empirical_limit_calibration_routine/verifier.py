#!/usr/bin/env python3
"""
Verifier for empirical_limit_calibration_routine task.

Evaluates an agent's ability to sample real-time telemetry, compute dynamic margins,
apply them programmatically into the COSMOS ground system, and produce a formal report.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  File Freshness & Export (hard gate)
  10pts  Structure & Data Types (parseable JSON with keys)
  15pts  Sample Collection (>= 15 items, max > min)
  15pts  Baseline Accuracy (baseline_min/max precisely match samples array)
  15pts  Math Correctness (20%/40% span formulas exactly matched)
  20pts  COSMOS State Applied (queried API limits show agent applied the computed values)
  15pts  Real Data Correlation / VLM Check (Anti-Gaming: samples align with ground truth, trajectory verified)

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM process verification prompt
TRAJECTORY_PROMPT = """You are analyzing trajectory frames from an agent completing an empirical limit calibration in OpenC3 COSMOS.
We need to verify if the agent actually worked in the interface.

Please assess if the agent interacted with tools such as 'Script Runner', 'Telemetry Viewer', 'Limits Monitor', or API documentation to sample telemetry or update limits.

Respond ONLY with a JSON dictionary:
{
    "interacted_with_cosmos": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_limit_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/limit_calibration_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/limit_calibration_report.json')
    gt_file = meta.get('ground_truth_file', '/var/lib/app/ground_truth_temp3.csv')
    
    score = 0
    feedback = []

    # 1. Read export metadata
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    if not file_exists:
        feedback.append('Report not found on Desktop (0 pts for content)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    if not file_is_new:
        feedback.append('Report predates task start — not created this session (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('File freshness & export passed (+10)')

    # 2. Parse report JSON
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except Exception as e:
        feedback.append(f'Report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 3. Structure & Data Types
    required_keys = {'target', 'item', 'sample_count', 'raw_samples', 'baseline_min', 'baseline_max', 'new_limits'}
    if required_keys.issubset(set(report.keys())):
        score += 10
        feedback.append('Structure & required keys present (+10)')
    else:
        missing = required_keys - set(report.keys())
        feedback.append(f'Missing keys: {missing}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # 4. Sample Collection
    samples = report.get('raw_samples', [])
    if isinstance(samples, list) and len(samples) >= 15:
        numeric_samples = [s for s in samples if isinstance(s, (int, float))]
        if len(numeric_samples) >= 15:
            s_min = min(numeric_samples)
            s_max = max(numeric_samples)
            if s_max > s_min:
                score += 15
                feedback.append('Sample collection valid (>= 15 items with variance) (+15)')
            else:
                feedback.append('Sample collection lacks variance (max <= min)')
        else:
            feedback.append('raw_samples contains non-numeric values')
    else:
        feedback.append('raw_samples list too small (need >= 15)')
        numeric_samples = []

    # 5. Baseline Accuracy
    if numeric_samples:
        rep_min = report.get('baseline_min')
        rep_max = report.get('baseline_max')
        if isinstance(rep_min, (int, float)) and isinstance(rep_max, (int, float)):
            if math.isclose(rep_min, min(numeric_samples), abs_tol=0.01) and math.isclose(rep_max, max(numeric_samples), abs_tol=0.01):
                score += 15
                feedback.append('Baseline accuracy matches samples exactly (+15)')
            else:
                feedback.append(f'Baseline mismatch: reported ({rep_min}, {rep_max}) vs actual ({min(numeric_samples)}, {max(numeric_samples)})')

    # 6. Math Correctness
    limits = report.get('new_limits', {})
    expected_limits = {}
    if isinstance(rep_min, (int, float)) and isinstance(rep_max, (int, float)):
        span = rep_max - rep_min
        if span == 0.0:
            span = 5.0
        expected_limits['yellow_low'] = rep_min - (span * 0.2)
        expected_limits['yellow_high'] = rep_max + (span * 0.2)
        expected_limits['red_low'] = rep_min - (span * 0.4)
        expected_limits['red_high'] = rep_max + (span * 0.4)

        if all(k in limits and isinstance(limits[k], (int, float)) for k in expected_limits):
            math_correct = True
            for k in expected_limits:
                if not math.isclose(limits[k], expected_limits[k], abs_tol=0.1):
                    math_correct = False
                    feedback.append(f'Math error on {k}: expected ~{expected_limits[k]:.2f}, got {limits[k]}')
            
            if math_correct:
                score += 15
                feedback.append('Limit formulas calculated correctly (+15)')

    # 7. COSMOS State Applied
    current_limits_raw = export_meta.get('current_limits', [])
    limits_applied = False
    
    # current_limits_raw from API is typically nested, e.g. [["RED_LOW", "YELLOW_LOW", ...]] 
    # Or even if we just dump string, we can search it for the specific computed float values.
    # Searching for values in the raw JSON string is extremely robust against exact API structure.
    current_limits_str = str(current_limits_raw)
    
    if expected_limits and current_limits_str and current_limits_str != "[]":
        # Check if at least 3 of the 4 computed limits are present in the API return string (tolerating some float formatting)
        found_count = 0
        for k, expected_val in expected_limits.items():
            # Check common string representations (e.g. 10.5, 10.50)
            val_str1 = f"{expected_val:.1f}"
            val_str2 = f"{expected_val:.2f}"
            if val_str1 in current_limits_str or val_str2 in current_limits_str:
                found_count += 1
                
        if found_count >= 3:
            limits_applied = True
            score += 20
            feedback.append('COSMOS State check passed: Computed limits active in API (+20)')
        else:
            feedback.append(f'COSMOS limits not applied. API limits: {current_limits_str[:100]}...')
            
    # 8. Real Data Correlation / VLM Check
    # First, verify the agent didn't hallucinate data by cross-referencing ground truth
    gt_data = []
    try:
        with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(gt_file, tmp_name)
        with open(tmp_name, 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) == 2 and parts[1] != 'value':
                    try:
                        gt_data.append(float(parts[1]))
                    except ValueError:
                        pass
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
            
    correlation_passed = False
    if gt_data and numeric_samples:
        # For each sample the agent claimed, it should be within 1.0 of some recorded ground truth
        valid_samples = 0
        for s in numeric_samples:
            min_diff = min(abs(s - gt) for gt in gt_data)
            if min_diff < 1.0:
                valid_samples += 1
        
        # If 80% of samples match ground truth
        if valid_samples / len(numeric_samples) >= 0.8:
            correlation_passed = True

    # Fallback to VLM if ground truth couldn't be collected or didn't correlate perfectly
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            result = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
            if result and result.get("success") and result.get("parsed"):
                vlm_passed = result["parsed"].get("interacted_with_cosmos", False)
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    if correlation_passed:
        score += 15
        feedback.append('Real Data Correlation passed (Anti-Gaming) (+15)')
    elif vlm_passed:
        score += 15
        feedback.append('VLM trajectory verification passed (Anti-Gaming) (+15)')
    else:
        feedback.append('Failed Anti-Gaming check: samples hallucinatory and/or VLM trajectory failed.')

    # Final logic
    key_criteria_met = file_is_new and limits_applied
    passed = (score >= 70) and key_criteria_met

    if not limits_applied:
        feedback.append("CRITICAL: New limits were never successfully applied to COSMOS.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "score": score,
            "file_is_new": file_is_new,
            "limits_applied": limits_applied
        }
    }