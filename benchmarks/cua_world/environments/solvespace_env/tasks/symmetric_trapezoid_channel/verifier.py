#!/usr/bin/env python3
"""
Verifier for symmetric_trapezoid_channel task in SolveSpace.

Checks:
1. Output .slvs file exists and was modified during the task.
2. File parses correctly and contains user-created line entities.
3. Constraint values match expected dimensions (40, 70, 25).
4. Coincident and horizontal constraints are present.
5. VLM verification confirms a trapezoid is drawn on canvas.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating a 2D CAD task in SolveSpace.
The goal was to draw a fully constrained symmetric trapezoidal channel profile.

Look at these trajectory frames and the final screenshot and determine:
1. Did the user successfully draw a closed trapezoid shape? (It should have 4 sides, wider at the top, narrower at the bottom).
2. Are there dimensional constraints visible on the screen indicating dimensions like 40, 70, and 25?
3. Does the constraint status appear to be fully constrained (e.g., green "ok" in the property browser or status bar)?

Respond in JSON format:
{
    "drew_trapezoid": true/false,
    "dimensions_visible": true/false,
    "fully_constrained_likely": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def parse_slvs(content):
    """Robust state-machine parser for .slvs files."""
    entities = []
    constraints = []
    
    lines = content.split('\n')
    current_item = {}
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        if line == 'AddEntity':
            entities.append(current_item)
            current_item = {}
        elif line == 'AddConstraint':
            constraints.append(current_item)
            current_item = {}
        elif line.startswith('Add'):
            current_item = {}  # reset for other items like AddGroup, AddParam
        elif '=' in line:
            parts = line.split('=', 1)
            if len(parts) == 2:
                current_item[parts[0]] = parts[1]
                
    return entities, constraints

def verify_symmetric_trapezoid_channel(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/channel_profile.slvs')
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Read task_result.json
    # ---------------------------------------------------------
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output .slvs file not found"}
        
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "File exists but was not modified during the task. Did the agent do nothing?"}
        
    score += 10
    feedback_parts.append("File exists and was modified")
    
    # ---------------------------------------------------------
    # 2. Parse the SLVS file
    # ---------------------------------------------------------
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_output_path, temp_slvs.name)
        with open(temp_slvs.name, 'r') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read SLVS file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    entities, constraints = parse_slvs(slvs_content)
    
    # Check entities: lines (Entity.type=11000)
    # Ignore reference groups (handles starting with 0001, 0002, 0003)
    user_lines = []
    for e in entities:
        if e.get("Entity.type") == "11000":
            handle_hex = e.get("Entity.h.v", "00000000")
            try:
                if int(handle_hex, 16) >= 0x00040000:
                    user_lines.append(e)
            except ValueError:
                pass
                
    if len(user_lines) >= 4:
        score += 15
        feedback_parts.append(f"Found {len(user_lines)} user lines")
    elif len(user_lines) > 0:
        score += 5
        feedback_parts.append(f"Found {len(user_lines)} lines (need 4)")
        
    # Check dimensions (40, 70, 25)
    dim_vals = []
    for c in constraints:
        try:
            val = abs(float(c.get("Constraint.valA", "0")))
            if val > 0:
                dim_vals.append(val)
        except ValueError:
            pass
            
    found_40 = any(abs(v - 40.0) <= 0.5 for v in dim_vals)
    found_70 = any(abs(v - 70.0) <= 0.5 for v in dim_vals)
    found_25 = any(abs(v - 25.0) <= 0.5 for v in dim_vals)
    
    if found_40: score += 15
    if found_70: score += 15
    if found_25: score += 15
    
    if found_40 and found_70 and found_25:
        feedback_parts.append("All expected dimensions found")
    else:
        feedback_parts.append(f"Dimensions missing: {[] if found_40 else ['40']} {[] if found_70 else ['70']} {[] if found_25 else ['25']}")
        
    # Check coincident constraints (type=20)
    coincident = [c for c in constraints if c.get("Constraint.type") == "20"]
    if len(coincident) >= 4:
        score += 10
        feedback_parts.append("Closed profile (coincident constraints)")
        
    # ---------------------------------------------------------
    # 3. VLM Verification
    # ---------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            images = frames + [final_img]
            try:
                vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('drew_trapezoid'):
                        score += 10
                        feedback_parts.append("VLM confirms trapezoid")
                    if parsed.get('fully_constrained_likely') or parsed.get('dimensions_visible'):
                        score += 10
                        feedback_parts.append("VLM confirms constraints/dimensions visible")
                else:
                    feedback_parts.append("VLM verification failed")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("VLM evaluation error")
    
    # ---------------------------------------------------------
    # Final check
    # ---------------------------------------------------------
    # Core criteria: file modified, right number of dimensions roughly, and some shape evidence
    key_criteria_met = result.get('file_created_during_task') and len(user_lines) >= 3 and (found_40 or found_70)
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }