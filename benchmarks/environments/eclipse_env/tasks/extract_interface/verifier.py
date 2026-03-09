#!/usr/bin/env python3
"""
Verifier for Extract Interface task.
"""

import json
import logging
import re
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_interface(traj, env_info, task_info):
    """
    Verify the Extract Interface task.
    
    Criteria:
    1. IUserService.java exists and is a valid interface (20 pts)
    2. Interface contains all 5 required methods (20 pts)
    3. UserService implements IUserService (20 pts)
    4. UserController uses IUserService (20 pts)
    5. Project compiles successfully (10 pts)
    6. VLM Trajectory Verification (10 pts)
    
    Pass threshold: 70 points AND Compilation Success.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Interface Exists & Valid (20 pts) ---
    interface_content = result.get("interface_content", "")
    if result.get("interface_exists") and "interface IUserService" in interface_content:
        score += 20
        feedback.append("✓ IUserService created correctly")
    else:
        feedback.append("✗ IUserService.java missing or invalid")

    # --- Criterion 2: Methods in Interface (20 pts) ---
    required_methods = ["findById", "findAll", "save", "delete", "exists"]
    methods_found = 0
    for method in required_methods:
        if method in interface_content:
            methods_found += 1
    
    if methods_found == 5:
        score += 20
        feedback.append("✓ All 5 methods present in interface")
    elif methods_found > 0:
        partial = int((methods_found / 5) * 20)
        score += partial
        feedback.append(f"⚠ Only {methods_found}/5 methods in interface")
    else:
        feedback.append("✗ No methods extracted to interface")

    # --- Criterion 3: UserService Implements (20 pts) ---
    user_service = result.get("user_service_content", "")
    if "implements IUserService" in user_service or "implements com.serviceapp.service.IUserService" in user_service:
        score += 20
        feedback.append("✓ UserService implements interface")
    else:
        feedback.append("✗ UserService does not implement IUserService")

    # --- Criterion 4: UserController Updated (20 pts) ---
    # Should use IUserService field, not UserService
    user_controller = result.get("user_controller_content", "")
    if "private final IUserService userService" in user_controller and "UserController(IUserService userService)" in user_controller:
        score += 20
        feedback.append("✓ UserController updated to use interface")
    elif "IUserService" in user_controller:
        score += 10
        feedback.append("⚠ UserController partially updated (check field/constructor types)")
    else:
        feedback.append("✗ UserController still uses concrete class")

    # --- Criterion 5: Compilation (10 pts) ---
    if result.get("compilation_success"):
        score += 10
        feedback.append("✓ Project compiles successfully")
    else:
        feedback.append("✗ Compilation failed")
        if result.get("compilation_log"):
            feedback.append(f"  Log: {result['compilation_log'][:200]}...")

    # --- Criterion 6: VLM Verification (10 pts) ---
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an Eclipse IDE task.
        Goal: Extract an interface from a Java class.
        
        Look for:
        1. The "Extract Interface" dialog box.
        2. Selection of methods in a dialog.
        3. Code editor showing Java code.
        4. "Refactoring" menus or context menus.
        
        Did the agent appear to perform a refactoring operation?
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_ss], prompt=prompt)
            if vlm_response and vlm_response.get('success'):
                 # Simple sentiment check or assume success if API call worked and looks positive
                 # For robust implementation, we'd parse JSON from VLM.
                 # Here assuming VLM returns text description implying success.
                 analysis = vlm_response.get('response', '').lower()
                 if "dialog" in analysis or "extract" in analysis or "refactor" in analysis:
                     vlm_passed = True
        except Exception:
            pass

    if vlm_passed:
        score += 10
        feedback.append("✓ VLM verified refactoring workflow")
    elif result.get("files_modified"):
        # Fallback: if files modified but VLM failed/unsure, give 5 pts
        score += 5
        feedback.append("⚠ Files modified (VLM inconclusive)")

    # --- Final Result ---
    # Must compile and meet score threshold
    passed = (score >= 70) and result.get("compilation_success")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }