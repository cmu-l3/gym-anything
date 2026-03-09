#!/usr/bin/env python3
"""
Verifier for household_emergency_binder@1

Verifies that the emergency reference document contains:
1. Main title "HOUSEHOLD EMERGENCY REFERENCE" with proper formatting
2. All 6 required sections
3. At least 2 tables (Emergency Contacts + Medical Information)
4. Proper section heading formatting
5. Specific content indicators for each section
6. Overall document completeness

Scoring:
- Title formatting: 15 points
- Required sections present: 30 points (5 per section)
- Tables present: 25 points
- Section heading formatting: 15 points
- Content indicators: 15 points
Total: 100 points (pass threshold: 70)
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
    check_text_formatting,
    count_tables,
    check_paragraph_alignment,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_section_heading_formatted(doc, section_keywords, min_matches=3):
    """
    Check if section headings are properly formatted (bold, larger font)
    
    Args:
        doc: Document object
        section_keywords: List of keywords that should appear in headings
        min_matches: Minimum number of keywords that should be formatted
        
    Returns:
        Tuple of (formatted_count, details_list)
    """
    formatted_count = 0
    details = []
    
    for keyword in section_keywords:
        # Check for bold formatting
        is_bold = check_text_formatting(doc, keyword, bold=True)
        
        # Check for larger font (14pt or higher)
        is_large_14 = check_text_formatting(doc, keyword, font_size=14)
        is_large_16 = check_text_formatting(doc, keyword, font_size=16)
        is_large_18 = check_text_formatting(doc, keyword, font_size=18)
        
        if is_bold or is_large_14 or is_large_16 or is_large_18:
            formatted_count += 1
            details.append(f"{keyword}:✓")
        else:
            details.append(f"{keyword}:✗")
    
    return formatted_count, details


def verify_emergency_binder(traj, env_info, task_info):
    """
    Verify the household emergency reference document.
    
    Checks:
    1. Document exists and can be parsed
    2. Has main title "HOUSEHOLD EMERGENCY REFERENCE" with proper formatting
    3. Contains all 6 required sections (keyword presence)
    4. Has at least 2 tables
    5. Section headings are formatted properly
    6. Contains specific content indicators
    
    Returns:
        dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }
    
    container_path = "/home/ga/Documents/TextDocuments/emergency_reference.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_emergency_')
    
    try:
        # Copy and parse the document
        logger.info(f"Attempting to copy and parse document from: {container_path}")
        success, doc, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'docx'
        )
        
        if not success:
            logger.error(f"Failed to parse document: {error}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to load or parse document: {error}"
            }
        
        # Extract full text (convert to lowercase for easier matching)
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        logger.info(f"Document text length: {len(full_text)} characters")
        
        # Check if document has substantial content
        if len(full_text.strip()) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Document appears empty or too short ({len(full_text)} characters, expected at least 100)"
            }
        
        # Initialize scoring
        score = 0
        max_score = 100
        feedback_parts = []
        
        # ===================================================================
        # CRITERION 1: Main title exists with proper formatting (15 points)
        # ===================================================================
        title_keywords = ["household emergency reference", "emergency reference", "household emergency"]
        has_title = any(keyword in full_text_lower for keyword in title_keywords)
        
        # Check for title formatting - look for "EMERGENCY" or "HOUSEHOLD" in caps with bold
        title_formatted = False
        title_centered = False
        
        if has_title:
            # Check if any title-related text is bold and large
            title_bold = (
                check_text_formatting(doc, "EMERGENCY", bold=True) or
                check_text_formatting(doc, "Emergency", bold=True) or
                check_text_formatting(doc, "HOUSEHOLD", bold=True)
            )
            
            # Check for 16pt font
            title_size_16 = (
                check_text_formatting(doc, "EMERGENCY", font_size=16) or
                check_text_formatting(doc, "Emergency", font_size=16) or
                check_text_formatting(doc, "REFERENCE", font_size=16)
            )
            
            # Check for larger fonts (18pt, 20pt also acceptable)
            title_size_large = (
                check_text_formatting(doc, "EMERGENCY", font_size=18) or
                check_text_formatting(doc, "Emergency", font_size=18) or
                check_text_formatting(doc, "EMERGENCY", font_size=20)
            )
            
            # Check centering
            title_centered = (
                check_paragraph_alignment(doc, "EMERGENCY", "center") or
                check_paragraph_alignment(doc, "Emergency", "center") or
                check_paragraph_alignment(doc, "HOUSEHOLD", "center")
            )
            
            title_formatted = title_bold and (title_size_16 or title_size_large)
        
        if has_title and title_formatted:
            score += 15
            if title_centered:
                feedback_parts.append("✅ Main title present, formatted (bold, large), and centered")
            else:
                feedback_parts.append("✅ Main title present and formatted (bold, large) but not centered")
        elif has_title:
            score += 7  # Partial credit for having title but not formatted
            feedback_parts.append("⚠️  Main title present but not properly formatted (should be bold, 16pt, centered)")
        else:
            feedback_parts.append("❌ Main title 'HOUSEHOLD EMERGENCY REFERENCE' missing")
        
        # ===================================================================
        # CRITERION 2: Required sections present (30 points - 5 per section)
        # ===================================================================
        required_sections = {
            "emergency contact": ["emergency contact", "contacts", "emergency phone"],
            "meeting point": ["meeting point", "meeting place", "rendezvous", "rally point"],
            "document": ["document", "important papers", "critical documents", "vital records"],
            "pet": ["pet", "animal", "dog", "cat"],
            "medical": ["medical", "health", "medication", "allergy", "allergies"],
            "evacuation": ["evacuation", "route", "escape", "exit"]
        }
        
        sections_found = 0
        missing_sections = []
        found_sections = []
        
        for section_key, section_variations in required_sections.items():
            section_found = any(variation in full_text_lower for variation in section_variations)
            if section_found:
                sections_found += 1
                score += 5
                found_sections.append(section_key)
            else:
                missing_sections.append(section_key)
        
        if sections_found >= 6:
            feedback_parts.append(f"✅ All {sections_found} required sections present")
        elif sections_found >= 4:
            feedback_parts.append(f"⚠️  {sections_found}/6 required sections found. Missing: {', '.join(missing_sections)}")
        else:
            feedback_parts.append(f"❌ Only {sections_found}/6 required sections found. Missing: {', '.join(missing_sections)}")
        
        # ===================================================================
        # CRITERION 3: Tables present (25 points)
        # ===================================================================
        table_count = count_tables(doc)
        logger.info(f"Document contains {table_count} table(s)")
        
        if table_count >= 2:
            score += 25
            feedback_parts.append(f"✅ {table_count} tables present (Emergency Contacts + Medical Info)")
        elif table_count == 1:
            score += 12  # Partial credit
            feedback_parts.append("⚠️  Only 1 table found (need at least 2: Emergency Contacts + Medical Info)")
        else:
            feedback_parts.append("❌ No tables found (should have Emergency Contacts + Medical Info tables)")
        
        # ===================================================================
        # CRITERION 4: Section headings with formatting (15 points)
        # ===================================================================
        section_heading_keywords = [
            "emergency contact", "meeting point", "medical", 
            "document", "evacuation", "pet"
        ]
        
        formatted_headings, heading_details = check_section_heading_formatted(
            doc, 
            section_heading_keywords,
            min_matches=4
        )
        
        logger.info(f"Formatted headings: {formatted_headings}, details: {heading_details}")
        
        if formatted_headings >= 5:
            score += 15
            feedback_parts.append(f"✅ {formatted_headings} section headings properly formatted (bold/large)")
        elif formatted_headings >= 3:
            score += 10  # Partial credit
            feedback_parts.append(f"⚠️  {formatted_headings} section headings formatted (need at least 5)")
        elif formatted_headings >= 1:
            score += 5  # Minimal credit
            feedback_parts.append(f"⚠️  Only {formatted_headings} section heading(s) formatted")
        else:
            feedback_parts.append("❌ Section headings not properly formatted (should be bold, size 14pt)")
        
        # ===================================================================
        # CRITERION 5: Specific content indicators (15 points)
        # ===================================================================
        content_score = 0
        content_details = []
        
        # Emergency contacts indicators (5 points)
        contact_keywords = ["phone", "contact", "call", "mobile", "number", "tel"]
        has_contact_info = any(keyword in full_text_lower for keyword in contact_keywords)
        if has_contact_info:
            content_score += 5
            content_details.append("contacts:✓")
        else:
            content_details.append("contacts:✗")
        
        # Meeting location indicators (5 points)
        location_keywords = ["address", "location", "meet at", "primary", "secondary", "street", "avenue"]
        has_location_info = any(keyword in full_text_lower for keyword in location_keywords)
        if has_location_info:
            content_score += 5
            content_details.append("locations:✓")
        else:
            content_details.append("locations:✗")
        
        # Medical/Health indicators (5 points)
        medical_keywords = ["medication", "allergy", "allergies", "condition", "prescription", "dose"]
        has_medical_info = any(keyword in full_text_lower for keyword in medical_keywords)
        if has_medical_info:
            content_score += 5
            content_details.append("medical:✓")
        else:
            content_details.append("medical:✗")
        
        score += content_score
        
        if content_score >= 15:
            feedback_parts.append(f"✅ All content indicators present ({', '.join(content_details)})")
        elif content_score >= 10:
            feedback_parts.append(f"⚠️  Most content indicators present ({', '.join(content_details)})")
        else:
            feedback_parts.append(f"⚠️  Limited content indicators ({', '.join(content_details)})")
        
        # ===================================================================
        # Final scoring and pass/fail determination
        # ===================================================================
        passed = score >= 70  # Need 70% to pass
        
        # Compile final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" || Final Score: {score}/{max_score}"
        
        logger.info(f"Verification complete: passed={passed}, score={score}/{max_score}")
        
        return {
            "passed": passed,
            "score": score / max_score,  # Normalize to 0-1
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary directory
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything verification system
def verify_task(traj, env_info, task_info):
    """Entry point called by gym-anything framework"""
    return verify_emergency_binder(traj, env_info, task_info)