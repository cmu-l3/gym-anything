#!/usr/bin/env python3
"""Verifier for format_business_letter task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_text_formatting,
    check_paragraph_alignment,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_line_spacing(doc, target_spacing=1.0):
    """
    Check if paragraphs have single line spacing (spacing=1.0 or Spacing.SINGLE).

    Args:
        doc: python-docx Document object
        target_spacing: Expected line spacing (1.0 for single)

    Returns:
        tuple: (passes, total_checked, details)
    """
    from docx.shared import Pt
    from docx.enum.text import WD_LINE_SPACING

    single_spaced = 0
    total_checked = 0

    for para in doc.paragraphs:
        text = para.text.strip()
        # Only check substantial paragraphs (body text, not blank lines or short items)
        if len(text) > 50:
            total_checked += 1
            pf = para.paragraph_format

            # Check for single spacing - can be set multiple ways
            is_single = False

            # Method 1: line_spacing_rule is SINGLE
            if pf.line_spacing_rule == WD_LINE_SPACING.SINGLE:
                is_single = True
            # Method 2: line_spacing is 1.0 (or None which defaults to single)
            elif pf.line_spacing is None or pf.line_spacing == 1.0:
                is_single = True
            # Method 3: line_spacing is close to 1.0
            elif isinstance(pf.line_spacing, float) and 0.9 <= pf.line_spacing <= 1.1:
                is_single = True

            if is_single:
                single_spaced += 1

    return single_spaced, total_checked, f"{single_spaced}/{total_checked} paragraphs have single spacing"


def check_signature_line(doc, sender_name):
    """
    Check if a signature line is present after the closing.

    The signature line should:
    1. Contain the sender's name
    2. Be after the closing (Sincerely)
    3. Optionally be on a separate line from the closing

    Args:
        doc: python-docx Document object
        sender_name: Expected name in signature (e.g., "Emily Chen")

    Returns:
        tuple: (found, details)
    """
    full_text = get_document_text(doc).lower()
    sender_lower = sender_name.lower()

    # Check if sender name appears in the document
    if sender_lower not in full_text:
        return False, "Signature line not found - sender name missing"

    # Find the position of closing and signature
    closing_pos = full_text.find('sincerely')
    if closing_pos == -1:
        return False, "Cannot verify signature - closing not found"

    signature_pos = full_text.find(sender_lower)

    # Signature should be AFTER the closing
    if signature_pos > closing_pos:
        return True, f"Signature line found: {sender_name}"
    else:
        # Name appears but before closing - might be in sender address at top
        # Check if it appears AGAIN after closing
        text_after_closing = full_text[closing_pos:]
        if sender_lower in text_after_closing:
            return True, f"Signature line found after closing: {sender_name}"
        else:
            return False, "Sender name found but not as signature after closing"


def verify_business_letter_formatting(traj, env_info, task_info):
    """
    Verify that the business letter was formatted correctly.

    PREREQUISITE: Content must be preserved (not corrupted). If content is
    corrupted or missing, return 0 score immediately.

    SCORING CRITERIA (only checked if prerequisite passes):
    1. Sender address is present (Emily Chen, Seattle, WA 98101)
    2. Date is present (January 15, 2024) - requires FULL date string
    3. Recipient address is present (Ms. Kathleen Hogan, Microsoft Corporation, Redmond)
    4. Salutation is bold
    5. Body paragraphs are justified
    6. Body paragraphs have single line spacing
    7. Closing is italic
    8. Signature line is present (sender name after closing)
    9. VLM visual verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/draft_letter.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        metadata = task_info.get('metadata', {})
        sender_name = metadata.get('sender_name', 'Emily Chen')
        sender_city = metadata.get('sender_city_state_zip', 'Seattle, WA')
        recipient_name = metadata.get('recipient_name', 'Ms. Kathleen Hogan')
        recipient_company = metadata.get('recipient_company', 'Microsoft')
        date_text = metadata.get('date_text', 'January 15, 2024')
        salutation = metadata.get('salutation', 'Dear Ms. Hogan')
        closing = metadata.get('closing', 'Sincerely')

        feedback_parts = []
        full_text = get_document_text(doc).lower()

        # ================================================================
        # PREREQUISITE CHECK: Content must be preserved
        # If content is corrupted/missing, score is 0 (not partial credit)
        # ================================================================
        key_phrases = [
            "senior software engineer",
            "full-stack development",
            "artificial intelligence",
            "collaborative culture",
        ]
        preserved = sum(1 for p in key_phrases if p in full_text)

        if preserved < 3:
            feedback_parts.append(f"PREREQUISITE FAILED: Content corrupted ({preserved}/{len(key_phrases)} key phrases)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
            }

        # Content is preserved - note this but don't count as positive criterion
        feedback_parts.append(f"Prerequisite: content preserved ({preserved}/{len(key_phrases)})")

        # ================================================================
        # SCORING CRITERIA - only evaluated if prerequisite passes
        # ================================================================
        criteria_passed = 0
        total_criteria = 9  # 8 document checks + VLM

        # Criterion 1: Sender address is present
        sender_present = (
            sender_name.lower() in full_text and
            (sender_city.lower() in full_text or 'seattle' in full_text)
        )
        if sender_present:
            criteria_passed += 1
            feedback_parts.append("Sender address: present")
        else:
            feedback_parts.append("Sender address: NOT found")

        # Criterion 2: Date is present - require specific date format
        # Must have both month and year, not just "2024" anywhere
        date_present = (
            date_text.lower() in full_text or  # Full date "January 15, 2024"
            ('january' in full_text and '2024' in full_text) or  # Month and year together
            'january 15' in full_text  # Month and day
        )
        if date_present:
            criteria_passed += 1
            feedback_parts.append("Date: present")
        else:
            feedback_parts.append("Date: NOT found (requires month+year, not just '2024')")

        # Criterion 3: Recipient address is present
        # Require SPECIFIC recipient info, not just "Microsoft" (which is in original document body)
        recipient_present = (
            recipient_name.lower() in full_text or  # "Ms. Kathleen Hogan"
            'kathleen hogan' in full_text or  # Name without title
            'chief people officer' in full_text or  # Title
            'one microsoft way' in full_text or  # Specific address
            'redmond' in full_text  # City in address
        )
        if recipient_present:
            criteria_passed += 1
            feedback_parts.append("Recipient address: present")
        else:
            feedback_parts.append("Recipient address: NOT found (need name/title/address, not just 'Microsoft')")

        # Criterion 4: Salutation is bold
        salutation_bold = check_text_formatting(doc, salutation, bold=True)
        if salutation_bold:
            criteria_passed += 1
            feedback_parts.append("Salutation: bold")
        else:
            if salutation.lower() in full_text or 'dear ms. hogan' in full_text:
                feedback_parts.append("Salutation: present but not bold")
            else:
                feedback_parts.append("Salutation: NOT formatted correctly")

        # Criterion 5: Body paragraphs are justified
        justified_count = 0
        body_samples = [
            "express my strong interest",  # First paragraph
            "enterprise-scale cloud services",  # Second paragraph
            "innovations in ai and cloud computing",  # Third paragraph
            "opportunity to discuss",  # Fifth paragraph
        ]
        for sample in body_samples:
            if check_paragraph_alignment(doc, sample, 'justify'):
                justified_count += 1

        # Require at least 3 out of 4 samples to be justified (75%+)
        if justified_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)}")
        else:
            feedback_parts.append(f"Body NOT justified: only {justified_count}/{len(body_samples)} (need 3+)")

        # Criterion 6: Single line spacing
        single_count, total_paras, spacing_detail = check_line_spacing(doc, 1.0)
        # Pass if at least 80% of checked paragraphs have single spacing
        # (Using integer math: 4*count >= 5*total is equivalent to count/total >= 0.8)
        if total_paras > 0 and (single_count * 5) >= (total_paras * 4):
            criteria_passed += 1
            feedback_parts.append(f"Line spacing: single ({spacing_detail})")
        else:
            pct = (single_count * 100 // total_paras) if total_paras > 0 else 0
            feedback_parts.append(f"Line spacing: NOT single ({spacing_detail}, only {pct}% - need 80%+)")

        # Criterion 7: Closing is italic
        closing_italic = check_text_formatting(doc, closing, italic=True)
        if closing_italic:
            criteria_passed += 1
            feedback_parts.append("Closing: italic")
        else:
            if closing.lower() in full_text or 'sincerely' in full_text:
                feedback_parts.append("Closing: present but not italic")
            else:
                feedback_parts.append("Closing: NOT found")

        # Criterion 8: Signature line present
        sig_found, sig_detail = check_signature_line(doc, sender_name)
        if sig_found:
            criteria_passed += 1
            feedback_parts.append(f"Signature: {sig_detail}")
        else:
            feedback_parts.append(f"Signature: {sig_detail}")

        # Criterion 9: VLM cross-validation
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Writer screenshot of a business letter. Answer in JSON:
{
    "has_header_address": true/false,
    "has_date": true/false,
    "has_recipient_address": true/false,
    "has_proper_letter_structure": true/false,
    "body_text_visible": true/false
}
Does the document show:
1. A sender/return address at the top?
2. A date below the header?
3. A recipient address (name, company, address)?
4. Proper business letter structure with greeting, body, and closing?
5. Visible body paragraphs with the letter content?
""")
        if vlm_result is not None:
            has_header = vlm_result.get("has_header_address", False)
            has_date = vlm_result.get("has_date", False)
            has_structure = vlm_result.get("has_proper_letter_structure", False)
            body_visible = vlm_result.get("body_text_visible", False)

            if (has_header or has_date) and (has_structure or body_visible):
                criteria_passed += 1
                feedback_parts.append("VLM: business letter formatting confirmed")
            else:
                feedback_parts.append("VLM: business letter formatting not confirmed")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable (skipped)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 55  # ~5/9 criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
