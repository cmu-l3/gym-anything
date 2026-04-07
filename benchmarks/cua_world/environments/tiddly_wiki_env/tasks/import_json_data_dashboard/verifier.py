#!/usr/bin/env python3
"""Verifier for import_json_data_dashboard task."""

import json
import tempfile
import os

def verify_import_dashboard(traj, env_info, task_info):
    """Verify that JSON dataset was imported and the dashboard tiddler contains the correct list filters."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/import_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    earthquakes_imported = result.get('earthquakes_imported', 0)
    
    # Criterion 1: Data Imported (40 pts)
    if earthquakes_imported >= 8:
        score += 40
        feedback_parts.append(f"Data successfully imported ({earthquakes_imported}/10 records)")
    elif earthquakes_imported > 0:
        score += 20
        feedback_parts.append(f"Data partially imported ({earthquakes_imported}/10 records)")
    else:
        feedback_parts.append("FAIL: Earthquake data not imported")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Dashboard Exists (10 pts)
    if result.get('dashboard_found'):
        score += 10
        feedback_parts.append("Dashboard tiddler found")
    else:
        feedback_parts.append("FAIL: Dashboard tiddler not found")
        # Can still partially pass if data was imported, but fail criteria for the rest
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Dashboard Tagged (10 pts)
    if result.get('has_dashboard_tag'):
        score += 10
        feedback_parts.append("Dashboard tagged correctly")
    else:
        feedback_parts.append("FAIL: Dashboard tag missing")

    # Criterion 4: Filter - Tag Target (10 pts)
    if result.get('has_tag_filter'):
        score += 10
        feedback_parts.append("Filter contains tag[Earthquake]")
    else:
        feedback_parts.append("FAIL: Filter missing tag[Earthquake]")

    # Criterion 5: Filter - Numerical Sort (20 pts)
    if result.get('has_sort_filter'):
        score += 20
        feedback_parts.append("Filter contains !nsort[magnitude]")
    else:
        dashboard_text = result.get('dashboard_text', '')
        if 'nsort[magnitude]' in dashboard_text:
            score += 10
            feedback_parts.append("Filter contains nsort[magnitude] (but missing descending '!')")
        elif 'sort[magnitude]' in dashboard_text:
            score += 5
            feedback_parts.append("Filter uses alphabetical sort instead of numerical sort")
        else:
            feedback_parts.append("FAIL: Filter missing !nsort[magnitude]")

    # Criterion 6: Filter - Limit (10 pts)
    if result.get('has_limit_filter'):
        score += 10
        feedback_parts.append("Filter contains limit[5]")
    else:
        feedback_parts.append("FAIL: Filter missing limit[5]")

    # Logging checks for anti-gaming verification
    if result.get('gui_save_detected'):
        feedback_parts.append("GUI interaction verified via logs")
    else:
        feedback_parts.append("Warning: GUI interaction not detected in server logs")

    # Pass condition
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }