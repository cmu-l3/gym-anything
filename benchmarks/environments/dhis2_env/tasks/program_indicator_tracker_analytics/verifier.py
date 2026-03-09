#!/usr/bin/env python3
"""
Verifier for program_indicator_tracker_analytics task.

Criteria:
1. Program Indicator 1 (Enrollment) exists (25 pts) [MANDATORY]
2. Program Indicator 1 has correct Analytics Type (ENROLLMENT) (10 pts)
3. Program Indicator 2 (Event) exists (20 pts)
4. Program Indicator 2 has correct Analytics Type (EVENT) (10 pts)
5. Both indicators associated with a program (10 pts)
6. Analytics tables regenerated (timestamp updated) (10 pts)
7. Visualization created with relevant name (15 pts)

Pass Threshold: 60 pts
Mandatory: PI 1 created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_program_indicator_tracker_analytics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        copy_from_env("/tmp/program_indicator_tracker_analytics_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    new_pis = result.get("new_program_indicators", [])
    new_viz = result.get("new_visualizations", [])
    analytics_gen = result.get("analytics_generated", False)

    # Helper to find PI by name keywords
    def find_pi(keywords, pis):
        for pi in pis:
            name = pi.get("name", "").lower()
            if all(k.lower() in name for k in keywords):
                return pi
        return None

    # Criterion 1: PI #1 (Enrollment) exists (Mandatory)
    pi1 = find_pi(["Child", "Enrollment"], new_pis)
    if not pi1:
        # Try looser matching
        pi1 = find_pi(["Enrollment"], new_pis)

    if pi1:
        score += 25
        feedback_parts.append("Enrollment indicator created (+25)")
        
        # Criterion 2: Correct Type
        if pi1.get("analyticsType") == "ENROLLMENT":
            score += 10
            feedback_parts.append("Enrollment indicator type correct (+10)")
        else:
            feedback_parts.append(f"Enrollment indicator has wrong type: {pi1.get('analyticsType')}")
            
        # Criterion 5 (Part A): Program association
        if pi1.get("program"):
            score += 5
            feedback_parts.append("Enrollment indicator linked to program (+5)")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Mandatory 'Enrollment' program indicator not found created during task."
        }

    # Criterion 3: PI #2 (Event) exists
    pi2 = find_pi(["Child", "Event"], new_pis)
    if not pi2:
        pi2 = find_pi(["Event"], new_pis)
        
    if pi2:
        score += 20
        feedback_parts.append("Event indicator created (+20)")
        
        # Criterion 4: Correct Type
        if pi2.get("analyticsType") == "EVENT":
            score += 10
            feedback_parts.append("Event indicator type correct (+10)")
        else:
            feedback_parts.append(f"Event indicator has wrong type: {pi2.get('analyticsType')}")
            
        # Criterion 5 (Part B): Program association
        if pi2.get("program"):
            score += 5
            feedback_parts.append("Event indicator linked to program (+5)")
    else:
        feedback_parts.append("Event program indicator not found")

    # Criterion 6: Analytics Generated
    if analytics_gen:
        score += 10
        feedback_parts.append("Analytics tables regenerated (+10)")
    else:
        feedback_parts.append("Analytics tables NOT regenerated (visualizations may be empty)")

    # Criterion 7: Visualization Created
    # Look for visualization with relevant keywords
    viz_found = False
    for v in new_viz:
        name = v.get("name", "").lower()
        if "child" in name or "enrollment" in name or "trend" in name:
            viz_found = True
            break
            
    if viz_found:
        score += 15
        feedback_parts.append("Visualization created (+15)")
    else:
        feedback_parts.append("No relevant visualization found")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }