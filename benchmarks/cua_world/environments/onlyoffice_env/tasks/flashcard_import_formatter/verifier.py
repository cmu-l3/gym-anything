#!/usr/bin/env python3
"""
Verifier for Flashcard Import Formatter task

Checks if messy vocabulary notes were properly reformatted into
tab-delimited flashcard import format with clean structure.
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_flashcard_formatter(traj, env_info, task_info):
    """
    Verify that vocabulary notes were reformatted correctly.

    Checks:
    1. File exists and readable
    2. Header row present with "English" and "Spanish"
    3. Correct entry count (10 vocabulary entries ±1)
    4. TAB delimiter used (not comma/space/other)
    5. All required Spanish vocab present
    6. Special characters preserved (á, é, ñ, ¿, ¡)
    7. Parenthetical notes removed
    8. No multi-line entries (each flashcard on single line)
    9. English column populated
    10. Consistent structure (2-3 columns per row)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/spanish_vocab_notes.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_flashcard_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        # Extract full text
        full_text = get_document_text(doc)
        
        if not full_text or len(full_text.strip()) == 0:
            return {"passed": False, "score": 0, "feedback": "Document is empty"}

        criteria_passed = 0
        feedback_parts = []

        # Split into lines and filter out empty/instructional lines
        all_lines = full_text.split('\n')
        
        # Filter to potential data lines (contains tabs or looks like vocabulary)
        data_lines = []
        for line in all_lines:
            line_stripped = line.strip()
            # Skip empty lines, titles, instructions
            if not line_stripped:
                continue
            if line_stripped.startswith('---'):
                continue
            if 'TODO' in line_stripped or 'Compiled from' in line_stripped:
                continue
            if line_stripped.startswith('Spanish Vocabulary'):
                continue
            if line_stripped.startswith('Need header') or line_stripped.startswith('Remove all'):
                continue
            data_lines.append(line_stripped)

        logger.info(f"Found {len(data_lines)} data lines")
        logger.info(f"Sample lines: {data_lines[:3]}")

        # Criterion 1: File exists and readable (already passed if we got here)
        criteria_passed += 1
        feedback_parts.append("✅ File exists and readable")

        # Criterion 2: Check for header row
        has_header = False
        header_line = None
        for line in data_lines[:3]:  # Check first 3 lines for header
            if 'english' in line.lower() and 'spanish' in line.lower():
                has_header = True
                header_line = line
                break
        
        if has_header:
            criteria_passed += 1
            feedback_parts.append("✅ Header row present with 'English' and 'Spanish'")
        else:
            feedback_parts.append("❌ Header row missing (should contain 'English' and 'Spanish')")

        # Remove header from data lines for vocabulary counting
        vocab_lines = [l for l in data_lines if not ('english' in l.lower() and 'spanish' in l.lower())]

        # Criterion 3: Check entry count (should be ~10 vocabulary entries)
        vocab_count = len(vocab_lines)
        if 9 <= vocab_count <= 11:
            criteria_passed += 1
            feedback_parts.append(f"✅ Correct entry count: {vocab_count} entries")
        else:
            feedback_parts.append(f"❌ Incorrect entry count: {vocab_count} entries (expected ~10)")

        # Criterion 4: Check for TAB delimiter usage
        tab_count = sum(1 for line in vocab_lines if '\t' in line)
        tab_percentage = (tab_count / max(len(vocab_lines), 1)) * 100
        
        if tab_percentage >= 70:  # At least 70% of lines should have tabs
            criteria_passed += 1
            feedback_parts.append(f"✅ TAB delimiter used in {tab_count}/{len(vocab_lines)} entries")
        else:
            feedback_parts.append(f"❌ TAB delimiter not consistently used ({tab_count}/{len(vocab_lines)} entries)")

        # Criterion 5: Check all required Spanish vocabulary is present
        required_vocab = [
            'restaurante', 'comer', 'hotel', 'playa', 
            'baño', 'aeropuerto', 'taxi', 'agua',
            'quisiera', 'cuesta'
        ]
        
        full_text_lower = full_text.lower()
        vocab_found = sum(1 for word in required_vocab if word in full_text_lower)
        
        if vocab_found >= 8:  # At least 8 out of 10
            criteria_passed += 1
            feedback_parts.append(f"✅ Required vocabulary present: {vocab_found}/10 words found")
        else:
            feedback_parts.append(f"❌ Missing vocabulary: only {vocab_found}/10 words found")

        # Criterion 6: Check special characters are preserved
        special_chars = ['á', 'é', 'í', 'ó', 'ú', 'ñ', '¿', '¡']
        special_found = sum(1 for char in special_chars if char in full_text)
        
        if special_found >= 4:  # Should have several special characters
            criteria_passed += 1
            feedback_parts.append(f"✅ Special characters preserved: {special_found} types found")
        else:
            feedback_parts.append(f"❌ Special characters missing or corrupted: only {special_found} found")

        # Criterion 7: Check parenthetical notes are removed
        has_parens = '(la playa)' in full_text or '(same!)' in full_text.lower()
        
        if not has_parens:
            criteria_passed += 1
            feedback_parts.append("✅ Parenthetical notes removed")
        else:
            feedback_parts.append("❌ Parenthetical notes still present: (la playa) or (same!)")

        # Criterion 8: Check for multi-line entries (should be minimal)
        # Look for pattern: single word/phrase followed by indented continuation
        multi_line_pattern = 0
        for i, line in enumerate(vocab_lines):
            # If line doesn't have tab and is very short, might be multi-line fragment
            if '\t' not in line and len(line) < 30 and i < len(vocab_lines) - 1:
                next_line = vocab_lines[i + 1]
                if next_line.startswith(' ') or (len(next_line) < 40 and '\t' not in next_line):
                    multi_line_pattern += 1
        
        if multi_line_pattern <= 2:  # Allow some tolerance
            criteria_passed += 1
            feedback_parts.append("✅ Entries consolidated to single lines")
        else:
            feedback_parts.append(f"❌ Multi-line entries detected: {multi_line_pattern} possible cases")

        # Criterion 9: Check English column is populated (entries have translations)
        # For tab-delimited entries, split and check both columns are non-empty
        tab_lines = [l for l in vocab_lines if '\t' in l]
        populated_count = 0
        for line in tab_lines:
            parts = line.split('\t')
            if len(parts) >= 2 and parts[0].strip() and parts[1].strip():
                populated_count += 1
        
        if tab_lines and (populated_count / len(tab_lines)) >= 0.7:
            criteria_passed += 1
            feedback_parts.append(f"✅ English column populated: {populated_count}/{len(tab_lines)} entries")
        else:
            feedback_parts.append(f"❌ English column incomplete: {populated_count}/{len(tab_lines)} entries")

        # Criterion 10: Check consistent structure (2-3 columns)
        inconsistent_count = 0
        for line in tab_lines:
            parts = line.split('\t')
            if len(parts) < 2 or len(parts) > 4:  # Should be 2-3 columns (allow 4 for tolerance)
                inconsistent_count += 1
        
        if inconsistent_count <= 2:  # Allow small tolerance
            criteria_passed += 1
            feedback_parts.append("✅ Consistent structure: 2-3 columns per entry")
        else:
            feedback_parts.append(f"❌ Inconsistent structure: {inconsistent_count} entries with wrong column count")

        # Calculate score and pass/fail
        score = int((criteria_passed / 10) * 100)
        passed = score >= 80  # Need 8/10 criteria

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