#!/usr/bin/env python3
"""
Verifier for Paperback Book Layout task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_paperback_book_layout(traj, env_info, task_info):
    """
    Verify the ODT document formatting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_header_even = metadata.get('header_even', "J.R. BLACKWOOD")
    expected_header_odd = metadata.get('header_odd', "THE ECHOING VOID")

    # Load result from container
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

    # Base checks
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get("modified_during_task"):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task (anti-gaming)."}

    analysis = result.get("analysis", {})
    score = 0
    feedback = []

    # 1. Page Size (25 pts)
    # Expected: 6in x 9in. ODT often stores as "6in" or "15.24cm"
    # We need robust parsing.
    width_raw = analysis.get("page_width", "")
    height_raw = analysis.get("page_height", "")
    
    def parse_inches(val):
        if not val: return 0
        if "in" in val: return float(val.replace("in", ""))
        if "cm" in val: return float(val.replace("cm", "")) / 2.54
        return 0

    width = parse_inches(width_raw)
    height = parse_inches(height_raw)
    
    # Allow small tolerance (e.g. 0.1 inch)
    if 5.9 < width < 6.1 and 8.9 < height < 9.1:
        score += 25
        feedback.append("Page size correct (6x9).")
    else:
        feedback.append(f"Page size incorrect. Found: {width_raw} x {height_raw}. Expected: 6in x 9in.")

    # 2. Mirrored Margins (25 pts)
    # Mirrored implies Inside (Left on odd) != Outside (Right on odd).
    # Typically Inside=0.8, Outside=0.5.
    # In ODT styles.xml:
    # If mirrored, margin-left and margin-right might be stored as "inside" and "outside" logically, 
    # OR explicit values.
    # The script extracted 'margin_left' and 'margin_right'. 
    # NOTE: In 'mirrored' layout, Left often maps to Inside and Right to Outside for the default page style.
    
    m_left = parse_inches(analysis.get("margin_left"))
    m_right = parse_inches(analysis.get("margin_right"))
    is_mirrored = analysis.get("print_orientation") == "mirrored" or analysis.get("has_header_left_style")

    # Check for asymmetry which implies mirroring logic was attempted
    # OR explicit correct values
    # Expected: 0.8 and 0.5
    
    margins_correct = False
    if (0.75 <= m_left <= 0.85 and 0.45 <= m_right <= 0.55) or \
       (0.75 <= m_right <= 0.85 and 0.45 <= m_left <= 0.55):
         margins_correct = True
    
    if margins_correct:
        score += 25
        feedback.append("Margins correct (0.8/0.5).")
    elif is_mirrored:
        score += 15
        feedback.append("Mirrored layout detected but values slightly off.")
    else:
        feedback.append(f"Margins incorrect or not mirrored. Found L:{m_left} R:{m_right}.")

    # 3. Paragraph Formatting (20 pts)
    # First line indent ~ 0.25in
    indent_raw = analysis.get("first_line_indent", "")
    indent = parse_inches(indent_raw)
    
    if 0.2 < indent < 0.3:
        score += 20
        feedback.append("First line indent correct.")
    elif indent > 0:
        score += 10
        feedback.append(f"Indent present but incorrect value ({indent_raw}).")
    else:
        feedback.append("No first line indent found.")

    # 4. Alternating Headers (20 pts)
    # We look for the author name and book title in the extracted header content
    # Note: The extraction might dump all header text found.
    left_content = analysis.get("header_content_left", "")
    right_content = analysis.get("header_content_right", "")
    
    # We allow them to be swapped (as long as they are distinct and present)
    has_author = expected_header_even in left_content or expected_header_even in right_content
    has_title = expected_header_odd in left_content or expected_header_odd in right_content
    distinct = left_content != right_content
    
    if has_author and has_title and distinct:
        score += 20
        feedback.append("Alternating headers correct.")
    elif has_author or has_title:
        score += 10
        feedback.append("Headers present but content mismatch or not alternating.")
    else:
        feedback.append(f"Headers missing or incorrect. Found L:'{left_content}' R:'{right_content}'.")

    # 5. File Creation (10 pts)
    # Already checked exists/modified
    score += 10

    # Final Pass Check
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }