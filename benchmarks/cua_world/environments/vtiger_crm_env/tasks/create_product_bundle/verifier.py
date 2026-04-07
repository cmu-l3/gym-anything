#!/usr/bin/env python3
"""
Verifier for create_product_bundle task.

Evaluates database state for the creation of a parent product and 
the relational mapping to existing child products (Product Bundles).
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_product_bundle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_part_number = metadata.get('expected_part_number', 'KIT-SH-001')
    expected_price = float(metadata.get('expected_price', 149.99))
    expected_stock = float(metadata.get('expected_stock', 100))
    expected_unit = metadata.get('expected_unit', 'Pack')
    
    child_1 = metadata.get('child_product_1', 'Smart Hub Pro')
    child_2 = metadata.get('child_product_2', 'RGB Smart Bulb')
    child_3 = metadata.get('child_product_3', 'WiFi Smart Plug')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_bundle_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Product Exists (20 pts)
    product_found = result.get('product_found', False)
    if not product_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Parent product 'Smart Home Starter Kit' was not found in the CRM."
        }
    
    score += 20
    feedback_parts.append("Parent product created")

    # Criterion 2: Correct Detail Fields (20 pts total)
    part_number = result.get('part_number', '')
    if part_number == expected_part_number:
        score += 5
        feedback_parts.append("Part Number matches")
    else:
        feedback_parts.append(f"Part Number incorrect (Expected {expected_part_number}, got {part_number})")

    try:
        unit_price = float(result.get('unit_price', 0))
    except ValueError:
        unit_price = 0.0
    
    if abs(unit_price - expected_price) < 0.05:
        score += 5
        feedback_parts.append("Unit Price matches")
    else:
        feedback_parts.append(f"Unit Price incorrect (Got {unit_price})")

    try:
        qty_stock = float(result.get('qty_in_stock', 0))
    except ValueError:
        qty_stock = 0.0
    
    if abs(qty_stock - expected_stock) < 0.5:
        score += 5
        feedback_parts.append("Stock matches")
    else:
        feedback_parts.append(f"Stock incorrect (Got {qty_stock})")
        
    usage_unit = result.get('usage_unit', '')
    if usage_unit == expected_unit:
        score += 5
        feedback_parts.append("Usage Unit matches")

    # Criterion 3: Child products linked (15 pts each)
    linked_se = result.get('linked_seproducts', '')
    linked_crm = result.get('linked_crmentityrel', '')
    linked_rev = result.get('linked_seproducts_rev', '')
    
    # Combine all found relationships across all valid CRM schema pathways
    all_linked_raw = f"{linked_se},{linked_crm},{linked_rev}"
    linked_list = [x.strip() for x in all_linked_raw.split(',') if x.strip()]
    unique_linked = set(linked_list)
    
    has_child_1 = child_1 in unique_linked
    has_child_2 = child_2 in unique_linked
    has_child_3 = child_3 in unique_linked
    
    if has_child_1:
        score += 15
        feedback_parts.append(f"Child 1 ({child_1}) linked")
    else:
        feedback_parts.append(f"Child 1 ({child_1}) missing")

    if has_child_2:
        score += 15
        feedback_parts.append(f"Child 2 ({child_2}) linked")
    else:
        feedback_parts.append(f"Child 2 ({child_2}) missing")

    if has_child_3:
        score += 15
        feedback_parts.append(f"Child 3 ({child_3}) linked")
    else:
        feedback_parts.append(f"Child 3 ({child_3}) missing")
        
    # Criterion 4: Exact relationships (No extras) (5 pts)
    if has_child_1 and has_child_2 and has_child_3 and len(unique_linked) == 3:
        score += 5
        feedback_parts.append("Exactly 3 child products linked")
    elif len(unique_linked) > 3:
        feedback_parts.append(f"Extra unknown products linked (Found {len(unique_linked)})")

    # Criterion 5: Anti-gaming / Product Count (10 pts)
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    new_products = current_count - initial_count
    
    if new_products == 1:
        score += 10
        feedback_parts.append("Only the parent product was newly created")
    elif new_products > 1:
        feedback_parts.append(f"WARNING: {new_products} new products were created instead of just 1.")
    else:
        feedback_parts.append("No new products created overall.")

    passed = score >= 75 and product_found and (has_child_1 or has_child_2 or has_child_3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }