#!/usr/bin/env python3
"""
Verifier for pm_schedule_create task.

Checks:
1. File exists and is substantial (>5KB)
2. Structure: Auto-generated TOC, Headings (H1/H2), Tables
3. Content: Plant name, PM terminology
4. Formatting: Page numbers in footer
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pm_schedule_create(traj, env_info, task_info):
    """Verify the PM Schedule document creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Create temp file for result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # --- Scoring Logic ---
    score = 0
    feedback_parts = []
    
    # 1. GATE: File Exists & Size (0 pts, but required for rest)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file not found. Did you save as CRWA_PM_Schedule_FY2025.odt?"
        }
        
    file_size = result.get("file_size", 0)
    if file_size < metadata.get("min_file_size_bytes", 5000):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"File too small ({file_size} bytes). Expected substantial document content."
        }

    # 2. Table of Contents (15 pts)
    if result.get("has_toc"):
        score += 15
        feedback_parts.append("TOC Found (+15)")
    else:
        feedback_parts.append("TOC Missing")

    # 3. Headings Level 1 (20 pts) - Expecting ~7-9 sections
    h1_count = result.get("heading1_count", 0)
    h1_min = metadata.get("required_h1_min", 7)
    if h1_count >= h1_min:
        score += 20
        feedback_parts.append(f"H1 Sections: {h1_count} (+20)")
    elif h1_count >= 3:
        score += 10
        feedback_parts.append(f"H1 Sections: {h1_count}/{h1_min} (+10)")
    else:
        feedback_parts.append(f"Insufficient H1 Sections ({h1_count})")

    # 4. Headings Level 2 (15 pts) - Expecting ~8+ subsections
    h2_count = result.get("heading2_count", 0)
    h2_min = metadata.get("required_h2_min", 8)
    if h2_count >= h2_min:
        score += 15
        feedback_parts.append(f"H2 Subsections: {h2_count} (+15)")
    elif h2_count >= 3:
        score += 7
        feedback_parts.append(f"H2 Subsections: {h2_count}/{h2_min} (+7)")
    else:
        feedback_parts.append(f"Insufficient H2 Subsections ({h2_count})")

    # 5. Tables (20 pts) - Equipment table + PM tables (~5 tables total)
    table_count = result.get("table_count", 0)
    tables_min = metadata.get("required_tables_min", 4)
    if table_count >= tables_min:
        score += 20
        feedback_parts.append(f"Tables: {table_count} (+20)")
    elif table_count >= 2:
        score += 10
        feedback_parts.append(f"Tables: {table_count}/{tables_min} (+10)")
    else:
        feedback_parts.append(f"Insufficient Tables ({table_count})")

    # 6. Page Numbers (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback_parts.append("Page Numbers Found (+10)")
    else:
        feedback_parts.append("Page Numbers Missing")

    # 7. Content Check (20 pts)
    content_score = 0
    checks = result.get("text_content_check", {})
    if checks.get("plant_name"): content_score += 10
    if checks.get("pm_terms"): content_score += 5
    if checks.get("equipment_mentioned"): content_score += 5
    
    score += content_score
    feedback_parts.append(f"Content Score: {content_score}/20")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }