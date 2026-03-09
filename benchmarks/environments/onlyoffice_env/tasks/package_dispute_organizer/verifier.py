#!/usr/bin/env python3
"""
Verifier for package_dispute_organizer@1
Checks spreadsheet structure, data completeness, formulas, priority flags, and calculations
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_sheet_data,
    get_cell_value,
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_package_dispute_organizer(traj, env_info, task_info):
    """
    Verify the package dispute tracker spreadsheet
    
    Expected criteria:
    1. All 6 packages listed (or at least 5 with issues)
    2. Required columns present (item, tracking, carrier, dates, amounts, etc.)
    3. Key package items documented (monitor, chair, lamp, webcam, supplies)
    4. Tracking numbers included
    5. Refund amounts documented (numeric values)
    6. Total refund calculation present (~$768 for 5 problem items)
    7. Priority/urgency flagging system
    8. Evidence tracking columns
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/Spreadsheets/package_disputes.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_dispute_')
    
    try:
        # Copy and parse the spreadsheet
        success, workbook, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to open spreadsheet: {error}"
            }
        
        # Get the first sheet
        sheet_names = workbook.sheetnames
        if not sheet_names:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        sheet = workbook[sheet_name]
        
        # Extract data (get more rows/cols to be safe)
        data = get_sheet_data(workbook, sheet_name, max_rows=30, max_cols=20)
        
        if len(data) < 2:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Spreadsheet appears empty (need header + data rows)"
            }
        
        # Convert all data to lowercase strings for searching
        all_text_lower = ""
        numeric_values = []
        
        for row in data:
            for cell in row:
                if cell is not None:
                    cell_str = str(cell).lower()
                    all_text_lower += " " + cell_str
                    # Extract numeric values
                    if isinstance(cell, (int, float)) and cell > 0:
                        numeric_values.append(cell)
        
        # Find header row (should contain key terms)
        header_row_idx = 0
        header_row = []
        for idx, row in enumerate(data[:5]):  # Check first 5 rows for headers
            row_text = " ".join([str(c).lower() if c else "" for c in row])
            if "item" in row_text or "tracking" in row_text or "package" in row_text:
                header_row = [str(cell).lower() if cell else "" for cell in row]
                header_row_idx = idx
                break
        
        # Get data rows (everything after header)
        data_rows = data[header_row_idx + 1:] if header_row_idx < len(data) - 1 else data[1:]
        
        # Remove completely empty rows
        data_rows = [row for row in data_rows if any(cell for cell in row)]
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        
        # ===== Criterion 1: Minimum number of package entries =====
        # Should have at least 5 rows (the 5 problematic packages)
        # 6 if they included the cable organizer that had no issue
        if len(data_rows) >= 5:
            feedback_parts.append(f"✅ Found {len(data_rows)} package entries (expected 5-6)")
            criteria_passed += 1
        elif len(data_rows) >= 4:
            feedback_parts.append(f"⚠️ Found {len(data_rows)} package entries (expected at least 5)")
            criteria_passed += 0.5
        else:
            feedback_parts.append(f"❌ Only {len(data_rows)} package entries found (need at least 5)")
        
        # ===== Criterion 2: Required columns present =====
        required_keywords = [
            'item', 'tracking', 'carrier', 'order', 'issue', 
            'deadline', 'refund', 'amount', 'priority'
        ]
        
        found_columns = sum(1 for keyword in required_keywords 
                           if any(keyword in h for h in header_row))
        
        if found_columns >= 7:
            feedback_parts.append(f"✅ Core columns present ({found_columns}/{len(required_keywords)} keywords)")
            criteria_passed += 1
        elif found_columns >= 5:
            feedback_parts.append(f"⚠️ Some columns present ({found_columns}/{len(required_keywords)} keywords)")
            criteria_passed += 0.5
        else:
            feedback_parts.append(f"❌ Missing key columns ({found_columns}/{len(required_keywords)} keywords found)")
        
        # ===== Criterion 3: Key package items documented =====
        expected_items = ['monitor', 'chair', 'lamp', 'webcam', 'cable', 'supplies']
        found_items = [item for item in expected_items if item in all_text_lower]
        
        if len(found_items) >= 5:
            feedback_parts.append(f"✅ Key items documented ({len(found_items)}/6: {', '.join(found_items)})")
            criteria_passed += 1
        elif len(found_items) >= 4:
            feedback_parts.append(f"⚠️ Most items documented ({len(found_items)}/6)")
            criteria_passed += 0.5
        else:
            feedback_parts.append(f"❌ Many items missing ({len(found_items)}/6 found)")
        
        # ===== Criterion 4: Tracking numbers present =====
        # Look for tracking number patterns
        tracking_patterns = [
            'fdx7723891', 'trk9384756', '9400123456', 
            'tba9876543', 'fdx8829341'
        ]
        # Also look for carriers
        carrier_keywords = ['fedex', 'ups', 'usps', 'amazon']
        
        tracking_found = sum(1 for pattern in tracking_patterns if pattern in all_text_lower)
        carriers_found = sum(1 for carrier in carrier_keywords if carrier in all_text_lower)
        
        if tracking_found >= 4 or carriers_found >= 3:
            feedback_parts.append(f"✅ Tracking info included ({tracking_found} tracking #s, {carriers_found} carriers)")
            criteria_passed += 1
        elif tracking_found >= 2 or carriers_found >= 2:
            feedback_parts.append(f"⚠️ Some tracking info present")
            criteria_passed += 0.5
        else:
            feedback_parts.append(f"❌ Tracking numbers not clearly visible")
        
        # ===== Criterion 5: Refund amounts documented =====
        # Expected amounts: 289, 245, 67, 124, 43
        expected_amounts = [289, 245, 67, 124, 43]
        
        # Look for values close to expected amounts
        found_amounts = []
        for expected in expected_amounts:
            for value in numeric_values:
                if abs(value - expected) <= 2:  # Allow small tolerance
                    found_amounts.append(expected)
                    break
        
        if len(found_amounts) >= 4:
            feedback_parts.append(f"✅ Refund amounts documented ({len(found_amounts)}/5 values found)")
            criteria_passed += 1
        elif len(found_amounts) >= 3:
            feedback_parts.append(f"⚠️ Most refund amounts present ({len(found_amounts)}/5)")
            criteria_passed += 0.5
        else:
            feedback_parts.append(f"❌ Refund amounts incomplete ({len(found_amounts)}/5)")
        
        # ===== Criterion 6: Total refund calculation =====
        # Expected total: 289 + 245 + 67 + 124 + 43 = 768
        expected_total_range = (650, 850)  # Allow some variation
        
        # Look for values in the expected range
        potential_totals = [v for v in numeric_values 
                           if expected_total_range[0] <= v <= expected_total_range[1]]
        
        # Also check for SUM formulas in the sheet
        has_sum_formula = False
        for row_idx in range(1, min(len(data) + 1, 30)):
            for col_idx in range(1, 16):
                try:
                    cell = sheet.cell(row=row_idx, column=col_idx)
                    if cell.value and isinstance(cell.value, str):
                        if 'SUM' in str(cell.value).upper():
                            has_sum_formula = True
                            break
                except:
                    pass
            if has_sum_formula:
                break
        
        if potential_totals:
            closest_total = min(potential_totals, key=lambda x: abs(x - 768))
            feedback_parts.append(f"✅ Total refund calculated (~${closest_total:.0f})")
            criteria_passed += 1
        elif has_sum_formula:
            feedback_parts.append(f"✅ SUM formula detected (total may be correct)")
            criteria_passed += 0.7
        else:
            feedback_parts.append(f"⚠️ Total refund calculation not clearly visible")
            criteria_passed += 0.3
        
        # ===== Criterion 7: Priority/urgency flagging =====
        urgency_keywords = ['urgent', 'priority', 'high', 'critical', 'flag', 'important']
        has_urgency = any(keyword in all_text_lower for keyword in urgency_keywords)
        
        # Also look for conditional formatting or special markers
        has_markers = any(marker in all_text_lower for marker in ['!!!', '***', 'yes', 'no'])
        
        if has_urgency:
            feedback_parts.append("✅ Priority flagging system present")
            criteria_passed += 1
        elif has_markers:
            feedback_parts.append("⚠️ Some priority indicators present")
            criteria_passed += 0.5
        else:
            feedback_parts.append("⚠️ Priority flags not clearly marked")
            criteria_passed += 0.3
        
        # ===== Criterion 8: Evidence tracking columns =====
        evidence_keywords = ['photo', 'screenshot', 'contacted', 'evidence', 'proof']
        evidence_count = sum(1 for kw in evidence_keywords if kw in all_text_lower)
        
        # Also check for yes/no values which indicate checklist
        has_checklist = ('yes' in all_text_lower or 'no' in all_text_lower or 
                        '✓' in all_text_lower or '✗' in all_text_lower)
        
        if evidence_count >= 2 and has_checklist:
            feedback_parts.append(f"✅ Evidence tracking columns included")
            criteria_passed += 1
        elif evidence_count >= 2 or has_checklist:
            feedback_parts.append(f"⚠️ Some evidence tracking present")
            criteria_passed += 0.5
        else:
            feedback_parts.append(f"⚠️ Evidence tracking incomplete")
            criteria_passed += 0.3
        
        # Calculate final score
        score = min((criteria_passed / total_criteria) * 100, 100.0)
        passed = score >= 70.0
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": round(score, 1),
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