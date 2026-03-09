#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_journal_manuscript_reformat(traj, env_info, task_info):
    """
    Verify the manuscript reformatting task.
    Checks for file existence, margins, font, spacing, headers, styles, etc.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    # Metadata targets
    metadata = task_info.get('metadata', {})
    req_h1 = metadata.get('required_h1_count', 7)
    req_h2 = metadata.get('required_h2_count', 6)
    
    score = 0
    feedback = []

    # 1. File Existence & Modification (Gate)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Formatted file not found."}
    if not result.get("modified_during_task"):
        return {"passed": False, "score": 0, "feedback": "File found but not modified during task (timestamp check failed)."}
    
    score += 5 # Base score for creating file
    
    # 2. Margins (10 pts)
    if result.get("margins_correct"):
        score += 10
        feedback.append("Margins correct (1 inch)")
    else:
        feedback.append("Margins incorrect")

    # 3. Font (10 pts)
    if result.get("font_correct"):
        score += 10
        feedback.append("Font correct (Times New Roman)")
    else:
        feedback.append("Font incorrect (Expected Times New Roman)")

    # 4. Line Spacing (15 pts)
    if result.get("line_spacing_correct"):
        score += 15
        feedback.append("Line spacing correct (Double)")
    else:
        feedback.append("Line spacing incorrect (Expected Double)")

    # 5. Line Numbering (10 pts)
    if result.get("line_numbering_enabled"):
        score += 10
        feedback.append("Line numbering enabled")
    else:
        feedback.append("Line numbering missing")

    # 6. Header (10 pts)
    if result.get("header_correct"):
        score += 10
        feedback.append("Header present and correct")
    else:
        feedback.append("Header missing or incorrect text")

    # 7. Headings H1 (15 pts)
    h1_count = result.get("h1_count", 0)
    if h1_count >= req_h1:
        score += 15
        feedback.append(f"H1 styles correct ({h1_count}/{req_h1})")
    elif h1_count > 0:
        score += 5
        feedback.append(f"H1 styles partial ({h1_count}/{req_h1})")
    else:
        feedback.append("H1 styles missing (still using direct formatting?)")

    # 8. Headings H2 (10 pts)
    h2_count = result.get("h2_count", 0)
    if h2_count >= req_h2:
        score += 10
        feedback.append(f"H2 styles correct ({h2_count}/{req_h2})")
    elif h2_count > 0:
        score += 3
        feedback.append(f"H2 styles partial ({h2_count}/{req_h2})")
    else:
        feedback.append("H2 styles missing")

    # 9. Hanging Indents (10 pts)
    indent_count = result.get("hanging_indent_count", 0)
    if indent_count >= 1: # Checking strictly via regex is hard, if we see ANY negative indent it's a good sign
        score += 10
        feedback.append("Hanging indents detected")
    else:
        feedback.append("Hanging indents missing in references")

    # 10. Footer Page Numbers (5 pts)
    if result.get("footer_has_page_numbers"):
        score += 5
        feedback.append("Page numbers present")
    else:
        feedback.append("Page numbers missing")

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }