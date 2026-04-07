#!/usr/bin/env python3
"""
Verifier for conditional_contingency_procedure task.

A flight operations engineer must write and execute an automation script that
samples telemetry, evaluates a flight rule threshold (55.0), executes the
appropriate conditional command branch, and logs the process.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  File Freshness Gate: JSON report exists and was created this session
  15pts  Schema Compliance: Correct keys and data types (samples length=3)
  20pts  Mathematical Accuracy: mean_temperature matches avg of samples
  20pts  Logical Branching: branch and command strictly map to the < 55.0 threshold
  35pts  Spacecraft Commanding: API verifies the specific reported command was sent
 ---
 100pts total

Because the pass threshold is 70, the agent MUST successfully command the system
(which grants up to 35 pts) to pass. Fabricating a perfect JSON without acting
on the system yields a max of 65 points.
"""

import json
import os
import tempfile
import math


def verify_conditional_contingency_procedure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/conditional_contingency_procedure_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/conditional_pass_report.json')
    threshold = float(meta.get('temperature_threshold', 55.0))

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
        feedback.append(f'Export metadata missing or invalid: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    init_collect = int(export_meta.get('initial_collect_count', 0))
    curr_collect = int(export_meta.get('current_collect_count', 0))
    init_abort = int(export_meta.get('initial_abort_count', 0))
    curr_abort = int(export_meta.get('current_abort_count', 0))

    # ── Step 2: File Freshness Gate (10 pts) ────────────────────────────────
    if not file_exists:
        feedback.append('Report file not found on Desktop')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    
    if not file_is_new:
        feedback.append('Report file predates task start (no content credit awarded)')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Report file is new (+10)')

    # ── Step 3: Copy and Parse JSON Report ──────────────────────────────────
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

    # ── Step 4: Schema Compliance (15 pts) ──────────────────────────────────
    required_keys = {'samples', 'mean_temperature', 'branch_executed', 'command_sent'}
    missing_keys = required_keys - set(report.keys())
    
    if missing_keys:
        feedback.append(f'Report missing keys: {sorted(missing_keys)}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    samples = report.get('samples')
    mean_temp = report.get('mean_temperature')
    branch = str(report.get('branch_executed', '')).upper().strip()
    command = str(report.get('command_sent', '')).upper().strip()

    if not isinstance(samples, list) or len(samples) != 3:
        feedback.append(f'samples must be a list of exactly 3 values (got {type(samples)}, length {len(samples) if isinstance(samples, list) else "N/A"})')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    try:
        samples = [float(s) for s in samples]
        mean_temp = float(mean_temp)
    except (ValueError, TypeError):
        feedback.append('samples and mean_temperature must be numeric floats')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append('Schema valid (+15)')

    # ── Step 5: Mathematical Accuracy (20 pts) ──────────────────────────────
    calculated_mean = sum(samples) / 3.0
    if abs(calculated_mean - mean_temp) <= 0.05:
        score += 20
        feedback.append('Mean calculation mathematically correct (+20)')
    else:
        feedback.append(f'Math error: avg of {samples} is {calculated_mean:.3f}, but report claims {mean_temp}')

    # ── Step 6: Logical Branching (20 pts) ──────────────────────────────────
    logic_correct = False
    expected_command_key = ""

    if mean_temp < threshold:
        if branch == "NOMINAL" and "COLLECT" in command:
            logic_correct = True
            expected_command_key = "COLLECT"
            score += 20
            feedback.append(f'Logic correct: {mean_temp} < {threshold} -> NOMINAL / COLLECT (+20)')
        else:
            feedback.append(f'Logic error: for mean {mean_temp} < {threshold}, expected NOMINAL branch and COLLECT command, got {branch} / {command}')
    else:
        if branch == "CONTINGENCY" and "ABORT" in command:
            logic_correct = True
            expected_command_key = "ABORT"
            score += 20
            feedback.append(f'Logic correct: {mean_temp} >= {threshold} -> CONTINGENCY / ABORT (+20)')
        else:
            feedback.append(f'Logic error: for mean {mean_temp} >= {threshold}, expected CONTINGENCY branch and ABORT command, got {branch} / {command}')

    # ── Step 7: Spacecraft Commanding (35 pts) ──────────────────────────────
    if not logic_correct:
        feedback.append('Command execution verification skipped due to logical branching error.')
    else:
        if expected_command_key == "COLLECT":
            if curr_collect > init_collect:
                score += 35
                feedback.append(f'Command verified via API: COLLECT count {init_collect} -> {curr_collect} (+35)')
            else:
                feedback.append(f'Command failure: Agent reported COLLECT sent, but system API recorded no change ({init_collect})')
        elif expected_command_key == "ABORT":
            if curr_abort > init_abort:
                score += 35
                feedback.append(f'Command verified via API: ABORT count {init_abort} -> {curr_abort} (+35)')
            else:
                feedback.append(f'Command failure: Agent reported ABORT sent, but system API recorded no change ({init_abort})')

    passed = score >= 70
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}