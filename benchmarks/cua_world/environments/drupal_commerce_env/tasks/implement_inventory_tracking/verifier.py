#!/usr/bin/env python3
"""
Verifier for Implement Inventory Tracking task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_tracking(traj, env_info, task_info):
    """
    Verifies:
    1. 'Stock Level' integer field exists on product variations.
    2. Stock data is correctly populated for 3 products.
    3. 'Low Stock Report' view exists with correct path and filter (< 10).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # Criteria 1: Field Creation (20 pts)
    field_config = result.get('field_storage_config')
    table_exists = result.get('table_exists', 0)
    
    if field_config and isinstance(field_config, dict):
        field_type = field_config.get('type')
        field_name = field_config.get('id', '')
        
        if field_type == 'integer' and 'field_stock_level' in field_name:
            score += 20
            feedback.append("Field 'field_stock_level' (integer) created successfully.")
        else:
            feedback.append(f"Field found but incorrect type or name. Type: {field_type}, ID: {field_name}")
            score += 5 # Partial credit for creating something
    elif int(table_exists) > 0:
         # Fallback: Config might have failed export but table exists implies field creation
         score += 15
         feedback.append("Field storage table exists, but config export failed.")
    else:
        feedback.append("Field 'field_stock_level' not found.")

    # Criteria 2: Data Entry (30 pts - 10 per product)
    stock_values = result.get('stock_values', {})
    expected_values = task_info.get('metadata', {}).get('stock_values', {})
    
    for sku, expected in expected_values.items():
        actual = stock_values.get(sku)
        # Actual comes back as string "3" or "null" or empty
        try:
            # Handle potential string/int types
            if actual is not None and str(actual).strip() == str(expected):
                score += 10
                feedback.append(f"Stock for {sku} correct ({actual}).")
            else:
                feedback.append(f"Stock for {sku} incorrect. Expected {expected}, got {actual}.")
        except:
            feedback.append(f"Error checking stock for {sku}.")

    # Criteria 3: View Creation & Configuration (50 pts)
    view_config = result.get('view_config')
    path_registered = int(result.get('view_path_registered', 0))
    
    if view_config and isinstance(view_config, dict):
        # 3a. View Exists (20 pts)
        score += 20
        feedback.append("View 'low_stock_report' created.")
        
        # 3b. View Path (10 pts)
        # Check display configurations for the path
        displays = view_config.get('display', {})
        path_found = False
        for display in displays.values():
            if display.get('display_options', {}).get('path') == 'admin/reports/low-stock':
                path_found = True
                break
        
        if path_found or path_registered > 0:
            score += 10
            feedback.append("View path '/admin/reports/low-stock' configured.")
        else:
            feedback.append("View path configuration missing or incorrect.")
            
        # 3c. Filter Criteria (< 10) (20 pts)
        # We need to dive deep into the display options to find filters
        filter_correct = False
        
        # Helper to recurse or search displays
        try:
            default_display = displays.get('default', {})
            filters = default_display.get('display_options', {}).get('filters', {})
            
            # Also check page_1 or other displays if filters are overridden
            for display in displays.values():
                d_filters = display.get('display_options', {}).get('filters', {})
                if d_filters:
                    filters.update(d_filters)

            for key, filter_item in filters.items():
                if filter_item.get('field') == 'field_stock_level_value':
                    op = filter_item.get('operator')
                    val = filter_item.get('value', {}).get('value')
                    # Config export format can vary, value might be direct or nested
                    if not val: 
                        val = filter_item.get('value')
                    
                    if op in ['<', 'lt'] and str(val) == '10':
                        filter_correct = True
                        break
        except Exception as e:
            feedback.append(f"Error parsing view filters: {e}")

        if filter_correct:
            score += 20
            feedback.append("View filter (Stock Level < 10) configured correctly.")
        else:
            feedback.append("View filter incorrect. Expected 'Stock Level < 10'.")
            
    else:
        feedback.append("View 'low_stock_report' not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }