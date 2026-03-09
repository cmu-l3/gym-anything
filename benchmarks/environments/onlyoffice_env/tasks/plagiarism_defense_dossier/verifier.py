#!/usr/bin/env python3
"""
Verifier for plagiarism_defense_dossier@1
Checks that the academic integrity defense document is properly structured
"""

import sys
import os
import logging
import tempfile

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


def verify_plagiarism_defense_dossier(traj, env_info, task_info):
    """
    Verify the academic integrity defense document.
    
    Requirements:
    1. Document exists and is parseable
    2. Title present, bold, 16pt, centered: "Academic Integrity Defense: Authenticity of Term Paper"
    3. Student information section with all 4 required fields
    4. Table with draft progression (at least 4 rows including header, 4 columns)
    5. "Explanation of Quality Improvement" section with specific content
    6. "Supporting Evidence" section with bulleted list
    7. Professional formatting throughout
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/TextDocuments/integrity_defense.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_defense_')
    
    try:
        # Parse document
        success, doc, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            file_format='docx'
        )
        
        if not success or doc is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse document: {error}"
            }
        
        feedback_parts = []
        score = 0
        max_score = 100
        
        feedback_parts.append("✅ Document created and parseable")
        score += 5
        
        # Get all text for content checks
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Check if document still has instruction template (should be removed/replaced)
        if "you may delete these instructions" in full_text_lower:
            feedback_parts.append("⚠️ Warning: Template instructions still present (but continuing verification)")
        
        # ====================================================================
        # Check 1: Title present and formatted (25 points total)
        # ====================================================================
        title_variants = [
            "Academic Integrity Defense: Authenticity of Term Paper",
            "Academic Integrity Defense",
            "Authenticity of Term Paper"
        ]
        
        title_found = False
        title_text_used = None
        for variant in title_variants:
            if variant.lower() in full_text_lower:
                title_found = True
                title_text_used = variant
                break
        
        if title_found:
            feedback_parts.append("✅ Title text present")
            score += 8
            
            # Check formatting: bold (7 points)
            if check_text_formatting(doc, title_text_used, bold=True):
                feedback_parts.append("✅ Title is bold")
                score += 7
            else:
                feedback_parts.append("⚠️ Title should be bold")
                score += 2
            
            # Check font size: 16pt (5 points)
            # Note: Allow 14-18pt range for flexibility
            if (check_text_formatting(doc, title_text_used, font_size=16) or
                check_text_formatting(doc, title_text_used, font_size=14) or
                check_text_formatting(doc, title_text_used, font_size=18)):
                feedback_parts.append("✅ Title has appropriate large font size")
                score += 5
            else:
                feedback_parts.append("⚠️ Title should be 16pt (or similar large size)")
            
            # Check centering (5 points)
            if check_paragraph_alignment(doc, title_text_used, 'center'):
                feedback_parts.append("✅ Title is centered")
                score += 5
            else:
                feedback_parts.append("⚠️ Title should be centered")
                score += 1
        else:
            feedback_parts.append("❌ Title missing or incorrect")
        
        # ====================================================================
        # Check 2: Student information (15 points total)
        # ====================================================================
        required_info = [
            ("jordan martinez", "Student name (Jordan Martinez)"),
            ("847392", "Student ID (847392)"),
            ("soc 301", "Course code (SOC 301)"),
            ("march 15, 2024", "Date (March 15, 2024)")
        ]
        
        info_found = 0
        missing_info = []
        for text_to_find, label in required_info:
            if text_to_find in full_text_lower:
                info_found += 1
            else:
                # Try alternative formats
                if "847392" in text_to_find and "847392" in full_text:
                    info_found += 1
                elif "soc 301" in text_to_find and ("soc301" in full_text_lower or "soc 301" in full_text_lower):
                    info_found += 1
                elif "march 15" in text_to_find and ("3/15/2024" in full_text or "15/03/2024" in full_text or "march 15" in full_text_lower):
                    info_found += 1
                else:
                    missing_info.append(label)
        
        if info_found == 4:
            feedback_parts.append("✅ All student information present (name, ID, course, date)")
            score += 15
        elif info_found >= 3:
            feedback_parts.append(f"⚠️ Most student information present ({info_found}/4 fields)")
            score += 10
        elif info_found >= 2:
            feedback_parts.append(f"⚠️ Partial student information ({info_found}/4 fields)")
            score += 6
        else:
            feedback_parts.append(f"❌ Student information incomplete ({info_found}/4 fields)")
        
        # ====================================================================
        # Check 3: Table with draft progression (25 points total)
        # ====================================================================
        table_count = count_tables(doc)
        if table_count >= 1:
            feedback_parts.append("✅ Table present in document")
            score += 8
            
            # Get the first table (most likely the draft progression table)
            table = doc.tables[0]
            rows = len(table.rows)
            cols = len(table.columns)
            
            # Check table dimensions (7 points)
            if rows >= 4:
                feedback_parts.append(f"✅ Table has adequate rows ({rows} rows, expected 4+)")
                score += 4
            else:
                feedback_parts.append(f"⚠️ Table has only {rows} rows (expected 4: header + 3 drafts)")
                score += 1
            
            if cols >= 4:
                feedback_parts.append(f"✅ Table has 4+ columns ({cols} columns)")
                score += 3
            else:
                feedback_parts.append(f"⚠️ Table has only {cols} columns (expected 4)")
            
            # Check for key table content (10 points)
            table_text = ""
            for row in table.rows:
                for cell in row.cells:
                    table_text += cell.text.lower() + " "
            
            # Check for column headers
            has_draft_col = "draft" in table_text
            has_date_col = "date" in table_text
            has_count_col = "word count" in table_text or "count" in table_text
            has_changes_col = "changes" in table_text or "key" in table_text
            
            header_score = sum([has_draft_col, has_date_col, has_count_col, has_changes_col])
            if header_score >= 3:
                feedback_parts.append(f"✅ Table has appropriate column headers ({header_score}/4)")
                score += 5
            else:
                feedback_parts.append(f"⚠️ Table missing some column headers ({header_score}/4)")
                score += 2
            
            # Check for draft data content
            has_draft1 = "draft 1" in table_text or "draft 2" in table_text or "final" in table_text
            has_feb_dates = "feb" in table_text or "february" in table_text or "march" in table_text
            has_numbers = any(num in table_text for num in ["2800", "2,800", "4100", "4,100", "4950", "4,950"])
            
            content_score = sum([has_draft1, has_feb_dates, has_numbers])
            if content_score >= 2:
                feedback_parts.append(f"✅ Table contains draft progression data")
                score += 5
            else:
                feedback_parts.append(f"⚠️ Table appears incomplete or missing data")
                score += 1
        else:
            feedback_parts.append("❌ No table found in document")
        
        # ====================================================================
        # Check 4: "Explanation of Quality Improvement" section (20 points total)
        # ====================================================================
        explanation_variants = [
            "explanation of quality improvement",
            "quality improvement",
            "explanation"
        ]
        
        explanation_found = False
        for variant in explanation_variants:
            if variant in full_text_lower:
                explanation_found = True
                break
        
        if explanation_found:
            feedback_parts.append("✅ 'Explanation of Quality Improvement' section present")
            score += 7
            
            # Check if formatted as heading (bold) (5 points)
            if check_text_formatting(doc, "Explanation", bold=True) or \
               check_text_formatting(doc, "Quality Improvement", bold=True):
                feedback_parts.append("✅ Section heading is bold")
                score += 5
            else:
                feedback_parts.append("⚠️ Section heading should be bold")
                score += 1
            
            # Check for key content phrases (8 points)
            key_phrases = [
                ("writing center", "Writing Center mentioned"),
                ("sarah chen", "Tutor Sarah Chen mentioned"),
                ("additional sources", "Additional sources mentioned"),
                ("legitimate", "Legitimacy explanation provided")
            ]
            
            phrases_found = 0
            for phrase, description in key_phrases:
                if phrase in full_text_lower:
                    phrases_found += 1
            
            if phrases_found >= 3:
                feedback_parts.append(f"✅ Explanation contains key details ({phrases_found}/4 elements)")
                score += 8
            elif phrases_found >= 2:
                feedback_parts.append(f"⚠️ Explanation has some key details ({phrases_found}/4 elements)")
                score += 5
            else:
                feedback_parts.append(f"⚠️ Explanation missing key details ({phrases_found}/4 elements)")
                score += 2
        else:
            feedback_parts.append("❌ 'Explanation of Quality Improvement' section missing")
        
        # ====================================================================
        # Check 5: "Supporting Evidence" section with bullets (15 points total)
        # ====================================================================
        evidence_variants = [
            "supporting evidence",
            "evidence",
            "support"
        ]
        
        evidence_found = False
        for variant in evidence_variants:
            if variant in full_text_lower:
                evidence_found = True
                break
        
        if evidence_found:
            feedback_parts.append("✅ 'Supporting Evidence' section present")
            score += 5
            
            # Check for bold heading (3 points)
            if check_text_formatting(doc, "Supporting Evidence", bold=True) or \
               check_text_formatting(doc, "Evidence", bold=True):
                feedback_parts.append("✅ Evidence heading is bold")
                score += 3
            else:
                feedback_parts.append("⚠️ Evidence heading should be bold")
                score += 1
            
            # Check for evidence items (7 points)
            evidence_items = [
                ("writing center", "Writing Center receipts"),
                ("draft files", "Draft files"),
                ("browser history", "Browser history"),
                ("email", "Email correspondence")
            ]
            
            items_found = 0
            for item, description in evidence_items:
                if item in full_text_lower:
                    items_found += 1
            
            if items_found >= 3:
                feedback_parts.append(f"✅ Supporting evidence list contains required items ({items_found}/4)")
                score += 7
            elif items_found >= 2:
                feedback_parts.append(f"⚠️ Supporting evidence list partially complete ({items_found}/4 items)")
                score += 4
            else:
                feedback_parts.append(f"⚠️ Supporting evidence list incomplete ({items_found}/4 items)")
                score += 1
        else:
            feedback_parts.append("❌ 'Supporting Evidence' section missing")
        
        # Final assessment
        passed = score >= 70  # 70% threshold for passing
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: Score={score}/{max_score}, Passed={passed}")
        
        return {
            "passed": passed,
            "score": score / max_score,
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
        cleanup_temp_dir(temp_dir)
