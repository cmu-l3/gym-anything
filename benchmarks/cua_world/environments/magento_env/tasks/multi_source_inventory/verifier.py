#!/usr/bin/env python3
"""Verifier for Multi-Source Inventory (MSI) task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_source_inventory(traj, env_info, task_info):
    """
    Verify MSI configuration: Sources, Stocks, and Product Assignments.
    
    Scoring Breakdown (100 pts total):
    1. Sources Created (24 pts): east_coast_wh (12), west_coast_wh (12)
    2. Source Details (16 pts): Correct Location Data (8 each)
    3. Stock Created (10 pts): US Regional Stock
    4. Stock Linked (15 pts): Both sources linked to stock
    5. Inventory Assigned (35 pts): Quantities correct for 3 products
    
    Pass threshold: 55 points (Allows passing if configuration is done but product assignment partially fails)
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/msi_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result data: {result}")
    
    score = 0
    feedback_parts = []
    
    # Metadata for verification
    metadata = task_info.get('metadata', {})
    expected_sources = metadata.get('sources', [])
    expected_stock_name = metadata.get('stock', {}).get('name', 'US Regional Stock')
    expected_inventory = metadata.get('inventory', {})
    
    # 1. Verify Sources (40 pts total)
    found_sources = {s['source_code']: s for s in result.get('sources', [])}
    
    for expected in expected_sources:
        code = expected['code']
        name = expected['name']
        if code in found_sources:
            # Source exists (12 pts)
            score += 12
            s_data = found_sources[code]
            
            # Check details (8 pts)
            # Region check is loose (substring) because Magento stores full names vs codes
            region_match = expected['region_sub'].lower() in s_data.get('region', '').lower()
            city_match = expected['city'].lower() == s_data.get('city', '').lower()
            postcode_match = expected['postcode'] in s_data.get('postcode', '')
            enabled_match = str(s_data.get('enabled', '0')) == '1'
            
            if region_match and city_match and postcode_match and enabled_match:
                score += 8
                feedback_parts.append(f"Source '{name}' created with correct details")
            else:
                feedback_parts.append(f"Source '{name}' created but has incorrect details (Region/City/Postcode/Enabled)")
        else:
            feedback_parts.append(f"Source '{name}' ({code}) NOT found")

    # 2. Verify Stock (10 pts)
    if result.get('stock_found'):
        score += 10
        feedback_parts.append(f"Stock '{expected_stock_name}' created")
    else:
        feedback_parts.append(f"Stock '{expected_stock_name}' NOT found")
        
    # 3. Verify Links (15 pts)
    # Both sources must be linked to the stock for full points
    stock_links = [l['source_code'] for l in result.get('stock_links', [])]
    east_linked = 'east_coast_wh' in stock_links
    west_linked = 'west_coast_wh' in stock_links
    
    if east_linked and west_linked:
        score += 15
        feedback_parts.append("Both sources linked to stock")
    elif east_linked or west_linked:
        score += 7
        feedback_parts.append("Partial: Only one source linked to stock")
    else:
        feedback_parts.append("Sources NOT linked to stock")

    # 4. Verify Inventory Quantities (35 pts)
    # Strategy: Total 6 assignments (3 products * 2 sources). ~5.8 pts each.
    # Grouped by Source for simpler feedback.
    
    found_items = result.get('inventory_items', [])
    # Map: sku -> source -> qty
    item_map = {}
    for item in found_items:
        s = item['sku']
        src = item['source_code']
        qty = float(item['quantity'])
        if s not in item_map: item_map[s] = {}
        item_map[s][src] = qty

    # East Coast Check (17 pts)
    east_correct_count = 0
    east_total_checks = 3
    
    # West Coast Check (18 pts)
    west_correct_count = 0
    west_total_checks = 3
    
    for sku, assignments in expected_inventory.items():
        # Check East
        exp_east = assignments.get('east_coast_wh')
        actual_east = item_map.get(sku, {}).get('east_coast_wh')
        if actual_east is not None and abs(actual_east - exp_east) <= 5:
            east_correct_count += 1
            
        # Check West
        exp_west = assignments.get('west_coast_wh')
        actual_west = item_map.get(sku, {}).get('west_coast_wh')
        if actual_west is not None and abs(actual_west - exp_west) <= 5:
            west_correct_count += 1
            
    # Calc scores
    if east_correct_count == 3:
        score += 17
        feedback_parts.append("East Coast inventory correct")
    elif east_correct_count > 0:
        partial = int(17 * (east_correct_count / 3))
        score += partial
        feedback_parts.append(f"East Coast inventory partial ({east_correct_count}/3)")
        
    if west_correct_count == 3:
        score += 18
        feedback_parts.append("West Coast inventory correct")
    elif west_correct_count > 0:
        partial = int(18 * (west_correct_count / 3))
        score += partial
        feedback_parts.append(f"West Coast inventory partial ({west_correct_count}/3)")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }