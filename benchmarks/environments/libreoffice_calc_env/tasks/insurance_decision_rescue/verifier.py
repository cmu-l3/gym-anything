#!/usr/bin/env python3
"""
Verifier for Health Insurance Decision Rescue task

Checks:
1. Data structure completeness (required columns)
2. Three scenario sections exist
3. Formula correctness (cost calculations)
4. Conditional formatting presence
5. Best plan identification
6. Decision logic present
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Optional, Any

# Do not use /workspace/utils, use relative path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_number(value: Any) -> Optional[float]:
    """Extract numeric value from cell (handles currency, percentages, text)"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove currency symbols, commas, /year, /month, etc.
        cleaned = re.sub(r'[$,/a-zA-Z\s]', '', value)
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def check_data_structure(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Verify that required columns exist and data is reasonably complete
    Returns: (success, feedback_list)
    """
    feedback = []
    required_columns = [
        "plan", "premium", "deductible", "coinsurance", "out-of-pocket",
        "pcp", "specialist", "rx"
    ]
    
    # Get first row (headers)
    first_row = workbook['sheets'][sheet_name][0] if workbook['sheets'][sheet_name] else []
    header_text = []
    for cell in first_row:
        val = cell.get('value', '') if isinstance(cell, dict) else str(cell)
        header_text.append(str(val).lower())
    
    header_combined = " ".join(header_text)
    
    # Check for required keywords in headers
    found_columns = 0
    for col_keyword in required_columns:
        if col_keyword in header_combined:
            found_columns += 1
    
    if found_columns >= 6:  # At least 6 of 8 columns
        feedback.append(f"✅ Data structure present ({found_columns}/8 key columns found)")
        return True, feedback
    else:
        feedback.append(f"❌ Missing required columns (only {found_columns}/8 found)")
        return False, feedback


def check_scenarios_exist(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Check if three scenario sections exist
    Returns: (success, feedback_list)
    """
    feedback = []
    rows = workbook['sheets'][sheet_name]
    
    scenario_keywords = ["minimal", "moderate", "high"]
    found_scenarios = []
    
    for row_idx, row in enumerate(rows):
        row_text = " ".join([
            str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            for cell in row
        ]).lower()
        
        for keyword in scenario_keywords:
            if keyword in row_text and keyword not in found_scenarios:
                found_scenarios.append(keyword)
    
    if len(found_scenarios) >= 3:
        feedback.append(f"✅ Three scenarios found: {', '.join(found_scenarios)}")
        return True, feedback
    else:
        feedback.append(f"⚠️ Only {len(found_scenarios)} scenarios found (expected 3)")
        return False, feedback


def find_plan_data(workbook: Dict, sheet_name: str) -> Dict[str, Dict[str, float]]:
    """
    Extract plan data from the spreadsheet
    Returns: dict of {plan_name: {premium: X, deductible: Y, ...}}
    """
    rows = workbook['sheets'][sheet_name]
    plans = {}
    
    # Find header row (contains "plan" and "premium")
    header_idx = None
    for idx, row in enumerate(rows[:10]):  # Check first 10 rows
        row_text = " ".join([
            str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            for cell in row
        ]).lower()
        if 'plan' in row_text and 'premium' in row_text:
            header_idx = idx
            break
    
    if header_idx is None:
        return plans
    
    # Parse next 4-5 rows as plan data
    for row_idx in range(header_idx + 1, min(header_idx + 6, len(rows))):
        row = rows[row_idx]
        if len(row) < 4:
            continue
        
        plan_name_cell = row[0] if len(row) > 0 else {}
        plan_name = plan_name_cell.get('value', '') if isinstance(plan_name_cell, dict) else str(plan_name_cell)
        
        if not plan_name or plan_name == "":
            continue
        
        # Extract numeric values from the row
        premium = extract_number(row[1].get('value') if isinstance(row[1], dict) else row[1]) if len(row) > 1 else None
        deductible = extract_number(row[2].get('value') if isinstance(row[2], dict) else row[2]) if len(row) > 2 else None
        coinsurance = extract_number(row[3].get('value') if isinstance(row[3], dict) else row[3]) if len(row) > 3 else None
        oop_max = extract_number(row[4].get('value') if isinstance(row[4], dict) else row[4]) if len(row) > 4 else None
        
        # Handle annual premium conversion (if > 2000, likely annual)
        if premium and premium > 2000:
            premium = premium / 12  # Convert to monthly
        
        plans[str(plan_name)] = {
            'premium': premium,
            'deductible': deductible,
            'coinsurance': coinsurance / 100 if coinsurance and coinsurance > 1 else coinsurance,
            'oop_max': oop_max
        }
    
    return plans


def calculate_expected_cost(plan_data: Dict[str, float], scenario: str) -> Optional[float]:
    """
    Calculate expected annual cost for a plan under a scenario
    Returns: expected cost or None if data insufficient
    """
    if not all(k in plan_data and plan_data[k] is not None for k in ['premium', 'deductible']):
        return None
    
    annual_premium = plan_data['premium'] * 12
    
    # Scenario parameters
    scenarios_params = {
        'minimal': {'medical_costs': 400},   # 2 PCP (25) + 1 specialist (50) + 300 Rx
        'moderate': {'medical_costs': 1700}, # 4 PCP (100) + 3 specialist (150) + 1500 Rx
        'high': {'medical_costs': 10000}     # Significant costs
    }
    
    if scenario not in scenarios_params:
        return None
    
    medical_costs = scenarios_params[scenario]['medical_costs']
    deductible = plan_data['deductible']
    coinsurance = plan_data.get('coinsurance', 0.2)
    oop_max = plan_data.get('oop_max', 10000)
    
    # Calculate patient responsibility
    if medical_costs <= deductible:
        patient_pays = medical_costs
    else:
        patient_pays = deductible + (medical_costs - deductible) * coinsurance
    
    # Cap at OOP max
    patient_pays = min(patient_pays, oop_max)
    
    return annual_premium + patient_pays


def check_formula_correctness(workbook: Dict, sheet_name: str, plan_data: Dict) -> Tuple[int, List[str]]:
    """
    Verify formulas exist and produce reasonable results
    Returns: (points, feedback_list)
    """
    feedback = []
    points = 0
    rows = workbook['sheets'][sheet_name]
    
    # Find scenario calculation section
    scenario_start_idx = None
    for idx, row in enumerate(rows):
        row_text = " ".join([
            str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            for cell in row
        ]).lower()
        if 'scenario' in row_text and 'calculation' in row_text:
            scenario_start_idx = idx
            break
    
    if scenario_start_idx is None:
        feedback.append("⚠️ Could not find scenario calculations section")
        return points, feedback
    
    # Check for formulas in the next few rows
    formulas_found = 0
    calculations_checked = 0
    
    for row_idx in range(scenario_start_idx + 2, min(scenario_start_idx + 10, len(rows))):
        row = rows[row_idx]
        
        for col_idx in range(1, min(4, len(row))):  # Check columns B, C, D (scenarios)
            cell = row[col_idx] if len(row) > col_idx else {}
            formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if formula and formula.startswith('='):
                formulas_found += 1
                
                # Check if formula contains expected elements
                formula_upper = formula.upper()
                if '*12' in formula_upper or '*' in formula_upper:
                    # Good: formula includes multiplication (likely annualizing premium)
                    pass
                
                if '+' in formula_upper:
                    # Good: formula includes addition (likely premium + medical costs)
                    pass
                
                # Try to validate calculation if we have plan data and value
                if value and isinstance(value, (int, float)) and value > 1000:
                    calculations_checked += 1
                    # This looks like a reasonable annual cost
    
    if formulas_found >= 3:
        points += 1
        feedback.append(f"✅ Formulas present ({formulas_found} found)")
    else:
        feedback.append(f"❌ Insufficient formulas ({formulas_found} found, need at least 3)")
    
    # Try to validate at least one calculation
    # Find a plan name and corresponding calculated value
    if calculations_checked >= 2:
        points += 1
        feedback.append(f"✅ Cost calculations appear reasonable ({calculations_checked} checked)")
    
    return points, feedback


def check_conditional_formatting_present(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Check if conditional formatting is applied
    Returns: (success, feedback_list)
    """
    feedback = []
    
    # Use existing utility function
    has_formatting = check_conditional_formatting(workbook, sheet_name, "B1:D20")
    
    if has_formatting:
        feedback.append("✅ Conditional formatting detected")
        return True, feedback
    else:
        feedback.append("⚠️ No conditional formatting detected (expected highlighting of best plans)")
        return False, feedback


def check_best_plan_marked(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Check if the lowest-cost plan for at least one scenario is clearly identified
    Returns: (success, feedback_list)
    """
    feedback = []
    rows = workbook['sheets'][sheet_name]
    
    # Look for any indication of "best" or minimum values
    best_indicators = ["best", "lowest", "recommended", "optimal", "cheapest"]
    
    for row in rows:
        row_text = " ".join([
            str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            for cell in row
        ]).lower()
        
        for indicator in best_indicators:
            if indicator in row_text:
                feedback.append(f"✅ Best plan identification found ('{indicator}' mentioned)")
                return True, feedback
    
    # Alternatively, check if there's clear highlighting via conditional formatting
    # (already checked in previous function)
    
    feedback.append("⚠️ No clear 'best plan' identification found")
    return False, feedback


def check_decision_logic(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Check if decision support logic exists (e.g., "Best For" column)
    Returns: (success, feedback_list)
    """
    feedback = []
    rows = workbook['sheets'][sheet_name]
    
    decision_keywords = [
        "best for", "recommended for", "ideal for", "suitable for",
        "healthy", "chronic", "high needs", "low needs", "average"
    ]
    
    decision_indicators_found = 0
    
    for row in rows:
        row_text = " ".join([
            str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            for cell in row
        ]).lower()
        
        for keyword in decision_keywords:
            if keyword in row_text:
                decision_indicators_found += 1
                break
    
    if decision_indicators_found >= 2:
        feedback.append(f"✅ Decision support logic present ({decision_indicators_found} indicators)")
        return True, feedback
    else:
        feedback.append("⚠️ Limited decision support (expected 'Best For' or similar recommendations)")
        return False, feedback


def verify_insurance_decision_rescue(traj, env_info, task_info):
    """
    Main verifier for Health Insurance Decision Rescue task
    
    Checks:
    1. Data structure complete (8 columns)
    2. Three scenarios exist
    3. Formulas correct (cost calculations)
    4. Conditional formatting applied
    5. Best plan identified
    6. Decision logic present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/insurance_comparison.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Data structure complete
        structure_ok, structure_feedback = check_data_structure(workbook, sheet_name)
        feedback_parts.extend(structure_feedback)
        if structure_ok:
            criteria_passed += 1
            subscores['data_structure'] = True
        else:
            subscores['data_structure'] = False
        
        # Criterion 2: Three scenarios exist
        scenarios_ok, scenarios_feedback = check_scenarios_exist(workbook, sheet_name)
        feedback_parts.extend(scenarios_feedback)
        if scenarios_ok:
            criteria_passed += 1
            subscores['scenarios_present'] = True
        else:
            subscores['scenarios_present'] = False
        
        # Criterion 3: Formula correctness
        plan_data = find_plan_data(workbook, sheet_name)
        formula_points, formula_feedback = check_formula_correctness(workbook, sheet_name, plan_data)
        feedback_parts.extend(formula_feedback)
        if formula_points >= 1:
            criteria_passed += formula_points * 0.5  # Each point is worth 0.5 criteria
            subscores['formulas_correct'] = True
        else:
            subscores['formulas_correct'] = False
        
        # Criterion 4: Conditional formatting
        formatting_ok, formatting_feedback = check_conditional_formatting_present(workbook, sheet_name)
        feedback_parts.extend(formatting_feedback)
        if formatting_ok:
            criteria_passed += 1
            subscores['conditional_formatting'] = True
        else:
            subscores['conditional_formatting'] = False
        
        # Criterion 5: Best plan identified
        best_marked, best_feedback = check_best_plan_marked(workbook, sheet_name)
        feedback_parts.extend(best_feedback)
        if best_marked:
            criteria_passed += 1
            subscores['best_plan_marked'] = True
        else:
            subscores['best_plan_marked'] = False
        
        # Criterion 6: Decision logic present
        decision_ok, decision_feedback = check_decision_logic(workbook, sheet_name)
        feedback_parts.extend(decision_feedback)
        if decision_ok:
            criteria_passed += 1
            subscores['decision_logic'] = True
        else:
            subscores['decision_logic'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (4-5 out of 6 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent insurance comparison analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Insurance comparison task completed")
        else:
            feedback_parts.insert(0, "❌ Insurance comparison incomplete - needs more work")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
