#!/usr/bin/env python3
"""
Verifier for simulate_vehicle_breakdown_traci task.
Validates the Python script logic via AST and the output data via physical traffic constraints.
"""

import ast
import csv
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simulate_vehicle_breakdown(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read export results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    script_exists = result.get('script_exists', False)
    csv_exists = result.get('csv_exists', False)
    
    if not script_exists:
        return {"passed": False, "score": 0, "feedback": "simulate_breakdown.py script was not found."}
    if not csv_exists:
        return {"passed": False, "score": 10, "feedback": "Python script created, but breakdown_queue.csv output is missing (script likely failed)."}

    score += 10
    feedback_parts.append("Script and CSV output exist")

    # 2. Validate AST of the Python script (Anti-Gaming)
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    has_valid_ast = False
    uses_traci_speed = False
    uses_traci_color = False
    uses_traci_halting = False
    
    try:
        copy_from_env("/tmp/simulate_breakdown.py", temp_script.name)
        with open(temp_script.name, 'r') as f:
            script_content = f.read()
        
        # Parse AST
        tree = ast.parse(script_content)
        has_valid_ast = True
        
        # Walk AST to find specific TraCI method calls
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute):
                if node.attr == 'setSpeed':
                    uses_traci_speed = True
                elif node.attr == 'setColor':
                    uses_traci_color = True
                elif node.attr == 'getLastStepHaltingNumber':
                    uses_traci_halting = True
                    
    except SyntaxError:
        feedback_parts.append("Script has syntax errors")
    except Exception as e:
        logger.error(f"Failed to parse AST: {e}")
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    if has_valid_ast:
        score += 10
        feedback_parts.append("Valid Python Syntax")
        
    if uses_traci_speed and uses_traci_halting:
        score += 20
        feedback_parts.append("TraCI API correctly utilized")
    else:
        feedback_parts.append("Missing required TraCI API calls (setSpeed or getLastStepHaltingNumber)")

    # 3. Validate CSV Content and Traffic Physics
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    valid_csv_format = False
    reached_min_steps = False
    event_timeline_logic = False
    shockwave_physics = False
    
    try:
        copy_from_env("/tmp/breakdown_queue.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames or []
            
            # Check headers
            expected_headers = ['step', 'target_vehicle_id', 'critical_edge_halted', 'upstream_edge_halted']
            if all(h in headers for h in expected_headers):
                valid_csv_format = True
                
                rows = list(reader)
                if len(rows) >= 600:
                    reached_min_steps = True
                
                # Analyze Timeline and Logic
                breakdown_start_step = -1
                target_vid = None
                
                halted_before_breakdown = 0
                halted_during_breakdown = 0
                baseline_samples = 0
                breakdown_samples = 0
                
                for r in rows:
                    try:
                        step_val = int(r['step'])
                        tid = r['target_vehicle_id'].strip()
                        c_halted = int(r['critical_edge_halted'])
                        u_halted = int(r['upstream_edge_halted'])
                        
                        total_halted = c_halted + u_halted
                        
                        if tid == 'NONE':
                            baseline_samples += 1
                            halted_before_breakdown += total_halted
                        else:
                            if breakdown_start_step == -1:
                                breakdown_start_step = step_val
                                target_vid = tid
                            
                            # Record halted stats for the 300 steps of the breakdown
                            if step_val <= breakdown_start_step + 300:
                                breakdown_samples += 1
                                halted_during_breakdown += total_halted
                                
                    except (ValueError, KeyError):
                        continue
                
                # Check Event Logic: Target vehicle ID changes from NONE at >= 150
                if breakdown_start_step >= 150 and target_vid is not None and target_vid != 'NONE':
                    event_timeline_logic = True
                
                # Check Physics: Average halted vehicles should be higher during the breakdown
                avg_halted_before = (halted_before_breakdown / baseline_samples) if baseline_samples > 0 else 0
                avg_halted_during = (halted_during_breakdown / breakdown_samples) if breakdown_samples > 0 else 0
                
                if avg_halted_during > avg_halted_before + 0.5: # At least a slight queue formed
                    shockwave_physics = True
                    
    except Exception as e:
        logger.error(f"Failed to process CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if valid_csv_format:
        score += 10
        if reached_min_steps:
            score += 10
            feedback_parts.append("CSV formatting and step duration correct")
        else:
            feedback_parts.append("CSV lacks sufficient steps (<600)")
    else:
        feedback_parts.append("Invalid CSV headers")

    if event_timeline_logic:
        score += 20
        feedback_parts.append("Breakdown correctly initiated >= step 150")
    else:
        feedback_parts.append("Timeline logic failed (Breakdown too early or target vehicle ID missing)")

    if shockwave_physics:
        score += 20
        feedback_parts.append("Shockwave physics validated (Halted vehicles increased during incident)")
    else:
        feedback_parts.append("No queue detected (Physics validation failed)")

    # Final logic
    key_criteria_met = uses_traci_speed and valid_csv_format and event_timeline_logic
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }