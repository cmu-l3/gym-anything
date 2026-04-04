#!/usr/bin/env python3
"""
Verifier for trade_fair_travel_briefing task.
Checks the JSON result exported from the container.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trade_fair_briefing(traj, env_info, task_info):
    """
    Verify the travel briefing document.
    
    Scoring Criteria (100 pts total):
    1. File Existence & Validity (5 pts)
    2. Document Structure (55 pts):
       - Table of Contents (15 pts)
       - Heading 1 Usage (15 pts)
       - Heading 2 Usage (10 pts)
       - Tables (15 pts)
    3. Content Accuracy (30 pts):
       - Delegate names (10 pts)
       - Travel details (10 pts)
       - Meeting partners (5 pts)
       - Page numbers (5 pts)
    4. Substantial Content (10 pts):
       - File size/paragraph count
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata
    metadata = task_info.get('metadata', {})
    min_h1 = metadata.get('min_h1_count', 6)
    min_h2 = metadata.get('min_h2_count', 8)
    min_tables = metadata.get('min_table_count', 4)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve validation results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Gate Check: File Exists (5 pts)
    if not result.get("file_exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAILED: Output file 'Sterling_Hannover_Messe_Briefing_2025.odt' was not created."
        }
    score += 5
    feedback.append("File created successfully (5/5)")
    
    # 2. Document Structure (55 pts)
    struct = result.get("structure", {})
    
    # TOC (15 pts)
    if struct.get("toc_present"):
        score += 15
        feedback.append("Table of Contents found (15/15)")
    else:
        feedback.append("Missing Table of Contents (0/15)")

    # Headings 1 (15 pts)
    h1_count = struct.get("h1_count", 0)
    if h1_count >= min_h1:
        score += 15
        feedback.append(f"Heading 1 structure good: {h1_count} sections (15/15)")
    elif h1_count >= 1:
        score += 5
        feedback.append(f"Partial Heading 1 structure: {h1_count}/{min_h1} sections (5/15)")
    else:
        feedback.append("Missing Heading 1 styles (0/15)")

    # Headings 2 (10 pts)
    h2_count = struct.get("h2_count", 0)
    if h2_count >= min_h2:
        score += 10
        feedback.append(f"Heading 2 structure good: {h2_count} subsections (10/10)")
    elif h2_count >= 1:
        score += 5
        feedback.append(f"Partial Heading 2 structure: {h2_count}/{min_h2} subsections (5/10)")
    else:
        feedback.append("Missing Heading 2 styles (0/10)")

    # Tables (15 pts)
    table_count = struct.get("table_count", 0)
    if table_count >= min_tables:
        score += 15
        feedback.append(f"Tables present: {table_count} tables (15/15)")
    elif table_count >= 2:
        score += 7
        feedback.append(f"Partial tables: {table_count}/{min_tables} tables (7/15)")
    else:
        feedback.append("Insufficient tables (0/15)")

    # 3. Content Accuracy (30 pts)
    content = result.get("content", {})
    
    # Delegates (10 pts)
    delegates_found = len(content.get("delegates_found", []))
    if delegates_found == 4:
        score += 10
        feedback.append("All delegation members found (10/10)")
    elif delegates_found >= 1:
        score += 5
        feedback.append(f"Some delegation members found: {delegates_found}/4 (5/10)")
    else:
        feedback.append("Delegation roster missing (0/10)")
        
    # Travel Details (10 pts)
    if content.get("flight_found") and content.get("hotel_found"):
        score += 10
        feedback.append("Flight and Hotel details found (10/10)")
    elif content.get("flight_found") or content.get("hotel_found"):
        score += 5
        feedback.append("Partial travel details found (5/10)")
    else:
        feedback.append("Travel details missing (0/10)")

    # Meeting Partners (5 pts)
    if len(content.get("partners_found", [])) >= 1:
        score += 5
        feedback.append("Meeting partners mentioned (5/5)")
    else:
        feedback.append("No meeting partners mentioned (0/5)")

    # Page Numbers (5 pts) - moved here from structure
    if struct.get("page_numbers_present"):
        score += 5
        feedback.append("Page numbers present (5/5)")
    else:
        feedback.append("Page numbers missing (0/5)")

    # 4. Substantial Content (10 pts)
    file_size = result.get("file_size", 0)
    para_count = struct.get("paragraph_count", 0)
    
    if file_size > 8000 and para_count > 20:
        score += 10
        feedback.append(f"Document has substantial content: {para_count} paras (10/10)")
    else:
        feedback.append("Document content too sparse (0/10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }