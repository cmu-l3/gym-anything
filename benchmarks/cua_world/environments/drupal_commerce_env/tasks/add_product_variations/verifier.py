#!/usr/bin/env python3
"""
Verifier for Add Product Variations task.

Scoring (100 points):
1. Parent product intact (5 pts)
2. Total variation count increased by at least 2 (15 pts)
3. Variation 1 (16GB/512GB) exists with correct SKU (15 pts)
4. Variation 1 price correct ($1249.99) (15 pts)
5. Variation 2 (32GB/1TB) exists with correct SKU (15 pts)
6. Variation 2 price correct ($1599.99) (15 pts)
7. Both variations linked to parent product (10 pts)
8. Both variations published (10 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_product_variations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values
    EXP_SKU1 = "DELL-XPS13-16-512"
    EXP_PRICE1 = 1249.99
    EXP_SKU2 = "DELL-XPS13-32-1TB"
    EXP_PRICE2 = 1599.99

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Helper to parse boolean/int fields safely
        def get_bool(key):
            val = result.get(key, False)
            return str(val).lower() == 'true' if isinstance(val, str) else bool(val)

        # 1. Parent Product Intact (5 pts)
        if get_bool('parent_exists'):
            score += 5
            feedback_parts.append("Parent product found")
        else:
            return {"passed": False, "score": 0, "feedback": "CRITICAL: Parent product 'Dell XPS 13 Laptop' not found or deleted."}

        # 2. Variation Count check (15 pts)
        init_count = int(result.get('initial_variation_count', 0))
        curr_count = int(result.get('current_variation_count', 0))
        if curr_count >= init_count + 2:
            score += 15
            feedback_parts.append(f"Variation count increased (+{curr_count - init_count})")
        elif curr_count > init_count:
            score += 5
            feedback_parts.append(f"Variation count increased only by {curr_count - init_count} (expected 2)")
        else:
            feedback_parts.append("No new variations linked to product")

        # 3 & 4. Variation 1 Checks (30 pts)
        if get_bool('var1_found'):
            score += 15
            feedback_parts.append(f"SKU {EXP_SKU1} found")
            
            # Price check
            try:
                p1 = float(result.get('var1_price', 0))
                if abs(p1 - EXP_PRICE1) < 0.01:
                    score += 15
                    feedback_parts.append(f"Price {EXP_PRICE1} correct")
                else:
                    feedback_parts.append(f"Price mismatch for {EXP_SKU1}: expected {EXP_PRICE1}, got {p1}")
            except ValueError:
                feedback_parts.append(f"Invalid price format for {EXP_SKU1}")
        else:
            feedback_parts.append(f"SKU {EXP_SKU1} NOT found")

        # 5 & 6. Variation 2 Checks (30 pts)
        if get_bool('var2_found'):
            score += 15
            feedback_parts.append(f"SKU {EXP_SKU2} found")
            
            try:
                p2 = float(result.get('var2_price', 0))
                if abs(p2 - EXP_PRICE2) < 0.01:
                    score += 15
                    feedback_parts.append(f"Price {EXP_PRICE2} correct")
                else:
                    feedback_parts.append(f"Price mismatch for {EXP_SKU2}: expected {EXP_PRICE2}, got {p2}")
            except ValueError:
                feedback_parts.append(f"Invalid price format for {EXP_SKU2}")
        else:
            feedback_parts.append(f"SKU {EXP_SKU2} NOT found")

        # 7. Linkage Check (10 pts)
        linked1 = get_bool('var1_linked')
        linked2 = get_bool('var2_linked')
        if linked1 and linked2:
            score += 10
            feedback_parts.append("Both variations linked to parent")
        elif linked1 or linked2:
            score += 5
            feedback_parts.append("One variation linked to parent")
        else:
            # If variations exist but aren't linked, this is a major failure in this context
            if get_bool('var1_found') or get_bool('var2_found'):
                feedback_parts.append("Variations created but NOT linked to the 'Dell XPS 13 Laptop' product")

        # 8. Status Check (10 pts)
        # Status from DB is '1' for active/published
        status1 = str(result.get('var1_status', '0')) == '1'
        status2 = str(result.get('var2_status', '0')) == '1'
        
        if status1 and status2:
            score += 10
            feedback_parts.append("Both variations published")
        elif status1 or status2:
            score += 5
            feedback_parts.append("One variation published")
        else:
            if get_bool('var1_found') or get_bool('var2_found'):
                feedback_parts.append("Variations are not published (status=0)")

        # Pass threshold
        passed = score >= 65
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}