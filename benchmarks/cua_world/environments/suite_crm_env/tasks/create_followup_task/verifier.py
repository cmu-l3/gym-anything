#!/usr/bin/env python3
"""
Verifier for create_followup_task task.

Evaluates the SuiteCRM task creation based on multiple signals:
1. Task Count Increased (Anti-gaming check)
2. Task created with correct/partial Subject Match
3. Correct Field Values (Priority, Status, Due Date)
4. Description contains expected keywords
5. VLM workflow verification via trajectory
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_followup_task(traj, env_info, task_info):
    """Verifies that the task record was properly created in the database."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Prepare Proposal for Meridian Retail Group')
    expected_priority = metadata.get('expected_priority', 'High')
    expected_due_date = metadata.get('expected_due_date', '2025-03-14')
    desc_keywords = metadata.get('desc_keywords', ['discovery call', 'loyalty program', 'ROI', 'case stud', '45,000'])

    # Copy results from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # -------------------------------------------------------------------------
    # Check 1: Count Increased (10 points) - ANTI-GAMING
    # -------------------------------------------------------------------------
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    task_created = current_count > initial_count
    if task_created:
        score += 10
        feedback.append("Task count increased (Anti-gaming pass)")
    else:
        feedback.append("Task count did NOT increase - No new task created")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback),
            "details": {"error": "Count did not increase, task failed."}
        }

    # -------------------------------------------------------------------------
    # Check 2: Task Subject Match (30 points for exact, 15 for partial)
    # -------------------------------------------------------------------------
    task_found = result.get('task_found', False)
    actual_name = result.get('name', '')

    subject_match = False
    if task_found:
        if actual_name.strip() == expected_subject:
            score += 30
            subject_match = True
            feedback.append("Exact subject match")
        elif "Meridian Retail" in actual_name:
            score += 15
            subject_match = True
            feedback.append(f"Partial subject match ('{actual_name}')")
        else:
            feedback.append(f"Subject mismatch ('{actual_name}')")
    else:
        feedback.append("No task matching Meridian Retail Group was found.")

    if not subject_match:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    # -------------------------------------------------------------------------
    # Check 3: Fields (Priority, Status, Due Date) (35 points total)
    # -------------------------------------------------------------------------
    actual_priority = result.get('priority', '')
    if actual_priority.strip().lower() == expected_priority.lower():
        score += 10
        feedback.append("Priority correct (High)")
    else:
        feedback.append(f"Priority incorrect ({actual_priority})")

    actual_status = result.get('status', '')
    # Check SuiteCRM internal keys / display values
    if actual_status in ['Not Started', 'Not_Started']:
        score += 10
        feedback.append("Status correct (Not Started)")
    else:
        feedback.append(f"Status incorrect ({actual_status})")

    actual_due_date = result.get('date_due', '')
    if expected_due_date in actual_due_date:
        score += 15
        feedback.append("Due date correct")
    else:
        feedback.append(f"Due date incorrect ({actual_due_date})")

    # -------------------------------------------------------------------------
    # Check 4: Description content (15 points)
    # -------------------------------------------------------------------------
    actual_description = result.get('description', '').lower()
    matches = sum(1 for kw in desc_keywords if kw.lower() in actual_description)
    
    if matches >= 3:
        score += 15
        feedback.append(f"Description robust ({matches}/{len(desc_keywords)} keywords)")
    elif matches >= 1:
        score += 5
        feedback.append(f"Description partial ({matches}/{len(desc_keywords)} keywords)")
    else:
        feedback.append("Description missing key information")

    # -------------------------------------------------------------------------
    # Check 5: VLM Workflow Trajectory (10 points)
    # -------------------------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames and final_img:
            prompt = (
                "Review these screenshots from an agent interacting with a CRM. "
                "Did the agent navigate to the 'Tasks' module (or activities) "
                "and open the 'Create Task' form? Respond strictly with YES or NO."
            )
            vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
            
            if "YES" in vlm_response.get("parsed", "").upper() or "YES" in vlm_response.get("raw", "").upper():
                score += 10
                feedback.append("VLM confirms Tasks module navigation")
            else:
                feedback.append("VLM could not confirm Tasks module navigation")
    except Exception as e:
        logger.warning(f"VLM verification failed/skipped: {e}")
        # Not penalizing hard if VLM fails due to framework config, but noting it
        pass

    # -------------------------------------------------------------------------
    # Final Score Evaluation
    # -------------------------------------------------------------------------
    passed = score >= 65 and subject_match and task_created
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result
    }