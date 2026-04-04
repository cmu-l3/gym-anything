#!/usr/bin/env python3
"""Verifier for survey_group_organization task."""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_survey_group_organization(traj, env_info, task_info):
    """
    Verify that survey groups were created correctly, sorted, and the survey 
    was assigned to the correct group with specific settings.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/group_org_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    groups = result.get("groups", [])
    survey = result.get("survey", {})
    
    # 1. Verify Groups (45 points total)
    # Expect 3 specific groups
    tech_group = next((g for g in groups if "Tech Summit" in g.get("title", "")), None)
    health_group = next((g for g in groups if "Healthcare Innovation" in g.get("title", "")), None)
    women_group = next((g for g in groups if "Women in Leadership" in g.get("title", "")), None)

    # Check existence (15 pts)
    if tech_group: score += 5
    else: feedback.append("Missing group: Annual Tech Summit 2024")
    
    if health_group: score += 5
    else: feedback.append("Missing group: Global Healthcare Innovation Forum 2024")
    
    if women_group: score += 5
    else: feedback.append("Missing group: Women in Leadership Conference 2024")

    # Check Sort Order (15 pts)
    # Tech=2, Health=1, Women=3
    if tech_group and int(tech_group.get("sortorder", 0)) == 2: score += 5
    elif tech_group: feedback.append(f"Tech Summit sort order incorrect (expected 2, got {tech_group.get('sortorder')})")

    if health_group and int(health_group.get("sortorder", 0)) == 1: score += 5
    elif health_group: feedback.append(f"Healthcare sort order incorrect (expected 1, got {health_group.get('sortorder')})")

    if women_group and int(women_group.get("sortorder", 0)) == 3: score += 5
    elif women_group: feedback.append(f"Women in Leadership sort order incorrect (expected 3, got {women_group.get('sortorder')})")

    # Check Descriptions (15 pts - lenient check)
    if tech_group and "Austin" in tech_group.get("description", ""): score += 5
    elif tech_group: feedback.append("Tech Summit description missing location/details")

    if health_group and "Boston" in health_group.get("description", ""): score += 5
    elif health_group: feedback.append("Healthcare description missing location/details")

    if women_group and "Chicago" in women_group.get("description", ""): score += 5
    elif women_group: feedback.append("Women in Leadership description missing location/details")


    # 2. Verify Survey (55 points total)
    if not survey.get("found"):
        feedback.append("Target survey 'Post-Event Satisfaction Survey - Tech Summit 2024' not found")
    else:
        score += 10 # Survey created
        
        # Check Group Assignment (15 pts)
        survey_gsid = str(survey.get("gsid", ""))
        tech_gsid = str(tech_group.get("gsid", "")) if tech_group else "nonexistent"
        
        if survey_gsid == tech_gsid and tech_gsid != "nonexistent":
            score += 15
        else:
            feedback.append("Survey not assigned to 'Annual Tech Summit 2024' group")

        # Check Anonymized (10 pts)
        if survey.get("anonymized") == "Y":
            score += 10
        else:
            feedback.append("Survey is not set to Anonymized")

        # Check Question (10 pts)
        if survey.get("question_found"):
            score += 10
        else:
            feedback.append("Question Q01 (List Radio) not found in survey")

        # Check Answer Options (10 pts)
        ans_count = int(survey.get("answer_option_count", 0))
        if ans_count >= 5:
            score += 10
        else:
            feedback.append(f"Incorrect answer options count: {ans_count} (expected 5)")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": "; ".join(feedback)
    }