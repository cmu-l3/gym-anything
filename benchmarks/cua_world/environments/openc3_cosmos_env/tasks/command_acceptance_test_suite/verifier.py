#!/usr/bin/env python3
"""
Verifier for command_acceptance_test_suite task.

A ground systems engineer must verify INST commands and write a structured 
JSON report to /home/ga/Desktop/test_report.json.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts  Export metadata JSON readable
  10pts  Test report JSON exists on Desktop
  10pts  Test report JSON created after task start [hard gate for file content]
  20pts  Command count increase via COSMOS API (delta >= 5) [Anti-gaming]
  10pts  Valid JSON with all 5 required top-level keys
  15pts  test_cases array has >= 5 entries
  15pts  Each test case has all 5 required valid fields (test_id, command, expected, actual, result)
  10pts  Internal consistency (passed + failed == total_tests == len(test_cases))
 ---
 100pts total
 
To prevent gaming (creating test entries without actually commanding the satellite),
test case scores are capped to the number of actual commands executed in the session.
"""

import json
import os
import tempfile

def verify_command_acceptance_test_suite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/command_acceptance_test_suite_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/test_report.json')

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
    initial_cmds = int(export_meta.get('initial_cmd_count', 0))
    current_cmds = int(export_meta.get('current_cmd_count', 0))
    delta_cmds = current_cmds - initial_cmds

    # 2. Command Count (20 pts)
    if delta_cmds >= 5:
        score += 20
        feedback.append(f'Commands sent >= 5 (Actual: {delta_cmds}) (+20)')
    elif delta_cmds > 0:
        partial = int((delta_cmds / 5.0) * 20)
        score += partial
        feedback.append(f'Commands sent: {delta_cmds}/5 (+{partial})')
    else:
        feedback.append('No commands sent during session.')

    # 3. File exists (10 pts)
    if not file_exists:
        feedback.append('Test report not found on Desktop.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 10
    feedback.append('Test report exists on Desktop (+10)')

    # 4. File is new (10 pts)
    if not file_is_new:
        feedback.append('Test report predates task start (no content credit).')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 10
    feedback.append('Test report created this session (+10)')

    # Parse JSON
    report = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except Exception as e:
        feedback.append(f'Test report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 5. Top-level keys (10 pts)
    req_keys = {'test_suite_name', 'total_tests', 'passed', 'failed', 'test_cases'}
    if req_keys.issubset(set(report.keys())):
        score += 10
        feedback.append('All 5 required top-level keys present (+10)')
    else:
        missing = req_keys - set(report.keys())
        feedback.append(f'Missing top-level keys: {missing}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Check test_cases array
    test_cases = report.get('test_cases', [])
    if not isinstance(test_cases, list):
        feedback.append('test_cases is not a list.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Anti-gaming rule: test case scores are capped to actual commands sent
    claimed_cases = len(test_cases)
    effective_cases = min(claimed_cases, delta_cmds)

    # 6. Test cases >= 5 (15 pts)
    if effective_cases >= 5:
        score += 15
        feedback.append(f'Valid test cases count >= 5 (Found {claimed_cases}, Commands {delta_cmds}) (+15)')
    elif effective_cases > 0:
        partial = effective_cases * 3
        score += partial
        feedback.append(f'Valid test cases: {effective_cases}/5 (+{partial})')
    else:
        feedback.append('No valid test cases backed by actual commands.')

    # 7. Each test case has 5 valid fields (15 pts)
    tc_req_keys = {'test_id', 'command', 'expected', 'actual', 'result'}
    valid_tcs = 0
    
    # We only award points up to the effective cases (anti-gaming limit)
    for tc in test_cases[:max(1, effective_cases)]:
        if not isinstance(tc, dict):
            continue
        if not tc_req_keys.issubset(set(tc.keys())):
            continue
        
        res = tc.get('result')
        cmd = tc.get('command')
        
        if res not in ['PASS', 'FAIL']:
            continue
        if not isinstance(cmd, str) or len(cmd.strip()) < 3:
            continue
            
        valid_tcs += 1

    if valid_tcs >= 5:
        score += 15
        feedback.append('All evaluated test cases have 5 required and valid fields (+15)')
    elif valid_tcs > 0:
        partial = valid_tcs * 3
        score += partial
        feedback.append(f'Test cases with valid fields: {valid_tcs}/5 (+{partial})')
    else:
        feedback.append('No test cases have all required valid fields.')

    # 8. Internal consistency (10 pts)
    try:
        t_tests = int(report.get('total_tests', 0))
        p_tests = int(report.get('passed', 0))
        f_tests = int(report.get('failed', 0))

        if t_tests == claimed_cases and p_tests + f_tests == t_tests:
            score += 10
            feedback.append('Internal arithmetic consistency verified (+10)')
        else:
            feedback.append('Internal consistency check failed (passed+failed != total or total != len).')
    except (ValueError, TypeError):
        feedback.append('Internal consistency check failed (non-integer values).')

    # Final pass determination
    key_criteria_met = (delta_cmds >= 5) and file_is_new
    passed = (score >= 60) and key_criteria_met
    
    return {'passed': passed, 'score': score, 'feedback': '; '.join(feedback)}