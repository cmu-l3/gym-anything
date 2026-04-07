#!/usr/bin/env python3
"""
Verifier for slot_profile_tangent task.

Multi-Criteria Verification:
1. File Creation & Modification: Verifies the file exists and was actively edited during the task.
2. File Structure Parsing: Solvespace slvs files are text-based. We parse for:
   - Line segments (Entity.type=11000)
   - Arc segments (Entity.type=14000)
   - Tangent constraints (Constraint.type=55)
   - Dimension values (near 40mm and 12mm/6mm)
3. VLM Verification: Analyzes trajectory and final screenshot to confirm the visual presence
   of a stadium/oblong slot profile.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a CAD design task in SolveSpace. 
The user was asked to draw a 'stadium' or 'slot' profile: an oblong shape consisting of two parallel lines connected by two semicircular arcs on the ends.

Look at these trajectory frames and the final screenshot.
1. Does the final image show an oblong/stadium profile clearly drawn on the canvas?
2. Are there dimension constraints visible matching ~40mm length and ~12mm width (or ~6mm radius/28mm center-to-center)?
3. Does the trajectory show the user actually constructing this geometry?

Provide your response in JSON:
{
    "shows_oblong_profile": true/false,
    "shows_dimensions": true/false,
    "workflow_verified": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_slot_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/slot_profile.slvs')
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Read the export JSON result
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += 15
        feedback_parts.append("✅ Output file exists and was created during task")
    elif output_exists:
        feedback_parts.append("❌ Output file exists but timestamp indicates it wasn't modified during task")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("❌ Target output file slot_profile.slvs not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # 2. Parse the SLVS File
    # ---------------------------------------------------------
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    content = ""
    try:
        copy_from_env(expected_path, temp_slvs.name)
        with open(temp_slvs.name, 'r') as f:
            content = f.read()
    except Exception as e:
        logger.warning(f"Could not read slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    if content:
        # Count structural elements
        line_count = content.count('Entity.type=11000')
        arc_count = content.count('Entity.type=14000')
        tangent_count = content.count('Constraint.type=55')
        
        # Line checks (expecting at least 2)
        if line_count >= 2:
            score += 10
            feedback_parts.append(f"✅ Found {line_count} line segments")
        else:
            feedback_parts.append(f"❌ Missing line segments (found {line_count}, expected >= 2)")
            
        # Arc checks (expecting at least 2)
        if arc_count >= 2:
            score += 15
            feedback_parts.append(f"✅ Found {arc_count} arc segments")
        else:
            feedback_parts.append(f"❌ Missing arc segments (found {arc_count}, expected >= 2)")
            
        # Tangent constraint checks
        if tangent_count >= 4:
            score += 20
            feedback_parts.append("✅ Found all 4 tangent constraints")
        elif tangent_count >= 2:
            score += 15
            feedback_parts.append(f"⚠️ Found partial tangent constraints ({tangent_count}/4)")
        else:
            feedback_parts.append(f"❌ Missing tangent constraints (found {tangent_count})")
            
        # Dimension checks (regex search for values assigned to parameters)
        # Look for values like Param.val=40.000 or Constraint.valA=12.000
        dimensions = [float(x) for x in re.findall(r'val[A-Za-z]*=([0-9]+\.[0-9]+)', content)]
        
        has_len = any(abs(d - 40.0) < 2.0 or abs(d - 28.0) < 2.0 for d in dimensions)
        has_width = any(abs(d - 12.0) < 1.0 or abs(d - 6.0) < 0.5 for d in dimensions)
        
        if has_len and has_width:
            score += 15
            feedback_parts.append("✅ Correct dimensions applied")
        elif has_len or has_width:
            score += 5
            feedback_parts.append("⚠️ Partial dimensions applied")
        else:
            feedback_parts.append("❌ Correct dimensions not found in geometry constraints")

    # ---------------------------------------------------------
    # 3. VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        try:
            vlm_res = query_vlm(
                prompt=VLM_PROMPT,
                images=frames + [final] if final else frames
            )
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('shows_oblong_profile'):
                    vlm_score += 15
                    feedback_parts.append("✅ VLM verified shape visual")
                if parsed.get('workflow_verified'):
                    vlm_score += 10
                    feedback_parts.append("✅ VLM verified workflow trajectory")
                    
                score += vlm_score
            else:
                feedback_parts.append(f"⚠️ VLM Error: {vlm_res.get('error', 'unknown')}")
        except Exception as e:
            feedback_parts.append(f"⚠️ VLM validation failed: {e}")
            
    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # To pass, agent must score at least 60 AND have created the file containing lines and arcs
    key_criteria_met = output_exists and file_created_during_task and (line_count >= 2) and (arc_count >= 2)
    
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }