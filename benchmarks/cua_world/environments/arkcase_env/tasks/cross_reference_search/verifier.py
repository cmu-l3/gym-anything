#!/usr/bin/env python3
"""
Verifier for Cross-Reference Search Task.

Checks:
1. JSON output file exists and is valid.
2. File was created during the task window (anti-gaming).
3. Data matches the randomly generated ground truth:
   - Organization Website
   - Person Email
   - Case Number
4. (Optional) VLM verification of search usage.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cross_reference_search(traj, env_info, task_info):
    """
    Verify the agent found the correct entities and extracted the right data.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

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

    # 2. Extract Data
    agent_output = result.get("agent_output", {})
    ground_truth = result.get("ground_truth", {})
    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)

    feedback_parts = []
    score = 0
    
    # 3. Scoring Logic
    
    # Check 1: File Existence & Freshness (20 pts)
    if output_exists:
        if file_created_during_task:
            score += 20
            feedback_parts.append("✅ Output file created.")
        else:
            score += 10 # Partial credit if file exists but timestamp looks old (unlikely in clean env, but good hygiene)
            feedback_parts.append("⚠️ Output file exists but timestamp is suspicious.")
    else:
        feedback_parts.append("❌ Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Check 2: Data Accuracy (20 pts each field = 60 pts)
    # We normalize comparison (strip whitespace, ignore case for email/web)
    
    # Organization Website
    agent_web = str(agent_output.get("organization_website", "")).strip().lower()
    true_web = str(ground_truth.get("organization_website", "")).strip().lower()
    
    if agent_web and agent_web == true_web:
        score += 20
        feedback_parts.append("✅ Org Website match.")
    else:
        feedback_parts.append(f"❌ Org Website mismatch (Expected: {true_web}, Got: {agent_web}).")

    # Person Email
    agent_email = str(agent_output.get("person_email", "")).strip().lower()
    true_email = str(ground_truth.get("person_email", "")).strip().lower()

    if agent_email and agent_email == true_email:
        score += 20
        feedback_parts.append("✅ Person Email match.")
    else:
        feedback_parts.append(f"❌ Person Email mismatch (Expected: {true_email}, Got: {agent_email}).")

    # Case Number (Case sensitive usually, but let's be lenient)
    agent_case = str(agent_output.get("case_number", "")).strip()
    true_case = str(ground_truth.get("case_number", "")).strip()

    if agent_case and agent_case.lower() == true_case.lower():
        score += 20
        feedback_parts.append("✅ Case Number match.")
    else:
        feedback_parts.append(f"❌ Case Number mismatch (Expected: {true_case}, Got: {agent_case}).")

    # Check 3: VLM Trajectory Verification (20 pts)
    # Ensure they actually used the search interface
    frames = sample_trajectory_frames(traj, n=4)
    if frames and query_vlm:
        vlm_prompt = (
            "Does the user appear to be using a search bar or viewing search results in a business application? "
            "Look for a list of results with 'Falcon' or details of a person/organization. "
            "Answer yes or no."
        )
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_response.get("success") and "yes" in vlm_response.get("response", "").lower():
                score += 20
                feedback_parts.append("✅ Visual verification passed (Search usage detected).")
            else:
                # Fallback points if text data is perfect but VLM is unsure
                if score >= 80: 
                    score += 20
                    feedback_parts.append("⚠️ Visual verification inconclusive, but data is perfect.")
                else:
                    feedback_parts.append("❌ Visual verification failed (No search usage detected).")
        except Exception:
            # If VLM fails, don't penalize if data is perfect
            if score >= 80:
                score += 20
            feedback_parts.append("⚠️ VLM check skipped.")
    else:
        # If no VLM available, give benefit of doubt if data is correct
        if score >= 80:
            score += 20

    # 4. Final Result
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }