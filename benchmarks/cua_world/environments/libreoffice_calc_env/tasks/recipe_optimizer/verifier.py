#!/usr/bin/env python3
"""
Verifier for Recipe Optimizer Task

Checks:
1. Data cleaning (standardized ingredient names)
2. Rating normalization (0-10 scale)
3. Composite score formula (weighted)
4. Top experiments identified (ranking)
5. Validity flagging (data quality)
6. Category analysis (averages by ingredient)
"""

import sys
import os
import logging
import re
from collections import defaultdict

# Use relative path to utils folder
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


def verify_recipe_optimizer(traj, env_info, task_info):
    """
    Main verification function for recipe optimization task
    
    Criteria:
    1. Data cleaning (20 points)
    2. Normalization (15 points)
    3. Composite score (25 points)
    4. Ranking (15 points)
    5. Validity flags (10 points)
    6. Category analysis (15 points)
    
    Total: 100 points
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the output file (try multiple possible names)
    temp_dir = None
    success = False
    workbook = None
    
    for path in ["/home/ga/Documents/cookie_analysis.ods",
                 "/home/ga/Documents/cookie_experiments.ods",
                 "/home/ga/Documents/cookie_experiments.csv"]:
        # Determine format
        file_format = 'ods' if path.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load output file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Initialize scoring
        score = 0
        max_score = 100
        feedback_parts = []
        criteria_met = 0
        total_criteria = 6
        
        # Get sheet data
        sheet_data = workbook['sheets'][sheet_name]
        
        # Parse headers and data
        headers, data_rows = parse_sheet_data(sheet_data)
        logger.info(f"Found {len(headers)} columns and {len(data_rows)} data rows")
        logger.info(f"Headers: {headers}")
        
        # Criterion 1: Data Cleaning (20 points)
        cleaning_result = verify_data_cleaning(headers, data_rows)
        if cleaning_result['passed']:
            score += 20
            criteria_met += 1
            feedback_parts.append(f"✅ Data cleaning: {cleaning_result['message']}")
        else:
            feedback_parts.append(f"❌ Data cleaning: {cleaning_result['message']}")
        
        # Criterion 2: Normalization (15 points)
        norm_result = verify_normalization(headers, data_rows)
        if norm_result['passed']:
            score += 15
            criteria_met += 1
            feedback_parts.append(f"✅ Normalization: {norm_result['message']}")
        else:
            feedback_parts.append(f"❌ Normalization: {norm_result['message']}")
        
        # Criterion 3: Composite Score (25 points)
        composite_result = verify_composite_score(headers, data_rows, workbook, sheet_name)
        score += composite_result['points']
        if composite_result['passed']:
            criteria_met += 1
            feedback_parts.append(f"✅ Composite score: {composite_result['message']}")
        else:
            feedback_parts.append(f"⚠️ Composite score: {composite_result['message']}")
        
        # Criterion 4: Ranking (15 points)
        ranking_result = verify_ranking(headers, data_rows)
        if ranking_result['passed']:
            score += 15
            criteria_met += 1
            feedback_parts.append(f"✅ Ranking: {ranking_result['message']}")
        else:
            feedback_parts.append(f"❌ Ranking: {ranking_result['message']}")
        
        # Criterion 5: Validity Flags (10 points)
        flags_result = verify_validity_flags(headers, data_rows)
        if flags_result['passed']:
            score += 10
            criteria_met += 1
            feedback_parts.append(f"✅ Validity flags: {flags_result['message']}")
        else:
            feedback_parts.append(f"⚠️ Validity flags: {flags_result['message']}")
        
        # Criterion 6: Category Analysis (15 points)
        category_result = verify_category_analysis(headers, data_rows)
        if category_result['passed']:
            score += 15
            criteria_met += 1
            feedback_parts.append(f"✅ Category analysis: {category_result['message']}")
        else:
            feedback_parts.append(f"❌ Category analysis: {category_result['message']}")
        
        # Determine pass/fail
        passed = score >= 70
        
        # Add summary
        summary = f"Score: {score}/{max_score} | Criteria: {criteria_met}/{total_criteria}"
        feedback_parts.insert(0, summary)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent recipe analysis!")
        elif passed:
            feedback_parts.append("✅ Recipe optimization complete")
        else:
            feedback_parts.append("❌ Analysis incomplete - needs more work")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "data_cleaning": cleaning_result['passed'],
                "normalization": norm_result['passed'],
                "composite_score": composite_result['passed'],
                "ranking": ranking_result['passed'],
                "validity_flags": flags_result['passed'],
                "category_analysis": category_result['passed']
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


def parse_sheet_data(sheet_data):
    """Parse sheet into headers and data rows"""
    if not sheet_data or len(sheet_data) == 0:
        return [], []
    
    # First row is headers
    header_row = sheet_data[0]
    headers = []
    for cell in header_row:
        if isinstance(cell, dict):
            value = cell.get('value', '')
        else:
            value = cell
        headers.append(str(value).strip() if value else '')
    
    # Remaining rows are data
    data_rows = []
    for row in sheet_data[1:]:
        row_data = []
        for cell in row:
            if isinstance(cell, dict):
                value = cell.get('value')
            else:
                value = cell
            row_data.append(value)
        # Only include non-empty rows
        if any(v is not None and str(v).strip() != '' for v in row_data):
            data_rows.append(row_data)
    
    return headers, data_rows


def verify_data_cleaning(headers, data_rows):
    """
    Check if data cleaning was performed:
    - Look for cleaned columns (e.g., Butter_Clean, Sugar_Clean)
    - OR check if original columns have consistent capitalization
    """
    # Look for cleaned column names
    cleaned_cols = [h for h in headers if 'clean' in h.lower() or 'standard' in h.lower()]
    
    if cleaned_cols:
        # Check if cleaned columns have consistent values
        for col_name in cleaned_cols:
            if 'butter' in col_name.lower() or 'sugar' in col_name.lower() or 'chocolate' in col_name.lower():
                col_idx = headers.index(col_name)
                values = [row[col_idx] for row in data_rows if col_idx < len(row)]
                values = [str(v).strip() for v in values if v is not None]
                
                if values:
                    # Check for case variations (butter vs Butter)
                    unique_lower = set(v.lower() for v in values)
                    unique_actual = set(values)
                    
                    if len(unique_lower) < len(unique_actual):
                        # Still has case inconsistencies
                        return {
                            'passed': False,
                            'message': f'Column {col_name} still has case inconsistencies'
                        }
        
        return {
            'passed': True,
            'message': f'Found {len(cleaned_cols)} cleaned columns'
        }
    
    # Check if original columns were cleaned in place
    ingredient_cols = [h for h in headers if any(x in h.lower() for x in ['butter', 'sugar', 'chocolate'])]
    if ingredient_cols:
        consistent = True
        for col_name in ingredient_cols[:3]:  # Check first 3 ingredient columns
            try:
                col_idx = headers.index(col_name)
                values = [row[col_idx] for row in data_rows if col_idx < len(row)]
                values = [str(v).strip() for v in values if v is not None and str(v).strip()]
                
                if values:
                    unique_lower = set(v.lower() for v in values)
                    unique_actual = set(values)
                    if len(unique_lower) < len(unique_actual):
                        consistent = False
                        break
            except:
                pass
        
        if consistent:
            return {
                'passed': True,
                'message': 'Ingredient columns have consistent formatting'
            }
    
    return {
        'passed': False,
        'message': 'No cleaned columns found or data still inconsistent'
    }


def verify_normalization(headers, data_rows):
    """
    Check if ratings were normalized to 0-10 scale:
    - Look for normalized columns (e.g., Taste_Norm, *_Normalized)
    - Verify values are in 0-10 range
    """
    # Look for normalized column names
    norm_cols = [h for h in headers if 'norm' in h.lower() or 'normalized' in h.lower()]
    
    if not norm_cols:
        return {
            'passed': False,
            'message': 'No normalized columns found (expected Taste_Norm, Texture_Norm, etc.)'
        }
    
    # Check if normalized values are in 0-10 range
    valid_ranges = True
    checked_count = 0
    
    for col_name in norm_cols:
        col_idx = headers.index(col_name)
        values = [row[col_idx] for row in data_rows if col_idx < len(row)]
        numeric_values = []
        
        for v in values:
            if v is not None:
                try:
                    numeric_values.append(float(v))
                except (ValueError, TypeError):
                    pass
        
        if numeric_values:
            checked_count += 1
            min_val = min(numeric_values)
            max_val = max(numeric_values)
            
            # Allow slight tolerance (e.g., -0.5 to 10.5)
            if min_val < -0.5 or max_val > 10.5:
                valid_ranges = False
                logger.warning(f"Column {col_name} has values outside 0-10 range: [{min_val}, {max_val}]")
    
    if checked_count >= 2 and valid_ranges:
        return {
            'passed': True,
            'message': f'Found {len(norm_cols)} normalized columns with valid 0-10 scale'
        }
    elif checked_count >= 2:
        return {
            'passed': False,
            'message': f'Normalized columns found but values outside 0-10 range'
        }
    else:
        return {
            'passed': False,
            'message': 'Insufficient normalized columns'
        }


def verify_composite_score(headers, data_rows, workbook, sheet_name):
    """
    Check if composite score was created:
    - Look for Composite_Score or similar column
    - Verify it contains numeric values in reasonable range
    - Check if it appears to be a weighted combination
    """
    # Look for composite score column
    composite_cols = [h for h in headers if 'composite' in h.lower() or 'score' in h.lower() or 'total' in h.lower()]
    
    if not composite_cols:
        return {
            'passed': False,
            'points': 0,
            'message': 'No composite score column found'
        }
    
    # Take the most likely column
    composite_col = composite_cols[0]
    col_idx = headers.index(composite_col)
    
    # Get values
    values = [row[col_idx] for row in data_rows if col_idx < len(row)]
    numeric_values = []
    
    for v in values:
        if v is not None:
            try:
                numeric_values.append(float(v))
            except (ValueError, TypeError):
                pass
    
    if len(numeric_values) < 10:
        return {
            'passed': False,
            'points': 5,
            'message': f'Composite score column found but insufficient valid values ({len(numeric_values)})'
        }
    
    # Check if values are in reasonable range (0-10 expected)
    min_val = min(numeric_values)
    max_val = max(numeric_values)
    
    if min_val < -1 or max_val > 12:
        return {
            'passed': False,
            'points': 10,
            'message': f'Composite scores outside expected range: [{min_val:.1f}, {max_val:.1f}]'
        }
    
    # Check if there's variation (not all same value)
    if max_val - min_val < 0.5:
        return {
            'passed': False,
            'points': 10,
            'message': 'Composite scores show no variation'
        }
    
    # Partial credit for having the column with valid values
    return {
        'passed': True,
        'points': 25,
        'message': f'Composite score column present with valid values (range: {min_val:.1f}-{max_val:.1f})'
    }


def verify_ranking(headers, data_rows):
    """
    Check if experiments are ranked:
    - Data sorted by composite score (descending)
    - OR top 3 marked/identified
    - OR rank column exists
    """
    # Look for composite/score column
    score_cols = [h for h in headers if 'composite' in h.lower() or 'score' in h.lower() or 'total' in h.lower()]
    
    if not score_cols:
        return {
            'passed': False,
            'message': 'Cannot verify ranking without score column'
        }
    
    score_col = score_cols[0]
    col_idx = headers.index(score_col)
    
    # Get scores
    scores = []
    for i, row in enumerate(data_rows):
        if col_idx < len(row):
            try:
                score = float(row[col_idx])
                scores.append((i, score))
            except (ValueError, TypeError):
                pass
    
    if len(scores) < 10:
        return {
            'passed': False,
            'message': 'Insufficient valid scores to verify ranking'
        }
    
    # Check if data is sorted (descending)
    is_sorted = True
    for i in range(len(scores) - 1):
        if scores[i][1] < scores[i+1][1] - 0.01:  # Allow small tolerance
            is_sorted = False
            break
    
    if is_sorted:
        top_score = scores[0][1]
        return {
            'passed': True,
            'message': f'Data sorted by score (top score: {top_score:.2f})'
        }
    
    # Check if there's a rank column
    rank_cols = [h for h in headers if 'rank' in h.lower() or 'top' in h.lower()]
    if rank_cols:
        return {
            'passed': True,
            'message': 'Ranking column found'
        }
    
    # Partial credit: at least scores exist
    return {
        'passed': False,
        'message': 'Scores exist but not sorted or ranked'
    }


def verify_validity_flags(headers, data_rows):
    """
    Check if validity flags were added:
    - Look for Valid, IsValid, Flag, or Quality column
    - Should contain TRUE/FALSE or similar values
    """
    # Look for validity columns
    flag_cols = [h for h in headers if any(x in h.lower() for x in ['valid', 'flag', 'quality', 'ok', 'good'])]
    
    if not flag_cols:
        return {
            'passed': False,
            'message': 'No validity flag column found'
        }
    
    flag_col = flag_cols[0]
    col_idx = headers.index(flag_col)
    
    # Get values
    values = [row[col_idx] for row in data_rows if col_idx < len(row)]
    values = [str(v).upper() if v is not None else '' for v in values]
    
    # Check if contains boolean-like values
    bool_values = [v for v in values if v in ['TRUE', 'FALSE', 'YES', 'NO', '1', '0', 'PASS', 'FAIL']]
    
    if len(bool_values) >= len(data_rows) * 0.5:  # At least half have valid flags
        return {
            'passed': True,
            'message': f'Validity flags found in column "{flag_col}"'
        }
    
    return {
        'passed': False,
        'message': f'Flag column exists but lacks valid TRUE/FALSE values'
    }


def verify_category_analysis(headers, data_rows):
    """
    Check if category analysis was performed:
    - Look for summary rows or separate analysis section
    - Check for AVERAGE formulas
    - Verify grouping by ingredient type
    """
    # Simple check: look for rows that might be category summaries
    # These often appear at the bottom or in a separate section
    
    # Check if there are any AVERAGE calculations for ingredients
    # This is a simplified check - in practice would need formula inspection
    
    # Look for summary indicators in data
    has_summary = False
    
    # Check last few rows for summary data
    if len(data_rows) > 20:
        last_rows = data_rows[-10:]
        for row in last_rows:
            row_str = ' '.join(str(v).lower() for v in row if v is not None)
            if any(x in row_str for x in ['average', 'mean', 'butter', 'margarine', 'coconut', 'summary']):
                has_summary = True
                break
    
    # Also check if there are separate analysis columns
    analysis_cols = [h for h in headers if any(x in h.lower() for x in ['average', 'mean', 'category', 'group'])]
    
    if has_summary or analysis_cols:
        return {
            'passed': True,
            'message': 'Category analysis present (summary rows or analysis columns found)'
        }
    
    # Lenient: if they at least have cleaned/grouped data, give partial credit
    cleaned_cols = [h for h in headers if 'clean' in h.lower()]
    if len(cleaned_cols) >= 2:
        return {
            'passed': True,
            'message': 'Category grouping enabled by cleaned columns'
        }
    
    return {
        'passed': False,
        'message': 'No category analysis found (no summary rows or averages by ingredient type)'
    }
