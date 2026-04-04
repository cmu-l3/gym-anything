#!/usr/bin/env python3
"""
Verifier for c4_internet_banking_system task.
"""

import json
import sys
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_c4_banking(traj, env_info, task_info):
    """
    Verify the C4 Internet Banking System diagrams.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Timestamp (10 pts)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Draw.io file not found."}
    
    if not result.get("file_modified"):
        feedback_parts.append("File not modified after task start.")
    else:
        score += 10
        feedback_parts.append("File saved successfully.")

    # Get analysis data
    analysis = result.get("analysis", {})
    if analysis.get("error"):
        feedback_parts.append(f"Analysis error: {analysis['error']}")
    
    # 3. Check Page Count & Names (15 pts)
    page_count = analysis.get("page_count", 0)
    page_names = [n.lower() for n in analysis.get("page_names", [])]
    
    if page_count >= 2:
        score += 10
        feedback_parts.append(f"2+ Pages found ({page_count}).")
    else:
        feedback_parts.append(f"Only {page_count} page(s) found.")
        
    has_context = any("context" in n for n in page_names)
    has_container = any("container" in n for n in page_names)
    if has_context and has_container:
        score += 5
        feedback_parts.append("Page names correct.")

    # 4. Check Context Elements (15 pts)
    # Flexible matching for element names
    shape_labels = " ".join(analysis.get("shape_labels", [])).lower()
    
    context_elements = ["banking customer", "internet banking", "e-mail", "mainframe"]
    found_context = sum(1 for e in context_elements if e in shape_labels)
    
    if found_context >= 4:
        score += 15
    elif found_context >= 2:
        score += 8
    feedback_parts.append(f"Context elements found: {found_context}/4.")

    # 5. Check Container Elements (15 pts)
    container_elements = ["web application", "single-page", "mobile app", "api application", "database"]
    found_container = sum(1 for e in container_elements if e in shape_labels)
    
    if found_container >= 5:
        score += 15
    elif found_container >= 3:
        score += 8
    feedback_parts.append(f"Container elements found: {found_container}/5.")

    # 6. Check Database Shape (5 pts)
    if analysis.get("has_cylinder"):
        score += 5
        feedback_parts.append("Database cylinder shape found.")
    else:
        feedback_parts.append("Database cylinder shape missing.")

    # 7. Check Protocols/Edge Labels (15 pts)
    edge_labels = " ".join(analysis.get("edge_labels", [])).lower()
    protocols = ["https", "json", "smtp", "sql", "xml"]
    found_protocols = sum(1 for p in protocols if p in edge_labels)
    
    if found_protocols >= 4:
        score += 15
    elif found_protocols >= 2:
        score += 7
    feedback_parts.append(f"Protocols found: {found_protocols}/5.")
    
    # 8. Check Styling/Colors (10 pts)
    # Basic check for color codes in styles
    styles = " ".join(analysis.get("styles", [])).lower()
    # Looking for blue-ish or gray hex codes roughly
    has_colors = ("#08427b" in styles or "08427b" in styles or 
                  "#1168bd" in styles or "1168bd" in styles or
                  "#999999" in styles or "999999" in styles)
    
    if has_colors:
        score += 10
        feedback_parts.append("C4 colors detected.")
    
    # 9. Check PNG Export (15 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 1000:
        score += 15
        feedback_parts.append("PNG export found.")
    else:
        feedback_parts.append("PNG export missing or invalid.")

    # Final Pass Logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }