#!/usr/bin/env python3
import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_18650_battery_holder(traj, env_info, task_info):
    """
    Verifies that the agent correctly modeled the 18650 battery holder.
    Implements file checks, native SLVS parsing (for precise CAD workflow steps), and VLM verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dimensions = set(metadata.get('expected_dimensions', [44.0, 71.0, 21.0, 40.0, 67.0, 19.0, 2.0, 10.0]))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)
    
    # ================================================================
    # 1. SLVS File Check & File Content Parsing
    # ================================================================
    slvs_exists = result.get('slvs_exists', False)
    slvs_mtime = result.get('slvs_mtime', 0)
    slvs_created_during_task = slvs_mtime >= task_start
    
    if slvs_exists and slvs_created_during_task:
        score += 15
        feedback_parts.append("SLVS file created")
        
        # Download and natively parse SLVS
        temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
        try:
            copy_from_env("/home/ga/Documents/SolveSpace/18650_holder.slvs", temp_slvs.name)
            with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
                slvs_content = f.read()
                
            # Type 5100 represents an EXTRUDE group
            extrusion_count = slvs_content.count('Group.type=5100')
            # meshCombine=1 represents a DIFFERENCE operation
            difference_count = slvs_content.count('Group.meshCombine=1')
            
            # Check for multi-group sequencing (Base, Pocket, Rib)
            if extrusion_count >= 3:
                score += 15
                feedback_parts.append(f"Found {extrusion_count} extrusions")
            elif extrusion_count > 0:
                score += 5
                feedback_parts.append(f"Found only {extrusion_count} extrusions (expected 3)")
                
            # Check for Boolean Difference Combine mode
            if difference_count >= 1:
                score += 15
                feedback_parts.append("Difference combining mode used")
            else:
                feedback_parts.append("Difference combining mode not found")
                
            # Extract dimension constraints/parameters
            param_vals = []
            for line in slvs_content.split('\n'):
                if 'Param.val=' in line:
                    val_str = line.split('=')[1].strip()
                    try:
                        param_vals.append(float(val_str))
                    except ValueError:
                        pass
                        
            # Normalize to absolutes/one decimal (prevent sign negations from failing)
            params = set(round(abs(v), 1) for v in param_vals)
            found_params = expected_dimensions.intersection(params)
            
            if len(found_params) >= 6:
                score += 15
                feedback_parts.append(f"Found {len(found_params)}/8 expected dimensions")
            elif len(found_params) >= 3:
                score += 5
                feedback_parts.append(f"Found {len(found_params)}/8 expected dimensions")
            else:
                feedback_parts.append(f"Found {len(found_params)}/8 expected dimensions")
                
        except Exception as e:
            feedback_parts.append(f"Failed to parse SLVS: {e}")
        finally:
            if os.path.exists(temp_slvs.name):
                os.unlink(temp_slvs.name)
    else:
        feedback_parts.append("SLVS file missing or not created during task")
        
    # ================================================================
    # 2. STL Export Check
    # ================================================================
    stl_exists = result.get('stl_exists', False)
    stl_mtime = result.get('stl_mtime', 0)
    stl_size = result.get('stl_size', 0)
    
    if stl_exists and stl_mtime >= task_start:
        if stl_size > 1000:
            score += 20
            feedback_parts.append("STL file exported successfully")
        else:
            score += 10
            feedback_parts.append("STL file exported but very small")
    else:
        feedback_parts.append("STL file missing or not exported during task")

    # ================================================================
    # 3. VLM Trajectory Verification
    # ================================================================
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        prompt = """Look at these screenshots of a SolveSpace CAD session.
Did the user successfully model a dual 18650 battery holder according to these steps?
1. Create a base block
2. Cut a pocket into the block (hollowing it out)
3. Add a thin separator rib in the middle of the pocket

By the end, you should see a 3D model that looks like a rectangular cup divided into two parallel bays.

Reply in JSON format:
{
    "model_looks_correct": true/false,
    "pocket_visible": true/false,
    "rib_visible": true/false,
    "reasoning": "brief explanation"
}"""
        vlm_result = query_vlm(images=frames, prompt=prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("model_looks_correct") and parsed.get("pocket_visible") and parsed.get("rib_visible"):
                score += 20
                feedback_parts.append("VLM confirmed 3D model features")
            elif parsed.get("pocket_visible"):
                score += 10
                feedback_parts.append("VLM saw pocket but missing other features")
            else:
                feedback_parts.append("VLM did not confirm 3D features")
        else:
            feedback_parts.append("VLM query failed")
    else:
        feedback_parts.append("VLM verification not available")

    # Key criteria: Passed minimum score AND required output files generated
    passed = score >= 60 and slvs_exists and stl_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }