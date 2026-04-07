#!/usr/bin/env python3
"""
Verifier for dual_satellite_health_comparison task.

Evaluates if the agent successfully captured telemetry from two satellite targets
(INST and INST2), computed mathematical deltas, and produced a valid JSON report.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts: Export metadata readable
  10pts: JSON file exists on Desktop
  10pts: File created this session (hard gate)
  10pts: JSON has all 5 required top-level keys
  15pts: inst1 has 4 numeric temp values + numeric collects
  15pts: inst2 has 4 numeric temp values + numeric collects
  10pts: deltas has 4 numeric delta values
  10pts: Delta consistency (each delta ≈ inst1.tempN - inst2.tempN within ±1.0)
   5pts: timestamp is valid ISO 8601 datetime
   5pts: assessment is a descriptive string (>= 10 chars)
"""

import json
import os
import tempfile
from datetime import datetime


def is_numeric(v):
    """Check if a value is strictly numeric (int or float) and not a boolean."""
    return isinstance(v, (int, float)) and type(v) is not bool


def verify_dual_satellite_health_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/dual_satellite_health_comparison_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/health_comparison.json')

    score = 0
    feedback = []

    # 1. Read export metadata (10 pts)
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
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    # 2. File exists (10 pts)
    if not file_exists:
        feedback.append('Comparison report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 10
    feedback.append('Comparison report exists on Desktop (+10)')

    # 3. File created this session (hard gate) (10 pts)
    if not file_is_new:
        feedback.append('Report predates task start — not created this session (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 10
    feedback.append('Report created during this session (+10)')

    # Load the agent's JSON report
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
        feedback.append(f'Could not copy report: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 4. Required top-level keys (10 pts)
    required_keys = {'timestamp', 'inst1', 'inst2', 'deltas', 'assessment'}
    missing_keys = required_keys - set(report.keys())
    if not missing_keys:
        score += 10
        feedback.append('All 5 required top-level keys present (+10)')
    else:
        feedback.append(f'Missing keys: {sorted(missing_keys)} — stopping here')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    inst1 = report.get('inst1', {})
    inst2 = report.get('inst2', {})
    deltas = report.get('deltas', {})

    # 5. inst1 format (15 pts)
    inst1_temps_ok = all(is_numeric(inst1.get(f'temp{i}')) for i in range(1, 5))
    inst1_collects_ok = is_numeric(inst1.get('collects'))
    if inst1_temps_ok and inst1_collects_ok:
        score += 15
        feedback.append('inst1 telemetry block correctly formatted (+15)')
    else:
        feedback.append('inst1 telemetry block missing fields or has non-numeric values')

    # 6. inst2 format (15 pts)
    inst2_temps_ok = all(is_numeric(inst2.get(f'temp{i}')) for i in range(1, 5))
    inst2_collects_ok = is_numeric(inst2.get('collects'))
    if inst2_temps_ok and inst2_collects_ok:
        score += 15
        feedback.append('inst2 telemetry block correctly formatted (+15)')
    else:
        feedback.append('inst2 telemetry block missing fields or has non-numeric values')

    # 7. deltas format (10 pts)
    deltas_ok = all(is_numeric(deltas.get(f'temp{i}_delta')) for i in range(1, 5))
    if deltas_ok:
        score += 10
        feedback.append('deltas block correctly formatted (+10)')
    else:
        feedback.append('deltas block missing fields or has non-numeric values')

    # 8. Delta consistency (10 pts)
    if inst1_temps_ok and inst2_temps_ok and deltas_ok:
        consistent = True
        for i in range(1, 5):
            t1 = float(inst1.get(f'temp{i}'))
            t2 = float(inst2.get(f'temp{i}'))
            d = float(deltas.get(f'temp{i}_delta'))
            expected_d = t1 - t2
            # Allow minor rounding differences (up to 1.0)
            if abs(d - expected_d) > 1.0:
                consistent = False
                feedback.append(f'Inconsistent temp{i}_delta: expected approx {expected_d}, got {d}')
                
        if consistent:
            score += 10
            feedback.append('Delta mathematical consistency verified (+10)')
    else:
        feedback.append('Delta consistency skipped due to invalid numeric fields')

    # 9. Timestamp validation (5 pts)
    timestamp = str(report.get('timestamp', ''))
    try:
        if timestamp.endswith('Z'):
            timestamp = timestamp[:-1] + '+00:00'
        datetime.fromisoformat(timestamp)
        score += 5
        feedback.append('Timestamp is valid ISO 8601 (+5)')
    except ValueError:
        feedback.append('Timestamp is not valid ISO 8601 format')

    # 10. Assessment validation (5 pts)
    assessment = report.get('assessment', '')
    if isinstance(assessment, str) and len(assessment.strip()) >= 10:
        score += 5
        feedback.append('Assessment string meets length requirements (+5)')
    else:
        feedback.append('Assessment is either missing, not a string, or too short')

    passed = score >= 60
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }