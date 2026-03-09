#!/usr/bin/env python3
"""
Verifier for deploy_customer_order_history_view task.

Checks:
1. Test data creation (Order exists for janesmith)
2. View creation (Block display, correct fields)
3. Contextual Filter configuration (User ID from route context) - CRITICAL
4. Block placement (Content region, restricted to /user/*)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_customer_order_history_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Test Data Creation (10 pts)
    # The agent must have created an order for janesmith to visualize the view
    orders_created = result.get('orders_created', 0)
    current_orders = result.get('current_orders', 0)
    
    if current_orders > 0:
        score += 10
        feedback_parts.append("Test order exists for user")
    else:
        feedback_parts.append("No orders found for test user (cannot verify view visualization)")

    # 2. Check View Existence (15 pts)
    if not result.get('view_exists'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "View 'my_recent_orders' was not created. " + " | ".join(feedback_parts)
        }
    
    score += 15
    feedback_parts.append("View created")
    view_config = result.get('view_config', {})
    
    # 3. Check Fields (15 pts)
    # Look for specific fields in the display options
    # We expect 'order_id', 'placed', 'total_price', 'state'
    # Note: Drupal config structure is deeply nested
    
    fields = {}
    try:
        # Check default display first, then block display
        default_display = view_config.get('display', {}).get('default', {}).get('display_options', {})
        fields = default_display.get('fields', {})
        
        # If fields are overridden in block display, check there too (simplified check)
    except:
        pass

    required_fields = ['order_id', 'placed', 'total_price', 'state']
    found_fields = [f for f in required_fields if any(k.startswith(f) for k in fields.keys())]
    
    if len(found_fields) >= 3:
        score += 15
        feedback_parts.append(f"Correct fields configured ({len(found_fields)}/4)")
    elif len(found_fields) > 0:
        score += 5
        feedback_parts.append(f"Some fields missing (found {len(found_fields)}/4)")
    else:
        feedback_parts.append("Required fields not found in view")

    # 4. Check Contextual Filter (30 pts) - CRITICAL
    # We need to find an argument (Contextual Filter) that maps to uid/owner
    # and uses 'user' default argument type (User ID from route context)
    
    contextual_filter_passed = False
    arguments = view_config.get('display', {}).get('default', {}).get('display_options', {}).get('arguments', {})
    
    for arg_id, arg_config in arguments.items():
        # Check if it's related to user/uid/owner
        if 'uid' in arg_config.get('field', '') or 'owner' in arg_config.get('field', ''):
            default_action = arg_config.get('default_action', '')
            default_arg_type = arg_config.get('default_argument_type', '')
            
            if default_action == 'default' and default_arg_type == 'user':
                contextual_filter_passed = True
                break
    
    if contextual_filter_passed:
        score += 30
        feedback_parts.append("Contextual filter correctly configured (User ID from route)")
    else:
        feedback_parts.append("Contextual filter missing or incorrect (Must be 'User ID from route context')")

    # 5. Check Block Placement (15 pts)
    if result.get('block_placed'):
        score += 15
        feedback_parts.append("Block placed in layout")
    else:
        feedback_parts.append("Block not placed in layout")
        # Can't check visibility if not placed
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 6. Check Visibility Restriction (15 pts)
    block_config = result.get('block_config', {})
    visibility = block_config.get('visibility', {})
    request_path = visibility.get('request_path', {})
    pages = request_path.get('pages', '')
    
    if '/user/*' in pages:
        score += 15
        feedback_parts.append("Visibility correctly restricted to /user/*")
    else:
        feedback_parts.append(f"Visibility setting incorrect (found: '{pages}')")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }