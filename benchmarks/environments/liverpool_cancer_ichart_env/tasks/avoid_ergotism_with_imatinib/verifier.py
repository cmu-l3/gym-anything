#!/usr/bin/env python3
"""
Verifier for avoid_ergotism_with_imatinib task.

Criteria:
1. Result file exists and was created during the task.
2. Content correctly identifies Ergotamine as Red/Contraindicated.
3. Content correctly identifies Sumatriptan as Green/Yellow/Safe.
4. Recommendation is Sumatriptan.
5. VLM verification of trajectory confirms app usage and red warning screen.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_avoid_ergotism(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timestamp (20 points)
    file_exists = result.get('file_exists', False)
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    
    if file_mtime < task_start:
        feedback_parts.append("File timestamp predates task start (anti-gaming failure)")
        # Continue but no points for creation
    else:
        score += 20
        feedback_parts.append("Report file created successfully")

    # 2. Content Analysis (50 points)
    content = result.get('file_content', '')
    lines = content.split('\n')
    
    ergotamine_correct = False
    sumatriptan_correct = False
    recommendation_correct = False
    
    # Regex to find colors/drugs loosely
    ergotamine_match = re.search(r'Ergotamine.*?(Red|Do Not Administer)', content, re.IGNORECASE)
    sumatriptan_match = re.search(r'Sumatriptan.*?(Green|Yellow|No Interaction)', content, re.IGNORECASE)
    recommendation_match = re.search(r'Recommendation.*?(Sumatriptan)', content, re.IGNORECASE)
    
    if ergotamine_match:
        score += 20
        ergotamine_correct = True
        feedback_parts.append("Correctly identified Ergotamine risk (Red)")
    else:
        feedback_parts.append("Failed to identify Ergotamine as Red/Contraindicated")

    if sumatriptan_match:
        score += 15
        sumatriptan_correct = True
        feedback_parts.append("Correctly identified Sumatriptan safety")
    else:
        feedback_parts.append("Failed to identify Sumatriptan as Safe")

    if recommendation_match:
        score += 15
        recommendation_correct = True
        feedback_parts.append("Correctly recommended Sumatriptan")
    else:
        feedback_parts.append("Failed to recommend Sumatriptan")

    # 3. VLM Trajectory Verification (30 points)
    # We want to see: 
    # - Navigation to Imatinib
    # - The Red warning screen (Ergotamine)
    # - The Green/Yellow screen (Sumatriptan)
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the Liverpool Cancer iChart app.
    The agent should have:
    1. Selected the cancer drug 'Imatinib'.
    2. Checked interaction with 'Ergotamine' (Look for a RED banner or 'Do Not Coadminister').
    3. Checked interaction with 'Sumatriptan' (Look for a GREEN/YELLOW banner or 'No Interaction').
    
    Review the screenshots and answer:
    - Did you see Imatinib selected?
    - Did you see a RED interaction result screen?
    - Did you see a GREEN or YELLOW interaction result screen?
    
    Return JSON:
    {
        "imatinib_seen": true/false,
        "red_result_seen": true/false,
        "green_yellow_result_seen": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    vlm_score = 0
    if vlm_data.get('imatinib_seen', False):
        vlm_score += 10
    if vlm_data.get('red_result_seen', False):
        vlm_score += 10
    if vlm_data.get('green_yellow_result_seen', False):
        vlm_score += 10
        
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"Visual verification passed ({vlm_score}/30 pts)")
    else:
        feedback_parts.append("Visual verification failed to confirm workflow")

    # Final Check
    passed = (score >= 80) and ergotamine_correct and recommendation_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }