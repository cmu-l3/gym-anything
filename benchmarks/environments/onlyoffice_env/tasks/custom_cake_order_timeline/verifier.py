#!/usr/bin/env python3
"""
Verifier for Custom Cake Order Timeline task

Verifies that a home baker has created a realistic production timeline
for three simultaneous cake orders with a single-oven constraint.
"""

import sys
import os
import logging
import tempfile
from typing import List, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_timeline_sheet(workbook) -> Optional[Tuple[str, any]]:
    """
    Find the timeline/production schedule sheet in the workbook.
    
    Returns:
        Tuple of (sheet_name, sheet_object) or None if not found
    """
    # Keywords that indicate a timeline sheet
    timeline_keywords = [
        'timeline', 'production', 'schedule', 'plan', 'calendar'
    ]
    
    for sheet_name in workbook.sheetnames:
        sheet_name_lower = sheet_name.lower()
        for keyword in timeline_keywords:
            if keyword in sheet_name_lower:
                return (sheet_name, workbook[sheet_name])
    
    # If no keyword match, look for sheets that aren't "Order Details"
    for sheet_name in workbook.sheetnames:
        if sheet_name.lower() not in ['order details', 'sheet1', 'sheet']:
            # Check if it has time-based content
            sheet = workbook[sheet_name]
            if sheet.max_row >= 10:  # Should have substantial content
                return (sheet_name, sheet)
    
    return None


def extract_sheet_text(sheet, max_rows: int = 100, max_cols: int = 10) -> List[str]:
    """
    Extract all text from a sheet as list of strings (one per row).
    
    Args:
        sheet: Worksheet object
        max_rows: Maximum rows to read
        max_cols: Maximum columns to read
        
    Returns:
        List of strings, one per row
    """
    text_rows = []
    
    for row_idx in range(1, min(max_rows + 1, sheet.max_row + 1)):
        row_text = []
        for col_idx in range(1, min(max_cols + 1, sheet.max_column + 1)):
            cell_value = sheet.cell(row=row_idx, column=col_idx).value
            if cell_value is not None:
                row_text.append(str(cell_value).lower())
        
        if row_text:  # Only add non-empty rows
            text_rows.append(" ".join(row_text))
    
    return text_rows


def check_logical_sequencing(text_rows: List[str]) -> Tuple[bool, str]:
    """
    Check if baking comes before cooling/decorating in the timeline.
    
    Returns:
        Tuple of (is_valid, feedback_message)
    """
    baking_rows = [i for i, line in enumerate(text_rows) if 'bak' in line]
    cooling_rows = [i for i, line in enumerate(text_rows) if 'cool' in line]
    decorating_rows = [i for i, line in enumerate(text_rows) if any(word in line for word in ['decorat', 'frost', 'assembl'])]
    
    # Need at least some of each
    if len(baking_rows) < 2:
        return False, f"Too few baking tasks found ({len(baking_rows)})"
    
    if len(decorating_rows) < 2:
        return False, f"Too few decorating tasks found ({len(decorating_rows)})"
    
    # Check if baking generally comes before decorating
    if baking_rows and decorating_rows:
        avg_baking_pos = sum(baking_rows) / len(baking_rows)
        avg_decorating_pos = sum(decorating_rows) / len(decorating_rows)
        
        if avg_baking_pos > avg_decorating_pos:
            return False, "Baking tasks appear AFTER decorating (timeline backwards)"
    
    return True, f"Valid sequencing: {len(baking_rows)} baking, {len(cooling_rows)} cooling, {len(decorating_rows)} decorating tasks"


def check_order_coverage(text_rows: List[str]) -> Tuple[int, str]:
    """
    Check if all three orders (A, B, C) or (Wedding, Graduation, Cupcakes) are mentioned.
    
    Returns:
        Tuple of (num_orders_found, feedback_message)
    """
    full_text = " ".join(text_rows)
    
    orders_found = 0
    order_details = []
    
    # Check for Order A / Wedding
    if 'order a' in full_text or 'wedding' in full_text or 'tier' in full_text:
        orders_found += 1
        order_details.append("Wedding/A")
    
    # Check for Order B / Graduation
    if 'order b' in full_text or 'graduation' in full_text:
        orders_found += 1
        order_details.append("Graduation/B")
    
    # Check for Order C / Cupcakes / Birthday
    if 'order c' in full_text or 'cupcake' in full_text or 'birthday' in full_text:
        orders_found += 1
        order_details.append("Cupcakes/C")
    
    if orders_found == 3:
        feedback = f"All 3 orders present: {', '.join(order_details)}"
    else:
        feedback = f"Only {orders_found}/3 orders found: {', '.join(order_details) if order_details else 'none'}"
    
    return orders_found, feedback


def check_time_references(text_rows: List[str]) -> Tuple[bool, str]:
    """
    Check if timeline has adequate time references (days, hours, AM/PM).
    
    Returns:
        Tuple of (has_adequate_timing, feedback_message)
    """
    full_text = " ".join(text_rows)
    
    time_indicators = {
        'days': ['thursday', 'friday', 'saturday'],
        'times': ['am', 'pm', ':00', 'hour', 'hr', 'min'],
    }
    
    day_count = sum(1 for day in time_indicators['days'] if day in full_text)
    time_count = sum(1 for time_word in time_indicators['times'] if time_word in full_text)
    
    # Should mention days multiple times and have many time references
    has_adequate = day_count >= 5 and time_count >= 15
    
    feedback = f"Time references: {day_count} day mentions, {time_count} time indicators"
    
    return has_adequate, feedback


def check_timeline_detail(text_rows: List[str]) -> Tuple[bool, str]:
    """
    Check if timeline has sufficient detail (enough task entries).
    
    Returns:
        Tuple of (has_adequate_detail, feedback_message)
    """
    # Filter to substantial rows (more than just a few words)
    substantial_rows = [row for row in text_rows if len(row) > 15]
    
    # Should have at least 20-25 task entries for 3-day timeline
    has_adequate = len(substantial_rows) >= 20
    
    feedback = f"Timeline detail: {len(substantial_rows)} substantive entries"
    
    return has_adequate, feedback


def check_oven_conflict_awareness(text_rows: List[str]) -> Tuple[bool, str]:
    """
    Check if timeline shows awareness of oven constraints.
    Look for multiple distinct baking tasks scheduled.
    
    Returns:
        Tuple of (shows_awareness, feedback_message)
    """
    full_text = " ".join(text_rows)
    
    # Look for different baking tasks
    has_graduation_bake = ('graduation' in full_text and 'bak' in full_text) or \
                          ('order b' in full_text and 'bak' in full_text)
    has_wedding_bake = (('wedding' in full_text or 'tier' in full_text) and 'bak' in full_text) or \
                       ('order a' in full_text and 'bak' in full_text)
    has_cupcake_bake = (('cupcake' in full_text or 'birthday' in full_text) and 'bak' in full_text) or \
                       ('order c' in full_text and 'bak' in full_text)
    
    distinct_baking_tasks = sum([has_graduation_bake, has_wedding_bake, has_cupcake_bake])
    
    # Additional check: look for "oven" mentions or conflict awareness
    mentions_oven = 'oven' in full_text
    mentions_conflict = any(word in full_text for word in ['busy', 'free', 'available', 'conflict'])
    
    shows_awareness = distinct_baking_tasks >= 2  # At least 2 different bakes scheduled
    
    feedback_parts = [f"{distinct_baking_tasks}/3 baking tasks scheduled"]
    if mentions_oven:
        feedback_parts.append("mentions oven")
    if mentions_conflict:
        feedback_parts.append("shows conflict awareness")
    
    feedback = "Oven awareness: " + ", ".join(feedback_parts)
    
    return shows_awareness, feedback


def check_deadline_awareness(text_rows: List[str]) -> Tuple[bool, str]:
    """
    Check if timeline mentions the critical deadlines (Saturday, 11 AM, 2 PM, 4 PM).
    
    Returns:
        Tuple of (shows_deadline_awareness, feedback_message)
    """
    full_text = " ".join(text_rows)
    
    has_saturday = 'saturday' in full_text
    has_morning_deadline = '11' in full_text or 'eleven' in full_text
    has_afternoon_deadlines = '2' in full_text or '4' in full_text or 'pm' in full_text
    
    mentions_deadline = any(word in full_text for word in ['deadline', 'delivery', 'pickup', 'due', 'finish'])
    
    shows_awareness = has_saturday and (has_morning_deadline or has_afternoon_deadlines)
    
    feedback_parts = []
    if has_saturday:
        feedback_parts.append("Saturday mentioned")
    if has_morning_deadline:
        feedback_parts.append("11 AM deadline")
    if mentions_deadline:
        feedback_parts.append("deadline language")
    
    feedback = "Deadline awareness: " + ", ".join(feedback_parts) if feedback_parts else "No clear deadline references"
    
    return shows_awareness, feedback


def verify_custom_cake_timeline(traj, env_info, task_info):
    """
    Verify that custom cake order production timeline was created correctly.
    
    Scoring criteria (7 total):
    1. File exists and is valid XLSX
    2. Timeline sheet exists (not just order details)
    3. Logical sequencing (baking → cooling → decorating)
    4. All three orders present in timeline
    5. Adequate time references (days, hours)
    6. Oven constraint awareness (multiple bakes scheduled)
    7. Sufficient timeline detail (25+ entries)
    
    Pass threshold: 70% (5/7 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Try both possible filenames
    container_paths = [
        "/home/ga/Documents/Spreadsheets/CakeOrders_ProductionTimeline.xlsx",
        "/home/ga/Documents/Spreadsheets/CakeOrders_RawInfo.xlsx"
    ]
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_cake_')
    
    workbook = None
    found_path = None
    
    try:
        # Try to find and load the spreadsheet
        for container_path in container_paths:
            success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
            if success:
                workbook = wb
                found_path = container_path
                break
        
        if not workbook:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Spreadsheet not found or invalid at expected locations"
            }
        
        # Criterion 1: File exists and is valid ✅
        criteria_passed = 1
        feedback_parts = ["✅ Spreadsheet file valid"]
        max_criteria = 7
        
        # Criterion 2: Find timeline sheet (not just order details)
        timeline_info = find_timeline_sheet(workbook)
        
        if timeline_info is None:
            feedback_parts.append("❌ No timeline sheet found (only order details sheet present)")
            return {
                "passed": False,
                "score": int((criteria_passed / max_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        sheet_name, timeline_sheet = timeline_info
        criteria_passed += 1
        feedback_parts.append(f"✅ Timeline sheet found: '{sheet_name}'")
        
        # Extract text from timeline sheet
        text_rows = extract_sheet_text(timeline_sheet, max_rows=100, max_cols=10)
        
        if len(text_rows) < 10:
            feedback_parts.append(f"❌ Timeline sheet too sparse ({len(text_rows)} rows)")
            return {
                "passed": False,
                "score": int((criteria_passed / max_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 3: Logical sequencing
        is_logical, seq_feedback = check_logical_sequencing(text_rows)
        if is_logical:
            criteria_passed += 1
            feedback_parts.append(f"✅ {seq_feedback}")
        else:
            feedback_parts.append(f"❌ Sequencing issue: {seq_feedback}")
        
        # Criterion 4: All three orders present
        orders_found, order_feedback = check_order_coverage(text_rows)
        if orders_found == 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ {order_feedback}")
        else:
            feedback_parts.append(f"❌ {order_feedback}")
        
        # Criterion 5: Adequate time references
        has_time_refs, time_feedback = check_time_references(text_rows)
        if has_time_refs:
            criteria_passed += 1
            feedback_parts.append(f"✅ {time_feedback}")
        else:
            feedback_parts.append(f"⚠️ {time_feedback}")
        
        # Criterion 6: Oven constraint awareness
        oven_aware, oven_feedback = check_oven_conflict_awareness(text_rows)
        if oven_aware:
            criteria_passed += 1
            feedback_parts.append(f"✅ {oven_feedback}")
        else:
            feedback_parts.append(f"❌ {oven_feedback}")
        
        # Criterion 7: Timeline detail
        has_detail, detail_feedback = check_timeline_detail(text_rows)
        if has_detail:
            criteria_passed += 1
            feedback_parts.append(f"✅ {detail_feedback}")
        else:
            feedback_parts.append(f"⚠️ {detail_feedback}")
        
        # Calculate final score
        percentage_score = (criteria_passed / max_criteria) * 100
        passed = percentage_score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": round(percentage_score, 1),
            "feedback": f"Score: {criteria_passed}/{max_criteria} | {feedback}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
