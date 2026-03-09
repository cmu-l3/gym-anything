#!/usr/bin/env python3
"""Verifier for Bulk Product Import task in Magento."""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_product_import(traj, env_info, task_info):
    """
    Verify bulk product import results.
    
    Scoring:
    1. Products Imported (existence): 40 pts (3.33 pts per SKU)
    2. Correct Prices: 25 pts (~2.08 pts per SKU)
    3. Correct Stock Quantities: 20 pts (~1.67 pts per SKU)
    4. Products Enabled & Visible: 15 pts
    
    Pass threshold: 60 points
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_prices = metadata.get('expected_prices', {})
    expected_qtys = metadata.get('expected_qtys', {})
    
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/import_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    products = result.get('products', [])
    initial_count = int(result.get('initial_kitchen_count', 0))
    current_count = int(result.get('current_kitchen_count', 0))
    
    # 1. Existence Score (Max 40)
    found_count = sum(1 for p in products if p.get('found'))
    existence_score = 0
    if found_count >= 12:
        existence_score = 40
    elif found_count >= 8:
        existence_score = (found_count / 12) * 40
    else:
        # Penalize more heavily if fewer than 8 found
        existence_score = (found_count / 12) * 20 

    # 2. Price Score (Max 25)
    price_matches = 0
    for p in products:
        if not p.get('found'): continue
        sku = p.get('sku')
        actual_price = float(p.get('price', 0))
        expected_price = float(expected_prices.get(sku, 0))
        if abs(actual_price - expected_price) < 0.1:
            price_matches += 1
            
    price_score = (price_matches / 12) * 25

    # 3. Qty Score (Max 20)
    qty_matches = 0
    for p in products:
        if not p.get('found'): continue
        sku = p.get('sku')
        actual_qty = float(p.get('qty', 0))
        expected_qty = float(expected_qtys.get(sku, 0))
        if actual_qty == expected_qty:
            qty_matches += 1
            
    qty_score = (qty_matches / 12) * 20

    # 4. Status/Visibility Score (Max 15)
    sv_matches = 0
    for p in products:
        if not p.get('found'): continue
        status = str(p.get('status', '0')).strip()
        visibility = str(p.get('visibility', '0')).strip()
        # Status 1=Enabled, Visibility 4=Catalog,Search
        if status == '1' and visibility == '4':
            sv_matches += 1
            
    sv_score = 0
    if sv_matches >= 12:
        sv_score = 15
    elif sv_matches >= 10:
        sv_score = 10
    elif sv_matches >= 8:
        sv_score = 5

    total_score = existence_score + price_score + qty_score + sv_score
    total_score = min(100, round(total_score))
    
    # Verify new data
    new_data_check = current_count > initial_count
    
    feedback = (
        f"Score: {total_score}/100. "
        f"Imported {found_count}/12 products. "
        f"Prices correct: {price_matches}/12. "
        f"Qtys correct: {qty_matches}/12. "
        f"Config correct: {sv_matches}/12."
    )
    
    if not new_data_check and found_count > 0:
         feedback += " WARNING: Product count did not increase (pre-existing data?)."

    passed = total_score >= 60 and new_data_check

    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "found": found_count,
            "price_ok": price_matches,
            "qty_ok": qty_matches,
            "config_ok": sv_matches
        }
    }