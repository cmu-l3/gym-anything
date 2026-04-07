#!/usr/bin/env python3
"""
Verifier for rf_link_drop_gap_detection task.

A ground station operator must write a monitoring script in COSMOS, trigger
a randomized link drop via the provided terminal script, and accurately measure
the resulting telemetry gap duration.

Scoring breakdown (100 pts total, pass threshold = 75):
  10pts  Export metadata and output file exist
  10pts  Output JSON created after task start (freshness gate)
  20pts  Simulator executed (actual_drop_duration > 0, proves interaction)
  20pts  Valid JSON with all 4 required schema keys, correctly typed
  15pts  gaps_detected == 1
  25pts  Accurate measurement: largest_gap_seconds is within ± 2.0s of actual
 ---
 100pts total

Because the simulator randomly determines the drop duration (between 4s and 9s),
an agent cannot guess the output and MUST mathematically measure the telemetry stream.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_rf_link_drop_gap_detection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/rf_link_drop_gap_detection_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/gap_report.json')

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
        feedback.append(f'Export metadata not found or unreadable: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    try:
        actual_drop_duration = float(export_meta.get('actual_drop_duration', 0.0))
    except (ValueError, TypeError):
        actual_drop_duration = 0.0

    if not file_exists:
        feedback.append('Gap report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Gap report exists (+10)')

    # ── Step 2: Freshness Gate ──────────────────────────────────────────────
    if not file_is_new:
        feedback.append('Gap report predates task start — not created this session (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Gap report created during this session (+10)')

    # ── Step 3: Check if simulator was executed ─────────────────────────────
    # If the user ran the bash script, actual_drop_duration will be > 0
    if actual_drop_duration > 0.0:
        score += 20
        feedback.append('Simulator executed successfully (+20)')
    else:
        feedback.append('Simulator script was NOT executed (actual drop duration is 0) — measurement impossible')
        # Cannot get measurement points if simulator was never run
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 4: Parse agent JSON report ─────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Gap report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy gap report: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # ── Step 5: Validate Schema ─────────────────────────────────────────────
    required_keys = {
        'monitoring_duration_seconds', 
        'total_read_cycles', 
        'gaps_detected', 
        'largest_gap_seconds'
    }
    
    missing_keys = required_keys - set(report.keys())
    if missing_keys:
        feedback.append(f'Missing required keys: {sorted(missing_keys)}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Verify types are numeric
    for key in required_keys:
        if not isinstance(report[key], (int, float)):
            feedback.append(f"Value for '{key}' is not numeric")
            return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
            
    score += 20
    feedback.append('Valid JSON schema with all required numeric keys (+20)')

    # ── Step 6: Verify Gap Detection Count ──────────────────────────────────
    gaps_detected = report.get('gaps_detected', 0)
    if gaps_detected == 1:
        score += 15
        feedback.append('Exactly 1 gap detected (+15)')
    else:
        feedback.append(f'Expected 1 gap, but reported {gaps_detected}')

    # ── Step 7: Verify Measurement Accuracy ─────────────────────────────────
    largest_gap = report.get('largest_gap_seconds', 0.0)
    error_margin = abs(largest_gap - actual_drop_duration)

    if error_margin <= 2.0:
        score += 25
        feedback.append(f'Measurement accurate: {largest_gap:.2f}s (Actual: {actual_drop_duration:.2f}s, error: {error_margin:.2f}s) (+25)')
    else:
        feedback.append(f'Measurement inaccurate: {largest_gap:.2f}s (Actual was {actual_drop_duration:.2f}s, > 2.0s error margin)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback)
    }