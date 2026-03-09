#!/usr/bin/env python3
"""
Verifier for setup_customer_sidebar task in Drupal Commerce.

Verifies:
1. Custom "Support" block entity created (text match).
2. Three specific blocks placed in Sidebar region.
3. Visibility rules correctly configured for Role (Authenticated).
4. Visibility rules correctly configured for Request Path (Hide on /checkout/*).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_customer_sidebar(traj, env_info, task_info):
    """
    Verify block layout configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    drupal_data = result.get('drupal_data', {})
    sidebar_blocks = drupal_data.get('sidebar_blocks', [])
    
    score = 0
    feedback = []
    
    # 1. Verify Custom Block Entity Creation (10 pts)
    custom_created = drupal_data.get('custom_block_created', False)
    custom_content = drupal_data.get('custom_block_content', '') or ''
    
    if custom_created and '555-0199' in custom_content:
        score += 10
        feedback.append("Custom 'Support' block created successfully.")
    elif custom_created:
        score += 5
        feedback.append("Custom block created but content missing '555-0199'.")
    else:
        feedback.append("Custom 'Support' block NOT created.")

    # Track which requirements are met for placement and visibility
    placed_account = False
    placed_cart = False
    placed_support = False
    
    # Track visibility compliance count (max 3 blocks)
    role_ok_count = 0
    path_ok_count = 0
    
    # Helper to check visibility
    def check_visibility(block_data):
        v_role = False
        v_path = False
        
        # Check Role: Authenticated only
        roles = block_data.get('visibility', {}).get('user_role', {}).get('roles', {})
        # Drupal config structure varies; typically it's dict {role_id: role_id} or list
        if isinstance(roles, dict):
            roles = list(roles.values())
        
        # We expect 'authenticated' to be present. 
        # Ideally 'anonymous' is NOT present, but strictness varies.
        if 'authenticated' in roles and 'anonymous' not in roles:
            v_role = True
        
        # Check Path: Hide on /checkout/*
        path_conf = block_data.get('visibility', {}).get('request_path', {})
        pages = path_conf.get('pages', '')
        negate = path_conf.get('negate', 0)
        
        # Negate=1 means "Hide for the listed pages" (if pages listed)
        # We accept exact match or slight variations
        if '/checkout/*' in pages and (negate == 1 or negate is True or negate == '1'):
            v_path = True
            
        return v_role, v_path

    # Iterate through placed blocks
    for block in sidebar_blocks:
        plugin = block.get('plugin_id', '')
        content = block.get('content_body', '') or ''
        
        is_account = 'system_menu_block:account' in plugin
        is_cart = 'commerce_cart' in plugin # loose match for various cart blocks
        is_support = ('block_content:' in plugin) and ('555-0199' in content or 'Support' in block.get('label', ''))

        role_ok, path_ok = check_visibility(block)

        if is_account:
            placed_account = True
            if role_ok: role_ok_count += 1
            if path_ok: path_ok_count += 1
            
        elif is_cart:
            placed_cart = True
            if role_ok: role_ok_count += 1
            if path_ok: path_ok_count += 1
            
        elif is_support:
            placed_support = True
            if role_ok: role_ok_count += 1
            if path_ok: path_ok_count += 1

    # 2. Verify Placement (30 pts total)
    if placed_account:
        score += 10
        feedback.append("Account menu placed in sidebar.")
    else:
        feedback.append("Account menu missing from sidebar.")
        
    if placed_cart:
        score += 10
        feedback.append("Cart block placed in sidebar.")
    else:
        feedback.append("Cart block missing from sidebar.")
        
    if placed_support:
        score += 10
        feedback.append("Support block placed in sidebar.")
    else:
        feedback.append("Support block missing from sidebar.")

    # 3. Verify Visibility (60 pts total)
    # We require 3 specific blocks to be placed. If fewer are placed, max visibility score drops.
    # Logic: 10 pts per correct visibility setting per required block type.
    
    score += (role_ok_count * 10)
    score += (path_ok_count * 10)
    
    if role_ok_count == 3:
        feedback.append("Role visibility correct for all blocks.")
    else:
        feedback.append(f"Role visibility correct for {role_ok_count}/3 blocks.")
        
    if path_ok_count == 3:
        feedback.append("Page visibility correct for all blocks.")
    else:
        feedback.append(f"Page visibility correct for {path_ok_count}/3 blocks.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }