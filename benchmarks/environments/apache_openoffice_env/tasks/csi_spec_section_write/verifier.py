#!/usr/bin/env python3
"""
Verifier for csi_spec_section_write task.

Evaluates if the agent correctly created a construction specification document
following CSI MasterFormat structure, proper styles, and data integration.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_csi_spec_section_write(traj, env_info, task_info):
    """
    Verify the spec section document.
    
    Criteria:
    1. File exists and is valid ODT. (10 pts)
    2. CSI Structure: Contains PART 1, PART 2, PART 3. (20 pts)
    3. Styles: PART headers use Heading 1 style. (20 pts)
    4. Table: At least one table exists (for the schedule). (15 pts)
    5. Header/Footer: Detected in styles. (15 pts)
    6. Content: Includes key technical terms from JSON (ANSI, T-1, T-2). (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 093013_Ceramic_Tiling.odt not found."
        }
    
    score += 10
    feedback_parts.append("File created")
    
    # 2. CSI Structure (20 pts)
    parts_found = result.get("parts_found", [])
    parts_score = 0
    if "PART 1" in parts_found: parts_score += 7
    if "PART 2" in parts_found: parts_score += 7
    if "PART 3" in parts_found: parts_score += 6
    
    score += parts_score
    if parts_score == 20:
        feedback_parts.append("CSI Parts 1/2/3 found")
    else:
        feedback_parts.append(f"Missing CSI Parts (found {parts_found})")
        
    # 3. Heading Styles (20 pts)
    # We expect at least 3 Heading 1s (for the Parts)
    h1_count = result.get("heading1_count", 0)
    if h1_count >= 3:
        score += 20
        feedback_parts.append("Heading 1 styles used correctly")
    elif h1_count > 0:
        score += 10
        feedback_parts.append("Heading 1 styles partially used")
    else:
        feedback_parts.append("No Heading 1 styles found")
        
    # 4. Table (15 pts)
    if result.get("table_count", 0) >= 1:
        score += 15
        feedback_parts.append("Schedule table present")
    else:
        feedback_parts.append("No table found for tile schedule")
        
    # 5. Header/Footer (15 pts)
    hf_score = 0
    if result.get("has_header"): hf_score += 10
    if result.get("has_footer") or result.get("has_page_numbers"): hf_score += 5
    score += hf_score
    
    if hf_score == 15:
        feedback_parts.append("Header and Footer present")
    elif hf_score > 0:
        feedback_parts.append("Partial Header/Footer found")
    else:
        feedback_parts.append("Header/Footer missing")
        
    # 6. Content Checks (20 pts)
    content = result.get("content_check", {})
    c_score = 0
    if content.get("ansi_a118"): c_score += 5
    if content.get("tcna"): c_score += 5
    if content.get("t1_found"): c_score += 5
    if content.get("t2_found"): c_score += 5
    score += c_score
    
    if c_score == 20:
        feedback_parts.append("Technical content correct")
    else:
        feedback_parts.append(f"Missing some content (score: {c_score}/20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }