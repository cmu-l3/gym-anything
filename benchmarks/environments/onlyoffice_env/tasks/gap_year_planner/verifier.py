#!/usr/bin/env python3
"""
Verifier for gap_year_planner@1
Checks if user created a comprehensive gap year planning spreadsheet with proper structure, formulas, and sorting.
"""

import sys
import os
import logging
import tempfile
from datetime import datetime
from typing import Dict, Any, List, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text: Any) -> str:
    """Normalize text for comparison"""
    if text is None:
        return ""
    return str(text).strip().lower()


def is_numeric(value: Any) -> bool:
    """Check if value is numeric"""
    try:
        float(value)
        return True
    except (ValueError, TypeError):
        return False


def extract_number(value: Any) -> Optional[float]:
    """Extract numeric value from cell"""
    if value is None:
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        # Try to extract number from string
        if isinstance(value, str):
            import re
            match = re.search(r'-?\d+\.?\d*', value)
            if match:
                return float(match.group())
        return None


def verify_gap_year_planner(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the gap year planning spreadsheet.
    
    Checks:
    1. File exists at correct location (0.3 points)
    2. Has proper column structure - 7 columns (0.2 points)
    3. Contains all 4 countries (0.2 points)
    4. Total Cost column has formulas (values consistent with Duration × Daily Budget) (0.15 points)
    5. Summary TOTAL row with aggregation formulas (0.1 points)
    6. Proper sorting by Visa Deadline (0.05 points)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    target_path = "/home/ga/Documents/Spreadsheets/gap_year_plan.xlsx"
    
    feedback_parts = []
    score = 0.0
    
    # Create temp file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy file from container
        try:
            copy_from_env(target_path, temp_path)
        except Exception as e:
            logger.error(f"Failed to copy file: {e}")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or inaccessible: {target_path}"
            }
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or empty: {target_path}"
            }
        
        # File exists - 0.3 points
        score += 0.3
        feedback_parts.append("✅ File exists and is accessible")
        
        # Parse the workbook
        wb = parse_xlsx_file(temp_path)
        if not wb:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ Failed to parse XLSX file"
            }
        
        # Get the first sheet (user might have worked on Template or created new sheet)
        sheet_name = wb.sheetnames[0]
        logger.info(f"Checking sheet: {sheet_name}")
        sheet_data = get_sheet_data(wb, sheet_name, max_rows=20, max_cols=10)
        
        if not sheet_data or len(sheet_data) < 2:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ Sheet is empty or has insufficient data"
            }
        
        # Check column headers (row 0)
        headers = [normalize_text(cell) for cell in sheet_data[0]]
        logger.info(f"Headers found: {headers}")
        
        # Define required column keywords (flexible matching)
        required_columns = {
            'country': ['country', 'destination', 'location'],
            'duration': ['duration', 'days', 'length'],
            'daily_budget': ['daily budget', 'budget', 'daily cost', 'cost per day'],
            'total_cost': ['total cost', 'total', 'cost'],
            'visa_required': ['visa required', 'visa', 'visa?'],
            'visa_deadline': ['visa deadline', 'deadline', 'due date', 'due'],
            'vaccines': ['vaccine', 'vaccination', 'immunization', 'shots']
        }
        
        # Find column indices
        col_indices = {}
        for key, keywords in required_columns.items():
            for col_idx, header in enumerate(headers):
                if any(keyword in header for keyword in keywords):
                    col_indices[key] = col_idx
                    break
        
        logger.info(f"Column indices found: {col_indices}")
        
        # Check if we have most required columns (at least 5 out of 7)
        if len(col_indices) >= 5:
            score += 0.2
            feedback_parts.append(f"✅ Column structure correct ({len(col_indices)}/7 key columns)")
        elif len(col_indices) >= 4:
            score += 0.1
            feedback_parts.append(f"⚠️ Partial column structure ({len(col_indices)}/7 columns)")
        else:
            feedback_parts.append(f"❌ Missing required columns (found {len(col_indices)}/7)")
        
        # Extract data rows (skip header, skip empty rows)
        countries_found = []
        data_rows = []
        total_row_info = None
        
        for row_idx, row in enumerate(sheet_data[1:], start=1):
            if not row or not row[0]:
                continue
            
            first_col_text = normalize_text(row[0])
            
            # Check if this is the TOTAL row
            if first_col_text in ['total', 'totals', 'sum', 'summary']:
                total_row_info = (row_idx, row)
                continue
            
            # Regular data row
            if first_col_text:
                countries_found.append(first_col_text)
                data_rows.append((row_idx, row))
        
        logger.info(f"Countries found: {countries_found}")
        logger.info(f"Total rows: {len(data_rows)}")
        
        # Check for all 4 required countries
        required_countries = ['thailand', 'vietnam', 'portugal', 'iceland']
        countries_present = 0
        for req_country in required_countries:
            if any(req_country in country for country in countries_found):
                countries_present += 1
        
        logger.info(f"Required countries present: {countries_present}/4")
        
        if countries_present >= 4:
            score += 0.2
            feedback_parts.append("✅ All 4 countries present")
        elif countries_present >= 3:
            score += 0.15
            feedback_parts.append(f"⚠️ {countries_present}/4 countries present")
        elif countries_present >= 2:
            score += 0.1
            feedback_parts.append(f"⚠️ Only {countries_present}/4 countries found")
        else:
            feedback_parts.append(f"❌ Only {countries_present}/4 countries found")
        
        # Check for formulas in Total Cost column
        # openpyxl with data_only=True shows calculated values
        # We verify by checking if values are consistent with Duration × Daily Budget
        if 'duration' in col_indices and 'daily_budget' in col_indices and 'total_cost' in col_indices:
            duration_col = col_indices['duration']
            budget_col = col_indices['daily_budget']
            total_col = col_indices['total_cost']
            
            consistent_formulas = 0
            total_formula_rows = 0
            
            for row_idx, row in data_rows[:6]:  # Check up to 6 data rows
                if len(row) > max(duration_col, budget_col, total_col):
                    duration_val = extract_number(row[duration_col])
                    budget_val = extract_number(row[budget_col])
                    total_val = extract_number(row[total_col])
                    
                    if duration_val is not None and budget_val is not None:
                        total_formula_rows += 1
                        expected = duration_val * budget_val
                        
                        if total_val is not None and abs(total_val - expected) < 10.0:
                            consistent_formulas += 1
                            logger.info(f"Row {row_idx}: Formula verified ({duration_val} × {budget_val} = {total_val})")
                        else:
                            logger.warning(f"Row {row_idx}: Formula mismatch ({duration_val} × {budget_val} ≠ {total_val})")
            
            logger.info(f"Formula consistency: {consistent_formulas}/{total_formula_rows}")
            
            if total_formula_rows > 0 and consistent_formulas >= min(3, total_formula_rows):
                score += 0.15
                feedback_parts.append(f"✅ Total Cost formulas working correctly ({consistent_formulas}/{total_formula_rows})")
            elif consistent_formulas > 0:
                score += 0.08
                feedback_parts.append(f"⚠️ Some Total Cost formulas working ({consistent_formulas}/{total_formula_rows})")
            else:
                feedback_parts.append("❌ Total Cost formulas missing or incorrect")
        else:
            feedback_parts.append("❌ Cannot verify formulas - missing required columns")
        
        # Check for TOTAL summary row
        if total_row_info:
            row_idx, row = total_row_info
            
            # Check if total row has meaningful aggregated values
            has_aggregated_values = False
            
            if 'total_cost' in col_indices and len(row) > col_indices['total_cost']:
                total_cost_val = extract_number(row[col_indices['total_cost']])
                if total_cost_val is not None and total_cost_val > 0:
                    has_aggregated_values = True
                    logger.info(f"TOTAL row has aggregated total cost: {total_cost_val}")
            
            if 'duration' in col_indices and len(row) > col_indices['duration']:
                total_duration_val = extract_number(row[col_indices['duration']])
                if total_duration_val is not None and total_duration_val > 0:
                    has_aggregated_values = True
                    logger.info(f"TOTAL row has aggregated duration: {total_duration_val}")
            
            if has_aggregated_values:
                score += 0.1
                feedback_parts.append("✅ Summary TOTAL row with calculations")
            else:
                score += 0.05
                feedback_parts.append("⚠️ TOTAL row present but may be incomplete")
        else:
            feedback_parts.append("❌ TOTAL summary row missing")
        
        # Check sorting by deadline (if we have deadline column and at least 3 countries)
        if 'visa_deadline' in col_indices and len(data_rows) >= 3:
            deadline_col = col_indices['visa_deadline']
            deadlines = []
            
            for row_idx, row in data_rows[:5]:
                if len(row) > deadline_col and row[deadline_col]:
                    deadlines.append(normalize_text(row[deadline_col]))
            
            logger.info(f"Deadlines found: {deadlines}")
            
            # Check if sorted (at least partially)
            # Thailand (May 15) should come before Vietnam (June 1)
            # Countries without deadlines might be at the end
            if len(deadlines) >= 2:
                # Simple heuristic: if we see "may" before "june" or dates in ascending order
                may_positions = [i for i, d in enumerate(deadlines) if 'may' in d or '5/' in d or '05' in d]
                june_positions = [i for i, d in enumerate(deadlines) if 'june' in d or '6/' in d or '06' in d]
                
                is_sorted = True
                if may_positions and june_positions:
                    if min(may_positions) > min(june_positions):
                        is_sorted = False
                
                # Also check if "no visa" or empty comes after actual dates
                visa_texts = [i for i, d in enumerate(deadlines) if 'no' in d or 'n/a' in d or not d or d == '']
                
                if is_sorted:
                    score += 0.05
                    feedback_parts.append("✅ Countries sorted by visa deadline")
                else:
                    feedback_parts.append("⚠️ Sorting by deadline may be incorrect")
            else:
                feedback_parts.append("⚠️ Cannot verify sorting - insufficient deadline data")
        
        # Final assessment
        passed = score >= 0.75
        
        if passed:
            feedback_parts.insert(0, "🎉 Task completed successfully!")
        else:
            feedback_parts.insert(0, f"⚠️ Task incomplete (score: {score:.2f}/1.0)")
        
        return {
            "passed": passed,
            "score": round(score, 2),
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + f" | ❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


# Entry point for gym-anything
def verify(traj, env_info, task_info):
    """Entry point for verification"""
    return verify_gap_year_planner(traj, env_info, task_info)