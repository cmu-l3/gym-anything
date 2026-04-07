#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_abc_cycle_counting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/abc_cycle_counting_locations_result.json')
    pass_threshold = metadata.get('pass_threshold', 75)
    
    score = 0
    feedback_parts = []
    
    # Read result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Setup/Export error: {result['error']}"}

    wh_stock_loc_id = result.get('wh_stock_loc_id')
    is_multi_loc_enabled = result.get('is_multi_loc_enabled', False)
    zones = result.get('zones', {})
    products = result.get('products', {})
    
    # Zone configuration checks (15 pts each)
    expected_zones = {
        'Zone A': 15,
        'Zone B': 30,
        'Zone C': 90
    }
    
    hierarchy_correct_count = 0
    
    for zone_name, expected_freq in expected_zones.items():
        zone_info = zones.get(zone_name)
        if zone_info:
            freq = zone_info.get('frequency', 0)
            parent_id = zone_info.get('parent_id')
            
            if freq == expected_freq:
                score += 15
                feedback_parts.append(f"PASS: {zone_name} configured with {freq} days frequency (+15)")
            else:
                feedback_parts.append(f"FAIL: {zone_name} frequency is {freq}, expected {expected_freq}")
                
            if parent_id == wh_stock_loc_id:
                hierarchy_correct_count += 1
        else:
            feedback_parts.append(f"FAIL: {zone_name} not found")
            
    # Product relocation checks (15 pts each)
    expected_moves = [
        ('ABC-A-001', 'Zone A', 10),
        ('ABC-B-001', 'Zone B', 50),
        ('ABC-C-001', 'Zone C', 200)
    ]
    
    for sku, target_zone, expected_qty in expected_moves:
        prod_quants = products.get(sku, [])
        target_zone_id = zones.get(target_zone, {}).get('id')
        
        qty_in_target = 0
        qty_elsewhere = 0
        
        for q in prod_quants:
            if q['loc_id'] == target_zone_id:
                qty_in_target += q['qty']
            else:
                qty_elsewhere += q['qty']
                
        if qty_in_target >= expected_qty and qty_elsewhere == 0:
            score += 15
            feedback_parts.append(f"PASS: {sku} correctly relocated to {target_zone} (+15)")
        elif qty_in_target > 0:
            score += 7  # Partial credit if some moved
            feedback_parts.append(f"PARTIAL: {sku} partially relocated to {target_zone} (+7)")
        else:
            feedback_parts.append(f"FAIL: {sku} not relocated to {target_zone} (found {qty_in_target})")
            
    # Hierarchy correct check (10 pts if all 3 are correct)
    if hierarchy_correct_count == 3:
        score += 10
        feedback_parts.append(f"PASS: Hierarchy correct, all zones parented to WH/Stock (+10)")
    elif hierarchy_correct_count > 0:
        partial = int(10 * hierarchy_correct_count / 3)
        score += partial
        feedback_parts.append(f"PARTIAL: Hierarchy correct for {hierarchy_correct_count}/3 zones (+{partial})")
    else:
        feedback_parts.append(f"FAIL: Hierarchy incorrect, zones not parented to WH/Stock")
        
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }