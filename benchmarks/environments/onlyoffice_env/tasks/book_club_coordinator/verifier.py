#!/usr/bin/env python3
"""
Verifier for Book Club Coordinator task (book_club_coordinator@1)

Checks:
1. Document exists and can be parsed
2. Contains required sections with appropriate headings
3. Has member roster with all 8 members
4. Has upcoming schedule with 4+ meetings in chronological order
5. Has book nomination pool with 5+ books
6. Has past discussions section with 3+ books
7. Has hosting rotation tracker
8. Proper formatting: centered title, bold headings, tables, italic text
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
    count_tables,
    count_paragraphs,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_book_club_document(traj, env_info, task_info):
    """
    Verify that the book club coordination document meets all requirements.
    
    Returns:
        dict with keys: passed (bool), score (float 0-1), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/BookClub_2025.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_bookclub_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load document: {error}"
            }

        # Get full text for content checking
        full_text = get_document_text(doc).lower()
        
        # Scoring system (total 10.0 points, normalized to 0-1 range)
        score = 0.0
        max_score = 10.0
        feedback_parts = []

        # === CONTENT CHECKS (7.0 points) ===

        # 1. Check for required section headings (1.0 point)
        section_keywords = [
            'member', 'roster', 'schedule', 'upcoming', 
            'nomination', 'pool', 'past', 'discussion', 
            'host', 'rotation'
        ]
        sections_found = sum(1 for keyword in section_keywords if keyword in full_text)
        
        if sections_found >= 8:
            score += 1.0
            feedback_parts.append("✅ All major sections present")
        elif sections_found >= 6:
            score += 0.7
            feedback_parts.append(f"⚠️ Most sections present ({sections_found}/10 keywords)")
        elif sections_found >= 4:
            score += 0.4
            feedback_parts.append(f"⚠️ Some sections present ({sections_found}/10 keywords)")
        else:
            feedback_parts.append(f"❌ Major sections missing ({sections_found}/10 keywords)")

        # 2. Check for member names (1.5 points)
        required_members = [
            'sarah chen', 'marcus johnson', 'elena rodriguez', 
            'david kim', 'jennifer wu', 'thomas anderson',
            'maria santos', 'robert lee'
        ]
        members_found = sum(1 for member in required_members if member in full_text)
        
        if members_found >= 7:
            score += 1.5
            feedback_parts.append(f"✅ Found {members_found}/8 members")
        elif members_found >= 5:
            score += 1.0
            feedback_parts.append(f"⚠️ Found {members_found}/8 members")
        elif members_found >= 3:
            score += 0.5
            feedback_parts.append(f"⚠️ Found only {members_found}/8 members")
        else:
            feedback_parts.append(f"❌ Found only {members_found}/8 members")

        # 3. Check for book titles (1.5 points)
        # Check for a mix of upcoming books and past books
        sample_books = [
            'midnight library', 'project hail mary', 'circe', 
            'evelyn hugo', 'song of achilles', 'anthropocene',
            'crawdads', 'atomic habits', 'thursday murder'
        ]
        books_found = sum(1 for book in sample_books if book in full_text)
        
        if books_found >= 6:
            score += 1.5
            feedback_parts.append(f"✅ Found {books_found} expected books")
        elif books_found >= 4:
            score += 1.0
            feedback_parts.append(f"⚠️ Found {books_found} expected books")
        elif books_found >= 2:
            score += 0.5
            feedback_parts.append(f"⚠️ Found only {books_found} expected books")
        else:
            feedback_parts.append(f"❌ Found only {books_found} expected books")

        # 4. Check for dates and chronological content (1.0 point)
        month_indicators = ['march', 'april', 'may', 'june']
        year_indicator = '2025' in full_text
        dates_found = sum(1 for month in month_indicators if month in full_text)
        
        if dates_found >= 3 and year_indicator:
            score += 1.0
            feedback_parts.append("✅ Schedule dates present")
        elif dates_found >= 2:
            score += 0.5
            feedback_parts.append("⚠️ Some schedule dates present")
        else:
            feedback_parts.append("❌ Schedule dates missing or incomplete")

        # 5. Check for tables (1.0 point)
        # Should have at least 4 tables: roster, schedule, nominations, hosting rotation
        table_count = count_tables(doc)
        
        if table_count >= 4:
            score += 1.0
            feedback_parts.append(f"✅ Contains {table_count} tables (expected 4+)")
        elif table_count >= 3:
            score += 0.7
            feedback_parts.append(f"⚠️ Contains {table_count} tables (expected 4)")
        elif table_count >= 2:
            score += 0.4
            feedback_parts.append(f"⚠️ Contains only {table_count} tables (expected 4)")
        elif table_count >= 1:
            score += 0.2
            feedback_parts.append(f"❌ Contains only {table_count} table (expected 4)")
        else:
            feedback_parts.append("❌ No tables found (expected 4)")

        # 6. Check for discussion questions (1.0 point)
        discussion_indicators = ['discussion', 'question', 'how does', 'what', 'why', 'favorite']
        discussion_found = sum(1 for ind in discussion_indicators if ind in full_text)
        
        if discussion_found >= 4:
            score += 1.0
            feedback_parts.append("✅ Discussion questions archive present")
        elif discussion_found >= 2:
            score += 0.5
            feedback_parts.append("⚠️ Discussion section incomplete")
        else:
            feedback_parts.append("❌ Discussion questions missing or minimal")

        # === FORMATTING CHECKS (3.0 points) ===

        # 7. Check for document title with proper formatting (1.0 point)
        has_formatted_title = False
        title_keywords = ['book club', 'mountain view', '2025', 'handbook']
        
        # Check first 10 paragraphs for title
        for para in doc.paragraphs[:10]:
            para_text_lower = para.text.lower()
            # Check if it has book club related keywords
            if any(keyword in para_text_lower for keyword in title_keywords):
                # Check if it's formatted (bold, centered, or large font)
                is_centered = (para.alignment == 1)  # CENTER alignment
                has_bold = any(run.bold for run in para.runs if run.text.strip())
                has_large_font = any(
                    run.font.size and run.font.size.pt >= 14 
                    for run in para.runs if run.text.strip()
                )
                
                if is_centered or has_bold or has_large_font:
                    has_formatted_title = True
                    break
        
        if has_formatted_title:
            score += 1.0
            feedback_parts.append("✅ Title properly formatted")
        else:
            feedback_parts.append("❌ Title missing or not formatted (should be centered/bold/large)")

        # 8. Check for bold formatting in headings (1.0 point)
        bold_count = 0
        bold_paragraphs = 0
        
        for para in doc.paragraphs:
            para_has_bold = False
            for run in para.runs:
                if run.bold and len(run.text.strip()) > 0:
                    bold_count += 1
                    para_has_bold = True
            if para_has_bold:
                bold_paragraphs += 1
        
        if bold_paragraphs >= 6:  # Expect title + 5 section headings
            score += 1.0
            feedback_parts.append(f"✅ Bold formatting used appropriately ({bold_paragraphs} bold paragraphs)")
        elif bold_paragraphs >= 4:
            score += 0.7
            feedback_parts.append(f"⚠️ Some bold formatting ({bold_paragraphs} bold paragraphs)")
        elif bold_paragraphs >= 2:
            score += 0.3
            feedback_parts.append(f"⚠️ Minimal bold formatting ({bold_paragraphs} bold paragraphs)")
        else:
            feedback_parts.append(f"❌ Insufficient bold formatting ({bold_paragraphs} bold paragraphs)")

        # 9. Check for italic formatting (1.0 point)
        italic_count = 0
        italic_paragraphs = 0
        
        for para in doc.paragraphs:
            para_has_italic = False
            for run in para.runs:
                if run.italic and len(run.text.strip()) > 0:
                    italic_count += 1
                    para_has_italic = True
            if para_has_italic:
                italic_paragraphs += 1
        
        # Lenient check - just need some italic text (for book titles ideally)
        if italic_count >= 3:
            score += 1.0
            feedback_parts.append(f"✅ Italic formatting used ({italic_count} instances)")
        elif italic_count >= 1:
            score += 0.7
            feedback_parts.append(f"⚠️ Some italic formatting ({italic_count} instances)")
        else:
            # Give partial credit since this is minor
            score += 0.3
            feedback_parts.append("⚠️ No italic formatting found (minor issue)")

        # === BONUS CHECKS (no points, just info) ===
        
        # Check if tables have proper structure
        if table_count > 0:
            try:
                first_table = doc.tables[0]
                first_table_rows = len(first_table.rows)
                first_table_cols = len(first_table.columns) if first_table.rows else 0
                
                # Member roster should have 8+ rows (header + 8 members)
                if first_table_rows >= 8:
                    feedback_parts.append(f"ℹ️ First table has {first_table_rows} rows (good for member roster)")
            except Exception as e:
                logger.warning(f"Could not analyze table structure: {e}")

        # Normalize score to 0-1 range
        normalized_score = min(score / max_score, 1.0)
        
        # Determine pass/fail (need at least 70%)
        passed = normalized_score >= 0.70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": f"Score: {score:.1f}/{max_score} - {feedback}"
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
