#!/usr/bin/env python3
"""
Verifier for configure_store_pages task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_store_pages(traj, env_info, task_info):
    """
    Verifies that the store pages and configuration are set up correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback = []
    
    # 1. Verify Site Identity (20 pts)
    site_config = result.get('site_config', {})
    
    # Site Name (10 pts)
    actual_name = site_config.get('name', '')
    expected_name = metadata.get('expected_site_name', 'Urban Electronics')
    if actual_name.strip() == expected_name:
        score += 10
        feedback.append(f"Site name correct: '{actual_name}'")
    else:
        feedback.append(f"Site name incorrect. Expected '{expected_name}', got '{actual_name}'")

    # Slogan (5 pts)
    actual_slogan = site_config.get('slogan', '')
    expected_slogan = metadata.get('expected_slogan', 'Premium Tech, Unbeatable Prices')
    if actual_slogan.strip() == expected_slogan:
        score += 5
        feedback.append("Site slogan correct")
    elif expected_slogan in actual_slogan:
        score += 3
        feedback.append("Site slogan partially correct")
    else:
        feedback.append(f"Site slogan incorrect: '{actual_slogan}'")

    # Front Page (5 pts)
    actual_front = site_config.get('front_page', '')
    expected_front = metadata.get('expected_front_page', '/products')
    # Normalizing paths
    norm_actual = actual_front.strip().lstrip('/')
    norm_expected = expected_front.strip().lstrip('/')
    if norm_actual == norm_expected:
        score += 5
        feedback.append(f"Front page correct: '{actual_front}'")
    else:
        feedback.append(f"Front page incorrect. Expected '{expected_front}', got '{actual_front}'")

    # 2. Verify Pages (40 pts)
    pages_res = result.get('pages', {})
    
    # Return Policy (20 pts)
    rp_res = pages_res.get('return_policy', {})
    if rp_res.get('exists'):
        score += 5
        feedback.append("Return Policy page created")
        
        # Check published
        if str(rp_res.get('status')) == "1":
            score += 5
            feedback.append("Return Policy published")
        else:
            feedback.append("Return Policy is NOT published")
            
        # Check alias
        if rp_res.get('alias') == "/return-policy":
            score += 5
            feedback.append("Return Policy alias correct")
        else:
            feedback.append(f"Return Policy alias incorrect: {rp_res.get('alias')}")
            
        # Check body content
        body = rp_res.get('body_snippet', '').lower()
        if "30 days" in body and "original packaging" in body:
            score += 5
            feedback.append("Return Policy content verified")
        else:
            feedback.append("Return Policy content missing required phrases")
    else:
        feedback.append("Return Policy page NOT found")

    # Shipping Info (20 pts)
    ship_res = pages_res.get('shipping_info', {})
    if ship_res.get('exists'):
        score += 5
        feedback.append("Shipping page created")
        
        if str(ship_res.get('status')) == "1":
            score += 5
            feedback.append("Shipping page published")
        
        if ship_res.get('alias') == "/shipping-info":
            score += 5
            feedback.append("Shipping page alias correct")
        
        body = ship_res.get('body_snippet', '').lower()
        if "free standard shipping" in body and "$50" in body:
            score += 5
            feedback.append("Shipping content verified")
        else:
            feedback.append("Shipping content missing required phrases")
    else:
        feedback.append("Shipping Information page NOT found")

    # 3. Verify Menu Links (40 pts)
    menu_links = result.get('menu_links', [])
    # Convert list of dicts to searchable format
    # link URIs in DB might be 'internal:/products' or 'entity:node/1'
    # We check titles primarily, and URIs secondarily if possible
    
    expected_links = metadata.get('menu_links', [])
    found_links = {link['title'].lower().strip(): link['uri'] for link in menu_links}
    
    menu_score = 0
    for exp in expected_links:
        title = exp['title']
        exp_uri_part = exp['uri_suffix']
        
        if title.lower() in found_links:
            actual_uri = found_links[title.lower()]
            # Check if URI matches (loose check for suffix)
            if exp_uri_part in actual_uri or (exp_uri_part == "contact" and "contact" in actual_uri):
                menu_score += 10
                feedback.append(f"Menu link '{title}' found and correct")
            else:
                menu_score += 5
                feedback.append(f"Menu link '{title}' found but URI seems wrong ('{actual_uri}')")
        else:
            feedback.append(f"Menu link '{title}' NOT found")
            
    score += menu_score

    # Anti-gaming check
    stats = result.get('stats', {})
    nodes_added = int(stats.get('current_node_count', 0)) - int(stats.get('initial_node_count', 0))
    
    if nodes_added < 1 and score > 20:
        feedback.append("WARNING: No new nodes detected despite content checks passing (re-using existing content?)")
        # In a real scenario, might penalize. Here we just warn unless score is suspiciously high without creation.

    # Final Pass Decision
    # Need pages created and some menu links
    passed = score >= 65 and pages_res.get('return_policy', {}).get('exists') and pages_res.get('shipping_info', {}).get('exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }