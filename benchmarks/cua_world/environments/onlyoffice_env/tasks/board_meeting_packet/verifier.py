#!/usr/bin/env python3
"""
Verifier for board_meeting_packet@1 task
Checks that the board packet is properly formatted with all required sections
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    check_text_formatting,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_board_meeting_packet(traj, env_info, task_info):
    """
    Verify that the board meeting packet is properly formatted
    
    Checks:
    1. Cover page elements present (organization, date, time, location)
    2. Agenda section with numbered items
    3. Meeting minutes formatted from raw notes
    4. Treasurer's report with table and financial data
    5. Action items section with table and status information
    
    Returns:
        dict with keys: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/BoardMeeting/December_Board_Packet.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_board_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        criteria_passed = 0
        max_criteria = 10
        feedback_parts = []

        # Extract full text for content checking
        full_text = get_document_text(doc).lower()

        # Criterion 1: Cover page elements (2 points)
        cover_elements = {
            'org_name': "riverside community food pantry" in full_text,
            'packet_title': "board meeting packet" in full_text,
            'meeting_date': ("december 15, 2024" in full_text or "december 15" in full_text),
            'meeting_time': ("6:00 pm" in full_text or "6:00pm" in full_text or "6 pm" in full_text),
            'location': ("community center" in full_text and "room 3b" in full_text)
        }
        
        cover_score = sum(cover_elements.values())
        if cover_score >= 4:
            criteria_passed += 2
            feedback_parts.append(f"✅ Cover page: {cover_score}/5 elements present")
        elif cover_score >= 2:
            criteria_passed += 1
            feedback_parts.append(f"⚠️ Cover page: {cover_score}/5 elements present (incomplete)")
        else:
            feedback_parts.append(f"❌ Cover page: {cover_score}/5 elements present (missing)")

        # Criterion 2: Agenda section (1.5 points)
        has_agenda_header = "agenda" in full_text
        agenda_items = [
            "call to order" in full_text,
            "treasurer" in full_text,
            ("old business" in full_text or "freezer" in full_text),
            ("new business" in full_text or "grant" in full_text),
            "adjournment" in full_text
        ]
        agenda_score = sum(agenda_items)
        
        if has_agenda_header and agenda_score >= 4:
            criteria_passed += 1.5
            feedback_parts.append(f"✅ Agenda section: {agenda_score}/5 items present")
        elif has_agenda_header and agenda_score >= 2:
            criteria_passed += 0.75
            feedback_parts.append(f"⚠️ Agenda section: {agenda_score}/5 items present (incomplete)")
        else:
            feedback_parts.append(f"❌ Agenda section: missing or incomplete")

        # Criterion 3: Meeting minutes formatted (2.5 points)
        has_minutes_header = "minutes" in full_text and "september" in full_text
        
        minutes_elements = {
            'attendees_section': ("present" in full_text or "attendees" in full_text or "attendance" in full_text),
            'maria': "maria" in full_text,
            'john': "john" in full_text,
            'freezer_discussion': "freezer" in full_text,
            'volunteer_discussion': "volunteer" in full_text,
            'lease_discussion': ("lease" in full_text or "landlord" in full_text)
        }
        
        minutes_score = sum(minutes_elements.values())
        
        if has_minutes_header and minutes_score >= 5:
            criteria_passed += 2.5
            feedback_parts.append(f"✅ Meeting minutes: properly formatted ({minutes_score}/6 elements)")
        elif has_minutes_header and minutes_score >= 3:
            criteria_passed += 1.5
            feedback_parts.append(f"⚠️ Meeting minutes: present but incomplete ({minutes_score}/6 elements)")
        elif has_minutes_header:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Meeting minutes: header present but minimal content")
        else:
            feedback_parts.append(f"❌ Meeting minutes: missing")

        # Criterion 4: Treasurer's report with table (2.5 points)
        has_treasurer_header = "treasurer" in full_text and ("report" in full_text or "q4" in full_text)
        num_tables = count_tables(doc)
        
        # Check for financial data (with and without commas/spaces)
        text_normalized = full_text.replace(",", "").replace(" ", "")
        
        financial_elements = {
            'income_q4': ("15200" in text_normalized or "15,200" in full_text),
            'expenses': "expense" in full_text,
            'food_purchases': ("9350" in text_normalized or "9,350" in full_text or "food" in full_text),
            'rent_data': ("2400" in text_normalized or "2,400" in full_text),
            'has_table': num_tables >= 1
        }
        
        treasurer_score = sum(financial_elements.values())
        
        if has_treasurer_header and treasurer_score >= 4:
            criteria_passed += 2.5
            feedback_parts.append(f"✅ Treasurer's report: table with financial data ({treasurer_score}/5 elements)")
        elif has_treasurer_header and treasurer_score >= 2:
            criteria_passed += 1.5
            feedback_parts.append(f"⚠️ Treasurer's report: present but incomplete ({treasurer_score}/5 elements)")
        elif has_treasurer_header:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Treasurer's report: header present but minimal content")
        else:
            feedback_parts.append(f"❌ Treasurer's report: missing")

        # Criterion 5: Action items table (1.5 points)
        has_action_header = "action item" in full_text or "action" in full_text
        
        action_elements = {
            'status_mentions': ("completed" in full_text or "status" in full_text or "progress" in full_text),
            'freezer_item': "freezer" in full_text and "michael" in full_text,
            'lease_item': ("landlord" in full_text or "lease" in full_text) and "john" in full_text,
            'holiday_item': ("holiday" in full_text or "food drive" in full_text) and "linda" in full_text,
            'multiple_items': full_text.count("completed") >= 1 or full_text.count("progress") >= 1
        }
        
        action_score = sum(action_elements.values())
        
        if has_action_header and action_score >= 4:
            criteria_passed += 1.5
            feedback_parts.append(f"✅ Action items: organized with updates ({action_score}/5 elements)")
        elif has_action_header and action_score >= 2:
            criteria_passed += 0.75
            feedback_parts.append(f"⚠️ Action items: present but incomplete ({action_score}/5 elements)")
        elif has_action_header:
            criteria_passed += 0.25
            feedback_parts.append(f"⚠️ Action items: header present but minimal content")
        else:
            feedback_parts.append(f"❌ Action items: missing")

        # Calculate final score and pass/fail
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 70  # Need 70% to pass

        # Add summary at the beginning
        summary = f"Score: {criteria_passed:.1f}/{max_criteria} ({score}%) | Tables: {num_tables}"
        feedback_parts.insert(0, summary)

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)