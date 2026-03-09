#!/usr/bin/env python3
"""
Verifier for special_education_iep_create task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_special_education_iep_create(traj, env_info, task_info):
    """
    Verify the IEP document creation task.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # 1. File Exists & Basic Size (GATE) - 5 pts
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "IEP document file was not saved."
        }
    
    file_size = result.get("file_size", 0)
    if file_size < 5000:
        return {
            "passed": False,
            "score": 5,
            "feedback": "File exists but is too small (<5KB) to contain required content."
        }
    
    score += 5
    feedback.append("File created successfully (5/5)")

    # 2. Table of Contents - 15 pts
    if result.get("has_toc", False):
        score += 15
        feedback.append("Table of Contents present (15/15)")
    else:
        feedback.append("Table of Contents missing (0/15)")

    # 3. Heading 1 Usage - 20 pts
    h1_count = result.get("heading1_count", 0)
    if h1_count >= 6:
        score += 20
        feedback.append(f"Heading 1 styles applied correctly: {h1_count} sections (20/20)")
    elif h1_count >= 3:
        score += 10
        feedback.append(f"Partial Heading 1 styles found: {h1_count} (10/20)")
    else:
        feedback.append(f"Insufficient Heading 1 styles: {h1_count} found (0/20)")

    # 4. Heading 2 Usage - 15 pts
    h2_count = result.get("heading2_count", 0)
    if h2_count >= 8:
        score += 15
        feedback.append(f"Heading 2 styles applied correctly: {h2_count} subsections (15/15)")
    elif h2_count >= 4:
        score += 7
        feedback.append(f"Partial Heading 2 styles found: {h2_count} (7/15)")
    else:
        feedback.append(f"Insufficient Heading 2 styles: {h2_count} found (0/15)")

    # 5. Tables - 15 pts
    table_count = result.get("table_count", 0)
    if table_count >= 3:
        score += 15
        feedback.append(f"Required tables found: {table_count} (15/15)")
    elif table_count >= 1:
        score += 7
        feedback.append(f"Partial tables found: {table_count} (7/15)")
    else:
        feedback.append("No tables found (0/15)")

    # 6. Page Numbers - 10 pts
    if result.get("has_page_numbers", False):
        score += 10
        feedback.append("Page numbers detected (10/10)")
    else:
        feedback.append("Page numbers missing (0/10)")

    # 7. Document Length - 5 pts
    para_count = result.get("paragraph_count", 0)
    if para_count >= 25:
        score += 5
        feedback.append("Document length sufficient (5/5)")
    else:
        feedback.append(f"Document too short: {para_count} paragraphs (0/5)")

    # 8. Content Verification - 15 pts total
    content_score = 0
    if result.get("student_name_found", False):
        content_score += 5
    if result.get("iep_terms_found", False):
        content_score += 5
    if result.get("assessment_data_found", False):
        content_score += 5
    
    score += content_score
    feedback.append(f"Content verification: {content_score}/15 pts")

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }