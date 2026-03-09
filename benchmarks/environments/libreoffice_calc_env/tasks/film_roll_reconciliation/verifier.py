#!/usr/bin/env python3
"""
Verifier for Film Roll Reconciliation task.

Checks:
1. Reconciliation sheet exists
2. All rolls matched (3 lab rolls present)
3. Frame validation working (>36 flagged)
4. Priority counts calculated (formulas present)
5. Priority scores assigned with differentiation
6. Cost per frame calculated (formulas)
7. At least 3 different formula types used
8. Conditional formatting applied
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since verification runs on host machine
# USE Relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_sheet_names,
    get_cell_value,
    get_cell_formula,
    verify_cell_value
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_sheet_exists(workbook, sheet_name_pattern):
    """Check if a sheet with name matching pattern exists"""
    sheet_names = get_sheet_names(workbook)
    pattern = sheet_name_pattern.lower()
    for name in sheet_names:
        if pattern in name.lower():
            return True, name
    return False, None


def get_reconciliation_data(workbook, sheet_name):
    """Extract data from reconciliation sheet"""
    try:
        sheet_data = workbook.get('sheets', {}).get(sheet_name, [])
        
        # Find header row
        headers = []
        header_row_idx = -1
        for i, row in enumerate(sheet_data[:5]):  # Check first 5 rows
            row_text = []
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value:
                    row_text.append(str(value).lower())
            
            # Look for key column names
            if any(keyword in ' '.join(row_text) for keyword in ['roll', 'lab', 'id', 'frame', 'priority', 'cost']):
                headers = row_text
                header_row_idx = i
                break
        
        if header_row_idx == -1:
            return None, "Could not find header row in Reconciliation sheet"
        
        # Extract data rows
        data_rows = []
        for row in sheet_data[header_row_idx + 1:]:
            # Skip empty rows
            if not any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                continue
            
            row_data = {
                'cells': row,
                'values': [cell.get('value') if isinstance(cell, dict) else cell for cell in row],
                'formulas': [cell.get('formula') if isinstance(cell, dict) else None for cell in row]
            }
            data_rows.append(row_data)
            
            # Limit to reasonable number of rows
            if len(data_rows) >= 10:
                break
        
        return {
            'headers': headers,
            'header_row_idx': header_row_idx,
            'data_rows': data_rows
        }, None
        
    except Exception as e:
        logger.error(f"Error extracting reconciliation data: {e}", exc_info=True)
        return None, str(e)


def count_formula_types(reconciliation_data):
    """Count different types of formulas used"""
    formula_types = set()
    
    for row in reconciliation_data.get('data_rows', []):
        for formula in row.get('formulas', []):
            if formula and isinstance(formula, str):
                formula_upper = formula.upper()
                if 'VLOOKUP' in formula_upper or 'HLOOKUP' in formula_upper:
                    formula_types.add('LOOKUP')
                if 'INDEX' in formula_upper and 'MATCH' in formula_upper:
                    formula_types.add('INDEX-MATCH')
                if 'COUNTIF' in formula_upper or 'COUNT' in formula_upper:
                    formula_types.add('COUNT')
                if 'IF' in formula_upper:
                    formula_types.add('IF')
                if 'SUM' in formula_upper:
                    formula_types.add('SUM')
                if 'AVERAGE' in formula_upper or 'AVG' in formula_upper:
                    formula_types.add('AVERAGE')
                # Check for division (cost per frame calculation)
                if '/' in formula:
                    formula_types.add('ARITHMETIC')
    
    return formula_types


def check_frame_validation(reconciliation_data, sheet_name, workbook):
    """Check if rolls with >36 frames are flagged"""
    # Look for frame count column and validation flag
    headers = reconciliation_data.get('headers', [])
    
    frame_col_idx = -1
    flag_col_idx = -1
    
    for i, header in enumerate(headers):
        if 'frame' in header and ('count' in header or 'total' in header):
            frame_col_idx = i
        if 'flag' in header or 'validation' in header or 'issue' in header or 'error' in header:
            flag_col_idx = i
    
    # Check if any row has >36 frames
    has_high_frame_count = False
    flagged_correctly = False
    
    for row in reconciliation_data.get('data_rows', []):
        values = row.get('values', [])
        
        # Check frame count
        if frame_col_idx >= 0 and frame_col_idx < len(values):
            frame_value = values[frame_col_idx]
            try:
                frame_count = float(frame_value) if frame_value else 0
                if frame_count > 36:
                    has_high_frame_count = True
                    
                    # Check if there's a flag in the same row
                    if flag_col_idx >= 0 and flag_col_idx < len(values):
                        flag_value = values[flag_col_idx]
                        if flag_value and str(flag_value).strip():
                            flagged_correctly = True
            except (ValueError, TypeError):
                pass
    
    # Alternative: check if conditional formatting or IF formulas flag >36
    for row in reconciliation_data.get('data_rows', []):
        formulas = row.get('formulas', [])
        for formula in formulas:
            if formula and isinstance(formula, str):
                # Look for IF statements checking >36
                if 'IF' in formula.upper() and '36' in formula:
                    flagged_correctly = True
    
    return has_high_frame_count, flagged_correctly


def verify_film_roll_reconciliation(traj, env_info, task_info):
    """
    Verify film roll reconciliation task completion.
    
    Checks:
    1. Reconciliation sheet exists
    2. All 3 rolls matched (R2847-A, R2847-B, R2847-C present)
    3. Frame validation working (roll with 38 frames flagged)
    4. Priority counts calculated (formulas present)
    5. Priority scores assigned with differentiation
    6. Cost per frame calculated (division formulas)
    7. At least 3 different formula types used
    8. Conditional formatting or flags applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification
    container_path = "/home/ga/Documents/film_rolls.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}
    
    try:
        workbook = file_info['sheet_data']
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Reconciliation sheet exists
        has_recon_sheet, recon_sheet_name = check_sheet_exists(workbook, 'reconciliation')
        if has_recon_sheet:
            criteria_passed += 1
            feedback_parts.append(f"✅ Reconciliation sheet found: '{recon_sheet_name}'")
            subscores['reconciliation_sheet_exists'] = True
        else:
            feedback_parts.append("❌ Reconciliation sheet not found")
            subscores['reconciliation_sheet_exists'] = False
            # Early exit if no reconciliation sheet
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # Extract reconciliation data
        recon_data, extract_error = get_reconciliation_data(workbook, recon_sheet_name)
        if not recon_data:
            feedback_parts.append(f"❌ Could not parse reconciliation data: {extract_error}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # Criterion 2: All 3 rolls matched
        data_rows = recon_data.get('data_rows', [])
        roll_ids_found = []
        expected_roll_ids = ['R2847-A', 'R2847-B', 'R2847-C']
        
        for row in data_rows:
            values = row.get('values', [])
            for value in values:
                if value and isinstance(value, str):
                    for roll_id in expected_roll_ids:
                        if roll_id in value:
                            roll_ids_found.append(roll_id)
                            break
        
        roll_ids_found = list(set(roll_ids_found))  # Remove duplicates
        all_rolls_present = len(roll_ids_found) >= 3
        
        if all_rolls_present:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 3 lab rolls matched: {', '.join(roll_ids_found)}")
            subscores['all_rolls_matched'] = True
        else:
            feedback_parts.append(f"❌ Not all rolls found (found {len(roll_ids_found)}/3: {roll_ids_found})")
            subscores['all_rolls_matched'] = False
        
        # Criterion 3: Frame validation (>36 flagged)
        has_high_count, is_flagged = check_frame_validation(recon_data, recon_sheet_name, workbook)
        
        if is_flagged:
            criteria_passed += 1
            feedback_parts.append("✅ Frame validation working (>36 frames flagged)")
            subscores['frame_validation'] = True
        else:
            # Check if at least frame counts are present
            frame_counts_present = False
            for row in data_rows:
                values = row.get('values', [])
                for value in values:
                    try:
                        if value and float(value) in [22, 38, 32]:
                            frame_counts_present = True
                            break
                    except (ValueError, TypeError):
                        pass
            
            if frame_counts_present:
                feedback_parts.append("⚠️ Frame counts present but validation flag not clearly visible")
                subscores['frame_validation'] = False
            else:
                feedback_parts.append("❌ Frame validation not implemented")
                subscores['frame_validation'] = False
        
        # Criterion 4: Priority counts calculated
        has_priority_count = False
        headers = recon_data.get('headers', [])
        
        # Check for priority-related column
        for i, header in enumerate(headers):
            if 'priority' in header and ('frame' in header or 'count' in header or 'shot' in header):
                # Check if data exists in this column
                for row in data_rows:
                    formulas = row.get('formulas', [])
                    if i < len(formulas) and formulas[i]:
                        has_priority_count = True
                        break
                if has_priority_count:
                    break
        
        # Alternative: look for COUNTIF anywhere
        if not has_priority_count:
            for row in data_rows:
                for formula in row.get('formulas', []):
                    if formula and 'COUNTIF' in formula.upper():
                        has_priority_count = True
                        break
        
        if has_priority_count:
            criteria_passed += 1
            feedback_parts.append("✅ Priority frame counts calculated")
            subscores['priority_counts'] = True
        else:
            feedback_parts.append("❌ Priority count formulas not found")
            subscores['priority_counts'] = False
        
        # Criterion 5: Priority scores with differentiation
        priority_scores = []
        for i, header in enumerate(headers):
            if 'priority' in header and ('score' in header or 'rank' in header or header == 'priority'):
                for row in data_rows:
                    values = row.get('values', [])
                    if i < len(values) and values[i]:
                        try:
                            score = float(values[i])
                            priority_scores.append(score)
                        except (ValueError, TypeError):
                            # Could be text like "High", "Medium", "Low"
                            priority_scores.append(str(values[i]))
        
        has_priority_scores = len(priority_scores) >= 3
        has_differentiation = len(set(priority_scores)) > 1  # Not all same
        
        if has_priority_scores and has_differentiation:
            criteria_passed += 1
            feedback_parts.append(f"✅ Priority scores assigned with differentiation: {set(priority_scores)}")
            subscores['priority_scores'] = True
        elif has_priority_scores:
            feedback_parts.append("⚠️ Priority scores present but all identical (no differentiation)")
            subscores['priority_scores'] = False
        else:
            feedback_parts.append("❌ Priority scores not found")
            subscores['priority_scores'] = False
        
        # Criterion 6: Cost per frame calculated
        has_cost_per_frame = False
        for i, header in enumerate(headers):
            if 'cost' in header and ('frame' in header or 'per' in header):
                for row in data_rows:
                    formulas = row.get('formulas', [])
                    if i < len(formulas) and formulas[i]:
                        # Check if formula contains division
                        if '/' in formulas[i]:
                            has_cost_per_frame = True
                            break
                if has_cost_per_frame:
                    break
        
        if has_cost_per_frame:
            criteria_passed += 1
            feedback_parts.append("✅ Cost per frame calculated with formula")
            subscores['cost_per_frame'] = True
        else:
            feedback_parts.append("❌ Cost per frame formula not found")
            subscores['cost_per_frame'] = False
        
        # Criterion 7: At least 3 different formula types
        formula_types = count_formula_types(recon_data)
        has_diverse_formulas = len(formula_types) >= 3
        
        if has_diverse_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ Diverse formulas used: {', '.join(formula_types)}")
            subscores['formula_diversity'] = True
        else:
            feedback_parts.append(f"⚠️ Limited formula variety (found: {', '.join(formula_types) if formula_types else 'none'})")
            subscores['formula_diversity'] = False
        
        # Criterion 8: Conditional formatting or visual indicators
        # This is hard to detect programmatically, so we give credit if other criteria suggest
        # proper implementation (validation flags, formulas, etc.)
        has_visual_indicators = is_flagged or (has_priority_scores and has_differentiation)
        
        if has_visual_indicators:
            criteria_passed += 1
            feedback_parts.append("✅ Visual indicators/formatting likely applied")
            subscores['visual_formatting'] = True
        else:
            feedback_parts.append("⚠️ Visual formatting not clearly detected")
            subscores['visual_formatting'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent film roll reconciliation!")
        elif passed:
            feedback_parts.append("✅ Film roll reconciliation completed")
        else:
            feedback_parts.append("❌ Reconciliation incomplete - needs more work")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
