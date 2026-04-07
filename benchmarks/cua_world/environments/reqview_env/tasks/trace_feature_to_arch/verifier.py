#!/usr/bin/env python3
"""Verifier for trace_feature_to_arch task.

Checks:
1. ARCH document contains a "Security Audit Module" component.
2. SRS document contains a requirement about "timestamped audit log".
3. A traceability link connects the SRS requirement to the ARCH component.
"""

import json
import os
import re
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Default paths - will verify against these if metadata is missing
DEFAULT_PROJECT_PATH = "/home/ga/Documents/ReqView/trace_feature_project"


def _strip_html(text):
    """Remove HTML tags from text."""
    if not text:
        return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()


def _find_item_recursive(items, text_contains=None, heading_contains=None):
    """Recursively search for an item matching text or heading."""
    for item in items:
        # Check text (description)
        item_text = _strip_html(item.get('text', ''))
        # Check heading
        item_heading = _strip_html(item.get('heading', ''))

        match = False
        if text_contains and text_contains.lower() in item_text.lower():
            match = True
        if heading_contains and heading_contains.lower() in item_heading.lower():
            match = True
        
        if match:
            return item

        if 'children' in item:
            result = _find_item_recursive(item['children'], text_contains, heading_contains)
            if result:
                return result
    return None


def verify_trace_feature_to_arch(traj, env_info, task_info):
    """Verify end-to-end feature definition and allocation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    arch_comp_name = metadata.get('arch_component_name', "Security Audit Module")
    srs_req_text = metadata.get('srs_req_text', "timestamped audit log entry")
    
    # Locate project files
    project_path = DEFAULT_PROJECT_PATH
    arch_json_path = os.path.join(project_path, "documents", "ARCH.json")
    srs_json_path = os.path.join(project_path, "documents", "SRS.json")

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # Step 1: Verify ARCH Component
    # ------------------------------------------------------------------
    arch_data = {}
    arch_comp = None
    
    temp_arch = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(arch_json_path, temp_arch.name)
        with open(temp_arch.name, 'r') as f:
            arch_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ARCH.json: {str(e)}"}
    finally:
        if os.path.exists(temp_arch.name):
            os.unlink(temp_arch.name)

    # Search for component in ARCH
    arch_comp = _find_item_recursive(arch_data.get('data', []), heading_contains=arch_comp_name, text_contains=arch_comp_name)
    
    if arch_comp:
        score += 25
        feedback_parts.append(f"ARCH component '{arch_comp_name}' found (ID: {arch_comp.get('id')})")
    else:
        feedback_parts.append(f"ARCH component '{arch_comp_name}' NOT found")

    # ------------------------------------------------------------------
    # Step 2: Verify SRS Requirement
    # ------------------------------------------------------------------
    srs_data = {}
    srs_req = None

    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_json_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read SRS.json: {str(e)}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    # Search for requirement in SRS
    srs_req = _find_item_recursive(srs_data.get('data', []), text_contains=srs_req_text)

    if srs_req:
        score += 25
        feedback_parts.append("SRS requirement found")
    else:
        feedback_parts.append(f"SRS requirement containing '{srs_req_text}' NOT found")

    # ------------------------------------------------------------------
    # Step 3: Verify Traceability Link
    # ------------------------------------------------------------------
    link_found = False
    
    if arch_comp and srs_req:
        # Check outgoing links from SRS (SRS -> ARCH)
        # Most common direction for "allocation" or "satisfaction"
        srs_links = srs_req.get('links', [])
        target_arch_id = str(arch_comp.get('id'))
        
        for link in srs_links:
            # Check if link points to ARCH document and our component ID
            # docId might be 'ARCH' or a UUID, but usually short ID in example projects
            # We match mostly on reqId being the component's ID
            if str(link.get('reqId')) == target_arch_id:
                link_found = True
                break
        
        # Also check incoming links (ARCH -> SRS) just in case agent linked backwards
        if not link_found:
            arch_links = arch_comp.get('links', [])
            target_srs_id = str(srs_req.get('id'))
            for link in arch_links:
                if str(link.get('reqId')) == target_srs_id:
                    link_found = True
                    break

    if link_found:
        score += 40
        feedback_parts.append("Traceability link confirmed")
    elif arch_comp and srs_req:
        feedback_parts.append("Link missing between found items")
    
    # ------------------------------------------------------------------
    # Step 4: Data Integrity (10 pts)
    # ------------------------------------------------------------------
    # If both items exist and look correct (text match verified above implies basic integrity)
    if arch_comp and srs_req:
        score += 10
    
    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    # Pass threshold: 90 points (Need both objects + link)
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "arch_comp_id": arch_comp.get('id') if arch_comp else None,
            "srs_req_id": srs_req.get('id') if srs_req else None,
            "link_found": link_found
        }
    }