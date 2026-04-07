#!/usr/bin/env python3
"""Verifier for digitize_memo_requirements task.

Checks that:
1. SRS document was saved/modified.
2. A new section "Audit Logging" exists.
3. Three specific requirements are present in that section (fuzzy text match).
4. Priorities for those requirements match the memo (High/Medium).
"""

import json
import os
import re
import tempfile
import logging
from difflib import SequenceMatcher

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/digitize_memo_project/documents/SRS.json"


def _strip_html(text):
    """Remove HTML tags from text."""
    if not text:
        return ""
    text = re.sub(r'<[^>]+>', '', str(text))
    return text.strip()


def _fuzzy_match(a, b, threshold=0.85):
    """Check if two strings are similar."""
    return SequenceMatcher(None, a.lower(), b.lower()).ratio() >= threshold


def _find_section(items, title):
    """Recursively find a section by heading."""
    for item in items:
        # Check if item is a section (often has 'heading')
        heading = item.get('heading', '')
        if title.lower() in heading.lower():
            return item
        if 'children' in item:
            res = _find_section(item['children'], title)
            if res:
                return res
    return None


def verify_digitize_memo(traj, env_info, task_info):
    """Verify transcription of memo requirements."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_section = metadata.get('expected_section', 'Audit Logging')
    requirements = metadata.get('requirements', [])

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to load task results"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Load SRS document
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(SRS_PATH, temp_srs.name)
        with open(temp_srs.name) as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load SRS document: {e}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Modification (5 pts)
    if task_result.get('srs_modified_during_task', False):
        score += 5
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project NOT saved (timestamps unchanged)")

    # 2. Find Section (20 pts)
    section_node = _find_section(srs_data.get('data', []), expected_section)
    if not section_node:
        feedback_parts.append(f"Section '{expected_section}' not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    score += 20
    feedback_parts.append(f"Section '{expected_section}' found")
    
    # 3. Check Requirements (25 pts each: 20 text + 5 priority)
    section_children = section_node.get('children', [])
    
    # Helper to find best match in children
    def find_best_match(target_text, candidates):
        best_score = 0
        best_item = None
        for item in candidates:
            # Check text and description fields
            txt = _strip_html(item.get('text', '') or item.get('description', ''))
            sim = SequenceMatcher(None, target_text.lower(), txt.lower()).ratio()
            if sim > best_score:
                best_score = sim
                best_item = item
        return best_item, best_score

    for i, req in enumerate(requirements):
        target_text = req['text']
        target_prio = req['priority']
        
        match, match_score = find_best_match(target_text, section_children)
        
        if match_score > 0.85:
            score += 20
            
            # Check Priority
            # Priority might be a direct key, or inside attributes dict
            # ReqView priorities often stored as keys: 'High', 'H', 'Medium', 'M'
            actual_prio = match.get('priority', '')
            if not actual_prio and 'attributes' in match:
                actual_prio = match['attributes'].get('priority', '')
            
            # Normalize for comparison
            prio_map = {'high': 'high', 'h': 'high', 'medium': 'medium', 'm': 'medium', 'low': 'low', 'l': 'low'}
            norm_target = prio_map.get(target_prio.lower(), 'unknown')
            norm_actual = prio_map.get(str(actual_prio).lower(), 'unknown')
            
            if norm_target == norm_actual:
                score += 5
                feedback_parts.append(f"Req {i+1} text & priority correct")
            else:
                feedback_parts.append(f"Req {i+1} text matched, but priority '{actual_prio}' != '{target_prio}'")
        else:
            feedback_parts.append(f"Req {i+1} text not found (max similarity: {match_score:.2f})")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "srs_modified": task_result.get('srs_modified_during_task'),
            "section_found": bool(section_node)
        }
    }