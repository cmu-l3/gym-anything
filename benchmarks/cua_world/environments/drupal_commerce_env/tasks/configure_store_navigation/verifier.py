#!/usr/bin/env python3
"""
Verifier for configure_store_navigation task.

Verifies:
1. "Shop", "Cart", "Account" links exist in the main menu.
2. Links point to correct paths (/products, /cart, /user).
3. Links are ordered correctly (Shop < Cart < Account).
4. A custom block exists with "© 2025 Urban Electronics".
5. The block is placed in the footer region.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_store_navigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_links = metadata.get('expected_menu_links', [])
    expected_copyright = metadata.get('expected_copyright_text', "2025 Urban Electronics")
    expected_region = metadata.get('expected_region', "footer_bottom") # olivero usually uses footer_bottom or footer

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # --- Verify Menu Links (45 pts total) ---
    menu_links = result.get('menu_links', [])
    found_links = {} # title -> {weight, path}
    
    # Helper to clean titles and paths for fuzzy matching
    def clean_str(s): return s.lower().strip()
    
    for link in menu_links:
        title = link.get('title', '')
        found_links[clean_str(title)] = link

    # Check existence and paths (15 pts per link)
    links_correct = 0
    link_weights = {} # title -> weight
    
    for exp in expected_links:
        exp_title = exp['title']
        exp_regex = exp['regex']
        
        # Find match
        match = None
        for title, data in found_links.items():
            if clean_str(exp_title) == title:
                match = data
                break
        
        if match:
            path = match.get('path', '')
            if re.search(exp_regex, path):
                score += 15
                links_correct += 1
                link_weights[exp_title] = match.get('weight', 0)
                feedback_parts.append(f"Link '{exp_title}' found and correct.")
            else:
                score += 5 # Partial for title match but wrong path
                feedback_parts.append(f"Link '{exp_title}' found but path '{path}' incorrect.")
        else:
            feedback_parts.append(f"Link '{exp_title}' NOT found.")

    # Check Order (10 pts)
    # Shop < Cart < Account
    if "Shop" in link_weights and "Cart" in link_weights and "Account" in link_weights:
        if link_weights["Shop"] < link_weights["Cart"] < link_weights["Account"]:
            score += 10
            feedback_parts.append("Menu order correct.")
        else:
            feedback_parts.append("Menu order incorrect.")
            # Debug info
            feedback_parts.append(f"(Weights: Shop={link_weights['Shop']}, Cart={link_weights['Cart']}, Acc={link_weights['Account']})")

    # --- Verify Copyright Block (45 pts total) ---
    
    # 1. Content (20 pts)
    custom_blocks = result.get('custom_blocks', [])
    target_block_uuid = None
    
    for block in custom_blocks:
        body = block.get('body', '')
        # Check for Copyright text (ignoring HTML entities like &copy; vs ©)
        # We look for "2025 Urban Electronics"
        if expected_copyright in body:
            score += 20
            target_block_uuid = block.get('uuid')
            feedback_parts.append("Copyright block content found.")
            break
            
    # 2. Placement (25 pts)
    # We need to find a placed block (config) that references our target_block_uuid
    if target_block_uuid:
        placed_blocks = result.get('placed_blocks', [])
        placement_found = False
        
        for pb in placed_blocks:
            plugin_id = pb.get('plugin_id', '')
            # Plugin ID for custom blocks is usually "block_content:UUID"
            if target_block_uuid in plugin_id:
                region = pb.get('region', '')
                if region in ['footer', 'footer_bottom', 'footer_top']:
                    score += 25
                    placement_found = True
                    feedback_parts.append(f"Block correctly placed in region '{region}'.")
                else:
                    score += 10 # Placed but wrong region
                    feedback_parts.append(f"Block placed in wrong region '{region}'.")
                break
        
        if not placement_found:
             feedback_parts.append("Copyright block created but NOT placed/active in theme.")
    else:
        feedback_parts.append("Copyright block content NOT found.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }