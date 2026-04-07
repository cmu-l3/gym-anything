#!/usr/bin/env python3
"""
Verifier for configure_quadruped_impedance task.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Timestep set to 8: 10 points
  - FL_KNEE impedance correctly set: 20 points (10 spring, 10 damping)
  - FR_KNEE impedance correctly set: 20 points (10 spring, 10 damping)
  - RL_KNEE impedance correctly set: 20 points (10 spring, 10 damping)
  - RR_KNEE impedance correctly set: 20 points (10 spring, 10 damping)
  - Penalty: -5 points for every hip joint improperly modified
  
Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_joint_params(content, joint_def):
    """Extract spring and damping constants from a specific HingeJoint."""
    idx = content.find(f"DEF {joint_def}")
    if idx == -1:
        return None
    
    param_idx = content.find("HingeJointParameters {", idx)
    if param_idx == -1 or param_idx > idx + 500:
        return {}
        
    brace_count = 1
    i = param_idx + len("HingeJointParameters {")
    while i < len(content):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                break
        i += 1
        
    param_block = content[param_idx:i]
    
    spring_match = re.search(r'springConstant\s+([\d.]+)', param_block)
    damping_match = re.search(r'dampingConstant\s+([\d.]+)', param_block)
    
    return {
        'springConstant': float(spring_match.group(1)) if spring_match else 0.0,
        'dampingConstant': float(damping_match.group(1)) if damping_match else 0.0
    }

def verify_configure_quadruped_impedance(traj, env_info, task_info):
    """
    Verify that the quadruped world was successfully configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
        
    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/quadruped_impedance.wbt')
    
    score = 0
    feedback_parts = []
    
    # --- Copy the .wbt file independently ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None
    
    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass
            
    # --- Check file existence ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }
        
    score += 10
    feedback_parts.append("World file saved at correct path")
    
    # --- Check basicTimeStep ---
    timestep_match = re.search(r'basicTimeStep\s+([\d.]+)', wbt_content)
    if timestep_match:
        actual_timestep = float(timestep_match.group(1))
        # Provide small flexibility
        if 4.0 <= actual_timestep <= 10.0:
            score += 10
            feedback_parts.append(f"basicTimeStep correctly set to {actual_timestep} ms")
        else:
            feedback_parts.append(f"basicTimeStep is {actual_timestep} ms, expected 8 ms")
    else:
        feedback_parts.append("basicTimeStep field not found")
        
    # --- Check knee joints ---
    knees = ['FL_KNEE', 'FR_KNEE', 'RL_KNEE', 'RR_KNEE']
    for knee in knees:
        params = extract_joint_params(wbt_content, knee)
        if params is None:
            feedback_parts.append(f"{knee} node missing entirely")
            continue
            
        spring = params.get('springConstant', 0.0)
        damping = params.get('dampingConstant', 0.0)
        
        knee_score = 0
        if 39.0 <= spring <= 41.0:
            knee_score += 10
            score += 10
        if 1.9 <= damping <= 2.1:
            knee_score += 10
            score += 10
            
        if knee_score == 20:
            feedback_parts.append(f"{knee} impedance correct")
        else:
            feedback_parts.append(f"{knee} incorrect: spring={spring}, damping={damping}")
            
    # --- Check hip joints (penalty check) ---
    hips = ['FL_HIP', 'FR_HIP', 'RL_HIP', 'RR_HIP']
    hips_modified = False
    for hip in hips:
        params = extract_joint_params(wbt_content, hip)
        if params is not None:
            spring = params.get('springConstant', 0.0)
            damping = params.get('dampingConstant', 0.0)
            if spring > 0.0 or damping > 0.0:
                hips_modified = True
                score = max(10, score - 5)  # Can't drop below the 10 points for saving the file
                feedback_parts.append(f"Penalty (-5): {hip} was modified (should be rigid)")
                
    if not hips_modified:
        feedback_parts.append("Hip joints correctly left unmodified")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }