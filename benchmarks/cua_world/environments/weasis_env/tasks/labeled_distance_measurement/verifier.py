#!/usr/bin/env python3
"""
Verifier for Labeled Distance Measurement task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_labeled_distance_measurement(traj, env_info, task_info):
    """
    Verify that a distance measurement line was created, labeled intrinsically 
    via properties, and successfully exported.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_label = metadata.get('expected_label', 'Aortic Root')
    min_size = metadata.get('min_file_size_bytes', 5000)

    score = 0
    feedback_parts = []
    
    # 1. Check Result File from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # File Criteria Scoring (max 30 pts)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)

    if output_exists:
        if created_during_task and file_size >= min_size:
            score += 30
            feedback_parts.append("Export file valid and created during task")
        else:
            score += 10
            feedback_parts.append(f"Export file exists but invalid (size: {file_size}, new: {created_during_task})")
    else:
        feedback_parts.append("Export file NOT found")
        # Fail fast if file doesn't exist
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. VLM Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        vlm_prompt = f"""
        You are verifying a medical imaging agent's performance in Weasis DICOM Viewer.
        Task: Draw a distance measurement line, and explicitly label it '{expected_label}' using the measurement's properties dialog (NOT a disconnected text box).
        
        Images provided: A chronological trajectory of the agent's screen, ending with the final state.
        
        Analyze the workflow and final state to determine:
        1. measurement_line_visible: Is there a distance measurement line (typically with end-caps and a numeric value like mm/px) drawn on the anatomy in the viewer?
        2. label_integrated: Does the text '{expected_label}' appear integrated or attached directly to that measurement line?
        3. properties_dialog_used: Do the trajectory frames show the agent accessing a "Properties" or "Settings" dialog/menu for the measurement to apply this label?
        4. text_tool_avoided: Did the agent correctly avoid using a separate, floating "Text Annotation" tool? (If they just clicked a Text 'T' or 'A' icon to drop floating text near the line, this is false).

        Return JSON format ONLY:
        {{
            "measurement_line_visible": true/false,
            "label_integrated": true/false,
            "properties_dialog_used": true/false,
            "text_tool_avoided": true/false,
            "reasoning": "Brief explanation of what is seen in the trajectory and final result"
        }}
        """
        
        vlm_result = query_vlm(
            images=frames + [final_screenshot], 
            prompt=vlm_prompt
        )
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            # Scoring VLM Results
            line_visible = parsed.get("measurement_line_visible", False)
            label_integrated = parsed.get("label_integrated", False)
            used_properties = parsed.get("properties_dialog_used", False)
            avoided_text = parsed.get("text_tool_avoided", True)
            
            # Content (40 pts)
            if line_visible and label_integrated:
                score += 40
                feedback_parts.append(f"Measurement line with '{expected_label}' label verified")
            elif line_visible:
                score += 20
                feedback_parts.append("Measurement line visible, but label missing/incorrect")
            else:
                feedback_parts.append("No measurement line visible")
                
            # Process/Workflow (30 pts)
            if used_properties and avoided_text:
                score += 30
                feedback_parts.append("Properties dialog correctly used for labeling")
            elif not avoided_text:
                feedback_parts.append("Failed: Used floating text tool instead of intrinsic properties")
            else:
                score += 15
                feedback_parts.append("Labeling workflow unclear, but floating text avoided")
                
        else:
            logger.warning(f"VLM query failed or returned no success: {vlm_result}")
            feedback_parts.append("VLM verification failed to run")
            
    except ImportError:
        logger.warning("VLM utilities not available for trajectory verification.")
        feedback_parts.append("VLM unavailable - cannot verify visual contents")
    except Exception as e:
        logger.warning(f"Error during VLM verification: {e}")
        feedback_parts.append(f"VLM error: {str(e)}")

    # Final pass determination
    # Require output file creation + accurate integrated labeling
    # Strict fail condition if the user relied on the external text tool to bypass the core task
    passed = score >= 70 and ("Failed: Used floating text tool" not in " ".join(feedback_parts))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }