#!/usr/bin/env python3
"""
Verifier for Interfaith Ceremony Script task

Verifies that the wedding ceremony script has been properly completed with:
- All placeholders filled in
- Proper formatting (headings, italic stage directions, bold sections)
- Required content (both cultural traditions, Hebrew blessing, vows, etc.)
- Timing information
- Professional structure
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_interfaith_ceremony_script(traj, env_info, task_info):
    """
    Verify that the interfaith ceremony script has been properly completed.

    Scoring breakdown (100 points total):
    - Required sections present (25 points)
    - No placeholders remaining (20 points)
    - Proper formatting applied (25 points)
    - Timing information (10 points)
    - Appropriate document length (10 points)
    - Both cultural traditions (10 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # Try both possible filenames
    container_paths = [
        "/home/ga/Documents/TextDocuments/ceremony_script.docx",
        "/home/ga/Documents/TextDocuments/ceremony_draft.docx"
    ]

    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_ceremony_')

    doc = None
    success = False
    
    for container_path in container_paths:
        try:
            success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
            if success:
                logger.info(f"Successfully loaded document from: {container_path}")
                break
        except Exception as e:
            logger.warning(f"Failed to load from {container_path}: {e}")
            continue

    if not success or doc is None:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Failed to load ceremony document from any expected location. Ensure document was saved."
        }

    try:
        score = 0.0
        max_score = 100.0
        feedback_parts = []

        # Get full text (lowercase for easier searching)
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        logger.info(f"Document text length: {len(full_text)} characters")

        # ============================================================
        # 1. REQUIRED SECTIONS PRESENT (25 points)
        # ============================================================
        required_sections = {
            "processional": 3,
            "recessional": 3,
            "vow": 3,
            "ring": 3,
            "pronounce": 3,
            "welcome": 2,
            "reading": 2,
        }

        sections_found = 0
        sections_missing = []

        for section, points in required_sections.items():
            if section in full_text_lower:
                score += points
                sections_found += 1
            else:
                sections_missing.append(section)

        if sections_found == len(required_sections):
            feedback_parts.append(f"✅ All {sections_found} required sections present (+{sum(required_sections.values())}pts)")
        else:
            found_points = sum(points for sect, points in required_sections.items() if sect in full_text_lower)
            feedback_parts.append(f"⚠️  {sections_found}/{len(required_sections)} sections found (+{found_points}pts)")
            if sections_missing:
                feedback_parts.append(f"   Missing: {', '.join(sections_missing)}")

        # Additional critical elements
        critical_elements = [
            ("unity candle", "candle lighting", 3),
            ("glass", "breaking", 2),
            ("hebrew", "baruch", 2),
        ]

        for term1, term2, points in critical_elements:
            if term1 in full_text_lower or term2 in full_text_lower:
                score += points

        # ============================================================
        # 2. NO PLACEHOLDERS REMAINING (20 points)
        # ============================================================
        placeholder_patterns = [
            r'\[fill in',
            r'\[choose',
            r'\?\?',
            r'or something\?',
            r'\[add\s+',
            r'\[insert',
            r'tbd',
            r'\[music:\s*what',
        ]

        placeholders_found = []
        for pattern in placeholder_patterns:
            matches = re.findall(pattern, full_text_lower)
            if matches:
                placeholders_found.extend(matches)

        if len(placeholders_found) == 0:
            score += 20
            feedback_parts.append("✅ All placeholders completed (+20pts)")
        elif len(placeholders_found) <= 2:
            score += 10
            feedback_parts.append(f"⚠️  {len(placeholders_found)} placeholders remain (+10pts)")
        else:
            feedback_parts.append(f"❌ {len(placeholders_found)} placeholders still present (0pts)")

        # ============================================================
        # 3. PROPER FORMATTING PRESENT (25 points)
        # ============================================================
        has_bold = False
        has_italic = False
        heading_count = 0
        bold_count = 0
        italic_count = 0

        for para in doc.paragraphs:
            # Check if paragraph uses heading style
            if para.style.name.startswith('Heading'):
                heading_count += 1
            
            # Check runs for formatting
            for run in para.runs:
                if run.bold:
                    has_bold = True
                    bold_count += 1
                if run.italic:
                    has_italic = True
                    italic_count += 1

        # Award points for formatting
        formatting_score = 0
        
        if has_bold and bold_count >= 5:
            formatting_score += 9
            feedback_parts.append(f"✅ Bold formatting used ({bold_count} instances) (+9pts)")
        elif has_bold:
            formatting_score += 4
            feedback_parts.append(f"⚠️  Limited bold formatting ({bold_count} instances) (+4pts)")
        else:
            feedback_parts.append("❌ No bold formatting found")

        if has_italic and italic_count >= 3:
            formatting_score += 8
            feedback_parts.append(f"✅ Italic formatting used ({italic_count} instances) (+8pts)")
        elif has_italic:
            formatting_score += 3
            feedback_parts.append(f"⚠️  Limited italic formatting ({italic_count} instances) (+3pts)")
        else:
            feedback_parts.append("❌ No italic formatting found")

        if heading_count >= 6:
            formatting_score += 8
            feedback_parts.append(f"✅ Excellent heading structure ({heading_count} headings) (+8pts)")
        elif heading_count >= 3:
            formatting_score += 4
            feedback_parts.append(f"⚠️  Adequate heading structure ({heading_count} headings) (+4pts)")
        elif heading_count > 0:
            formatting_score += 2
            feedback_parts.append(f"⚠️  Minimal heading structure ({heading_count} headings) (+2pts)")
        else:
            feedback_parts.append("❌ No heading styles applied")

        score += formatting_score

        # ============================================================
        # 4. TIMING INFORMATION PRESENT (10 points)
        # ============================================================
        timing_patterns = [
            r'\[\s*\d+\s*min',  # [3 min]
            r'\d+\s*minutes',   # 3 minutes
            r'\d+-\d+\s*min',   # 3-4 min
            r'approximately\s+\d+',  # approximately 3
            r'duration[:\s]+\d+',    # duration: 3
        ]

        timing_matches = 0
        for pattern in timing_patterns:
            matches = re.findall(pattern, full_text_lower)
            timing_matches += len(matches)

        if timing_matches >= 5:
            score += 10
            feedback_parts.append(f"✅ Comprehensive timing cues ({timing_matches} found) (+10pts)")
        elif timing_matches >= 3:
            score += 7
            feedback_parts.append(f"✅ Good timing cues ({timing_matches} found) (+7pts)")
        elif timing_matches >= 1:
            score += 3
            feedback_parts.append(f"⚠️  Some timing cues ({timing_matches} found) (+3pts)")
        else:
            feedback_parts.append("❌ No timing information found")

        # ============================================================
        # 5. APPROPRIATE LENGTH (10 points)
        # ============================================================
        para_count = count_paragraphs(doc)
        word_count = len(full_text.split())

        if 30 <= para_count <= 80 and word_count >= 400:
            score += 10
            feedback_parts.append(f"✅ Good document length ({para_count} paragraphs, {word_count} words) (+10pts)")
        elif 20 <= para_count <= 100 and word_count >= 250:
            score += 6
            feedback_parts.append(f"⚠️  Acceptable length ({para_count} paragraphs, {word_count} words) (+6pts)")
        elif para_count < 20:
            feedback_parts.append(f"❌ Document too short ({para_count} paragraphs)")
        else:
            feedback_parts.append(f"⚠️  Document length borderline ({para_count} paragraphs, {word_count} words) (+3pts)")
            score += 3

        # ============================================================
        # 6. BOTH CULTURAL ELEMENTS (10 points)
        # ============================================================
        # Jewish elements
        jewish_terms = ["hebrew", "sheva", "baruch", "glass", "breaking", "mazel", "jewish"]
        has_jewish = any(term in full_text_lower for term in jewish_terms)
        
        # Check for transliteration (Hebrew phonetics)
        has_transliteration = bool(re.search(r'baruch|atah|adonai|elohenu|melech|haolam', full_text_lower))
        
        # Catholic elements
        catholic_terms = ["candle", "unity", "light", "catholic", "blessing"]
        has_catholic = any(term in full_text_lower for term in catholic_terms)

        cultural_score = 0
        if has_jewish and has_transliteration:
            cultural_score += 5
            feedback_parts.append("✅ Jewish tradition with transliteration (+5pts)")
        elif has_jewish:
            cultural_score += 3
            feedback_parts.append("⚠️  Jewish tradition present but no transliteration (+3pts)")

        if has_catholic:
            cultural_score += 5
            feedback_parts.append("✅ Catholic tradition represented (+5pts)")
        else:
            feedback_parts.append("❌ Catholic tradition not clearly present")

        score += cultural_score

        # ============================================================
        # FINAL ASSESSMENT
        # ============================================================
        passed = score >= 70.0
        normalized_score = score / max_score

        # Add summary to feedback
        feedback_summary = f"Final Score: {score:.1f}/{max_score} ({normalized_score*100:.1f}%)"
        if passed:
            feedback_summary += " ✅ PASSED"
        else:
            feedback_summary += " ❌ FAILED (need 70+)"

        feedback = feedback_summary + " | " + " | ".join(feedback_parts)

        logger.info(f"Verification complete. Score: {score}/{max_score}, Passed: {passed}")

        return {
            "passed": passed,
            "score": normalized_score,
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
