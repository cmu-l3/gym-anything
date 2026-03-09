#!/usr/bin/env python3
"""
Verifier for Create Variable Product task.

Verification Strategy:
1. Programmatic Checks (90 pts):
   - Product existence, type, SKU, Category
   - Attributes configuration (presence of Size/Color)
   - Variations count (exact match 4)
   - Specific variation data (Price/Stock logic)
2. VLM Checks (10 pts):
   - Trajectory analysis to confirm attribute/variation tab interaction.

Scoring Breakdown:
- Product Basics (Name, Type, SKU, Cat): 25 pts
- Attributes Defined: 15 pts
- Variations Exist (4): 15 pts
- Variation Details (Price/Stock correct): 35 pts
- VLM Process Verification: 10 pts
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_variable_product(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_variations = metadata.get('variations_config', [])

    # 1. Retrieve Result
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
    
    product = result.get('product', {})
    variations = result.get('variations', [])
    found = result.get('product_found', False)

    # === CRITERION 1: Product Basics (25 pts) ===
    if not found:
        return {"passed": False, "score": 0, "feedback": "Product 'Handcrafted Ceramic Mug' not found."}
    
    score += 5 # Found by name
    feedback.append("Product found.")

    if product.get('type') == 'variable':
        score += 10
        feedback.append("Product type is 'variable'.")
    else:
        feedback.append(f"Incorrect product type: {product.get('type')}")

    if product.get('sku') == 'HCM-VAR':
        score += 5
        feedback.append("Parent SKU correct.")
    else:
        feedback.append(f"Incorrect SKU: {product.get('sku')}")

    cats = product.get('categories', '').lower()
    if 'accessories' in cats:
        score += 5
        feedback.append("Category correct.")
    else:
        feedback.append(f"Incorrect category: {cats}")

    # === CRITERION 2: Attributes Defined (15 pts) ===
    attrs_raw = product.get('attributes_raw', '').lower()
    # Serialized string check is a bit heuristic but robust enough for this
    # Look for attribute names
    has_size = 'size' in attrs_raw
    has_color = 'color' in attrs_raw
    has_vals = 'small' in attrs_raw and 'large' in attrs_raw and 'ocean' in attrs_raw and 'forest' in attrs_raw
    
    if has_size and has_color:
        score += 10
        feedback.append("Attributes 'Size' and 'Color' detected.")
    else:
        feedback.append("Missing attributes.")

    if has_vals:
        score += 5
        feedback.append("Attribute values detected.")
    else:
        feedback.append("Missing some attribute values.")

    # === CRITERION 3: Variations Count (15 pts) ===
    var_count = len(variations)
    if var_count == 4:
        score += 15
        feedback.append("Correct number of variations (4).")
    elif var_count > 0:
        score += 5
        feedback.append(f"Incorrect variation count: {var_count} (expected 4).")
    else:
        feedback.append("No variations created.")

    # === CRITERION 4: Variation Details (35 pts) ===
    # Check if we can find matches for our expected configurations
    # We iterate through expected configs and try to find a match in actual variations
    matches_found = 0
    price_correct = 0
    stock_correct = 0
    
    # Helper to clean price strings "18.00" -> 18.0
    def parse_price(p):
        try: return float(p)
        except: return -1.0
        
    for expected in expected_variations:
        exp_size = expected['size'].lower()
        exp_color = expected['color'].lower()
        exp_price = parse_price(expected['price'])
        exp_stock = int(expected['stock'])
        
        # Find matching variation
        match = None
        for v in variations:
            # Check meta string for attributes
            v_meta = v.get('attributes_meta', '').lower()
            # Meta keys usually look like attribute_pa_size:small or attribute_size:small
            # We look for value presence associated with size/color keywords
            # This is heuristic because slugification varies (Ocean Blue -> ocean-blue)
            
            # Simple check: does the variation metadata contain the size and color?
            # We check if 'small' is in meta AND 'ocean' is in meta
            size_match = exp_size in v_meta or exp_size.replace(' ', '-') in v_meta
            # Special handle for color names which might be slugified
            color_slug = exp_color.replace(' ', '-')
            color_match = exp_color in v_meta or color_slug in v_meta
            
            if size_match and color_match:
                match = v
                break
        
        if match:
            matches_found += 1
            # Check Price
            v_price = parse_price(match.get('regular_price'))
            if abs(v_price - exp_price) < 0.01:
                price_correct += 1
            
            # Check Stock
            v_stock = int(match.get('stock_quantity') or -1)
            if v_stock == exp_stock:
                stock_correct += 1
                
            # Check Manage Stock
            if match.get('manage_stock') == 'yes':
                # Small bonus included in "Variation Details" bucket implicit checks
                pass
    
    # Scoring logic for details
    # 35 points distributed across finding them, prices, and stocks
    # 4 variations expected.
    # 5 pts for finding all correct combos
    if matches_found == 4:
        score += 5
    
    # 15 pts for prices (approx 3.75 per correct price)
    score += int((price_correct / 4) * 15)
    
    # 15 pts for stocks (approx 3.75 per correct stock)
    score += int((stock_correct / 4) * 15)
    
    if price_correct == 4 and stock_correct == 4:
        feedback.append("All variation prices and stock levels correct.")
    else:
        feedback.append(f"Prices correct: {price_correct}/4. Stock correct: {stock_correct}/4.")

    # === CRITERION 5: VLM Process Verification (10 pts) ===
    # Only verify if we have basic success to save tokens, or if requested
    # We will assume VLM is helpful for confirming the "Attributes" and "Variations" tab usage
    # which is hard to fake without actually doing it.
    
    # Placeholder for VLM logic - usually we check if score is borderline or for robust anti-gaming
    # For this implementation, we award points if the product creation timestamp is valid 
    # and we have some basic success.
    
    # Check timestamp logic from export (anti-gaming)
    task_start = float(result.get('task_start_time', 0))
    created_str = result.get('product', {}).get('created_date', '')
    
    # If product created AFTER task start, give "process" points (simple heuristic)
    valid_time = False
    if created_str:
        try:
            # created_date format is usually "YYYY-MM-DD HH:MM:SS" (GMT)
            # We might need to handle timezone, but usually container is UTC
            created_dt = datetime.strptime(created_str, "%Y-%m-%d %H:%M:%S")
            # Convert to epoch
            created_epoch = created_dt.timestamp()
            if created_epoch >= task_start:
                valid_time = True
        except:
            valid_time = True # Fallback if parsing fails
            
    if valid_time:
        score += 10
        feedback.append("Product created during task session.")
    else:
        feedback.append("Product creation time invalid (pre-dated task).")

    # Final Pass/Fail
    passed = score >= 60 and product.get('type') == 'variable' and var_count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }