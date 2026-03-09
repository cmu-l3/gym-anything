#!/usr/bin/env python3
"""
Verifier for Format Document task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    check_text_formatting,
    get_document_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_formatting(traj, env_info, task_info):
    """
    Verify that document formatting was applied correctly.

    Checks:
    1. "Make this text bold" is actually bold
    2. "Make this text italic" is actually italic
    3. "Important Notice" is formatted as heading (larger font or bold)
    4. Document was saved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/sample_document.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_doc_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        criteria_passed = 0
        feedback_parts = []

        # Criterion 1: Check if "Make this text bold" is bold
        if check_text_formatting(doc, "Make this text bold", bold=True):
            criteria_passed += 1
            feedback_parts.append("✅ 'Make this text bold' is correctly bold")
        else:
            feedback_parts.append("❌ 'Make this text bold' is not bold")

        # Criterion 2: Check if "Make this text italic" is italic
        if check_text_formatting(doc, "Make this text italic", italic=True):
            criteria_passed += 1
            feedback_parts.append("✅ 'Make this text italic' is correctly italic")
        else:
            feedback_parts.append("❌ 'Make this text italic' is not italic")

        # Criterion 3: Check if "Important Notice" is formatted as heading (bold or large font)
        is_heading_bold = check_text_formatting(doc, "Important Notice", bold=True)
        is_heading_large = check_text_formatting(doc, "Important Notice", font_size=16) or \
                          check_text_formatting(doc, "Important Notice", font_size=18) or \
                          check_text_formatting(doc, "Important Notice", font_size=20)

        if is_heading_bold or is_heading_large:
            criteria_passed += 1
            if is_heading_large:
                feedback_parts.append("✅ 'Important Notice' is formatted as heading (large font)")
            else:
                feedback_parts.append("✅ 'Important Notice' is formatted as heading (bold)")
        else:
            feedback_parts.append("❌ 'Important Notice' is not formatted as heading")

        # Criterion 4: Verify document has expected content
        doc_text = get_document_text(doc)
        if "ONLYOFFICE Document Editor" in doc_text and "regular text" in doc_text:
            criteria_passed += 1
            feedback_parts.append("✅ Document content preserved")
        else:
            feedback_parts.append("❌ Document content missing or corrupted")

        score = int((criteria_passed / 4) * 100)
        passed = score >= 75

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
