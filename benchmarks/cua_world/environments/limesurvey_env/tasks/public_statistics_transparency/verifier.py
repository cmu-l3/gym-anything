#!/usr/bin/env python3
"""Verifier for public_statistics_transparency task."""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_public_statistics_transparency(traj, env_info, task_info):
    """
    Verify configuration of public statistics and privacy settings.
    
    Criteria:
    1. Global 'Public statistics' enabled (20 pts)
    2. Global 'Show graphs' enabled (10 pts)
    3. Voting questions (PROJ, SCORE) visible in stats (20 pts)
    4. PROJ question uses Pie Chart (10 pts)
    5. Demographic questions (ZIP, INC) HIDDEN (20 pts) - CRITICAL FAIL if visible
    6. Survey Active (20 pts)
    """
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/public_stats_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get("survey_found", False):
        return {"passed": False, "score": 0, "feedback": "Survey not found."}

    score = 0
    feedback = []
    
    # 1. Global Settings
    if result.get("global_stats_enabled") == "Y":
        score += 20
        feedback.append("Global stats enabled (+20)")
    else:
        feedback.append("Global stats NOT enabled")

    if result.get("global_graphs_enabled") == "Y":
        score += 10
        feedback.append("Global graphs enabled (+10)")
    else:
        feedback.append("Global graphs NOT enabled")

    # 2. Voting Questions Visibility
    qs = result.get("questions", {})
    proj_vis = str(qs.get("project_pref", {}).get("stats_visible", "0"))
    score_vis = str(qs.get("priority_score", {}).get("stats_visible", "0"))

    if proj_vis == "1" and score_vis == "1":
        score += 20
        feedback.append("Voting questions visible (+20)")
    elif proj_vis == "1" or score_vis == "1":
        score += 10
        feedback.append("Partial voting questions visible (+10)")
    else:
        feedback.append("Voting questions NOT visible")

    # 3. Graph Type for Project Preference
    # LimeSurvey graph types: 0=Bar, 1=Pie, 2=Radar, etc. (Check specific version, usually 1 is Pie)
    proj_graph = str(qs.get("project_pref", {}).get("graph_type", "0"))
    if proj_graph == "1":
        score += 10
        feedback.append("Project preference set to Pie Chart (+10)")
    else:
        feedback.append(f"Project preference graph type incorrect (Val: {proj_graph})")

    # 4. Privacy Check (CRITICAL)
    zip_vis = str(qs.get("zip_code", {}).get("stats_visible", "0"))
    inc_vis = str(qs.get("household_income", {}).get("stats_visible", "0"))
    
    privacy_violation = False
    if zip_vis == "1" or inc_vis == "1":
        privacy_violation = True
        feedback.append("PRIVACY VIOLATION: Demographic questions are visible in public stats!")
    else:
        score += 20
        feedback.append("Privacy preserved (Demographics hidden) (+20)")

    # 5. Activation
    if result.get("is_active") == "Y":
        score += 20
        feedback.append("Survey is active (+20)")
    else:
        feedback.append("Survey NOT active")

    # Final logic
    passed = (score >= 70) and (not privacy_violation)
    
    if privacy_violation:
        feedback.insert(0, "FAILED: Privacy constraint violated.")
        score = 0 # Strict penalty for privacy violation in this context

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }