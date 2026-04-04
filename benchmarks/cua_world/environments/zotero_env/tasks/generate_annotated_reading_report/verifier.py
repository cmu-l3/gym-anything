#!/usr/bin/env python3
"""
Verifier for generate_annotated_reading_report task.

Scoring Breakdown (100 pts):
1. Collection 'AI History Seminar' exists in DB (10 pts)
2. Collection contains the 4 correct papers (20 pts)
3. Note added to 'Computing Machinery...' with correct text (20 pts)
4. Report HTML file exists and created during task (20 pts)
5. Report HTML content is valid (contains note and titles) (30 pts)

Pass Threshold: 70 pts
"""

import json
import tempfile
import os

def verify_generate_annotated_reading_report(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    db_state = result.get('db_state', {})
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    report_valid = result.get('report_content_valid', False)

    score = 0
    feedback = []

    # 3. Score Criteria
    
    # Criterion 1: Collection Creation (10 pts)
    if db_state.get('collection_exists'):
        score += 10
        feedback.append("Collection 'AI History Seminar' created.")
    else:
        feedback.append("Collection 'AI History Seminar' NOT found.")

    # Criterion 2: Collection Population (20 pts)
    # Require correct_items_present (checked in export script) AND reasonable count
    item_count = db_state.get('collection_item_count', 0)
    correct_items = db_state.get('correct_items_present', False)
    
    if correct_items and 4 <= item_count <= 6: # Allow slight margin
        score += 20
        feedback.append("Collection populated with correct papers.")
    elif item_count > 0:
        score += 5
        feedback.append(f"Collection has {item_count} items, but not exactly the targets.")
    else:
        feedback.append("Collection is empty.")

    # Criterion 3: Annotation (20 pts)
    if db_state.get('note_attached_correctly'):
        score += 20
        feedback.append("Note added to correct paper.")
    elif db_state.get('note_exists'):
        score += 10
        feedback.append("Note created but attached to wrong paper or unattached.")
    else:
        feedback.append("Required reading note NOT found.")

    # Criterion 4: Report File Existence (20 pts)
    if report_exists and report_fresh:
        score += 20
        feedback.append("Report file generated successfully.")
    elif report_exists:
        # Exists but old timestamp (unlikely given cleanup, but possible)
        score += 5
        feedback.append("Report file exists but has wrong timestamp.")
    else:
        feedback.append("Report file NOT found at /home/ga/Documents/ai_seminar_report.html.")

    # Criterion 5: Report Content (30 pts)
    # This verifies the export actually contains the data (wasn't just an empty file)
    if report_valid:
        score += 30
        feedback.append("Report content verified (contains note and paper titles).")
    else:
        feedback.append("Report content missing required data (note text or paper titles).")

    # 4. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }