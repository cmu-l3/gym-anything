#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_field_labels(traj, env_info, task_info):
    """
    Verify that the 'Host' field was renamed to 'Escort' and the visitor was registered.
    
    Verification Strategy:
    1. Check if evidence file exists and was created during task.
    2. Use VLM to analyze the evidence screenshot (or final screenshot) for:
       - The specific label "Escort" on the UI.
       - The visitor name "Viktor Antonov".
       - The host name "Eli Vance".
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_label = metadata.get('expected_label', 'Escort')
    
    # 1. Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract Evidence Image
    evidence_exists = result.get('evidence_exists', False)
    evidence_created = result.get('evidence_created_during_task', False)
    
    # We prefer the agent's explicit screenshot, but fall back to final state if needed
    image_to_verify = None
    
    # Try to copy the evidence image
    if result.get('evidence_path'):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result['evidence_path'], temp_img.name)
            if os.path.getsize(temp_img.name) > 0:
                image_to_verify = temp_img.name
        except Exception:
            pass # Fallback to trajectory

    # If no explicit evidence, use final screenshot from trajectory
    if not image_to_verify:
        final_screen = get_final_screenshot(traj)
        if final_screen:
            # Save bytes to temp file for consistent handling if needed, 
            # but query_vlm accepts PIL/bytes directly usually.
            # Here we just pass the object to query_vlm.
            image_to_verify = final_screen

    if not image_to_verify:
         return {"passed": False, "score": 0, "feedback": "No visual evidence available (screenshot missing)."}

    # 3. VLM Verification
    prompt = f"""
    Analyze this screenshot of the Jolly Lobby Track visitor management software.
    
    I am looking for three specific things:
    1. A field label on the form that says "{expected_label}" (Case sensitive). It usually replaces "Host" or "Person Visiting".
    2. Visitor Name: "Viktor Antonov" (or similar).
    3. Host/Escort Name: "Eli Vance".

    Return JSON:
    {{
        "label_escort_visible": boolean,
        "visitor_name_visible": boolean,
        "host_name_visible": boolean,
        "is_lobby_track_ui": boolean
    }}
    """

    vlm_response = query_vlm(image=image_to_verify, prompt=prompt)
    
    score = 0
    feedback = []
    
    if vlm_response and vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        
        # Criterion 1: Label Customization (40 pts)
        if parsed.get('label_escort_visible'):
            score += 40
            feedback.append(f"Success: '{expected_label}' label found.")
        else:
            feedback.append(f"Fail: '{expected_label}' label not visible.")

        # Criterion 2: Visitor Registration Data (30 pts)
        if parsed.get('visitor_name_visible'):
            score += 30
            feedback.append("Success: Visitor 'Viktor Antonov' details visible.")
        else:
            feedback.append("Fail: Visitor name not clearly visible.")

        # Criterion 3: Host Association (20 pts)
        if parsed.get('host_name_visible'):
            score += 20
            feedback.append("Success: Host 'Eli Vance' visible.")
        else:
            feedback.append("Fail: Host name not clearly visible.")
            
        # Criterion 4: Evidence File (10 pts)
        if evidence_exists and evidence_created:
            score += 10
            feedback.append("Success: Screenshot evidence saved correctly.")
        elif evidence_exists:
            score += 5
            feedback.append("Partial: Screenshot exists but timestamp is suspicious.")
        else:
            feedback.append("Fail: Screenshot file not found at expected path.")

    else:
        return {"passed": False, "score": 0, "feedback": "VLM analysis failed."}

    passed = score >= 70 and parsed.get('label_escort_visible', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }