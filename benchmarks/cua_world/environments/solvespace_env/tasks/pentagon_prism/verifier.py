#!/usr/bin/env python3
"""
Verifier for the pentagon_prism task in SolveSpace.

VERIFICATION METRICS:
1. File Existence & Anti-Gaming: Output file must exist and be created during the task.
2. File Content Checks (.slvs parsing):
   - Contains line segments (Entity.type=11000)
   - Contains constraints (Request.type blocks)
   - Contains Extrude group (Group.type=5100, 5101, or 5102)
3. VLM Trajectory Verification:
   - Proves agent drew a 5-sided polygon
   - Proves constraints were applied
   - Proves 3D extrusion was performed
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for Verification
VLM_PROMPT = """You are evaluating a CAD agent's performance in SolveSpace.
The agent was asked to:
1. Draw a 2D regular pentagon (5 sides).
2. Apply constraints (equal length, 25mm distance, 108° angles) to fully constrain it.
3. Extrude the sketch into a 3D solid prism (15mm depth).

Analyze these trajectory frames and the final screenshot.
Return a JSON object with your analysis:
{
    "drew_pentagon": true/false,
    "applied_constraints": true/false,
    "extruded_to_3d": true/false,
    "reasoning": "Brief explanation of what visual evidence supports these flags"
}
Note: Constraints in SolveSpace appear as magenta/green dimensions and equality tick marks. 3D extrusion shows the flat shape extending into a 3D solid block.
"""

def verify_pentagon_prism(traj, env_info, task_info):
    """
    Verify that the pentagonal prism was created and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/pentagon_prism.slvs')
    
    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Fetch JSON Results
    # -------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # 2. Check File Existence & Anti-Gaming (20 points)
    # -------------------------------------------------------------------------
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file was not saved."}
        
    if not file_created_during_task:
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during task."}

    if file_size > 1000:
        score += 20
        feedback_parts.append("Valid file saved during task")
    else:
        feedback_parts.append("File exists but is too small to be a valid model")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # -------------------------------------------------------------------------
    # 3. Parse .slvs File Content (40 points)
    # -------------------------------------------------------------------------
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    slvs_content = ""
    try:
        copy_from_env(expected_output, temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        logger.error(f"Failed to read slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # Check for Line Segments (Entity.type=11000)
    line_count = slvs_content.count("Entity.type=11000")
    if line_count >= 5:
        score += 15
        feedback_parts.append(f"Found {line_count} line segments")
    else:
        feedback_parts.append(f"Found only {line_count} lines (need >=5 for pentagon)")
        
    # Check for Constraints (Request.type blocks)
    request_count = slvs_content.count("Request.type=")
    if request_count >= 5:
        score += 10
        feedback_parts.append(f"Found constraints ({request_count})")
    else:
        feedback_parts.append("Insufficient constraints found")
        
    # Check for Extrusion Group (Group.type=5100 or 5101 or 5102)
    has_extrusion = "Group.type=510" in slvs_content
    if has_extrusion:
        score += 15
        feedback_parts.append("Extrusion group found")
    else:
        feedback_parts.append("No Extrusion group found")

    # -------------------------------------------------------------------------
    # 4. VLM Trajectory Verification (40 points)
    # -------------------------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result.get('success') and 'parsed' in vlm_result:
                    parsed = vlm_result['parsed']
                    
                    if parsed.get('drew_pentagon', False):
                        vlm_score += 15
                        feedback_parts.append("VLM: Pentagon drawn")
                        
                    if parsed.get('applied_constraints', False):
                        vlm_score += 10
                        feedback_parts.append("VLM: Constraints visible")
                        
                    if parsed.get('extruded_to_3d', False):
                        vlm_score += 15
                        feedback_parts.append("VLM: 3D Extrusion visible")
                        
                    logger.info(f"VLM Reasoning: {parsed.get('reasoning', '')}")
                else:
                    logger.error("VLM query failed or returned invalid format")
        except ImportError:
            logger.warning("gym_anything.vlm not available, skipping visual check")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            
    score += vlm_score

    # -------------------------------------------------------------------------
    # Final Evaluation
    # -------------------------------------------------------------------------
    # Pass requires saving the file, drawing >= 5 lines, making an extrusion, 
    # and either good VLM visual proof or strong file evidence.
    key_criteria_met = output_exists and file_created_during_task and (line_count >= 5) and has_extrusion
    
    passed = (score >= 70) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }