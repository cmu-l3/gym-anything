#!/usr/bin/env python3
"""Verifier for Admin Order Grid Customization task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_column_visibility(config, column_name):
    """
    Recursively search for a column configuration in the complex UI component JSON.
    Returns:
      True if explicitly visible
      False if explicitly hidden
      None if not found
    """
    if not isinstance(config, dict):
        return None
    
    # Check if we are at a column definition
    # Structure typically: positions > column_name > visible
    # OR: columns > column_name > visible
    if column_name in config:
        col_config = config[column_name]
        if isinstance(col_config, dict) and 'visible' in col_config:
            return col_config['visible']
    
    # Recursive search
    for key, value in config.items():
        if isinstance(value, dict):
            res = find_column_visibility(value, column_name)
            if res is not None:
                return res
    
    return None

def verify_grid_customization(traj, env_info, task_info):
    """
    Verify that the 'Logistics View' was created with specific column visibility.
    
    Criteria:
    1. View 'Logistics View' exists (40 pts)
    2. 'Payment Method' is visible (20 pts)
    3. 'Shipping Information' is visible (20 pts)
    4. 'Grand Total (Base)' is hidden (20 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Copy result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/grid_customization_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        bookmark_found = result.get('bookmark_found', False)
        bookmark_config_str = result.get('bookmark_config', '{}')
        
        if not bookmark_found or not bookmark_config_str:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "View 'Logistics View' was not found. Did you save the view using the 'Save View As' option?"
            }
            
        score += 40
        feedback_parts.append("View 'Logistics View' exists")
        
        # Parse the inner JSON config from the DB
        try:
            config = json.loads(bookmark_config_str)
        except json.JSONDecodeError:
            return {"passed": False, "score": score, "feedback": "View exists but config is invalid JSON"}

        # Check Payment Method (payment_method)
        # In Magento UI components, internal names are typically snake_case
        payment_vis = find_column_visibility(config, 'payment_method')
        if payment_vis is True:
            score += 20
            feedback_parts.append("Payment Method visible")
        elif payment_vis is False:
            feedback_parts.append("Payment Method hidden (expected visible)")
        else:
            feedback_parts.append("Payment Method visibility not set (default)")
            
        # Check Shipping Information (shipping_information)
        shipping_vis = find_column_visibility(config, 'shipping_information')
        if shipping_vis is True:
            score += 20
            feedback_parts.append("Shipping Info visible")
        elif shipping_vis is False:
            feedback_parts.append("Shipping Info hidden (expected visible)")
        else:
            feedback_parts.append("Shipping Info visibility not set")

        # Check Grand Total Base (base_grand_total) - Must be HIDDEN
        # Note: sometimes logic is inverted or keys differ. 'base_grand_total' is standard.
        base_total_vis = find_column_visibility(config, 'base_grand_total')
        if base_total_vis is False:
            score += 20
            feedback_parts.append("Base Grand Total hidden")
        elif base_total_vis is True:
            feedback_parts.append("Base Grand Total visible (expected hidden)")
        else:
            # If not found in config, it might be visible by default, so we don't award points
            # unless we find an explicit 'false' or we know defaults. 
            # In bookmark saved configs, usually only changes are saved, 
            # OR full state is saved. Assuming full state or explicit change.
            feedback_parts.append("Base Grand Total visibility not modified")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}