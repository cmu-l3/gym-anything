#!/usr/bin/env python3
"""
Verifier for gitflow_workflow_diagram task.

Scoring (100 points total):
- File saved & valid: 10 pts
- Swimlane structure used: 20 pts
- Correct lane labeling (Main, Develop, Feature, etc.): 15 pts
- Commits placed in Feature lane: 15 pts
- Commits placed in Release lane: 15 pts
- Commits placed in Hotfix lane: 15 pts
- PNG exported: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os

def verify_gitflow_diagram(traj, env_info, task_info):
    """Verify Gitflow diagram structure and content."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    analysis = result.get('analysis', {})

    # Criterion 1: File Saved (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback.append("Draw.io file saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback.append("File exists but not modified after start")
    else:
        feedback.append("FAIL: No diagram file saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Swimlane Structure (20 pts)
    if analysis.get('swimlane_structure_found'):
        score += 20
        feedback.append("Swimlane/Pool structure detected")
    else:
        feedback.append("FAIL: No Swimlane or Pool structure found")

    # Criterion 3: Correct Lanes (15 pts)
    # Lanes found in XML are normalized to lowercase in export_result.sh if I did it right? 
    # Actually the python script lowercases them.
    found_lanes = [l.lower() for l in analysis.get('lanes_found', [])]
    required_lanes = ["main", "develop", "feature", "release", "hotfix"]
    
    # Check for presence of key keywords
    lanes_matched = 0
    for req in required_lanes:
        if any(req in l for l in found_lanes):
            lanes_matched += 1
    
    if lanes_matched >= 5:
        score += 15
        feedback.append("All 5 required lanes found")
    elif lanes_matched >= 3:
        score += 10
        feedback.append(f"Partial lanes found ({lanes_matched}/5)")
    else:
        feedback.append(f"Missing required lanes (found {lanes_matched}/5)")

    # Criterion 4: Feature Branch Logic (15 pts)
    # Check if there are nodes technically contained in a 'Feature' lane
    nodes_feature = analysis.get('nodes_in_feature', 0)
    if nodes_feature >= 1:
        score += 15
        feedback.append(f"Feature branch populated ({nodes_feature} nodes)")
    else:
        feedback.append("Feature lane is empty")

    # Criterion 5: Release Branch Logic (15 pts)
    nodes_release = analysis.get('nodes_in_release', 0)
    if nodes_release >= 1:
        score += 15
        feedback.append(f"Release branch populated ({nodes_release} nodes)")
    else:
        feedback.append("Release lane is empty")

    # Criterion 6: Hotfix Branch Logic (15 pts)
    nodes_hotfix = analysis.get('nodes_in_hotfix', 0)
    if nodes_hotfix >= 1:
        score += 15
        feedback.append(f"Hotfix branch populated ({nodes_hotfix} nodes)")
    else:
        feedback.append("Hotfix lane is empty")

    # Criterion 7: PNG Export (10 pts)
    if result.get('png_exists'):
        score += 10
        feedback.append("PNG export found")
    else:
        feedback.append("PNG export missing")

    # Bonus: Tags check (internal metric, no extra points but good for feedback)
    tags = analysis.get('tags_found', [])
    if tags:
        feedback.append(f"Tags found: {', '.join(tags)}")

    passed = score >= 60 and analysis.get('swimlane_structure_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }