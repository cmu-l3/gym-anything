#!/usr/bin/env python3
"""
Verifier for Home Inventory Insurance task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for flexible matching"""
    if text is None:
        return ""
    return str(text).strip().lower()


def extract_number(value):
    """Extract numeric value from cell (handles currency formatting, text, etc.)"""
    if value is None:
        return None
    
    if isinstance(value, (int, float)):
        return float(value)
    
    # Try to extract number from string
    text = str(value)
    # Remove currency symbols, commas, etc.
    text = re.sub(r'[$,]', '', text)
    try:
        return float(text)
    except:
        return None


def verify_home_inventory_insurance(traj, env_info, task_info):
    """
    Verify that home inventory spreadsheet was created correctly.

    Checks:
    1. Core data entry: 7 items with correct details (40 points)
    2. Formulas and calculations: SUM formulas in D9, E9 (25 points)
    3. High-value items section: 3 items listed (20 points)
    4. Documentation priority section: 2 items listed (10 points)
    5. Basic formatting: Bold headers (5 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/Home_Inventory.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_inventory_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load spreadsheet: {error}"
            }

        sheet = wb.active
        total_score = 0.0
        feedback_parts = []

        # ===================================================================
        # CRITERION 1: Core data entry (7 items in rows 2-8) - 40 points
        # ===================================================================
        expected_items = [
            {
                "row": 2,
                "room_keywords": ["living", "room"],
                "item_keywords": ["samsung", "tv"],
                "original_cost": 1800,
                "current_value": 900,
                "serial_keywords": ["sam", "789"],
                "receipt": "yes"
            },
            {
                "row": 3,
                "room_keywords": ["living", "room"],
                "item_keywords": ["bose", "sound"],
                "original_cost": 1200,
                "current_value": 600,
                "serial_keywords": ["bose", "456"],
                "receipt": "yes"
            },
            {
                "row": 4,
                "room_keywords": ["master", "bedroom"],
                "item_keywords": ["diamond", "ring", "engagement"],
                "original_cost": 4500,
                "current_value": 5200,
                "serial_keywords": ["n/a", "na"],
                "receipt": "yes"
            },
            {
                "row": 5,
                "room_keywords": ["home", "office"],
                "item_keywords": ["macbook", "pro"],
                "original_cost": 2800,
                "current_value": 2100,
                "serial_keywords": ["mbp", "2022"],
                "receipt": "yes"
            },
            {
                "row": 6,
                "room_keywords": ["garage"],
                "item_keywords": ["mountain", "bike", "trek"],
                "original_cost": 1600,
                "current_value": 1000,
                "serial_keywords": ["trk", "2021"],
                "receipt": "no"
            },
            {
                "row": 7,
                "room_keywords": ["basement"],
                "item_keywords": ["gibson", "guitar"],
                "original_cost": None,  # "Unknown" is acceptable
                "current_value": 2500,
                "serial_keywords": ["gibs", "1987"],
                "receipt": "no"
            },
            {
                "row": 8,
                "room_keywords": ["kitchen"],
                "item_keywords": ["kitchenaid", "mixer"],
                "original_cost": 450,
                "current_value": 350,
                "serial_keywords": ["n/a", "na"],
                "receipt": "yes"
            }
        ]

        items_correct = 0
        item_details = []

        for expected in expected_items:
            row = expected["row"]
            
            room = normalize_text(get_cell_value(wb, sheet.title, f'A{row}'))
            item = normalize_text(get_cell_value(wb, sheet.title, f'B{row}'))
            original_cost = extract_number(get_cell_value(wb, sheet.title, f'D{row}'))
            current_value = extract_number(get_cell_value(wb, sheet.title, f'E{row}'))
            serial = normalize_text(get_cell_value(wb, sheet.title, f'F{row}'))
            receipt = normalize_text(get_cell_value(wb, sheet.title, f'G{row}'))
            
            item_correct = True
            
            # Check room
            if not any(keyword in room for keyword in expected["room_keywords"]):
                item_correct = False
            
            # Check item description
            if not any(keyword in item for keyword in expected["item_keywords"]):
                item_correct = False
            
            # Check original cost (allow None for "Unknown")
            if expected["original_cost"] is not None:
                if original_cost is None or abs(original_cost - expected["original_cost"]) > 10:
                    item_correct = False
            
            # Check current value
            if current_value is None or abs(current_value - expected["current_value"]) > 10:
                item_correct = False
            
            # Check serial (flexible - just check if some keywords present)
            if not any(keyword in serial for keyword in expected["serial_keywords"]):
                item_correct = False
            
            # Check receipt status
            if expected["receipt"] not in receipt:
                item_correct = False
            
            if item_correct:
                items_correct += 1
                item_details.append(f"Row {row}: ✓")
            else:
                item_details.append(f"Row {row}: ✗")

        data_entry_score = (items_correct / 7.0) * 40
        total_score += data_entry_score
        feedback_parts.append(f"Data entry: {items_correct}/7 items correct ({data_entry_score:.1f}/40 pts)")

        # ===================================================================
        # CRITERION 2: Formulas and calculations (row 9) - 25 points
        # ===================================================================
        d9_value = extract_number(get_cell_value(wb, sheet.title, 'D9'))
        e9_value = extract_number(get_cell_value(wb, sheet.title, 'E9'))
        
        # Expected totals (accounting for "Unknown" in row 7 original cost)
        # If Unknown is 0 or missing: total = 1800+1200+4500+2800+1600+450 = 12350
        # If Unknown is included as 2500: total would be higher
        # We'll be flexible and check if it's in reasonable range
        
        formula_score = 0.0
        
        # Check D9 (Original Cost total)
        # Expected range: 12350 (without Gibson) to 14850 (with Gibson valued at 2500)
        if d9_value is not None:
            if 12000 <= d9_value <= 15000:
                formula_score += 12.5
                feedback_parts.append(f"✅ Original cost total: ${d9_value:.0f} (12.5/12.5 pts)")
            else:
                feedback_parts.append(f"❌ Original cost total incorrect: ${d9_value:.0f} (expected ~$12,350-$14,850) (0/12.5 pts)")
        else:
            feedback_parts.append("❌ Original cost total missing (0/12.5 pts)")
        
        # Check E9 (Current Value total)
        # Expected: 900+600+5200+2100+1000+2500+350 = 12650
        if e9_value is not None:
            if 12500 <= e9_value <= 12800:
                formula_score += 12.5
                feedback_parts.append(f"✅ Current value total: ${e9_value:.0f} (12.5/12.5 pts)")
            else:
                feedback_parts.append(f"❌ Current value total incorrect: ${e9_value:.0f} (expected ~$12,650) (0/12.5 pts)")
        else:
            feedback_parts.append("❌ Current value total missing (0/12.5 pts)")
        
        total_score += formula_score

        # ===================================================================
        # CRITERION 3: High-value items section (rows 11-15) - 20 points
        # ===================================================================
        high_value_score = 0.0
        
        # Check section header in A11
        a11 = normalize_text(get_cell_value(wb, sheet.title, 'A11'))
        if "high" in a11 and "value" in a11:
            high_value_score += 2
        
        # Check for three high-value items in rows 13-15
        row13_item = normalize_text(get_cell_value(wb, sheet.title, 'A13'))
        row13_value = extract_number(get_cell_value(wb, sheet.title, 'B13'))
        
        row14_item = normalize_text(get_cell_value(wb, sheet.title, 'A14'))
        row14_value = extract_number(get_cell_value(wb, sheet.title, 'B14'))
        
        row15_item = normalize_text(get_cell_value(wb, sheet.title, 'A15'))
        row15_value = extract_number(get_cell_value(wb, sheet.title, 'B15'))
        
        high_value_items_correct = 0
        
        # Check row 13: Diamond Ring, $5200
        if ("diamond" in row13_item or "ring" in row13_item) and (row13_value and abs(row13_value - 5200) < 100):
            high_value_items_correct += 1
            high_value_score += 6
        
        # Check row 14: MacBook Pro, $2100
        if ("macbook" in row14_item or "laptop" in row14_item) and (row14_value and abs(row14_value - 2100) < 100):
            high_value_items_correct += 1
            high_value_score += 6
        
        # Check row 15: Gibson Guitar, $2500
        if ("guitar" in row15_item or "gibson" in row15_item) and (row15_value and abs(row15_value - 2500) < 100):
            high_value_items_correct += 1
            high_value_score += 6
        
        total_score += high_value_score
        feedback_parts.append(f"High-value items: {high_value_items_correct}/3 items correct ({high_value_score:.1f}/20 pts)")

        # ===================================================================
        # CRITERION 4: Documentation priority section (rows 17-19) - 10 points
        # ===================================================================
        doc_priority_score = 0.0
        
        # Check section header in A17
        a17 = normalize_text(get_cell_value(wb, sheet.title, 'A17'))
        if ("items" in a17 or "documentation" in a17 or "needing" in a17) and ("photo" in a17 or "receipt" in a17):
            doc_priority_score += 2
        
        # Check for two items needing documentation
        a18 = normalize_text(get_cell_value(wb, sheet.title, 'A18'))
        a19 = normalize_text(get_cell_value(wb, sheet.title, 'A19'))
        
        doc_items_correct = 0
        
        # Check for Mountain Bike
        if "bike" in a18 or "mountain" in a18 or "trek" in a18:
            doc_items_correct += 1
            doc_priority_score += 4
        elif "bike" in a19 or "mountain" in a19 or "trek" in a19:
            doc_items_correct += 1
            doc_priority_score += 4
        
        # Check for Gibson Guitar
        if "guitar" in a18 or "gibson" in a18:
            doc_items_correct += 1
            doc_priority_score += 4
        elif "guitar" in a19 or "gibson" in a19:
            doc_items_correct += 1
            doc_priority_score += 4
        
        total_score += doc_priority_score
        feedback_parts.append(f"Documentation priority: {doc_items_correct}/2 items correct ({doc_priority_score:.1f}/10 pts)")

        # ===================================================================
        # CRITERION 5: Basic formatting (bold headers) - 5 points
        # ===================================================================
        format_score = 0.0
        
        # Check if row 1 headers are bold
        try:
            a1_cell = sheet['A1']
            if a1_cell.font and a1_cell.font.bold:
                format_score += 2
        except:
            pass
        
        # Check if row 9 is bold (total row)
        try:
            a9_cell = sheet['A9']
            if a9_cell.font and a9_cell.font.bold:
                format_score += 1.5
        except:
            pass
        
        # Check if section headers (A11, A17) are bold
        try:
            a11_cell = sheet['A11']
            a17_cell = sheet['A17']
            if (a11_cell.font and a11_cell.font.bold) or (a17_cell.font and a17_cell.font.bold):
                format_score += 1.5
        except:
            pass
        
        total_score += format_score
        feedback_parts.append(f"Formatting: {format_score:.1f}/5 pts")

        # ===================================================================
        # Final assessment
        # ===================================================================
        passed = total_score >= 70.0
        normalized_score = total_score / 100.0
        
        feedback = " | ".join(feedback_parts)

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
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)