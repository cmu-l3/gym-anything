#!/usr/bin/env python3
"""
Verifier for inventory_system_user_manual task.

Scores the agent's ODT document based on:
1. File existence and size (Gate)
2. Structural elements (Headings, Tables, TOC, Page Numbers)
3. Content completeness (Keywords, Error Codes, Length)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_system_user_manual(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 8192)

    # 1. Load result JSON
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

    # 2. Gate Check: File must exist and be of substantial size
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'StockPulse_WMS_User_Manual.odt' not found."
        }
    
    file_size = result.get("file_size", 0)
    if file_size < min_size:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAILED: Document is too small ({file_size} bytes). Expected substantial manual (>8KB)."
        }

    score = 0
    feedback_parts = []
    
    # 3. Scoring Criteria
    
    # A. Base Score for valid file creation (5 pts)
    score += 5
    feedback_parts.append("File created")

    # B. Table of Contents (15 pts)
    if result.get("has_toc"):
        score += 15
        feedback_parts.append("TOC present (+15)")
    else:
        feedback_parts.append("Missing TOC")

    # C. Heading 1 Structure (15 pts)
    # Expecting ~7 sections
    h1_count = result.get("heading1_count", 0)
    if h1_count >= 6:
        score += 15
        feedback_parts.append(f"Headings L1 good ({h1_count}) (+15)")
    elif h1_count >= 3:
        score += 7
        feedback_parts.append(f"Headings L1 partial ({h1_count}) (+7)")
    else:
        feedback_parts.append(f"Headings L1 insufficient ({h1_count})")

    # D. Heading 2 Structure (15 pts)
    # Expecting ~10 subsections
    h2_count = result.get("heading2_count", 0)
    if h2_count >= 8:
        score += 15
        feedback_parts.append(f"Headings L2 good ({h2_count}) (+15)")
    elif h2_count >= 4:
        score += 7
        feedback_parts.append(f"Headings L2 partial ({h2_count}) (+7)")
    else:
        feedback_parts.append(f"Headings L2 insufficient ({h2_count})")

    # E. Tables (15 pts)
    # Expecting tables for shortcuts, requirements, errors (min 3-4)
    table_count = result.get("table_count", 0)
    if table_count >= 3:
        score += 15
        feedback_parts.append(f"Tables good ({table_count}) (+15)")
    elif table_count >= 1:
        score += 7
        feedback_parts.append(f"Tables partial ({table_count}) (+7)")
    else:
        feedback_parts.append("No tables found")

    # F. Page Numbers / Footer (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback_parts.append("Page numbers found (+10)")
    else:
        feedback_parts.append("Missing page numbers")

    # G. Document Length (10 pts)
    # Expecting > 40 paragraphs
    para_count = result.get("paragraph_count", 0)
    if para_count >= 35:
        score += 10
        feedback_parts.append(f"Length good ({para_count} paras) (+10)")
    elif para_count >= 20:
        score += 5
        feedback_parts.append(f"Length partial ({para_count} paras) (+5)")
    else:
        feedback_parts.append(f"Too short ({para_count} paras)")

    # H. Content Keywords (10 pts)
    keywords_found = result.get("keywords_found", [])
    if len(keywords_found) >= 4:
        score += 10
        feedback_parts.append(f"Content topics covered ({len(keywords_found)}/6) (+10)")
    elif len(keywords_found) >= 2:
        score += 5
        feedback_parts.append(f"Content topics partial ({len(keywords_found)}/6) (+5)")
    else:
        feedback_parts.append("Content generic/irrelevant")

    # I. Error Codes (5 pts)
    error_codes = result.get("error_codes_found", 0)
    if error_codes >= 4:
        score += 5
        feedback_parts.append("Error codes included (+5)")
    else:
        feedback_parts.append("Error codes missing")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }