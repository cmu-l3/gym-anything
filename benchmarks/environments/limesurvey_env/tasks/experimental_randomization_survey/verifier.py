#!/usr/bin/env python3
"""
Verifier for experimental_randomization_survey task.
Verifies the creation of a survey with specific group randomization structure.
"""

import json
import os
import tempfile
import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_experimental_survey(traj, env_info, task_info):
    """
    Verify the framing effect experiment survey.
    
    Criteria:
    1. Survey exists with correct title (Gate)
    2. At least 5 question groups (20 pts)
    3. Randomization:
       - At least 3 groups share the SAME non-empty randomization group (25 pts)
       - That randomization group name is 'experimental' (5 pts)
       - At least 2 groups have NO randomization group (fixed) (10 pts)
    4. Questions: At least 5 total questions (15 pts)
    5. Settings:
       - Backward navigation disabled (10 pts)
       - Anonymized enabled (10 pts)
       - Survey active (5 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    feedback = []
    
    # Gate Check
    if not result.get("survey_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found with 'Framing Effect' in the title."
        }
    
    # Anti-gaming check
    initial_count = int(result.get("initial_survey_count", 0))
    current_count = int(result.get("current_survey_count", 0))
    if current_count <= initial_count:
        feedback.append("Warning: Survey count did not increase (modified existing?)")
        # Proceeding but noting it, as they might have deleted and recreated
    
    # Check Groups
    groups = result.get("groups", [])
    group_count = len(groups)
    
    if group_count >= 5:
        score += 20
        feedback.append(f"Correct number of groups ({group_count}) [+20]")
    else:
        feedback.append(f"Insufficient groups: {group_count} (expected 5) [+0]")
        
    # Analyze Randomization
    rand_groups = []
    fixed_groups = 0
    
    for g in groups:
        rg = g.get("randomization_group", "").strip()
        if rg:
            rand_groups.append(rg)
        else:
            fixed_groups += 1
            
    # Count frequencies of randomization strings
    rand_counts = Counter(rand_groups)
    # Find the most common randomization group
    if rand_counts:
        most_common_rg, count = rand_counts.most_common(1)[0]
    else:
        most_common_rg, count = None, 0
    
    # Criterion: >= 3 groups share same non-empty randomization group
    if count >= 3:
        score += 25
        feedback.append(f"Randomization configured: {count} groups share group '{most_common_rg}' [+25]")
        
        # Criterion: Name is 'experimental'
        if most_common_rg.lower() == "experimental":
            score += 5
            feedback.append("Randomization group name is correct ('experimental') [+5]")
        else:
            feedback.append(f"Randomization group name '{most_common_rg}' != 'experimental' [+0]")
    else:
        feedback.append(f"Randomization incorrect: Max sharing groups is {count} (need 3) [+0]")
        
    # Criterion: >= 2 fixed groups
    if fixed_groups >= 2:
        score += 10
        feedback.append(f"Fixed groups configured: {fixed_groups} groups found [+10]")
    else:
        feedback.append(f"Insufficient fixed groups: {fixed_groups} (need 2) [+0]")
        
    # Check Questions
    q_count = int(result.get("question_count", 0))
    if q_count >= 5:
        score += 15
        feedback.append(f"Questions added: {q_count} [+15]")
    else:
        feedback.append(f"Insufficient questions: {q_count} (need 5) [+0]")
        
    # Check Settings
    # allowprev: 'N' means disabled (which is what we want)
    allowprev = result.get("allowprev", "Y") 
    if allowprev == "N":
        score += 10
        feedback.append("Backward navigation disabled [+10]")
    else:
        feedback.append("Backward navigation enabled (should be disabled) [+0]")
        
    anonymized = result.get("anonymized", "N")
    if anonymized == "Y":
        score += 10
        feedback.append("Anonymized responses enabled [+10]")
    else:
        feedback.append("Anonymized responses disabled [+0]")
        
    active = result.get("active", "N")
    if active == "Y":
        score += 5
        feedback.append("Survey is active [+5]")
    else:
        feedback.append("Survey is inactive [+0]")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }