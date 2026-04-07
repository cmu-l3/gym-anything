#!/usr/bin/env python3
"""
Verifier for Cylindrical Spacer STL Export task.

Validates via multi-signal verification:
1. File existence and anti-gaming timestamp checks
2. Programmatic validation of .slvs parameters (24, 8, 12)
3. Programmatic validation of .stl file (binary/ascii headers + facet count)
4. Visual validation of trajectory steps and final tube shape via VLM
"""

import os
import json
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully created a 3D CAD model of a cylindrical spacer in SolveSpace.
The user's goal was to:
1. Draw two concentric circles.
2. Extrude them into a 3D tube (annular cylinder) with a hole in the middle.
3. Export the model.

Please review the provided trajectory screenshots (which show the progression of the task and the final state) and determine:
1. Did the agent draw two concentric circles?
2. Did the agent use the Extrude operation to turn the 2D sketch into a 3D solid?
3. Is the final 3D shape an annular tube / spacer (a cylinder with a clear hole straight through its center)?

Respond strictly in JSON format:
{
    "drew_concentric_circles": true/false,
    "extruded_to_3d": true/false,
    "is_annular_tube": true/false,
    "reasoning": "brief explanation"
}"""

def verify_cylindrical_spacer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    slvs_path = metadata.get('expected_slvs', '/home/ga/Documents/SolveSpace/spacer.slvs')
    stl_path = metadata.get('expected_stl', '/home/ga/Documents/SolveSpace/spacer.stl')

    score = 0
    feedback_parts = []
    
    # 1. READ TASK RESULT JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. FILE EXISTENCE & TIMESTAMPS
    slvs_exists = result.get('slvs_exists', False)
    slvs_created = result.get('slvs_created_during_task', False)
    stl_exists = result.get('stl_exists', False)
    stl_created = result.get('stl_created_during_task', False)

    if slvs_exists and slvs_created:
        score += 10
        feedback_parts.append("SLVS created")
    elif slvs_exists:
        feedback_parts.append("SLVS exists but predates task (Warning)")
        
    if stl_exists and stl_created:
        score += 10
        feedback_parts.append("STL created")
    elif stl_exists:
        feedback_parts.append("STL exists but predates task (Warning)")

    # 3. PARSE SLVS FILE
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_valid = False
    has_od = False
    has_id = False
    has_h = False
    has_extrude = False
    
    try:
        if slvs_exists:
            copy_from_env(slvs_path, temp_slvs.name)
            if os.path.getsize(temp_slvs.name) > 0:
                with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                # Check for Extrude Group (Type=5100 in SolveSpace internals)
                has_extrude = "Group.type=5100" in content
                
                # Extract all constraint parameter values
                params = []
                for line in content.split('\n'):
                    if line.startswith("Param.val="):
                        try:
                            params.append(float(line.split('=')[1]))
                        except ValueError:
                            pass
                
                def has_val(target, tol=0.01):
                    return any(abs(p - target) < tol for p in params)
                
                # Either diameter (24) or radius (12)
                has_od = has_val(24.0) or has_val(12.0)
                # Either diameter (8) or radius (4)
                has_id = has_val(8.0) or has_val(4.0)
                # Extrusion height
                has_h = has_val(12.0)
                
                slvs_valid = True
    except Exception as e:
        logger.warning(f"Error parsing SLVS: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    if has_extrude:
        score += 10
        feedback_parts.append("Extrude found")
    if has_od:
        score += 10
        feedback_parts.append("OD correct")
    if has_id:
        score += 10
        feedback_parts.append("ID correct")
    if has_h:
        score += 10
        feedback_parts.append("Height correct")

    # 4. PARSE STL FILE
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    stl_valid = False
    try:
        if stl_exists:
            copy_from_env(stl_path, temp_stl.name)
            if os.path.getsize(temp_stl.name) > 100:
                with open(temp_stl.name, 'rb') as f:
                    header = f.read(80)
                    if header.startswith(b'solid'):
                        f.seek(0)
                        text = f.read().decode('utf-8', errors='ignore')
                        tri_count = text.count('facet normal')
                    else:
                        count_bytes = f.read(4)
                        if len(count_bytes) == 4:
                            tri_count = struct.unpack('<I', count_bytes)[0]
                        else:
                            tri_count = 0
                
                # A cylinder needs multiple triangles to approximate curves (usually >30)
                if tri_count > 12:
                    stl_valid = True
                    score += 10
                    feedback_parts.append(f"STL valid ({tri_count} faces)")
    except Exception as e:
        logger.warning(f"Error parsing STL: {e}")
    finally:
        if os.path.exists(temp_stl.name):
            os.unlink(temp_stl.name)

    # 5. VLM VERIFICATION (Trajectory + Output)
    vlm_passed = False
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        
        images = frames
        if final_scr:
            images.append(final_scr)
            
        if images:
            vlm_response = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("drew_concentric_circles"):
                    score += 10
                if parsed.get("extruded_to_3d"):
                    score += 10
                if parsed.get("is_annular_tube"):
                    score += 10
                    vlm_passed = True
                
                reasoning = parsed.get("reasoning", "")
                feedback_parts.append(f"VLM: {reasoning}")

    # Determine pass/fail
    key_criteria_met = slvs_exists and stl_exists and slvs_valid and stl_valid and vlm_passed
    passed = (score >= 60) and key_criteria_met
    
    if not slvs_exists or not stl_exists:
        feedback_parts.append("FAILED: Missing required output files")
        passed = False

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }