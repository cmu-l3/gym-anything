#!/usr/bin/env python3
"""
Verifier for IRS Mileage Audit Log task

Verifies that the mileage log meets IRS Publication 463 requirements:
- Required fields present (Date, Business Purpose, Starting Location, Destination, Miles)
- All 12 trips documented with complete information
- Business purposes are specific (not vague)
- Calculations are accurate (total miles ~134, deduction ~$89.78)
- Professional formatting applied
"""

import sys
import os
import logging
import tempfile
import re
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


def verify_irs_mileage_log(traj, env_info, task_info):
    """
    Verify IRS-compliant mileage log spreadsheet
    
    Returns:
        dict: {
            "passed": bool,
            "score": float (0-110, with bonus points for formatting),
            "feedback": str
        }
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/mileage_log_2024_q1.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_mileage_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=25, max_cols=10)

        if len(data) < 2:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet is empty or has only one row"}

        score = 0
        feedback_parts = []

        # Required field mapping (various acceptable names)
        REQUIRED_FIELDS = {
            'date': ['date', 'trip date', 'day'],
            'purpose': ['business purpose', 'purpose', 'reason', 'description'],
            'start': ['starting location', 'starting point', 'origin', 'from', 'start'],
            'destination': ['destination', 'ending location', 'to', 'end location'],
            'miles': ['miles', 'miles driven', 'distance', 'mileage', 'mi']
        }

        # B. Header validation (20 points)
        headers_row = data[0] if data else []
        headers = [str(h).lower().strip() if h else "" for h in headers_row]
        found_fields = {}

        for field_type, acceptable_names in REQUIRED_FIELDS.items():
            found = False
            for idx, header in enumerate(headers):
                if not header:
                    continue
                for name in acceptable_names:
                    if name in header:
                        found = True
                        found_fields[field_type] = idx
                        break
                if found:
                    break
            
            if found:
                score += 4  # 5 fields × 4 points = 20
            else:
                feedback_parts.append(f"❌ Missing required field: {field_type}")

        if len(found_fields) == 5:
            feedback_parts.append("✅ All 5 required IRS fields present")
        else:
            feedback_parts.append(f"⚠️ Only {len(found_fields)}/5 required fields found")
        
        if len(found_fields) < 3:
            # Cannot proceed with meaningful verification
            feedback = " | ".join(feedback_parts)
            return {"passed": False, "score": score, "feedback": feedback + " | Cannot verify data without proper headers"}

        # C. Data completeness (30 points)
        data_rows = data[1:]  # Exclude header
        complete_rows = 0
        trip_details = []

        for row_idx, row in enumerate(data_rows, start=2):
            if not any(row):  # Skip completely empty rows
                continue
            
            # Stop counting if we hit a totals row or summary section
            row_str = ' '.join([str(cell) for cell in row if cell]).lower()
            if any(keyword in row_str for keyword in ['total', 'sum', 'grand total', 'subtotal']):
                break
            
            try:
                # Check date field
                date_val = row[found_fields.get('date', 0)] if 'date' in found_fields else None
                has_date = date_val is not None and date_val != ""
                
                # Check purpose field (must be specific, >10 chars)
                purpose = str(row[found_fields.get('purpose', 1)] or "") if 'purpose' in found_fields else ""
                has_purpose = len(purpose) > 10
                
                # Check starting location
                start_val = row[found_fields.get('start', 2)] if 'start' in found_fields else None
                has_start = start_val is not None and str(start_val).strip() != ""
                
                # Check destination
                dest_val = row[found_fields.get('destination', 3)] if 'destination' in found_fields else None
                has_destination = dest_val is not None and str(dest_val).strip() != ""
                
                # Check miles (must be numeric and reasonable)
                miles_val = row[found_fields.get('miles', 4)] if 'miles' in found_fields else None
                has_miles = False
                miles_numeric = 0
                
                if miles_val is not None:
                    try:
                        miles_numeric = float(miles_val)
                        has_miles = 3 <= miles_numeric <= 30
                    except (ValueError, TypeError):
                        has_miles = False
                
                if all([has_date, has_purpose, has_start, has_destination, has_miles]):
                    complete_rows += 1
                    trip_details.append({
                        'row': row_idx,
                        'purpose': purpose,
                        'miles': miles_numeric
                    })
            except (IndexError, KeyError, TypeError) as e:
                logger.debug(f"Error checking row {row_idx}: {e}")
                continue

        # Score based on complete rows
        if complete_rows >= 12:
            score += 30
            feedback_parts.append(f"✅ All {complete_rows} trips documented completely")
        elif complete_rows >= 10:
            score += 25
            feedback_parts.append(f"⚠️ {complete_rows}/12 trips complete (good)")
        elif complete_rows >= 8:
            score += 20
            feedback_parts.append(f"⚠️ {complete_rows}/12 trips complete (acceptable)")
        elif complete_rows >= 6:
            score += 15
            feedback_parts.append(f"⚠️ {complete_rows}/12 trips complete (needs improvement)")
        else:
            score += (complete_rows * 2)
            feedback_parts.append(f"❌ Only {complete_rows}/12 trips complete")

        # D. Business purpose specificity (15 points)
        specific_purposes = 0
        vague_purposes = []
        
        # Keywords that indicate specificity
        specific_keywords = [
            'website', 'logo', 'branding', 'presentation', 'consultation', 
            'review', 'design', 'contract', 'portfolio', 'pitch', 'proofs',
            'signing', 'session', 'coordination', 'techstart', 'creative co',
            'speedyprint', 'bakery', 'author', 'attorney'
        ]
        
        for trip in trip_details[:12]:
            purpose = trip['purpose'].lower()
            # Check for specificity: length AND meaningful content
            is_specific = (
                len(purpose) > 20 and 
                any(keyword in purpose for keyword in specific_keywords)
            )
            
            if is_specific:
                specific_purposes += 1
            else:
                vague_purposes.append(purpose[:30])

        if specific_purposes >= 10:
            score += 15
            feedback_parts.append(f"✅ Business purposes are IRS-compliant ({specific_purposes}/12 specific)")
        elif specific_purposes >= 7:
            score += 12
            feedback_parts.append(f"⚠️ Most purposes specific ({specific_purposes}/12), but some too vague")
        elif specific_purposes >= 5:
            score += 8
            feedback_parts.append(f"⚠️ Some purposes too vague for IRS ({specific_purposes}/12 specific)")
        else:
            score += 3
            feedback_parts.append(f"❌ Business purposes too vague - IRS requires specifics ({specific_purposes}/12)")

        # E. Calculation accuracy (25 points)
        total_miles = 0
        calculated_deduction = None
        has_formula = False
        
        # Calculate total miles from trip data
        for trip in trip_details[:12]:
            total_miles += trip['miles']
        
        expected_miles = 134
        expected_deduction = expected_miles * 0.67  # $89.78
        
        # Look for totals in the spreadsheet
        found_total_row = False
        for row_idx, row in enumerate(data_rows):
            if not any(row):
                continue
            
            row_str = ' '.join([str(cell) for cell in row if cell]).lower()
            if 'total' in row_str or 'sum' in row_str:
                found_total_row = True
                
                # Check for miles total
                if 'miles' in found_fields:
                    miles_col = found_fields['miles']
                    if miles_col < len(row):
                        miles_in_total = row[miles_col]
                        if miles_in_total and isinstance(miles_in_total, (int, float)):
                            total_miles = miles_in_total
                
                # Check for deduction amount (look for currency values)
                for cell_idx, cell in enumerate(row):
                    if cell and isinstance(cell, (int, float)):
                        if 85 <= cell <= 95:
                            calculated_deduction = cell
                        elif 8500 <= cell <= 9500:  # Might be in cents
                            calculated_deduction = cell / 100
                
                # Check if formulas are used (check actual cell objects)
                try:
                    actual_row_idx = row_idx + 2  # +1 for header, +1 for 0-index
                    for col_idx in range(len(row)):
                        cell = sheet.cell(row=actual_row_idx, column=col_idx + 1)
                        if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                            has_formula = True
                            break
                except:
                    pass

        miles_accurate = abs(total_miles - expected_miles) <= 3
        
        if calculated_deduction:
            deduction_accurate = abs(calculated_deduction - expected_deduction) <= 2.0
            
            if miles_accurate and deduction_accurate and has_formula:
                score += 25
                feedback_parts.append(f"✅ Calculations perfect: {total_miles:.0f} miles, ${calculated_deduction:.2f} deduction, formulas used")
            elif miles_accurate and deduction_accurate:
                score += 22
                feedback_parts.append(f"✅ Calculations correct: {total_miles:.0f} miles, ${calculated_deduction:.2f} deduction")
            elif miles_accurate:
                score += 15
                feedback_parts.append(f"⚠️ Miles correct ({total_miles:.0f}) but deduction calculation off (${calculated_deduction:.2f} vs ${expected_deduction:.2f})")
            else:
                score += 10
                feedback_parts.append(f"⚠️ Totals present but calculations have errors")
        elif miles_accurate:
            score += 12
            feedback_parts.append(f"⚠️ Total miles correct ({total_miles:.0f}) but missing deduction calculation")
        elif found_total_row:
            score += 5
            feedback_parts.append(f"⚠️ Totals row present but calculations incorrect (got {total_miles:.0f} miles, expected ~{expected_miles})")
        else:
            feedback_parts.append(f"❌ Missing totals and calculations")

        # F. Professional formatting (10 bonus points)
        bonus = 0
        
        try:
            # Check for header formatting (bold)
            first_row_cells = list(sheet[1])
            bold_headers = sum(1 for cell in first_row_cells if cell.value and hasattr(cell.font, 'bold') and cell.font.bold)
            if bold_headers >= 3:
                bonus += 3
                feedback_parts.append("⭐ Headers formatted (bold)")
            
            # Check for borders
            has_borders = False
            for row_idx in range(2, min(5, len(data) + 1)):
                for col_idx in range(1, 6):
                    cell = sheet.cell(row=row_idx, column=col_idx)
                    if cell.border and (cell.border.left.style or cell.border.top.style):
                        has_borders = True
                        break
                if has_borders:
                    break
            
            if has_borders:
                bonus += 2
                feedback_parts.append("⭐ Professional borders applied")
            
            # Check for currency formatting
            has_currency = False
            for row in sheet.iter_rows(min_row=2, max_row=20):
                for cell in row:
                    if cell.number_format and ('$' in cell.number_format or 'currency' in cell.number_format.lower()):
                        has_currency = True
                        break
                if has_currency:
                    break
            
            if has_currency:
                bonus += 3
                feedback_parts.append("⭐ Currency formatting applied")
            
            # Check for formulas (not just static values)
            if has_formula:
                bonus += 2
                feedback_parts.append("⭐ Formulas used (not manual calculations)")
            
        except Exception as e:
            logger.debug(f"Error checking formatting: {e}")

        score += min(bonus, 10)  # Cap bonus at 10

        # Final determination
        passed = score >= 75
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": min(score, 110),  # Cap at 110 with bonus
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)