#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_onboard_employee_dependents(traj, env_info, task_info):
    """
    Verifies that employee James Holden was created and dependents Naomi and Filip were added correctly.
    """
    # 1. Setup and retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Define expected values
    EXP_FIRST = metadata.get("employee_firstname", "James")
    EXP_LAST = metadata.get("employee_lastname", "Holden")
    
    EXP_DEP1_NAME = metadata.get("dep1_name", "Naomi Nagata")
    EXP_DEP1_REL = metadata.get("dep1_rel", "Spouse")
    EXP_DEP1_DOB = metadata.get("dep1_dob", "1988-04-15")
    
    EXP_DEP2_NAME = metadata.get("dep2_name", "Filip Inaros")
    EXP_DEP2_REL = metadata.get("dep2_rel", "Child")
    EXP_DEP2_DOB = metadata.get("dep2_dob", "2012-10-20")

    # Load JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Check Employee Creation (20 pts)
    if result.get("employee_found", False):
        score += 20
        feedback.append(f"Employee {EXP_FIRST} {EXP_LAST} created.")
    else:
        feedback.append(f"Employee {EXP_FIRST} {EXP_LAST} NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Check Dependents
    dependents = result.get("dependents", [])
    
    # Helper to find dependent
    def find_dep(name):
        for d in dependents:
            # Case-insensitive name match
            if d.get("name", "").lower() == name.lower():
                return d
        return None

    # Verify Dependent 1 (Naomi)
    dep1 = find_dep(EXP_DEP1_NAME)
    if dep1:
        score += 20 # Exists
        feedback.append(f"Dependent {EXP_DEP1_NAME} found.")
        
        # Check details
        rel_type = dep1.get("relationship_type", "")
        # OrangeHRM might store "spouse" or "child" in relationship_type, or use "other"
        # We accept exact match or reasonably close (case insensitive)
        if rel_type.lower() == EXP_DEP1_REL.lower():
            dob_match = (dep1.get("dob") == EXP_DEP1_DOB)
            if dob_match:
                score += 15
                feedback.append(f"{EXP_DEP1_NAME} details correct.")
            else:
                score += 5 # Partial credit if relation correct but DOB wrong
                feedback.append(f"{EXP_DEP1_NAME} DOB incorrect (Expected {EXP_DEP1_DOB}, Got {dep1.get('dob')}).")
        else:
            feedback.append(f"{EXP_DEP1_NAME} relationship incorrect (Expected {EXP_DEP1_REL}, Got {rel_type}).")
    else:
        feedback.append(f"Dependent {EXP_DEP1_NAME} NOT found.")

    # Verify Dependent 2 (Filip)
    dep2 = find_dep(EXP_DEP2_NAME)
    if dep2:
        score += 20 # Exists
        feedback.append(f"Dependent {EXP_DEP2_NAME} found.")
        
        rel_type = dep2.get("relationship_type", "")
        if rel_type.lower() == EXP_DEP2_REL.lower():
            dob_match = (dep2.get("dob") == EXP_DEP2_DOB)
            if dob_match:
                score += 15
                feedback.append(f"{EXP_DEP2_NAME} details correct.")
            else:
                score += 5
                feedback.append(f"{EXP_DEP2_NAME} DOB incorrect (Expected {EXP_DEP2_DOB}, Got {dep2.get('dob')}).")
        else:
            feedback.append(f"{EXP_DEP2_NAME} relationship incorrect (Expected {EXP_DEP2_REL}, Got {rel_type}).")
    else:
        feedback.append(f"Dependent {EXP_DEP2_NAME} NOT found.")

    # Linkage check (Implicit: if we found them via query on emp_number, they are linked)
    if dep1 or dep2:
        score += 10
        feedback.append("Dependents correctly linked to employee.")

    # 3. VLM Verification (Trajectory Check)
    # We only run this if we have partial success to confirm workflow or debug
    # But as per requirements, we should use it as an independent signal.
    # Since DB verification is very strong here, we treat VLM as confirmation of the "Dependents" tab visit.
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames and final_img:
            prompt = (
                "Review this sequence of screenshots from an HR software task.\n"
                "1. Does the user navigate to an employee list or 'Add Employee' form?\n"
                "2. Is there a screen showing the 'Dependents' tab/section being accessed?\n"
                "3. In the final state, is there a list of dependents visible?\n"
                "Return valid JSON: {'add_employee_workflow': bool, 'dependents_tab_visited': bool, 'dependents_visible_final': bool}"
            )
            
            # We use the frames + final image
            vlm_resp = query_vlm(images=frames + [final_img], prompt=prompt)
            
            if vlm_resp.get("success"):
                vlm_data = vlm_resp.get("parsed", {})
                if not vlm_data.get("dependents_tab_visited", False) and score > 50:
                     feedback.append("(Warning: VLM did not clearly see Dependents tab interaction).")
            
    # 4. Final Verdict
    passed = (score >= 75) and result.get("employee_found", False)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }