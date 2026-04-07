#!/usr/bin/env python3
"""Verifier for supplier_procurement_setup task."""

import json
import tempfile
import os
import re
import logging

logger = logging.getLogger(__name__)

def parse_tsv(filepath, headers):
    """Safely parse TSV file into a list of dictionaries."""
    results = []
    if not os.path.exists(filepath):
        return results
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            # Pad parts if there are missing trailing columns
            parts += [''] * (len(headers) - len(parts))
            results.append(dict(zip(headers, parts)))
    return results

def normalize_phone(phone_str):
    """Strip everything except digits to compare phone numbers."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', phone_str)

def verify_supplier_procurement_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # Prepare temporary paths
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_suppliers = tempfile.NamedTemporaryFile(delete=False, suffix='.tsv').name
    temp_assets = tempfile.NamedTemporaryFile(delete=False, suffix='.tsv').name

    try:
        # Copy files from container
        copy_from_env("/tmp/task_result.json", temp_json)
        copy_from_env("/tmp/suppliers_dump.tsv", temp_suppliers)
        copy_from_env("/tmp/assets_dump.tsv", temp_assets)

        with open(temp_json, 'r') as f:
            result_meta = json.load(f)
            
        suppliers_data = parse_tsv(temp_suppliers, ['name', 'city', 'state', 'zip', 'email', 'phone', 'url', 'notes'])
        assets_data = parse_tsv(temp_assets, ['asset_tag', 'order_number', 'supplier_name'])

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading output files: {e}"}
    finally:
        for p in [temp_json, temp_suppliers, temp_assets]:
            if os.path.exists(p):
                os.unlink(p)

    # --- Check for Do-Nothing ---
    initial_supps = int(result_meta.get("initial_suppliers", 0))
    current_supps = int(result_meta.get("current_suppliers", 0))
    
    modified_assets = [a for a in assets_data if a.get('order_number') or a.get('supplier_name')]

    if current_supps <= initial_supps and len(modified_assets) == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No suppliers created and no assets modified."}

    # Extract expected parameters from metadata
    meta = task_info.get("metadata", {})
    expected_suppliers = meta.get("expected_suppliers", [])
    expected_assets = meta.get("expected_assets", {})

    # Helper to find a supplier by keyword in the dumped data
    def find_supplier(keyword):
        for s in suppliers_data:
            if keyword.lower() in s['name'].lower():
                return s
        return None

    suppliers_found_count = 0
    valid_cities = 0
    valid_urls = 0
    valid_notes = 0

    # Evaluate C1 - C11: Supplier details
    for idx, exp_sup in enumerate(expected_suppliers):
        kw = exp_sup['name_keyword']
        sup_record = find_supplier(kw)
        
        if sup_record:
            suppliers_found_count += 1
            # C1-C4: Supplier created (8 pts each)
            score += 8
            feedback.append(f"C{idx+1}: Supplier '{kw}' created successfully (+8)")

            # C5-C8: Email and Phone validation (4 pts each: 2 for email, 2 for phone)
            c_email_phone = 0
            if exp_sup['email'].lower() in sup_record['email'].lower():
                c_email_phone += 2
            if exp_sup['phone_digits'] in normalize_phone(sup_record['phone']):
                c_email_phone += 2
            score += c_email_phone
            feedback.append(f"C{idx+5}: '{kw}' Email/Phone check (+{c_email_phone}/4)")

            # Track global supplier fields for C9, C10, C11
            if exp_sup['city'].lower() in sup_record['city'].lower() and exp_sup['state'].lower() in sup_record['state'].lower():
                valid_cities += 1
            if exp_sup['url_keyword'].lower() in sup_record['url'].lower():
                valid_urls += 1
            if exp_sup['notes_keyword'].lower() in sup_record['notes'].lower():
                valid_notes += 1
        else:
            feedback.append(f"C{idx+1}: Supplier '{kw}' NOT found (+0)")

    # Score aggregated constraints (C9, C10, C11)
    if valid_cities == 4:
        score += 4
        feedback.append("C9: All 4 suppliers have correct city/state (+4)")
    else:
        score += valid_cities
        feedback.append(f"C9: {valid_cities}/4 suppliers have correct city/state (+{valid_cities})")

    if valid_urls == 4:
        score += 4
        feedback.append("C10: All 4 suppliers have correct URLs (+4)")
    else:
        score += valid_urls
        feedback.append(f"C10: {valid_urls}/4 suppliers have correct URLs (+{valid_urls})")

    if valid_notes == 4:
        score += 4
        feedback.append("C11: All 4 suppliers have required notes (+4)")
    else:
        score += valid_notes
        feedback.append(f"C11: {valid_notes}/4 suppliers have required notes (+{valid_notes})")

    # Evaluate C12 - C16: Asset Assignments (8 pts each)
    asset_dict = {a['asset_tag']: a for a in assets_data}
    asset_tags = ["PROC-001", "PROC-002", "PROC-003", "PROC-004", "PROC-005"]
    
    for idx, tag in enumerate(asset_tags):
        exp = expected_assets.get(tag, {})
        actual = asset_dict.get(tag, {})
        
        # Check if supplier name matches and order number matches
        sup_match = False
        if actual.get('supplier_name') and exp.get('supplier_keyword'):
            if exp['supplier_keyword'].lower() in actual['supplier_name'].lower():
                sup_match = True
                
        ord_match = False
        if actual.get('order_number') and exp.get('order_number'):
            if exp['order_number'].lower() == actual['order_number'].lower():
                ord_match = True
                
        if sup_match and ord_match:
            score += 8
            feedback.append(f"C{idx+12}: {tag} correctly assigned to {exp['supplier_keyword']} with PO {exp['order_number']} (+8)")
        elif sup_match:
            score += 4
            feedback.append(f"C{idx+12}: {tag} assigned to {exp['supplier_keyword']} but wrong/missing PO (+4)")
        elif ord_match:
            score += 4
            feedback.append(f"C{idx+12}: {tag} has correct PO but wrong/missing Supplier (+4)")
        else:
            feedback.append(f"C{idx+12}: {tag} missing correct Supplier and PO (+0)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }