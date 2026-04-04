#!/usr/bin/env python3
"""
Verifier for genealogy_manuscript_index task.
Verifies that the user created an index, marked terms, and formatted the document correctly.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_genealogy_index(traj, env_info, task_info):
    """
    Verify the genealogy manuscript indexing task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_marks = metadata.get('min_index_marks', 8)
    
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
    
    # 1. File Exists (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("Output file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Heading Style (10 pts)
    if result.get("heading_style_applied"):
        score += 10
        feedback.append("Heading 1 style applied to title.")
    else:
        feedback.append("Heading 1 style missing from title.")

    # 3. Page Numbers (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback.append("Page numbers detected.")
    else:
        feedback.append("Page numbers missing.")

    # 4. Index Section Exists (25 pts)
    if result.get("index_section_exists"):
        score += 25
        feedback.append("Alphabetical Index section generated.")
    else:
        feedback.append("Alphabetical Index section missing (did you Insert > Indexes?).")

    # 5. Index Marks Count (25 pts)
    # Check if enough terms were marked
    marked_list = result.get("marked_terms_found", [])
    count_marked = sum(1 for item in marked_list if item["marked"])
    
    if count_marked >= min_marks:
        score += 25
        feedback.append(f"Sufficient terms marked ({count_marked}/{len(marked_list)}).")
    elif count_marked > 0:
        partial = int(25 * (count_marked / min_marks))
        score += partial
        feedback.append(f"Partial terms marked ({count_marked}/{min_marks}).")
    else:
        feedback.append("No index entry marks found in the text.")

    # 6. Index Content Verification (20 pts)
    # Check if the generated index actually contains the terms
    content_list = result.get("index_content_verification", [])
    count_in_index = sum(1 for item in content_list if item["in_generated_index"])
    
    # We expect roughly the same number as marked, but let's use a threshold
    if count_in_index >= min_marks:
        score += 20
        feedback.append("Generated index contains expected terms.")
    elif count_in_index > 0:
        partial = int(20 * (count_in_index / min_marks))
        score += partial
        feedback.append("Generated index contains some terms, but not all.")
    else:
        if result.get("index_section_exists"):
            feedback.append("Index exists but appears empty (did you update it?).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }