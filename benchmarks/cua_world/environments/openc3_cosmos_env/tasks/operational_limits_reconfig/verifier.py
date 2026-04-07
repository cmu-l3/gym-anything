#!/usr/bin/env python3
"""
Verifier for operational_limits_reconfig task.

A flight dynamics controller must change the operational limits of INST TEMP1
to eclipse-phase values via OpenC3 COSMOS and document the original and new
values in a JSON report on the Desktop.

Verification ensures both the backend COSMOS state actually changed, and the
documentation reflects those changes.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts  Result metadata JSON readable
   5pts  Report JSON file exists on Desktop
   5pts  File created after task start (hard gate for file content)
  30pts  Limits actually changed in COSMOS (API current != initial)
  15pts  All four limits match specified target values (±0.5) in COSMOS API
  10pts  Report has all 4 required top-level keys
  10pts  `original_limits` in report is valid (4 numeric values)
  15pts  `new_limits` in report matches specified targets (±0.5)
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_float_equal(a, b, tol=0.5):
    try:
        return abs(float(a) - float(b)) <= tol
    except (ValueError, TypeError):
        return False

def verify_operational_limits_reconfig(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/operational_limits_reconfig_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/limits_change_report.json')
    target_limits = meta.get('target_limits', [-100.0, -90.0, 60.0, 80.0])

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
    initial_limits = export_meta.get('initial_limits', [])
    current_limits = export_meta.get('current_limits', [])

    # ── Step 2: COSMOS API State Checks (Backend verification) ──────────────
    api_limits_changed = False
    
    # Check if limits array has elements and differs from initial
    if isinstance(current_limits, list) and len(current_limits) >= 4:
        if current_limits != initial_limits:
            api_limits_changed = True
            score += 30
            feedback.append('Limits successfully changed in COSMOS API (+30)')
        else:
            feedback.append('Limits in COSMOS API are unchanged from start state')
        
        # Check if they match exact targets
        api_matches = all(is_float_equal(current_limits[i], target_limits[i]) for i in range(4))
        if api_matches:
            score += 15
            feedback.append('COSMOS API limits match target eclipse values (+15)')
        else:
            feedback.append(f'COSMOS API limits {current_limits[:4]} do not match targets {target_limits}')
    else:
        feedback.append('Could not read valid current limits from COSMOS API')

    # ── Step 3: Report File Existence ───────────────────────────────────────
    if not file_exists:
        feedback.append('Limits change report not found on Desktop')
        # We can still pass if API changes were perfect and score >= 60, but without file it's max 55.
        return {'passed': score >= 60, 'score': score, 'feedback': '; '.join(feedback)}

    score += 5
    feedback.append('Limits change report exists (+5)')

    if file_is_new:
        score += 5
        feedback.append('Report created during this session (+5)')
    else:
        feedback.append('Report predates task start (no content credit)')
        return {'passed': score >= 60, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 4: Parse Report JSON ───────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except Exception as e:
        feedback.append(f'Could not parse report JSON: {e}')
        return {'passed': score >= 60, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 5: Required top-level keys ─────────────────────────────────────
    required_keys = {'item', 'original_limits', 'new_limits', 'change_reason'}
    if isinstance(report, dict):
        missing_keys = required_keys - set(report.keys())
        if not missing_keys:
            score += 10
            feedback.append('All 4 required keys present (+10)')
        else:
            feedback.append(f'Missing keys in report: {sorted(missing_keys)}')
    else:
        feedback.append('Report is not a JSON object')
        return {'passed': score >= 60, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 6: Validate `original_limits` ──────────────────────────────────
    orig_lims = report.get('original_limits', {})
    if isinstance(orig_lims, dict):
        lim_keys = ['red_low', 'yellow_low', 'yellow_high', 'red_high']
        has_all_lims = all(k in orig_lims for k in lim_keys)
        if has_all_lims:
            try:
                # Must be finite numbers
                valid_nums = all(math.isfinite(float(orig_lims[k])) for k in lim_keys)
                if valid_nums:
                    score += 10
                    feedback.append('original_limits valid and numeric (+10)')
                else:
                    feedback.append('original_limits contains non-finite values')
            except (ValueError, TypeError):
                feedback.append('original_limits contains non-numeric values')
        else:
            feedback.append(f'original_limits missing required keys')
    else:
        feedback.append('original_limits is not a dictionary')

    # ── Step 7: Validate `new_limits` targets ───────────────────────────────
    new_lims = report.get('new_limits', {})
    if isinstance(new_lims, dict):
        lim_keys = ['red_low', 'yellow_low', 'yellow_high', 'red_high']
        has_all_lims = all(k in new_lims for k in lim_keys)
        if has_all_lims:
            matches = [
                is_float_equal(new_lims['red_low'], target_limits[0]),
                is_float_equal(new_lims['yellow_low'], target_limits[1]),
                is_float_equal(new_lims['yellow_high'], target_limits[2]),
                is_float_equal(new_lims['red_high'], target_limits[3])
            ]
            if all(matches):
                score += 15
                feedback.append('new_limits in report match target values (+15)')
            else:
                feedback.append('new_limits in report do not match the expected targets')
        else:
            feedback.append('new_limits missing required keys')
    else:
        feedback.append('new_limits is not a dictionary')

    passed = score >= 60 and api_limits_changed

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }