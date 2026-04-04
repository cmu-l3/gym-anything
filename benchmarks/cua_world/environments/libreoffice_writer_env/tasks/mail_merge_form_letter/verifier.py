#!/usr/bin/env python3
"""Verifier for mail_merge_form_letter task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_mail_merge_output,
    check_no_raw_placeholders,
    verify_page_breaks,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mail_merge(traj, env_info, task_info):
    """
    Verify that mail merge was completed successfully.

    Checks:
    1. Merged output file exists (not just template)
    2. All 5 patron names appear in the document
    3. Letter structure preserved (salutation, closing, library name)
    4. Page breaks between letters (at least 4)
    5. No raw placeholders remain
    6. VLM cross-validation (visual check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_names = metadata.get('expected_names', [])
    placeholders = metadata.get('placeholders', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/merged_letters.docx')
    template_path = metadata.get('template_path', '/home/ga/Documents/letter_template.docx')

    # Try the expected output path first, then fall back to template path
    doc = None
    temp_dir = None
    loaded_output = False
    for path in [output_path, template_path]:
        success, doc, error, temp_dir = copy_and_parse_document(
            path, copy_from_env, file_format='docx'
        )
        if success:
            loaded_output = (path == output_path)
            break
        if temp_dir:
            cleanup_verification_temp(temp_dir)

    if not success or doc is None:
        return {"passed": False, "score": 0, "feedback": f"Could not load output document: {error}"}

    try:
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Criterion 1: Merged output file exists (not just the template)
        if loaded_output:
            criteria_passed += 1
            feedback_parts.append("Merged output file found")
        else:
            feedback_parts.append("Merged output file NOT found (fell back to template)")

        # Criterion 2: All patron names appear
        name_found, name_total, name_feedback = check_mail_merge_output(doc, expected_names)
        if name_found >= 4:  # At least 4 of 5
            criteria_passed += 1
            feedback_parts.append(f"Patron names found: {name_found}/{name_total}")
        else:
            feedback_parts.append(f"Patron names missing: only {name_found}/{name_total} found")

        # Criterion 3: Letter structure preserved (not just CSV data dump)
        # The output must contain template phrases proving actual letters were generated
        full_text = get_document_text(doc).lower()
        structure_phrases = [
            "dear",              # salutation
            "sincerely",         # closing
            "greenfield public library",  # letterhead
            "renew",             # body content about renewal
        ]
        structure_found = sum(1 for sp in structure_phrases if sp in full_text)
        if structure_found >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Letter structure: {structure_found}/{len(structure_phrases)} phrases found")
        else:
            feedback_parts.append(f"Letter structure missing: only {structure_found}/{len(structure_phrases)} template phrases")

        # Criterion 4: Page breaks between letters
        page_breaks = verify_page_breaks(doc)
        if page_breaks >= 4:
            criteria_passed += 1
            feedback_parts.append(f"Page breaks: {page_breaks}")
        else:
            feedback_parts.append(f"Page breaks insufficient: {page_breaks} (expected >= 4)")

        # Criterion 5: No raw placeholders remain
        placeholder_violations, placeholder_feedback = check_no_raw_placeholders(
            doc, placeholders
        )
        if placeholder_violations == 0:
            criteria_passed += 1
            feedback_parts.append("No raw placeholders remaining")
        else:
            feedback_parts.append(
                f"Raw placeholders still present: {placeholder_violations}"
            )

        # Criterion 6: VLM cross-validation (visual check of final screenshot)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this LibreOffice Writer screenshot. Answer in JSON:
{
    "shows_letter_content": true/false,
    "shows_personalized_name": true/false,
    "multiple_pages_visible": true/false
}
Does the document show:
1. Content that looks like a letter (greeting, body text, closing)?
2. A personalized name (not a placeholder like {Name})?
3. Evidence of multiple pages or page breaks?
""")
        if vlm_result is not None:
            shows_letter = vlm_result.get("shows_letter_content", False)
            shows_name = vlm_result.get("shows_personalized_name", False)
            if shows_letter and shows_name:
                criteria_passed += 1
                feedback_parts.append("VLM: personalized letter confirmed visually")
            else:
                feedback_parts.append("VLM: personalized letter not confirmed visually")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable (skipped)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60

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
