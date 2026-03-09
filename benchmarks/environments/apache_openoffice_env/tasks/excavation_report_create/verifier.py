#!/usr/bin/env python3
"""
Verifier for Excavation Report Creation Task.

Checks:
1. File existence and validity (ODT format).
2. Structural elements: Heading 1, Heading 2, Tables, TOC.
3. Formatting features: Page numbers.
4. Content validation: Keywords matching JSON input.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_excavation_report(traj, env_info, task_info):
    """
    Verifies the archaeological excavation report task.
    """
    # 1. Setup copy mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve validation results: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Define Scoring Criteria
    score = 0
    feedback = []
    
    # Metadata thresholds
    meta = task_info.get('metadata', {}).get('criteria', {})
    min_h1 = meta.get('min_h1', 8)
    min_h2 = meta.get('min_h2', 10)
    min_tables = meta.get('min_tables', 3)
    min_paras = meta.get('min_body_paras', 35)

    # --- CHECK 1: File Existence & Validity (Gatekeeper) ---
    if not result.get("exists"):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if result.get("size_bytes", 0) < 5000: # 5KB min
        return {"passed": False, "score": 0, "feedback": "Report file is empty or too small (<5KB)."}
    
    score += 5
    feedback.append("File created successfully (5/5)")

    # --- CHECK 2: Structure (Headings) ---
    h1_count = result.get("h1_count", 0)
    h2_count = result.get("h2_count", 0)
    
    # Heading 1
    if h1_count >= min_h1:
        score += 20
        feedback.append(f"Heading 1 structure correct ({h1_count} sections) (20/20)")
    elif h1_count > 0:
        score += 10
        feedback.append(f"Partial Heading 1 structure ({h1_count}/{min_h1}) (10/20)")
    else:
        feedback.append("Missing Heading 1 styles (0/20)")

    # Heading 2
    if h2_count >= min_h2:
        score += 15
        feedback.append(f"Heading 2 structure correct ({h2_count} subsections) (15/15)")
    elif h2_count > 0:
        score += 7
        feedback.append(f"Partial Heading 2 structure ({h2_count}/{min_h2}) (7/15)")
    else:
        feedback.append("Missing Heading 2 styles (0/15)")

    # --- CHECK 3: Tables ---
    table_count = result.get("table_count", 0)
    if table_count >= min_tables:
        score += 15
        feedback.append(f"Tables present ({table_count}) (15/15)")
    elif table_count > 0:
        score += 5
        feedback.append(f"Insufficient tables ({table_count}/{min_tables}) (5/15)")
    else:
        feedback.append("No data tables found (0/15)")

    # --- CHECK 4: Table of Contents ---
    if result.get("toc_present"):
        score += 15
        feedback.append("Table of Contents present (15/15)")
    else:
        feedback.append("Table of Contents missing (0/15)")

    # --- CHECK 5: Formatting (Page Numbers) ---
    if result.get("page_numbers_present"):
        score += 10
        feedback.append("Page numbers detected (10/10)")
    else:
        feedback.append("Page numbers missing (0/10)")

    # --- CHECK 6: Content (Keywords & Length) ---
    body_paras = result.get("body_para_count", 0)
    keywords = result.get("keywords_found", [])
    
    content_score = 0
    if body_paras >= min_paras:
        content_score += 10
    else:
        content_score += int((body_paras / min_paras) * 10)
    
    if len(keywords) >= 3:
        content_score += 10
    else:
        feedback.append(f"Missing specific site keywords. Found: {keywords}")

    score += content_score
    feedback.append(f"Content volume and relevance ({content_score}/20)")

    # --- Final Result ---
    # Pass threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }