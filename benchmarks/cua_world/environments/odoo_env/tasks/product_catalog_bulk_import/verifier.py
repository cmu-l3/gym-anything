#!/usr/bin/env python3
"""
Verifier for product_catalog_bulk_import task.

Scoring System (100 points total):
1. Import Volume (30 pts): 2 pts per correct SKU found (max 30).
2. Price Accuracy (20 pts): Sales Price matches CSV.
3. Cost Accuracy (20 pts): Cost matches CSV.
4. Category Mapping (15 pts): Categories match CSV (and were created).
5. VLM Trajectory (15 pts): Visual confirmation of import wizard usage.

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Import VLM utils from framework
try:
    from vlm_utils import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False}
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth data from setup script
GROUND_TRUTH = {
    'PEN-GEL-BLK': {'rrp': 2.50, 'cost': 0.85, 'cat': 'Writing Instruments'},
    'PAP-A4-500': {'rrp': 6.99, 'cost': 3.50, 'cat': 'Office Paper'},
    'DSK-ORG-MESH': {'rrp': 14.99, 'cost': 6.50, 'cat': 'Desk Accessories'},
    'COR-TAPE-5MM': {'rrp': 2.25, 'cost': 0.75, 'cat': 'Writing Instruments'},
    'NB-SPI-RUL': {'rrp': 3.50, 'cost': 1.10, 'cat': 'Office Paper'}
}

def verify_product_catalog_bulk_import(traj, env_info, task_info):
    """Verify that products were imported correctly from CSV."""
    
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Programmatic Criteria
    
    # Criterion 1: Import Volume (30 pts)
    found_count = result.get("found_count", 0)
    # Cap at 15
    volume_score = min(30, found_count * 2)
    score += volume_score
    feedback_parts.append(f"Imported {found_count}/15 products ({volume_score}/30 pts)")
    
    if found_count == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No products found. Import failed completely."
        }

    # Data Quality Checks (Price, Cost, Category)
    product_data = result.get("product_data", {})
    
    total_checks = 0
    price_matches = 0
    cost_matches = 0
    cat_matches = 0
    
    # We check all found products against our subset of ground truth or general logic
    # Since we have the full map in the verifier logic below for all items:
    FULL_CSV_MAP = {
        'PEN-GEL-BLK': (2.50, 0.85, 'Writing Instruments'),
        'PEN-GEL-BLU': (2.50, 0.85, 'Writing Instruments'),
        'PEN-GEL-RED': (2.50, 0.85, 'Writing Instruments'),
        'PCL-MECH-05': (4.25, 1.50, 'Writing Instruments'),
        'REF-LEAD-HB': (1.20, 0.40, 'Writing Instruments'),
        'PAP-A4-500': (6.99, 3.50, 'Office Paper'),
        'PAP-A3-100': (12.50, 6.00, 'Office Paper'),
        'NOT-STK-YEL': (1.99, 0.50, 'Office Paper'),
        'NB-SPI-RUL': (3.50, 1.10, 'Office Paper'),
        'DSK-TAPE-DISP': (8.99, 3.20, 'Desk Accessories'),
        'DSK-STAP-STD': (7.50, 2.80, 'Desk Accessories'),
        'REF-STAP-266': (2.99, 0.90, 'Desk Accessories'),
        'DSK-ORG-MESH': (14.99, 6.50, 'Desk Accessories'),
        'MRK-WHT-SET': (5.99, 2.20, 'Writing Instruments'),
        'COR-TAPE-5MM': (2.25, 0.75, 'Writing Instruments')
    }
    
    for sku, p_info in product_data.items():
        if sku in FULL_CSV_MAP:
            total_checks += 1
            expected_price, expected_cost, expected_cat = FULL_CSV_MAP[sku]
            
            # Check Price (allow small float diff)
            if abs(float(p_info.get('list_price', 0)) - expected_price) < 0.05:
                price_matches += 1
                
            # Check Cost
            if abs(float(p_info.get('standard_price', 0)) - expected_cost) < 0.05:
                cost_matches += 1
                
            # Check Category (flexible match)
            # Odoo might display "All / Saleable / Office Paper"
            actual_cat = p_info.get('category', '').lower()
            if expected_cat.lower() in actual_cat:
                cat_matches += 1

    # Normalize scores based on items found
    if total_checks > 0:
        # Criterion 2: Price Accuracy (20 pts)
        price_score = int((price_matches / total_checks) * 20)
        score += price_score
        feedback_parts.append(f"Price accuracy: {price_matches}/{total_checks} correct ({price_score}/20 pts)")
        
        # Criterion 3: Cost Accuracy (20 pts)
        cost_score = int((cost_matches / total_checks) * 20)
        score += cost_score
        feedback_parts.append(f"Cost accuracy: {cost_matches}/{total_checks} correct ({cost_score}/20 pts)")
        
        # Criterion 4: Category Mapping (15 pts)
        cat_score = int((cat_matches / total_checks) * 15)
        score += cat_score
        feedback_parts.append(f"Category mapping: {cat_matches}/{total_checks} correct ({cat_score}/15 pts)")
    
    # 3. VLM Verification (15 pts)
    # Check if the agent actually used the import wizard
    frames = sample_trajectory_frames(traj, 5)
    vlm_prompt = """
    Look at these screenshots of a user interacting with Odoo.
    Did the user perform a bulk data import?
    Look for:
    1. The 'Import records' page or button.
    2. A CSV file upload screen.
    3. The Import Mapping configuration table (columns like 'File Column' -> 'Odoo Field').
    4. A success message like 'Everything seems valid' or 'records successfully imported'.
    
    Answer JSON: {"import_wizard_visible": bool, "mapping_screen_visible": bool, "success": bool}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("import_wizard_visible") or parsed.get("mapping_screen_visible"):
            vlm_score = 15
            feedback_parts.append("VLM: Import wizard usage confirmed (15/15 pts)")
        else:
            feedback_parts.append("VLM: Could not visually confirm import wizard usage (0/15 pts)")
    else:
        # Fallback if VLM fails but data is good, give benefit of doubt if data is perfect
        if found_count >= 13:
            vlm_score = 15
            feedback_parts.append("VLM skipped but data confirms import (15/15 pts)")
            
    score += vlm_score

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }