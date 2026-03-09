#!/usr/bin/env python3
"""
Verifier for Costume Damage Assessment task.
Checks inventory updates, urgency formulas, priority flags, gap analysis, and sorting.
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple, List

# Use relative path to the utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_environment,
    get_cell_value,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_sheet_headers(rows: List[List]) -> Dict[str, int]:
    """Parse header row to find column indices."""
    if not rows or len(rows) == 0:
        return {}
    
    headers = {}
    header_row = rows[0]
    
    for i, cell in enumerate(header_row):
        if isinstance(cell, dict):
            value = cell.get('value', '')
        else:
            value = cell
        
        header_text = str(value).lower().strip()
        headers[header_text] = i
    
    return headers


def get_column_values(rows: List[List], col_idx: int, start_row: int = 1) -> List[Any]:
    """Extract all values from a specific column."""
    values = []
    for i in range(start_row, len(rows)):
        if col_idx < len(rows[i]):
            cell = rows[i][col_idx]
            if isinstance(cell, dict):
                value = cell.get('value')
            else:
                value = cell
            values.append(value)
    return values


def check_conditions_updated(rows: List[List], headers: Dict[str, int]) -> Tuple[bool, str]:
    """Check if at least 6 items have updated conditions (Fair/Poor/Unusable)."""
    condition_col = None
    
    # Find condition column
    for key in ['current_condition', 'condition', 'current condition']:
        if key in headers:
            condition_col = headers[key]
            break
    
    if condition_col is None:
        return False, "Current_Condition column not found"
    
    conditions = get_column_values(rows, condition_col)
    
    # Count items with Fair, Poor, or Unusable conditions
    damaged_count = sum(1 for c in conditions 
                       if c and any(status in str(c).lower() 
                                  for status in ['fair', 'poor', 'unusable']))
    
    if damaged_count >= 6:
        return True, f"✅ {damaged_count} items show damage (Fair/Poor/Unusable)"
    else:
        return False, f"❌ Only {damaged_count} items show damage (expected 6+)"


def check_urgency_formula(rows: List[List], headers: Dict[str, int]) -> Tuple[bool, str]:
    """Check if Repair_Urgency_Score column exists with numeric values."""
    urgency_col = None
    
    # Find urgency score column
    for key in ['repair_urgency_score', 'urgency_score', 'urgency', 'repair urgency score']:
        if key in headers:
            urgency_col = headers[key]
            break
    
    if urgency_col is None:
        return False, "❌ Repair_Urgency_Score column not found"
    
    urgency_values = get_column_values(rows, urgency_col)
    
    # Count numeric urgency values
    numeric_count = sum(1 for v in urgency_values 
                       if v is not None and isinstance(v, (int, float)))
    
    if numeric_count >= 10:
        return True, f"✅ Urgency scores calculated ({numeric_count} items)"
    else:
        return False, f"❌ Urgency scores missing or incomplete ({numeric_count} items)"


def check_logic_correctness(rows: List[List], headers: Dict[str, int]) -> Tuple[bool, str]:
    """Spot-check that urgency logic is reasonable (Poor condition → higher urgency)."""
    condition_col = None
    urgency_col = None
    
    for key in ['current_condition', 'condition', 'current condition']:
        if key in headers:
            condition_col = headers[key]
            break
    
    for key in ['repair_urgency_score', 'urgency_score', 'urgency']:
        if key in headers:
            urgency_col = headers[key]
            break
    
    if condition_col is None or urgency_col is None:
        return False, "❌ Cannot verify logic (missing columns)"
    
    # Check a few rows: Poor condition should have urgency >= 2
    logic_errors = 0
    checks_performed = 0
    
    for i in range(1, min(len(rows), 15)):
        if condition_col >= len(rows[i]) or urgency_col >= len(rows[i]):
            continue
        
        condition_cell = rows[i][condition_col]
        urgency_cell = rows[i][urgency_col]
        
        condition = str(condition_cell.get('value', '') if isinstance(condition_cell, dict) else condition_cell).lower()
        urgency = urgency_cell.get('value') if isinstance(urgency_cell, dict) else urgency_cell
        
        if 'poor' in condition and isinstance(urgency, (int, float)):
            checks_performed += 1
            if urgency < 2:
                logic_errors += 1
        elif 'fair' in condition and isinstance(urgency, (int, float)):
            checks_performed += 1
            if urgency < 1:
                logic_errors += 1
    
    if checks_performed == 0:
        return False, "❌ No damaged items found to verify logic"
    
    if logic_errors == 0:
        return True, f"✅ Urgency logic appears correct ({checks_performed} items checked)"
    else:
        return False, f"❌ Logic errors found ({logic_errors}/{checks_performed} items)"


def check_priority_flags(rows: List[List], headers: Dict[str, int]) -> Tuple[bool, str]:
    """Check if priority flags are applied to high-urgency items."""
    priority_col = None
    urgency_col = None
    
    for key in ['repair_priority', 'priority', 'repair priority', 'flag']:
        if key in headers:
            priority_col = headers[key]
            break
    
    for key in ['repair_urgency_score', 'urgency_score', 'urgency']:
        if key in headers:
            urgency_col = headers[key]
            break
    
    if priority_col is None:
        return False, "❌ Repair_Priority column not found"
    
    priority_values = get_column_values(rows, priority_col)
    
    # Count urgent flags
    urgent_count = sum(1 for p in priority_values 
                      if p and 'urgent' in str(p).lower())
    
    if 2 <= urgent_count <= 8:
        return True, f"✅ Priority flags applied ({urgent_count} urgent items)"
    elif urgent_count > 0:
        return True, f"⚠️ Priority flags present but unusual count ({urgent_count} items)"
    else:
        return False, "❌ No URGENT priority flags found"


def check_gap_analysis(rows: List[List]) -> Tuple[bool, str]:
    """Check if gap analysis or shortage calculation is present."""
    # Look for keywords in any cell that suggest gap analysis
    gap_keywords = ['gap', 'shortage', 'needed', 'missing', 'short', 'deficit']
    
    for row in rows:
        for cell in row:
            if isinstance(cell, dict):
                value = str(cell.get('value', '')).lower()
            else:
                value = str(cell).lower()
            
            if any(keyword in value for keyword in gap_keywords):
                return True, "✅ Gap analysis or shortage calculation present"
    
    return False, "❌ No evidence of costume gap analysis"


def check_sorted_by_priority(rows: List[List], headers: Dict[str, int]) -> Tuple[bool, str]:
    """Check if inventory is sorted by urgency score (descending)."""
    urgency_col = None
    
    for key in ['repair_urgency_score', 'urgency_score', 'urgency']:
        if key in headers:
            urgency_col = headers[key]
            break
    
    if urgency_col is None:
        return False, "❌ Cannot verify sorting (urgency column not found)"
    
    urgency_values = []
    for i in range(1, min(len(rows), 15)):
        if urgency_col < len(rows[i]):
            cell = rows[i][urgency_col]
            value = cell.get('value') if isinstance(cell, dict) else cell
            if isinstance(value, (int, float)):
                urgency_values.append(value)
    
    if len(urgency_values) < 3:
        return False, "❌ Insufficient data to verify sorting"
    
    # Check if descending order (allowing ties)
    is_sorted = all(urgency_values[i] >= urgency_values[i+1] 
                   for i in range(len(urgency_values)-1))
    
    if is_sorted:
        return True, f"✅ Inventory sorted by urgency (descending)"
    else:
        return False, f"❌ Inventory not properly sorted by priority"


def verify_costume_damage_assessment(traj, env_info, task_info):
    """
    Main verification function for costume damage assessment task.
    
    Checks:
    1. Conditions updated for damaged items (6+)
    2. Urgency score formula present and calculated
    3. Logic correctness (spot-check)
    4. Priority flags applied (2-8 urgent items)
    5. Gap analysis present
    6. Data sorted by priority
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    possible_paths = [
        "/home/ga/Documents/costume_inventory.ods",
        "/home/ga/Documents/costume_inventory_updated.ods",
        "/home/ga/Documents/results/costume_inventory.ods"
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            ['ods', 'xlsx']
        )
        if success:
            logger.info(f"Found file at: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not find costume inventory file. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        data = file_info['sheet_data']
        sheets = data.get('sheets', {})
        
        # Find Master_Inventory sheet
        inventory_sheet = None
        for sheet_name in sheets.keys():
            if 'inventory' in sheet_name.lower() or 'master' in sheet_name.lower():
                inventory_sheet = sheets[sheet_name]
                break
        
        if inventory_sheet is None:
            # Fallback to first sheet
            if sheets:
                inventory_sheet = list(sheets.values())[0]
            else:
                return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        if len(inventory_sheet) < 2:
            return {"passed": False, "score": 0, "feedback": "Inventory sheet has insufficient data"}
        
        # Parse headers
        headers = parse_sheet_headers(inventory_sheet)
        
        # Run all checks
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Conditions updated
        passed_1, msg_1 = check_conditions_updated(inventory_sheet, headers)
        if passed_1:
            criteria_passed += 1
        feedback_parts.append(msg_1)
        subscores['conditions_updated'] = passed_1
        
        # Criterion 2: Urgency formula present
        passed_2, msg_2 = check_urgency_formula(inventory_sheet, headers)
        if passed_2:
            criteria_passed += 1
        feedback_parts.append(msg_2)
        subscores['urgency_formula_present'] = passed_2
        
        # Criterion 3: Logic correctness
        passed_3, msg_3 = check_logic_correctness(inventory_sheet, headers)
        if passed_3:
            criteria_passed += 1
        feedback_parts.append(msg_3)
        subscores['logic_correct'] = passed_3
        
        # Criterion 4: Priority flags
        passed_4, msg_4 = check_priority_flags(inventory_sheet, headers)
        if passed_4:
            criteria_passed += 1
        feedback_parts.append(msg_4)
        subscores['priority_flags_applied'] = passed_4
        
        # Criterion 5: Gap analysis
        passed_5, msg_5 = check_gap_analysis(inventory_sheet)
        if passed_5:
            criteria_passed += 1
        feedback_parts.append(msg_5)
        subscores['gap_analysis_present'] = passed_5
        
        # Criterion 6: Sorted by priority
        passed_6, msg_6 = check_sorted_by_priority(inventory_sheet, headers)
        if passed_6:
            criteria_passed += 1
        feedback_parts.append(msg_6)
        subscores['sorted_by_priority'] = passed_6
        
        # Calculate score (each criterion worth ~16.67%)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60  # Pass threshold: 60% (4 out of 6 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent costume damage assessment!")
        elif passed:
            feedback_parts.append("✅ Costume assessment completed successfully")
        else:
            feedback_parts.append(f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria met)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_environment(file_info.get('temp_dir'))
