#!/usr/bin/env python3
import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ship_hydrodynamics_calibration(traj, env_info, task_info):
    """
    Verify the ship calibration task.
    
    Scoring Criteria:
    1. Unit Conversion (Length/Beam): 20 pts
    2. RudderArea Calculation: 30 pts
    3. DragArea Calculation: 30 pts
    4. Metadata Update (Description): 10 pts
    5. Certificate File Creation: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load metadata / ground truth
    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})
    required_desc_string = metadata.get('required_string', "Calibrated 2025")
    
    # Ground Truth Values
    # We allow a 5% tolerance as specified in metadata
    gt_length = gt.get('length_m', 165.0)
    gt_beam = gt.get('beam_m', 23.0)
    gt_rudder = gt.get('rudder_area', 455.7)
    gt_drag = gt.get('drag_area', 16.5)
    tolerance = gt.get('tolerance_percent', 5.0) / 100.0
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    ini_data = result.get('ini_data', {})
    values = ini_data.get('values', {})
    
    # Check 1: Unit Conversions (Length/Beam) - 20 pts
    try:
        agent_length = float(values.get('Length', 0))
        agent_beam = float(values.get('Beam', 0))
        
        # Check Length (165.0 m)
        if abs(agent_length - gt_length) < 0.5:
            score += 10
            feedback.append(f"Length correct ({agent_length})")
        else:
            feedback.append(f"Length incorrect (Got {agent_length}, Expected ~{gt_length})")
            
        # Check Beam (23.0 m)
        if abs(agent_beam - gt_beam) < 0.5:
            score += 10
            feedback.append(f"Beam correct ({agent_beam})")
        else:
            feedback.append(f"Beam incorrect (Got {agent_beam}, Expected ~{gt_beam})")
            
    except ValueError:
        feedback.append("Could not parse dimensions as numbers")

    # Check 2: RudderArea - 30 pts
    try:
        agent_rudder = float(values.get('RudderArea', 0))
        rudder_error = abs(agent_rudder - gt_rudder) / gt_rudder
        
        if rudder_error <= tolerance:
            score += 30
            feedback.append(f"RudderArea correct ({agent_rudder})")
        elif rudder_error <= 0.2: # Partial credit for being in the ballpark
            score += 10
            feedback.append(f"RudderArea close but outside tolerance ({agent_rudder}, expected ~{gt_rudder})")
        else:
            feedback.append(f"RudderArea incorrect ({agent_rudder}, expected ~{gt_rudder})")
            
    except ValueError:
        feedback.append("Could not parse RudderArea")

    # Check 3: DragArea - 30 pts
    try:
        agent_drag = float(values.get('DragArea', 0))
        drag_error = abs(agent_drag - gt_drag) / gt_drag
        
        if drag_error <= tolerance:
            score += 30
            feedback.append(f"DragArea correct ({agent_drag})")
        elif drag_error <= 0.2:
            score += 10
            feedback.append(f"DragArea close but outside tolerance ({agent_drag}, expected ~{gt_drag})")
        else:
            feedback.append(f"DragArea incorrect ({agent_drag}, expected ~{gt_drag})")
            
    except ValueError:
        feedback.append("Could not parse DragArea")

    # Check 4: Metadata Update - 10 pts
    description = values.get('Description', '')
    if required_desc_string.lower() in description.lower():
        score += 10
        feedback.append("Description updated correctly")
    else:
        feedback.append(f"Description missing required text '{required_desc_string}'")

    # Check 5: Certificate Creation - 10 pts
    if result.get('certificate_exists'):
        score += 10
        feedback.append("Certificate file created")
    else:
        feedback.append("Certificate file missing")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }