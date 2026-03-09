#!/usr/bin/env python3
"""Verifier for Electronics Recycling Fee Setup task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_electronics_recycling_fee_setup(traj, env_info, task_info):
    """
    Verify FPT setup for California E-Waste Fee.
    
    Criteria:
    1. FPT Enabled in Config (20 pts)
    2. Attribute Created with correct Input Type 'weee' (25 pts)
    3. Attribute assigned to Default Attribute Set (15 pts)
    4. Tax Rule applied to correct product (LAPTOP-001) (20 pts)
    5. Tax Rule has correct value ($12.50) and region (CA/12) (20 pts)
    
    Pass threshold: 80 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/fpt_task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    logger.info(f"Result: {result}")
    
    score = 0
    feedback_parts = []
    
    # 1. Check FPT Enabled (20 pts)
    if result.get('fpt_enabled', False):
        score += 20
        feedback_parts.append("FPT enabled (20 pts)")
    else:
        feedback_parts.append("FPT NOT enabled in Config")

    # 2. Check Attribute Creation (25 pts)
    attr_exists = result.get('attribute_exists', False)
    attr_type = result.get('attribute_type', '')
    
    if attr_exists and attr_type == 'weee':
        score += 25
        feedback_parts.append("Attribute created correctly (25 pts)")
    elif attr_exists:
        score += 10
        feedback_parts.append(f"Attribute exists but wrong input type: {attr_type} (expected 'Fixed Product Tax') (10 pts)")
    else:
        feedback_parts.append("Attribute 'california_ewaste_fee' not found")

    # 3. Check Attribute Set Assignment (15 pts)
    if result.get('attribute_in_set', False):
        score += 15
        feedback_parts.append("Attribute assigned to set (15 pts)")
    else:
        feedback_parts.append("Attribute not assigned to Default Attribute Set")

    # 4 & 5. Check Product Tax Application (40 pts total)
    tax_applied = result.get('tax_applied', False)
    tax_val_str = str(result.get('tax_value', '0'))
    tax_region_str = str(result.get('tax_region', '0'))
    
    if tax_applied:
        score += 20
        feedback_parts.append("Tax rule applied to product (20 pts)")
        
        # Check value (allow small float diff)
        try:
            val = float(tax_val_str)
            if abs(val - 12.50) < 0.01:
                val_ok = True
            else:
                val_ok = False
        except:
            val_ok = False
            
        # Check region (12 is CA)
        region_ok = (tax_region_str == '12')
        
        if val_ok and region_ok:
            score += 20
            feedback_parts.append("Tax value ($12.50) and region (CA) correct (20 pts)")
        elif val_ok:
            score += 10
            feedback_parts.append(f"Tax value correct, but wrong region (ID: {tax_region_str}) (10 pts)")
        elif region_ok:
            score += 10
            feedback_parts.append(f"Region correct, but wrong value (${tax_val_str}) (10 pts)")
        else:
            feedback_parts.append(f"Tax applied but wrong value/region (${tax_val_str}, ID: {tax_region_str})")
    else:
        feedback_parts.append("No tax rule found on product LAPTOP-001")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }