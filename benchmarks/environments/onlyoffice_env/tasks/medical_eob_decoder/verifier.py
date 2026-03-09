#!/usr/bin/env python3
"""
Verifier for Medical EOB Decoder task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_medical_eob_decoder(traj, env_info, task_info):
    """
    Verify that medical EOB was correctly decoded into a spreadsheet.

    Checks:
    1. File exists and is valid XLSX (15 points)
    2. Data structure - contains all 5 EOB line items (20 points)
    3. Human-readable procedure descriptions (15 points)
    4. Accurate calculations - totals and discrepancy (20 points)
    5. Denied claims are flagged (15 points)
    6. Questions section present (15 points)
    
    Total: 100 points, passing threshold: 70
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/EOB_Decoded_2024.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_eob_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        score = 0
        feedback_parts = []

        # Criterion 1: File exists and is valid (15 points)
        score += 15
        feedback_parts.append("✅ File created and valid XLSX format")

        # Get the active sheet
        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=50, max_cols=15)

        # Convert all data to lowercase string for easier searching
        all_text = ' '.join([str(cell).lower() for row in data for cell in row if cell is not None])
        
        # Also keep original case for some checks
        all_text_original = ' '.join([str(cell) for row in data for cell in row if cell is not None])

        # Criterion 2: Data structure - contains all 5 line items (20 points)
        # Look for the 4 unique procedure codes (99285 appears twice)
        required_codes = ['99285', '85025', '92004', '92134']
        codes_found = []
        for code in required_codes:
            if code in all_text or code in all_text_original:
                codes_found.append(code)
        
        # Also check for monetary values that appear in the EOB
        key_amounts = ['892', '156', '1450', '425', '380']  # Billed amounts
        amounts_found = sum([1 for amt in key_amounts if amt in all_text_original])

        data_structure_score = 0
        if len(codes_found) >= 4:
            data_structure_score += 10
            feedback_parts.append(f"✅ All 4 procedure codes present ({len(codes_found)}/4)")
        elif len(codes_found) >= 3:
            data_structure_score += 7
            feedback_parts.append(f"⚠️ Most procedure codes present ({len(codes_found)}/4)")
        elif len(codes_found) >= 2:
            data_structure_score += 4
            feedback_parts.append(f"⚠️ Some procedure codes present ({len(codes_found)}/4)")
        else:
            feedback_parts.append(f"❌ Missing procedure codes ({len(codes_found)}/4 found)")

        if amounts_found >= 4:
            data_structure_score += 10
            feedback_parts.append(f"✅ Financial data extracted ({amounts_found}/5 key amounts)")
        elif amounts_found >= 3:
            data_structure_score += 6
            feedback_parts.append(f"⚠️ Most financial data present ({amounts_found}/5)")
        elif amounts_found >= 2:
            data_structure_score += 3
            feedback_parts.append(f"⚠️ Some financial data present ({amounts_found}/5)")

        score += data_structure_score

        # Criterion 3: Human-readable descriptions (15 points)
        # Look for plain English descriptions of medical procedures
        description_keywords = [
            'emergency', 'blood', 'ophthalmology', 'exam', 'imaging', 
            'er visit', 'cbc', 'count', 'eye', 'retinal', 'diagnostic',
            'department', 'comprehensive', 'lab', 'hospital'
        ]
        
        keywords_found = sum([1 for kw in description_keywords if kw in all_text])
        
        # Check if any procedures are described (not just codes)
        has_descriptions = keywords_found >= 3
        
        description_score = 0
        if keywords_found >= 4:
            description_score = 15
            feedback_parts.append(f"✅ Human-readable descriptions present ({keywords_found} keywords)")
        elif keywords_found >= 3:
            description_score = 12
            feedback_parts.append(f"✅ Good descriptions present ({keywords_found} keywords)")
        elif keywords_found >= 2:
            description_score = 8
            feedback_parts.append(f"⚠️ Some descriptions present ({keywords_found} keywords)")
        elif keywords_found >= 1:
            description_score = 4
            feedback_parts.append(f"⚠️ Minimal descriptions ({keywords_found} keyword)")
        else:
            feedback_parts.append("❌ No human-readable descriptions found")

        score += description_score

        # Criterion 4: Accurate calculations (20 points)
        # Look for key totals:
        # - Total Billed: $3,303.00
        # - Correct Patient Total: $869.80 (126.80 + 156.00 + 240.00 + 62.00 + 285.00)
        # - Incorrect EOB Total: $847.32
        # - Discrepancy: $22.48
        
        calc_score = 0
        
        # Check for total billed
        found_3303 = ('3303' in all_text_original or '3,303' in all_text_original)
        if found_3303:
            calc_score += 5
            feedback_parts.append("✅ Total billed amount ($3,303) calculated")
        
        # Check for correct patient responsibility total (~870 or 869.80)
        found_correct_total = ('869' in all_text_original or '870' in all_text_original)
        if found_correct_total:
            calc_score += 6
            feedback_parts.append("✅ Correct patient responsibility total (~$870) calculated")
        
        # Check for the incorrect EOB total (847)
        found_eob_total = '847' in all_text_original
        if found_eob_total:
            calc_score += 3
            feedback_parts.append("✅ EOB stated total ($847.32) noted")
        
        # Check for discrepancy identification (22.48 or 22 or reference to discrepancy)
        found_discrepancy = (
            '22.48' in all_text_original or 
            '22.50' in all_text_original or
            ('22' in all_text_original and ('discrepan' in all_text or 'difference' in all_text or 'error' in all_text))
        )
        if found_discrepancy:
            calc_score += 6
            feedback_parts.append("✅ Billing discrepancy ($22.48) identified")
        else:
            feedback_parts.append("❌ Billing discrepancy not identified")

        score += calc_score

        # Criterion 5: Denied claims flagged (15 points)
        # Look for mentions of denied, both procedures, and highlighting
        denied_mentions = all_text.count('denied') + all_text.count('deny')
        
        # Check for specific denied items
        has_blood_denial = ('85025' in all_text_original and 'denied' in all_text) or \
                          ('blood' in all_text and 'denied' in all_text) or \
                          ('cbc' in all_text and 'denied' in all_text)
        
        has_imaging_denial = ('92134' in all_text_original and 'denied' in all_text) or \
                            ('imaging' in all_text and 'denied' in all_text) or \
                            ('ophthalm' in all_text and 'denied' in all_text)
        
        flag_score = 0
        if denied_mentions >= 2 and (has_blood_denial or has_imaging_denial):
            flag_score = 15
            feedback_parts.append(f"✅ Denied claims properly flagged ({denied_mentions} mentions)")
        elif denied_mentions >= 2:
            flag_score = 12
            feedback_parts.append(f"✅ Denied claims flagged ({denied_mentions} mentions)")
        elif denied_mentions >= 1:
            flag_score = 8
            feedback_parts.append(f"⚠️ Some denial flagging present ({denied_mentions} mention)")
        else:
            feedback_parts.append("❌ Denied claims not flagged")

        score += flag_score

        # Criterion 6: Questions section (15 points)
        # Look for question indicators and specific content
        question_indicators = [
            '?', 'question', 'why', 'call', 'ask', 'dispute', 
            'appeal', 'clarif', 'insurance', 'contact', 'phone'
        ]
        
        question_count = sum([1 for ind in question_indicators if ind in all_text])
        
        # Look for question marks as a strong indicator
        question_mark_count = all_text_original.count('?')
        
        # Check if specific issues are mentioned
        asks_about_blood = ('blood' in all_text or '85025' in all_text_original) and \
                          ('why' in all_text or '?' in all_text_original or 'question' in all_text)
        
        asks_about_imaging = ('imaging' in all_text or '92134' in all_text_original) and \
                            ('why' in all_text or '?' in all_text_original or 'question' in all_text)
        
        asks_about_discrepancy = ('discrepan' in all_text or '847' in all_text_original or '22' in all_text_original) and \
                                ('why' in all_text or '?' in all_text_original or 'question' in all_text)
        
        specific_questions = sum([asks_about_blood, asks_about_imaging, asks_about_discrepancy])
        
        questions_score = 0
        if question_mark_count >= 3 or (question_count >= 5 and specific_questions >= 2):
            questions_score = 15
            feedback_parts.append(f"✅ Questions section present ({question_mark_count} questions, {specific_questions} specific topics)")
        elif question_mark_count >= 2 or (question_count >= 4 and specific_questions >= 1):
            questions_score = 12
            feedback_parts.append(f"✅ Questions section mostly complete ({question_mark_count} questions)")
        elif question_mark_count >= 1 or question_count >= 3:
            questions_score = 8
            feedback_parts.append(f"⚠️ Questions section partially present ({question_mark_count} questions)")
        elif question_count >= 2:
            questions_score = 4
            feedback_parts.append(f"⚠️ Minimal questions section ({question_count} indicators)")
        else:
            feedback_parts.append("❌ Questions section missing")

        score += questions_score

        # Calculate pass/fail
        passed = score >= 70

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
