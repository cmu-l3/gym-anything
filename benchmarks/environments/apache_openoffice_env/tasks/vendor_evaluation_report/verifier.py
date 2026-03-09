#!/usr/bin/env python3
"""
Verifier for Vendor Evaluation Report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vendor_evaluation_report(traj, env_info, task_info):
    """
    Verify the Vendor Evaluation Report creation task.
    
    Criteria:
    1. File exists and is substantial (>5KB)
    2. Document Structure (Headings, TOC, Footer, Tables)
    3. Content Accuracy (Vendor names, Quote figures)
    """
    # 1. Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get metadata expectations
    metadata = task_info.get('metadata', {})
    expected_vendors = metadata.get('required_vendors', [])
    min_file_size = metadata.get('min_file_size_bytes', 5000)

    # 3. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # --- Gate: File Existence & Size (Must pass to get any points) ---
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if result.get('file_size', 0) < min_file_size:
        return {"passed": False, "score": 0, "feedback": f"File too small ({result.get('file_size')} bytes). Expected > {min_file_size} bytes."}
    
    score += 5 # Base points for valid file
    feedback.append("File created successfully.")

    # --- Structure Scoring (Total 55 points) ---
    
    # Table of Contents (15 pts)
    if result.get('has_toc'):
        score += 15
        feedback.append("Table of Contents present.")
    else:
        feedback.append("Missing Table of Contents.")

    # Heading 1 (15 pts)
    h1_count = result.get('heading1_count', 0)
    if h1_count >= 6:
        score += 15
        feedback.append(f"Structure: {h1_count} main sections (Heading 1).")
    elif h1_count > 0:
        score += 5
        feedback.append(f"Structure: Only {h1_count} main sections (Heading 1). Expected >= 6.")
    else:
        feedback.append("Structure: No Heading 1 styles used.")

    # Heading 2 (10 pts)
    h2_count = result.get('heading2_count', 0)
    if h2_count >= 8:
        score += 10
        feedback.append(f"Structure: {h2_count} subsections (Heading 2).")
    elif h2_count > 0:
        score += 5
        feedback.append(f"Structure: Only {h2_count} subsections. Expected >= 8.")

    # Tables (20 pts)
    table_count = result.get('table_count', 0)
    if table_count >= 4:
        score += 20
        feedback.append(f"Tables: {table_count} tables found.")
    elif table_count >= 1:
        score += 10
        feedback.append(f"Tables: Only {table_count} tables found. Expected >= 4.")
    else:
        feedback.append("Tables: No tables found.")

    # Footer/Page Numbers (10 pts)
    if result.get('has_footer_pagenum'):
        score += 10
        feedback.append("Footer/Page numbers detected.")
    else:
        feedback.append("Missing Page Numbers in footer.")
        
    # Paragraph Volume (5 pts)
    if result.get('paragraph_count', 0) >= 30:
        score += 5
        feedback.append("Document length is sufficient.")

    # --- Content Scoring (Total 20 points) ---
    
    # Vendors Found (10 pts)
    vendors_found = len(result.get('vendors_found', []))
    if vendors_found == 4:
        score += 10
        feedback.append("All 4 vendors mentioned.")
    elif vendors_found > 0:
        score += 5
        feedback.append(f"Only {vendors_found}/4 vendors mentioned.")
    else:
        feedback.append("No vendor names found in text.")

    # Quotes/Prices Found (5 pts)
    quotes_found = len(result.get('quotes_found', []))
    if quotes_found >= 3:
        score += 5
        feedback.append("Specific pricing figures found.")
    else:
        feedback.append("Pricing figures missing or incorrect.")

    # Key Terms (5 pts)
    terms_found = len(result.get('key_terms_found', []))
    if terms_found >= 3:
        score += 5
        feedback.append("Procurement terminology used.")

    # --- Pass Threshold ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }