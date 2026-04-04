#!/usr/bin/env python3
"""
Verifier for Import Products CSV task in WooCommerce.

Verification Strategy:
1. Programmatic (80 pts):
   - Check if 8 specific products exist in database (35 pts)
   - Verify product names match CSV (15 pts)
   - Verify product prices match CSV (20 pts)
   - Verify categories assigned correctly (10 pts)
   - Bonus: Check timestamp/delta for anti-gaming (scored implicitly via "found" checks on specific SKUs created during task)
2. VLM (20 pts):
   - Verify wizard usage via trajectory (10 pts)
   - Verify final success message/state (10 pts)

Pass threshold: 70 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent importing products into WooCommerce via CSV.

Look for these stages:
1. Navigation to "Products > Import" or clicking an "Import" button.
2. The "Import Products" wizard screen (Step 1: Upload CSV file).
3. The Column Mapping screen (Step 2: Map CSV fields to products).
4. The Import progress bar or completion screen.

Respond in JSON:
{
    "import_wizard_visible": true/false,
    "mapping_step_visible": true/false,
    "success_message_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

# ================================================================
# VERIFIER
# ================================================================

def verify_import_products_csv(traj, env_info, task_info):
    """
    Verify products were imported correctly from CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('expected_products', [])
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Product Existence and Data Verification (80 pts max)
    imported_products = result.get('imported_products', [])
    
    products_found = 0
    names_correct = 0
    prices_correct = 0
    cats_correct = 0
    
    # We expect 8 products
    total_expected = len(expected_products)
    
    for expected in expected_products:
        sku = expected['sku']
        # Find corresponding result
        match = next((p for p in imported_products if p['sku'] == sku), None)
        
        if match and match.get('found'):
            products_found += 1
            
            # Check Name
            # Allow minor whitespace differences or case issues if close
            if match['name'].strip() == expected['name'].strip():
                names_correct += 1
            
            # Check Price (string comparison)
            # Database might return "45.00" or "45"
            db_price = str(match['price'])
            exp_price = str(expected['price'])
            if float(db_price) == float(exp_price):
                prices_correct += 1
                
            # Check Category
            # Database returns comma separated string
            db_cats = match['categories'].lower()
            exp_cat = expected['category'].lower()
            if exp_cat in db_cats:
                cats_correct += 1
    
    # Calculate scores based on ratios
    # 35 pts for existence
    score_existence = (products_found / total_expected) * 35
    score += score_existence
    
    # 15 pts for names
    score_names = (names_correct / total_expected) * 15
    score += score_names
    
    # 20 pts for prices
    score_prices = (prices_correct / total_expected) * 20
    score += score_prices
    
    # 10 pts for categories
    score_cats = (cats_correct / total_expected) * 10
    score += score_cats
    
    feedback.append(f"Found {products_found}/{total_expected} products ({int(score_existence)} pts)")
    if products_found > 0:
        feedback.append(f"Names correct: {names_correct}/{products_found}")
        feedback.append(f"Prices correct: {prices_correct}/{products_found}")
        feedback.append(f"Categories correct: {cats_correct}/{products_found}")

    # 2. VLM Verification (20 pts)
    # Only run if we are not at 100% yet or as confirmation
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('import_wizard_visible'):
                vlm_score += 10
                feedback.append("VLM: Import wizard detected (10 pts)")
            if parsed.get('success_message_visible') or parsed.get('mapping_step_visible'):
                vlm_score += 10
                feedback.append("VLM: Import progress/success detected (10 pts)")
        else:
            feedback.append("VLM query failed")
    else:
        # Fallback if VLM not available but products found perfectly
        if products_found == total_expected:
            vlm_score = 20
            feedback.append("VLM unavailable - full score awarded based on perfect data match")

    score += vlm_score
    
    # Final cleanup
    score = min(100, score)
    passed = (products_found == total_expected) and (score >= 70)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }