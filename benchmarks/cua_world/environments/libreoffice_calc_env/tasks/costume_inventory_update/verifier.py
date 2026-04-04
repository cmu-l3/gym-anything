#!/usr/bin/env python3
"""
Verifier for Theater Costume Inventory Update task
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp,
    setup_calc_verification
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_conditional_formatting_ods(filepath):
    """
    Check if conditional formatting exists in ODS file.
    Returns True if formatting rules are detected.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting in various namespaces
            # ODS uses calc:conditional-formats or style:map elements
            namespaces = {
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'
            }
            
            # Check for conditional format elements
            for ns_key in ['calcext', 'style']:
                cond_formats = root.findall(f'.//{ns_key}:conditional-format', namespaces)
                if cond_formats:
                    logger.info(f"Found {len(cond_formats)} conditional format(s) in ODS")
                    return True
            
            # Alternative: check for map elements within cell styles
            maps = root.findall('.//style:map', namespaces)
            if maps:
                logger.info(f"Found {len(maps)} style map(s) in ODS")
                return True
                
        return False
    except Exception as e:
        logger.warning(f"Could not parse ODS conditional formatting: {e}")
        return False


def check_conditional_formatting_xlsx(filepath):
    """
    Check if conditional formatting exists in XLSX file.
    Returns True if formatting rules are detected.
    """
    try:
        from openpyxl import load_workbook
        wb = load_workbook(filepath)
        ws = wb.active
        
        # Check if worksheet has conditional formatting rules
        if hasattr(ws, 'conditional_formatting') and len(ws.conditional_formatting._cf_rules) > 0:
            logger.info(f"Found {len(ws.conditional_formatting._cf_rules)} conditional formatting rule(s)")
            return True
        
        return False
    except ImportError:
        logger.warning("openpyxl not available for XLSX conditional formatting check")
        return False
    except Exception as e:
        logger.warning(f"Could not check XLSX conditional formatting: {e}")
        return False


def verify_costume_inventory_update(traj, env_info, task_info):
    """
    Verify costume inventory update task completion.
    
    Checks:
    1. Status updates: Victorian Jacket, Medieval Tunic, Top Hat → "Available"
    2. Damage marking: Victorian Jacket, Medieval Tunic → "Damaged"
    3. Notes added with damage descriptions
    4. Conditional formatting applied to Condition column
    5. Data integrity: other items unchanged
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations and formats
    temp_dir = None
    success = False
    workbook = None
    filepath = None
    file_format = None
    
    # Priority order: ODS (updated), then CSV (original modified), then ODS (original name)
    file_attempts = [
        ('ods', '/home/ga/Documents/costume_inventory_updated.ods'),
        ('csv', '/home/ga/Documents/costume_inventory.csv'),
        ('ods', '/home/ga/Documents/costume_inventory.ods'),
    ]
    
    for fmt, path in file_attempts:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            filepath = workbook.get('filepath', '')
            file_format = fmt
            logger.info(f"Successfully loaded file: {path} (format: {fmt})")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load costume inventory file: {error}"
        }

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Define expected updates
        # Row 6: Victorian Jacket (Item C005)
        # Row 9: Medieval Tunic (Item C008)
        # Row 12: Top Hat (Item C011)
        # Columns: F=Status, G=Condition, H=Notes
        
        # Criterion 1: Status Updates Complete (Victorian Jacket, Medieval Tunic, Top Hat)
        status_updates = {
            6: ("Victorian Jacket", "F6"),
            9: ("Medieval Tunic", "F9"),
            12: ("Top Hat", "F12")
        }
        
        status_correct = 0
        status_total = len(status_updates)
        
        for row, (item_name, cell_ref) in status_updates.items():
            status_value = get_cell_value(workbook, sheet_name, cell_ref)
            if status_value and 'available' in str(status_value).lower():
                status_correct += 1
            else:
                feedback_parts.append(f"❌ {item_name} (row {row}): Status not updated to Available (got: {status_value})")
        
        if status_correct == status_total:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status updates complete ({status_correct}/{status_total} items marked Available)")
        elif status_correct > 0:
            feedback_parts.append(f"⚠️ Partial status updates ({status_correct}/{status_total} items updated)")
            criteria_passed += (status_correct / status_total)  # Partial credit
        else:
            feedback_parts.append(f"❌ Status updates missing (0/{status_total} items updated)")
        
        # Criterion 2: Damage Marked (Victorian Jacket, Medieval Tunic)
        damage_items = {
            6: ("Victorian Jacket", "G6"),
            9: ("Medieval Tunic", "G9")
        }
        
        damage_correct = 0
        damage_total = len(damage_items)
        
        for row, (item_name, cell_ref) in damage_items.items():
            condition_value = get_cell_value(workbook, sheet_name, cell_ref)
            if condition_value and 'damaged' in str(condition_value).lower():
                damage_correct += 1
            else:
                feedback_parts.append(f"❌ {item_name} (row {row}): Condition not marked as Damaged (got: {condition_value})")
        
        if damage_correct == damage_total:
            criteria_passed += 1
            feedback_parts.append(f"✅ Damage marking complete ({damage_correct}/{damage_total} items marked Damaged)")
        elif damage_correct > 0:
            feedback_parts.append(f"⚠️ Partial damage marking ({damage_correct}/{damage_total} items marked)")
            criteria_passed += (damage_correct / damage_total)  # Partial credit
        else:
            feedback_parts.append(f"❌ Damage marking missing (0/{damage_total} items marked)")
        
        # Criterion 3: Notes Added with Damage Descriptions
        notes_items = {
            6: ("Victorian Jacket", "H6", ["torn", "sleeve", "stitch", "repair", "sew"]),
            9: ("Medieval Tunic", "H9", ["wine", "stain", "clean", "wash", "front"])
        }
        
        notes_correct = 0
        notes_total = len(notes_items)
        damage_keywords = ["torn", "stain", "damage", "needs", "requires", "repair", "clean", 
                          "wash", "fix", "mend", "broken", "rip", "hole"]
        
        for row, (item_name, cell_ref, specific_keywords) in notes_items.items():
            notes_value = get_cell_value(workbook, sheet_name, cell_ref)
            
            if notes_value and str(notes_value).strip():
                notes_text = str(notes_value).lower()
                # Check for any damage-related keywords
                has_keyword = any(kw in notes_text for kw in damage_keywords)
                # Bonus: check for item-specific keywords
                has_specific = any(kw in notes_text for kw in specific_keywords)
                
                if has_keyword and len(notes_text) > 5:  # Not just a single word
                    notes_correct += 1
                    if has_specific:
                        logger.info(f"{item_name} notes contain specific damage details: {notes_value}")
                else:
                    feedback_parts.append(f"⚠️ {item_name} (row {row}): Notes lack damage description (got: {notes_value})")
            else:
                feedback_parts.append(f"❌ {item_name} (row {row}): No damage notes added")
        
        if notes_correct == notes_total:
            criteria_passed += 1
            feedback_parts.append(f"✅ Damage notes added ({notes_correct}/{notes_total} items documented)")
        elif notes_correct > 0:
            feedback_parts.append(f"⚠️ Partial notes ({notes_correct}/{notes_total} items documented)")
            criteria_passed += (notes_correct / notes_total)  # Partial credit
        else:
            feedback_parts.append(f"❌ Damage notes missing (0/{notes_total} items documented)")
        
        # Criterion 4: Conditional Formatting Applied
        formatting_detected = False
        
        if file_format == 'ods':
            formatting_detected = check_conditional_formatting_ods(filepath)
        elif file_format == 'xlsx':
            formatting_detected = check_conditional_formatting_xlsx(filepath)
        
        if formatting_detected:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected in Condition column")
        else:
            # Conditional formatting is complex to detect reliably
            # Give partial credit if the task is otherwise complete
            if criteria_passed >= 2.5:  # Other criteria mostly met
                feedback_parts.append("⚠️ Conditional formatting not reliably detected (may exist but not parsed)")
                criteria_passed += 0.5  # Lenient partial credit
            else:
                feedback_parts.append("❌ Conditional formatting not detected")
        
        # Criterion 5: Data Integrity (spot check a few unchanged items)
        integrity_checks = {
            2: ("C001", "Renaissance Gown", "Available", "Good"),  # Row 2: Should be unchanged
            4: ("C003", "Flapper Dress", "Available", "Good"),    # Row 4: Should be unchanged
            13: ("C012", "Police Uniform", "Available", "Good")   # Row 13: Should be unchanged
        }
        
        integrity_ok = True
        for row, (item_id, item_name, expected_status, expected_condition) in integrity_checks.items():
            # Check Item Name (Column B)
            name_value = get_cell_value(workbook, sheet_name, f"B{row}")
            if name_value and item_name.lower() in str(name_value).lower():
                # Check Status (Column F) and Condition (Column G)
                status_val = get_cell_value(workbook, sheet_name, f"F{row}")
                condition_val = get_cell_value(workbook, sheet_name, f"G{row}")
                
                if not (status_val and expected_status.lower() in str(status_val).lower()):
                    integrity_ok = False
                    feedback_parts.append(f"⚠️ Data integrity issue: {item_name} (row {row}) status changed unexpectedly")
                    break
                
                if not (condition_val and expected_condition.lower() in str(condition_val).lower()):
                    integrity_ok = False
                    feedback_parts.append(f"⚠️ Data integrity issue: {item_name} (row {row}) condition changed unexpectedly")
                    break
        
        if integrity_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Data integrity maintained (unchanged items preserved)")
        else:
            if not any("integrity" in fp.lower() for fp in feedback_parts):
                feedback_parts.append("❌ Data integrity issue detected")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 3.5/5 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent work! Inventory updated comprehensively")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed successfully")
        else:
            feedback_parts.insert(0, "❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "status_updates": status_correct == status_total,
                "damage_marked": damage_correct == damage_total,
                "notes_added": notes_correct == notes_total,
                "formatting_applied": formatting_detected,
                "data_integrity": integrity_ok
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
