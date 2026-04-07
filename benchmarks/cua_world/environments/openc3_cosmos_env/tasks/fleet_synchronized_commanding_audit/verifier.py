#!/usr/bin/env python3
"""
Verifier for fleet_synchronized_commanding_audit task.

A constellation operator must audit closed-loop commanding for multiple satellites
in OpenC3 COSMOS and write a structured JSON report to
/home/ga/Desktop/fleet_command_report.json.

Scoring breakdown (100 pts total, pass threshold = 60):
   5pts  Export metadata JSON readable
  10pts  Report file exists on Desktop and was created during task [Hard Gate]
  25pts  INST system count increased (command accepted by INST via telemetry)
  25pts  INST2 system count increased (command accepted by INST2 via telemetry)
  10pts  JSON structure valid with required targets (INST, INST2)
  25pts  JSON content mathematically valid (delta logic and booleans match inputs)
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 5)
"""

import json
import os
import tempfile


def verify_fleet_synchronized_commanding_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}
        
    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/fleet_command_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/fleet_command_report.json')
    
    score = 0
    feedback = []
    
    # ── Step 1: Read export metadata (Anti-Gaming Ground Truth) ───────────────────
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
        score += 5
        feedback.append('Export metadata readable (+5)')
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
    
    try:
        initial_inst = int(float(export_meta.get('initial_inst_count', 0)))
        final_inst = int(float(export_meta.get('final_inst_count', 0)))
    except (TypeError, ValueError):
        initial_inst, final_inst = 0, 0
        
    try:
        initial_inst2 = int(float(export_meta.get('initial_inst2_count', 0)))
        final_inst2 = int(float(export_meta.get('final_inst2_count', 0)))
    except (TypeError, ValueError):
        initial_inst2, final_inst2 = 0, 0
        
    inst_increased = final_inst > initial_inst
    inst2_increased = final_inst2 > initial_inst2
    
    # Check physical system changes regardless of output file (Anti-Gaming)
    if inst_increased:
        score += 25
        feedback.append(f'INST system count increased (count: {initial_inst} → {final_inst}) (+25)')
    else:
        feedback.append(f'INST system count did NOT increase (count: {initial_inst} → {final_inst})')
        
    if inst2_increased:
        score += 25
        feedback.append(f'INST2 system count increased (count: {initial_inst2} → {final_inst2}) (+25)')
    else:
        feedback.append(f'INST2 system count did NOT increase (count: {initial_inst2} → {final_inst2})')
        
    # Check output file conditions
    if not file_exists:
        feedback.append('Report file not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    if not file_is_new:
        feedback.append('Report file predates task start (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    score += 10
    feedback.append('Report file exists and is fresh (+10)')
    
    # ── Step 2: Parse report JSON ──────────────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except Exception as e:
        feedback.append(f'Could not parse report file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass
            
    # ── Step 3: Validate JSON structure ────────────────────────────────────────────
    required_keys = {'execution_timestamp', 'fleet_status'}
    if not required_keys.issubset(set(report.keys())):
        feedback.append(f'Report missing top-level keys. Required: {required_keys}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    fleet_status = report.get('fleet_status')
    if not isinstance(fleet_status, list):
        feedback.append('fleet_status must be a list')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    target_names = []
    for entry in fleet_status:
        if isinstance(entry, dict) and 'target' in entry:
            target_names.append(entry['target'])
            
    if 'INST' not in target_names or 'INST2' not in target_names:
        feedback.append('fleet_status missing required targets INST and INST2')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    score += 10
    feedback.append('JSON structure valid with required targets (+10)')
    
    # ── Step 4: JSON content mathematically valid ──────────────────────────────────
    valid_math = True
    for entry in fleet_status:
        try:
            init_c = int(entry.get('initial_cmd_acpt_cnt', 0))
            final_c = int(entry.get('final_cmd_acpt_cnt', 0))
            delta = int(entry.get('delta', 0))
            verified = bool(entry.get('verified', False))
            
            calc_delta = final_c - init_c
            calc_verified = calc_delta >= 1
            
            if delta != calc_delta:
                valid_math = False
                feedback.append(f"Math error for target {entry.get('target')}: {final_c} - {init_c} != {delta}")
            if verified != calc_verified:
                valid_math = False
                feedback.append(f"Logic error for target {entry.get('target')}: expected verified={calc_verified}, got {verified}")
        except (TypeError, ValueError) as e:
            valid_math = False
            feedback.append(f"Value error in fleet_status: {e}")
            break
            
    if valid_math:
        score += 25
        feedback.append('JSON content mathematically valid (+25)')
        
    # Minimum requirement to pass: 60 points + file created + commands actually accepted
    key_criteria_met = file_is_new and inst_increased and inst2_increased and valid_math
    passed = score >= 60 and key_criteria_met
    
    return {'passed': passed, 'score': score, 'feedback': '; '.join(feedback)}