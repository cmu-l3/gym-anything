#!/usr/bin/env python3
"""
Verifier for transport_phase_state_prediction task.
Parses the agent's report file and verifies melting points, boiling points,
and phase state predictions against ground truth logic.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report(content):
    """
    Parses the structured text report into a dictionary.
    Expected format:
    Chemical: [Name]
      Melting Point: [Val] C
      Boiling Point: [Val] C
      State at -10C: [State]
      State at 45C: [State]
    """
    data = {}
    current_chem = None
    
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Match Chemical header
        chem_match = re.match(r"Chemical:\s*(.+)", line, re.IGNORECASE)
        if chem_match:
            current_chem = chem_match.group(1).strip()
            data[current_chem] = {}
            continue
            
        if current_chem:
            # Match Properties
            mp_match = re.match(r"Melting Point:\s*([-\d\.]+)", line, re.IGNORECASE)
            bp_match = re.match(r"Boiling Point:\s*([-\d\.]+)", line, re.IGNORECASE)
            state_low_match = re.match(r"State at -10C:\s*(\w+)", line, re.IGNORECASE)
            state_high_match = re.match(r"State at 45C:\s*(\w+)", line, re.IGNORECASE)
            
            if mp_match:
                try:
                    data[current_chem]['mp'] = float(mp_match.group(1))
                except ValueError:
                    pass
            elif bp_match:
                try:
                    data[current_chem]['bp'] = float(bp_match.group(1))
                except ValueError:
                    pass
            elif state_low_match:
                data[current_chem]['state_neg10'] = state_low_match.group(1).capitalize()
            elif state_high_match:
                data[current_chem]['state_pos45'] = state_high_match.group(1).capitalize()
                
    return data

def verify_phase_state_prediction(traj, env_info, task_info):
    """
    Verifies the chemical phase state prediction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get ground truth from metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    expected_chemicals = list(ground_truth.keys())
    
    # 1. Check basic file existence and timestamp from result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_info = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    if not result_info.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected location."}
        
    if not result_info.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file exists but was not created during this task session (stale file)."}

    # 2. Retrieve and parse the actual report content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(metadata.get('output_file', '/home/ga/Documents/phase_state_report.txt'), temp_report.name)
        with open(temp_report.name, 'r') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    parsed_data = parse_report(content)
    
    # 3. Score the content
    score = 0
    feedback_parts = []
    
    # Points breakdown: 10 pts for file existence (already passed if we are here)
    score += 10
    
    # 22.5 points available per chemical (90 pts total remaining)
    # Breakdown per chemical: 
    # - Found in report: 5 pts
    # - MP correct (+/- 5 deg): 2.5 pts
    # - BP correct (+/- 5 deg): 2.5 pts
    # - State -10C correct: 5 pts
    # - State 45C correct: 5 pts
    # - Consistency bonus: 2.5 pts (if predicted state matches the provided MP/BP logic, even if values wrong)

    passed_chemicals = 0
    
    for chem_name, gt in ground_truth.items():
        # Find matching chemical in report (case insensitive match)
        match_key = None
        for key in parsed_data:
            if chem_name.lower() in key.lower():
                match_key = key
                break
        
        if not match_key:
            feedback_parts.append(f"❌ Missing {chem_name}")
            continue
            
        chem_data = parsed_data[match_key]
        chem_score = 5 # Found it
        chem_feedback = [f"{chem_name}:"]
        
        # Check MP
        mp_val = chem_data.get('mp')
        if mp_val is not None and abs(mp_val - gt['mp_approx']) <= 5.0:
            chem_score += 2.5
        else:
            chem_feedback.append(f"MP mismatch ({mp_val} vs {gt['mp_approx']})")

        # Check BP
        bp_val = chem_data.get('bp')
        if bp_val is not None and abs(bp_val - gt['bp_approx']) <= 5.0:
            chem_score += 2.5
        else:
            chem_feedback.append(f"BP mismatch ({bp_val} vs {gt['bp_approx']})")

        # Check State at -10C
        # Ground truth check
        pred_neg10 = chem_data.get('state_neg10', 'Unknown')
        if pred_neg10.lower() == gt['state_neg10'].lower():
            chem_score += 5
        else:
            chem_feedback.append(f"-10C state wrong ({pred_neg10})")

        # Check State at 45C
        # Ground truth check
        pred_pos45 = chem_data.get('state_pos45', 'Unknown')
        if pred_pos45.lower() == gt['state_pos45'].lower():
            chem_score += 5
        else:
            chem_feedback.append(f"45C state wrong ({pred_pos45})")

        # Consistency Check (Logic Validation)
        # If the user supplied MP/BP, does their state prediction follow logic?
        # Only grant if they provided numeric MP/BP
        logic_bonus = True
        if mp_val is not None and bp_val is not None:
            # Check -10C Logic
            expected_state_neg10 = "Solid" if -10 < mp_val else ("Liquid" if -10 < bp_val else "Gas")
            if pred_neg10.lower() != expected_state_neg10.lower():
                logic_bonus = False
            
            # Check 45C Logic
            expected_state_pos45 = "Solid" if 45 < mp_val else ("Liquid" if 45 < bp_val else "Gas")
            if pred_pos45.lower() != expected_state_pos45.lower():
                logic_bonus = False
                
            if logic_bonus:
                chem_score += 2.5
        
        score += chem_score
        
        if chem_score >= 15: # Roughly 2/3 correct for this chemical
            passed_chemicals += 1
            
        if len(chem_feedback) > 1:
            feedback_parts.append(" ".join(chem_feedback))
        else:
            feedback_parts.append(f"✅ {chem_name}")

    final_score = min(100, score) # Cap at 100
    
    # Pass criteria: File exists + reasonable score (>75) + at least 3/4 chemicals mostly correct
    passed = (final_score >= 75) and (passed_chemicals >= 3)
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }