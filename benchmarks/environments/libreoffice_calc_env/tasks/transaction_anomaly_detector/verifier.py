#!/usr/bin/env python3
"""
Verifier for Transaction Anomaly Detector task.
Validates that the agent correctly identified suspicious transactions using formulas.
"""

import sys
import os
import logging
import re
from typing import Dict, Set, List, Tuple

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth: known anomaly positions (0-indexed data rows, excluding header)
KNOWN_ANOMALIES = {
    'duplicates': [44, 45, 101, 102, 200, 201],
    'future_dates': [77, 133],
    'ancient_dates': [55],
    'outliers': [22, 88, 155, 233],
    'impossible_amounts': [66, 177],
    'balance_errors': [98, 149, 219]
}

# All anomaly rows (0-indexed, excluding header)
ALL_ANOMALY_ROWS = set()
for category_rows in KNOWN_ANOMALIES.values():
    ALL_ANOMALY_ROWS.update(category_rows)

# Critical anomalies that MUST be detected
CRITICAL_ANOMALY_ROWS = set(
    KNOWN_ANOMALIES['future_dates'] + 
    KNOWN_ANOMALIES['impossible_amounts'] +
    KNOWN_ANOMALIES['duplicates'][:4]  # At least 2 duplicate pairs
)


def detect_new_columns(sheet_data: Dict, original_cols: List[str]) -> List[int]:
    """
    Detect which columns were added by the agent.
    
    Args:
        sheet_data: Parsed sheet data
        original_cols: List of original column names
        
    Returns:
        List of column indices that were added
    """
    if not sheet_data or 'sheets' not in sheet_data:
        return []
    
    sheet_name = list(sheet_data['sheets'].keys())[0]
    rows = sheet_data['sheets'][sheet_name]
    
    if not rows or len(rows) == 0:
        return []
    
    # Check header row for new columns
    header_row = rows[0]
    new_columns = []
    
    for col_idx, cell in enumerate(header_row):
        if col_idx >= len(original_cols):
            # Column beyond original columns
            new_columns.append(col_idx)
        else:
            # Check if column name changed (indicating new column)
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and str(cell_value).strip() not in original_cols:
                # This might be a new column inserted
                new_columns.append(col_idx)
    
    return new_columns


def check_formula_usage(sheet_data: Dict, sheet_name: str, functions: List[str]) -> bool:
    """
    Check if specific formula functions are used in the sheet.
    
    Args:
        sheet_data: Parsed sheet data
        sheet_name: Name of the sheet
        functions: List of function names to check for (e.g., ['COUNTIFS', 'IF'])
        
    Returns:
        True if any of the functions are found
    """
    if not sheet_data or 'sheets' not in sheet_data:
        return False
    
    if sheet_name not in sheet_data['sheets']:
        return False
    
    rows = sheet_data['sheets'][sheet_name]
    
    for row in rows:
        for cell in row:
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula:
                formula_upper = formula.upper()
                for func in functions:
                    if func.upper() in formula_upper:
                        return True
    
    return False


def identify_flagged_rows(sheet_data: Dict, sheet_name: str, 
                         new_col_indices: List[int]) -> Set[int]:
    """
    Identify which transaction rows have been flagged by the agent.
    
    Args:
        sheet_data: Parsed sheet data
        sheet_name: Name of the sheet
        new_col_indices: Indices of columns added by agent
        
    Returns:
        Set of row indices (0-indexed data rows) that are flagged
    """
    flagged_rows = set()
    
    if not sheet_data or 'sheets' not in sheet_data:
        return flagged_rows
    
    if sheet_name not in sheet_data['sheets']:
        return flagged_rows
    
    rows = sheet_data['sheets'][sheet_name]
    
    # Skip header row, start from row 1 (first data row)
    for row_idx in range(1, len(rows)):
        row = rows[row_idx]
        is_flagged = False
        
        # Check new columns for any non-empty value
        for col_idx in new_col_indices:
            if col_idx < len(row):
                cell = row[col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                # Check if cell has meaningful content (not empty, not 0, not blank)
                if value is not None and str(value).strip() != '' and value != 0:
                    # Check for common flag indicators
                    value_str = str(value).upper()
                    flag_keywords = ['DUPLICATE', 'ERROR', 'OUTLIER', 'INVALID', 
                                   'SUSPICIOUS', 'WARNING', 'FLAG', 'ANOMALY',
                                   'HIGH', 'MEDIUM', 'LOW', 'TRUE', 'YES', '❌', '⚠️']
                    
                    if any(keyword in value_str for keyword in flag_keywords):
                        is_flagged = True
                        break
                    
                    # Also consider non-zero numbers or long text as flags
                    if len(value_str) > 2:
                        is_flagged = True
                        break
        
        if is_flagged:
            # Convert to 0-indexed data row (excluding header)
            flagged_rows.add(row_idx - 1)
    
    return flagged_rows


def analyze_formula_sophistication(sheet_data: Dict, sheet_name: str) -> Dict[str, bool]:
    """
    Analyze the sophistication of formulas used.
    
    Returns:
        Dict with boolean flags for different formula types
    """
    analysis = {
        'uses_countifs': False,
        'uses_if': False,
        'uses_statistics': False,
        'uses_date_functions': False,
        'has_complex_formulas': False
    }
    
    if not sheet_data or 'sheets' not in sheet_data:
        return analysis
    
    if sheet_name not in sheet_data['sheets']:
        return analysis
    
    rows = sheet_data['sheets'][sheet_name]
    
    for row in rows:
        for cell in row:
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula:
                formula_upper = formula.upper()
                
                if 'COUNTIFS' in formula_upper or 'COUNTIF' in formula_upper:
                    analysis['uses_countifs'] = True
                
                if 'IF(' in formula_upper:
                    analysis['uses_if'] = True
                
                if any(func in formula_upper for func in ['AVERAGE', 'STDEV', 'MEAN', 'MEDIAN']):
                    analysis['uses_statistics'] = True
                
                if any(func in formula_upper for func in ['DATE', 'TODAY', 'NOW', 'YEAR', 'MONTH', 'DAY']):
                    analysis['uses_date_functions'] = True
                
                # Complex formula: nested functions or long formulas
                if formula_upper.count('(') >= 2 or len(formula) > 30:
                    analysis['has_complex_formulas'] = True
    
    return analysis


def verify_transaction_anomaly_detector(traj, env_info, task_info):
    """
    Verify transaction anomaly detection task completion.
    
    Checks:
    1. Validation structure created (new columns with formulas)
    2. High recall (≥80%: 12+ of 15 anomalies detected)
    3. Acceptable precision (≥60% of flags are true anomalies)
    4. Critical anomalies caught (duplicates, future dates, impossible amounts)
    5. Formula sophistication (uses appropriate functions)
    6. Visual indication (any marking/formatting)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/validated_transactions.ods",
        "/home/ga/Documents/transactions_corrupted.ods",
        "/home/ga/Documents/transactions_corrupted.csv"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for path in possible_paths:
        # Determine format from extension
        if path.endswith('.ods'):
            file_format = 'ods'
        elif path.endswith('.csv'):
            file_format = 'csv'
        else:
            continue
        
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path, copy_from_env, file_format=file_format
        )
        
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load transaction file: {error}"
        }
    
    try:
        # Get sheet name
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        # Original columns in the transaction data
        original_cols = ['Date', 'Merchant', 'Category', 'Amount', 'Type', 'Balance']
        
        # Detect new columns added by agent
        new_col_indices = detect_new_columns(workbook, original_cols)
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Validation structure created
        has_validation_structure = len(new_col_indices) > 0
        if has_validation_structure:
            criteria_passed += 1
            feedback_parts.append(f"✅ Validation columns added ({len(new_col_indices)} new columns)")
        else:
            feedback_parts.append("❌ No validation columns detected")
        
        # Identify flagged rows
        flagged_rows = identify_flagged_rows(workbook, sheet_name, new_col_indices)
        
        logger.info(f"Flagged rows: {len(flagged_rows)}")
        logger.info(f"Known anomalies: {len(ALL_ANOMALY_ROWS)}")
        
        # Calculate detection metrics
        true_positives = len(flagged_rows & ALL_ANOMALY_ROWS)
        false_positives = len(flagged_rows - ALL_ANOMALY_ROWS)
        false_negatives = len(ALL_ANOMALY_ROWS - flagged_rows)
        
        recall = true_positives / len(ALL_ANOMALY_ROWS) if ALL_ANOMALY_ROWS else 0
        precision = true_positives / len(flagged_rows) if flagged_rows else 0
        
        logger.info(f"True positives: {true_positives}, False positives: {false_positives}")
        logger.info(f"Recall: {recall:.2%}, Precision: {precision:.2%}")
        
        # Criterion 2: High recall (≥80%: 12+ anomalies detected)
        if true_positives >= 12:
            criteria_passed += 1
            feedback_parts.append(f"✅ High recall: {true_positives}/15 anomalies detected ({recall:.0%})")
        elif true_positives >= 10:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Moderate recall: {true_positives}/15 anomalies detected ({recall:.0%})")
        else:
            feedback_parts.append(f"❌ Low recall: {true_positives}/15 anomalies detected ({recall:.0%})")
        
        # Criterion 3: Acceptable precision (≥60%)
        if precision >= 0.6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Good precision: {precision:.0%} ({true_positives}/{len(flagged_rows)} flags correct)")
        elif precision >= 0.4:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Moderate precision: {precision:.0%} ({false_positives} false positives)")
        else:
            feedback_parts.append(f"❌ Low precision: {precision:.0%} (too many false positives)")
        
        # Criterion 4: Critical anomalies caught
        critical_detected = len(flagged_rows & CRITICAL_ANOMALY_ROWS)
        critical_total = len(CRITICAL_ANOMALY_ROWS)
        critical_rate = critical_detected / critical_total if critical_total else 0
        
        if critical_rate >= 0.75:
            criteria_passed += 1
            feedback_parts.append(f"✅ Critical anomalies detected: {critical_detected}/{critical_total}")
        elif critical_rate >= 0.5:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some critical anomalies missed: {critical_detected}/{critical_total}")
        else:
            feedback_parts.append(f"❌ Critical anomalies missed: {critical_detected}/{critical_total}")
        
        # Criterion 5: Formula sophistication
        formula_analysis = analyze_formula_sophistication(workbook, sheet_name)
        
        formula_score = 0
        if formula_analysis['uses_countifs']:
            formula_score += 0.3
        if formula_analysis['uses_if']:
            formula_score += 0.2
        if formula_analysis['uses_statistics']:
            formula_score += 0.3
        if formula_analysis['has_complex_formulas']:
            formula_score += 0.2
        
        if formula_score >= 0.5:
            criteria_passed += 1
            feedback_parts.append("✅ Sophisticated formulas used (COUNTIFS, IF, statistics)")
        elif formula_score >= 0.3:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Basic formulas used")
        else:
            # Check if ANY formulas were used
            has_any_formulas = False
            rows = workbook['sheets'][sheet_name]
            for row in rows:
                for cell in row:
                    if isinstance(cell, dict) and cell.get('formula'):
                        has_any_formulas = True
                        break
                if has_any_formulas:
                    break
            
            if has_any_formulas:
                criteria_passed += 0.3
                feedback_parts.append("⚠️ Formulas present but not sophisticated")
            else:
                feedback_parts.append("❌ No formulas detected (manual flagging?)")
        
        # Criterion 6: Visual indication (check for any new columns as proxy)
        if has_validation_structure:
            criteria_passed += 1
            feedback_parts.append("✅ Visual indication present (validation columns)")
        else:
            feedback_parts.append("❌ No clear visual indication")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent anomaly detection!")
        elif passed:
            feedback_parts.insert(0, "✅ Anomaly detection completed")
        else:
            feedback_parts.insert(0, "❌ Insufficient anomaly detection")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "validation_structure": has_validation_structure,
                "recall": recall,
                "precision": precision,
                "true_positives": true_positives,
                "false_positives": false_positives,
                "false_negatives": false_negatives,
                "critical_detection_rate": critical_rate,
                "uses_formulas": formula_analysis['has_complex_formulas'] or formula_analysis['uses_if'],
                "uses_countifs": formula_analysis['uses_countifs'],
                "uses_statistics": formula_analysis['uses_statistics']
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
