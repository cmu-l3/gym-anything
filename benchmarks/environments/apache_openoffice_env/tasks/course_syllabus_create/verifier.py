#!/usr/bin/env python3
"""
Verifier for course_syllabus_create task.

Task: Create a 16-week course syllabus in OpenOffice Writer from JSON data.
Requirements:
1. Specific filename: ENVS410_Syllabus_Fall2024.odt
2. Proper Heading 1 (sections) and Heading 2 (subsections) styles
3. Auto-generated Table of Contents
4. 16-row weekly schedule table
5. Page numbers in footer
6. Correct course content (Instructor, Course Code, Grading breakdown)

Verification Strategy:
- Python script analyzes ODT structure (headings, tables, xml tags) via export_result.sh
- Verifier reads the exported JSON analysis
- Scores based on structural and content fidelity
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_course_syllabus_create(traj, env_info, task_info):
    """Verify the syllabus document creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse verification results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # GATE: File existence and size (5 pts)
    # 8KB is a safe minimum for a multi-page ODT with tables
    if not result.get('file_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file ENVS410_Syllabus_Fall2024.odt not found."
        }
    
    if result.get('file_size', 0) < 5000:
        feedback.append("File exists but is very small (<5KB). Likely incomplete.")
        score += 2 # minimal credit
    else:
        score += 5
        feedback.append("File created with substantial content.")

    # Structural Criteria
    
    # Heading 1 (15 pts) - Expecting ~10 sections
    h1_count = result.get('heading1_count', 0)
    if h1_count >= 8:
        score += 15
        feedback.append(f"Heading 1 styles applied correctly ({h1_count} sections).")
    elif h1_count >= 4:
        score += 7
        feedback.append(f"Partial Heading 1 styles found ({h1_count}/8).")
    else:
        feedback.append(f"Missing proper Heading 1 styles (found {h1_count}). Check if direct formatting was used instead of Styles.")

    # Heading 2 (10 pts) - Expecting ~5 subsections (policies)
    h2_count = result.get('heading2_count', 0)
    if h2_count >= 5:
        score += 10
        feedback.append(f"Heading 2 styles applied correctly ({h2_count} subsections).")
    elif h2_count >= 2:
        score += 5
        feedback.append(f"Partial Heading 2 styles found ({h2_count}/5).")
    else:
        feedback.append("Missing proper Heading 2 styles.")

    # Tables (10 pts) - Expecting Schedule + Grading
    table_count = result.get('table_count', 0)
    if table_count >= 2:
        score += 10
        feedback.append(f"Tables present ({table_count}).")
    elif table_count == 1:
        score += 5
        feedback.append("Only 1 table found (expected at least 2).")
    else:
        feedback.append("No tables found.")

    # Weekly Schedule Rows (15 pts) - The hard part
    max_rows = result.get('max_table_rows', 0)
    if max_rows >= 16:
        score += 15
        feedback.append(f"Schedule table has sufficient rows ({max_rows}).")
    elif max_rows >= 10:
        score += 8
        feedback.append(f"Schedule table incomplete ({max_rows}/16 rows).")
    else:
        feedback.append(f"Schedule table missing or very short (max rows: {max_rows}).")

    # Navigation Elements
    
    # TOC (15 pts)
    if result.get('has_toc'):
        score += 15
        feedback.append("Table of Contents found.")
    else:
        feedback.append("Table of Contents missing.")

    # Page Numbers (10 pts)
    if result.get('has_page_numbers'):
        score += 10
        feedback.append("Page numbers found.")
    else:
        feedback.append("Page numbers missing.")

    # Content Fidelity (20 pts total)
    content = result.get('content_check', {})
    content_score = 0
    
    if content.get('has_course_code') and content.get('has_domain_term'):
        content_score += 5
    if content.get('has_instructor'):
        content_score += 5
    if content.get('has_grading_pct'): # Checks if agent copied grading table data
        content_score += 5
    if content.get('has_textbook'):
        content_score += 5
        
    score += content_score
    if content_score < 20:
        feedback.append(f"Content check partial: {content_score}/20 pts.")
    else:
        feedback.append("Content check passed.")

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }