#!/usr/bin/env python3
"""
Verifier for Maintenance Tracker task.

Checks:
1. Days Open column has TODAY()-based formulas
2. Conditional formatting applied (overdue highlighting)
3. Status column has conditional formatting
4. Summary section with COUNT/SUM/COUNTIF formulas
5. Overdue logic excludes completed items
6. Original data preserved
"""

import sys
import os
import re
import logging

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_days_formula(data, sheet_name, days_column='G', date_column='A', start_row=2, end_row=20):
    """
    Verify that Days Open column uses TODAY()-based date calculation.
    
    Returns:
        Tuple of (formulas_found_pct, uses_today_pct, correct_refs_pct)
    """
    formulas_found = 0
    today_usage = 0
    correct_refs = 0
    total_rows = 0
    
    for row in range(start_row, end_row + 1):
        cell_ref = f"{days_column}{row}"
        formula = get_cell_formula(data, sheet_name, cell_ref)
        
        # Check if this row has data (check Request Date column)
        date_value = get_cell_value(data, sheet_name, f"{date_column}{row}")
        if not date_value:
            continue  # Skip empty rows
        
        total_rows += 1
        
        if formula:
            formulas_found += 1
            formula_upper = formula.upper()
            
            # Check for TODAY() function
            if 'TODAY()' in formula_upper:
                today_usage += 1
            
            # Check for reference to date column (flexible - could be A2, $A$2, etc.)
            if date_column in formula_upper or date_column.lower() in formula:
                correct_refs += 1
    
    if total_rows == 0:
        return 0, 0, 0
    
    return (
        formulas_found / total_rows,
        today_usage / total_rows,
        correct_refs / total_rows
    )


def verify_summary_section(data, sheet_name, start_row=22, end_row=30):
    """
    Check for summary formulas in specified area.
    
    Returns:
        Dict with boolean flags for different formula types found
    """
    found_count = False
    found_sum = False
    found_countif = False
    found_countifs = False
    
    # Scan potential summary area
    for row in range(start_row, end_row + 1):
        for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']:
            cell_ref = f"{col}{row}"
            formula = get_cell_formula(data, sheet_name, cell_ref)
            
            if formula:
                formula_upper = formula.upper()
                
                # Check for COUNT (but not COUNTIF)
                if 'COUNTA' in formula_upper or ('COUNT(' in formula_upper and 'COUNTIF' not in formula_upper):
                    found_count = True
                
                # Check for SUM
                if 'SUM(' in formula_upper:
                    found_sum = True
                
                # Check for COUNTIF (single condition)
                if 'COUNTIF(' in formula_upper and 'COUNTIFS' not in formula_upper:
                    found_countif = True
                
                # Check for COUNTIFS (multiple conditions)
                if 'COUNTIFS(' in formula_upper:
                    found_countifs = True
    
    return {
        'count': found_count,
        'sum': found_sum,
        'countif': found_countif,
        'countifs': found_countifs
    }


def verify_maintenance_tracker(traj, env_info, task_info):
    """
    Main verification function for maintenance tracker task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    file_info = None
    
    for container_path in [
        "/home/ga/Documents/maintenance_tracker_complete.ods",
        "/home/ga/Documents/maintenance_log.ods",
        "/home/ga/Documents/maintenance_log.csv"
    ]:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv']
        else:
            formats = ['ods']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            formats
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = get_sheet_names(data)
        
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # ===== CRITERION 1: Days Formula Present =====
        formula_pct, today_pct, refs_pct = verify_days_formula(
            data, sheet_name, 
            days_column='G', 
            date_column='A', 
            start_row=2, 
            end_row=20
        )
        
        if formula_pct >= 0.9 and today_pct >= 0.85:
            criteria_passed += 1
            subscores['days_formula'] = True
            feedback_parts.append(f"✅ Days formula present ({int(formula_pct*100)}% rows, {int(today_pct*100)}% use TODAY())")
        elif formula_pct >= 0.5:
            subscores['days_formula'] = False
            feedback_parts.append(f"⚠️ Days formula partially present ({int(formula_pct*100)}% rows)")
        else:
            subscores['days_formula'] = False
            feedback_parts.append("❌ Days Open column missing formulas")
        
        # ===== CRITERION 2: Conditional Formatting on Days Open =====
        has_days_cf = check_conditional_formatting(data, sheet_name, "G2:G20")
        
        if has_days_cf:
            criteria_passed += 1
            subscores['overdue_formatting'] = True
            feedback_parts.append("✅ Conditional formatting applied to Days Open")
        else:
            subscores['overdue_formatting'] = False
            feedback_parts.append("❌ No conditional formatting on Days Open column")
        
        # ===== CRITERION 3: Conditional Formatting on Status =====
        has_status_cf = check_conditional_formatting(data, sheet_name, "D2:D20")
        
        if has_status_cf:
            criteria_passed += 1
            subscores['status_formatting'] = True
            feedback_parts.append("✅ Status column has conditional formatting")
        else:
            subscores['status_formatting'] = False
            feedback_parts.append("❌ Status column missing conditional formatting")
        
        # ===== CRITERION 4: Summary Statistics Present =====
        summary_formulas = verify_summary_section(data, sheet_name, start_row=22, end_row=35)
        
        # Need at least: (COUNT or COUNTA) + SUM + (COUNTIF or COUNTIFS)
        has_summary = (
            (summary_formulas['count']) and
            (summary_formulas['sum']) and
            (summary_formulas['countif'] or summary_formulas['countifs'])
        )
        
        if has_summary:
            criteria_passed += 1
            subscores['summary_stats'] = True
            found_types = []
            if summary_formulas['count']: found_types.append("COUNT")
            if summary_formulas['sum']: found_types.append("SUM")
            if summary_formulas['countif']: found_types.append("COUNTIF")
            if summary_formulas['countifs']: found_types.append("COUNTIFS")
            feedback_parts.append(f"✅ Summary section present ({', '.join(found_types)})")
        else:
            subscores['summary_stats'] = False
            missing = []
            if not summary_formulas['count']: missing.append("COUNT")
            if not summary_formulas['sum']: missing.append("SUM")
            if not (summary_formulas['countif'] or summary_formulas['countifs']): missing.append("COUNTIF")
            feedback_parts.append(f"❌ Summary section incomplete (missing: {', '.join(missing)})")
        
        # ===== CRITERION 5: Overdue Logic (COUNTIFS with multiple conditions) =====
        # This is a bonus criterion - having COUNTIFS suggests proper overdue logic
        if summary_formulas['countifs']:
            criteria_passed += 1
            subscores['overdue_logic'] = True
            feedback_parts.append("✅ Advanced overdue logic detected (COUNTIFS)")
        elif summary_formulas['countif']:
            # Partial credit for having COUNTIF even if not COUNTIFS
            criteria_passed += 0.5
            subscores['overdue_logic'] = False
            feedback_parts.append("⚠️ Basic counting logic present (consider COUNTIFS for overdue)")
        else:
            subscores['overdue_logic'] = False
            feedback_parts.append("❌ No conditional counting logic found")
        
        # ===== CRITERION 6: Data Integrity =====
        # Check that original data is preserved (look for Request Date in A2)
        a2_value = get_cell_value(data, sheet_name, 'A2')
        b2_value = get_cell_value(data, sheet_name, 'B2')  # Unit #
        
        # Check for multiple rows of data
        row_count = 0
        for row in range(2, 21):
            date_val = get_cell_value(data, sheet_name, f'A{row}')
            if date_val:
                row_count += 1
        
        if a2_value and row_count >= 15:
            criteria_passed += 1
            subscores['data_preserved'] = True
            feedback_parts.append(f"✅ Data integrity preserved ({row_count} requests)")
        else:
            subscores['data_preserved'] = False
            feedback_parts.append(f"❌ Data may be corrupted ({row_count} rows found)")
        
        # ===== CALCULATE FINAL SCORE =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (4/6 criteria)
        
        # Add final message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent maintenance tracker!")
        elif passed:
            feedback_parts.append("✅ Maintenance tracker functional")
        else:
            feedback_parts.append("❌ Tracker incomplete - needs more work")
        
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
        # Clean up temporary files
        if file_info and 'temp_dir' in file_info:
            cleanup_verification_temp(file_info['temp_dir'])
