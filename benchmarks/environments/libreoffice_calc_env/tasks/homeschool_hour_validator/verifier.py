#!/usr/bin/env python3
"""
Verifier for Homeschool Hour Validator task.

Validates:
1. SUMIF formulas present in summary section
2. Calculations accurate (compare against independently calculated totals)
3. Deficiency identification correct
4. Conditional formatting applied
5. Complete subject coverage
"""

import sys
import os
import logging
import re
from collections import defaultdict

# Use relative path to utils
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

# State requirements
STATE_REQUIREMENTS = {
    'Mathematics': 120,
    'Language Arts': 160,
    'Science': 100,
    'Social Studies': 100,
    'Physical Education': 60,
    'Arts': 40
}


def normalize_subject_name(subject):
    """Normalize subject name for comparison"""
    if not subject:
        return ""
    return subject.strip().lower()


def independently_calculate_hours(workbook, sheet_name):
    """
    Independently calculate total hours per subject from lesson log.
    Returns dict: {subject: total_hours}
    """
    hours_by_subject = defaultdict(float)
    
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Skip header row (row 0), process data rows
        for row_idx, row in enumerate(sheet_rows[1:], start=2):
            if len(row) < 3:
                continue
            
            # Column B (index 1): Subject
            # Column C (index 2): Duration
            subject_cell = row[1] if len(row) > 1 else {}
            duration_cell = row[2] if len(row) > 2 else {}
            
            subject = subject_cell.get('value') if isinstance(subject_cell, dict) else subject_cell
            duration = duration_cell.get('value') if isinstance(duration_cell, dict) else duration_cell
            
            # Stop if we hit empty rows (end of lesson log)
            if not subject or subject == "":
                continue
            
            # Skip if this looks like a summary section
            if normalize_subject_name(subject) in ['subject', 'total', 'summary']:
                continue
            
            # Try to convert duration to float
            try:
                duration_float = float(duration) if duration else 0.0
                hours_by_subject[normalize_subject_name(subject)] += duration_float
            except (ValueError, TypeError):
                continue
    
    except Exception as e:
        logger.error(f"Error calculating hours: {e}", exc_info=True)
    
    return dict(hours_by_subject)


def find_summary_section(workbook, sheet_name):
    """
    Find the summary section in the spreadsheet.
    Returns: (start_row, columns_dict) where columns_dict maps 'subject', 'completed', etc. to column indices
    """
    sheet_rows = workbook['sheets'][sheet_name]
    
    # Look for keywords that indicate summary section
    summary_keywords = ['hours completed', 'completed', 'total', 'status', 'difference', 'deficient']
    
    for row_idx, row in enumerate(sheet_rows):
        # Check if this row contains summary headers
        row_text = []
        for cell in row[:10]:  # Check first 10 columns
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value:
                row_text.append(str(value).lower())
        
        row_text_joined = ' '.join(row_text)
        
        # If we find multiple summary keywords in one row, this is likely the header
        keyword_count = sum(1 for keyword in summary_keywords if keyword in row_text_joined)
        if keyword_count >= 2:
            logger.info(f"Found summary section header at row {row_idx + 1}")
            
            # Map column headers to indices
            columns = {}
            for col_idx, cell in enumerate(row[:10]):
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value:
                    value_lower = str(value).lower()
                    if 'subject' in value_lower and 'completed' not in value_lower:
                        columns['subject'] = col_idx
                    elif 'completed' in value_lower or 'actual' in value_lower:
                        columns['completed'] = col_idx
                    elif 'required' in value_lower or 'minimum' in value_lower:
                        columns['required'] = col_idx
                    elif 'difference' in value_lower or 'surplus' in value_lower or 'gap' in value_lower:
                        columns['difference'] = col_idx
                    elif 'status' in value_lower:
                        columns['status'] = col_idx
            
            return row_idx, columns
    
    return None, {}


def check_formula_patterns(formula_text):
    """Check if formula contains SUMIF, SUMIFS, or equivalent aggregation"""
    if not formula_text:
        return False
    
    formula_upper = formula_text.upper()
    
    # Check for SUMIF/SUMIFS
    if 'SUMIF' in formula_upper:
        return True
    
    # Check for array formula with SUM and IF
    if 'SUM' in formula_upper and 'IF' in formula_upper:
        return True
    
    # Check for DSUM (database sum)
    if 'DSUM' in formula_upper:
        return True
    
    return False


def verify_homeschool_compliance(traj, env_info, task_info):
    """
    Main verification function for homeschool hour validator task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/homeschool_log.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # Step 1: Independently calculate expected hours
        expected_hours = independently_calculate_hours(workbook, sheet_name)
        logger.info(f"Expected hours by subject: {expected_hours}")
        
        # Step 2: Find summary section
        summary_row, summary_cols = find_summary_section(workbook, sheet_name)
        
        if summary_row is None:
            feedback_parts.append("❌ No summary section found (expected headers: Subject, Hours Completed, Status, etc.)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        logger.info(f"Summary section at row {summary_row + 1}, columns: {summary_cols}")
        
        # Step 3: Check formulas and calculations for each subject
        subjects_found = []
        formulas_found = 0
        calculations_correct = 0
        deficiency_logic_correct = 0
        
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Check rows after header
        for offset in range(1, 15):  # Check up to 15 rows after header
            row_idx = summary_row + offset
            if row_idx >= len(sheet_rows):
                break
            
            row = sheet_rows[row_idx]
            
            # Get subject name
            subject_col = summary_cols.get('subject', 0)
            if subject_col >= len(row):
                continue
            
            subject_cell = row[subject_col]
            subject_name = subject_cell.get('value') if isinstance(subject_cell, dict) else subject_cell
            
            if not subject_name or str(subject_name).strip() == "":
                continue
            
            subject_normalized = normalize_subject_name(subject_name)
            
            # Check if this is one of the required subjects
            matched_subject = None
            for req_subject in STATE_REQUIREMENTS.keys():
                if normalize_subject_name(req_subject) == subject_normalized:
                    matched_subject = req_subject
                    break
            
            if not matched_subject:
                continue
            
            subjects_found.append(matched_subject)
            logger.info(f"Found subject '{matched_subject}' at row {row_idx + 1}")
            
            # Check "Hours Completed" column for formula
            completed_col = summary_cols.get('completed')
            if completed_col is not None and completed_col < len(row):
                completed_cell = row[completed_col]
                completed_value = completed_cell.get('value') if isinstance(completed_cell, dict) else completed_cell
                completed_formula = completed_cell.get('formula') if isinstance(completed_cell, dict) else None
                
                # Check for formula
                if completed_formula and check_formula_patterns(completed_formula):
                    formulas_found += 1
                    logger.info(f"  Formula found: {completed_formula}")
                
                # Check calculation accuracy
                try:
                    completed_float = float(completed_value) if completed_value else 0.0
                    expected_float = expected_hours.get(subject_normalized, 0.0)
                    
                    if abs(completed_float - expected_float) <= 0.5:
                        calculations_correct += 1
                        logger.info(f"  Calculation correct: {completed_float} ≈ {expected_float}")
                    else:
                        logger.warning(f"  Calculation off: {completed_float} vs expected {expected_float}")
                except (ValueError, TypeError) as e:
                    logger.warning(f"  Could not verify calculation: {e}")
            
            # Check status/difference for deficiency logic
            status_col = summary_cols.get('status')
            difference_col = summary_cols.get('difference')
            required_col = summary_cols.get('required')
            
            # Determine if this subject should be compliant or deficient
            expected_float = expected_hours.get(subject_normalized, 0.0)
            required_hours = STATE_REQUIREMENTS.get(matched_subject, 0)
            is_compliant = expected_float >= required_hours
            
            # Check status column
            if status_col is not None and status_col < len(row):
                status_cell = row[status_col]
                status_value = status_cell.get('value') if isinstance(status_cell, dict) else status_cell
                
                if status_value:
                    status_str = str(status_value).lower()
                    
                    compliant_terms = ['compliant', 'complete', 'met', 'sufficient', 'pass', 'yes', 'ok']
                    deficient_terms = ['deficient', 'under', 'short', 'insufficient', 'fail', 'no']
                    
                    status_correct = False
                    if is_compliant and any(term in status_str for term in compliant_terms):
                        status_correct = True
                    elif not is_compliant and any(term in status_str for term in deficient_terms):
                        status_correct = True
                    
                    if status_correct:
                        deficiency_logic_correct += 1
                        logger.info(f"  Status correct: '{status_value}' for {matched_subject}")
                    else:
                        logger.warning(f"  Status incorrect: '{status_value}' (should be {'COMPLIANT' if is_compliant else 'DEFICIENT'})")
        
        # Criterion 1: Formulas present
        if formulas_found >= 4:  # At least 4 subjects with formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ SUMIF formulas detected ({formulas_found} subjects)")
            subscores['formulas_present'] = True
        else:
            feedback_parts.append(f"❌ Insufficient formulas found ({formulas_found}/6 subjects)")
            subscores['formulas_present'] = False
        
        # Criterion 2: Calculations accurate
        if calculations_correct >= 4:  # At least 4 subjects calculated correctly
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations accurate ({calculations_correct}/6 subjects within tolerance)")
            subscores['calculations_accurate'] = True
        else:
            feedback_parts.append(f"❌ Calculations inaccurate ({calculations_correct}/6 subjects correct)")
            subscores['calculations_accurate'] = False
        
        # Criterion 3: Deficiency identification
        if deficiency_logic_correct >= 4:  # At least 4 subjects with correct status
            criteria_passed += 1
            feedback_parts.append(f"✅ Deficiency logic correct ({deficiency_logic_correct}/6 subjects)")
            subscores['deficiency_identified'] = True
        else:
            feedback_parts.append(f"❌ Deficiency logic incorrect ({deficiency_logic_correct}/6 subjects)")
            subscores['deficiency_identified'] = False
        
        # Criterion 4: Conditional formatting (best effort check)
        has_formatting = check_conditional_formatting(workbook, sheet_name, "A1:Z200")
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
            subscores['visual_formatting'] = True
        else:
            # Give partial credit if status column exists with clear indicators
            if deficiency_logic_correct >= 3:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Conditional formatting not clearly detected (partial credit for status column)")
                subscores['visual_formatting'] = 0.5
            else:
                feedback_parts.append("❌ No conditional formatting detected")
                subscores['visual_formatting'] = False
        
        # Criterion 5: Complete coverage
        if len(subjects_found) >= 5:  # At least 5 of 6 subjects covered
            criteria_passed += 1
            feedback_parts.append(f"✅ Complete subject coverage ({len(subjects_found)}/6 subjects)")
            subscores['complete_coverage'] = True
        else:
            feedback_parts.append(f"❌ Incomplete subject coverage ({len(subjects_found)}/6 subjects)")
            subscores['complete_coverage'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria
        
        # Add summary feedback
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent compliance analysis!")
        elif passed:
            feedback_parts.append("✅ Homeschool compliance validation complete")
        else:
            feedback_parts.append("❌ Compliance validation incomplete")
        
        # Log detailed results
        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria met")
        logger.info(f"Subjects found: {subjects_found}")
        
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
        cleanup_verification_temp(temp_dir)
