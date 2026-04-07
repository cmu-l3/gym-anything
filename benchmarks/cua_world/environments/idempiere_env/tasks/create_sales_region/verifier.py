#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

def verify_create_sales_region(traj, env_info, task_info):
    """
    Verifies the create_sales_region task.
    
    Criteria:
    1. Sales Region 'PNW' exists in database.
    2. Region Name is 'Pacific North West'.
    3. Region Description contains expected text.
    4. Business Partner 'Joe Block' is assigned to the new Region ID.
    5. Anti-gaming: Records created/modified during task session.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_region_name', 'Pacific North West')
    expected_desc_part = metadata.get('expected_description_part', 'Territory covering')

    score = 0
    feedback_log = []

    # 2. Database Verification (Primary)
    
    # Check 1: Region Creation (30 pts)
    if result.get('region_found'):
        score += 30
        feedback_log.append("✅ Sales Region 'PNW' created.")
    else:
        feedback_log.append("❌ Sales Region 'PNW' not found.")
        
    # Check 2: Region Details (20 pts)
    actual_name = result.get('region_name', '')
    actual_desc = result.get('region_desc', '')
    
    if actual_name == expected_name:
        score += 10
        feedback_log.append(f"✅ Region Name is correct ('{actual_name}').")
    else:
        feedback_log.append(f"❌ Region Name incorrect. Expected '{expected_name}', got '{actual_name}'.")

    if expected_desc_part.lower() in actual_desc.lower():
        score += 10
        feedback_log.append("✅ Region Description contains expected text.")
    else:
        feedback_log.append(f"❌ Region Description missing keywords ('{expected_desc_part}').")

    # Check 3: Assignment to Joe Block (30 pts)
    if result.get('bp_assignment_correct'):
        score += 30
        feedback_log.append("✅ 'Joe Block' is correctly assigned to the new region.")
    else:
        # Diagnostic feedback
        bp_rid = result.get('bp_region_id', 'None')
        new_rid = result.get('new_region_id', 'None')
        feedback_log.append(f"❌ 'Joe Block' assignment incorrect. BP Region ID: {bp_rid}, New Region ID: {new_rid}.")

    # Check 4: Anti-Gaming / Integrity (20 pts)
    # The record must have been created during the task
    if result.get('created_during_task'):
        score += 20
        feedback_log.append("✅ Record creation timestamp verified (created during task).")
    elif result.get('region_found'):
         feedback_log.append("⚠️ Record exists but timestamp check failed (pre-existing?).")
    
    # 3. Optional VLM Verification (Bonus/Confirmation)
    # If the score is borderline, VLM can confirm UI state, but usually DB is sufficient here.
    # We will use it to ensure the agent actually navigated the UI if DB checks pass but look suspicious,
    # or simply as a trajectory check.
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using iDempiere ERP.
        Did the agent:
        1. Access a "Sales Region" window?
        2. Access a "Business Partner" window for "Joe Block"?
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_res.get('success'):
                # We don't modify score strictly based on VLM here unless DB failed, 
                # but we append the observation.
                feedback_log.append(f"VLM Observation: {vlm_res.get('response', 'Analyzed')}")
        except Exception:
            pass # VLM failure shouldn't fail the task if DB is correct

    # 4. Final Result
    passed = (score >= 70) and result.get('region_found') and result.get('bp_assignment_correct')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }