#!/usr/bin/env python3
"""
Verifier for SRS Appointment Module task.
Verifies the creation of an IEEE 830 compliant SRS document in OpenOffice Writer.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_srs_creation(traj, env_info, task_info):
    """
    Verify the SRS document properties: structure, content, and formatting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata expectations
    meta = task_info.get('metadata', {})
    min_h1 = meta.get('min_h1', 7)
    min_h2 = meta.get('min_h2', 10)
    min_h3 = meta.get('min_h3', 4)
    min_tables = meta.get('min_tables', 4)
    min_rows = meta.get('min_table_rows', 20)

    # Retrieve result JSON
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

    # Scoring Logic
    score = 0
    feedback = []

    # 1. File Existence & Validity (5 pts)
    if result.get("file_exists") and result.get("file_size", 0) > 5000:
        score += 5
        feedback.append("File created and has substantial size.")
    else:
        return {"passed": False, "score": 0, "feedback": "SRS document not found or empty."}

    # 2. Table of Contents (12 pts)
    if result.get("has_toc"):
        score += 12
        feedback.append("Table of Contents found.")
    else:
        feedback.append("Missing Table of Contents.")

    # 3. Headings Structure (30 pts total)
    h1 = result.get("h1_count", 0)
    h2 = result.get("h2_count", 0)
    h3 = result.get("h3_count", 0)

    if h1 >= min_h1: score += 12
    else: score += int((h1/min_h1) * 12)
    feedback.append(f"H1 Sections: {h1}/{min_h1}")

    if h2 >= min_h2: score += 10
    else: score += int((h2/min_h2) * 10)
    feedback.append(f"H2 Subsections: {h2}/{min_h2}")

    if h3 >= min_h3: score += 8
    else: score += int((h3/min_h3) * 8)
    feedback.append(f"H3 Groups: {h3}/{min_h3}")

    # 4. Tables (23 pts total)
    tables = result.get("table_count", 0)
    rows = result.get("table_rows_total", 0)

    if tables >= min_tables: score += 15
    else: score += int((tables/min_tables) * 15)
    feedback.append(f"Tables: {tables}/{min_tables}")

    if rows >= min_rows: score += 8
    else: score += int((rows/min_rows) * 8)
    feedback.append(f"Total Table Rows: {rows}/{min_rows}")

    # 5. Page Numbers (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback.append("Page numbers detected.")
    else:
        feedback.append("Missing page numbers.")

    # 6. Body Content (5 pts)
    paras = result.get("paragraph_count", 0)
    if paras >= 40: score += 5
    else: score += int((paras/40) * 5)
    
    # 7. Content Accuracy (15 pts total)
    content = result.get("content_check", {})
    
    # Req IDs (5 pts)
    reqs = len(content.get("req_ids", []))
    if reqs >= 5: score += 5
    else: score += reqs  # 1 pt per req up to 5
    
    # Use Cases / Interfaces (5 pts)
    uc_if_count = len(content.get("use_cases", [])) + len(content.get("interfaces", []))
    if uc_if_count >= 3: score += 5
    else: score += int((uc_if_count/3) * 5)

    # Keywords (5 pts)
    kws = len(content.get("keywords", []))
    if kws >= 3: score += 5
    else: score += int((kws/3) * 5)

    feedback.append(f"Content Check: Reqs={reqs}, UC/IF={uc_if_count}, Keywords={kws}")

    # Final Check
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }