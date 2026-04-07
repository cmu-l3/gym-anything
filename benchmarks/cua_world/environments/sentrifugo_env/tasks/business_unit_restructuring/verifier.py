#!/usr/bin/env python3
"""
Verifier for business_unit_restructuring task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Database DB check (primary objective evaluation)
2. Trajectory VLM check (process matters/anti-gaming evaluation)

Scoring (100 pts total):
  - DB checks (80% of final score):
    - "Acme Corp Technology" BU exists: 16 pts
    - Engineering in Tech: 14 pts
    - Data Science in Tech: 14 pts
    - DevOps & Infrastructure in Tech: 14 pts
    - Quality Assurance in Tech: 14 pts
    - Precision: Non-tech depts still in HQ: Starts at 28 pts, loses 5 pts per dept moved wrongly.
  - VLM checks (20% of final score):
    - Trajectory frames show the agent navigated the Sentrifugo Organization UI.

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_business_unit_restructuring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_bu = metadata.get('expected_bu', "Acme Corp Technology")
    tech_depts = metadata.get('tech_depts', [])
    hq_depts = metadata.get('hq_depts', [])
    
    # -------------------------------------------------------------------------
    # 1. Fetch JSON State from Container
    # -------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # 2. Score the Database State
    # -------------------------------------------------------------------------
    db_score = 0
    feedback_parts = []
    
    bu_created = result.get('bu_created', False)
    mappings = result.get('department_mappings', {})

    if bu_created:
        db_score += 16
        feedback_parts.append(f"BU '{expected_bu}' created (16/16)")
    else:
        feedback_parts.append(f"BU '{expected_bu}' missing (0/16)")

    # Tech Departments moved to new BU (14 pts each)
    correct_tech = 0
    for dept in tech_depts:
        actual_bu = mappings.get(dept, "Unknown")
        if actual_bu == expected_bu:
            db_score += 14
            correct_tech += 1
            feedback_parts.append(f"{dept} -> {expected_bu} (14/14)")
        else:
            feedback_parts.append(f"{dept} -> {actual_bu} (0/14)")

    # Non-Tech Departments Precision (28 pts total, -5 per error)
    precision_score = 28
    mistakes = 0
    for dept in hq_depts:
        actual_bu = mappings.get(dept, "Unknown")
        if actual_bu != "Acme Corp HQ":
            mistakes += 1
            precision_score = max(0, precision_score - 5)
            
    db_score += precision_score
    if mistakes == 0:
        feedback_parts.append(f"Precision perfect: No non-tech depts moved (28/28)")
    else:
        feedback_parts.append(f"Precision penalized: {mistakes} non-tech dept(s) moved ({precision_score}/28)")

    # Check for "Do Nothing" shortcut (0 departments moved and BU not created)
    if not bu_created and correct_tech == 0 and mistakes == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Initial state unchanged. Agent did not perform the task."
        }

    # -------------------------------------------------------------------------
    # 3. Trajectory Verification via VLM (Anti-Gaming Check)
    # -------------------------------------------------------------------------
    vlm_score = 0
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final]
            images = [img for img in images if img is not None]

            if images:
                prompt = (
                    "Review these screenshots from a user's session. Did the user actively interact "
                    "with the Sentrifugo HRMS web interface (specifically navigating the Organization, "
                    "Business Units, or Departments screens) to complete the task? Reply YES or NO."
                )
                vlm_resp = query_vlm(images=images, prompt=prompt)
                
                if vlm_resp and "YES" in vlm_resp.upper():
                    vlm_score = 100
                    vlm_feedback = "VLM verified active UI interaction."
                else:
                    vlm_score = 0
                    vlm_feedback = "VLM did not detect Sentrifugo UI interaction (possible script injection)."
            else:
                # No images available, fail open
                vlm_score = 100
                vlm_feedback = "No trajectory frames found for VLM (pass by default)."
        except Exception as e:
            logger.warning(f"VLM verification failed, giving benefit of the doubt: {e}")
            vlm_score = 100
            vlm_feedback = "VLM exception (pass by default)."
    else:
        # If framework doesn't provide VLM, fail open to avoid penalizing valid runs
        vlm_score = 100
        vlm_feedback = "VLM capability not available (pass by default)."

    # -------------------------------------------------------------------------
    # 4. Final Calculation
    # -------------------------------------------------------------------------
    # Database is 80% of score, VLM check is 20%
    final_score = (db_score * 0.8) + (vlm_score * 0.2)
    passed = final_score >= 70

    feedback = f"Total: {final_score}/100 [DB: {db_score}/100, VLM: {vlm_score}/100]. Details: " + " | ".join(feedback_parts) + f" | {vlm_feedback}"

    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }