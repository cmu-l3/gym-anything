#!/usr/bin/env python3
"""
Verifier for Construction Bid Proposal Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_construction_bid_proposal(traj, env_info, task_info):
    """
    Verify the construction bid proposal ODT file.
    
    Criteria:
    1. File exists and is substantial (> 5KB) (Gate)
    2. Proper Heading Styles used (H1 >= 6, H2 >= 8) (30 pts)
    3. Navigation Elements (TOC + Page Numbers) (30 pts)
    4. Data Presentation (Tables >= 3) (20 pts)
    5. Content Accuracy (Bid Amount, Company Name) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring variables
    score = 0
    feedback = []
    
    # --- GATE CHECK ---
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size', 0)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'Ironclad_Bid_Proposal_LSCU.odt' was not found."
        }
    
    if file_size < 5000:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"FAILED: Output file is too small ({file_size} bytes). Expected substantial content (>5KB)."
        }
        
    feedback.append(f"Gate passed: File exists ({file_size} bytes).")

    # --- CRITERION 1: Structure & Styles (30 pts) ---
    struct = result.get('structure', {})
    h1_count = struct.get('heading1_count', 0)
    h2_count = struct.get('heading2_count', 0)
    
    # Heading 1
    if h1_count >= 6:
        score += 15
        feedback.append("Headings (H1): Pass (>=6).")
    elif h1_count >= 3:
        score += 5
        feedback.append(f"Headings (H1): Partial ({h1_count}/6).")
    else:
        feedback.append(f"Headings (H1): Fail ({h1_count}/6). Did you use Styles?")

    # Heading 2
    if h2_count >= 8:
        score += 15
        feedback.append("Subheadings (H2): Pass (>=8).")
    elif h2_count >= 4:
        score += 5
        feedback.append(f"Subheadings (H2): Partial ({h2_count}/8).")
    else:
        feedback.append(f"Subheadings (H2): Fail ({h2_count}/8).")

    # --- CRITERION 2: Navigation (30 pts) ---
    # TOC (20 pts)
    if struct.get('has_toc', False):
        score += 20
        feedback.append("TOC: Pass.")
    else:
        feedback.append("TOC: Fail (Table of Contents missing).")
        
    # Page Numbers (10 pts)
    if struct.get('has_page_numbers', False):
        score += 10
        feedback.append("Page Numbers: Pass.")
    elif struct.get('has_footer', False):
        score += 5
        feedback.append("Page Numbers: Partial (Footer found but page numbers not detected).")
    else:
        feedback.append("Page Numbers: Fail (No footer/page numbers).")

    # --- CRITERION 3: Tables (20 pts) ---
    table_count = struct.get('table_count', 0)
    if table_count >= 3:
        score += 20
        feedback.append("Tables: Pass (>=3).")
    elif table_count >= 1:
        score += 10
        feedback.append(f"Tables: Partial ({table_count}/3).")
    else:
        feedback.append("Tables: Fail (No tables found).")

    # --- CRITERION 4: Content Accuracy (20 pts) ---
    content = result.get('content', {})
    content_score = 0
    
    if content.get('has_company_name', False): content_score += 5
    else: feedback.append("Content: Missing company name 'Ironclad'.")
    
    if content.get('has_client_name', False): content_score += 5
    else: feedback.append("Content: Missing client name 'Lone Star'.")
    
    if content.get('has_bid_amount', False): 
        content_score += 10
        feedback.append("Content: Correct bid amount found.")
    else: 
        feedback.append("Content: Missing or incorrect bid amount ($1,009,000).")
        
    score += content_score

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }