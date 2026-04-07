#!/usr/bin/env python3
"""
Verifier for implicit_state_deduction task.

A mission data analyst must write and execute a script to query live telemetry 
and apply a strictly ordered logic matrix to deduce the spacecraft's mode, 
writing the results to a structured JSON file.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  Export metadata JSON readable
  10pts  Output JSON exists on Desktop
  10pts  File created after task start (file_is_new=True) [hard gate]
  15pts  INST COLLECT command was sent (current_cmd_count > initial)
  15pts  JSON has target='INST' and 'evaluations' array with >= 10 samples
  15pts  Data authenticity & variance: recorded 'collects' is realistic compared 
         to live state, and temp1 varies (proving it's not a single hardcoded snapshot)
  25pts  Deduction Logic Accuracy: Agent's reported 'deduced_mode' matches the 
         mathematically correct outcome when applying the matrix to their reported data
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import os
import tempfile
import math

def deduce_expected_mode(temp1, temp2, collects):
    """
    Applies the deduction matrix strictly in the specified order:
    1. 'INITIALIZATION' if collects < 10
    2. 'ASYMMETRIC_HEATING' if |temp1 - temp2| >= 15.0
    3. 'HIGH_THERMAL' if temp1 >= 30.0 AND temp2 >= 30.0
    4. 'NOMINAL' otherwise
    """
    if collects < 10:
        return "INITIALIZATION"
    if abs(temp1 - temp2) >= 15.0:
        return "ASYMMETRIC_HEATING"
    if temp1 >= 30.0 and temp2 >= 30.0:
        return "HIGH_THERMAL"
    return "NOMINAL"

def verify_implicit_state_deduction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/implicit_state_deduction_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/state_deduction.json')

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
        score += 10
        feedback.append('Export metadata readable (+10)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    initial_cmd = int(export_meta.get('initial_cmd_count', 0))
    current_cmd = int(export_meta.get('current_cmd_count', 0))
    live_collects = float(export_meta.get('live_collects_value', 0))

    if not file_exists:
        feedback.append('Output report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 10
    feedback.append('Output report exists on Desktop (+10)')

    # Hard gate: file must have been created during the session
    if not file_is_new:
        feedback.append('Output report predates task start (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Output report created during this session (+10)')

    # ── Step 2: Check INST COLLECT Command ──────────────────────────────────
    if current_cmd > initial_cmd:
        score += 15
        feedback.append(f'INST COLLECT command sent ({initial_cmd} -> {current_cmd}) (+15)')
    else:
        feedback.append('INST COLLECT command was NOT sent')

    # ── Step 3: Parse report JSON ───────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Output report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy output file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 4: Schema & Samples Validation ─────────────────────────────────
    if not isinstance(report, dict) or report.get('target') != 'INST':
        feedback.append('Invalid schema: target key missing or not INST')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    evaluations = report.get('evaluations', [])
    if not isinstance(evaluations, list):
        feedback.append('Invalid schema: evaluations must be a list')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    if len(evaluations) >= 10:
        score += 15
        feedback.append(f'Schema valid with {len(evaluations)} samples (+15)')
    else:
        feedback.append(f'Insufficient samples: found {len(evaluations)}, required 10+')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 5: Data Authenticity & Variance ────────────────────────────────
    valid_samples = []
    temp1_values = []
    max_reported_collects = -1

    for idx, sample in enumerate(evaluations):
        try:
            t1 = float(sample.get('temp1'))
            t2 = float(sample.get('temp2'))
            col = int(sample.get('collects'))
            mode = str(sample.get('deduced_mode'))
            
            if not math.isnan(t1) and not math.isnan(t2):
                valid_samples.append({'t1': t1, 't2': t2, 'col': col, 'mode': mode})
                temp1_values.append(t1)
                max_reported_collects = max(max_reported_collects, col)
        except (TypeError, ValueError):
            continue

    if len(valid_samples) < 10:
        feedback.append(f'Only {len(valid_samples)} parseable samples found, need 10+')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Check Variance (prevents hardcoded static mock data)
    variance_ok = False
    if len(temp1_values) > 0:
        if max(temp1_values) - min(temp1_values) > 0:
            variance_ok = True
    
    # Check Authenticity (the reported collects shouldn't far exceed what live shows, give generous 20 buffer for delays)
    authenticity_ok = max_reported_collects <= (live_collects + 20) and max_reported_collects >= 0

    if variance_ok and authenticity_ok:
        score += 15
        feedback.append('Data authenticity and variance verified (+15)')
    else:
        if not variance_ok:
            feedback.append('Data variance failed: telemetry is static (suspicion of hardcoded values)')
        if not authenticity_ok:
            feedback.append(f'Data authenticity failed: reported collects={max_reported_collects} vs live={live_collects}')

    # ── Step 6: Deduction Logic Accuracy ────────────────────────────────────
    logic_correct_count = 0
    for sample in valid_samples:
        expected_mode = deduce_expected_mode(sample['t1'], sample['t2'], sample['col'])
        if sample['mode'] == expected_mode:
            logic_correct_count += 1

    logic_ratio = logic_correct_count / len(valid_samples)
    
    if logic_ratio == 1.0:
        score += 25
        feedback.append('Deduction logic accuracy is 100% (+25)')
    elif logic_ratio > 0.8:
        score += 10
        feedback.append(f'Deduction logic accuracy is {logic_ratio*100:.1f}% (+10 partial)')
    else:
        feedback.append(f'Deduction logic accuracy poor: {logic_ratio*100:.1f}%')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback)
    }