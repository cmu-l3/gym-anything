#!/usr/bin/env python3
"""
Verifier for external_stakeholder_dashboard task.

The agent must command the satellite, query telemetry (including limits), and
generate an HTML dashboard containing a table with specific telemetry items.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts  Result metadata JSON readable
  10pts  HTML file exists on Desktop
  15pts  HTML file created after task start [hard gate]
  15pts  Command verified in COSMOS (current_cmd_cnt > initial)
  15pts  HTML table structure valid (has rows for all 6 required params)
  20pts  Dynamic value verified (CMD_ACPT_CNT in HTML > initial baseline)
  15pts  Limit states documented (valid limit keywords in the rows)
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_external_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/dashboard_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/stakeholder_dashboard.html')
    required_params = [p.upper() for p in meta.get('required_params', ['TEMP1', 'TEMP2', 'TEMP3', 'TEMP4', 'COLLECTS', 'CMD_ACPT_CNT'])]
    limit_keywords = [k.upper() for k in meta.get('limit_keywords', ['NOMINAL', 'GREEN', 'OK', 'YELLOW', 'RED', 'HIGH', 'LOW'])]

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
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    
    try:
        initial_cmd = float(export_meta.get('initial_cmd_cnt', 0))
        current_cmd = float(export_meta.get('current_cmd_cnt', 0))
    except (ValueError, TypeError):
        initial_cmd, current_cmd = 0.0, 0.0

    # ── Step 2: System-level Command Verification ───────────────────────────
    command_sent = current_cmd > initial_cmd
    if command_sent:
        score += 15
        feedback.append(f'Command successfully sent in COSMOS ({initial_cmd} -> {current_cmd}) (+15)')
    else:
        feedback.append(f'Command NOT detected in COSMOS (count unchanged at {initial_cmd})')

    # ── Step 3: File Existence & Freshness ──────────────────────────────────
    if not file_exists:
        feedback.append('HTML dashboard not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('HTML file exists (+10)')

    if not file_is_new:
        feedback.append('HTML file predates task start (no content credit awarded)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append('HTML file created this session (+15)')

    # ── Step 4: Parse HTML File ─────────────────────────────────────────────
    html_content = ""
    try:
        with tempfile.NamedTemporaryFile(suffix='.html', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r', encoding='utf-8') as f:
            html_content = f.read()
    except Exception as e:
        feedback.append(f'Could not copy HTML file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # Extract table rows. We use a regex robust to newlines and attributes
    # We find all <tr>...</tr> blocks
    tr_matches = re.findall(r'<tr[^>]*>(.*?)</tr>', html_content, flags=re.IGNORECASE | re.DOTALL)
    
    # Convert each row's HTML into clean text by stripping internal tags
    row_texts = []
    for tr in tr_matches:
        # replace any <... > with space
        clean_text = re.sub(r'<[^>]+>', ' ', tr)
        # normalize whitespace
        clean_text = ' '.join(clean_text.split()).upper()
        row_texts.append(clean_text)

    # ── Step 5: Content Verification ────────────────────────────────────────
    params_found = 0
    limits_documented = 0
    dynamic_val_verified = False

    for param in required_params:
        param_row = None
        # Find the row containing this parameter name
        for rt in row_texts:
            # Look for exact word match of the parameter to avoid substring bugs
            if re.search(rf'\b{param}\b', rt):
                param_row = rt
                break
        
        if param_row:
            params_found += 1
            
            # Check for limit states in the same row
            if any(kw in param_row for kw in limit_keywords):
                limits_documented += 1
                
            # Dynamic value check for CMD_ACPT_CNT
            if param == 'CMD_ACPT_CNT':
                # Extract all numbers from the row
                numbers = re.findall(r'\b\d+(?:\.\d+)?\b', param_row)
                for num_str in numbers:
                    try:
                        if float(num_str) > initial_cmd:
                            dynamic_val_verified = True
                            break
                    except ValueError:
                        continue

    # Score: HTML table structure (up to 15 pts, 2.5 per param)
    structure_score = int((params_found / len(required_params)) * 15)
    score += structure_score
    feedback.append(f'HTML structure: {params_found}/{len(required_params)} params found (+{structure_score})')

    # Score: Limit states documented (up to 15 pts, 2.5 per param)
    limits_score = int((limits_documented / len(required_params)) * 15)
    score += limits_score
    feedback.append(f'Limit states: {limits_documented}/{len(required_params)} valid limits found (+{limits_score})')

    # Score: Dynamic value (20 pts)
    if dynamic_val_verified:
        score += 20
        feedback.append('Dynamic value verified (CMD_ACPT_CNT in HTML > initial baseline) (+20)')
    else:
        feedback.append('Dynamic value failed (CMD_ACPT_CNT in HTML did not show newly commanded data)')

    # Final evaluation
    key_criteria_met = file_is_new and command_sent and dynamic_val_verified and (params_found >= 4)
    passed = score >= 60 and key_criteria_met

    if passed:
        feedback.append('SUCCESS: Agent successfully commanded target and generated live dashboard.')
    else:
        feedback.append('FAILED: Did not meet required score or key criteria.')

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }