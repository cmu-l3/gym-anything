#!/usr/bin/env python3
"""
Verifier for command_uplink_optimization task.

A ground data systems engineer must read a raw command schedule, deduplicate consecutive
identical commands, execute the mathematically optimized sequence against OpenC3 COSMOS,
and write the resulting optimized sequence to a JSON report.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  Export metadata JSON readable
  10pts  Output JSON file exists on Desktop and was created after task start
  20pts  Output JSON has correct schema and keys
  20pts  Logical optimization correct (optimized_sequence array strictly matches expectation)
  15pts  Live commanding executed (command delta > 0)
  25pts  Strict commanding accuracy (command delta == mathematically optimized count)
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import os
import tempfile


def verify_command_uplink_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/command_uplink_optimization_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/optimized_schedule.json')
    expected_optimized_count = meta.get('expected_optimized_count', 4)

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
    
    # Parse API counters safely
    try:
        initial_cmd = int(float(export_meta.get('initial_cmd', 0)))
        current_cmd = int(float(export_meta.get('current_cmd', 0)))
    except (TypeError, ValueError):
        initial_cmd, current_cmd = 0, 0

    cmd_delta = current_cmd - initial_cmd

    # ── Step 2: File existence and freshness ────────────────────────────────
    if not file_exists:
        feedback.append('Output JSON file not found on Desktop')
    else:
        if file_is_new:
            score += 10
            feedback.append('Output JSON file exists and was created this session (+10)')
        else:
            feedback.append('Output JSON file predates task start (no content credit)')
            file_exists = False

    # ── Step 3: Parse and validate JSON content ─────────────────────────────
    report = None
    if file_exists:
        try:
            with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
                tmp_name = tmp.name
            copy_from_env(output_file, tmp_name)
            with open(tmp_name, 'r') as f:
                report = json.load(f)
        except json.JSONDecodeError as e:
            feedback.append(f'Output file is not valid JSON: {e}')
            report = None
        except Exception as e:
            feedback.append(f'Could not copy output file: {e}')
            report = None
        finally:
            try:
                os.unlink(tmp_name)
            except Exception:
                pass

    if report:
        # Schema validation
        req_keys = {'original_count', 'optimized_count', 'optimized_sequence'}
        if req_keys.issubset(report.keys()) and isinstance(report['optimized_sequence'], list):
            score += 20
            feedback.append('JSON schema and required keys present (+20)')
            
            # Logical Optimization Check
            # Expected sequence based on consecutive deduplication rule
            expected_seq = [
                {"seq_id": 1, "target": "INST", "command": "COLLECT", "type": "NORMAL", "duration": 1.0},
                {"seq_id": 4, "target": "INST", "command": "COLLECT", "type": "NORMAL", "duration": 2.0},
                {"seq_id": 6, "target": "INST", "command": "COLLECT", "type": "NORMAL", "duration": 3.0},
                {"seq_id": 7, "target": "INST", "command": "COLLECT", "type": "NORMAL", "duration": 1.0}
            ]
            
            actual_seq = report['optimized_sequence']
            
            # Normalize sequence for robust comparison
            try:
                clean_actual = [
                    {
                        "seq_id": int(item.get("seq_id", -1)),
                        "target": str(item.get("target", "")).upper(),
                        "command": str(item.get("command", "")).upper(),
                        "type": str(item.get("type", "")).upper(),
                        "duration": float(item.get("duration", -1.0))
                    }
                    for item in actual_seq
                ]
                
                if clean_actual == expected_seq:
                    score += 20
                    feedback.append('Logical deduplication optimization is 100% correct (+20)')
                else:
                    feedback.append(f'Logical optimization failed. Expected {len(expected_seq)} specific items, got {len(clean_actual)} or mismatched parameters.')
            except Exception as e:
                feedback.append(f'Error parsing sequence array: {e}')
        else:
            feedback.append('JSON missing required schema keys or optimized_sequence is not a list')

    # ── Step 4: Live Commanding Execution & Accuracy ─────────────────────────
    if cmd_delta > 0:
        score += 15
        feedback.append(f'Live commanding executed (delta={cmd_delta}) (+15)')
        
        if cmd_delta == expected_optimized_count:
            score += 25
            feedback.append(f'Strict commanding accuracy achieved (delta exactly {expected_optimized_count}) (+25)')
        else:
            feedback.append(f'Commanding accuracy failed: expected exactly {expected_optimized_count} commands, but recorded {cmd_delta}')
    else:
        feedback.append('No commanding executed against INST target (delta=0)')

    # ── Final Evaluation ─────────────────────────────────────────────────────
    # Agent must achieve a passing score, file must exist, and commanding must have been executed
    key_criteria_met = file_exists and file_is_new and (cmd_delta > 0)
    passed = score >= 70 and key_criteria_met

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }