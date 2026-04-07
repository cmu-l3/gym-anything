#!/usr/bin/env python3
"""
Verifier for T-Beam Cross-Section Profile task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File Verification (Host-side parsing of the .slvs file)
   - Checks file exists and was created during the task (anti-gaming).
   - Counts line segments (looks for ≥ 8).
   - Checks for horizontal/vertical constraints.
   - Extracts dimension constraints and verifies values against targets (60, 10, 40, 8).
2. Visual Trajectory Verification (VLM)
   - Checks that the agent actually sketched a T-shape in the application.

Pass threshold: 60/100 points AND key criteria met (file exists & is valid).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully created a 2D CAD sketch of a T-beam profile.

Review the provided screenshots from the agent's trajectory and the final state. 
Determine the following:
1. Is the agent actively working in SolveSpace?
2. Did the agent draw a clear "T" shaped cross-section outline?
3. Are there dimension constraints visible that indicate the agent was setting exact sizes?

Provide your assessment in the following JSON format:
{
    "in_solvespace": true/false,
    "drew_t_shape": true/false,
    "dimensions_visible": true/false,
    "reasoning": "Brief explanation of what you see in the frames."
}"""

def verify_t_beam_cross_section(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/t_beam_profile.slvs')
    tolerance = metadata.get('tolerance', 1.5)
    
    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Fetch JSON result exported by the environment
    # -------------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result_data.get('file_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target .slvs file was not found. The agent did not save the file correctly."
        }
    
    if file_created:
        score += 15
        feedback_parts.append("File created during session (+15)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this session.")

    # -------------------------------------------------------------------------
    # 2. Fetch and Parse the .slvs file programmatically
    # -------------------------------------------------------------------------
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env(expected_path, temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy or read .slvs file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # File validity check
    is_valid_slvs = any("SolveSpaceREVa" in line for line in slvs_lines[:5])
    if not is_valid_slvs:
        return {"passed": False, "score": score, "feedback": "File exists but is not a valid SolveSpace file."}
        
    score += 10
    feedback_parts.append("Valid format (+10)")

    # Parse entities and constraints
    entities = []
    constraints = []
    current_item = {}
    
    for line in slvs_lines:
        line = line.strip()
        if line.startswith("Entity."):
            k, v = line.split("=", 1)
            current_item[k.replace("Entity.", "")] = v
        elif line == "AddEntity":
            entities.append(current_item)
            current_item = {}
        elif line.startswith("Constraint."):
            k, v = line.split("=", 1)
            current_item[k.replace("Constraint.", "")] = v
        elif line == "AddConstraint":
            constraints.append(current_item)
            current_item = {}

    # Check for line segments (type 11000)
    line_count = sum(1 for e in entities if e.get("type") == "11000")
    if line_count >= 8:
        score += 15
        feedback_parts.append(f"Found {line_count} line segments (≥8 expected) (+15)")
    elif line_count > 0:
        score += 5
        feedback_parts.append(f"Found {line_count} line segments (incomplete shape)")
    else:
        feedback_parts.append("No line segments found in file")

    # Check for Geometric Constraints (20 = Horizontal, 21 = Vertical)
    has_h = any(c.get("type") == "20" for c in constraints)
    has_v = any(c.get("type") == "21" for c in constraints)
    if has_h and has_v:
        score += 10
        feedback_parts.append("H/V constraints present (+10)")
    elif has_h or has_v:
        score += 5
        feedback_parts.append("Partial H/V constraints (+5)")
    else:
        feedback_parts.append("No H/V constraints found")

    # Check Dimension Constraints (extract all valA values)
    dim_vals = []
    for c in constraints:
        if "valA" in c:
            try:
                dim_vals.append(float(c["valA"]))
            except:
                pass
                
    has_60 = any(abs(v - metadata['dim_flange_width']) <= tolerance for v in dim_vals)
    has_10 = any(abs(v - metadata['dim_flange_thickness']) <= tolerance for v in dim_vals)
    has_40 = any(abs(v - metadata['dim_web_height']) <= tolerance for v in dim_vals)
    has_50 = any(abs(v - metadata['dim_total_height']) <= tolerance for v in dim_vals) # Total height alternative
    has_8  = any(abs(v - metadata['dim_web_thickness']) <= tolerance for v in dim_vals)

    dims_found = 0
    if has_60: dims_found += 1
    if has_10: dims_found += 1
    if has_40 or has_50: dims_found += 1
    if has_8: dims_found += 1
    
    score += (dims_found * 5)
    feedback_parts.append(f"Found {dims_found}/4 required dimensions (+{dims_found*5})")

    # -------------------------------------------------------------------------
    # 3. Visual Trajectory Verification via VLM
    # -------------------------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            try:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_resp.get("success") and "parsed" in vlm_resp:
                    parsed = vlm_resp["parsed"]
                    if parsed.get("in_solvespace"):
                        score += 5
                    if parsed.get("drew_t_shape"):
                        score += 15
                        feedback_parts.append("VLM confirmed T-shape sketch (+15)")
                    if parsed.get("dimensions_visible"):
                        score += 10
                        feedback_parts.append("VLM confirmed dimensions visible (+10)")
                    
                    feedback_parts.append(f"VLM Note: {parsed.get('reasoning', '')}")
            except Exception as e:
                logger.error(f"VLM verification error: {e}")
                feedback_parts.append("VLM error, relying on programmatic metrics.")

    # -------------------------------------------------------------------------
    # Final Result Calculation
    # -------------------------------------------------------------------------
    # A perfect programmatic file (15 + 10 + 15 + 10 + 20) = 70 points minimum.
    # We require the file to be created, and at least some line geometry inside.
    key_criteria_met = file_exists and file_created and line_count >= 4
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }