#!/usr/bin/env python3
"""
Verifier for FRS Patient Portal Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_frs_document(traj, env_info, task_info):
    """
    Verify the FRS document creation task.
    """
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Load thresholds from metadata
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_kb', 8) * 1024
    criteria = metadata.get('criteria', {})

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Validity (Gatekeeper) ---
    if not result.get('file_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'FRS-PC3-2024-012.odt' was not found."
        }
    
    if not result.get('file_created_during_task'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAILED: Anti-gaming check failed. File timestamp is older than task start."
        }
        
    file_size = result.get('file_size_bytes', 0)
    if file_size < min_size:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAILED: Document is too empty ({file_size} bytes). Expected > {min_size} bytes."
        }

    score += 5
    feedback.append("File created successfully.")

    # --- Criterion 2: Document Structure (50 pts) ---
    struct = result.get('structure', {})
    
    # TOC (15 pts)
    if struct.get('toc_found'):
        score += 15
        feedback.append("Table of Contents found.")
    else:
        feedback.append("Missing Table of Contents.")

    # Heading 1 (15 pts)
    h1_count = struct.get('h1_count', 0)
    if h1_count >= criteria.get('min_h1', 7):
        score += 15
        feedback.append(f"Heading 1 structure good ({h1_count} sections).")
    elif h1_count >= 3:
        score += 5
        feedback.append(f"Heading 1 structure partial ({h1_count} sections).")
    else:
        feedback.append("Insufficient Heading 1 sections.")

    # Heading 2 (10 pts)
    h2_count = struct.get('h2_count', 0)
    if h2_count >= criteria.get('min_h2', 10):
        score += 10
        feedback.append(f"Heading 2 structure good ({h2_count} subsections).")
    elif h2_count >= 5:
        score += 5
        feedback.append("Heading 2 structure partial.")
    else:
        feedback.append("Insufficient Heading 2 subsections.")

    # Page Numbers (10 pts)
    if struct.get('page_numbers_found'):
        score += 10
        feedback.append("Page numbers found.")
    else:
        feedback.append("Missing page numbers.")

    # --- Criterion 3: Content & Tables (45 pts) ---
    
    # Tables (15 pts)
    table_count = struct.get('table_count', 0)
    if table_count >= criteria.get('min_tables', 4):
        score += 15
        feedback.append(f"Requirement tables found ({table_count}).")
    elif table_count >= 1:
        score += 5
        feedback.append("Some tables found, but fewer than expected.")
    else:
        feedback.append("No tables found. Requirements should be in tables.")

    # Module Coverage (10 pts)
    content = result.get('content', {})
    found_modules = content.get('module_ids_found', [])
    if len(found_modules) >= 3:
        score += 10
        feedback.append(f"Modules covered: {len(found_modules)}/5.")
    else:
        feedback.append(f"Insufficient module coverage ({len(found_modules)}/5).")

    # Keywords / Terminology (10 pts)
    found_keywords = content.get('keywords_found', [])
    if len(found_keywords) >= 3:
        score += 10
        feedback.append("Correct technical terminology used.")
    else:
        feedback.append("Missing expected domain keywords.")

    # Content Volume (10 pts)
    para_count = struct.get('paragraph_count', 0)
    if para_count >= criteria.get('min_paragraphs', 40):
        score += 10
        feedback.append("Document length is sufficient.")
    else:
        feedback.append("Document appears too short.")

    # --- Final Score Calculation ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }