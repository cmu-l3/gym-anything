#!/usr/bin/env python3
"""
Verifier for fillet_arc_profile CAD task.

Evaluates:
1. File existence and timestamps (anti-gaming)
2. Programmatic analysis of SolveSpace .slvs file for required geometries
3. Programmatic analysis of constraints and their values
4. Visual verification via VLM on trajectory frames
"""

import os
import json
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating if an AI agent successfully completed a CAD task in SolveSpace.

TASK: Draw a corner profile with two line segments and connect them with a tangent arc (a fillet), then constrain the arc radius to 10mm (diameter 20mm).

Look at the provided progression of screenshots. Please determine:
1. Did the agent draw at least two distinct lines?
2. Did the agent draw an arc connecting the two lines?
3. Are there visual indicators of constraints (like tangency icons or a dimension label showing "10.00" or "20.00")?
4. Does the final image clearly show a filleted corner profile?

Respond ONLY with a valid JSON block:
{
    "lines_drawn": true/false,
    "arc_drawn": true/false,
    "constraints_visible": true/false,
    "fillet_profile_achieved": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_fillet_arc_profile(traj, env_info, task_info):
    """Verify the fillet_arc_profile task using both programmatic and VLM signals."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy_from_env not available."}
        
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/fillet_profile.slvs')
    expected_diameter = metadata.get('expected_diameter', 20.0)
    expected_radius = metadata.get('expected_radius', 10.0)
    tolerance = metadata.get('tolerance', 0.5)
    
    score = 0
    feedback_parts = []
    
    # 1. Read exported metadata
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": f"Output file {expected_path} was not created."}
        
    if file_modified:
        score += 10
        feedback_parts.append("File created/modified during task (+10)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not modified during task.")
        
    # 2. Parse the SolveSpace .slvs file directly
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_path, temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read .slvs file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # Check valid header
    if "SolveSpaceREVa" in slvs_content or "±Pro" in slvs_content:
        score += 10
        feedback_parts.append("Valid SLVS format (+10)")
        
    # Count requests and constraints
    line_reqs = slvs_content.count("Request.type=200")
    arc_reqs = slvs_content.count("Request.type=400")
    tangent_consts = slvs_content.count("Constraint.type=120")
    diam_consts = slvs_content.count("Constraint.type=90")
    
    if line_reqs >= 2:
        score += 10
        feedback_parts.append(f"Lines found: {line_reqs} (+10)")
    else:
        feedback_parts.append(f"Missing lines (found {line_reqs}, need >= 2)")
        
    if arc_reqs >= 1:
        score += 15
        feedback_parts.append(f"Arcs found: {arc_reqs} (+15)")
    else:
        feedback_parts.append("No arc entities found")
        
    if tangent_consts >= 2:
        score += 15
        feedback_parts.append(f"Tangent constraints found: {tangent_consts} (+15)")
    elif tangent_consts == 1:
        score += 7
        feedback_parts.append("Partial: Only 1 tangent constraint found (+7)")
    else:
        feedback_parts.append("No tangent constraints found")
        
    if diam_consts >= 1:
        score += 10
        feedback_parts.append("Dimension constraint found (+10)")
    else:
        feedback_parts.append("No diameter/radius constraint found")
        
    # Extract radius/diameter values
    radius_correct = False
    blocks = slvs_content.split('AddConstraint')
    for block in blocks:
        if 'Constraint.type=90' in block:
            for line in block.split('\n'):
                if 'Constraint.valA=' in line:
                    try:
                        val = float(line.split('=')[1].strip())
                        # Check if it matches expected diameter OR expected radius
                        if abs(val - expected_diameter) <= tolerance or abs(val - expected_radius) <= tolerance:
                            radius_correct = True
                    except:
                        pass
                        
    if radius_correct:
        score += 10
        feedback_parts.append("Dimension value correct (10mm R / 20mm D) (+10)")
    elif diam_consts >= 1:
        feedback_parts.append("Dimension value incorrect")
        
    # 3. VLM Verification
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        try:
            vlm_res = query_vlm(images=frames, prompt=VERIFICATION_PROMPT)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('fillet_profile_achieved', False) and parsed.get('arc_drawn', False):
                score += 20
                vlm_passed = True
                feedback_parts.append("VLM verified visual fillet profile (+20)")
            else:
                feedback_parts.append(f"VLM visual check failed: {parsed.get('reasoning', 'No reason provided')}")
        except Exception as e:
            feedback_parts.append(f"VLM verification error: {e}")
            
    # Key criteria requirement
    key_criteria_met = file_modified and arc_reqs >= 1 and line_reqs >= 2
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": bool(passed),
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }