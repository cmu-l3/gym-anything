#!/usr/bin/env python3
"""
Verifier for thermal_rate_of_change_profiling task.

The agent must sample INST HEALTH_STATUS TEMP1 exactly 20 times at ~1.0s intervals,
calculate the time differential (dt) and temperature differential, compute the
rate of change (dT_dt), extract extrema, and export a structured JSON to the Desktop.

Scoring breakdown (100 pts total, pass threshold = 75):
  10pts  Report file exists and was created during the session
  15pts  Valid JSON schema with exactly 20 samples and all required keys
  15pts  Live data variance (temperatures are not all identical)
  20pts  Temporal consistency (dt is accurate to the timestamps, 0.5 <= dt <= 2.5)
  25pts  Mathematical integrity (dT_dt perfectly matches (T_curr - T_prev)/dt)
  15pts  Extrema extraction (max heating and cooling match array contents)
 ---
 100pts total

Do-nothing invariant: passed=False (score = 0)
"""

import json
import os
import tempfile
import datetime

def parse_iso(ts_str):
    s = str(ts_str).replace('Z', '+00:00')
    try:
        return datetime.datetime.fromisoformat(s)
    except Exception:
        return None

def verify_thermal_rate_of_change_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/thermal_roc_profiling_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/thermal_roc_report.json')

    score = 0
    feedback = []

    # ── Step 1: Read export metadata ────────────────────────────────────────
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
        feedback.append('Report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    if not file_is_new:
        feedback.append('Report predates task start (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Report exists and created during session (+10)')

    # ── Step 2: Parse report JSON ──────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy report file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # ── Step 3: Required top-level keys ────────────────────────────────────
    required_keys = {'target', 'item', 'sample_count', 'max_heating_rate', 'max_cooling_rate', 'samples'}
    if not required_keys.issubset(report.keys()):
        missing = required_keys - set(report.keys())
        feedback.append(f'Missing required keys: {sorted(missing)}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    samples = report.get('samples', [])
    if not isinstance(samples, list) or len(samples) != 20:
        found_len = len(samples) if isinstance(samples, list) else "not a list"
        feedback.append(f'Expected exactly 20 samples, found {found_len}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append('Schema valid and contains exactly 20 samples (+15)')

    # ── Step 4: Check live data variance ───────────────────────────────────
    try:
        temps = [float(s.get('temp', 0)) for s in samples]
        if len(set(temps)) > 1:
            score += 15
            feedback.append('Live data variance detected (temps are not identical) (+15)')
        else:
            feedback.append('All temperatures identical (suspected faked data or static simulation)')
    except Exception as e:
        feedback.append(f'Error reading temperatures: {e}')

    # ── Step 5 & 6: Check temporal and mathematical integrity ──────────────
    temporal_errors = 0
    math_errors = 0
    valid_dt_count = 0
    has_math_integrity = False

    try:
        for i in range(1, 20):
            dt = float(samples[i].get('dt', 0))
            dT_dt = float(samples[i].get('dT_dt', 0))
            prev_temp = float(samples[i-1].get('temp', 0))
            curr_temp = float(samples[i].get('temp', 0))
            
            # Temporal check bounds
            if not (0.5 <= dt <= 2.5):
                temporal_errors += 1
            
            # Temporal check against ISO timestamps
            ts_prev = parse_iso(samples[i-1].get('timestamp', ''))
            ts_curr = parse_iso(samples[i].get('timestamp', ''))
            if ts_prev and ts_curr:
                diff = (ts_curr - ts_prev).total_seconds()
                if abs(diff - dt) > 0.1:  # 100ms tolerance for script rounding behavior
                    temporal_errors += 1
            else:
                temporal_errors += 1

            # Mathematical derivative check
            if dt != 0:
                valid_dt_count += 1
                expected_dT_dt = (curr_temp - prev_temp) / dt
                if abs(expected_dT_dt - dT_dt) > 0.05:  # Tolerance for floating point variance
                    math_errors += 1
            else:
                math_errors += 1
        
        if temporal_errors == 0:
            score += 20
            feedback.append('Perfect temporal consistency (+20)')
        elif temporal_errors <= 2:
            score += 10
            feedback.append(f'Minor temporal consistency errors ({temporal_errors}) (+10)')
        else:
            feedback.append(f'Temporal consistency failed ({temporal_errors} errors)')

        if valid_dt_count > 0 and math_errors == 0:
            score += 25
            feedback.append('Perfect mathematical integrity (+25)')
            has_math_integrity = True
        elif valid_dt_count > 0 and math_errors <= 2:
            score += 10
            feedback.append(f'Minor mathematical errors ({math_errors}) (+10)')
            has_math_integrity = True
        else:
            feedback.append(f'Mathematical integrity failed ({math_errors} errors)')

    except Exception as e:
        feedback.append(f'Error parsing sample fields: {e}')

    # ── Step 7: Check extrema extraction ───────────────────────────────────
    try:
        dT_dt_values = [float(s.get('dT_dt', 0)) for s in samples[1:]]
        if dT_dt_values:
            actual_max = max(dT_dt_values)
            actual_min = min(dT_dt_values)
            reported_max = float(report.get('max_heating_rate', 0))
            reported_min = float(report.get('max_cooling_rate', 0))

            if abs(reported_max - actual_max) <= 0.01 and abs(reported_min - actual_min) <= 0.01:
                score += 15
                feedback.append('Extrema correctly extracted (+15)')
            else:
                feedback.append('Reported extrema do not match array contents')
    except Exception as e:
        feedback.append(f'Error calculating extrema: {e}')

    passed = score >= 75 and has_math_integrity
    return {'passed': passed, 'score': score, 'feedback': '; '.join(feedback)}