#!/usr/bin/env python3
"""
Verifier for telemetry_conversion_verification task.

A ground systems engineer must verify telemetry unit conversions for the INST
satellite by querying RAW, CONVERTED, and FORMATTED representations of telemetry
items and writing a structured JSON report to /home/ga/Desktop/conversion_verification.json.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts  Export metadata JSON readable
  10pts  Output JSON file exists on Desktop
  10pts  Output file created after task start [hard gate]
  10pts  JSON has all 6 required top-level keys
   5pts  verification_timestamp is a valid ISO 8601 datetime
   5pts  target is 'INST' and packet is 'HEALTH_STATUS'
  20pts  items_verified has >= 4 entries including TEMP1, TEMP2, TEMP3, TEMP4
  20pts  All items have correct field types (raw_value: numeric, formatted_value: string, etc.)
  10pts  total_items_checked and all_conversions_valid match items_verified content

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import os
import tempfile
from datetime import datetime

def verify_telemetry_conversion_verification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/telemetry_conversion_verification_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/conversion_verification.json')

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

    if not file_exists:
        feedback.append('Verification report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Verification report exists on Desktop (+10)')

    # Hard gate: file must have been created during the session
    if not file_is_new:
        feedback.append('Verification report predates task start — not created this session (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Verification report created during this session (+10)')

    # ── Step 2: Parse report JSON ───────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Verification report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy verification report: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 3: Required top-level keys ─────────────────────────────────────
    required_keys = {'verification_timestamp', 'target', 'packet', 'items_verified', 'total_items_checked', 'all_conversions_valid'}
    missing_keys = required_keys - set(report.keys())
    
    if not missing_keys:
        score += 10
        feedback.append('All 6 required top-level keys present (+10)')
    else:
        feedback.append(f'Missing keys: {sorted(missing_keys)} — stopping here')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 4: Validate timestamp ──────────────────────────────────────────
    timestamp_str = report.get('verification_timestamp', '')
    try:
        # Handle 'Z' suffix commonly found in JS/ISO exports
        clean_ts = timestamp_str.replace('Z', '+00:00')
        datetime.fromisoformat(clean_ts)
        score += 5
        feedback.append('verification_timestamp is valid ISO 8601 (+5)')
    except (ValueError, TypeError):
        feedback.append(f'verification_timestamp "{timestamp_str}" is not a valid ISO 8601 string')

    # ── Step 5: Target and Packet validation ────────────────────────────────
    target = str(report.get('target', '')).strip().upper()
    packet = str(report.get('packet', '')).strip().upper()
    
    if target == 'INST' and packet == 'HEALTH_STATUS':
        score += 5
        feedback.append('Target and packet correctly identified (+5)')
    else:
        feedback.append(f'Incorrect target/packet. Expected INST/HEALTH_STATUS, got {target}/{packet}')

    # ── Step 6: Validate items array and requirements ───────────────────────
    items = report.get('items_verified', [])
    if not isinstance(items, list):
        feedback.append('items_verified is not an array')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    item_names = [str(item.get('item_name', '')).upper() for item in items if isinstance(item, dict)]
    required_items = {'TEMP1', 'TEMP2', 'TEMP3', 'TEMP4'}
    
    if len(items) >= 4 and required_items.issubset(set(item_names)):
        score += 20
        feedback.append(f'items_verified contains >= 4 items including required temps (+20)')
    else:
        missing_temps = required_items - set(item_names)
        feedback.append(f'items_verified failed requirement: missing temps {missing_temps} or count < 4')

    # ── Step 7: Validate field types ────────────────────────────────────────
    all_fields_correct = True
    if len(items) == 0:
        all_fields_correct = False
        feedback.append('items_verified is empty')
    else:
        for i, item in enumerate(items):
            if not isinstance(item, dict):
                all_fields_correct = False
                feedback.append(f'Item at index {i} is not a JSON object')
                break
                
            required_item_keys = {'item_name', 'raw_value', 'converted_value', 'formatted_value', 'conversion_valid'}
            if not required_item_keys.issubset(set(item.keys())):
                all_fields_correct = False
                feedback.append(f'Item {item.get("item_name", f"index {i}")} is missing required fields')
                break
            
            # Check types
            if not isinstance(item['item_name'], str):
                all_fields_correct = False
                break
            if not isinstance(item['raw_value'], (int, float)):
                all_fields_correct = False
                break
            if not isinstance(item['converted_value'], (int, float)):
                all_fields_correct = False
                break
            if not isinstance(item['formatted_value'], str):
                all_fields_correct = False
                break
            if not isinstance(item['conversion_valid'], bool):
                all_fields_correct = False
                break

    if all_fields_correct:
        score += 20
        feedback.append('All verified items have correct field types (+20)')
    else:
        feedback.append('One or more verified items have incorrect or missing fields/types')

    # ── Step 8: Internal Consistency ────────────────────────────────────────
    try:
        total_items = int(report.get('total_items_checked', -1))
        all_valid_flag = report.get('all_conversions_valid')
        
        expected_all_valid = all(item.get('conversion_valid', False) for item in items if isinstance(item, dict))
        
        consistent_len = total_items == len(items)
        consistent_bool = isinstance(all_valid_flag, bool) and all_valid_flag == expected_all_valid
        
        if consistent_len and consistent_bool:
            score += 10
            feedback.append('Internal report consistency checks passed (+10)')
        else:
            feedback.append(f'Internal consistency failed: length match={consistent_len}, bool match={consistent_bool}')
    except (ValueError, TypeError):
        feedback.append('Internal consistency check failed due to invalid types')

    # ── Final evaluation ────────────────────────────────────────────────────
    passed = score >= 60 and (len(items) >= 4 and required_items.issubset(set(item_names)))
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }