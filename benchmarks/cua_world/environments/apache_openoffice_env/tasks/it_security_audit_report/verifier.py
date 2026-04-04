#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_security_report(traj, env_info, task_info):
    """
    Verifies the IT Security Audit Report task.
    
    Scoring Breakdown (100 pts):
    - File Exists & Created During Task: 10 pts
    - Content (All 5 Vulns present): 20 pts
    - Structure (TOC + Table + Headers): 20 pts
    - Executive Summary & Findings Sections: 10 pts
    - Color Coding (Critical=Red, High=Orange, etc.): 25 pts
    - Formatting (Page Num, Header): 15 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Result JSON
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

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get("output_exists") and result.get("file_created_during_task") and result.get("file_size", 0) > 2000:
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task."}

    analysis = result.get("odt_analysis", {})
    
    # 2. Content Integrity (20 pts)
    vulns_found = len(analysis.get("vulns_found", []))
    if vulns_found == 5:
        score += 20
        feedback.append("All 5 vulnerabilities found.")
    else:
        score += (vulns_found * 4)
        feedback.append(f"Found {vulns_found}/5 vulnerabilities.")

    # 3. Structure: Tables & TOC (20 pts)
    if analysis.get("has_table"):
        score += 10
        feedback.append("Summary table present.")
    else:
        feedback.append("Summary table missing.")
        
    if analysis.get("has_toc"):
        score += 10
        feedback.append("Table of Contents present.")
    else:
        feedback.append("Table of Contents missing.")

    # 4. Headings (10 pts)
    # Expect at least 6 headings (Exec Summary + Vuln Summary + 5 Findings)
    headings = analysis.get("headings_count", 0)
    if headings >= 6:
        score += 10
        feedback.append(f"Structure looks good ({headings} headings).")
    elif headings > 0:
        score += 5
        feedback.append(f"Structure incomplete ({headings} headings).")

    # 5. Formatting: Header & Page Numbers (15 pts)
    if analysis.get("header_found"):
        score += 10
        feedback.append("Confidential header found.")
    else:
        feedback.append("Confidential header missing.")
        
    if analysis.get("page_numbers_found"):
        score += 5
        feedback.append("Page numbers found.")

    # 6. Color Coding (25 pts)
    colors = analysis.get("color_coding", {})
    color_score = 0
    if colors.get("Critical"): color_score += 7
    if colors.get("High"): color_score += 6
    if colors.get("Medium"): color_score += 6
    if colors.get("Low"): color_score += 6
    
    score += color_score
    if color_score == 25:
        feedback.append("Perfect severity color coding.")
    elif color_score > 0:
        feedback.append(f"Partial color coding ({color_score}/25 pts).")
    else:
        feedback.append("No severity color coding detected.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }