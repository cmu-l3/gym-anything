#!/usr/bin/env python3
"""
Verifier for Moodle: Configure Weighted Gradebook

Checks:
1. Grade categories created ("Lab Reports", "Examinations", "Final Project").
2. Weights applied accurately (25, 50, 25).
3. Manual items created ("Midterm Paper", "Prototype Demonstration").
4. Nesting applied successfully (Manual items belong to the correct category).
5. Anti-gaming check (Ensures items were modified/created during the task).
6. VLM Trajectory Verification to ensure organic interaction with Gradebook UI.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt for VLM Trajectory Verification
VLM_PROMPT = """You are verifying an AI agent's trajectory performing a Moodle task.
The task was to configure a "Weighted Gradebook" by setting up categories ("Lab Reports", "Examinations", "Final Project") and assigning specific weights.

Look at these chronologically sampled screenshots from the task and answer:
1. GRADEBOOK_ACCESSED: Did the agent navigate to the "Gradebook setup" page for the Thermodynamics course?
2. INTERACTION_VISIBLE: Is there evidence of the agent typing category names, editing weights, or adding grade items?
3. FINAL_UI_CORRECT: In the later frames, do you see the Moodle Gradebook Setup table displaying the correct categories and their relative weights (25, 50, 25)?

Respond in JSON format:
{
    "gradebook_accessed": true/false,
    "interaction_visible": true/false,
    "final_ui_correct": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible in the frames."
}"""

def verify_weighted_gradebook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_categories = metadata.get('expected_categories', {})
    expected_items = metadata.get('expected_items', {})

    score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get("task_start_time", 0)
    
    if not result.get("course_exists", False):
        return {"passed": False, "score": 0, "feedback": "Course 'ENG201' or its Gradebook data could not be found."}

    categories_db = result.get("categories", [])
    items_db = result.get("items", [])

    # Map ID -> Category Name
    cat_id_to_name = {}
    for cat in categories_db:
        if cat.get('fullname') and cat.get('fullname') != '?':
            cat_id_to_name[cat['id']] = cat['fullname'].strip()

    # Map Category Item Instance -> Category ID -> Weights
    # In Moodle, categories are linked in `mdl_grade_items` where `itemtype`='category'
    cat_name_to_weight = {}
    for item in items_db:
        if item.get('itemtype') == 'category':
            cat_instance_id = item.get('iteminstance')
            if cat_instance_id in cat_id_to_name:
                name = cat_id_to_name[cat_instance_id]
                # Weights can be stored in aggregationcoef or aggregationcoef2 depending on Moodle aggregation method
                w1 = float(item.get('aggregationcoef', 0) or 0)
                w2 = float(item.get('aggregationcoef2', 0) or 0)
                # Max value found will be considered the applied weight
                weight = max(w1, w2)
                
                # Normalization check (e.g., Moodle might store 25% as 0.25)
                if 0 < weight <= 1.0 and sum(expected_categories.values()) > 1.0:
                    weight *= 100 
                
                cat_name_to_weight[name] = weight

    # Map manual items to their parent category
    manual_items = {}
    items_modified_during_task = False
    
    for item in items_db:
        if item.get('itemtype') == 'manual':
            # Check timestamps to detect gaming / "do nothing" state
            timemodified = int(item.get('timemodified', 0) or 0)
            timecreated = int(item.get('timecreated', 0) or 0)
            if timemodified >= task_start or timecreated >= task_start:
                items_modified_during_task = True
            
            parent_cat_id = item.get('categoryid')
            parent_name = cat_id_to_name.get(parent_cat_id, "Unknown")
            manual_items[item.get('itemname', '').strip()] = parent_name

    # Check 1: Categories Created (30 pts)
    found_categories = 0
    for req_cat in expected_categories.keys():
        if req_cat in cat_id_to_name.values():
            found_categories += 1
            score += 10
            
    if found_categories == 3:
        feedback_parts.append("All categories created.")
    else:
        feedback_parts.append(f"Found {found_categories}/3 categories.")

    # Check 2: Weights Applied correctly (15 pts)
    correct_weights = 0
    for req_cat, req_weight in expected_categories.items():
        if req_cat in cat_name_to_weight:
            actual_weight = cat_name_to_weight[req_cat]
            if abs(actual_weight - req_weight) < 1.0:
                correct_weights += 1
                score += 5
                
    if correct_weights == 3:
        feedback_parts.append("All weights perfectly assigned.")
    else:
        feedback_parts.append(f"Found {correct_weights}/3 correct weights.")

    # Check 3 & 4: Manual Items and Nesting (40 pts)
    items_correct = 0
    nesting_correct = 0
    for req_item, req_parent in expected_items.items():
        if req_item in manual_items:
            items_correct += 1
            score += 10
            if manual_items[req_item] == req_parent:
                nesting_correct += 1
                score += 10
                
    feedback_parts.append(f"Manual Items: {items_correct}/2 created, {nesting_correct}/2 properly nested.")

    # Check 5: Anti-gaming Timestamp Check
    if not items_modified_during_task and (items_correct > 0 or found_categories > 0):
        # Gradebook exists, but was not touched during the execution window
        return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: DB items match but were NOT created/modified during the task window."}

    # Check 6: VLM Trajectory Verification (15 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('gradebook_accessed', False):
                    vlm_score += 5
                if parsed.get('interaction_visible', False):
                    vlm_score += 5
                if parsed.get('final_ui_correct', False):
                    vlm_score += 5
                    
                score += vlm_score
                feedback_parts.append(f"VLM Score: {vlm_score}/15.")
            else:
                feedback_parts.append("VLM query failed or returned no parsable data.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM Verification skipped/failed.")

    # Passed Threshold
    # Ensure they at least created the categories and items (60+ points from DB checks)
    passed = score >= 70 and found_categories >= 2 and items_correct == 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }