#!/usr/bin/env python3
"""
Verifier for Archive Finding Aid Creation task.
Verifies ODT file structure, content, and formatting styles.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_finding_aid(traj, env_info, task_info):
    """
    Verify the agent created a compliant finding aid ODT.
    
    Criteria:
    1. File creation (Gate)
    2. Document Structure (Heading 1s for sections, Heading 2s for Series)
    3. Content Organization (Tables created for inventory)
    4. Navigation (TOC and Page Numbers)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_h1 = metadata.get('expected_structure', {}).get('min_h1', 4)
    expected_h2 = metadata.get('expected_structure', {}).get('min_h2', 4)
    expected_tables = metadata.get('expected_structure', {}).get('min_tables', 4)

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/verifier_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # 1. GATE: File must exist (10 pts)
    if not result.get("file_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'Sterling_Finding_Aid.odt' was not created."
        }
    score += 10
    feedback_parts.append("File created (+10)")

    # 2. Heading Structure (Heading 1 and Heading 2) (30 pts)
    # H1 check (15 pts)
    h1_count = result.get("heading1_count", 0)
    if h1_count >= expected_h1:
        score += 15
        feedback_parts.append(f"Main sections correctly styled (H1 count: {h1_count}) (+15)")
    elif h1_count > 0:
        score += 5
        feedback_parts.append(f"Some main sections styled (H1 count: {h1_count}/{expected_h1}) (+5)")
    else:
        feedback_parts.append("Main sections missing Heading 1 style")

    # H2 check (15 pts) - This implies Series organization
    h2_count = result.get("heading2_count", 0)
    if h2_count >= expected_h2:
        score += 15
        feedback_parts.append(f"Series correctly styled (H2 count: {h2_count}) (+15)")
    elif h2_count > 0:
        score += 5
        feedback_parts.append(f"Some series styled (H2 count: {h2_count}/{expected_h2}) (+5)")
    else:
        feedback_parts.append("Series headers missing Heading 2 style")

    # 3. Inventory Tables (20 pts)
    # We expect one table per series or one big table. Metadata suggests min_tables=4.
    table_count = result.get("table_count", 0)
    if table_count >= expected_tables:
        score += 20
        feedback_parts.append(f"Inventory tables created ({table_count}) (+20)")
    elif table_count >= 1:
        score += 10
        feedback_parts.append(f"Partial tables found ({table_count}) (+10)")
    else:
        feedback_parts.append("No inventory tables found")

    # 4. Navigation Elements (25 pts)
    # TOC (15 pts)
    if result.get("has_toc"):
        score += 15
        feedback_parts.append("Table of Contents present (+15)")
    else:
        feedback_parts.append("Table of Contents missing")
    
    # Page Numbers (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback_parts.append("Page numbers detected (+10)")
    else:
        feedback_parts.append("Page numbers missing")

    # 5. Content Verification (15 pts)
    # Check if specific text exists (proving they read the JSON)
    content_check = result.get("content_check", {})
    content_score = 0
    if content_check.get("title_page"): content_score += 5
    if content_check.get("abstract"): content_score += 5
    if content_check.get("admin_records"): content_score += 5
    
    score += content_score
    if content_score == 15:
        feedback_parts.append("Content verified (+15)")
    else:
        feedback_parts.append(f"Partial content match (+{content_score})")

    # Final result
    passed = score >= 70
    feedback = "; ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }