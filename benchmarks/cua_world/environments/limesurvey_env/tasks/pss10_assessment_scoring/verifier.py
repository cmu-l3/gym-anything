#!/usr/bin/env python3
"""
Verifier for PSS-10 Assessment Scoring Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pss10_assessment_scoring(traj, env_info, task_info):
    """
    Verify PSS-10 configuration.
    Criteria:
    1. Assessments Enabled (20 pts)
    2. Survey Activated (10 pts)
    3. Reverse items (PSS04, PSS05, PSS07, PSS08) corrected (30 pts)
    4. Assessment Rules created (Low/Mod/High) (40 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 1. Assessments Enabled
    if result.get("assessments_enabled") == "Y":
        score += 20
        feedback.append("Assessments mode enabled (+20)")
    else:
        feedback.append("Assessments mode NOT enabled (0/20)")

    # 2. Survey Activated
    if result.get("is_active") == "Y":
        score += 10
        feedback.append("Survey is active (+10)")
    else:
        feedback.append("Survey is NOT active (0/10)")

    # 3. Check Reverse Items
    # Expect Code 0 -> Val 4, Code 1 -> Val 3, ... Code 4 -> Val 0
    reverse_items = result.get("reverse_items", [])
    correct_reverse = 0
    total_checks = 0
    
    # Group by question
    questions = {}
    for item in reverse_items:
        q = item["title"]
        if q not in questions: questions[q] = []
        questions[q].append(item)

    for q_title in ["PSS04", "PSS05", "PSS07", "PSS08"]:
        q_items = questions.get(q_title, [])
        if not q_items:
            feedback.append(f"{q_title} not found in database")
            continue
            
        q_correct = True
        for item in q_items:
            code = int(item["code"])
            val = int(item["value"])
            expected_val = 4 - code  # 0->4, 4->0
            if val != expected_val:
                q_correct = False
                break
        
        if q_correct:
            correct_reverse += 1
            feedback.append(f"{q_title} scoring correct")
        else:
            feedback.append(f"{q_title} scoring INCORRECT")

    # 7.5 points per correct question = 30 points total
    score += (correct_reverse * 7.5)
    
    # 4. Check Rules
    rules = result.get("rules", [])
    rule_score = 0
    
    has_low = False
    has_mod = False
    has_high = False
    
    for r in rules:
        try:
            rmin = int(r["min"])
            rmax = int(r["max"])
            msg = r["message"].lower()
            
            # Rule 1: 0-13 "low"
            if rmin == 0 and rmax == 13 and "low" in msg:
                has_low = True
            # Rule 2: 14-26 "moderate"
            elif rmin == 14 and rmax == 26 and "moderate" in msg:
                has_mod = True
            # Rule 3: 27-40 "high"
            elif rmin == 27 and rmax == 40 and "high" in msg:
                has_high = True
        except:
            continue
            
    if has_low: 
        rule_score += 13.3
        feedback.append("Low stress rule correct")
    if has_mod: 
        rule_score += 13.3
        feedback.append("Moderate stress rule correct")
    if has_high: 
        rule_score += 13.4
        feedback.append("High stress rule correct")
        
    score += rule_score
    if not rules:
        feedback.append("No assessment rules found")

    # Final check
    passed = (score >= 70) and (result.get("assessments_enabled") == "Y")
    
    return {
        "passed": passed,
        "score": round(score),
        "feedback": " | ".join(feedback)
    }