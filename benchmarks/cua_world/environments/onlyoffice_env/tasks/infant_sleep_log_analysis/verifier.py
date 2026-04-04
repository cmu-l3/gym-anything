#!/usr/bin/env python3
"""
Verifier for Infant Sleep Log Analysis task

This verifier checks:
1. Structure: Proper columns and data organization
2. Data Accuracy: Correct extraction from messy notes
3. Formulas: AVERAGE formulas for method comparisons
4. Analysis: Summary with recommendations
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime
from typing import Dict, List, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Ground truth data extracted from the notes
GROUND_TRUTH = {
    'sept_15': {'wakings': 7, 'duration': 45, 'method': 'ferber'},
    'sept_16': {'wakings': 6, 'duration': 30, 'method': 'ferber'},
    'sept_17': {'wakings': 4, 'duration': 20, 'method': 'ferber'},
    'sept_18': {'wakings': 6, 'duration': 38, 'method': 'ferber'},
    'sept_19': {'wakings': 5, 'duration': 33, 'method': 'ferber'},
    'sept_21': {'wakings': 8, 'duration': 50, 'method': 'chair'},
    'sept_22': {'wakings': 7, 'duration': 42, 'method': 'chair'},
    'sept_23': {'wakings': 8, 'duration': 48, 'method': 'chair'},
    'sept_24': {'wakings': 7, 'duration': 45, 'method': 'chair'},
    'sept_26': {'wakings': 6, 'duration': 40, 'method': 'chair'},
    'sept_27': {'wakings': 7, 'duration': 44, 'method': 'chair'},
    'sept_28': {'wakings': 8, 'duration': 52, 'method': 'chair'},
    'sept_29': {'wakings': 6, 'duration': 38, 'method': 'chair'},
    'sept_30': {'wakings': 7, 'duration': 43, 'method': 'chair'},
    'oct_1': {'wakings': 5, 'duration': 35, 'method': 'pupd'},
    'oct_2': {'wakings': 4, 'duration': 28, 'method': 'pupd'},
    'oct_3': {'wakings': 5, 'duration': 30, 'method': 'pupd'},
    'oct_4': {'wakings': 3, 'duration': 22, 'method': 'pupd'},
    'oct_5': {'wakings': 4, 'duration': 25, 'method': 'pupd'},
    'oct_6': {'wakings': 5, 'duration': 32, 'method': 'pupd'},
    'oct_7': {'wakings': 4, 'duration': 27, 'method': 'pupd'},
    'oct_8': {'wakings': 3, 'duration': 20, 'method': 'pupd'},
    'oct_9': {'wakings': 5, 'duration': 31, 'method': 'pupd'},
    'oct_10': {'wakings': 4, 'duration': 26, 'method': 'pupd'},
    'oct_11': {'wakings': 4, 'duration': 28, 'method': 'pupd'},
    'oct_12': {'wakings': 5, 'duration': 30, 'method': 'pupd'},
}

# Expected averages
EXPECTED_AVERAGES = {
    'ferber': {'wakings': 5.6, 'duration': 33.2},  # 5 days
    'chair': {'wakings': 7.1, 'duration': 44.7},   # 9 days (missing Sept 25)
    'pupd': {'wakings': 4.25, 'duration': 27.8},   # 12 days
}


def normalize_method_name(method: str) -> str:
    """Normalize method names for comparison"""
    if not method:
        return ''
    
    method_lower = str(method).lower()
    if 'ferber' in method_lower:
        return 'ferber'
    elif 'chair' in method_lower:
        return 'chair'
    elif 'pick' in method_lower or 'pupd' in method_lower or 'put down' in method_lower:
        return 'pupd'
    return method_lower


def find_column_by_keywords(headers: List, keywords: List[str]) -> Optional[int]:
    """Find column index by matching keywords"""
    for i, header in enumerate(headers):
        if header:
            header_str = str(header).lower()
            for keyword in keywords:
                if keyword in header_str:
                    return i
    return None


def extract_number(value) -> Optional[float]:
    """Extract numeric value from cell (handles strings with numbers)"""
    if value is None:
        return None
    
    if isinstance(value, (int, float)):
        return float(value)
    
    # Try to extract number from string
    if isinstance(value, str):
        # Remove common text and extract numbers
        match = re.search(r'(\d+\.?\d*)', value)
        if match:
            return float(match.group(1))
    
    return None


def parse_date_from_cell(value) -> Optional[Tuple[int, int]]:
    """Parse date from cell value, return (month, day) tuple"""
    if value is None:
        return None
    
    value_str = str(value).lower()
    
    # Try various date formats
    patterns = [
        r'sept?\.?\s*(\d+)',
        r'9[-/](\d+)',
        r'oct\.?\s*(\d+)',
        r'10[-/](\d+)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, value_str)
        if match:
            day = int(match.group(1))
            month = 9 if ('sept' in value_str or value_str.startswith('9')) else 10
            return (month, day)
    
    return None


def verify_sleep_training_analysis(traj, env_info, task_info):
    """
    Verify that sleep training analysis spreadsheet was created correctly.

    Scoring breakdown:
    - Structure (20 points): Columns, data organization, completeness
    - Data Accuracy (30 points): Correct extraction from messy notes
    - Formulas (30 points): AVERAGE formulas for method comparisons
    - Analysis & Insight (20 points): Summary, comparison, recommendations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/sleep_training_analysis.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_sleep_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        score = 0
        feedback_parts = []

        # Get the active sheet
        sheet = wb.active
        
        # Get all data
        all_data = get_sheet_data(wb, sheet.title, max_rows=100, max_cols=20)
        
        if not all_data or len(all_data) < 2:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet is empty or has insufficient data"}

        # ==================================================================
        # CRITERION 1: STRUCTURE (20 points)
        # ==================================================================
        structure_score = 0
        
        # Find header row (look in first 5 rows)
        header_row_idx = None
        headers = []
        
        for i in range(min(5, len(all_data))):
            row = all_data[i]
            row_text = ' '.join([str(cell).lower() for cell in row if cell])
            if any(keyword in row_text for keyword in ['date', 'method', 'waking', 'duration']):
                header_row_idx = i
                headers = row
                break
        
        if header_row_idx is None:
            feedback_parts.append("❌ No header row found with required columns")
        else:
            # Find column indices
            date_col = find_column_by_keywords(headers, ['date'])
            method_col = find_column_by_keywords(headers, ['method', 'approach', 'technique'])
            wakings_col = find_column_by_keywords(headers, ['waking', 'wake up', 'wakeup', 'night'])
            duration_col = find_column_by_keywords(headers, ['duration', 'minute', 'min', 'time', 'crying'])
            
            cols_found = sum([col is not None for col in [date_col, method_col, wakings_col, duration_col]])
            
            if cols_found >= 4:
                structure_score += 10
                feedback_parts.append(f"✅ Found all required columns")
            elif cols_found >= 3:
                structure_score += 5
                feedback_parts.append(f"⚠️ Found {cols_found}/4 required columns")
            else:
                feedback_parts.append(f"❌ Only found {cols_found}/4 required columns")
            
            # Check data completeness (count non-empty data rows)
            data_rows = []
            if header_row_idx is not None:
                for i in range(header_row_idx + 1, len(all_data)):
                    row = all_data[i]
                    # Check if row has meaningful data (not just summary)
                    if date_col is not None and row[date_col] is not None:
                        data_rows.append(row)
            
            data_row_count = len(data_rows)
            
            if data_row_count >= 24:
                structure_score += 10
                feedback_parts.append(f"✅ {data_row_count} data rows (excellent coverage)")
            elif data_row_count >= 20:
                structure_score += 7
                feedback_parts.append(f"✅ {data_row_count} data rows (good coverage)")
            elif data_row_count >= 15:
                structure_score += 4
                feedback_parts.append(f"⚠️ {data_row_count} data rows (acceptable)")
            else:
                feedback_parts.append(f"❌ Only {data_row_count} data rows (need at least 20)")

        score += structure_score

        # ==================================================================
        # CRITERION 2: DATA ACCURACY (30 points)
        # ==================================================================
        accuracy_score = 0
        
        if header_row_idx is not None and date_col is not None and wakings_col is not None:
            # Spot check specific dates
            spot_checks = {
                'sept_15': (9, 15),
                'sept_17': (9, 17),
                'oct_2': (10, 2),
                'oct_4': (10, 4),
                'oct_8': (10, 8),
            }
            
            matches = 0
            total_checks = len(spot_checks)
            
            for key, (month, day) in spot_checks.items():
                expected = GROUND_TRUTH[key]
                
                # Find row with this date
                found = False
                for row in data_rows:
                    date_value = row[date_col] if date_col < len(row) else None
                    parsed_date = parse_date_from_cell(date_value)
                    
                    if parsed_date and parsed_date == (month, day):
                        # Check wakings
                        wakings_value = row[wakings_col] if wakings_col < len(row) else None
                        wakings = extract_number(wakings_value)
                        
                        if wakings is not None and abs(wakings - expected['wakings']) <= 0.5:
                            matches += 1
                            found = True
                            break
                
                if not found:
                    logger.debug(f"Spot check failed for {key}: not found or incorrect")
            
            accuracy_percentage = (matches / total_checks) * 100
            
            if matches >= 4:
                accuracy_score += 20
                feedback_parts.append(f"✅ Data accuracy: {matches}/{total_checks} spot checks passed")
            elif matches >= 3:
                accuracy_score += 15
                feedback_parts.append(f"✅ Data accuracy: {matches}/{total_checks} spot checks passed")
            elif matches >= 2:
                accuracy_score += 10
                feedback_parts.append(f"⚠️ Data accuracy: {matches}/{total_checks} spot checks passed")
            else:
                feedback_parts.append(f"❌ Data accuracy: {matches}/{total_checks} spot checks passed")
            
            # Check method classification
            if method_col is not None:
                method_counts = {'ferber': 0, 'chair': 0, 'pupd': 0}
                
                for row in data_rows:
                    method_value = row[method_col] if method_col < len(row) else None
                    normalized_method = normalize_method_name(method_value)
                    if normalized_method in method_counts:
                        method_counts[normalized_method] += 1
                
                # Expected: Ferber 5, Chair 9, PUPD 12 (approximate)
                if (method_counts['ferber'] >= 4 and 
                    method_counts['chair'] >= 7 and 
                    method_counts['pupd'] >= 10):
                    accuracy_score += 10
                    feedback_parts.append(f"✅ Methods classified correctly ({method_counts})")
                elif sum(method_counts.values()) >= 20:
                    accuracy_score += 5
                    feedback_parts.append(f"⚠️ Some method classifications present ({method_counts})")
                else:
                    feedback_parts.append(f"❌ Method classification incomplete ({method_counts})")

        score += accuracy_score

        # ==================================================================
        # CRITERION 3: FORMULAS (30 points)
        # ==================================================================
        formula_score = 0
        
        # Look for formulas in the entire sheet (check raw cells, not just values)
        formulas_found = []
        average_formulas_count = 0
        
        for row_idx, row in enumerate(sheet.iter_rows(min_row=1, max_row=100), start=1):
            for col_idx, cell in enumerate(row, start=1):
                if cell.value and isinstance(cell.value, str):
                    cell_str = str(cell.value).upper()
                    if 'AVERAGE' in cell_str or '=AVERAGE' in cell_str:
                        formulas_found.append(f"{cell.coordinate}: {cell.value}")
                        average_formulas_count += 1
        
        if average_formulas_count >= 3:
            formula_score += 20
            feedback_parts.append(f"✅ Found {average_formulas_count} AVERAGE formulas")
        elif average_formulas_count >= 2:
            formula_score += 15
            feedback_parts.append(f"✅ Found {average_formulas_count} AVERAGE formulas (need 3+)")
        elif average_formulas_count >= 1:
            formula_score += 10
            feedback_parts.append(f"⚠️ Found {average_formulas_count} AVERAGE formula (need 3+)")
        else:
            # Check if averages are calculated correctly even without formulas
            feedback_parts.append(f"❌ No AVERAGE formulas detected")
        
        # Check if calculated averages are approximately correct
        # Look for summary section with method names and numbers
        summary_found = False
        correct_averages = 0
        
        for row in all_data:
            row_text = ' '.join([str(cell).lower() for cell in row if cell])
            
            # Check for Ferber summary
            if 'ferber' in row_text:
                for cell in row:
                    num = extract_number(cell)
                    if num and (abs(num - EXPECTED_AVERAGES['ferber']['wakings']) <= 1.0 or
                               abs(num - EXPECTED_AVERAGES['ferber']['duration']) <= 5.0):
                        correct_averages += 1
                        summary_found = True
                        break
            
            # Check for Chair summary
            if 'chair' in row_text:
                for cell in row:
                    num = extract_number(cell)
                    if num and (abs(num - EXPECTED_AVERAGES['chair']['wakings']) <= 1.0 or
                               abs(num - EXPECTED_AVERAGES['chair']['duration']) <= 5.0):
                        correct_averages += 1
                        summary_found = True
                        break
            
            # Check for PUPD summary
            if 'pick' in row_text or 'pupd' in row_text or 'put down' in row_text:
                for cell in row:
                    num = extract_number(cell)
                    if num and (abs(num - EXPECTED_AVERAGES['pupd']['wakings']) <= 1.0 or
                               abs(num - EXPECTED_AVERAGES['pupd']['duration']) <= 5.0):
                        correct_averages += 1
                        summary_found = True
                        break
        
        if correct_averages >= 4:
            formula_score += 10
            feedback_parts.append(f"✅ Calculated averages are correct ({correct_averages}/6)")
        elif correct_averages >= 2:
            formula_score += 5
            feedback_parts.append(f"⚠️ Some calculated averages are correct ({correct_averages}/6)")

        score += formula_score

        # ==================================================================
        # CRITERION 4: ANALYSIS & INSIGHT (20 points)
        # ==================================================================
        insight_score = 0
        
        # Check for summary section
        if summary_found:
            insight_score += 8
            feedback_parts.append("✅ Summary section with method comparisons found")
        else:
            feedback_parts.append("❌ No clear summary section found")
        
        # Check for recommendation or interpretation
        all_text = ' '.join([str(cell).lower() for row in all_data for cell in row if cell])
        
        recommendation_keywords = ['recommend', 'best', 'better', 'suggest', 'effective', 'worst', 'prefer']
        has_recommendation = any(keyword in all_text for keyword in recommendation_keywords)
        
        # Check if PUPD is identified as best (it has lowest wakings and duration)
        pupd_keywords = ['pick', 'pupd', 'put down']
        has_pupd_reference = any(keyword in all_text for keyword in pupd_keywords)
        
        if has_recommendation and has_pupd_reference:
            insight_score += 12
            feedback_parts.append("✅ Contains recommendation identifying best method")
        elif has_recommendation:
            insight_score += 8
            feedback_parts.append("✅ Contains recommendation (though may not identify correct best method)")
        elif summary_found:
            insight_score += 4
            feedback_parts.append("⚠️ Has summary but no clear recommendation")
        else:
            feedback_parts.append("❌ Missing recommendation/interpretation")

        score += insight_score

        # ==================================================================
        # FINAL SCORING
        # ==================================================================
        
        # Cap score at 100
        score = min(score, 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        result = {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
        logger.info(f"Verification complete: {result}")
        return result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
