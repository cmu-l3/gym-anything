#!/usr/bin/env python3
"""
Verifier for configure_org_structure task.

Verifies:
1. Database State: Checks if specific units exist and have correct parent-child relationships
   using the Nested Set Model (lft/rgt bounds).
2. Anti-Gaming: Ensures data was created during the task.
3. VLM: Verifies UI interaction using trajectory frames.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_org_structure(traj, env_info, task_info):
    """
    Verify the organizational structure creation.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    target_structure = metadata.get('target_structure', [])
    
    # Copy result JSON from container
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

    db_data = result.get('db_data', [])
    initial_count = result.get('initial_count', 0)
    
    score = 0
    feedback = []
    
    # 2. Anti-Gaming Check (Data Creation)
    # Filter out root node (id=1 or level=0)
    new_units = [u for u in db_data if u.get('id', 0) > 1]
    
    if len(new_units) <= int(initial_count):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new organizational units were created in the database."
        }

    # Helper to find unit by name or ID
    def find_unit(name, unit_id):
        for u in db_data:
            # Match strictly by name AND unit_id for full points, or loosen logic below
            if u['name'].strip() == name and u['unit_id'].strip() == unit_id:
                return u
        return None

    # Helper to check nested set hierarchy
    def is_child_of(child, parent_name):
        # Find parent
        parent = None
        for u in db_data:
            if u['name'] == parent_name:
                parent = u
                break
        
        if not child or not parent:
            return False
            
        # Nested set logic: child.lft > parent.lft AND child.rgt < parent.rgt
        return (child['lft'] > parent['lft']) and (child['rgt'] < parent['rgt'])

    # 3. Database Verification (80 Points)
    
    # Level 1: Academic Affairs (20 pts)
    acad = find_unit("Academic Affairs", "ACAD")
    if acad:
        score += 10
        feedback.append("✅ 'Academic Affairs' unit found.")
        # Check parent (Root, usually 'GymAnything Corp' or id=1)
        # Root usually has level 0. Level 1 units should be children of Root.
        root = next((u for u in db_data if u['level'] == 0), None)
        if root and is_child_of(acad, root['name']):
            score += 10
            feedback.append("✅ 'Academic Affairs' is correctly placed under Root.")
        else:
            feedback.append("⚠️ 'Academic Affairs' exists but parent relationship is incorrect.")
    else:
        feedback.append("❌ 'Academic Affairs' (ACAD) not found.")

    # Level 2: Colleges (30 pts)
    for college_name, college_id in [("College of Engineering", "COE"), ("College of Liberal Arts", "CLA")]:
        unit = find_unit(college_name, college_id)
        if unit:
            score += 10
            feedback.append(f"✅ '{college_name}' found.")
            if is_child_of(unit, "Academic Affairs"):
                score += 5
                feedback.append(f"✅ '{college_name}' is correctly under Academic Affairs.")
            else:
                feedback.append(f"⚠️ '{college_name}' is not under Academic Affairs.")
        else:
            feedback.append(f"❌ '{college_name}' ({college_id}) not found.")

    # Level 3: Departments (30 pts)
    for dept_name, dept_id in [("Department of Computer Science", "CS"), ("Department of Electrical Engineering", "EE")]:
        unit = find_unit(dept_name, dept_id)
        if unit:
            score += 10
            feedback.append(f"✅ '{dept_name}' found.")
            if is_child_of(unit, "College of Engineering"):
                score += 5
                feedback.append(f"✅ '{dept_name}' is correctly under College of Engineering.")
            else:
                feedback.append(f"⚠️ '{dept_name}' is not under College of Engineering.")
        else:
            feedback.append(f"❌ '{dept_name}' ({dept_id}) not found.")

    # 4. VLM Verification (20 Points)
    # Use trajectory frames to verify the user actually navigated the UI
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        You are verifying if an agent successfully configured an organizational structure in OrangeHRM.
        Look at the sequence of screenshots.
        
        Check for:
        1. Navigation to "Organization Structure" or "Company Structure" page.
        2. Interaction with a tree diagram (clicking 'Edit', 'Add', or '+' buttons).
        3. Filling out input fields for "Unit Id" or "Name".
        4. The final tree structure showing "Academic Affairs", "Colleges", and "Departments".
        
        Return JSON:
        {
            "ui_navigation_confirmed": true/false,
            "tree_interaction_visible": true/false,
            "final_tree_visible": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                vlm_score = 0
                if parsed.get("ui_navigation_confirmed"): vlm_score += 5
                if parsed.get("tree_interaction_visible"): vlm_score += 10
                if parsed.get("final_tree_visible"): vlm_score += 5
                
                score += vlm_score
                feedback.append(f"✅ VLM verification added {vlm_score} points.")
            else:
                # If VLM fails, we don't penalize database success, but we can't award bonus points
                feedback.append("⚠️ VLM verification failed to process images.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback.append("⚠️ VLM verification skipped due to error.")
    else:
        # Graceful fallback if VLM not available, normalize score to exclude VLM portion
        # Current max without VLM is 80. If perfect, scale to 100.
        if score > 0:
            score = int(score * (100/80))
            feedback.append("ℹ️ VLM not available; score scaled.")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score), # Cap at 100
        "feedback": "\n".join(feedback)
    }