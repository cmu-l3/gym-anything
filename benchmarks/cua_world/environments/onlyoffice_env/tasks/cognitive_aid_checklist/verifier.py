#!/usr/bin/env python3
"""
Verifier for Cognitive Aid Checklist task

This task verifies that a user created a clear, accessible emergency procedure
document suitable for someone with cognitive impairment.
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


def count_numbered_items(doc):
    """
    Count numbered list items in document.
    Checks both proper list formatting and manual numbering like "1.", "2.", etc.
    """
    count = 0
    
    # Method 1: Check for numbered list style
    try:
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'list' in style_name.lower() and 'number' in style_name.lower():
                count += 1
    except Exception as e:
        logger.debug(f"Error checking list styles: {e}")
    
    # Method 2: Check for manual numbering patterns in text
    try:
        text = get_document_text(doc)
        # Match patterns like "1.", "1)", "2.", "2)", etc. at start of lines
        manual_numbers = re.findall(r'^\s*\d+[\.)]\s+\w', text, re.MULTILINE)
        manual_count = len(manual_numbers)
        
        # Use the higher count (proper lists or manual numbering)
        count = max(count, manual_count)
        
        logger.info(f"Found {count} numbered items (proper lists or manual numbering)")
    except Exception as e:
        logger.debug(f"Error checking manual numbering: {e}")
    
    return count


def count_bold_runs(doc):
    """Count number of distinct bold text runs in document"""
    count = 0
    try:
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold and run.text and run.text.strip():
                    count += 1
        logger.info(f"Found {count} bold text runs")
    except Exception as e:
        logger.debug(f"Error counting bold runs: {e}")
    
    return count


def check_for_large_fonts(doc, min_size=14):
    """
    Check if document contains fonts >= min_size pt.
    Returns count of runs with large fonts.
    """
    count = 0
    try:
        for para in doc.paragraphs:
            for run in para.runs:
                if run.font.size:
                    size_pt = run.font.size.pt
                    if size_pt >= min_size:
                        count += 1
        logger.info(f"Found {count} text runs with font size >= {min_size}pt")
    except Exception as e:
        logger.debug(f"Error checking font sizes: {e}")
    
    return count


def check_for_title_formatting(doc):
    """
    Check if document has a properly formatted title.
    Returns True if title is found with appropriate formatting.
    """
    try:
        # Check first 3 paragraphs for title
        for i, para in enumerate(doc.paragraphs[:3]):
            if not para.text.strip():
                continue
            
            # Check if paragraph contains emergency-related keywords
            text_lower = para.text.lower()
            has_keyword = ('emergency' in text_lower or 'gas' in text_lower or 
                          'leak' in text_lower or 'procedure' in text_lower)
            
            if not has_keyword:
                continue
            
            # Check formatting
            is_bold = False
            is_large = False
            is_centered = False
            
            # Check for bold
            for run in para.runs:
                if run.bold:
                    is_bold = True
                if run.font.size and run.font.size.pt >= 16:
                    is_large = True
            
            # Check for center alignment
            try:
                if para.alignment == 1:  # CENTER
                    is_centered = True
            except:
                pass
            
            # Title should have at least 2 of: bold, large, centered
            formatting_score = sum([is_bold, is_large, is_centered])
            
            if formatting_score >= 2:
                logger.info(f"Found well-formatted title: '{para.text[:50]}'")
                return True
            elif formatting_score >= 1:
                logger.info(f"Found partially formatted title: '{para.text[:50]}'")
                return True  # Be lenient
                
    except Exception as e:
        logger.debug(f"Error checking title formatting: {e}")
    
    return False


def verify_cognitive_aid_checklist(traj, env_info, task_info):
    """
    Verify that the cognitive aid emergency procedure document was created correctly.

    Checks:
    1. Document exists and has content
    2. Contains appropriate title with "emergency" or "gas" keywords
    3. Has at least 5 numbered steps
    4. Has at least 2 instances of bold text (for warnings)
    5. Contains warning keywords ("do not", "never", "warning")
    6. Has emergency contact section with phone numbers
    7. Document is concise (under 800 words - one page constraint)
    8. Uses large fonts (14pt+ detected)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/gas_leak_procedure.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_cognitive_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []

        # Get full text for various checks
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        word_count = len(full_text.split())

        # Criterion 1: Document has substantial content (not just template)
        if word_count >= 50:
            criteria_passed += 1
            feedback_parts.append(f"✅ Document has content ({word_count} words)")
        else:
            feedback_parts.append(f"❌ Document has insufficient content ({word_count} words, need at least 50)")

        # Criterion 2: Check for appropriate title
        has_title_keywords = ('emergency' in full_text_lower or 'gas' in full_text_lower)
        has_title_formatting = check_for_title_formatting(doc)
        
        if has_title_keywords and has_title_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Has properly formatted title with appropriate keywords")
        elif has_title_keywords:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Has title keywords but formatting could be improved")
        else:
            feedback_parts.append("❌ Missing appropriate title (should contain 'emergency' or 'gas')")

        # Criterion 3: Check for numbered steps (at least 5)
        numbered_items = count_numbered_items(doc)
        if numbered_items >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Has {numbered_items} numbered steps (need at least 5)")
        elif numbered_items >= 3:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Has only {numbered_items} numbered steps (need at least 5)")
        else:
            feedback_parts.append(f"❌ Has only {numbered_items} numbered steps (need at least 5)")

        # Criterion 4: Check for bold text (warnings should be bold)
        bold_count = count_bold_runs(doc)
        if bold_count >= 3:  # At least some bold text beyond title
            criteria_passed += 1
            feedback_parts.append(f"✅ Has {bold_count} bold text elements (for emphasis)")
        elif bold_count >= 1:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Has only {bold_count} bold text elements (need more for warnings)")
        else:
            feedback_parts.append("❌ No bold text found (warnings should be bold)")

        # Criterion 5: Check for warning language
        warning_patterns = [
            (r'\bdo not\b', 'DO NOT'),
            (r'\bdon\'?t\b', "DON'T"),
            (r'\bnever\b', 'NEVER'),
            (r'\bwarning\b', 'WARNING'),
            (r'\bcaution\b', 'CAUTION'),
            (r'\bdanger\b', 'DANGER')
        ]
        
        warning_count = 0
        found_warnings = []
        for pattern, label in warning_patterns:
            matches = re.findall(pattern, full_text_lower)
            if matches:
                warning_count += len(matches)
                found_warnings.append(label)
        
        if warning_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Has {warning_count} warning phrases ({', '.join(set(found_warnings))})")
        elif warning_count >= 1:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Has only {warning_count} warning phrase (need at least 2)")
        else:
            feedback_parts.append("❌ Missing warning language (should include 'DO NOT', 'NEVER', etc.)")

        # Criterion 6: Check for emergency contacts section
        has_contact_keyword = ('contact' in full_text_lower or 'call' in full_text_lower or 
                              'phone' in full_text_lower or 'number' in full_text_lower)
        
        # Look for phone number patterns
        phone_patterns = [
            r'\d{3}[-.\s]?\d{3}[-.\s]?\d{4}',  # XXX-XXX-XXXX or similar
            r'\(\d{3}\)\s?\d{3}[-.\s]?\d{4}',  # (XXX) XXX-XXXX
            r'1[-.\s]?800[-.\s]?\d{3}[-.\s]?\d{4}',  # 1-800-XXX-XXXX
        ]
        
        phone_numbers = []
        for pattern in phone_patterns:
            phone_numbers.extend(re.findall(pattern, full_text))
        
        if has_contact_keyword and len(phone_numbers) >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Has emergency contact section with {len(phone_numbers)} phone numbers")
        elif has_contact_keyword and len(phone_numbers) >= 1:
            criteria_passed += 0.75
            feedback_parts.append(f"⚠️ Has emergency contacts with {len(phone_numbers)} phone number (need at least 2)")
        elif has_contact_keyword or len(phone_numbers) >= 1:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Has partial emergency contact info")
        else:
            feedback_parts.append("❌ Missing emergency contact section with phone numbers")

        # Criterion 7: Check document length (should be concise - one page)
        if word_count <= 800:
            criteria_passed += 1
            feedback_parts.append(f"✅ Document is concise ({word_count} words, under 800)")
        elif word_count <= 1000:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Document is a bit long ({word_count} words, should be under 800)")
        else:
            feedback_parts.append(f"❌ Document is too long ({word_count} words, should be under 800 for one page)")

        # Criterion 8: Check for large fonts (accessibility requirement)
        large_font_count = check_for_large_fonts(doc, min_size=14)
        if large_font_count >= 5:  # Multiple elements in large font
            criteria_passed += 1
            feedback_parts.append(f"✅ Uses large fonts for readability ({large_font_count} elements >= 14pt)")
        elif large_font_count >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some large fonts used ({large_font_count} elements >= 14pt)")
        else:
            feedback_parts.append("❌ Needs larger fonts for accessibility (14pt or larger)")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 75% to pass

        feedback = " | ".join(feedback_parts)

        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria passed, score={score}")

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
