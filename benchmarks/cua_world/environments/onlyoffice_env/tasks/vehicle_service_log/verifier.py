#!/usr/bin/env python3
"""
Verifier for Vehicle Service Log task (vehicle_service_log@1)

This verifier checks:
1. File structure: correct sheet name, columns, rows
2. Data completeness: 5 service records with all fields filled
3. Formula presence: SUM, AVERAGE, and calculation formulas
4. Value accuracy: calculated totals within reasonable ranges
5. Formatting: currency, dates, number formatting applied
6. Summary section: next service alert with calculation
"""

import sys
import os
import logging
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vehicle_service_log(traj, env_info, task_info):
    """
    Verify the vehicle maintenance log spreadsheet.
    
    Returns:
        dict with keys: passed (bool), score (float 0-1), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0.0, 
            "feedback": "❌ Copy function not available"
        }

    container_path = "/home/ga/Documents/Spreadsheets/vehicle_maintenance.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_vehicle_')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(
            container_path, copy_from_env, 'xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or failed to parse: {error}"
            }
        
        # ===================================================================
        # CRITERION 1: Sheet Structure (15 points)
        # ===================================================================
        
        # Check if sheet named "MaintenanceLog" exists
        if "MaintenanceLog" in wb.sheetnames:
            score += 5
            sheet = wb["MaintenanceLog"]
            feedback_parts.append("✅ Sheet 'MaintenanceLog' exists")
        else:
            # Try active sheet as fallback
            sheet = wb.active
            score += 2
            feedback_parts.append(f"⚠️ Sheet not named 'MaintenanceLog', using '{sheet.title}'")
        
        # Check column headers (row 1)
        headers_row = [str(cell.value).lower() if cell.value else "" for cell in sheet[1][:6]]
        required_headers = ["service date", "odometer", "service type", "cost"]
        headers_found = 0
        
        for req in required_headers:
            if any(req in h for h in headers_row):
                headers_found += 1
        
        if headers_found >= 4:
            score += 10
            feedback_parts.append(f"✅ All {headers_found}/4 required column headers present")
        elif headers_found >= 3:
            score += 6
            feedback_parts.append(f"⚠️ Found {headers_found}/4 column headers")
        else:
            score += 2
            feedback_parts.append(f"❌ Missing column headers (found {headers_found}/4)")
        
        # ===================================================================
        # CRITERION 2: Data Entry Completeness (20 points)
        # ===================================================================
        
        # Check rows 2-6 for complete data
        data_rows = []
        filled_rows = 0
        
        for row_idx in range(2, 7):  # Rows 2-6
            row_data = []
            for col_idx in range(1, 5):  # Columns A-D (Date, Mileage, Service Type, Cost)
                cell_value = sheet.cell(row=row_idx, column=col_idx).value
                row_data.append(cell_value)
            
            # Check if row is complete (no None values, no placeholder text)
            if all(val is not None for val in row_data):
                # Check if not placeholder text
                if not any(isinstance(val, str) and '[' in val for val in row_data):
                    filled_rows += 1
                    data_rows.append(row_data)
        
        if filled_rows >= 5:
            score += 20
            feedback_parts.append(f"✅ All 5 service records entered completely")
        elif filled_rows >= 4:
            score += 15
            feedback_parts.append(f"⚠️ {filled_rows}/5 service records complete")
        elif filled_rows >= 3:
            score += 10
            feedback_parts.append(f"⚠️ Only {filled_rows}/5 service records complete")
        elif filled_rows >= 1:
            score += 5
            feedback_parts.append(f"❌ Only {filled_rows}/5 service records complete")
        else:
            feedback_parts.append(f"❌ No complete service records found")
        
        # ===================================================================
        # CRITERION 3: Formula Verification (30 points)
        # ===================================================================
        
        # Check Total Maintenance Cost (B8) - should be SUM
        total_cost_cell = get_cell_value(wb, sheet.title, 'B8')
        
        if total_cost_cell and isinstance(total_cost_cell, (int, float)):
            # Expected total: 45 + 35 + 48 + 125 + 47 = 300
            if 280 <= total_cost_cell <= 320:
                score += 10
                feedback_parts.append(f"✅ Total cost correct: ${total_cost_cell:.2f} (expected ~$300)")
            elif 100 <= total_cost_cell <= 500:
                score += 6
                feedback_parts.append(f"⚠️ Total cost seems off: ${total_cost_cell:.2f} (expected ~$300)")
            else:
                score += 2
                feedback_parts.append(f"❌ Total cost very wrong: ${total_cost_cell:.2f}")
        else:
            feedback_parts.append("❌ Total cost formula missing or invalid")
        
        # Check Average Cost per Service (B9) - should be AVERAGE
        avg_cost_cell = get_cell_value(wb, sheet.title, 'B9')
        
        if avg_cost_cell and isinstance(avg_cost_cell, (int, float)):
            # Expected average: 300 / 5 = 60
            if 55 <= avg_cost_cell <= 65:
                score += 10
                feedback_parts.append(f"✅ Average cost correct: ${avg_cost_cell:.2f} (expected ~$60)")
            elif 30 <= avg_cost_cell <= 100:
                score += 6
                feedback_parts.append(f"⚠️ Average cost seems off: ${avg_cost_cell:.2f}")
            else:
                score += 2
                feedback_parts.append(f"❌ Average cost incorrect: ${avg_cost_cell:.2f}")
        else:
            feedback_parts.append("❌ Average cost formula missing or invalid")
        
        # Check Total Miles Driven (B10) - should be calculation
        total_miles_cell = get_cell_value(wb, sheet.title, 'B10')
        
        if total_miles_cell and isinstance(total_miles_cell, (int, float)):
            # Expected: 45500 - 35000 = 10500
            if 10000 <= total_miles_cell <= 11000:
                score += 5
                feedback_parts.append(f"✅ Total miles correct: {total_miles_cell:,} (expected ~10,500)")
            elif 5000 <= total_miles_cell <= 15000:
                score += 3
                feedback_parts.append(f"⚠️ Total miles seems off: {total_miles_cell:,}")
            else:
                score += 1
                feedback_parts.append(f"❌ Total miles incorrect: {total_miles_cell:,}")
        else:
            feedback_parts.append("❌ Total miles calculation missing")
        
        # Check Cost per 1,000 Miles (B11) - should be formula
        cost_per_mile_cell = get_cell_value(wb, sheet.title, 'B11')
        
        if cost_per_mile_cell and isinstance(cost_per_mile_cell, (int, float)):
            # Expected: (300 / 10500) * 1000 = 28.57
            if 25 <= cost_per_mile_cell <= 32:
                score += 5
                feedback_parts.append(f"✅ Cost per 1,000 miles correct: ${cost_per_mile_cell:.2f}")
            elif 10 <= cost_per_mile_cell <= 50:
                score += 3
                feedback_parts.append(f"⚠️ Cost per 1,000 miles seems off: ${cost_per_mile_cell:.2f}")
            else:
                score += 1
                feedback_parts.append(f"❌ Cost per 1,000 miles incorrect: ${cost_per_mile_cell:.2f}")
        else:
            feedback_parts.append("❌ Cost per 1,000 miles formula missing")
        
        # ===================================================================
        # CRITERION 4: Formatting (15 points)
        # ===================================================================
        
        # Check currency formatting in column D (Cost column)
        sample_cost_cell = sheet['D2']
        if sample_cost_cell.value is not None:
            number_format = str(sample_cost_cell.number_format)
            if '$' in number_format or 'currency' in number_format.lower() or '"$"' in number_format:
                score += 5
                feedback_parts.append("✅ Currency formatting applied to costs")
            else:
                score += 2
                feedback_parts.append(f"⚠️ Currency formatting weak or missing (format: {number_format})")
        
        # Check date formatting in column A
        sample_date_cell = sheet['A2']
        if sample_date_cell.value is not None:
            number_format = str(sample_date_cell.number_format)
            # Check if it's a date format or actual date value
            is_date_value = isinstance(sample_date_cell.value, datetime)
            is_date_format = any(x in number_format.lower() for x in ['m/d', 'd/m', 'yyyy', 'date'])
            
            if is_date_value or is_date_format:
                score += 5
                feedback_parts.append("✅ Date formatting applied")
            else:
                score += 2
                feedback_parts.append(f"⚠️ Date formatting not detected (format: {number_format})")
        
        # Check number formatting with commas (in mileage column B)
        sample_mileage_cell = sheet['B2']
        if sample_mileage_cell.value is not None and isinstance(sample_mileage_cell.value, (int, float)):
            number_format = str(sample_mileage_cell.number_format)
            if ',' in number_format or '#,##0' in number_format:
                score += 5
                feedback_parts.append("✅ Number formatting with separators applied")
            else:
                score += 2
                feedback_parts.append("⚠️ Number separators not fully applied")
        
        # ===================================================================
        # CRITERION 5: Next Service Alert Section (10 points)
        # ===================================================================
        
        # Check if "NEXT OIL CHANGE DUE" label exists (A13)
        next_service_label = get_cell_value(wb, sheet.title, 'A13')
        if next_service_label and 'oil change' in str(next_service_label).lower():
            score += 3
            feedback_parts.append("✅ Next service alert label present")
        else:
            score += 1
            feedback_parts.append("⚠️ Next service alert label missing or incorrect")
        
        # Check if next service mileage is specified (B13)
        next_service_miles = get_cell_value(wb, sheet.title, 'B13')
        if next_service_miles:
            # Check if contains "50500" or "50,500" as number or string
            if isinstance(next_service_miles, (int, float)) and 50000 <= next_service_miles <= 51000:
                score += 2
                feedback_parts.append(f"✅ Next service mileage specified: {next_service_miles}")
            elif isinstance(next_service_miles, str) and '50' in next_service_miles and '500' in next_service_miles:
                score += 2
                feedback_parts.append("✅ Next service mileage specified")
            else:
                score += 1
                feedback_parts.append("⚠️ Next service mileage present but unclear")
        
        # Check days until due calculation (B14)
        days_until_cell = get_cell_value(wb, sheet.title, 'B14')
        if days_until_cell and isinstance(days_until_cell, (int, float)):
            # Should be days between today and 2025-06-18
            # We can't know exact value but it should be positive and reasonable
            if -100 <= days_until_cell <= 600:  # Within reasonable range
                score += 5
                feedback_parts.append(f"✅ Days until due calculated: {days_until_cell} days")
            else:
                score += 2
                feedback_parts.append(f"⚠️ Days until due seems incorrect: {days_until_cell}")
        else:
            score += 1
            feedback_parts.append("⚠️ Days until due calculation missing or invalid")
        
        # ===================================================================
        # CRITERION 6: Data Accuracy Bonus (10 points)
        # ===================================================================
        
        # Bonus points for accurate data entry
        if filled_rows == 5:
            # Check if at least 3 of the specific costs are present
            costs_in_data = []
            for row_idx in range(2, 7):
                cost_val = sheet.cell(row=row_idx, column=4).value  # Column D
                if cost_val and isinstance(cost_val, (int, float)):
                    costs_in_data.append(cost_val)
            
            # Expected costs: 45, 35, 48, 125, 47
            expected_costs = [45, 35, 48, 125, 47]
            matches = 0
            for expected in expected_costs:
                if any(abs(cost - expected) <= 2 for cost in costs_in_data):
                    matches += 1
            
            if matches >= 4:
                score += 10
                feedback_parts.append(f"✅ BONUS: Data accuracy excellent ({matches}/5 costs match)")
            elif matches >= 3:
                score += 6
                feedback_parts.append(f"⚠️ BONUS: Partial data accuracy ({matches}/5 costs match)")
            elif matches >= 2:
                score += 3
                feedback_parts.append(f"⚠️ BONUS: Some data accuracy ({matches}/5 costs match)")
        
        # ===================================================================
        # Final Assessment
        # ===================================================================
        
        # Normalize score to 0-1 range
        normalized_score = min(score / max_score, 1.0)
        passed = score >= 70
        
        # Create final feedback string
        feedback = " | ".join(feedback_parts)
        feedback += f" || TOTAL SCORE: {score}/{max_score} ({int(normalized_score * 100)}%)"
        
        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification failed with exception: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything framework
def verify_task(traj, env_info, task_info):
    """Main entry point called by gym-anything"""
    return verify_vehicle_service_log(traj, env_info, task_info)