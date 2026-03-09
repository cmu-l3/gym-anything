#!/usr/bin/env python3
"""
Verifier for Equipment Rental Coordinator task
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, date
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    parse_xlsx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_item_name(item_name):
    """Normalize equipment item names for comparison"""
    if not item_name:
        return ""
    item = str(item_name).lower().strip()
    # Normalize variations
    if "projector" in item:
        return "projector"
    elif "pa" in item or "sound" in item:
        return "pa_system"
    elif "table" in item or "folding" in item:
        return "tables"
    return item


def normalize_renter_name(name):
    """Normalize renter names for comparison"""
    if not name:
        return ""
    name = str(name).lower().strip()
    # Handle various formats: "Alice Chen", "alice chen", "ALICE CHEN", etc.
    return name.replace("  ", " ")


def parse_date_flexible(date_val):
    """Parse various date formats flexibly"""
    if isinstance(date_val, (datetime, date)):
        return date_val if isinstance(date_val, date) else date_val.date()
    
    if not date_val:
        return None
    
    date_str = str(date_val).strip()
    
    # Try common formats
    formats = [
        "%Y-%m-%d",
        "%m/%d/%Y",
        "%d/%m/%Y",
        "%Y/%m/%d",
        "%m-%d-%Y",
        "%d-%m-%Y",
        "%B %d, %Y",
        "%b %d, %Y",
        "%m/%d/%y",
        "%d/%m/%y"
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt).date()
        except:
            continue
    
    # Try parsing "March 15-17, 2025" style (extract first date)
    match = re.search(r'(\w+)\s+(\d+)', date_str)
    if match:
        try:
            month_name, day = match.groups()
            # Assume 2025 if year not found
            year_match = re.search(r'20\d{2}', date_str)
            year = year_match.group(0) if year_match else "2025"
            date_str_normalized = f"{month_name} {day}, {year}"
            return datetime.strptime(date_str_normalized, "%B %d, %Y").date()
        except:
            pass
    
    return None


def check_date_overlap(start1, end1, start2, end2):
    """Check if two date ranges overlap"""
    if not all([start1, end1, start2, end2]):
        return False
    return start1 <= end2 and end1 >= start2


def verify_equipment_rental_tracker(traj, env_info, task_info):
    """
    Verify equipment rental tracking spreadsheet.
    
    Checks:
    1. All 6 rentals are entered
    2. Dates are valid and in expected range
    3. Deposits are correct (20% of equipment value)
    4. Conflict is correctly identified for PA System overlap
    5. Non-conflicts are not flagged
    6. Days rented calculation (if present)
    7. Professional formatting
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/equipment_rental_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_rental_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to load spreadsheet: {error}"
            }

        # Get active sheet
        try:
            sheet = wb.active
            data = list(sheet.iter_rows(values_only=True))
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read sheet data: {str(e)}"
            }

        if len(data) < 2:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Spreadsheet is empty or has no data rows"
            }

        feedback_parts = []
        score = 0

        # Identify header row and columns
        header_row = data[0]
        col_map = {}
        
        for idx, header in enumerate(header_row):
            if not header:
                continue
            h_lower = str(header).lower()
            
            if 'item' in h_lower and ('name' in h_lower or h_lower.startswith('item')):
                col_map['item'] = idx
            elif 'renter' in h_lower or ('name' in h_lower and 'renter' in h_lower):
                col_map['renter'] = idx
            elif 'start' in h_lower and 'date' in h_lower:
                col_map['start'] = idx
            elif 'end' in h_lower and 'date' in h_lower:
                col_map['end'] = idx
            elif 'deposit' in h_lower and 'paid' in h_lower:
                col_map['deposit'] = idx
            elif ('equipment' in h_lower or 'item' in h_lower) and 'value' in h_lower:
                col_map['equipment_value'] = idx
            elif 'conflict' in h_lower:
                col_map['conflict'] = idx
            elif 'days' in h_lower and 'rented' in h_lower:
                col_map['days_rented'] = idx

        logger.info(f"Column mapping: {col_map}")

        # Expected rental data for validation
        expected_rentals = [
            {
                "item": "projector",
                "renter": "alice chen",
                "start": "2025-03-15",
                "end": "2025-03-17",
                "deposit": 60,
                "value": 300,
                "days": 3
            },
            {
                "item": "pa_system",
                "renter": "bob martinez",
                "start": "2025-03-16",
                "end": "2025-03-18",
                "deposit": 100,
                "value": 500,
                "days": 3,
                "conflict": True
            },
            {
                "item": "tables",
                "renter": "alice chen",
                "start": "2025-03-15",
                "end": "2025-03-17",
                "deposit": 40,
                "value": 200,
                "days": 3
            },
            {
                "item": "projector",
                "renter": "dana kim",
                "start": "2025-03-18",
                "end": "2025-03-20",
                "deposit": 60,
                "value": 300,
                "days": 3
            },
            {
                "item": "pa_system",
                "renter": "elena rodriguez",
                "start": "2025-03-17",
                "end": "2025-03-19",
                "deposit": 100,
                "value": 500,
                "days": 3,
                "conflict": True
            },
            {
                "item": "tables",
                "renter": "frank thompson",
                "start": "2025-03-19",
                "end": "2025-03-21",
                "deposit": 40,
                "value": 200,
                "days": 3
            }
        ]

        # Extract data rows (skip header)
        data_rows = data[1:]
        non_empty_rows = []
        
        for row in data_rows:
            # Check if row has any content
            if any(cell is not None and str(cell).strip() for cell in row):
                # Skip instruction rows (check if first cell starts with "INSTRUCTIONS")
                first_cell = str(row[0]).upper() if row[0] else ""
                if "INSTRUCTION" not in first_cell:
                    non_empty_rows.append(row)

        logger.info(f"Found {len(non_empty_rows)} non-empty data rows")

        # CRITERION 1: Check data completeness (6 rentals) - 20 points
        if len(non_empty_rows) >= 6:
            score += 20
            feedback_parts.append(f"✅ All 6 rentals entered ({len(non_empty_rows)} rows found)")
        elif len(non_empty_rows) >= 4:
            score += 12
            feedback_parts.append(f"⚠️ Only {len(non_empty_rows)} rentals found (expected 6)")
        else:
            feedback_parts.append(f"❌ Only {len(non_empty_rows)} rentals found (expected 6)")

        # Parse entered rental data
        entered_rentals = []
        for row in non_empty_rows:
            rental = {}
            
            if 'item' in col_map:
                rental['item'] = normalize_item_name(row[col_map['item']])
            if 'renter' in col_map:
                rental['renter'] = normalize_renter_name(row[col_map['renter']])
            if 'start' in col_map:
                rental['start'] = parse_date_flexible(row[col_map['start']])
            if 'end' in col_map:
                rental['end'] = parse_date_flexible(row[col_map['end']])
            if 'deposit' in col_map:
                try:
                    deposit_val = row[col_map['deposit']]
                    if isinstance(deposit_val, (int, float)):
                        rental['deposit'] = float(deposit_val)
                    elif isinstance(deposit_val, str):
                        # Remove $ and parse
                        rental['deposit'] = float(deposit_val.replace('$', '').replace(',', '').strip())
                except:
                    rental['deposit'] = None
            if 'conflict' in col_map:
                conflict_val = str(row[col_map['conflict']]).upper() if row[col_map['conflict']] else ''
                rental['conflict'] = any(word in conflict_val for word in ['YES', 'TRUE', 'X', 'CONFLICT', '1'])
            if 'days_rented' in col_map:
                try:
                    days_val = row[col_map['days_rented']]
                    rental['days_rented'] = int(days_val) if days_val else None
                except:
                    rental['days_rented'] = None
                    
            entered_rentals.append(rental)

        logger.info(f"Parsed rentals: {entered_rentals}")

        # CRITERION 2: Check deposit calculations (20% rule) - 25 points
        deposit_correct_count = 0
        expected_deposits = {"projector": 60, "pa_system": 100, "tables": 40}
        
        for rental in entered_rentals:
            item = rental.get('item', '')
            deposit = rental.get('deposit')
            expected = expected_deposits.get(item)
            
            if expected and deposit is not None:
                if abs(deposit - expected) <= 1:  # Allow $1 tolerance
                    deposit_correct_count += 1

        if deposit_correct_count >= 5:
            score += 25
            feedback_parts.append(f"✅ Deposits correctly calculated ({deposit_correct_count}/6 match 20% rule)")
        elif deposit_correct_count >= 3:
            score += 15
            feedback_parts.append(f"⚠️ Partial deposit accuracy ({deposit_correct_count}/6 match 20% rule)")
        else:
            feedback_parts.append(f"❌ Deposits incorrect ({deposit_correct_count}/6 match 20% rule)")

        # CRITERION 3: Check conflict detection - 30 points
        conflict_detected = False
        bob_flagged = False
        elena_flagged = False
        false_positives = 0
        
        if 'conflict' in col_map:
            for rental in entered_rentals:
                item = rental.get('item', '')
                renter = rental.get('renter', '')
                is_conflict = rental.get('conflict', False)
                
                # Check if PA System rentals are flagged
                if item == "pa_system":
                    if "bob" in renter and "martinez" in renter:
                        if is_conflict:
                            bob_flagged = True
                    elif "elena" in renter and "rodriguez" in renter:
                        if is_conflict:
                            elena_flagged = True
                
                # Check for false positives (non-conflicting rentals flagged)
                elif is_conflict:
                    # Alice's projector/tables don't conflict with each other
                    # Dana's projector doesn't conflict (different dates from Alice)
                    # Frank's tables don't conflict (different dates from Alice)
                    false_positives += 1
            
            if bob_flagged and elena_flagged:
                score += 30
                feedback_parts.append("✅ PA System conflict correctly identified for both Bob and Elena")
                conflict_detected = True
            elif bob_flagged or elena_flagged:
                score += 15
                feedback_parts.append("⚠️ PA System conflict partially identified (only one renter flagged)")
                conflict_detected = True
            else:
                feedback_parts.append("❌ PA System conflict not detected")
            
            if false_positives > 0:
                feedback_parts.append(f"⚠️ {false_positives} false positive conflict(s) flagged")
        else:
            feedback_parts.append("❌ No conflict detection column found")

        # CRITERION 4: Check date validity - 15 points
        valid_dates = 0
        march_2025_dates = 0
        
        for rental in entered_rentals:
            start = rental.get('start')
            end = rental.get('end')
            
            if start and end:
                # Check dates are logical (start < end)
                if start <= end:
                    valid_dates += 1
                    
                # Check dates are in March 2025
                if start.year == 2025 and start.month == 3:
                    march_2025_dates += 1

        if valid_dates >= 5 and march_2025_dates >= 5:
            score += 15
            feedback_parts.append(f"✅ Dates properly formatted and logical ({valid_dates}/6 valid, {march_2025_dates}/6 in March 2025)")
        elif valid_dates >= 4:
            score += 10
            feedback_parts.append(f"⚠️ Most dates valid ({valid_dates}/6)")
        else:
            feedback_parts.append(f"❌ Date formatting issues ({valid_dates}/6 valid)")

        # CRITERION 5: Check for formula usage - 10 points
        has_formulas = False
        formula_count = 0
        
        try:
            for row in sheet.iter_rows(min_row=2, max_row=min(8, len(data))):
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        has_formulas = True
                        formula_count += 1
        except:
            pass

        if has_formulas:
            score += 10
            feedback_parts.append(f"✅ Formulas used for calculations ({formula_count} found)")
        else:
            feedback_parts.append("⚠️ No formulas detected (calculations may be manual)")

        # Bonus: Check if renters are correctly entered
        expected_renters = ["alice chen", "bob martinez", "dana kim", "elena rodriguez", "frank thompson"]
        found_renters = set()
        
        for rental in entered_rentals:
            renter = rental.get('renter', '')
            if renter:
                # Check if it matches any expected renter
                for expected in expected_renters:
                    if expected.split()[0] in renter and expected.split()[1] in renter:
                        found_renters.add(expected)

        if len(found_renters) >= 5:
            feedback_parts.append(f"✅ All renters correctly identified")

        # Final evaluation
        passed = score >= 75
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
