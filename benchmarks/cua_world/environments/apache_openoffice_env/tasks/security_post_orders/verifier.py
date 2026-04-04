#!/usr/bin/env python3
"""
Verifier for Security Post Orders task.
Verifies the creation of a professional ODT document with specific structural requirements.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_security_post_orders(traj, env_info, task_info):
    """
    Verify the Security Post Orders document creation.
    
    Criteria:
    1. File exists and is substantial (>8KB)
    2. File created/modified during task (Anti-gaming)
    3. Proper structure:
       - Table of Contents
       - Heading 1 sections (>= 6)
       - Heading 2 subsections (>= 10)
    4. Content elements:
       - Tables (>= 5)
       - Footer with page numbers
    5. Text content validation (Company names, Keywords)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Gate: File Existence & Size (Must exist and be > 1KB to score anything)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Critical: Output file SPO-HBC-2024-003.odt not found."}
    
    file_size = result.get("file_size", 0)
    if file_size < 1000:
        return {"passed": False, "score": 0, "feedback": "Critical: File is empty or too small to be valid."}
    
    score += 5
    feedback_parts.append("File created successfully")

    # 2. Anti-Gaming: File Timestamp
    if not result.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp indicates it may not have been modified during this session.")
        # We don't fail immediately but this is suspicious
    else:
        # Only check size if timestamp is valid
        if file_size >= 8000:
             # Substantial content bonus
             pass
        else:
             feedback_parts.append(f"File size ({file_size} bytes) is smaller than expected for a full document.")

    # 3. Structure - Table of Contents (15 pts)
    if result.get("has_toc", False):
        score += 15
        feedback_parts.append("Table of Contents found")
    else:
        feedback_parts.append("Missing Table of Contents")

    # 4. Structure - Heading 1 (15 pts)
    h1_count = result.get("heading1_count", 0)
    if h1_count >= 6:
        score += 15
        feedback_parts.append(f"Heading 1 structure good ({h1_count} sections)")
    elif h1_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient Heading 1 sections ({h1_count}/6)")
    else:
        feedback_parts.append("No Heading 1 styles used")

    # 5. Structure - Heading 2 (15 pts)
    h2_count = result.get("heading2_count", 0)
    if h2_count >= 10:
        score += 15
        feedback_parts.append(f"Heading 2 structure good ({h2_count} subsections)")
    elif h2_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient Heading 2 subsections ({h2_count}/10)")
    else:
        feedback_parts.append("No Heading 2 styles used")

    # 6. Content - Tables (15 pts)
    table_count = result.get("table_count", 0)
    if table_count >= 5:
        score += 15
        feedback_parts.append(f"Tables present ({table_count})")
    elif table_count > 0:
        score += 5 * table_count # 5 pts per table up to 15 max roughly, or just partial
        feedback_parts.append(f"Partial tables found ({table_count}/5)")
    else:
        feedback_parts.append("No tables found")

    # 7. Content - Footer/Page Numbers (10 pts)
    if result.get("has_page_numbers", False):
        score += 10
        feedback_parts.append("Page numbers present")
    else:
        feedback_parts.append("Missing page numbers/footer")

    # 8. Content - Body Length (10 pts)
    p_count = result.get("paragraph_count", 0)
    if p_count >= 35:
        score += 10
        feedback_parts.append("Document length sufficient")
    elif p_count >= 15:
        score += 5
        feedback_parts.append("Document length partial")
    else:
        feedback_parts.append("Document content too short")

    # 9. Text Validation (15 pts)
    if result.get("company_names_present", False):
        score += 5
        feedback_parts.append("Company names verified")
    else:
        feedback_parts.append("Company names missing")

    if result.get("keywords_present", False):
        score += 10
        feedback_parts.append("Security terminology verified")
    else:
        feedback_parts.append("Security terminology missing")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }