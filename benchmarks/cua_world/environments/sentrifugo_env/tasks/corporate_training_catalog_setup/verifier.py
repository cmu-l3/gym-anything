#!/usr/bin/env python3
"""
Verifier for corporate_training_catalog_setup task.

Ensures that training providers and courses are created and relationally linked,
preventing gaming via strict validation and VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_training_setup(traj, env_info, task_info):
    # 1. Ensure copy_from_env is available
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Extract results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            db_state = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported state: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    providers = db_state.get('providers', [])
    courses = db_state.get('courses', [])
    
    score = 0
    feedback_parts = []
    
    # Check if a database error occurred
    if len(providers) > 0 and "error" in providers[0]:
        return {"passed": False, "score": 0, "feedback": "Failed to query providers table from Sentrifugo."}

    # Helper to safely check values regardless of strict Sentrifugo schema casing
    def search_records(records, search_term, field_hints=None):
        search_term = search_term.lower()
        for r in records:
            for k, v in r.items():
                if v and search_term in str(v).lower():
                    return r
        return None

    # --- CRITERION: Provider 1 (15 pts) ---
    p1 = search_records(providers, "Red Cross Safety Institute")
    p1_id = None
    if p1:
        # Verify contact details are roughly correct to prevent blank bypasses
        p1_details = str(p1.values()).lower()
        if "jane.doe@redcross-mock.org" in p1_details and "555-0192" in p1_details:
            score += 15
            p1_id = p1.get('id') or p1.get('ID')
            feedback_parts.append("Provider 1 (Red Cross) created accurately.")
        else:
            score += 8
            p1_id = p1.get('id') or p1.get('ID')
            feedback_parts.append("Provider 1 (Red Cross) exists but missing correct contact info.")
    else:
        feedback_parts.append("Provider 1 (Red Cross) missing.")

    # --- CRITERION: Provider 2 (15 pts) ---
    p2 = search_records(providers, "TechAdvantage Learning")
    p2_id = None
    if p2:
        p2_details = str(p2.values()).lower()
        if "alan.turing@techadvantage-mock.com" in p2_details and "555-0198" in p2_details:
            score += 15
            p2_id = p2.get('id') or p2.get('ID')
            feedback_parts.append("Provider 2 (TechAdvantage) created accurately.")
        else:
            score += 8
            p2_id = p2.get('id') or p2.get('ID')
            feedback_parts.append("Provider 2 (TechAdvantage) exists but missing correct contact info.")
    else:
        feedback_parts.append("Provider 2 (TechAdvantage) missing.")

    # --- CRITERION: Course 1 (20 pts + 5 pts link) ---
    c1 = search_records(courses, "Occupational First Aid & CPR")
    if c1:
        score += 20
        feedback_parts.append("Course 1 exists.")
        
        # Verify provider relation
        c1_provider_id = str(c1.get('provider_id') or c1.get('providerid') or c1.get('trainingprovider_id'))
        if str(p1_id) == c1_provider_id and p1_id is not None:
            score += 5
            feedback_parts.append("Course 1 correctly linked to Red Cross.")
        else:
            feedback_parts.append("Course 1 exists but NOT correctly linked to Red Cross.")
    else:
        feedback_parts.append("Course 1 missing.")

    # --- CRITERION: Course 2 (20 pts + 5 pts link) ---
    c2 = search_records(courses, "Advanced Python for Data Science")
    if c2:
        score += 20
        feedback_parts.append("Course 2 exists.")
        
        # Verify provider relation
        c2_provider_id = str(c2.get('provider_id') or c2.get('providerid') or c2.get('trainingprovider_id'))
        if str(p2_id) == c2_provider_id and p2_id is not None:
            score += 5
            feedback_parts.append("Course 2 correctly linked to TechAdvantage.")
        else:
            feedback_parts.append("Course 2 exists but NOT correctly linked to TechAdvantage.")
    else:
        feedback_parts.append("Course 2 missing.")

    # --- CRITERION: Course 3 (15 pts + 5 pts link) ---
    c3 = search_records(courses, "Cloud Architecture Fundamentals")
    if c3:
        score += 15
        feedback_parts.append("Course 3 exists.")
        
        # Verify provider relation
        c3_provider_id = str(c3.get('provider_id') or c3.get('providerid') or c3.get('trainingprovider_id'))
        if str(p2_id) == c3_provider_id and p2_id is not None:
            score += 5
            feedback_parts.append("Course 3 correctly linked to TechAdvantage.")
        else:
            feedback_parts.append("Course 3 exists but NOT correctly linked to TechAdvantage.")
    else:
        feedback_parts.append("Course 3 missing.")

    # --- ANTI-GAMING VLM TRAJECTORY CHECK ---
    # Ensures the agent didn't just magic the DB via SQL injection in the terminal
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_scr = get_final_screenshot(traj)
            
            prompt = (
                "Review these screenshots from an agent automating a task in Sentrifugo HRMS. "
                "Did the agent navigate to the 'Training' or 'Training Providers' / 'Training Courses' "
                "UI sections at any point? Reply simply YES or NO."
            )
            vlm_res = query_vlm(images=frames + [final_scr], prompt=prompt)
            vlm_ans = vlm_res.get('response', '').upper()
            if "YES" not in vlm_ans and score > 0:
                logger.warning("VLM Trajectory check failed. Agent may have bypassed UI.")
                score = int(score * 0.5) # Penalize 50% for direct SQL injection/bypassing UI
                feedback_parts.append("Penalty: VLM found no visual evidence of UI interaction with Training module.")
        except Exception as e:
            logger.warning(f"VLM verification exception (ignoring): {e}")

    # Calculate final passing state
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }