#!/usr/bin/env python3
"""
Verifier for generate_reading_list_report task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_generate_reading_list_report(traj, env_info, task_info):
    """
    Verify that the reading list report was generated and saved correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract metrics
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    is_html = result.get('is_html', False)
    has_marker = result.get('has_report_marker', False)
    title_count = result.get('title_count', 0)
    file_size = result.get('output_size_bytes', 0)

    # Criterion 1: File Creation (30 pts)
    if output_exists:
        if file_created:
            score += 30
            feedback_parts.append("Report file created")
        else:
            score += 10
            feedback_parts.append("File exists but timestamp is old (reused?)")
    else:
        feedback_parts.append("Report file not found at expected path")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Format Validation (20 pts)
    if is_html:
        score += 20
        feedback_parts.append("Valid HTML format")
    else:
        feedback_parts.append("File is not valid HTML")

    # Criterion 3: Content Accuracy (40 pts)
    # Expecting at least 3-4 titles for full points
    if title_count >= 4:
        score += 40
        feedback_parts.append(f"Content correct ({title_count} papers found)")
    elif title_count >= 1:
        partial = int(40 * (title_count / 4))
        score += partial
        feedback_parts.append(f"Partial content match ({title_count} papers found)")
    else:
        feedback_parts.append("No expected paper titles found in report")

    # Criterion 4: Report Specifics (10 pts)
    # Distinguish between a Bibliography export and a Report
    if has_marker:
        score += 10
        feedback_parts.append("Confirmed Zotero Report format")
    else:
        feedback_parts.append("Could not confirm Report format (might be Bibliography?)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }