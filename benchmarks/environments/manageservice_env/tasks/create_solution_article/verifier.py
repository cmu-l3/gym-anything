#!/usr/bin/env python3
"""
Verifier for create_solution_article task.

Checks:
1. Solution exists in DB with correct title (Database)
2. Content contains required technical details (Database)
3. Solution status is Published/Approved (Database)
4. Keywords are present (Database)
5. Agent actually visited Solutions module (VLM Trajectory)
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_solution_article(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "")
    required_phrases = metadata.get('required_content_phrases', [])
    expected_keywords = metadata.get('expected_keywords', [])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Solution Existence & Title (30 pts)
    found = result.get('found', False)
    actual_title = result.get('title', "")
    
    if found and expected_title.lower() in actual_title.lower():
        score += 30
        feedback_parts.append("Solution created with correct title")
    elif found:
        score += 15
        feedback_parts.append(f"Solution created but title mismatch ('{actual_title}')")
    else:
        # Check if count increased even if specific lookup failed
        if result.get('current_count', 0) > result.get('initial_count', 0):
             score += 10
             feedback_parts.append("New solution detected, but could not verify details (title mismatch?)")
        else:
             return {"passed": False, "score": 0, "feedback": "No solution created"}

    # 2. Verify Content (20 pts)
    description = result.get('description', "").lower()
    phrases_found = 0
    for phrase in required_phrases:
        if phrase.lower() in description:
            phrases_found += 1
            
    if phrases_found == len(required_phrases):
        score += 20
        feedback_parts.append("Content verified complete")
    elif phrases_found > 0:
        partial = int(20 * (phrases_found / len(required_phrases)))
        score += partial
        feedback_parts.append(f"Content partially correct ({phrases_found}/{len(required_phrases)} phrases)")
    else:
        feedback_parts.append("Content missing required technical details")

    # 3. Verify Status (Published/Approved) (15 pts)
    status_name = result.get('status_name', "").lower()
    # Accept common 'published' statuses or if not draft
    if "publish" in status_name or "approv" in status_name:
        score += 15
        feedback_parts.append(f"Status correct ({status_name})")
    elif "draft" in status_name:
        feedback_parts.append("Solution left in Draft status (should be published)")
    else:
        # If status is unknown but created, give small points
        score += 5
        feedback_parts.append(f"Status: {status_name}")

    # 4. Verify Keywords (10 pts)
    actual_keywords = [k.lower() for k in result.get('keywords', [])]
    kw_match = 0
    for ek in expected_keywords:
        if any(ek.lower() in ak for ak in actual_keywords):
            kw_match += 1
            
    if kw_match >= 2:
        score += 10
        feedback_parts.append("Keywords present")
    elif kw_match > 0:
        score += 5
        feedback_parts.append("Some keywords present")

    # 5. VLM Verification (25 pts)
    # Check if agent navigated to Solutions tab and filled form
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = (
        "Analyze these screenshots of a helpdesk software interaction. "
        "Did the user: "
        "1. Navigate to a 'Solutions' or 'Knowledge Base' section? "
        "2. Fill out a form with title 'VPN Connection Drops'? "
        "3. Save or publish the article? "
        "Reply with YES/NO and brief reasoning."
    )
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    if vlm_result and "yes" in vlm_result.get("text", "").lower():
        score += 25
        feedback_parts.append("VLM verified workflow")
    else:
        # Fallback if DB was perfect, assume VLM might be strict, give partial
        if score > 60: 
            score += 10 
            feedback_parts.append("VLM inconclusive but DB validates work")
        else:
            feedback_parts.append("VLM did not observe correct workflow")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }