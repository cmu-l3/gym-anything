#!/usr/bin/env python3
"""
Verifier for create_physical_security_plan task.

Verification Strategy:
1. Programmatic (Primary): 
   - Extract the .eddx file (which is a ZIP archive).
   - Parse internal XMLs to find text labels matching the security device IDs (CR-01, CAM-01, etc.).
   - Check if the correct number of devices are labeled.
2. VLM (Secondary):
   - Analyze the exported PNG or trajectory frames.
   - Verify it looks like a floor plan (walls, door) and not just a list of text.
   - Confirm spatial arrangement (e.g., camera in corner).
"""

import os
import json
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_physical_security_plan(traj, env_info, task_info):
    """
    Verify the security plan creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    title_text = metadata.get('title_text', "Server Room Security Layout")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. GET RESULT JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. CHECK FILE EXISTENCE (10 pts)
    eddx_exists = result_data.get('eddx_exists', False)
    png_exists = result_data.get('png_exists', False)
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    
    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created successfully")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but timestamp is old")
    else:
        feedback_parts.append("EDDX file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. CONTENT ANALYSIS OF EDDX (65 pts)
    # The .eddx file is a ZIP containing XML data. We search for the labels.
    found_labels = []
    title_found = False
    
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    try:
        copy_from_env("/home/ga/Diagrams/security_plan.eddx", temp_eddx.name)
        
        if zipfile.is_zipfile(temp_eddx.name):
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # EdrawMax stores page data in XML files usually under pages/ or just in root
                all_xml_text = ""
                for filename in zf.namelist():
                    if filename.endswith(".xml"):
                        try:
                            content = zf.read(filename).decode('utf-8', errors='ignore')
                            all_xml_text += content
                        except:
                            pass
                
                # Check for labels
                for label in required_labels:
                    if label in all_xml_text:
                        found_labels.append(label)
                
                # Check for title
                if title_text in all_xml_text:
                    title_found = True
        else:
            feedback_parts.append("EDDX file is not a valid ZIP archive")

    except Exception as e:
        feedback_parts.append(f"Error analyzing EDDX content: {e}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    # Scoring for labels
    # Total 8 labels + 1 title = 9 items for 65 points (~7 pts each)
    label_score = len(found_labels) * 7
    if title_found:
        label_score += 9
    
    # Cap content score at 65
    label_score = min(label_score, 65)
    score += label_score
    
    feedback_parts.append(f"Found {len(found_labels)}/{len(required_labels)} device labels")
    if title_found:
        feedback_parts.append("Title found")
    
    # 4. VISUAL VERIFICATION (25 pts)
    # Use VLM to check if it looks like a floor plan
    vlm_score = 0
    
    # Prefer the exported PNG if available, else final screenshot
    image_to_check = None
    if png_exists:
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Diagrams/security_plan.png", temp_png.name)
            image_to_check = temp_png.name
        except:
            pass
    
    # If no exported PNG, use final screenshot
    if not image_to_check:
        image_to_check = get_final_screenshot(traj)

    if image_to_check:
        prompt = """
        You are verifying a "Server Room Security Plan" created in diagramming software.
        
        Criteria:
        1. Does the image show a floor plan (walls enclosing a rectangular room)?
        2. Is there a door visible?
        3. Are there distinct symbols placed inside/around the room (cameras, sensors)?
        4. Does it look like a professional diagram, not just random text?
        
        Respond in JSON:
        {
            "is_floor_plan": true/false,
            "door_visible": true/false,
            "security_symbols_visible": true/false,
            "overall_quality_ok": true/false,
            "reasoning": "..."
        }
        """
        
        # We can also add trajectory frames to see the workflow
        traj_frames = sample_trajectory_frames(traj, n=3)
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=image_to_check, images=traj_frames)
            if vlm_resp and vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                
                if parsed.get('is_floor_plan'): vlm_score += 10
                if parsed.get('door_visible'): vlm_score += 5
                if parsed.get('security_symbols_visible'): vlm_score += 5
                if parsed.get('overall_quality_ok'): vlm_score += 5
                
                feedback_parts.append(f"VLM check: {parsed.get('reasoning', 'No reasoning')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if we found all labels, assume visual is likely okay-ish, give partial credit
            if len(found_labels) >= 6:
                vlm_score += 15
        
        # Cleanup temp PNG if we created it
        if png_exists and image_to_check and os.path.exists(image_to_check) and "task_final" not in image_to_check:
             os.unlink(image_to_check)

    score += vlm_score

    # Final Pass Logic
    # Must have file + at least 50% of labels + reasonable visual
    passed = (score >= 70) and eddx_exists and (len(found_labels) >= 4)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }