#!/usr/bin/env python3
"""
Verifier for closed_loop_telemetry_response task.

An automation engineer must write a Python script that reads 5 live telemetry samples,
computes their mean, dynamically calculates a command duration `max(1, int(abs(mean)))`,
sends the command to the live COSMOS system, and saves a JSON report.

Scoring breakdown (100 pts total, pass threshold = 60):
  15pts  Export metadata JSON readable
  10pts  Both script and JSON report exist and are fresh (created this session)
  15pts  JSON report schema is valid (all keys present, exactly 5 numeric samples)
  15pts  Mathematical consistency (`calculated_mean` matches `sum(samples)/5`)
  15pts  Logic consistency (`commanded_duration` matches `max(1, int(abs(mean)))`)
  30pts  Live system command execution (`current_cmd_count > initial_cmd_count`)
 ---
 100pts total

ANTI-GAMING GATE: If the command was not actually executed in the live system
(`current_cmd_count <= initial_cmd_count`), the maximum possible score is strictly capped
at 50. This prevents the agent from passing by just hallucinating a mathematically
consistent JSON file without interacting with the real API.
"""

import json
import math
import os
import tempfile


def verify_closed_loop_telemetry_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/closed_loop_telemetry_response_result.json')
    report_file = meta.get('output_report', '/home/ga/Desktop/automation_report.json')

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
        score += 15
        feedback.append('Export metadata readable (+15)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    script_exists = export_meta.get('script_exists', False)
    script_is_new = export_meta.get('script_is_new', False)
    report_exists = export_meta.get('report_exists', False)
    report_is_new = export_meta.get('report_is_new', False)
    
    try:
        initial_cmd_count = int(export_meta.get('initial_cmd_count', 0))
        current_cmd_count = int(export_meta.get('current_cmd_count', 0))
    except (TypeError, ValueError):
        initial_cmd_count = 0
        current_cmd_count = 0

    command_executed = current_cmd_count > initial_cmd_count

    # ── Step 2: File existence & freshness ──────────────────────────────────
    if not script_exists or not report_exists:
        feedback.append('Missing required output files (script or JSON report).')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    if not script_is_new or not report_is_new:
        feedback.append('Output files predate task start (not created this session).')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Script and report files exist and were created this session (+10)')

    # ── Step 3: Parse the output JSON report ────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(report_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'JSON report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy JSON report: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 4: Schema validation ───────────────────────────────────────────
    required_keys = {'target', 'telemetry_item', 'samples', 'calculated_mean', 'commanded_duration', 'command_sent'}
    missing_keys = required_keys - set(report.keys())
    
    if missing_keys:
        feedback.append(f'JSON missing required keys: {sorted(missing_keys)}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    raw_samples = report.get('samples', [])
    if not isinstance(raw_samples, list) or len(raw_samples) != 5:
        feedback.append(f'JSON samples must be an array of exactly 5 elements. Found {len(raw_samples) if isinstance(raw_samples, list) else type(raw_samples).__name__}.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    try:
        samples = [float(x) for x in raw_samples]
        calculated_mean = float(report.get('calculated_mean'))
        commanded_duration = int(report.get('commanded_duration'))
    except (TypeError, ValueError) as e:
        feedback.append(f'JSON contains invalid data types (samples must be floats, mean float, duration int): {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append('JSON schema is valid (+15)')

    # ── Step 5: Mathematical consistency ────────────────────────────────────
    expected_mean = sum(samples) / 5.0
    if math.isclose(expected_mean, calculated_mean, rel_tol=1e-2, abs_tol=1e-2):
        score += 15
        feedback.append(f'Mathematical consistency verified (mean {calculated_mean:.2f}) (+15)')
    else:
        feedback.append(f'Math mismatch: sum(samples)/5 is {expected_mean:.3f}, but JSON claims {calculated_mean}')

    # ── Step 6: Logic consistency ───────────────────────────────────────────
    expected_duration = max(1, int(abs(calculated_mean)))
    if commanded_duration == expected_duration:
        score += 15
        feedback.append(f'Logic consistency verified (duration {commanded_duration} matches formula) (+15)')
    else:
        feedback.append(f'Logic mismatch: max(1, int(abs({calculated_mean}))) is {expected_duration}, but JSON claims {commanded_duration}')

    # ── Step 7: Live system execution check ─────────────────────────────────
    if command_executed:
        score += 30
        feedback.append(f'Live system confirmed command execution (count {initial_cmd_count} -> {current_cmd_count}) (+30)')
    else:
        feedback.append(f'Live system command check failed (count {initial_cmd_count} -> {current_cmd_count}). The script did not successfully send the command to COSMOS.')

    # ── Final Gate & Output ─────────────────────────────────────────────────
    if not command_executed:
        score = min(score, 50)
        feedback.append('ANTI-GAMING GATE: Score capped at 50 because live system execution was not detected.')

    passed = score >= 60 and command_executed
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }