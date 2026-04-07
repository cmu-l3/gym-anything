#!/usr/bin/env python3
"""
Verifier for document_math_formula task.

Checks that:
1. A requirement titled "Altitude Control Loop" exists in SRS.
2. The description contains the introductory text.
3. The description contains the PID formula in LaTeX format.
4. The project was saved (file modified).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_tex(text):
    """Normalize LaTeX string by removing whitespace to allow for spacing variations."""
    if not text:
        return ""
    # Remove all whitespace
    return re.sub(r'\s+', '', text)

def find_requirement_by_heading(items, target_heading):
    """Recursively search for a requirement with specific heading."""
    for item in items:
        # Check both 'heading' and 'name' fields depending on ReqView version/structure
        item_heading = item.get('heading', '')
        if not item_heading and item.get('name'):
            item_heading = item.get('name')
            
        if item_heading and target_heading.lower() in item_heading.lower():
            return item
            
        if 'children' in item:
            result = find_requirement_by_heading(item['children'], target_heading)
            if result:
                return result
    return None

def verify_document_math_formula(traj, env_info, task_info):
    """Verify the math formula requirement creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    target_heading = metadata.get('target_heading', "Altitude Control Loop")
    
    # Target formula parts (normalized for whitespace-insensitive comparison)
    # u(t) = K_p e(t) + K_i \int_0^t e(\tau) d\tau + K_d \frac{de(t)}{dt}
    expected_formula_components = [
        "u(t)=",
        "K_pe(t)",
        "K_i\\int_0^te(\\tau)d\\tau",
        "K_d\\frac{de(t)}{dt}"
    ]

    # Load result JSON from export script
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check if SRS file was modified (Anti-gaming)
    if not task_result.get('srs_file_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project was not saved (SRS file not modified). Please save your work (Ctrl+S)."
        }

    srs_path = task_result.get('srs_file_path')
    if not srs_path:
        return {"passed": False, "score": 0, "feedback": "SRS file path missing in result"}

    # Load SRS document content
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read SRS document: {e}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    score = 0
    feedback_parts = []
    
    # 1. Check for Requirement Creation (20 pts)
    req_item = find_requirement_by_heading(srs_data.get('data', []), target_heading)
    if req_item:
        score += 20
        feedback_parts.append(f"Requirement '{target_heading}' found")
    else:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Could not find requirement with heading '{target_heading}'"
        }

    # Get description text (handle HTML content)
    description = req_item.get('text', '') or req_item.get('description', '')
    # Remove HTML tags for text analysis, but keep structure for math checks if needed
    clean_desc = re.sub(r'<[^>]+>', '', description)
    norm_desc = normalize_tex(description)

    # 2. Check for LaTeX Delimiters (20 pts)
    # ReqView often stores math as $$...$$ or \(...\) or \[...\]
    has_delimiters = "$$" in description or "\\[" in description or "\\(" in description
    if has_delimiters:
        score += 20
        feedback_parts.append("LaTeX delimiters found")
    else:
        feedback_parts.append("Missing LaTeX delimiters (e.g. $$)")

    # 3. Check for Introductory Text (10 pts)
    if "standard PID algorithm" in clean_desc:
        score += 10
        feedback_parts.append("Introductory text found")
    else:
        feedback_parts.append("Introductory text missing or incorrect")

    # 4. Check Formula Correctness (40 pts)
    formula_score = 0
    components_found = 0
    for comp in expected_formula_components:
        if comp in norm_desc:
            components_found += 1
    
    # Calculate formula score proportional to components found
    if components_found == len(expected_formula_components):
        formula_score = 40
        feedback_parts.append("Formula is correct")
    elif components_found > 0:
        formula_score = int(40 * (components_found / len(expected_formula_components)))
        feedback_parts.append(f"Formula partially correct ({components_found}/{len(expected_formula_components)} parts)")
    else:
        feedback_parts.append("Formula content not found")
    
    score += formula_score

    # 5. Save Check (10 pts)
    # We already checked modification time at the start, award points here
    score += 10
    feedback_parts.append("Project saved successfully")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "heading_found": True,
            "components_found": components_found,
            "total_components": len(expected_formula_components),
            "raw_description_preview": description[:100]
        }
    }