#!/usr/bin/env python3
"""
Verifier for freight_shipping_docs task.

Goal: Verify that the agent created a compliant Bill of Lading ODT document
based on the provided JSON data.

Criteria:
1. File exists and is substantial (>= 5KB).
2. Table of Contents exists.
3. Proper Heading Styles used (Heading 1 & 2).
4. Multiple tables created (Manifest, Schedule, Hazmat).
5. Footer with page numbers.
6. Content accuracy (BOL#, NMFC codes, UN numbers, Cities).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_freight_shipping_docs(traj, env_info, task_info):
    """Verify the freight shipping document creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Create temp file for result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    # --- Verification Logic ---
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Size (Gate)
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file GLI_BOL_2024_03847.odt not found."
        }
    
    file_size = result.get("file_size", 0)
    if file_size < 5000:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"File too small ({file_size} bytes). Expected substantial document content."
        }
    
    score += 5
    feedback_parts.append(f"File exists ({file_size} bytes) (+5)")

    # 2. Table of Contents (15 pts)
    if result.get("has_toc", False):
        score += 15
        feedback_parts.append("Table of Contents found (+15)")
    else:
        feedback_parts.append("Table of Contents missing")

    # 3. Headings (Heading 1: 15 pts, Heading 2: 10 pts)
    h1_count = result.get("heading1_count", 0)
    h2_count = result.get("heading2_count", 0)
    
    # H1 check
    if h1_count >= 6:
        score += 15
        feedback_parts.append(f"Heading 1 styles okay ({h1_count}) (+15)")
    elif h1_count >= 3:
        score += 7
        feedback_parts.append(f"Partial Heading 1 styles ({h1_count}) (+7)")
    else:
        feedback_parts.append(f"Insufficient Heading 1 styles ({h1_count})")

    # H2 check
    if h2_count >= 6:
        score += 10
        feedback_parts.append(f"Heading 2 styles okay ({h2_count}) (+10)")
    elif h2_count >= 3:
        score += 5
        feedback_parts.append(f"Partial Heading 2 styles ({h2_count}) (+5)")
    else:
        feedback_parts.append(f"Insufficient Heading 2 styles ({h2_count})")

    # 4. Tables (15 pts)
    table_count = result.get("table_count", 0)
    if table_count >= 3:
        score += 15
        feedback_parts.append(f"Tables present ({table_count}) (+15)")
    elif table_count >= 1:
        score += 7
        feedback_parts.append(f"Partial tables ({table_count}) (+7)")
    else:
        feedback_parts.append("No tables found (Manifest/Schedule/Hazmat missing)")

    # 5. Page Numbers / Footer (10 pts)
    if result.get("has_page_numbers", False):
        score += 10
        feedback_parts.append("Page numbers found (+10)")
    else:
        feedback_parts.append("Page numbers missing")

    # 6. Content Checks (30 pts)
    found_content = result.get("text_content_found", [])
    content_score = 0
    
    # 6a. BOL Number (5 pts)
    if "bol_number" in found_content:
        content_score += 5
    
    # 6b. Carrier Name (5 pts)
    if "carrier" in found_content:
        content_score += 5

    # 6c. NMFC Codes (5 pts for >= 1 found)
    if "nmfc_1" in found_content or "nmfc_2" in found_content:
        content_score += 5

    # 6d. Hazmat UN Numbers (10 pts for >= 2 found, 5 for 1)
    hazmat_found = sum(1 for k in found_content if k.startswith("hazmat_"))
    if hazmat_found >= 2:
        content_score += 10
    elif hazmat_found == 1:
        content_score += 5
        
    # 6e. Cities (5 pts for >= 2 found)
    cities_found = sum(1 for k in found_content if k.startswith("city_"))
    if cities_found >= 2:
        content_score += 5
        
    score += content_score
    feedback_parts.append(f"Content check score: {content_score}/30")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }