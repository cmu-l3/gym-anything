#!/usr/bin/env python3
"""
Verifier for apartment_condition_dispute@1
Checks document structure, content accuracy, and professional formatting
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


def verify_apartment_dispute(traj, env_info, task_info):
    """
    Verify the apartment condition dispute document.
    
    Scoring breakdown (100 points total):
    - Header structure: 25 points
    - Table structure: 30 points
    - Content accuracy: 30 points
    - Summary section: 15 points
    
    Minimum passing score: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/apartment_dispute/output.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_dispute_')
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load document: {error}. Ensure document is saved as DOCX."
            }
        
        # Get full document text for content checking
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # ===== SECTION 1: Header Structure (25 points) =====
        header_score = 0
        
        # Check for title with unit number (6 points)
        has_dispute_title = "apartment condition dispute" in full_text_lower or "condition dispute" in full_text_lower
        has_unit = "unit 4b" in full_text_lower or "unit 4-b" in full_text_lower or "unit4b" in full_text_lower
        
        if has_dispute_title and has_unit:
            header_score += 6
            feedback_parts.append("✅ Document title with unit number found")
        elif has_dispute_title or has_unit:
            header_score += 3
            feedback_parts.append("⚠️  Partial header found (missing title or unit number)")
        else:
            feedback_parts.append("❌ Missing document title with unit number")
        
        # Check for move-in and move-out dates (6 points)
        has_move_in_date = any(term in full_text_lower for term in ["january 15", "jan 15", "1/15/2023", "01/15/2023", "2023-01-15"])
        has_move_out_date = any(term in full_text_lower for term in ["july 31", "jul 31", "7/31/2024", "07/31/2024", "2024-07-31"])
        
        if has_move_in_date and has_move_out_date:
            header_score += 6
            feedback_parts.append("✅ Move-in and move-out dates present")
        elif has_move_in_date or has_move_out_date:
            header_score += 3
            feedback_parts.append("⚠️  Only one date found (need both move-in and move-out)")
        else:
            feedback_parts.append("❌ Missing move-in/move-out dates")
        
        # Check for centered header (7 points)
        header_centered = False
        for i, para in enumerate(doc.paragraphs[:7]):  # Check first 7 paragraphs
            para_text = para.text.lower()
            if ("dispute" in para_text or "unit" in para_text) and len(para_text.strip()) > 5:
                if para.alignment == 1:  # CENTER alignment
                    header_centered = True
                    break
        
        if header_centered:
            header_score += 7
            feedback_parts.append("✅ Header is centered")
        else:
            feedback_parts.append("❌ Header should be centered")
        
        # Check for bold header (6 points)
        header_bold = False
        for i, para in enumerate(doc.paragraphs[:7]):
            para_text = para.text.lower()
            if ("dispute" in para_text or "unit" in para_text) and len(para_text.strip()) > 5:
                for run in para.runs:
                    if run.bold and len(run.text.strip()) > 3:
                        header_bold = True
                        break
                if header_bold:
                    break
        
        if header_bold:
            header_score += 6
            feedback_parts.append("✅ Header is bold")
        else:
            feedback_parts.append("❌ Header should be bold")
        
        score += header_score
        
        # ===== SECTION 2: Table Structure (30 points) =====
        table_score = 0
        
        num_tables = count_tables(doc)
        
        if num_tables >= 1:
            table_score += 5
            feedback_parts.append(f"✅ Table found (document has {num_tables} table(s))")
            
            table = doc.tables[0]
            num_rows = len(table.rows)
            num_cols = len(table.columns)
            
            # Check for 5 columns (10 points)
            if num_cols >= 5:
                table_score += 10
                feedback_parts.append(f"✅ Table has 5+ columns ({num_cols} found)")
            elif num_cols >= 4:
                table_score += 5
                feedback_parts.append(f"⚠️  Table has {num_cols} columns (5 recommended)")
            else:
                feedback_parts.append(f"❌ Table has only {num_cols} columns (need 5)")
            
            # Check for at least 6 rows - header + 5 data rows (10 points)
            if num_rows >= 6:
                table_score += 10
                feedback_parts.append(f"✅ Table has adequate rows ({num_rows} total)")
            elif num_rows >= 4:
                table_score += 5
                feedback_parts.append(f"⚠️  Table has {num_rows} rows (6+ recommended for all locations)")
            else:
                feedback_parts.append(f"❌ Table has only {num_rows} rows (need 6+)")
            
            # Check for appropriate column headers (5 points)
            if num_rows >= 1:
                header_row_text = " ".join([cell.text.lower() for cell in table.rows[0].cells])
                
                required_terms = ["location", "move", "charge", "position"]
                terms_found = sum(1 for term in required_terms if term in header_row_text)
                
                if terms_found >= 3:
                    table_score += 5
                    feedback_parts.append(f"✅ Table headers look appropriate ({terms_found}/4 key terms)")
                elif terms_found >= 2:
                    table_score += 2
                    feedback_parts.append(f"⚠️  Table headers partially present ({terms_found}/4 key terms)")
                else:
                    feedback_parts.append("❌ Table headers unclear or missing")
        else:
            feedback_parts.append("❌ No comparison table found (critical requirement)")
        
        score += table_score
        
        # ===== SECTION 3: Content Accuracy (30 points) =====
        content_score = 0
        
        # Check for required locations (15 points - 3 each)
        required_locations = {
            "kitchen": ["kitchen", "cabinet"],
            "bedroom": ["bedroom", "carpet"],
            "bathroom": ["bathroom", "grout"],
            "living": ["living", "room", "wall"],
            "window": ["window", "screen"]
        }
        
        locations_found = 0
        for location_key, search_terms in required_locations.items():
            if any(term in full_text_lower for term in search_terms):
                locations_found += 1
        
        content_score += (locations_found * 3)
        if locations_found >= 5:
            feedback_parts.append(f"✅ All 5 required locations mentioned")
        elif locations_found >= 3:
            feedback_parts.append(f"⚠️  Found {locations_found}/5 required locations")
        else:
            feedback_parts.append(f"❌ Only {locations_found}/5 required locations found")
        
        # Check for disputed charges with dollar amounts (7 points)
        dollar_pattern = r'\$\s*\d+'
        dollar_matches = re.findall(dollar_pattern, full_text)
        
        if len(dollar_matches) >= 5:
            content_score += 7
            feedback_parts.append(f"✅ Multiple dollar amounts present ({len(dollar_matches)} found)")
        elif len(dollar_matches) >= 3:
            content_score += 4
            feedback_parts.append(f"⚠️  Some dollar amounts present ({len(dollar_matches)} found)")
        else:
            feedback_parts.append(f"❌ Few or no dollar amounts in document")
        
        # Check for rebuttal/position language (8 points)
        rebuttal_terms = [
            "pre-existing", "pre existing", "already present", "already damaged",
            "normal wear", "wear and tear", "noted", "prior", "before", 
            "move-in", "documented", "unfair"
        ]
        
        rebuttals_found = sum(1 for term in rebuttal_terms if term in full_text_lower)
        
        if rebuttals_found >= 3:
            content_score += 8
            feedback_parts.append(f"✅ Strong rebuttal language present ({rebuttals_found} terms)")
        elif rebuttals_found >= 2:
            content_score += 4
            feedback_parts.append(f"⚠️  Some rebuttal language ({rebuttals_found} terms)")
        else:
            feedback_parts.append("❌ Weak rebuttal language - need to reference pre-existing conditions")
        
        score += content_score
        
        # ===== SECTION 4: Summary Section (15 points) =====
        summary_score = 0
        
        # Check for summary section (5 points)
        has_summary = "summary" in full_text_lower
        
        if has_summary:
            summary_score += 5
            feedback_parts.append("✅ Summary section found")
            
            # Check for total amount (5 points)
            has_total = "800" in full_text or "total" in full_text_lower
            if has_total:
                summary_score += 5
                feedback_parts.append("✅ Summary mentions total disputed amount")
            else:
                feedback_parts.append("⚠️  Summary should mention total disputed amount")
            
            # Check for wear and tear language (5 points)
            has_wear_language = "normal wear" in full_text_lower or "wear and tear" in full_text_lower
            if has_wear_language:
                summary_score += 5
                feedback_parts.append("✅ Summary addresses normal wear and tear")
            else:
                feedback_parts.append("⚠️  Summary should address normal wear and tear")
        else:
            feedback_parts.append("❌ No summary section found")
        
        score += summary_score
        
        # ===== Final Assessment =====
        normalized_score = score / max_score
        passed = score >= 70
        
        # Check for profanity or aggressive language (would reduce score)
        aggressive_terms = ["stupid", "idiot", "scam", "theft", "stealing", "liar", "lawsuit"]
        has_aggressive = any(term in full_text_lower for term in aggressive_terms)
        
        if has_aggressive:
            feedback_parts.append("⚠️  Document contains overly aggressive language - maintain professional tone")
        
        feedback = " | ".join(feedback_parts)
        feedback += f" || TOTAL SCORE: {score}/{max_score} points"
        
        if passed:
            feedback += " || ✓ PASSED - Document meets requirements for security deposit dispute"
        else:
            feedback += " || ✗ FAILED - Document needs improvement for professional use"
        
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
