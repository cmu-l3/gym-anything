#!/usr/bin/env python3
"""
Verifier for Fixed Asset Depreciation Schedule task.

Verification Strategy:
1. File was created and contains data (> 5000 bytes).
2. Content completeness: All 28 assets present.
3. Tax Methodology: MACRS percentages present in formulas/cells.
4. Total Accuracy: MACRS, Straight-Line, and Book-Tax differences fall in correct ranges.
5. Formulas: Contains active spreadsheet calculations (formulas).
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_depreciation_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})
    total_assets = gt.get('total_assets', 28)
    macrs_low = gt.get('macrs_range_low', 340000)
    macrs_high = gt.get('macrs_range_high', 440000)
    sl_low = gt.get('sl_range_low', 195000)
    sl_high = gt.get('sl_range_high', 275000)
    diff_low = gt.get('diff_range_low', 80000)
    diff_high = gt.get('diff_range_high', 180000)

    # Copy the JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/depreciation_task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Creation and Validity
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file depreciation_schedule_2023.xlsx not found."}
        
    if not result.get('created_during_task', False):
        feedback_parts.append("File modification timestamp predates task start (Anti-gaming check).")
        
    if result.get('file_size', 0) < 5000:
        return {"passed": False, "score": 0, "feedback": "Output file is too small to contain valid schedule."}
        
    if not result.get('success', False):
        return {"passed": False, "score": 0, "feedback": f"Spreadsheet parsing error: {result.get('error')}"}

    score += 10
    feedback_parts.append("Valid workbook found")

    all_text = result.get('all_text', '')
    all_numbers = result.get('all_numbers', [])
    sheets = result.get('sheets', [])
    formula_count = result.get('formula_count', 0)

    # 2. Check Data Completeness (28 assets)
    fa_count = all_text.count("fa-")
    if fa_count >= 25:
        score += 15
        feedback_parts.append("Asset data fully imported")
    elif fa_count >= 10:
        score += 5
        feedback_parts.append("Asset data partially imported")
    else:
        feedback_parts.append("Asset register is missing or incomplete")

    # 3. Check MACRS percentages (Tax Methodology)
    macrs_rates = [20.0, 32.0, 19.2, 14.29, 24.49, 17.49, 11.52, 5.76, 8.92, 8.93]
    rates_found = 0
    for rate in macrs_rates:
        # Match as raw number, decimal fraction, or string representation
        if rate in all_numbers or (rate/100) in all_numbers or str(rate) in all_text:
            rates_found += 1
            
    if rates_found >= 5:
        score += 15
        feedback_parts.append("MACRS rates applied correctly")
    elif rates_found >= 2:
        score += 5
        feedback_parts.append("Partial MACRS rates identified")

    # 4. Check Calculation Accuracy
    macrs_correct = any(macrs_low <= n <= macrs_high for n in all_numbers)
    sl_correct = any(sl_low <= n <= sl_high for n in all_numbers)
    diff_correct = any(diff_low <= n <= diff_high for n in all_numbers)

    if macrs_correct:
        score += 20
        feedback_parts.append(f"MACRS 2023 total within acceptable range (${macrs_low}-${macrs_high})")
    
    if sl_correct:
        score += 15
        feedback_parts.append(f"Straight-Line 2023 total within acceptable range (${sl_low}-${sl_high})")
        
    if diff_correct:
        score += 15
        feedback_parts.append("Book-Tax difference calculated and within acceptable range")

    # 5. Check Structure and Formulas
    if len(sheets) >= 3:
        score += 5
        feedback_parts.append("Good multi-sheet organization")
        
    if formula_count >= 15:
        score += 5
        feedback_parts.append(f"Calculations driven by formulas (count: {formula_count})")
    elif formula_count > 0:
        score += 2
        feedback_parts.append(f"Some formulas present (count: {formula_count})")
    else:
        feedback_parts.append("No active formulas found (hardcoded values)")

    # Final pass logic
    # The agent passes if they score >= 60 AND hit the key targets (MACRS calculation is structurally present)
    passed = (score >= 60) and macrs_correct and sl_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }