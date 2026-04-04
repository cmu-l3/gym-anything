#!/usr/bin/env python3
"""
Verifier for export_menu_usage_report task.

Criteria:
1. File /home/ga/Desktop/menu_usage.pdf exists.
2. File is a valid PDF (checked via MIME type).
3. File was created during the task window (anti-gaming).
4. File has non-zero size.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_menu_usage_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metrics
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    file_size = result.get("file_size_bytes", 0)
    mime_type = result.get("file_mime_type", "unknown")
    
    score = 0
    feedback_parts = []
    
    # Scoring Logic
    
    # 1. File Existence (30 pts)
    if file_exists:
        score += 30
        feedback_parts.append("File found on Desktop")
    else:
        feedback_parts.append("File 'menu_usage.pdf' NOT found on Desktop")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. File Validity (PDF format) (30 pts)
    if "pdf" in mime_type.lower():
        score += 30
        feedback_parts.append("File is a valid PDF")
    else:
        feedback_parts.append(f"File is not a PDF (detected type: {mime_type})")

    # 3. Anti-Gaming Timestamp Check (20 pts)
    if created_during_task:
        score += 20
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("File has old timestamp (pre-task?)")

    # 4. Content Check (Size) (20 pts)
    # Even an empty report with headers is usually > 1KB
    if file_size > 1000: 
        score += 20
        feedback_parts.append(f"File size looks correct ({file_size} bytes)")
    elif file_size > 0:
        score += 10
        feedback_parts.append(f"File size is very small ({file_size} bytes)")
    else:
        feedback_parts.append("File is empty (0 bytes)")

    # Final Pass Determination
    # Must have the file, it must be a PDF, and created during the task
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }