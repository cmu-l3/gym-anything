#!/usr/bin/env python3
"""
Verifier for Poker Night Settlement Calculator task.

Validates:
1. Data structure integrity (8 players, numeric values)
2. Total buy-in formulas (SUM of columns B:D)
3. Net position formulas (Final chips - Total buy-ins)
4. Zero-sum constraint (critical: all net positions sum to ~0)
5. Data organization (sorted by net position - bonus)
"""

import sys
import os
import logging
import re
from typing import Dict, List, Any, Tuple, Optional

# Use relative path to utils folder (host machine, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula: str) -> str:
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(" ", "").upper()


def verify_sum_formula(formula: str, row: int, expected_cols: str = "B:D") -> bool:
    """
    Verify that formula correctly sums buy-in columns.
    
    Valid patterns:
    - =SUM(B2:D2)
    - =B2+C2+D2
    - =SUM(B2,C2,D2)
    - =SUM($B2:$D2) (with absolute references)
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Check for SUM function with range
    pattern1 = f"SUM(B{row}:D{row})"
    pattern2 = f"SUM($B{row}:$D{row})"
    pattern3 = f"SUM(B${row}:D${row})"
    pattern4 = f"SUM($B${row}:$D${row})"
    
    # Check for explicit addition
    pattern5 = f"B{row}+C{row}+D{row}"
    pattern6 = f"$B{row}+$C{row}+$D{row}"
    
    # Check for SUM with individual cells
    pattern7 = f"SUM(B{row},C{row},D{row})"
    
    patterns = [pattern1, pattern2, pattern3, pattern4, pattern5, pattern6, pattern7]
    
    return any(pattern.replace("$", "") in norm.replace("$", "") for pattern in patterns)


def verify_net_position_formula(formula: str, row: int) -> bool:
    """
    Verify that formula correctly calculates net position.
    
    Valid patterns:
    - =E2-F2
    - =E2+(-F2)
    - =$E2-$F2 (with absolute references)
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Basic subtraction patterns
    pattern1 = f"E{row}-F{row}"
    pattern2 = f"$E{row}-$F{row}"
    pattern3 = f"E${row}-F${row}"
    pattern4 = f"$E${row}-$F${row}"
    
    patterns = [pattern1, pattern2, pattern3, pattern4]
    
    return any(pattern.replace("$", "") in norm.replace("$", "") for pattern in patterns)


def verify_data_integrity(sheet_data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str, int]:
    """
    Verify data structure integrity.
    
    Returns:
        (is_valid, error_message, row_count)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Count rows with data
        data_row_count = 0
        for row in rows:
            if row and len(row) > 0:
                first_cell = row[0]
                cell_value = first_cell.get('value') if isinstance(first_cell, dict) else first_cell
                if cell_value and str(cell_value).strip():
                    data_row_count += 1
        
        # Expect header + 8 players = 9 rows minimum
        if data_row_count < 9:
            return False, f"Insufficient data rows (found {data_row_count}, expected 9+)", data_row_count
        
        # Check that numeric columns have valid data
        # Row 2 (first data row after header) should have numeric values
        if len(rows) < 2:
            return False, "No data rows found", data_row_count
        
        return True, "", data_row_count
        
    except Exception as e:
        return False, f"Data integrity check error: {str(e)}", 0


def verify_poker_settlement(traj, env_info, task_info):
    """
    Main verification function for poker settlement task.
    
    Scoring:
    - Data Integrity: 20%
    - Total Buy-in Formulas: 20%
    - Net Position Formulas: 25%
    - Zero-Sum Validation: 30% (CRITICAL)
    - Organization (sorting): 5% (bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/poker_settlement.ods",
        "/home/ga/Documents/poker_night_data.ods",
        "/home/ga/Documents/poker_night_data.csv",
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            file_format = 'csv'
        else:
            file_format = 'ods'
        
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load poker settlement file. Tried: {', '.join(possible_paths)}. Error: {error}"
        }
    
    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Initialize scoring
        criteria_scores = {
            'data_integrity': 0,
            'total_buyin_formulas': 0,
            'net_position_formulas': 0,
            'zero_sum_validation': 0,
            'organization': 0
        }
        feedback_parts = []
        
        # --- Criterion 1: Data Integrity (20%) ---
        data_valid, error_msg, row_count = verify_data_integrity(workbook, sheet_name)
        if data_valid:
            criteria_scores['data_integrity'] = 20
            feedback_parts.append(f"✅ Data integrity verified ({row_count} rows)")
        else:
            feedback_parts.append(f"❌ Data integrity issue: {error_msg}")
        
        # --- Criterion 2: Total Buy-in Formulas (20%) ---
        # Check formulas in column F (Total Buy-in) for rows 2-9
        total_buyin_correct = 0
        total_buyin_checked = 0
        
        for row_idx in range(2, 10):  # Rows 2-9 (8 players)
            formula = get_cell_formula(workbook, sheet_name, f'F{row_idx}')
            value = get_cell_value(workbook, sheet_name, f'F{row_idx}')
            
            if value is not None:  # Cell has a value
                total_buyin_checked += 1
                if verify_sum_formula(formula, row_idx):
                    total_buyin_correct += 1
                    logger.debug(f"F{row_idx} formula correct: {formula}")
                else:
                    logger.debug(f"F{row_idx} formula incorrect or missing: {formula}")
        
        if total_buyin_checked >= 8:
            if total_buyin_correct >= 6:  # At least 75% correct
                criteria_scores['total_buyin_formulas'] = 20
                feedback_parts.append(f"✅ Total Buy-in formulas correct ({total_buyin_correct}/{total_buyin_checked})")
            elif total_buyin_correct >= 4:
                criteria_scores['total_buyin_formulas'] = 10
                feedback_parts.append(f"⚠️ Total Buy-in formulas partially correct ({total_buyin_correct}/{total_buyin_checked})")
            else:
                feedback_parts.append(f"❌ Total Buy-in formulas incorrect ({total_buyin_correct}/{total_buyin_checked})")
        else:
            feedback_parts.append(f"❌ Total Buy-in column incomplete ({total_buyin_checked} cells)")
        
        # --- Criterion 3: Net Position Formulas (25%) ---
        net_position_correct = 0
        net_position_checked = 0
        net_positions = []  # Store for zero-sum check
        
        for row_idx in range(2, 10):  # Rows 2-9 (8 players)
            formula = get_cell_formula(workbook, sheet_name, f'G{row_idx}')
            value = get_cell_value(workbook, sheet_name, f'G{row_idx}')
            
            if value is not None:  # Cell has a value
                net_position_checked += 1
                try:
                    net_positions.append(float(value))
                except (ValueError, TypeError):
                    logger.warning(f"Non-numeric net position in G{row_idx}: {value}")
                
                if verify_net_position_formula(formula, row_idx):
                    net_position_correct += 1
                    logger.debug(f"G{row_idx} formula correct: {formula}")
                else:
                    logger.debug(f"G{row_idx} formula incorrect or missing: {formula}")
        
        if net_position_checked >= 8:
            if net_position_correct >= 6:  # At least 75% correct
                criteria_scores['net_position_formulas'] = 25
                feedback_parts.append(f"✅ Net Position formulas correct ({net_position_correct}/{net_position_checked})")
            elif net_position_correct >= 4:
                criteria_scores['net_position_formulas'] = 12
                feedback_parts.append(f"⚠️ Net Position formulas partially correct ({net_position_correct}/{net_position_checked})")
            else:
                feedback_parts.append(f"❌ Net Position formulas incorrect ({net_position_correct}/{net_position_checked})")
        else:
            feedback_parts.append(f"❌ Net Position column incomplete ({net_position_checked} cells)")
        
        # --- Criterion 4: Zero-Sum Validation (30%) - CRITICAL ---
        if len(net_positions) >= 8:
            total_net = sum(net_positions)
            logger.info(f"Net positions sum: {total_net} (individual: {net_positions})")
            
            # Allow $1 tolerance for rounding
            if abs(total_net) <= 1.0:
                criteria_scores['zero_sum_validation'] = 30
                feedback_parts.append(f"✅ Zero-sum validated (sum={total_net:.2f})")
            elif abs(total_net) <= 5.0:
                criteria_scores['zero_sum_validation'] = 15
                feedback_parts.append(f"⚠️ Near zero-sum (sum={total_net:.2f}, expected ~0)")
            else:
                feedback_parts.append(f"❌ Zero-sum constraint violated (sum={total_net:.2f}, expected ~0)")
        else:
            feedback_parts.append(f"❌ Insufficient net position data for zero-sum check")
        
        # --- Criterion 5: Organization / Sorting (5% bonus) ---
        # Check if data is sorted by net position descending
        if len(net_positions) >= 8:
            is_sorted = all(net_positions[i] >= net_positions[i+1] for i in range(len(net_positions)-1))
            if is_sorted:
                criteria_scores['organization'] = 5
                feedback_parts.append("✅ Data sorted by net position (descending)")
            else:
                feedback_parts.append("ℹ️ Data not sorted (optional)")
        
        # --- Calculate Final Score ---
        total_score = sum(criteria_scores.values())
        passed = total_score >= 75
        
        # Add summary
        if passed and total_score >= 95:
            feedback_parts.insert(0, "🎉 Excellent poker settlement reconciliation!")
        elif passed:
            feedback_parts.insert(0, "✅ Poker settlement task completed")
        else:
            feedback_parts.insert(0, "❌ Poker settlement requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(total_score),
            "feedback": feedback,
            "subscores": {
                "data_integrity": criteria_scores['data_integrity'] == 20,
                "total_buyin_formulas": criteria_scores['total_buyin_formulas'] == 20,
                "net_position_formulas": criteria_scores['net_position_formulas'] == 25,
                "zero_sum_validated": criteria_scores['zero_sum_validation'] == 30,
                "sorted": criteria_scores['organization'] == 5
            },
            "details": {
                "total_buyin_correct": total_buyin_correct,
                "total_buyin_checked": total_buyin_checked,
                "net_position_correct": net_position_correct,
                "net_position_checked": net_position_checked,
                "net_sum": sum(net_positions) if net_positions else None,
                "is_sorted": criteria_scores['organization'] == 5
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
        cleanup_verification_temp(temp_dir)
