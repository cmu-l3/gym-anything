#!/usr/bin/env python3
"""
Verifier for parametric_scissor_lift_kinematics task.

Programmatic Verification (via .slvs file parsing):
1. File exists and was modified during the task.
2. File contains input dimensions: ~100.0 and (~260.0 OR ~130.0).
3. Anti-gaming check: File MUST NOT contain an explicit 240.0 dimension.
4. Solver output check: File MUST contain solved points with Y coordinates ~240.0.

VLM Verification:
1. Reviews trajectory and final screenshot to ensure a crossed-arm linkage was constructed.
"""

import os
import re
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying if a computer agent successfully modeled a 2D scissor lift linkage in SolveSpace.

TASK CONTEXT:
The agent had to draw a crossed-arm scissor mechanism. The arms are constrained to a length of 260mm, and the base width to 100mm. The vertical height should have been derived naturally by the geometry to reach 240mm.

Please look at the trajectory frames and final screenshot, then answer:
1. Does the sketch clearly show a crossed-arm mechanism (an "X" shape)?
2. Does the sketch appear fully constrained (usually indicated by green lines, or "OK" / "0 DOF" in the Property Browser)?
3. Did the agent successfully avoid just drawing a plain 100x240 rectangle?

Respond strictly in JSON format:
{
    "shows_crossed_arms": true/false,
    "appears_fully_constrained": true/false,
    "is_not_just_a_rectangle": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_scissor_lift(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}
        
    metadata = task_info.get('metadata', {})
    expected_base = metadata.get('expected_base_width', 100.0)
    expected_arm_full = metadata.get('expected_arm_length_full', 260.0)
    expected_arm_half = metadata.get('expected_arm_length_half', 130.0)
    expected_height = metadata.get('expected_solved_height', 240.0)
    tolerance = metadata.get('tolerance_mm', 0.5)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)
            
    # Check file basics
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified_during_task', False)
    file_size = result.get('file_size_bytes', 0)
    
    if file_exists and file_modified and file_size > 100:
        score += 10
        feedback_parts.append("✅ File exists and was modified")
    else:
        feedback_parts.append("❌ File not found, empty, or not modified")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    # 2. Parse the SLVS file
    slvs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/scissor_lift_result.slvs", slvs_file.name)
        with open(slvs_file.name, 'r') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read SLVS: {e}"}
    finally:
        if os.path.exists(slvs_file.name):
            os.unlink(slvs_file.name)
            
    # SolveSpace Param extraction (inputs)
    param_matches = re.findall(r'Param\.val=([0-9\.\-]+)', slvs_content)
    params = [float(p) for p in param_matches]
    
    # SolveSpace ActPoint extraction (solved geometric outputs)
    act_y_matches = re.findall(r'Entity\.actPoint\.y=([0-9\.\-]+)', slvs_content)
    act_y_vals = [float(y) for y in act_y_matches]
    
    # 3. Evaluate Constraints
    has_base = any(abs(p - expected_base) <= tolerance for p in params)
    has_arm_full = any(abs(p - expected_arm_full) <= tolerance for p in params)
    has_arm_half = any(abs(p - expected_arm_half) <= tolerance for p in params)
    
    if has_base and (has_arm_full or has_arm_half):
        score += 30
        feedback_parts.append(f"✅ Correct driving dimensions found ({expected_base} and {expected_arm_full}/{expected_arm_half})")
    else:
        feedback_parts.append("❌ Missing required driving dimensions (100 base or 260/130 arm)")

    # 4. Anti-Gaming Check
    # Ensure they didn't explicitly constrain the height to 240
    gaming_attempt = any(abs(p - expected_height) <= tolerance for p in params)
    if not gaming_attempt:
        score += 10
        feedback_parts.append("✅ Anti-gaming passed (no explicit 240 constraint)")
    else:
        feedback_parts.append("❌ FAILED: Explicit 240 constraint found. The solver must calculate this natively!")
        
    # 5. Solver Output Verification
    # Check if the geometric solver successfully put endpoints at Y = 240.0
    solved_correctly = any(abs(y - expected_height) <= tolerance for y in act_y_vals)
    if solved_correctly and not gaming_attempt:
        score += 30
        feedback_parts.append("✅ Geometric solver successfully calculated height to exactly 240.0")
    else:
        feedback_parts.append("❌ Geometric solver did not reach Y = 240.0 (mechanism built incorrectly)")
        
    # 6. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if final_frame:
                images = frames + [final_frame]
                vlm_result = query_vlm(
                    prompt=VLM_PROMPT,
                    images=images
                )
                
                parsed = vlm_result.get("parsed", {})
                if parsed.get("shows_crossed_arms", False) and parsed.get("is_not_just_a_rectangle", False):
                    vlm_score += 15
                    feedback_parts.append("✅ VLM confirmed crossed-arm geometry")
                else:
                    feedback_parts.append("❌ VLM did not see crossed-arm geometry")
                    
                if parsed.get("appears_fully_constrained", False):
                    vlm_score += 5
                    feedback_parts.append("✅ VLM confirmed constraints")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM check skipped: {e}")
    
    score += vlm_score
    
    # Calculate final passing condition
    key_criteria_met = solved_correctly and (not gaming_attempt) and file_exists
    passed = (score >= 70) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }