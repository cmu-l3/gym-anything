#!/usr/bin/env python3
"""
Verifier for Repair Café Intake Form task

Checks that messy repair notes have been converted into a standardized,
professionally formatted intake form document.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_paragraphs,
    check_text_formatting,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_repair_intake_form(traj, env_info, task_info):
    """
    Verify that repair café intake form was created correctly.

    Checks:
    1. File valid - DOCX exists, readable, appropriate size
    2. Structure present - Title + 5 repair entries with headers
    3. Formatting consistent - Bold headers, labeled fields
    4. Content complete - All 5 repairs documented with required fields
    5. Professional quality - Cleaned up language, proper organization
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/repair_intake_formatted.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_repair_')

    try:
        # Copy and parse the formatted document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load formatted document: {error}"}

        criteria_met = 0
        feedback_parts = []

        # Get full document text and paragraph count
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        para_count = count_paragraphs(doc)

        logger.info(f"Document has {para_count} paragraphs and {len(full_text)} characters")

        # ===================================================================
        # CRITERION 1: File Valid (basic check - already passed if we got here)
        # ===================================================================
        if len(full_text) >= 500:  # Should have substantial content
            criteria_met += 1
            feedback_parts.append(f"✅ File valid and readable ({len(full_text)} chars)")
        else:
            feedback_parts.append(f"❌ File too small ({len(full_text)} chars, expected >500)")

        # ===================================================================
        # CRITERION 2: Structure Present (Title + 5 entries)
        # ===================================================================
        
        # Check for title/header about repair café or intake forms
        has_title = any(word in full_text_lower for word in [
            'repair café', 'repair cafe', 'intake form', 'repair form'
        ])
        
        # Check for 5 repair entries - look for various patterns
        repair_patterns = [
            r'repair\s*#?\s*[1-5]',  # "repair #1", "repair 1", etc.
            r'entry\s*#?\s*[1-5]',   # "entry #1", etc.
            r'item\s*#?\s*[1-5]'     # "item #1", etc.
        ]
        
        repair_count = 0
        for pattern in repair_patterns:
            matches = re.findall(pattern, full_text_lower)
            repair_count = max(repair_count, len(matches))
        
        has_five_entries = repair_count >= 5
        
        # Check for reasonable structure (enough paragraphs for organized content)
        sufficient_structure = para_count >= 30  # Should have many paragraphs for structured data
        
        if has_title and has_five_entries and sufficient_structure:
            criteria_met += 1
            feedback_parts.append(f"✅ Structure present (title: yes, entries: {repair_count}, paras: {para_count})")
        else:
            issues = []
            if not has_title:
                issues.append("no title")
            if not has_five_entries:
                issues.append(f"only {repair_count} entries found")
            if not sufficient_structure:
                issues.append(f"only {para_count} paragraphs")
            feedback_parts.append(f"❌ Structure incomplete ({', '.join(issues)})")

        # ===================================================================
        # CRITERION 3: Formatting Consistent (Bold headers + field labels)
        # ===================================================================
        
        # Check for bold repair headers
        has_bold_headers = False
        for i in range(1, 6):
            # Try various header formats
            if (check_text_formatting(doc, f'repair #{i}', bold=True) or
                check_text_formatting(doc, f'repair {i}', bold=True) or
                check_text_formatting(doc, f'entry #{i}', bold=True) or
                check_text_formatting(doc, f'item #{i}', bold=True)):
                has_bold_headers = True
                break
        
        # Check for required field labels (at least 4 of them present)
        required_labels = [
            'date', 'item', 'problem', 'outcome', 'volunteer', 
            'diagnosis', 'parts', 'time', 'customer'
        ]
        labels_present = sum(1 for label in required_labels if label in full_text_lower)
        
        # Check if at least some labels are bold (sampling approach)
        labels_bold_count = 0
        for label in ['date:', 'item type:', 'problem:', 'outcome:', 'volunteer:']:
            if check_text_formatting(doc, label, bold=True):
                labels_bold_count += 1
        
        has_bold_labels = labels_bold_count >= 2  # At least 2 labels should be bold
        
        if has_bold_headers and labels_present >= 6 and has_bold_labels:
            criteria_met += 1
            feedback_parts.append(f"✅ Consistent formatting (headers bold: yes, labels: {labels_present}/9, bold labels: {labels_bold_count})")
        else:
            issues = []
            if not has_bold_headers:
                issues.append("headers not bold")
            if labels_present < 6:
                issues.append(f"only {labels_present} labels")
            if not has_bold_labels:
                issues.append("labels not bold")
            feedback_parts.append(f"❌ Inconsistent formatting ({', '.join(issues)})")

        # ===================================================================
        # CRITERION 4: Content Complete (All 5 repairs with key info)
        # ===================================================================
        
        # Check for items from source notes
        expected_items = ['toaster', 'laptop', 'lamp', 'blender', 'iphone', 'phone']
        items_found = sum(1 for item in expected_items if item in full_text_lower)
        
        # Check for outcome keywords
        outcome_words = ['fixed', 'not fixable', 'partial', 'success', 'replaced', 'repaired']
        outcomes_found = sum(1 for word in outcome_words if word in full_text_lower)
        
        # Check for volunteer/customer names
        has_names = any(name in full_text_lower for name in [
            'mike', 'alex', 'jessica', 'raj', 'sam', 'sarah', 'rodriguez', 'jenny'
        ])
        
        # Check for dates or months
        has_dates = any(date in full_text_lower for date in ['march', 'mar', '2024', '15', '16', '17'])
        
        content_complete = (items_found >= 3 and outcomes_found >= 2 and 
                          has_names and has_dates)
        
        if content_complete:
            criteria_met += 1
            feedback_parts.append(f"✅ Content complete (items: {items_found}, outcomes: {outcomes_found}, names: yes, dates: yes)")
        else:
            feedback_parts.append(f"❌ Content incomplete (items: {items_found}, outcomes: {outcomes_found}, names: {has_names}, dates: {has_dates})")

        # ===================================================================
        # CRITERION 5: Professional Quality (No messy language, good structure)
        # ===================================================================
        
        # Check for unprofessional/messy words that should have been cleaned up
        messy_words = ['idk', 'probs', 'dunno', 'lol', 'idc']
        has_messy = any(word in full_text_lower for word in messy_words)
        
        # Check for reasonable document length (should be substantial)
        has_reasonable_length = len(full_text) >= 800  # Should have detailed info
        
        # Check for good paragraph structure
        has_good_structure = para_count >= 35  # Well-structured doc has many paragraphs
        
        # Check that it's not just the original messy doc (look for standardization markers)
        has_standardization = (
            full_text_lower.count(':') >= 30 or  # Many field labels with colons
            'customer name' in full_text_lower or
            'problem description' in full_text_lower or
            'volunteer name' in full_text_lower
        )
        
        is_professional = (not has_messy and has_reasonable_length and 
                          has_good_structure and has_standardization)
        
        if is_professional:
            criteria_met += 1
            feedback_parts.append(f"✅ Professional quality (clean language, length: {len(full_text)}, structure: {para_count} paras)")
        else:
            issues = []
            if has_messy:
                issues.append("contains unprofessional language")
            if not has_reasonable_length:
                issues.append(f"too short ({len(full_text)} chars)")
            if not has_good_structure:
                issues.append(f"poor structure ({para_count} paras)")
            if not has_standardization:
                issues.append("not properly standardized")
            feedback_parts.append(f"❌ Quality issues ({', '.join(issues)})")

        # ===================================================================
        # Calculate Final Score
        # ===================================================================
        
        score = int((criteria_met / 5) * 100)
        passed = score >= 75  # Need at least 4/5 criteria

        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {criteria_met}/5 criteria met, score={score}, passed={passed}")

        return {
            "passed": passed,
            "score": score,
            "feedback": f"Score: {criteria_met}/5 criteria. {feedback}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
