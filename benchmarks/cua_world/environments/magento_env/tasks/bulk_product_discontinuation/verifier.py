#!/usr/bin/env python3
"""
Verifier for Bulk Product Discontinuation Task.

Goal:
1. All 25 'LEG-' products must be Disabled (status=2) and Tax Class None (tax_class=0).
2. All 15 'CORE-' products must remain Enabled (status=1) and Tax Class Taxable Goods (tax_class=2).

Scoring:
- Legacy Status: 40 points (pro-rated)
- Legacy Tax Class: 40 points (pro-rated)
- Core Integrity: 20 points (all or nothing per product)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/bulk_update_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}

    # Targets
    legacy_products = result.get('legacy_products', [])
    core_products = result.get('core_products', [])
    
    # Expected counts (from Setup)
    expected_legacy_count = 25
    expected_core_count = 15
    
    # Counters
    legacy_status_ok = 0
    legacy_tax_ok = 0
    core_ok = 0
    
    feedback_parts = []
    
    # 1. Verify Legacy Products
    if not legacy_products:
        feedback_parts.append("CRITICAL: No Legacy products found in database.")
    
    for p in legacy_products:
        sku = p.get('sku', 'Unknown')
        status = str(p.get('status', '1')).strip() # 1=Enabled, 2=Disabled
        tax = str(p.get('tax_class', '2')).strip() # 0=None, 2=Taxable Goods
        
        # Check Status (Should be 2)
        if status == '2':
            legacy_status_ok += 1
        
        # Check Tax (Should be 0)
        if tax == '0':
            legacy_tax_ok += 1
            
    # 2. Verify Core Products
    for p in core_products:
        status = str(p.get('status', '1')).strip()
        tax = str(p.get('tax_class', '2')).strip()
        
        # Should be Enabled(1) and Taxable(2)
        if status == '1' and tax == '2':
            core_ok += 1
            
    # Scoring Calculation
    # Max Points: 100
    # Legacy Status: 40 pts
    # Legacy Tax: 40 pts
    # Core Integrity: 20 pts
    
    score_status = 0
    if len(legacy_products) > 0:
        score_status = (legacy_status_ok / len(legacy_products)) * 40
        
    score_tax = 0
    if len(legacy_products) > 0:
        score_tax = (legacy_tax_ok / len(legacy_products)) * 40
        
    score_core = 0
    if len(core_products) > 0:
        score_core = (core_ok / len(core_products)) * 20
        
    total_score = round(score_status + score_tax + score_core)
    
    # Feedback Generation
    feedback_parts.append(f"Legacy Products Disabled: {legacy_status_ok}/{len(legacy_products)}")
    feedback_parts.append(f"Legacy Products Tax Removed: {legacy_tax_ok}/{len(legacy_products)}")
    feedback_parts.append(f"Core Products Untouched: {core_ok}/{len(core_products)}")
    
    if legacy_status_ok == 20 and expected_legacy_count == 25:
        feedback_parts.append("WARNING: It looks like you only updated the first page of results (20 items) and missed the remaining 5.")

    passed = total_score >= 85
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }