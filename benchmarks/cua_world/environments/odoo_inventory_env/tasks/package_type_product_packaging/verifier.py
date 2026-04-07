#!/usr/bin/env python3
"""
Verifier for Package Type and Product Packaging task in Odoo 17.

Scoring (100 pts total, pass threshold: 60):
- Small Shipping Box exists with correct name (3 pts)
- Small Shipping Box dimensions/weight correct (7 pts)
- Medium Shipping Box exists with correct name (3 pts)
- Medium Shipping Box dimensions/weight correct (7 pts)
- Large Shipping Crate exists with correct name (3 pts)
- Large Shipping Crate dimensions/weight correct (7 pts)
- 7x Product Packaging Records correct product, package type, and qty (10 pts each)

Anti-gaming:
Setup script drops all existing package types and packagings. Any records found
were successfully created by the agent.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_package_type_product_packaging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/package_type_result.json')
    pass_threshold = metadata.get('pass_threshold', 60)

    score = 0
    feedback_parts = []
    subscores = {}

    # Read export result
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        if os.path.exists(local_path): os.unlink(local_path)
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(local_path): os.unlink(local_path)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    package_types = result.get('package_types', [])
    if not isinstance(package_types, list): package_types = []
    
    product_packagings = result.get('product_packagings', [])
    if not isinstance(product_packagings, list): product_packagings = []

    # 1. Verify Package Types (30 points total)
    expected_package_types = {
        'small shipping box': {'l': 30, 'w': 25, 'h': 20, 'wt': 10},
        'medium shipping box': {'l': 60, 'w': 40, 'h': 35, 'wt': 25},
        'large shipping crate': {'l': 120, 'w': 80, 'h': 60, 'wt': 50}
    }

    pt_eval = {}
    for pt in package_types:
        name = pt.get('name', '').strip().lower()
        if name in expected_package_types and name not in pt_eval:
            pt_eval[name] = {'exists': True, 'dims_ok': False}
            exp = expected_package_types[name]
            
            # Odoo 17 fields fallback checks
            l = pt.get('packaging_length') or pt.get('length') or 0
            w = pt.get('width', 0)
            h = pt.get('height', 0)
            wt = pt.get('max_weight', 0)
            
            # +/- 0.5 tolerance
            if (abs(l - exp['l']) <= 0.5 and abs(w - exp['w']) <= 0.5 and 
                abs(h - exp['h']) <= 0.5 and abs(wt - exp['wt']) <= 0.5):
                pt_eval[name]['dims_ok'] = True

    for expected_name in expected_package_types:
        if expected_name in pt_eval:
            score += 3
            if pt_eval[expected_name]['dims_ok']:
                score += 7
                subscores[f"pt_{expected_name}"] = 10
                feedback_parts.append(f"PASS: {expected_name.title()} created with correct dimensions (+10)")
            else:
                subscores[f"pt_{expected_name}"] = 3
                feedback_parts.append(f"PARTIAL: {expected_name.title()} created but dimensions/weight incorrect (+3)")
        else:
            subscores[f"pt_{expected_name}"] = 0
            feedback_parts.append(f"FAIL: {expected_name.title()} missing")

    # 2. Verify Product Packaging (70 points total)
    expected_packagings = [
        ('PKG-DRILL-001', 'small shipping box', 1),
        ('PKG-DRILL-001', 'medium shipping box', 4),
        ('PKG-SAW-001', 'large shipping crate', 1),
        ('PKG-LASER-001', 'small shipping box', 2),
        ('PKG-LASER-001', 'medium shipping box', 8),
        ('PKG-CHISEL-001', 'small shipping box', 3),
        ('PKG-CHISEL-001', 'medium shipping box', 12),
    ]

    matched_packs = set()
    for pkg in product_packagings:
        code = pkg.get('product_code', '')
        pt_name = pkg.get('package_type_name', '').strip().lower()
        qty = pkg.get('qty', 0)
        
        for idx, (exp_code, exp_pt, exp_qty) in enumerate(expected_packagings):
            if idx not in matched_packs:
                if code == exp_code and pt_name == exp_pt and abs(qty - exp_qty) <= 0.1:
                    matched_packs.add(idx)
                    score += 10
                    break

    pack_matches = len(matched_packs)
    if pack_matches == len(expected_packagings):
        feedback_parts.append(f"PASS: All 7 product packagings configured correctly (+70)")
    elif pack_matches > 0:
        feedback_parts.append(f"PARTIAL: {pack_matches}/7 product packagings configured correctly (+{pack_matches * 10})")
    else:
        feedback_parts.append(f"FAIL: No correct product packagings found")

    subscores["packagings_matched"] = pack_matches

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }