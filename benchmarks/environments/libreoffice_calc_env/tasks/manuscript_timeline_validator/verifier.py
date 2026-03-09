#!/usr/bin/env python3
"""
Verifier for Manuscript Timeline Validator task.
Checks for validation formulas detecting planted conflicts.
"""

import sys
import os
import logging
import re

# Use relative path to utils folder (host machine, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    parse_ods_file,
    parse_csv_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def detect_formulas_in_row(row_data, start_col=7):
    """
    Detect if any cells in a row contain formulas (start with '=')
    
    Args:
        row_data: List of cell data dicts
        start_col: Starting column index to check (default 7 = column H)
    
    Returns:
        List of (col_idx, formula) tuples
    """
    formulas = []
    for col_idx in range(start_col, len(row_data)):
        cell = row_data[col_idx]
        if isinstance(cell, dict):
            formula = cell.get('formula')
            if formula and (formula.startswith('=') or formula.startswith('of:=')):
                formulas.append((col_idx, formula))
    return formulas


def check_for_conflict_indicators(cell_value):
    """
    Check if a cell value indicates a conflict
    
    Args:
        cell_value: Cell value (string or other)
    
    Returns:
        True if cell indicates conflict, False otherwise
    """
    if not cell_value:
        return False
    
    value_str = str(cell_value).upper().strip()
    conflict_keywords = ['CONFLICT', 'ERROR', 'MISSING', 'INVALID', 'FAIL', 'WARNING', 'PROBLEM']
    
    return any(keyword in value_str for keyword in conflict_keywords)


def analyze_validation_formulas(workbook, sheet_name):
    """
    Analyze the spreadsheet for validation formulas and conflicts detected
    
    Returns:
        dict with analysis results
    """
    result = {
        'has_formulas': False,
        'formula_columns': [],
        'conflicts_detected': [],
        'total_conflicts': 0,
        'rows_with_formulas': 0,
        'false_positives': 0,
        'summary_stats_found': False
    }
    
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return result
        
        rows = sheets[sheet_name]
        
        # Known conflict rows (0-indexed):
        # Row 12 (Scene 12, first occurrence): Character location conflict (Sarah at Airport Terminal)
        # Row 13 (Scene 12, duplicate): Character location conflict (Sarah at Precinct, same timestamp)
        # Row 23 (Scene 23): POV Marcus not in Characters Present
        # Row 31 (Scene 31): Timeline reversal (17:30 after 18:00)
        
        known_conflict_rows = {12, 13, 23, 31}  # 0-indexed, but row 0 is header, so these are data rows
        
        # Analyze each row for validation formulas
        for row_idx, row_data in enumerate(rows):
            if row_idx == 0:  # Skip header
                continue
            
            # Check for formulas in columns beyond the original data (col 7+)
            formulas = detect_formulas_in_row(row_data, start_col=7)
            
            if formulas:
                result['has_formulas'] = True
                result['rows_with_formulas'] += 1
                
                # Track which columns have formulas
                for col_idx, formula in formulas:
                    if col_idx not in result['formula_columns']:
                        result['formula_columns'].append(col_idx)
                
                # Check if any formula result indicates a conflict
                conflict_found = False
                for col_idx, formula in formulas:
                    if col_idx < len(row_data):
                        cell_value = row_data[col_idx].get('value') if isinstance(row_data[col_idx], dict) else row_data[col_idx]
                        if check_for_conflict_indicators(cell_value):
                            conflict_found = True
                            result['conflicts_detected'].append(row_idx)
                            result['total_conflicts'] += 1
                            break
                
                # Check for false positives (valid rows incorrectly flagged)
                if conflict_found and row_idx not in known_conflict_rows:
                    # Check if this is genuinely a false positive or just a different row number
                    # Scene 12 is special - it has 2 rows with same scene number
                    scene_num = get_cell_value(workbook, sheet_name, f'A{row_idx+1}')
                    if scene_num != 12 or row_idx not in {12, 13}:
                        result['false_positives'] += 1
        
        # Check for summary statistics (look in first few rows or last few rows)
        # Summary might use COUNTIF or similar functions
        for check_row_idx in list(range(min(5, len(rows)))) + list(range(max(0, len(rows)-5), len(rows))):
            if check_row_idx >= len(rows):
                continue
            row_data = rows[check_row_idx]
            for cell in row_data:
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    if formula and ('COUNTIF' in formula.upper() or 'SUM(' in formula.upper()):
                        result['summary_stats_found'] = True
                        break
            if result['summary_stats_found']:
                break
        
        # Alternative: Check if any cell contains text like "Total Conflicts" or similar
        for row_data in rows[:10]:  # Check first 10 rows
            for cell in row_data:
                if isinstance(cell, dict):
                    value = cell.get('value', '')
                    if isinstance(value, str) and ('TOTAL' in value.upper() or 'CONFLICTS' in value.upper() or 'SUMMARY' in value.upper()):
                        result['summary_stats_found'] = True
                        break
        
        logger.info(f"Analysis: {result['rows_with_formulas']} rows with formulas, {result['total_conflicts']} conflicts detected")
        
    except Exception as e:
        logger.error(f"Error analyzing formulas: {e}", exc_info=True)
    
    return result


def check_known_conflicts_detected(workbook, sheet_name):
    """
    Check if the 3 known planted conflicts were correctly identified
    
    Returns:
        dict with conflict detection results
    """
    result = {
        'conflict_12_detected': False,  # Sarah location conflict (Scene 12)
        'conflict_23_detected': False,  # Marcus POV not present (Scene 23)
        'conflict_31_detected': False,  # Timeline reversal (Scene 31)
        'details': []
    }
    
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return result
        
        rows = sheets[sheet_name]
        
        # Check Scene 12 (rows 12-13, 0-indexed) - should have conflict indicator
        # Scene 12 appears twice with different locations at same timestamp
        for check_row in [12, 13]:  # Check both rows for Scene 12
            if check_row >= len(rows):
                continue
            row_data = rows[check_row]
            # Check validation columns (7+)
            for col_idx in range(7, len(row_data)):
                cell = row_data[col_idx]
                if isinstance(cell, dict):
                    value = cell.get('value')
                    if check_for_conflict_indicators(value):
                        result['conflict_12_detected'] = True
                        result['details'].append(f"✓ Scene 12 location conflict detected in row {check_row+1}")
                        break
            if result['conflict_12_detected']:
                break
        
        # Check Scene 23 (row 23, 0-indexed) - POV character not present
        if 23 < len(rows):
            row_data = rows[23]
            for col_idx in range(7, len(row_data)):
                cell = row_data[col_idx]
                if isinstance(cell, dict):
                    value = cell.get('value')
                    if check_for_conflict_indicators(value):
                        result['conflict_23_detected'] = True
                        result['details'].append(f"✓ Scene 23 POV missing detected in row 24")
                        break
        
        # Check Scene 31 (row 31, 0-indexed) - Timeline reversal
        if 31 < len(rows):
            row_data = rows[31]
            for col_idx in range(7, len(row_data)):
                cell = row_data[col_idx]
                if isinstance(cell, dict):
                    value = cell.get('value')
                    if check_for_conflict_indicators(value):
                        result['conflict_31_detected'] = True
                        result['details'].append(f"✓ Scene 31 timeline reversal detected in row 32")
                        break
        
    except Exception as e:
        logger.error(f"Error checking known conflicts: {e}", exc_info=True)
    
    return result


def verify_manuscript_timeline(traj, env_info, task_info):
    """
    Verify manuscript timeline validator task completion.
    
    Checks:
    1. Validation formula columns added
    2. Known conflicts detected (3 planted conflicts)
    3. Valid scenes not falsely flagged (low false positives)
    4. Conditional formatting applied (harder to verify, give partial credit)
    5. Summary statistics present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try ODS first, then CSV
    temp_dir = None
    success = False
    workbook = None
    
    for fmt, path in [('ods', '/home/ga/Documents/mystery_novel_scenes.ods'),
                      ('ods', '/home/ga/Documents/validated_manuscript.ods'),
                      ('csv', '/home/ga/Documents/mystery_novel_scenes.csv')]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        # Get sheet name
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Validation formulas added (at least 2 formula columns)
        analysis = analyze_validation_formulas(workbook, sheet_name)
        
        if analysis['has_formulas'] and len(analysis['formula_columns']) >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Validation formulas added ({len(analysis['formula_columns'])} columns)")
        elif analysis['has_formulas']:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some formulas added but need at least 2 validation columns (found {len(analysis['formula_columns'])})")
        else:
            feedback_parts.append("❌ No validation formulas found")
        
        # Criterion 2: Known conflicts detected
        conflict_check = check_known_conflicts_detected(workbook, sheet_name)
        conflicts_found = sum([
            conflict_check['conflict_12_detected'],
            conflict_check['conflict_23_detected'],
            conflict_check['conflict_31_detected']
        ])
        
        if conflicts_found == 3:
            criteria_passed += 1
            feedback_parts.append("✅ All 3 planted conflicts detected")
            for detail in conflict_check['details']:
                logger.info(detail)
        elif conflicts_found >= 2:
            criteria_passed += 0.7
            feedback_parts.append(f"⚠️ {conflicts_found}/3 planted conflicts detected")
        elif conflicts_found >= 1:
            criteria_passed += 0.3
            feedback_parts.append(f"⚠️ Only {conflicts_found}/3 planted conflicts detected")
        else:
            feedback_parts.append("❌ Known conflicts not detected")
        
        # Criterion 3: Low false positives (max 1-2 acceptable)
        if analysis['false_positives'] <= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Valid scenes not falsely flagged ({analysis['false_positives']} false positives)")
        elif analysis['false_positives'] <= 3:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some false positives detected ({analysis['false_positives']})")
        else:
            feedback_parts.append(f"❌ Too many false positives ({analysis['false_positives']})")
        
        # Criterion 4: Conditional formatting applied
        # Note: This is hard to verify from parsed data, so we'll give credit if conflicts detected
        if analysis['total_conflicts'] >= 2:
            criteria_passed += 0.5  # Partial credit - assume they added some highlighting
            feedback_parts.append("⚠️ Conflict detection present (conditional formatting not fully verifiable)")
        else:
            feedback_parts.append("❌ Conditional formatting verification inconclusive")
        
        # Criterion 5: Summary statistics present
        if analysis['summary_stats_found']:
            criteria_passed += 1
            feedback_parts.append("✅ Summary statistics found")
        else:
            feedback_parts.append("❌ Summary statistics not found")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria (80%)
        
        # Additional feedback
        if passed:
            feedback_parts.append("🎉 Timeline validation system successfully implemented!")
        else:
            feedback_parts.append("📝 Timeline validation needs improvement")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_added": len(analysis['formula_columns']) >= 2,
                "conflicts_detected": conflicts_found,
                "false_positives": analysis['false_positives'],
                "summary_stats": analysis['summary_stats_found']
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
