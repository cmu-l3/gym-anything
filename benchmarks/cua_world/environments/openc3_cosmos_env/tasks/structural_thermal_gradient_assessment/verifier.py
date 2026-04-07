#!/usr/bin/env python3
"""
Verifier for structural_thermal_gradient_assessment task.

This verifier heavily leverages mathematical and variance cross-checking 
to prevent gaming. Because the target output is entirely derived from live 
telemetry readings, faking the result requires the agent to perfectly hallucinate
mathematical invariants across 10 samples.

Scoring breakdown (100 pts total, pass threshold = 75):
  20pts: JSON Report exists and was created this session (Hard Gate)
  15pts: Schema contains 10 elements and valid keys
  25pts: Internal math consistency (gradient strictly = max - min for each sample)
  15pts: Logic logic consistency (peak_gradient and WARNING/NOMINAL mapping)
  25pts: Anti-gaming (Realistic physical bounds, and variance > 0 proving live sampling)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_thermal_gradient_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/structural_thermal_gradient_assessment_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/thermal_gradient_report.json')

    score = 0
    feedback = []

    # ================================================================
    # 1. Read export metadata
    # ================================================================
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Export metadata not found: {e}'}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    if not file_exists:
        return {'passed': False, 'score': 0, 'feedback': 'Report file not found on Desktop'}
    
    score += 10
    feedback.append("Report file exists (+10)")

    if not file_is_new:
        return {'passed': False, 'score': score, 'feedback': 'Report file predates task start (no content credit)'}
    
    score += 10
    feedback.append("Report file created this session (+10)")

    # ================================================================
    # 2. Parse report JSON
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': score, 'feedback': f'Failed to parse report JSON: {e}'}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # ================================================================
    # 3. Schema & Data Volume (15 pts)
    # ================================================================
    required_keys = {'target', 'packet', 'samples', 'peak_gradient', 'limit', 'status'}
    if not required_keys.issubset(set(report.keys())):
        feedback.append(f"Missing top-level keys. Found: {list(report.keys())}")
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}
    
    samples = report.get('samples', [])
    if not isinstance(samples, list) or len(samples) != 10:
        feedback.append(f"Expected 10 samples, found {len(samples) if isinstance(samples, list) else 'non-list'}")
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}
    
    score += 15
    feedback.append("Valid schema and exactly 10 samples (+15)")

    # ================================================================
    # 4. Math Consistency (25 pts)
    # ================================================================
    math_correct_count = 0
    t1_values, t2_values, t3_values, t4_values = [], [], [], []
    valid_bounds = True
    
    for i, s in enumerate(samples):
        if not isinstance(s, dict):
            continue
        try:
            t1 = float(s.get('temp1', 0))
            t2 = float(s.get('temp2', 0))
            t3 = float(s.get('temp3', 0))
            t4 = float(s.get('temp4', 0))
            grad = float(s.get('gradient', -1))
            
            t1_values.append(t1)
            t2_values.append(t2)
            t3_values.append(t3)
            t4_values.append(t4)
            
            # physical bounds check: satellite simulator values typically fall between 0 and 100
            # generously allowing -200 to +400 for anomaly injections
            for t in (t1, t2, t3, t4):
                if not (-200 <= t <= 400):
                    valid_bounds = False
            
            expected_grad = max(t1, t2, t3, t4) - min(t1, t2, t3, t4)
            if abs(grad - expected_grad) <= 0.01:
                math_correct_count += 1
        except (ValueError, TypeError):
            pass # Malformed numerical conversion
    
    math_score = int((math_correct_count / 10.0) * 25)
    score += math_score
    feedback.append(f"Math correct for {math_correct_count}/10 samples (+{math_score})")

    # ================================================================
    # 5. Peak & Status Logic (15 pts)
    # ================================================================
    try:
        peak_grad = float(report['peak_gradient'])
        limit = float(report['limit'])
        status = str(report['status']).strip().upper()
        
        # Recalculate intended peak from what they actually collected
        valid_grads = []
        for s in samples:
            try:
                valid_grads.append(float(s['gradient']))
            except Exception:
                pass
        expected_peak = max(valid_grads) if valid_grads else 0.0
        
        peak_correct = abs(peak_grad - expected_peak) <= 0.01
        expected_status = 'WARNING' if peak_grad > 15.0 else 'NOMINAL'
        status_correct = (status == expected_status)
        
        if peak_correct and status_correct:
            score += 15
            feedback.append("Peak gradient and flight rule status correct (+15)")
        else:
            feedback.append(f"Logic Error (Peak correct: {peak_correct}, Status correct: {status_correct})")
    except Exception as e:
        feedback.append(f"Error evaluating peak/status logic: {e}")

    # ================================================================
    # 6. Anti-Gaming: Bounds & Live Data Variance (25 pts)
    # ================================================================
    # Because INST simulator operates dynamically, capturing 10 samples separated by 1s
    # guarantees numerical drift. If all numbers are identical, the agent faked it.
    variance_present = False
    if len(set(t1_values)) > 1 or len(set(t2_values)) > 1 or len(set(t3_values)) > 1 or len(set(t4_values)) > 1:
        variance_present = True
        
    if valid_bounds and variance_present and len(t1_values) == 10:
        score += 25
        feedback.append("Live data variance and bounds verified (+25)")
    else:
        feedback.append(f"Anti-gaming fail (Variance found: {variance_present}, Plausible bounds: {valid_bounds})")

    # Final pass determination
    passed = (score >= 75)
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }