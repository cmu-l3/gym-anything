#!/usr/bin/env python3
"""
Verifier for Workplace Investigation Report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investigation_report(traj, env_info, task_info):
    """
    Verify the created investigation report based on structure and content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata requirements
    metadata = task_info.get('metadata', {})
    min_h1 = metadata.get('min_h1_count', 7)
    min_h2 = metadata.get('min_h2_count', 8)
    min_tables = metadata.get('min_table_count', 3)
    
    # Copy result file from container
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
    
    # 1. GATE: File Existence and Size (5 pts)
    # File must exist and have content (>1KB) to be scored at all
    if not result.get("file_exists") or result.get("file_size", 0) < 1024:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Output file not found or empty. No report created."
        }
    
    # Check for substantial content (>5KB implies meaningful content)
    if result.get("file_size", 0) >= 5120:
        score += 5
        feedback.append("OK: File size indicates substantial content (5/5)")
    else:
        feedback.append(f"WARN: File size small ({result.get('file_size')} bytes) (0/5)")

    # 2. Structure: Heading 1 (20 pts)
    h1_count = result.get("heading1_count", 0)
    if h1_count >= min_h1:
        score += 20
        feedback.append(f"OK: Heading 1 count {h1_count} (20/20)")
    elif h1_count >= 4:
        score += 10
        feedback.append(f"PARTIAL: Heading 1 count {h1_count} (10/20)")
    else:
        feedback.append(f"FAIL: Insufficient Heading 1 sections ({h1_count}) (0/20)")

    # 3. Structure: Heading 2 (15 pts)
    h2_count = result.get("heading2_count", 0)
    if h2_count >= min_h2:
        score += 15
        feedback.append(f"OK: Heading 2 count {h2_count} (15/15)")
    elif h2_count >= 4:
        score += 8
        feedback.append(f"PARTIAL: Heading 2 count {h2_count} (8/15)")
    else:
        feedback.append(f"FAIL: Insufficient Heading 2 sections ({h2_count}) (0/15)")

    # 4. Structure: Table of Contents (15 pts)
    if result.get("has_toc"):
        score += 15
        feedback.append("OK: Table of Contents found (15/15)")
    else:
        feedback.append("FAIL: No Table of Contents found (0/15)")

    # 5. Structure: Tables (15 pts)
    table_count = result.get("table_count", 0)
    if table_count >= min_tables:
        score += 15
        feedback.append(f"OK: {table_count} tables found (15/15)")
    elif table_count >= 1:
        score += 7
        feedback.append(f"PARTIAL: {table_count} tables found (7/15)")
    else:
        feedback.append("FAIL: No data tables found (0/15)")

    # 6. Formatting: Page Numbers (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback.append("OK: Page numbers detected (10/10)")
    else:
        feedback.append("FAIL: No page numbers found (0/10)")

    # 7. Content Volume (5 pts)
    # Check paragraph count to ensure not just a skeleton
    para_count = result.get("paragraph_count", 0)
    if para_count >= 30:
        score += 5
        feedback.append(f"OK: Content length good ({para_count} paras) (5/5)")
    else:
        feedback.append(f"FAIL: Document too short ({para_count} paras) (0/5)")

    # 8. Content Specifics (15 pts total)
    checks = result.get("content_check", {})
    content_score = 0
    
    if checks.get("case_number_found"): content_score += 5
    else: feedback.append("MISSING: Case Number")
    
    if checks.get("complainant_found"): content_score += 3
    else: feedback.append("MISSING: Complainant Name")
    
    if checks.get("respondent_found"): content_score += 3
    else: feedback.append("MISSING: Respondent Name")
    
    if checks.get("findings_found"): content_score += 4
    else: feedback.append("MISSING: Findings keyword 'Substantiated'")
    
    score += content_score
    feedback.append(f"Content Check: {content_score}/15")

    # Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }