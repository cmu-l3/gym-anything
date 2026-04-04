#!/usr/bin/env python3
"""
Verifier for create_sub_server task.

Scoring Criteria (Total 100):
1. Domain Exists (15 pts)
2. Is Sub-Server of correct parent (20 pts)
3. Features Enabled (15 pts each -> 45 pts total): Web, DNS, MySQL
4. Metadata Correct (10 pts): Description matches
5. State Verification (5 pts): Document root exists
6. Anti-Gaming (5 pts): Created during task time

Pass Threshold: 70 pts + Critical Criteria (Domain exists as sub-server)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sub_server(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    max_score = 100
    
    # 2. Scoring Logic
    
    # Criterion 1: Domain Exists (15 pts)
    if result.get('domain_exists'):
        score += 15
        feedback.append("Domain 'blog.greenwidgets.test' created.")
    else:
        feedback.append("Domain 'blog.greenwidgets.test' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Is Sub-Server (20 pts)
    # The parent domain should be greenwidgets.test
    parent = result.get('parent_domain', '')
    if parent == 'greenwidgets.test':
        score += 20
        feedback.append("Correctly created as sub-server.")
    elif parent:
        score += 5 # Partial credit if it's a sub-server of wrong parent (unlikely but possible)
        feedback.append(f"Created under wrong parent: {parent}")
    else:
        feedback.append("Created as top-level server, not sub-server (0 pts).")

    # Criterion 3: Features (45 pts)
    features = result.get('features', {})
    
    # Web (15 pts)
    if features.get('web'):
        score += 15
        feedback.append("Web enabled.")
    else:
        feedback.append("Web feature missing.")

    # DNS (15 pts)
    if features.get('dns'):
        score += 15
        feedback.append("DNS enabled.")
    else:
        feedback.append("DNS feature missing.")

    # MySQL (15 pts)
    if features.get('mysql') and features.get('mysql_db_confirmed'):
        score += 15
        feedback.append("MySQL enabled and DB created.")
    elif features.get('mysql'):
        score += 10 # Feature on but DB check failed?
        feedback.append("MySQL feature enabled, but DB check inconclusive.")
    else:
        feedback.append("MySQL feature missing.")

    # Criterion 4: Description (10 pts)
    desc = result.get('description', '')
    if "greenwidgets company blog" in desc.lower():
        score += 10
        feedback.append("Description correct.")
    else:
        feedback.append(f"Description mismatch (found: '{desc}').")

    # Criterion 5: Doc Root (5 pts)
    if result.get('doc_root_exists'):
        score += 5
        feedback.append("Document root directory confirmed.")
    else:
        feedback.append("Document root directory not found.")

    # Criterion 6: Anti-Gaming (5 pts)
    # Check if domain count increased
    initial = int(result.get('initial_domain_count', 0))
    current = int(result.get('current_domain_count', 0))
    if current > initial:
        score += 5
    else:
        feedback.append("Domain count did not increase (re-used existing?).")

    # 3. VLM Trajectory Check (Tie-breaker / Validation)
    # We only penalize if the score is high but VLM looks completely wrong,
    # or use it to verify they used the GUI.
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user interact with a web form titled 'Create Virtual Server'? "
            "Do they select 'Sub-server' option? "
            "Do they enter 'blog' as the domain? "
            "Answer yes/no with reasoning."
        )
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        # We assume VLM is just logging/secondary here unless we want to enforce GUI usage
        # feedback.append(f"VLM Analysis: {vlm_res.get('text', 'No analysis')}")

    # 4. Final Determination
    passed = False
    # Must have domain, must be sub-server, and respectable score
    if result.get('domain_exists') and parent == 'greenwidgets.test' and score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }