#!/usr/bin/env python3
"""
Verifier for Contractor Quote Normalizer task
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any, Optional

# Add utils to path - use relative path since verification runs on host
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


def extract_number(value) -> Optional[float]:
    """Extract numeric value from cell, handling currency and text."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove currency symbols, commas, spaces
        cleaned = re.sub(r'[\$,\s]', '', value)
        try:
            return float(cleaned)
        except (ValueError, TypeError):
            return None
    return None


def find_category_headers(workbook: Dict, sheet_name: str, keywords: List[str]) -> int:
    """
    Count how many standard category keywords appear in the spreadsheet.
    This indicates data standardization effort.
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return 0
    
    rows = sheets[sheet_name]
    category_count = 0
    found_keywords = set()
    
    for row in rows:
        for cell in row:
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and isinstance(cell_value, str):
                cell_lower = cell_value.lower()
                for keyword in keywords:
                    if keyword in cell_lower and keyword not in found_keywords:
                        found_keywords.add(keyword)
                        category_count += 1
    
    return category_count


def find_sum_formulas(workbook: Dict, sheet_name: str) -> List[Dict[str, Any]]:
    """
    Find all SUM formulas in the spreadsheet.
    Returns list of dicts with formula, value, and location.
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return []
    
    rows = sheets[sheet_name]
    sum_formulas = []
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                if formula and 'SUM' in formula.upper():
                    sum_formulas.append({
                        'formula': formula,
                        'value': cell.get('value'),
                        'row': row_idx,
                        'col': col_idx
                    })
    
    return sum_formulas


def find_min_or_ranking(workbook: Dict, sheet_name: str) -> bool:
    """
    Check if there's a MIN formula or ranking logic (1st, 2nd, 3rd or RANK function).
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return False
    
    rows = sheets[sheet_name]
    
    for row in rows:
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                value = cell.get('value', '')
                
                # Check for MIN function
                if formula and 'MIN' in formula.upper():
                    return True
                
                # Check for RANK function
                if formula and 'RANK' in formula.upper():
                    return True
                
                # Check for ranking indicators (1st, 2nd, 3rd)
                if isinstance(value, str):
                    if re.search(r'\b(1st|2nd|3rd|first|second|third)\b', value.lower()):
                        return True
    
    return False


def check_for_outlier_flags(workbook: Dict, sheet_name: str) -> int:
    """
    Check for outlier flagging mechanisms:
    - Conditional formatting rules
    - Cells with outlier-related text
    - Formulas that calculate differences from average
    """
    outlier_count = 0
    
    # Check for conditional formatting
    if check_conditional_formatting(workbook, sheet_name, "A1:Z100"):
        outlier_count += 2  # Conditional formatting is sophisticated
    
    # Check for outlier-related text
    sheets = workbook.get('sheets', {})
    if sheet_name in sheets:
        rows = sheets[sheet_name]
        for row in rows:
            for cell in row:
                if isinstance(cell, dict):
                    value = cell.get('value', '')
                    formula = cell.get('formula', '')
                    
                    # Check for outlier indicators in text
                    if isinstance(value, str):
                        if any(keyword in value.lower() for keyword in 
                               ['outlier', 'flag', 'high', 'low', 'concern', 'clarify', 'suspicious']):
                            outlier_count += 1
                    
                    # Check for AVERAGE formulas (used for outlier detection)
                    if formula and 'AVERAGE' in formula.upper():
                        outlier_count += 0.5
    
    return int(outlier_count)


def check_for_summary_section(workbook: Dict, sheet_name: str) -> bool:
    """
    Check if there's a summary section with keywords like:
    - Summary, Comparison, Total, Ranking, Best Value, etc.
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return False
    
    rows = sheets[sheet_name]
    summary_keywords = ['summary', 'comparison', 'ranking', 'best value', 
                       'winner', 'recommendation', 'contractor comparison']
    
    for row in rows:
        for cell in row:
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value and isinstance(value, str):
                if any(keyword in value.lower() for keyword in summary_keywords):
                    return True
    
    return False


def validate_total_formulas(workbook: Dict, sheet_name: str, 
                           expected_totals: Dict[str, float]) -> Tuple[bool, List[str]]:
    """
    Validate that calculated totals are reasonably accurate.
    We expect totals around: A=1925, B=1950, C=1430
    Allow some variance since user might separate required/optional differently.
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return False, ["Sheet not found"]
    
    rows = sheets[sheet_name]
    found_totals = []
    errors = []
    
    # Look for cells with formulas that produce values close to expected totals
    for row in rows:
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                value = extract_number(cell.get('value'))
                
                if formula and 'SUM' in formula.upper() and value:
                    # Check if this total is close to any expected contractor total
                    for contractor, expected in expected_totals.items():
                        if abs(value - expected) < 100:  # Within $100
                            found_totals.append(contractor)
    
    if len(found_totals) >= 2:  # At least 2 of 3 contractors have correct totals
        return True, []
    else:
        errors.append(f"Expected totals for contractors not found or inaccurate")
        return False, errors


def verify_contractor_quotes(traj, env_info, task_info):
    """
    Verify contractor quote normalization task completion.
    
    Checks:
    1. Data standardized into categories (≥4 category keywords)
    2. Formulas calculate totals correctly
    3. Best value contractor identified (MIN or ranking)
    4. Outliers flagged (≥2 items)
    5. Summary section exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/contractor_quotes.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found"}
        sheet_name = sheet_names[0]

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []

        # Criterion 1: Data Standardization
        category_keywords = ['material', 'labor', 'permit', 'optional', 'fee', 'required']
        category_count = find_category_headers(workbook, sheet_name, category_keywords)
        
        if category_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data standardized ({category_count} standard categories found)")
        else:
            feedback_parts.append(f"❌ Insufficient standardization ({category_count}/4+ categories)")

        # Criterion 2: Formula Accuracy
        expected_totals = {
            'A': 1925,  # Contractor A
            'B': 1950,  # Contractor B (without optional)
            'C': 1430   # Contractor C (base)
        }
        formulas_accurate, formula_errors = validate_total_formulas(workbook, sheet_name, expected_totals)
        
        sum_formulas = find_sum_formulas(workbook, sheet_name)
        if formulas_accurate and len(sum_formulas) >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas correct ({len(sum_formulas)} SUM formulas found)")
        elif len(sum_formulas) >= 3:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Formulas present but accuracy unclear ({len(sum_formulas)} SUM formulas)")
        else:
            feedback_parts.append(f"❌ Insufficient formulas ({len(sum_formulas)} SUM formulas, expected 3+)")

        # Criterion 3: Best Value Identification
        has_min_or_ranking = find_min_or_ranking(workbook, sheet_name)
        
        if has_min_or_ranking:
            criteria_passed += 1
            feedback_parts.append("✅ Best value identification present (MIN/RANK formula)")
        else:
            feedback_parts.append("❌ No MIN or ranking formula detected")

        # Criterion 4: Outlier Flagging
        outlier_count = check_for_outlier_flags(workbook, sheet_name)
        
        if outlier_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Outliers flagged ({outlier_count} indicators found)")
        else:
            feedback_parts.append(f"❌ Insufficient outlier detection ({outlier_count}/2+ items)")

        # Criterion 5: Summary Section
        has_summary = check_for_summary_section(workbook, sheet_name)
        
        if has_summary:
            criteria_passed += 1
            feedback_parts.append("✅ Summary comparison section present")
        else:
            feedback_parts.append("❌ No summary section detected")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria
        
        # Add context-specific feedback
        if passed:
            feedback_parts.append("🎉 Quote comparison successfully normalized!")
        else:
            feedback_parts.append("❌ More work needed on standardization and analysis")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "data_standardized": category_count >= 4,
                "formulas_correct": formulas_accurate,
                "best_value_identified": has_min_or_ranking,
                "outliers_flagged": outlier_count >= 2,
                "summary_exists": has_summary
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
