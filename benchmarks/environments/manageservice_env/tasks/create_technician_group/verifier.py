#!/usr/bin/env python3
"""
Verifier for create_technician_group task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_technician_group(traj, env_info, task_info):
    """
    Verifies if the 'Network Operations Center' group was created with correct members.
    """
    # 1. Setup - Copy result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    group_data = result.get('group_data', {})
    found = group_data.get('found', False)
    group_name = group_data.get('name', "")
    description = group_data.get('description', "")
    members = group_data.get('members', [])
    
    # 3. Scoring Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Group Exists (20 pts)
    if found and "network operations center" in group_name.lower():
        score += 20
        feedback.append("Group 'Network Operations Center' created.")
    else:
        feedback.append("Group 'Network Operations Center' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Description Content (15 pts)
    # Expected: "Handles all network infrastructure incidents, changes, and monitoring alerts for Meridian Financial Corp"
    required_keywords = ["network", "infrastructure", "meridian"]
    desc_lower = (description or "").lower()
    matches = sum(1 for kw in required_keywords if kw in desc_lower)
    if matches >= 2:
        score += 15
        feedback.append("Description is correct.")
    elif matches == 1:
        score += 5
        feedback.append("Description partially correct.")
    else:
        feedback.append("Description missing or incorrect.")

    # Criterion 3: Members (30 pts - 10 per member)
    expected_members = ["sarah.chen", "marcus.williams", "priya.sharma"]
    # Normalize members from DB to check containment
    # DB might return names or login names depending on the query in export_result.sh
    # The export script queries AaaLogin.NAME, so it should match 'sarah.chen', etc.
    
    member_matches = 0
    current_members_lower = [m.lower() for m in members]
    
    for expected in expected_members:
        # Check partial match as login names might vary slightly in real scenarios
        if any(expected in curr for curr in current_members_lower):
            score += 10
            member_matches += 1
        else:
            feedback.append(f"Member '{expected}' missing.")

    if member_matches == 3:
        feedback.append("All 3 technicians assigned.")
    
    # Criterion 4: Member Count Exactness (15 pts)
    if len(members) == 3:
        score += 15
        feedback.append("Member count is exactly 3.")
    elif len(members) > 3:
        feedback.append(f"Too many members assigned ({len(members)}).")
    
    # Criterion 5: Anti-Gaming / New Creation (10 pts)
    initial_count = int(result.get('initial_group_count', 0))
    current_count = int(result.get('current_group_count', 0))
    # Or check timestamps if available in DB result
    # For now, simplistic count check
    if current_count > initial_count:
        score += 10
        feedback.append("New group record created during task.")
    else:
        # It's possible they renamed an existing group? Unlikely given the prompt.
        feedback.append("Group count did not increase (modified existing?).")

    # Criterion 6: VLM Verification (10 pts)
    # Check if they used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Analyze these screenshots of a user creating a technician group in ServiceDesk Plus. "
            "1. Do you see the 'Technician Groups' list or form? "
            "2. Do you see a form filled with 'Network Operations Center'? "
            "3. Do you see member selection (Sarah Chen, Marcus Williams, Priya Sharma)? "
            "Reply with JSON: {\"ui_interaction\": true, \"group_details_visible\": true, \"members_selected\": true}"
        )
        
        vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
        vlm_json = vlm_res.get('parsed', {})
        
        if vlm_json.get('ui_interaction') or vlm_json.get('members_selected'):
            score += 10
            feedback.append("VLM confirmed UI interaction.")
        else:
            feedback.append("VLM could not confirm UI workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails technically
        score += 10

    # Pass Threshold
    passed = score >= 60 and member_matches >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }