#!/usr/bin/env python3
"""
Verifier for Corporate GHG Emissions Inventory.

The agent calculates Scope 1 and Scope 2 MTCO2e emissions from raw kBtu energy data
for 150 NYC properties based on specific EPA emission factors.

Scoring (10 points max, 6.0 threshold):
- CHECK 1: Multi-sheet structure (1.0 pt)
- CHECK 2: Unit Conversions (MWh, mmBtu) verified via sampling (2.0 pts)
- CHECK 3: Scope 2 MTCO2e logic verified via sampling (2.0 pts)
- CHECK 4: Scope 1 MTCO2e logic verified via sampling (2.0 pts)
- CHECK 5: Portfolio grand totals correct on summary sheet (1.5 pts)
- CHECK 6: Top 5 Emitters identified on summary sheet (1.5 pts)
"""

import sys
import os
import json
import logging
import tempfile
import random

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import copy_and_parse_document

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def generate_expected_data():
    """Regenerates the exact dataset values expected based on the deterministic seed."""
    random.seed(2023)
    properties = []
    total_scope1 = 0.0
    total_scope2 = 0.0
    total_mtco2e = 0.0
    
    for i in range(1, 151):
        elec = round(random.uniform(500000, 20000000), 2)
        gas = round(random.uniform(100000, 10000000), 2)
        oil = round(random.uniform(50000, 5000000), 2) if random.random() > 0.6 else 0.0
        
        elec_mwh = elec / 3412.14
        gas_mmbtu = gas / 1000.0
        oil_mmbtu = oil / 1000.0
        
        scope2 = (elec_mwh * 552.8) / 2204.62
        scope1 = (gas_mmbtu * 53.11 / 1000.0) + (oil_mmbtu * 74.21 / 1000.0)
        total = scope1 + scope2
        
        properties.append({
            'id': f"NYC-{1000+i}",
            'name': f"Property_{i:03d}",
            'scope1': scope1,
            'scope2': scope2,
            'total': total,
            'elec_mwh': elec_mwh,
            'gas_mmbtu': gas_mmbtu,
            'oil_mmbtu': oil_mmbtu
        })
        
        total_scope1 += scope1
        total_scope2 += scope2
        total_mtco2e += total
        
    properties.sort(key=lambda x: x['total'], reverse=True)
    top_5 = properties[:5]
    
    return properties, total_scope1, total_scope2, total_mtco2e, top_5

def extract_numbers_from_row(row):
    """Robust number extraction accounting for string formatting."""
    nums = []
    for cell in row:
        if isinstance(cell.value, (int, float)):
            nums.append(float(cell.value))
        elif isinstance(cell.value, str):
            try:
                clean_str = cell.value.replace(',', '').replace(' ', '').replace('$', '').replace('%', '')
                nums.append(float(clean_str))
            except Exception:
                pass
    return nums

def find_row_numbers_by_id(sheet, prop_id):
    """Finds a specific property's row and extracts its numbers."""
    for row in sheet.iter_rows():
        row_has_id = False
        for cell in row:
            if isinstance(cell.value, str) and prop_id in cell.value:
                row_has_id = True
                break
        if row_has_id:
            return extract_numbers_from_row(row)
    return []

def extract_numbers_from_sheet(sheet):
    nums = []
    for row in sheet.iter_rows():
        nums.extend(extract_numbers_from_row(row))
    return nums

def extract_all_text(sheet):
    text = []
    for row in sheet.iter_rows(values_only=True):
        for cell in row:
            if cell is not None and isinstance(cell, str):
                text.append(cell.lower())
    return " ".join(text)

def find_close_value(val, numbers_list, tolerance=0.02):
    """Checks if a target mathematically-derived value exists in a list of cell numbers."""
    if val == 0:
        return any(abs(n) < 1e-5 for n in numbers_list)
    return any(abs((n - val) / val) <= tolerance for n in numbers_list)

def verify_ghg_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # Read the result json exported by export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ghg_inventory_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Wrong-Target Gate
    if not result.get("output_file_exists", False) or result.get("output_file_size", 0) < 1000:
        return {"passed": False, "score": 0.0, "feedback": "Wrong-target gate: Valid workbook output does not exist."}

    container_path = result.get("output_path", "/home/ga/Documents/Spreadsheets/ghg_inventory_2023.xlsx")
    
    # Copy and parse workbook (data_only=True is handled internally by default in our utils)
    success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
    if not success:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to parse workbook: {error}"}

    feedback = []
    score = 0.0

    # Retrieve ground truth
    expected_props, exp_tot_scope1, exp_tot_scope2, exp_tot_all, exp_top5 = generate_expected_data()

    # Identify sheets safely
    data_sheet = None
    summary_sheet = None
    
    for sn in wb.sheetnames:
        if "emissions" in sn.lower() or "data" in sn.lower():
            data_sheet = wb[sn]
        elif "esg" in sn.lower() or "summary" in sn.lower():
            summary_sheet = wb[sn]
            
    if not data_sheet:
        data_sheet = wb.worksheets[0]
    if not summary_sheet and len(wb.worksheets) > 1:
        summary_sheet = wb.worksheets[1]

    # CHECK 1: Sheet structure
    if len(wb.worksheets) >= 2:
        score += 1.0
        feedback.append("Multi-sheet structure found.")
    else:
        feedback.append("Only one sheet found. Missing summary sheet separation.")

    # CHECK 2-4: Row calculations (Sample 5 random but deterministic properties)
    test_ids = ['NYC-1010', 'NYC-1050', 'NYC-1100', 'NYC-1125', 'NYC-1149']
    test_props = [p for p in expected_props if p['id'] in test_ids]
    
    mwh_success = 0
    scope2_success = 0
    scope1_success = 0
    
    for tp in test_props:
        nums = find_row_numbers_by_id(data_sheet, tp['id'])
        if not nums:
            continue
            
        if find_close_value(tp['elec_mwh'], nums, 0.02) or find_close_value(tp['gas_mmbtu'], nums, 0.02):
            mwh_success += 1
        if find_close_value(tp['scope2'], nums, 0.02):
            scope2_success += 1
        if find_close_value(tp['scope1'], nums, 0.02) or find_close_value(tp['total'], nums, 0.02):
            scope1_success += 1
            
    if mwh_success >= 3:
        score += 2.0
        feedback.append("Unit conversions verified (MWh / mmBtu).")
    elif mwh_success > 0:
        score += 1.0
        feedback.append("Partial unit conversions verified.")
        
    if scope2_success >= 3:
        score += 2.0
        feedback.append("Scope 2 calculations verified.")
    elif scope2_success > 0:
        score += 1.0
        feedback.append("Partial Scope 2 calculations verified.")
        
    if scope1_success >= 3:
        score += 2.0
        feedback.append("Scope 1 calculations verified.")
    elif scope1_success > 0:
        score += 1.0
        feedback.append("Partial Scope 1 calculations verified.")

    # CHECK 5: Grand totals
    summary_nums = []
    if summary_sheet and summary_sheet != data_sheet:
        summary_nums = extract_numbers_from_sheet(summary_sheet)
    else:
        for sheet in wb.worksheets:
            summary_nums.extend(extract_numbers_from_sheet(sheet))
            
    totals_found = 0
    if find_close_value(exp_tot_scope1, summary_nums, 0.02): totals_found += 1
    if find_close_value(exp_tot_scope2, summary_nums, 0.02): totals_found += 1
    if find_close_value(exp_tot_all, summary_nums, 0.02): totals_found += 1
    
    if totals_found >= 2:
        score += 1.5
        feedback.append("Portfolio totals verified.")
    elif totals_found == 1:
        score += 0.5
        feedback.append("Partial portfolio totals verified.")

    # CHECK 6: Top 5 Emitters
    summary_text = extract_all_text(summary_sheet) if (summary_sheet and summary_sheet != data_sheet) else ""
    if not summary_text:
        summary_text = extract_all_text(wb.worksheets[0])
        
    top5_found = 0
    for p in exp_top5:
        if p['name'].lower() in summary_text:
            top5_found += 1
            
    if top5_found >= 3:
        score += 1.5
        feedback.append("Top emitters ranked correctly.")
    elif top5_found > 0:
        score += 0.5
        feedback.append("Some top emitters identified.")

    passed = score >= 6.0
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }