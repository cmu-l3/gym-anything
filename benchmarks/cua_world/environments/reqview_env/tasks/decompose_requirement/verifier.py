#!/usr/bin/env python3
"""
Verifier for decompose_requirement task.

Task: Create a "System Performance" requirement with 3 specific children.

Verification checks:
1. SRS.json file exists and was modified.
2. A requirement containing "System Performance" exists.
3. This requirement has exactly 3 children.
4. The children match the expected text (latency, concurrency, uptime).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _strip_html(text):
    """Remove HTML tags from text."""
    if not text:
        return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()

def _find_requirement_with_children(items, target_text):
    """
    Recursively search for a requirement whose text contains target_text.
    Returns the item dict if found, else None.
    """
    for item in items:
        # Check current item
        # ReqView stores text in 'text' (HTML) or sometimes 'heading'
        text_content = _strip_html(item.get('text', '')) + " " + _strip_html(item.get('heading', ''))
        
        if target_text.lower() in text_content.lower():
            return item
            
        # Recurse into children
        if 'children' in item:
            result = _find_requirement_with_children(item['children'], target_text)
            if result:
                return result
    return None

def verify_decompose_requirement(traj, env_info, task_info):
    """Verify the functional decomposition of the System Performance requirement."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    srs_path = metadata.get('srs_path', '/home/ga/Documents/ReqView/decompose_req_project/documents/SRS.json')
    parent_text = metadata.get('parent_text', 'System Performance')
    
    # Check result json for modification status
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            res_data = json.load(f)
            file_modified = res_data.get('file_modified_during_task', False)
    except Exception:
        pass # If result json fails, we continue but lose the modification bonus
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Load SRS Document
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read SRS document. Did you save the project? Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Parent Requirement Creation (20 pts)
    # Note: SRS data is in srs_data['data'] which is a list of objects
    parent_req = _find_requirement_with_children(srs_data.get('data', []), parent_text)
    
    if not parent_req:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not find a requirement with text/heading '{parent_text}'."
        }
    
    score += 20
    feedback_parts.append(f"Parent requirement '{parent_text}' found")
    
    # 3. Verify Hierarchy/Nesting (30 pts)
    children = parent_req.get('children', [])
    child_count = len(children)
    
    if child_count == 3:
        score += 30
        feedback_parts.append("Correctly nested 3 child requirements")
    else:
        # Partial credit if they have some children, but we want exact structure
        if child_count > 0:
            score += 10
            feedback_parts.append(f"Found {child_count} children nested (expected 3)")
        else:
            feedback_parts.append("No child requirements nested under parent (did you indent them?)")

    # 4. Verify Child Content (45 pts total, 15 each)
    # We check if the expected text fragments appear in *any* of the children
    expected_children = [
        ("respond to API requests within 200ms", "Latency"),
        ("support 500 concurrent user sessions", "Concurrency"),
        ("maintain 99.9% uptime", "Uptime")
    ]
    
    found_children_text = []
    for c in children:
        text = _strip_html(c.get('text', '')) + " " + _strip_html(c.get('description', ''))
        found_children_text.append(text.lower())
    
    matched_count = 0
    for fragment, label in expected_children:
        fragment_lower = fragment.lower()
        # Check if this fragment is in any of the actual children
        if any(fragment_lower in child_text for child_text in found_children_text):
            score += 15
            matched_count += 1
            feedback_parts.append(f"Child '{label}' correct")
        else:
            feedback_parts.append(f"Child '{label}' missing or incorrect text")

    # 5. Verify File Saved (5 pts)
    if file_modified:
        score += 5
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project not saved (file timestamp unchanged)")

    # 6. Final Evaluation
    # Pass threshold: 85 (Needs structure + at least 2/3 children correct)
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "parent_found": True,
            "child_count": child_count,
            "matched_children": matched_count,
            "file_modified": file_modified
        }
    }