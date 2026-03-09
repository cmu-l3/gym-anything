#!/usr/bin/env python3
"""
Verifier for Baby Feeding Tracker task.

Checks:
1. Duration column contains formulas
2. Duration calculations are accurate (spot check)
3. Interval column contains formulas
4. Summary statistics exist and are reasonable
5. Conditional formatting applied
6. Longest sleep correctly identified
7. Minimum 10 data entries
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_to_decimal(time_value) -> float:
    """
    Convert time value to decimal hours for comparison.
    Handles various formats: floats (0.5 = 12 hours), strings, etc.
    
    Returns:
        Decimal hours (e.g., 2.5 for 2:30)
    """
    if time_value is None:
        return 0.0
    
    if isinstance(time_value, (int, float)):
        # ODS stores time as fraction of day (0.5 = 12 hours)
        return time_value * 24
    
    if isinstance(time_value, str):
        # Try to parse string like "2:30" or "02:30:00"
        match = re.match(r'(\d+):(\d+)', time_value)
        if match:
            hours, minutes = int(match.group(1)), int(match.group(2))
            return hours + minutes / 60.0
    
    return 0.0


def verify_baby_feeding_tracker(traj, env_info, task_info):
    """
    Verify the baby feeding tracker task completion.
    
    Checks:
    1. Duration column contains formulas
    2. Duration calculations are accurate
    3. Interval column contains formulas  
    4. Summary statistics exist and are reasonable
    5. Conditional formatting applied
    6. Longest sleep correctly identified
    7. Minimum 10 data entries
    
    Returns:
        Dict with passed, score, feedback, and subscores
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to copy and parse spreadsheet
    container_path = "/home/ga/Documents/baby_feeding_tracker.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env, 
        container_path, 
        ['ods']
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    temp_dir = file_info.get('temp_dir')
    
    try:
        data = file_info['sheet_data']
        sheets = data.get('sheets', {})
        
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = list(sheets.keys())[0]
        rows = sheets[sheet_name]
        
        score = 0
        max_score = 7
        feedback = []
        subscores = {}
        
        # Criterion 1: Check for Duration formulas (Column E, index 4)
        duration_col_idx = 4
        formula_count = 0
        data_rows_checked = 0
        
        for row_idx in range(1, min(len(rows), 14)):  # Skip header (0), check rows 1-13
            if row_idx < len(rows) and duration_col_idx < len(rows[row_idx]):
                cell = rows[row_idx][duration_col_idx]
                data_rows_checked += 1
                
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and '=' in str(formula):
                    formula_count += 1
        
        duration_formulas_present = formula_count >= max(8, int(data_rows_checked * 0.7))
        if duration_formulas_present:
            score += 1
            feedback.append(f"✅ Duration formulas present ({formula_count}/{data_rows_checked} rows)")
            subscores['duration_formulas'] = True
        else:
            feedback.append(f"❌ Duration formulas missing or insufficient ({formula_count}/{data_rows_checked} found)")
            subscores['duration_formulas'] = False
        
        # Criterion 2: Spot-check duration accuracy
        # Check a few rows to see if Duration ≈ End - Start
        accurate_count = 0
        checked_count = 0
        
        for row_idx in [1, 3, 7]:  # Sample rows
            if row_idx >= len(rows):
                continue
            
            row = rows[row_idx]
            if len(row) <= duration_col_idx:
                continue
            
            # Get start time (column C, index 2), end time (column D, index 3)
            start_cell = row[2] if len(row) > 2 else {}
            end_cell = row[3] if len(row) > 3 else {}
            duration_cell = row[duration_col_idx]
            
            start_val = start_cell.get('value') if isinstance(start_cell, dict) else start_cell
            end_val = end_cell.get('value') if isinstance(end_cell, dict) else end_cell
            duration_val = duration_cell.get('value') if isinstance(duration_cell, dict) else duration_cell
            
            if start_val and end_val and duration_val:
                checked_count += 1
                
                # Parse times to decimal hours
                start_hours = parse_time_to_decimal(start_val)
                end_hours = parse_time_to_decimal(end_val)
                duration_hours = parse_time_to_decimal(duration_val)
                
                # Calculate expected duration
                expected = end_hours - start_hours
                if expected < 0:  # Handle overnight period
                    expected += 24
                
                # Check if within tolerance (±0.1 hours = 6 minutes)
                if abs(duration_hours - expected) < 0.1:
                    accurate_count += 1
        
        duration_accurate = checked_count > 0 and accurate_count >= max(1, checked_count - 1)
        if duration_accurate:
            score += 1
            feedback.append(f"✅ Duration calculations accurate ({accurate_count}/{checked_count} checked)")
            subscores['duration_accurate'] = True
        else:
            feedback.append(f"❌ Duration calculations inaccurate ({accurate_count}/{checked_count} checked)")
            subscores['duration_accurate'] = False
        
        # Criterion 3: Check for Interval formulas (Column F, index 5)
        interval_col_idx = 5
        interval_formula_count = 0
        
        for row_idx in range(2, min(len(rows), 14)):  # Start from row 2
            if row_idx < len(rows) and interval_col_idx < len(rows[row_idx]):
                cell = rows[row_idx][interval_col_idx]
                
                # Check if this is a Feed event (column D, index 3)
                event_cell = rows[row_idx][3] if len(rows[row_idx]) > 3 else {}
                event_type = event_cell.get('value') if isinstance(event_cell, dict) else event_cell
                
                if event_type and 'feed' in str(event_type).lower():
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula and '=' in str(formula):
                        interval_formula_count += 1
        
        interval_formulas_present = interval_formula_count >= 3
        if interval_formulas_present:
            score += 1
            feedback.append(f"✅ Interval formulas present ({interval_formula_count} found)")
            subscores['interval_formulas'] = True
        else:
            feedback.append(f"❌ Interval formulas missing ({interval_formula_count} found, need 3+)")
            subscores['interval_formulas'] = False
        
        # Criterion 4: Check summary statistics (look for MIN, MAX/MAXIFS, AVERAGE around rows 14-20)
        summary_functions_found = {
            'min': False,
            'max': False,
            'average': False
        }
        
        for row_idx in range(13, min(len(rows), 25)):
            if row_idx >= len(rows):
                continue
            
            row = rows[row_idx]
            for cell in row:
                formula = str(cell.get('formula', '')).upper() if isinstance(cell, dict) else ''
                
                if 'MIN(' in formula:
                    summary_functions_found['min'] = True
                if 'MAXIFS(' in formula or ('MAX(' in formula and 'SLEEP' in formula.upper()):
                    summary_functions_found['max'] = True
                if 'AVERAGE(' in formula or 'AVG(' in formula:
                    summary_functions_found['average'] = True
        
        summary_count = sum(summary_functions_found.values())
        summary_complete = summary_count >= 2
        
        if summary_complete:
            score += 1
            functions = [k.upper() for k, v in summary_functions_found.items() if v]
            feedback.append(f"✅ Summary statistics present ({', '.join(functions)})")
            subscores['summary_statistics'] = True
        else:
            feedback.append(f"❌ Summary statistics incomplete ({summary_count}/3 found)")
            subscores['summary_statistics'] = False
        
        # Criterion 5: Conditional formatting check
        has_conditional_fmt = check_conditional_formatting(data, sheet_name, "F2:F15")
        
        if has_conditional_fmt:
            score += 1
            feedback.append("✅ Conditional formatting applied")
            subscores['conditional_formatting'] = True
        else:
            feedback.append("❌ Conditional formatting not detected")
            subscores['conditional_formatting'] = False
        
        # Criterion 6: Longest sleep stretch calculated (MAXIFS formula)
        longest_sleep_found = summary_functions_found['max']
        
        if longest_sleep_found:
            score += 1
            feedback.append("✅ Longest sleep stretch formula present (MAXIFS or MAX)")
            subscores['longest_sleep'] = True
        else:
            feedback.append("❌ Longest sleep stretch not calculated")
            subscores['longest_sleep'] = False
        
        # Criterion 7: Minimum 10 data entries
        data_row_count = 0
        for row_idx in range(1, len(rows)):
            row = rows[row_idx]
            # Check if row has data in Date column (Column A, index 0)
            if len(row) > 0:
                date_cell = row[0]
                date_val = date_cell.get('value') if isinstance(date_cell, dict) else date_cell
                if date_val and str(date_val).strip():
                    data_row_count += 1
        
        sufficient_data = data_row_count >= 10
        if sufficient_data:
            score += 1
            feedback.append(f"✅ Sufficient data entries ({data_row_count} rows)")
            subscores['data_completeness'] = True
        else:
            feedback.append(f"❌ Insufficient data entries ({data_row_count}/10 required)")
            subscores['data_completeness'] = False
        
        # Calculate final score
        final_score = int((score / max_score) * 100)
        passed = final_score >= 70  # 70% threshold (5/7 criteria)
        
        feedback_str = " | ".join(feedback)
        feedback_str += f"\n\nFinal Score: {final_score}% ({score}/{max_score} criteria met)"
        
        if passed:
            feedback_str += "\n✅ Baby feeding tracker ready for pediatrician appointment!"
        else:
            feedback_str += "\n❌ Tracker incomplete - needs more work before doctor visit"
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback_str,
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
        cleanup_verification_temp(temp_dir)
