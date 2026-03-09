#!/usr/bin/env python3
"""
Verifier for Create Promo Landing View task.

Verifies:
1. Page exists at /pro-audio (HTTP 200)
2. Page contains specific header text
3. Page filters correctly (shows Pro items, hides others)
4. View configuration exists in Drupal
5. Menu link exists in Main menu
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_promo_landing_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_header = metadata.get('expected_header_text', 'Upgrade your setup with our professional gear')
    
    # Load primary result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Load raw view config (optional, for deeper debug if needed)
    view_config = {}
    try:
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/view_config_raw.json", temp_config.name)
        with open(temp_config.name, 'r') as f:
            content = f.read()
            if content.strip():
                view_config = json.loads(content)
        os.unlink(temp_config.name)
    except Exception:
        pass # Optional

    score = 0
    feedback_parts = []
    
    # Criterion 1: Page Accessibility (20 pts)
    http_status = int(result.get('http_status', 0))
    if http_status == 200:
        score += 20
        feedback_parts.append("Page /pro-audio is accessible")
    else:
        feedback_parts.append(f"Page /pro-audio returned status {http_status}")

    # Criterion 2: View Configuration Exists (20 pts)
    # This proves they used Views and not just a Basic Page node with path alias
    view_found = result.get('view_config_found', False)
    if isinstance(view_found, str): view_found = (view_found.lower() == 'true')
    
    if view_found:
        score += 20
        view_id = result.get('view_id', 'unknown')
        feedback_parts.append(f"View configuration found (ID: {view_id})")
    else:
        feedback_parts.append("No View configuration found for path /pro-audio")

    # Criterion 3: Header Text (20 pts)
    header_found = result.get('content_header_found', False)
    if isinstance(header_found, str): header_found = (header_found.lower() == 'true')
    
    if header_found:
        score += 20
        feedback_parts.append("Header text is correct")
    else:
        # Check raw config to see if they added it but it's not rendering
        raw_header = view_config.get('header', {})
        text_in_config = False
        if raw_header:
            for key, item in raw_header.items():
                if expected_header in str(item.get('content', '')):
                    text_in_config = True
        
        if text_in_config:
            score += 10 # Partial credit: Configured but not visible (maybe caching or format issue)
            feedback_parts.append("Header text found in config but not visible on page")
        else:
            feedback_parts.append("Header text missing")

    # Criterion 4: Filtering Logic (25 pts)
    # Must show Pro products AND NOT show others
    pos_found = result.get('content_positive_product_found', False)
    neg_found = result.get('content_negative_product_found', False)
    if isinstance(pos_found, str): pos_found = (pos_found.lower() == 'true')
    if isinstance(neg_found, str): neg_found = (neg_found.lower() == 'true')

    if pos_found and not neg_found:
        score += 25
        feedback_parts.append("Product filtering is correct")
    elif pos_found and neg_found:
        score += 10 # Filtering failed, but page renders products
        feedback_parts.append("Page lists products but filtering is missing (non-Pro items visible)")
    elif not pos_found:
        feedback_parts.append("No expected 'Pro' products found on page")

    # Criterion 5: Menu Link (15 pts)
    menu_found = result.get('menu_link_found', False)
    if isinstance(menu_found, str): menu_found = (menu_found.lower() == 'true')
    
    if menu_found:
        score += 15
        feedback_parts.append("Menu link 'Pro Audio' found")
    else:
        feedback_parts.append("Menu link not found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }