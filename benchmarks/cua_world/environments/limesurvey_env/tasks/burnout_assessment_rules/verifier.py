#!/usr/bin/env python3
"""
Verifier for burnout_assessment_rules task.
Checks if the agent correctly set up the survey, assessment mode, scoring values, and rules.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_burnout_assessment(traj, env_info, task_info):
    """
    Verify the burnout assessment survey configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    score = 0
    feedback = []

    # 1. GATE: Survey Exists (Must pass to get any points)
    if not result.get("survey_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found with 'Burnout' or 'CBI' in the title."
        }
    
    score += 10 # Base points for creating the survey
    feedback.append(f"Survey created: {result.get('title')}")

    # 2. Assessment Mode Enabled (20 pts)
    assessments = str(result.get("assessments_enabled", "N")).upper()
    if assessments == "Y":
        score += 20
        feedback.append("Assessment mode enabled (+20)")
    else:
        feedback.append("Assessment mode NOT enabled (0/20)")

    # 3. Question Group (10 pts)
    if result.get("group_count", 0) > 0:
        score += 10
        feedback.append("Question group created (+10)")
    else:
        feedback.append("No question group found (0/10)")

    # 4. Array Question Structure (20 pts)
    # Needs array question with >= 6 subquestions
    subq_count = result.get("subquestion_count", 0)
    if subq_count >= 6:
        score += 20
        feedback.append(f"Array question has {subq_count} sub-questions (+20)")
    elif subq_count >= 1:
        # Partial credit if they made the question but missed items
        score += 10
        feedback.append(f"Array question incomplete ({subq_count}/6 sub-questions) (+10)")
    else:
        feedback.append("No Array question with sub-questions found (0/20)")

    # 5. Assessment Values (20 pts)
    # Expecting [0, 25, 50, 75, 100] (string or int)
    # We check if there are at least 3 distinct non-zero values used, indicating effort to score options
    values = result.get("assessment_values", [])
    # Convert to ints for comparison
    try:
        int_values = sorted(list(set([int(float(v)) for v in values if float(v) > 0])))
    except:
        int_values = []
    
    if len(int_values) >= 3:
        score += 20
        feedback.append(f"Assessment scoring values configured correctly ({len(int_values)} distinct positive values) (+20)")
    elif len(int_values) >= 1:
        score += 10
        feedback.append("Partial scoring values detected (+10)")
    else:
        feedback.append("No assessment values assigned to answer options (0/20)")

    # 6. Assessment Rules (10 pts)
    # Expecting 3 rules
    rules = result.get("rules", [])
    rule_count = result.get("rule_count", 0)
    
    # Check for distinct ranges if possible
    valid_rules = 0
    if rules:
        valid_rules = len(rules)
    
    if valid_rules >= 3:
        score += 10
        feedback.append(f"3 Assessment rules created (+10)")
    elif valid_rules >= 1:
        score += 5
        feedback.append(f"Partial assessment rules ({valid_rules}/3) (+5)")
    else:
        feedback.append("No assessment rules found (0/10)")

    # 7. Survey Active (10 pts)
    active = str(result.get("active", "N")).upper()
    if active == "Y":
        score += 10
        feedback.append("Survey is Active (+10)")
    else:
        feedback.append("Survey is NOT Active (0/10)")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }