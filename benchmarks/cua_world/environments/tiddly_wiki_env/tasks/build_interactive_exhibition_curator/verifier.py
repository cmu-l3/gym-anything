#!/usr/bin/env python3
"""Verifier for build_interactive_exhibition_curator task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exhibition_curator(traj, env_info, task_info):
    """Verify the interactive dashboard and resulting data tiddler."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_artifacts = metadata.get('expected_artifacts', [])
    decoy_artifacts = metadata.get('decoy_artifacts', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/curator_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Dashboard: Available List (15 points)
    # Checks if <$list> widget is used
    if result.get('has_list_widget'):
        score += 15
        feedback_parts.append("Dashboard uses <$list> widget")
    else:
        feedback_parts.append("FAIL: No <$list> widget found in dashboard")

    # 2. Dashboard: Add Logic (20 points)
    # Checks if listops and target tiddler/field are referenced
    if result.get('has_listops_widget') and result.get('targets_exhibition') and result.get('targets_list_field'):
        score += 20
        feedback_parts.append("Dashboard correctly targets Exhibition list via <$action-listops>")
    elif result.get('has_listops_widget'):
        score += 10
        feedback_parts.append("Partial: <$action-listops> found, but may not target correct tiddler/field")
    else:
        feedback_parts.append("FAIL: No <$action-listops> logic found")

    # 3. Dashboard: Selected List (15 points)
    # Assumes the <$list> widget check partially covered this, but verify button presence
    if result.get('has_button_widget'):
        score += 15
        feedback_parts.append("Dashboard contains interactive <$button> elements")
    else:
        feedback_parts.append("FAIL: No <$button> widgets found")

    # 4. Dashboard: Item Count (10 points)
    if result.get('has_count_widget'):
        score += 10
        feedback_parts.append("Dashboard includes <$count> widget")
    else:
        feedback_parts.append("FAIL: No <$count> widget found")

    # 5. Dashboard: Remove Logic (20 points)
    if result.get('has_subtraction'):
        score += 20
        feedback_parts.append("Dashboard includes subtractive logic for removal")
    else:
        feedback_parts.append("FAIL: No subtractive filter (e.g., -[...]) found for remove button")

    # 6. Exhibition Populated (20 points)
    target_list = result.get('target_list_field', '')
    
    # Check if exact artifacts are in the list
    artifacts_found = 0
    for artifact in expected_artifacts:
        if artifact in target_list:
            artifacts_found += 1
            
    # Check if any decoys mistakenly added
    decoys_found = 0
    for decoy in decoy_artifacts:
        if decoy in target_list:
            decoys_found += 1
            
    if not result.get('target_exists'):
        feedback_parts.append("FAIL: Target tiddler 'Exhibition: Daily Life' does not exist")
    elif artifacts_found == len(expected_artifacts) and decoys_found == 0:
        score += 20
        feedback_parts.append("Target tiddler populated perfectly with correct 4 artifacts")
    elif artifacts_found > 0:
        score += int(10 * (artifacts_found / len(expected_artifacts)))
        feedback_parts.append(f"Target list contains {artifacts_found}/4 correct artifacts and {decoys_found} incorrect ones")
    else:
        feedback_parts.append("FAIL: Target list is empty or incorrect")
        
    # ANTI-GAMING CHECK
    # If the user just hardcoded the output data but didn't build the dashboard, cap score.
    dashboard_built = result.get('builder_exists') and result.get('has_listops_widget')
    if not dashboard_built and artifacts_found > 0:
        score = min(score, 20)
        feedback_parts.append("ANTI-GAMING WARNING: Output was hardcoded without building functional dashboard. Score capped.")

    # Final pass conditions
    passed = score >= 70 and artifacts_found == len(expected_artifacts) and dashboard_built

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }