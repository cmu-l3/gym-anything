#!/usr/bin/env python3
"""
Verifier for create_clinical_template task.

HYBRID VERIFICATION: Combines programmatic state checks with VLM-based visual verification.

Programmatic checks:
- Searches database for specific multiline medical text segments indicating success.
- Ensures text instances increased (anti-gaming against pre-existing data).

VLM checks:
- Verifies the agent actually interacted with the Web UI to enter the data instead of cheating via raw SQL queries.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_clinical_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/template_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    init_heent = int(result.get('initial_heent_count', 0))
    final_heent = int(result.get('final_heent_count', 0))
    
    init_cv = int(result.get('initial_cv_count', 0))
    final_cv = int(result.get('final_cv_count', 0))
    
    init_title = int(result.get('initial_title_count', 0))
    final_title = int(result.get('final_title_count', 0))
    
    # 1. HEENT phrase count Check (30 points)
    if final_heent > init_heent:
        score += 30
        feedback_parts.append("HEENT phrase found in database")
    else:
        feedback_parts.append("HEENT phrase missing")
        
    # 2. CV phrase count Check (30 points)
    if final_cv > init_cv:
        score += 30
        feedback_parts.append("CV phrase found in database")
    else:
        feedback_parts.append("CV phrase missing")
        
    # 3. Title Check (20 points)
    if final_title > init_title:
        score += 20
        feedback_parts.append("Template title found in database")
    else:
        feedback_parts.append("Template title missing")
        
    # 4. VLM UI interaction Verification (20 points)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Look at these screenshots from a session interacting with FreeMED EMR.
Task: Verify if the user used the FreeMED Web Interface (in the browser) to create a template or canned text.
Check for:
1. Is the user navigating the FreeMED UI (menus, configuration, template forms)?
2. Did the user enter the text "Normal Physical Exam" or the physical exam text into web form fields?
3. Did the user interact with the UI to save it (as opposed to opening a terminal and typing SQL commands)?

Return a JSON object:
{
    "used_web_ui": true/false,
    "entered_text_in_form": true/false,
    "terminal_used_for_sql": true/false
}"""
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                used_web = parsed.get("used_web_ui", False)
                entered_text = parsed.get("entered_text_in_form", False)
                terminal_sql = parsed.get("terminal_used_for_sql", False)
                
                if (used_web or entered_text) and not terminal_sql:
                    score += 20
                    feedback_parts.append("VLM verified UI interaction")
                else:
                    feedback_parts.append("VLM did not verify proper UI interaction")
            else:
                feedback_parts.append("VLM query failed")
        except ImportError:
            feedback_parts.append("gym_anything.vlm not available for VLM check")
        except Exception as e:
            feedback_parts.append(f"VLM verification error: {e}")
    else:
        feedback_parts.append("VLM not available")
        
    # Threshold condition: MUST pass majority of checks and actively input at least one string parameter 
    passed = score >= 80 and (final_heent > init_heent or final_cv > init_cv)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }