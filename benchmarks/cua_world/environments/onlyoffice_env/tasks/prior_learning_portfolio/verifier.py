#!/usr/bin/env python3
"""
Verifier for Prior Learning Portfolio task

This verifier checks that rough notes have been transformed into a
properly formatted academic PLA (Prior Learning Assessment) portfolio.
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
    count_paragraphs,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_prior_learning_portfolio(traj, env_info, task_info):
    """
    Verify PLA portfolio document meets requirements
    
    Checks:
    - Document structure (6 required sections in order)
    - Cover page elements (title, course, student info)
    - Content completeness (key phrases and elements)
    - Table structure (3 columns, 5+ rows for objectives)
    - Formatting (fonts, spacing, structure)
    - Overall professionalism and completeness
    
    Returns:
        dict: {
            "passed": bool,
            "score": int (0-100),
            "feedback": str
        }
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    expected_path = "/home/ga/Documents/TextDocuments/PLA_Portfolio_Final.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_pla_')

    try:
        # Copy and parse document
        success, doc, error = copy_and_parse_document(
            expected_path,
            copy_from_env,
            'docx'
        )
        
        if not success:
            # Check if file exists but has different name
            alt_paths = [
                "/home/ga/Documents/TextDocuments/PLA_Portfolio.docx",
                "/home/ga/Documents/TextDocuments/portfolio_final.docx",
                "/home/ga/Documents/TextDocuments/PLA_rough_notes.docx"
            ]
            
            for alt_path in alt_paths:
                success, doc, error = copy_and_parse_document(
                    alt_path,
                    copy_from_env,
                    'docx'
                )
                if success:
                    logger.info(f"Found document at alternate path: {alt_path}")
                    break
            
            if not success:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Document not found or failed to parse. Expected at {expected_path}. Error: {error}"
                }
        
        score = 0
        feedback_parts = []
        
        # Get full text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Check if document has substantial content
        if len(full_text) < 500:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Document is too short ({len(full_text)} characters). Expected substantial portfolio content (800+ characters)."
            }
        
        # === CRITERION 1: Cover page elements (10 points) ===
        cover_score = 0
        
        # Check for portfolio title
        if "prior learning assessment portfolio" in full_text_lower:
            cover_score += 3
        else:
            feedback_parts.append("❌ Missing portfolio title 'Prior Learning Assessment Portfolio'")
        
        # Check for course identifier
        if "bus 210" in full_text_lower or "bus210" in full_text_lower or "small business management" in full_text_lower:
            cover_score += 2
        else:
            feedback_parts.append("❌ Missing course identifier (BUS 210)")
        
        # Check for student name
        if "maria gutierrez" in full_text_lower:
            cover_score += 3
        else:
            feedback_parts.append("❌ Missing student name (Maria Gutierrez)")
        
        # Check for student ID
        if "23457890" in full_text:
            cover_score += 2
        else:
            feedback_parts.append("❌ Missing student ID (23457890)")
        
        score += cover_score
        
        if cover_score >= 8:
            feedback_parts.append("✅ Cover page complete with required elements")
        else:
            feedback_parts.append(f"⚠️  Cover page incomplete ({cover_score}/10 points)")
        
        # === CRITERION 2: Six required sections present (15 points) ===
        required_sections = [
            ("course learning objectives", "Course Learning Objectives"),
            ("professional experience", "Professional Experience"),
            ("competency evidence matrix", "Competency Evidence Matrix / Competency Mapping"),
            ("reflective analysis", "Reflective Analysis / Reflection"),
            ("appendix", "Appendix")
        ]
        
        sections_found = 0
        missing_sections = []
        
        for section_key, section_display in required_sections:
            if section_key in full_text_lower:
                sections_found += 1
            else:
                missing_sections.append(section_display)
        
        section_score = int((sections_found / len(required_sections)) * 15)
        score += section_score
        
        if sections_found == len(required_sections):
            feedback_parts.append("✅ All 5 required sections present")
        elif sections_found >= 4:
            feedback_parts.append(f"⚠️  Found {sections_found}/5 sections. Missing: {', '.join(missing_sections)}")
        else:
            feedback_parts.append(f"❌ Only found {sections_found}/5 sections. Missing: {', '.join(missing_sections)}")
        
        # === CRITERION 3: Content completeness (25 points) ===
        content_score = 0
        
        # Check for business name
        if "elegant moments" in full_text_lower:
            content_score += 5
        else:
            feedback_parts.append("❌ Missing business name 'Elegant Moments'")
        
        # Check for years of operation
        if "2008" in full_text and "2020" in full_text:
            content_score += 5
        elif "2008" in full_text or "2020" in full_text:
            content_score += 2
            feedback_parts.append("⚠️  Partially missing years (should mention both 2008-2020)")
        else:
            feedback_parts.append("❌ Missing years of operation (2008-2020)")
        
        # Check for supporting documents list
        supporting_docs_score = 0
        if "client contracts" in full_text_lower or "client contract" in full_text_lower:
            supporting_docs_score += 1
        if "vendor agreements" in full_text_lower or "vendor agreement" in full_text_lower:
            supporting_docs_score += 1
        if "budget" in full_text_lower and ("spreadsheet" in full_text_lower or "spreadsheets" in full_text_lower):
            supporting_docs_score += 1
        
        content_score += supporting_docs_score * 2  # 2 points each, max 6
        
        if supporting_docs_score >= 2:
            feedback_parts.append(f"✅ Supporting documents listed ({supporting_docs_score}/3)")
        else:
            feedback_parts.append(f"❌ Insufficient supporting documents listed ({supporting_docs_score}/3)")
        
        # Check for academic language in reflection
        academic_indicators = [
            "applied business theory",
            "theoretical framework",
            "business principles",
            "academic",
            "demonstrates mastery",
            "competency",
            "strategic planning"
        ]
        
        academic_language_found = sum(1 for phrase in academic_indicators if phrase in full_text_lower)
        
        if academic_language_found >= 3:
            content_score += 6
            feedback_parts.append("✅ Academic language present in reflection")
        elif academic_language_found >= 1:
            content_score += 3
            feedback_parts.append("⚠️  Some academic language present, could be stronger")
        else:
            feedback_parts.append("❌ Reflective statement lacks academic language")
        
        # Check for learning objectives (should have 5)
        # Count numbered list items or mentions of objectives
        numbered_objectives = len(re.findall(r'\b[1-5][\.\)]\s+', full_text[:2000]))  # Check first 2000 chars
        
        if numbered_objectives >= 4:
            content_score += 3
            feedback_parts.append(f"✅ Learning objectives formatted as list ({numbered_objectives} found)")
        else:
            feedback_parts.append(f"⚠️  Learning objectives may not be properly formatted as numbered list")
        
        score += content_score
        
        # === CRITERION 4: Table structure (10 points) ===
        table_count = count_tables(doc)
        
        if table_count >= 1:
            table = doc.tables[0]
            num_cols = len(table.columns)
            num_rows = len(table.rows)
            
            table_score = 0
            
            if num_cols == 3:
                table_score += 5
                feedback_parts.append("✅ Competency matrix has correct 3-column structure")
            elif num_cols >= 2:
                table_score += 3
                feedback_parts.append(f"⚠️  Table has {num_cols} columns (expected 3)")
            else:
                feedback_parts.append(f"❌ Table has only {num_cols} column(s), needs 3")
            
            if num_rows >= 5:
                table_score += 5
                feedback_parts.append(f"✅ Table has sufficient rows ({num_rows} rows)")
            elif num_rows >= 3:
                table_score += 3
                feedback_parts.append(f"⚠️  Table has {num_rows} rows (expected at least 5)")
            else:
                feedback_parts.append(f"❌ Table has insufficient rows ({num_rows})")
            
            score += table_score
        else:
            feedback_parts.append("❌ No table found - competency evidence matrix missing")
        
        # === CRITERION 5: Document structure and formatting (25 points) ===
        format_score = 0
        
        # Check paragraph count (should have multiple sections = many paragraphs)
        para_count = count_paragraphs(doc)
        
        if para_count >= 25:
            format_score += 7
            feedback_parts.append(f"✅ Document has good structure ({para_count} paragraphs)")
        elif para_count >= 15:
            format_score += 5
        elif para_count >= 10:
            format_score += 3
        else:
            feedback_parts.append(f"⚠️  Document seems under-developed ({para_count} paragraphs)")
        
        # Check for proper heading formatting (14pt bold)
        # We'll check if major section headings exist with emphasis
        heading_keywords = [
            "Course Learning Objectives",
            "Professional Experience",
            "Competency Evidence Matrix",
            "Reflective Analysis",
            "Appendix"
        ]
        
        bold_headings = 0
        for heading in heading_keywords:
            if check_text_formatting(doc, heading, bold=True):
                bold_headings += 1
        
        if bold_headings >= 4:
            format_score += 7
            feedback_parts.append(f"✅ Section headings properly formatted ({bold_headings}/5 bold)")
        elif bold_headings >= 2:
            format_score += 4
            feedback_parts.append(f"⚠️  Some headings formatted ({bold_headings}/5)")
        else:
            feedback_parts.append("❌ Section headings not properly formatted")
        
        # Check for title formatting (should be bold and larger)
        if check_text_formatting(doc, "Prior Learning Assessment Portfolio", bold=True):
            format_score += 5
            feedback_parts.append("✅ Title properly formatted (bold)")
        elif "prior learning" in full_text_lower:
            format_score += 2
        
        # Award points for overall document length and completeness
        if len(full_text) >= 1500:
            format_score += 6
            feedback_parts.append("✅ Document has substantial content (1500+ characters)")
        elif len(full_text) >= 1000:
            format_score += 4
        elif len(full_text) >= 800:
            format_score += 2
        
        score += format_score
        
        # === CRITERION 6: Document saved properly with correct naming (15 points) ===
        # Already verified by successful parsing at correct path
        save_score = 15
        
        # Slight deduction if saved at alternate location
        if expected_path not in str(success):
            save_score = 12
            feedback_parts.append("⚠️  Document saved but not at exact expected path")
        else:
            feedback_parts.append("✅ Document saved correctly at expected location")
        
        score += save_score
        
        # === FINAL EVALUATION ===
        # Cap score at 100
        score = min(score, 100)
        
        passed = score >= 75
        
        # Compile feedback
        feedback = " | ".join(feedback_parts)
        feedback = f"Score: {score}/100. " + feedback
        
        if passed:
            if score >= 90:
                feedback = "🎓 EXCELLENT! " + feedback + " | Portfolio exceeds university requirements. Maria should receive credit!"
            else:
                feedback = "✅ PASSED! " + feedback + " | Portfolio meets university requirements for review."
        else:
            feedback = "❌ NEEDS REVISION. " + feedback + " | Portfolio does not yet meet submission standards. Maria should revise before deadline."
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
