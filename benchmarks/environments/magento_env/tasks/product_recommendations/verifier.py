#!/usr/bin/env python3
"""Verifier for Product Recommendations task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_product_recommendations(traj, env_info, task_info):
    """
    Verify that the product recommendations are correctly configured.
    
    Expected configuration for PHONE-001:
    - Related (Type 1): HEADPHONES-001, BOTTLE-001
    - Up-Sell (Type 4): LAPTOP-001
    - Cross-Sell (Type 5): LAMP-001, TSHIRT-001, YOGA-001
    
    Scoring:
    - Each correct link: Points based on task difficulty
    - Penalties for extraneous links
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata defines expectations
    metadata = task_info.get('metadata', {})
    expected_links = metadata.get('expected_links', {})
    link_type_map = metadata.get('link_type_map', {"1": "related", "4": "upsell", "5": "crosssell"})

    # Flatten expectations for easier processing
    # Map: type_name -> set of SKUs
    expectations = {
        "related": set(expected_links.get("related", [])),
        "upsell": set(expected_links.get("upsell", [])),
        "crosssell": set(expected_links.get("crosssell", []))
    }
    
    # Points per correct link
    points_map = {
        "related": 15,    # 2 items * 15 = 30
        "upsell": 20,     # 1 item * 20 = 20
        "crosssell": 10   # 3 items * 10 = 30
                          # Total = 80 + 20 bonus for cleanliness = 100
    }

    try:
        # Load result
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/prod_recs_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
        
        logger.info(f"Result data: {result}")
        
        if not result.get("product_found", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Target product PHONE-001 not found in database."
            }
            
        # Parse actual links from result
        # Structure: [{"type_id": "1", "sku": "ABC"}, ...]
        actual_links = result.get("links", [])
        
        # Categorize actual links
        # Map: type_name -> set of SKUs
        actuals = {
            "related": set(),
            "upsell": set(),
            "crosssell": set()
        }
        
        extraneous_count = 0
        
        for link in actual_links:
            type_id = str(link.get("type_id", ""))
            sku = link.get("sku", "").strip()
            
            type_name = link_type_map.get(type_id)
            if type_name:
                actuals[type_name].add(sku)
            else:
                # Unknown link type (unlikely in standard magento)
                extraneous_count += 1

        # Calculate score
        score = 0
        feedback_parts = []
        
        # Check Related
        for sku in expectations["related"]:
            if sku in actuals["related"]:
                score += 15
                feedback_parts.append(f"✓ Related: {sku}")
            else:
                feedback_parts.append(f"✗ Missing Related: {sku}")
        
        # Check Up-Sell
        for sku in expectations["upsell"]:
            if sku in actuals["upsell"]:
                score += 20
                feedback_parts.append(f"✓ Up-Sell: {sku}")
            else:
                feedback_parts.append(f"✗ Missing Up-Sell: {sku}")

        # Check Cross-Sell
        for sku in expectations["crosssell"]:
            if sku in actuals["crosssell"]:
                score += 10 # Slightly lower per item as there are more
                feedback_parts.append(f"✓ Cross-Sell: {sku}")
            else:
                feedback_parts.append(f"✗ Missing Cross-Sell: {sku}")

        # Check for extraneous links (wrong type or wrong product)
        # Iterate over all actuals and check if they are expected
        current_extraneous = 0
        for type_name, skus in actuals.items():
            for sku in skus:
                if sku not in expectations[type_name]:
                    current_extraneous += 1
                    feedback_parts.append(f"⚠ Extraneous {type_name}: {sku}")
        
        current_extraneous += extraneous_count
        
        # Bonus for no extraneous links (Cleanliness)
        # We award up to 20 points if the result is perfect with no extra junk
        if current_extraneous == 0 and score > 0:
            score += 20
            feedback_parts.append("✓ Clean configuration (no extra links)")
        elif current_extraneous > 0:
            # Penalty logic: -5 per extra link, but don't go below 0
            penalty = current_extraneous * 5
            score = max(0, score - penalty)
            feedback_parts.append(f"Penalty: -{penalty} pts for {current_extraneous} incorrect links")

        # Cap score at 100
        score = min(100, score)
        
        # Pass threshold
        passed = score >= 60
        
        # Check if any work was done
        initial_count = result.get("initial_count", 0)
        current_count = result.get("current_count", 0)
        
        if current_count == 0 and initial_count == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No product recommendations were added."
            }

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}