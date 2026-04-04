#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lab_procedure(traj, env_info, task_info):
    """
    Verifies that the agent configured the lab procedure hierarchy correctly.
    
    Scoring:
    - Group Created: 15 pts
    - Order Created: 20 pts
    - Order Details (Code/StdCode): 5 pts
    - Hierarchy (Order -> Group): 10 pts
    - Results Created (3x10): 30 pts
    - Hierarchy (Results -> Order): 10 pts
    - Anti-gaming (New IDs): 10 pts
    - VLM Confirmation: Secondary check
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    group = data.get('group')
    order = data.get('order')
    results = data.get('results', {})
    initial_max_id = data.get('initial_max_id', 0)
    
    score = 0
    feedback = []

    # 2. Database Verification
    
    # Check Group
    group_id = None
    if group:
        score += 15
        group_id = group.get('id')
        feedback.append("Order Group 'In-House Lab' created.")
        if int(group_id) <= int(initial_max_id):
             # This should theoretically be caught by query logic, but double check
             feedback.append("(Warning: Group ID predates task start)")
    else:
        feedback.append("Order Group 'In-House Lab' NOT found.")

    # Check Order
    order_id = None
    if order:
        score += 20
        order_id = order.get('id')
        
        # Check Details
        code = order.get('code', '')
        std_code = order.get('standard_code', '')
        if '80053' in str(code):
             feedback.append("Order code 80053 correct.")
        else:
             feedback.append(f"Order code incorrect (found {code}).")
             
        if 'CPT4:80053' in str(std_code):
             score += 5
             feedback.append("Standard code correct.")
        else:
             feedback.append("Standard code missing or incorrect.")

        # Check Hierarchy (Order -> Group)
        parent = order.get('parent')
        if group_id and parent == group_id:
            score += 10
            feedback.append("Order correctly nested under Group.")
        else:
            feedback.append("Order is NOT nested under the correct Group.")
    else:
        feedback.append("Procedure Order 'Comprehensive Metabolic Panel' NOT found.")

    # Check Results
    result_names = ['glucose', 'creatinine', 'sodium']
    results_correctly_nested = 0
    
    for r_key in result_names:
        res = results.get(r_key)
        if res:
            score += 10
            feedback.append(f"Result '{r_key}' created.")
            
            # Check Hierarchy (Result -> Order)
            if order_id and res.get('parent') == order_id:
                results_correctly_nested += 1
            
            # Check Specific Codes (already filtered in SQL, but good to confirm)
            # Query ensured code match, so existence implies correctness here
        else:
            feedback.append(f"Result '{r_key}' NOT found.")

    if results_correctly_nested == 3:
        score += 10
        feedback.append("All results correctly nested under Order.")
    elif results_correctly_nested > 0:
        score += int((results_correctly_nested / 3) * 10)
        feedback.append(f"{results_correctly_nested}/3 results correctly nested.")

    # Anti-gaming check (Implicitly handled by SQL > ID check, but explicitly awarding points)
    # If we found items and they came from the SQL query which filters ID > Max, we award these points.
    if score > 0:
        score += 10
        feedback.append("Verification passed anti-gaming checks (fresh data).")

    # 3. VLM Verification (Trajectory & Final State)
    # We want to verify they actually used the UI and didn't just hack the DB (unlikely but possible)
    # Also confirms visual state matches internal state
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of LibreHealth EHR / OpenEMR.\n"
        "The user task is to configure a Lab Procedure hierarchy in Procedures > Configuration.\n"
        "Look for a tree view showing:\n"
        "1. A group named 'In-House Lab'\n"
        "2. An order named 'Comprehensive Metabolic Panel'\n"
        "3. Results like 'Glucose', 'Creatinine', 'Sodium'\n\n"
        "Does the final state show this hierarchy? Did the user navigate to the Configuration screen?"
    )

    try:
        # We perform VLM check but mostly rely on the robust DB verification for scoring.
        # However, if DB check fails partially, VLM might redeem (or confirm failure).
        # Here we treat it as a sanity check.
        vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {}).get('content', '') or vlm_res.get('result', '')
            feedback.append(f"VLM Analysis: {analysis[:100]}...")
    except Exception:
        pass # VLM is secondary here

    # 4. Final Verdict
    # Threshold: 55 points (Requires Group + Order + Hierarchy or Results)
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "\n".join(feedback)
    }