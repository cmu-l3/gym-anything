#!/usr/bin/env python3
"""
Verifier for IEP Meeting Prep task
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
    check_paragraph_alignment,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_iep_meeting_prep(traj, env_info, task_info):
    """
    Verify that IEP Meeting Preparation Document was formatted correctly.

    Checks:
    1. Title present with proper formatting (18pt, bold, centered)
    2. Four required section headings present (14pt, bold)
    3. Table exists with 4 columns in Current Performance Data section
    4. Numbered list in Areas of Concern (3+ items)
    5. Bulleted list in Requested Accommodations (4+ items) with bold text
    6. Measurable goal with bold skill, measurable criterion, and timeframe
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/IEP_Meeting_Prep.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_iep_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        score = 0
        feedback_parts = []
        full_text = get_document_text(doc).lower()

        # ===== Check 1: Title presence and formatting (10 points) =====
        title_keywords_present = ("iep" in full_text and "meeting" in full_text and 
                                 "preparation" in full_text and "elijah" in full_text and 
                                 "rodriguez" in full_text)
        
        if title_keywords_present:
            # Check formatting - look for bold text near the top
            title_formatted = False
            title_centered = False
            
            # Check first few paragraphs for the title
            for i, para in enumerate(doc.paragraphs[:5]):
                para_text = para.text.lower()
                if "iep" in para_text and "elijah" in para_text:
                    # Check if text is bold
                    for run in para.runs:
                        if run.bold and ("iep" in run.text.lower() or "elijah" in run.text.lower()):
                            title_formatted = True
                            break
                    
                    # Check alignment
                    if para.alignment == 1:  # CENTER
                        title_centered = True
                    
                    break
            
            if title_formatted and title_centered:
                score += 10
                feedback_parts.append("✅ Title properly formatted (bold, centered)")
            elif title_formatted or title_centered:
                score += 5
                feedback_parts.append("⚠️ Title partially formatted (missing bold or center)")
            else:
                score += 2
                feedback_parts.append("⚠️ Title present but not formatted correctly")
        else:
            feedback_parts.append("❌ Title missing key elements")

        # ===== Check 2: Four main sections present (20 points - 5 each) =====
        required_sections = [
            ("current performance data", "performance"),
            ("areas of concern", "concern"),
            ("requested accommodations", "accommodation"),
            ("proposed measurable goal", "goal")
        ]
        
        sections_found = 0
        sections_bold = 0
        
        for full_name, short_name in required_sections:
            if full_name in full_text or short_name in full_text:
                sections_found += 1
                
                # Check if section heading is bold
                for para in doc.paragraphs:
                    if short_name in para.text.lower():
                        for run in para.runs:
                            if run.bold and short_name in run.text.lower():
                                sections_bold += 1
                                break
                        break
        
        section_score = (sections_found * 3) + (sections_bold * 2)
        score += min(section_score, 20)
        
        if sections_found == 4:
            feedback_parts.append(f"✅ All 4 sections present ({sections_bold} bold)")
        else:
            feedback_parts.append(f"❌ Only {sections_found}/4 required sections found")

        # ===== Check 3: Table exists with proper structure (20 points) =====
        table_count = count_tables(doc)
        
        if table_count >= 1:
            score += 12
            feedback_parts.append("✅ Table created")
            
            # Check table structure
            try:
                table = doc.tables[0]
                col_count = len(table.columns)
                row_count = len(table.rows)
                
                if col_count >= 4:
                    score += 5
                    feedback_parts.append(f"✅ Table has {col_count} columns (need 4+)")
                else:
                    score += 2
                    feedback_parts.append(f"⚠️ Table has only {col_count} columns (need 4)")
                
                if row_count >= 3:
                    score += 3
                    feedback_parts.append(f"✅ Table has {row_count} rows (data organized)")
                else:
                    score += 1
                    feedback_parts.append(f"⚠️ Table has only {row_count} rows")
                    
            except Exception as e:
                logger.warning(f"Could not verify table structure: {e}")
                feedback_parts.append("⚠️ Table exists but structure unclear")
        else:
            feedback_parts.append("❌ No table found in document")

        # ===== Check 4: Numbered list in Areas of Concern (15 points) =====
        numbered_list_score = check_for_numbered_list(doc, full_text, "concern")
        score += numbered_list_score
        
        if numbered_list_score >= 12:
            feedback_parts.append("✅ Numbered list found in Areas of Concern (3+ items)")
        elif numbered_list_score >= 8:
            feedback_parts.append("⚠️ Numbered list found but may have <3 items")
        else:
            feedback_parts.append("❌ No proper numbered list in Areas of Concern")

        # ===== Check 5: Bulleted list with bold items in Accommodations (15 points) =====
        bullet_score = check_for_bulleted_list_with_bold(doc, full_text, "accommodation")
        score += bullet_score
        
        if bullet_score >= 12:
            feedback_parts.append("✅ Bulleted list with bold items (4+ accommodations)")
        elif bullet_score >= 8:
            feedback_parts.append("⚠️ Bulleted list present but formatting incomplete")
        else:
            feedback_parts.append("❌ No proper bulleted list in Accommodations")

        # ===== Check 6: Measurable goal components (20 points) =====
        goal_score = check_measurable_goal(doc, full_text, "goal")
        score += goal_score
        
        if goal_score >= 15:
            feedback_parts.append("✅ Measurable goal with all components")
        elif goal_score >= 10:
            feedback_parts.append("⚠️ Goal present but missing some components")
        else:
            feedback_parts.append("❌ Goal not properly structured as SMART goal")

        # Determine pass/fail (75% threshold)
        passed = score >= 75
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": f"Score: {score}/100. {feedback}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)


def check_for_numbered_list(doc, full_text, section_keyword):
    """
    Check if there's a numbered list in the specified section.
    Returns score 0-15.
    """
    score = 0
    
    # Extract section text
    section_text = extract_section_between_keywords(full_text, section_keyword, 
                                                    ["accommodation", "goal", "proposed"])
    
    if not section_text:
        return 0
    
    # Look for numbered list patterns
    numbered_patterns = [
        r'\b1[\.\)]\s+',
        r'\b2[\.\)]\s+',
        r'\b3[\.\)]\s+',
        r'\b①',
        r'\b②',
        r'\b③'
    ]
    
    matches = 0
    for pattern in numbered_patterns:
        if re.search(pattern, section_text):
            matches += 1
    
    if matches >= 3:
        score = 15
    elif matches >= 2:
        score = 10
    elif matches >= 1:
        score = 5
    
    return score


def check_for_bulleted_list_with_bold(doc, full_text, section_keyword):
    """
    Check for bulleted list with bold items in the specified section.
    Returns score 0-15.
    """
    score = 0
    
    # Find section in document
    in_section = False
    bullet_count = 0
    bold_count = 0
    
    for para in doc.paragraphs:
        para_lower = para.text.lower()
        
        # Check if we're entering the section
        if section_keyword in para_lower:
            in_section = True
            continue
        
        # Check if we're leaving the section
        if in_section and para_lower.strip() and any(keyword in para_lower for keyword in ["goal", "proposed", "measurable"]):
            break
        
        if in_section:
            # Check for bullet indicators
            text = para.text.strip()
            if text and (text.startswith('•') or text.startswith('-') or text.startswith('*') or 
                        para.text.startswith('  -') or para.text.startswith('    •')):
                bullet_count += 1
                
                # Check if any run in this paragraph is bold
                for run in para.runs:
                    if run.bold and run.text.strip():
                        bold_count += 1
                        break
    
    # Score based on bullets and bold
    if bullet_count >= 4:
        score += 8
    elif bullet_count >= 3:
        score += 6
    elif bullet_count >= 2:
        score += 3
    
    if bold_count >= 3:
        score += 7
    elif bold_count >= 2:
        score += 4
    elif bold_count >= 1:
        score += 2
    
    return min(score, 15)


def check_measurable_goal(doc, full_text, section_keyword):
    """
    Check if the goal section has measurable components.
    Returns score 0-20.
    """
    score = 0
    
    # Extract goal section text
    section_text = extract_section_between_keywords(full_text, section_keyword, 
                                                    ["end of document", "zzzzz"])
    
    if not section_text or len(section_text) < 20:
        return 0
    
    # Check 1: Has bold text in goal section (indicates skill/behavior) - 7 points
    in_goal_section = False
    has_bold_in_goal = False
    
    for para in doc.paragraphs:
        para_lower = para.text.lower()
        
        if "goal" in para_lower and ("measurable" in para_lower or "proposed" in para_lower):
            in_goal_section = True
            continue
        
        if in_goal_section and para.text.strip():
            for run in para.runs:
                if run.bold and run.text.strip():
                    has_bold_in_goal = True
                    break
            if has_bold_in_goal:
                break
    
    if has_bold_in_goal:
        score += 7
    
    # Check 2: Has measurable criterion (numbers, percentages, ratios) - 7 points
    measurable_patterns = [
        r'\d+%',  # Percentage
        r'\d+\s*out\s*of\s*\d+',  # X out of Y
        r'\d+/\d+',  # X/Y
        r'accuracy',
        r'trial',
        r'\d+\s*times',
        r'at least \d+',
        r'minimum \d+',
        r'\d+\s*correct'
    ]
    
    has_measurable = False
    for pattern in measurable_patterns:
        if re.search(pattern, section_text, re.IGNORECASE):
            has_measurable = True
            break
    
    if has_measurable:
        score += 7
    
    # Check 3: Has timeframe - 6 points
    timeframe_patterns = [
        r'by\s+\w+\s+\d{4}',  # by Month 2024
        r'by\s+the\s+end\s+of',
        r'q[1-4]',  # Q1, Q2, etc
        r'quarter',
        r'within\s+\d+\s+(week|month|day)',
        r'2025',
        r'2024',
        r'by\s+(january|february|march|april|may|june|july|august|september|october|november|december)'
    ]
    
    has_timeframe = False
    for pattern in timeframe_patterns:
        if re.search(pattern, section_text, re.IGNORECASE):
            has_timeframe = True
            break
    
    if has_timeframe:
        score += 6
    
    return score


def extract_section_between_keywords(text, start_keyword, end_keywords):
    """
    Extract text between start keyword and any of the end keywords.
    """
    start_idx = text.find(start_keyword)
    if start_idx == -1:
        return ""
    
    # Find the earliest end keyword
    end_idx = len(text)
    for end_keyword in end_keywords:
        idx = text.find(end_keyword, start_idx + len(start_keyword))
        if idx != -1 and idx < end_idx:
            end_idx = idx
    
    return text[start_idx:end_idx]