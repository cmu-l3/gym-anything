#!/usr/bin/env python3
"""
Verifier for add_arch_design_section task.

Verifies that:
1. The ARCH document was modified.
2. A new "Performance Constraints" heading exists.
3. A child requirement with specific text exists under that heading.
4. VLM confirms the UI shows the correct hierarchy.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, Optional, List

# VLM utilities from environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _strip_html(text: str) -> str:
    """Remove HTML tags from text."""
    if not text:
        return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()

def _find_item_recursive(items: List[Dict], criteria_fn) -> Optional[Dict]:
    """Recursively search for an item matching criteria."""
    for item in items:
        if criteria_fn(item):
            return item
        if 'children' in item and item['children']:
            found = _find_item_recursive(item['children'], criteria_fn)
            if found:
                return found
    return None

def verify_add_arch_design_section(traj, env_info, task_info):
    """
    Verify the ARCH document modification and hierarchy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    heading_text = metadata.get('heading_text', 'Performance Constraints')
    child_terms = metadata.get('child_text_terms', ['real-time', '50 milliseconds', 'sensor input'])

    # 1. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Get ARCH Document JSON
    temp_arch = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    arch_data = {}
    file_modified = result_data.get('arch_file_modified', False)
    
    try:
        copy_from_env("/tmp/ARCH_final.json", temp_arch.name)
        with open(temp_arch.name) as f:
            arch_data = json.load(f)
    except Exception as e:
        # If file missing or copy failed, we can still try VLM, but score will be low
        logger.warning(f"Failed to load ARCH.json: {e}")
    finally:
        if os.path.exists(temp_arch.name):
            os.unlink(temp_arch.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Modification (10 pts) ---
    if file_modified:
        score += 10
        feedback_parts.append("ARCH file modified")
    else:
        feedback_parts.append("ARCH file NOT modified (did you save?)")

    # --- Criterion 2: Heading Creation (25 pts) ---
    root_items = arch_data.get('data', [])
    
    def match_heading(item):
        txt = _strip_html(item.get('text', '') or item.get('heading', ''))
        return heading_text.lower() in txt.lower()

    heading_item = _find_item_recursive(root_items, match_heading)
    
    if heading_item:
        score += 25
        feedback_parts.append(f"Heading '{heading_text}' found")
    else:
        feedback_parts.append(f"Heading '{heading_text}' NOT found")

    # --- Criterion 3: Child Requirement Creation & Hierarchy (40 pts) ---
    child_found = False
    hierarchy_correct = False
    
    if heading_item:
        # Define matching function for child
        def match_child(item):
            txt = _strip_html(item.get('text', '') or item.get('description', ''))
            return all(term.lower() in txt.lower() for term in child_terms)

        # Check strict hierarchy: Child must be inside the heading's 'children' list
        # OR parentId must match (depending on how ReqView saves structure)
        
        # Method A: Direct children list check (most common in ReqView JSON)
        if 'children' in heading_item and heading_item['children']:
            target_child = _find_item_recursive(heading_item['children'], match_child)
            if target_child:
                child_found = True
                hierarchy_correct = True
        
        # Method B: Global search if not found in children (in case of flat structure with IDs)
        if not child_found:
            target_child = _find_item_recursive(root_items, match_child)
            if target_child:
                child_found = True
                # Check parent ID if available
                if str(target_child.get('parentId', '')) == str(heading_item.get('id', '')):
                    hierarchy_correct = True
                elif str(target_child.get('parent', '')) == str(heading_item.get('id', '')):
                    hierarchy_correct = True

    if child_found:
        score += 20
        feedback_parts.append("Child requirement text found")
        if hierarchy_correct:
            score += 20
            feedback_parts.append("Child properly nested under heading")
        else:
            feedback_parts.append("Child found but NOT nested under 'Performance Constraints'")
    else:
        feedback_parts.append("Child requirement with '50ms'/'real-time' text NOT found")

    # --- Criterion 4: VLM Visual Verification (25 pts) ---
    vlm_score = 0
    if VLM_AVAILABLE:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            Review this screenshot of ReqView.
            1. Is the 'ARCH' document open (check the document tab or tree)?
            2. Is there a section called 'Performance Constraints'?
            3. Is there a requirement under it mentioning '50 milliseconds' or 'real-time'?
            
            Return JSON: {"arch_open": bool, "section_visible": bool, "req_visible": bool}
            """
            try:
                vlm_res = query_vlm(prompt, final_screenshot)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('arch_open'): vlm_score += 5
                if parsed.get('section_visible'): vlm_score += 10
                if parsed.get('req_visible'): vlm_score += 10
                feedback_parts.append(f"VLM verification: {vlm_score}/25")
            except Exception as e:
                logger.warning(f"VLM query failed: {e}")
                # Fallback: if program check passed fully, award partial VLM points
                if score >= 65:
                    vlm_score = 15
                    feedback_parts.append("VLM failed, assuming visible based on file check")
        else:
            feedback_parts.append("No screenshot for VLM")
    
    score += vlm_score

    # Final Pass Check
    # Must have Heading + Child + valid structure to pass
    passed = (heading_item is not None) and child_found and hierarchy_correct and (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "heading_id": heading_item.get('id') if heading_item else None,
            "child_found": child_found,
            "hierarchy_correct": hierarchy_correct,
            "file_modified": file_modified
        }
    }