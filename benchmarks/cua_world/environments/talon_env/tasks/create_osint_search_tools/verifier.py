#!/usr/bin/env python3
"""
Verifier for Create Voice-Controlled OSINT Search Tool task.
Uses purely programmatic AST/String analysis combined with trajectory VLM to prevent gaming.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_osint_tools(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Fetch the JSON artifact from the Windows container
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result from container: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files_exist = result.get("files_exist", False)
    py_content = result.get("python_content", "") or ""
    talon_content = result.get("talon_content", "") or ""
    list_content = result.get("list_content", "") or ""
    
    # ---------------------------------------------------------
    # Criterion 1: File Structure Check (10 pts)
    # ---------------------------------------------------------
    if files_exist and py_content and talon_content and list_content:
        score += 10
        feedback.append("File structure correct")
    else:
        feedback.append("Missing required files in target directory")
        
    # ---------------------------------------------------------
    # Criterion 2: Talon List Configuration (15 pts)
    # ---------------------------------------------------------
    list_lower = list_content.lower().replace(" ", "")
    if "list:user.osint_category" in list_lower:
        score += 5
        mappings = ["map:map", "scholar:scholar", "flight:flight", "network:network"]
        matches = sum(1 for m in mappings if m in list_lower)
        if matches == 4:
            score += 10
            feedback.append("Talon list configured correctly")
        else:
            feedback.append(f"Talon list mappings incomplete ({matches}/4)")
    else:
        feedback.append("Talon list header missing")
        
    # ---------------------------------------------------------
    # Criterion 3: Talon Command Syntax (15 pts)
    # ---------------------------------------------------------
    talon_lower = talon_content.lower()
    if "investigate" in talon_lower and "user.osint_category" in talon_lower:
        score += 7
        if "user.osint_search(" in talon_lower:
            score += 8
            feedback.append("Talon command syntax correct")
        else:
            feedback.append("Talon command missing action call")
    else:
        feedback.append("Talon command trigger incorrect")
        
    # ---------------------------------------------------------
    # Criterion 4: Python Logic - Encoding & Cleaning (40 pts)
    # ---------------------------------------------------------
    py_lower = py_content.lower()
    
    # Check if correct endpoints are included
    has_map = "openstreetmap.org" in py_lower
    has_scholar = "scholar.google.com" in py_lower
    has_flight = "flightaware.com" in py_lower
    has_bgp = "bgpview.io" in py_lower
    
    if has_map and has_scholar:
        # Looking for url encoding behavior
        if "urllib.parse" in py_lower or "quote" in py_lower or "%20" in py_lower or "replace" in py_lower:
            score += 20
            feedback.append("URL encoding logic implemented")
        else:
            score += 10
            feedback.append("Endpoints present, URL encoding missing")
            
    if has_flight and has_bgp:
        # Looking for string cleaning behavior
        if "replace" in py_lower and "upper" in py_lower:
            score += 20
            feedback.append("String cleaning logic implemented")
        else:
            score += 10
            feedback.append("Endpoints present, string cleaning missing")
            
    # ---------------------------------------------------------
    # Criterion 5: Python Logic - Audit Logging (20 pts)
    # ---------------------------------------------------------
    # Looking for a file append open method
    if "osint_audit_log.txt" in py_lower and ("open(" in py_lower or "path(" in py_lower) and "a" in py_content:
        score += 10
        if "datetime" in py_lower or "time" in py_lower:
            score += 10
            feedback.append("Audit logging with timestamp implemented")
        else:
            feedback.append("Audit logging missing timestamp logic")

    # ---------------------------------------------------------
    # Anti-Gaming: VLM Trajectory Verification
    # ---------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    try:
        from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
        # Combine mid-trajectory frames + final image to prove work wasn't scripted behind scenes
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if query_vlm and frames:
            prompt = """Look at these screenshots from a computer agent session.
            Did the agent actively use a text editor (like Notepad or VS Code) to write Python and Talon configuration code?
            Respond in JSON format with a single boolean field:
            {"editor_used": true/false}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("editor_used", False):
                    feedback.append("VLM verified editor activity")
                else:
                    feedback.append("VLM did NOT detect editor activity (Possible gaming penalty applied)")
                    score = max(0, score - 40)
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")

    # Calculate final status
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }