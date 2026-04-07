#!/usr/bin/env python3
"""
Verifier for system_readiness_audit task.

A ground station operator must perform a system readiness audit in OpenC3 COSMOS
and write a structured JSON report to /home/ga/Desktop/system_readiness.json.

Scoring breakdown (100 pts total, pass threshold = 60):
  15pts  Export metadata JSON readable
  10pts  Report JSON file exists on Desktop
  10pts  File created this session (hard gate)
  10pts  JSON has all 5 required top-level keys
  15pts  targets list matches COSMOS API ground truth (contains at least INST and INST2)
  15pts  interfaces has >= 2 entries with valid state strings
  15pts  telemetry_check has TEMP1 and TEMP2 as finite numbers
  10pts  system_ready is a boolean
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 15)
"""

import json
import os
import tempfile
import math

def verify_system_readiness_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/system_readiness_audit_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/system_readiness.json')

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

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    ground_truth_targets = export_meta.get('ground_truth_targets', ['INST', 'INST2'])

    if not file_exists:
        feedback.append('Readiness report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Readiness report exists on Desktop (+10)')

    # Hard gate: file must have been created during the session
    if not file_is_new:
        feedback.append('Readiness report predates task start — not created this session (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Readiness report created during this session (+10)')

    # ── Step 2: Parse report JSON ───────────────────────────────────────────
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
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 3: Required top-level keys ─────────────────────────────────────
    required_keys = {'audit_time', 'targets', 'interfaces', 'telemetry_check', 'system_ready'}
    missing_keys = required_keys - set(report.keys())
    if not missing_keys:
        score += 10
        feedback.append('All 5 required top-level keys present (+10)')
    else:
        feedback.append(f'Missing keys: {sorted(missing_keys)}')
        # Do not return here, allow partial points for keys that do exist

    # ── Step 4: Check targets list ──────────────────────────────────────────
    reported_targets = report.get('targets', [])
    if isinstance(reported_targets, list) and len(reported_targets) > 0:
        if 'INST' in reported_targets and 'INST2' in reported_targets:
            # Check for fabricated targets (targets not in ground truth)
            fabricated = set(reported_targets) - set(ground_truth_targets)
            if fabricated:
                score += 5
                feedback.append(f'Targets includes INST/INST2 but contains fabricated targets: {fabricated} (+5)')
            else:
                score += 15
                feedback.append('Targets list correctly matches COSMOS configuration (+15)')
        else:
            feedback.append('Targets list is missing required INST or INST2')
    else:
        feedback.append('Targets is not a valid list')

    # ── Step 5: Check interfaces ────────────────────────────────────────────
    interfaces = report.get('interfaces', {})
    if isinstance(interfaces, dict) and len(interfaces) >= 2:
        valid_entries = 0
        for name, info in interfaces.items():
            if isinstance(info, dict) and 'state' in info and isinstance(info['state'], str) and info['state'].strip() != "":
                valid_entries += 1
        if valid_entries >= 2:
            score += 15
            feedback.append(f'Interfaces dict has {valid_entries} valid entries (+15)')
        else:
            feedback.append(f'Interfaces dict has insufficient valid entries ({valid_entries} < 2)')
    else:
        feedback.append('Interfaces is not a dict or has fewer than 2 entries')

    # ── Step 6: Check telemetry_check ───────────────────────────────────────
    telemetry_check = report.get('telemetry_check', {})
    if isinstance(telemetry_check, dict):
        items = telemetry_check.get('items', {})
        if isinstance(items, dict) and 'TEMP1' in items and 'TEMP2' in items:
            t1 = items['TEMP1']
            t2 = items['TEMP2']
            if isinstance(t1, (int, float)) and isinstance(t2, (int, float)) and math.isfinite(t1) and math.isfinite(t2):
                score += 15
                feedback.append(f'Telemetry TEMP1/TEMP2 are valid numbers (+15)')
            else:
                feedback.append('Telemetry TEMP1/TEMP2 are not finite numbers')
        else:
            feedback.append('telemetry_check items missing TEMP1 or TEMP2')
    else:
        feedback.append('telemetry_check is not a dict')

    # ── Step 7: Check system_ready ──────────────────────────────────────────
    system_ready = report.get('system_ready')
    if isinstance(system_ready, bool):
        score += 10
        feedback.append('system_ready is a boolean (+10)')
    else:
        feedback.append('system_ready is not a boolean')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': '; '.join(feedback)}