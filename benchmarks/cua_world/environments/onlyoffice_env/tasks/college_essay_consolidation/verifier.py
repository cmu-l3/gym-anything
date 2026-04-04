#!/usr/bin/env python3
"""
Verifier for College Essay Consolidation task

This verifier checks that the student has created a comprehensive essay tracker
that consolidates information from multiple essay draft files, organizes them by
application deadline, tracks word counts, and flags essays that need editing.
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, Any, Tuple, List

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


def verify_essay_tracker(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that the college essay tracker document was created correctly.

    Binary Requirements (must pass all):
    1. File exists and can be parsed
    2. Contains title section with "Essay Tracker" and "Maya Chen"
    3. Has at least one table with 5+ rows
    4. Contains deadline information (Berkeley Nov 30, MIT Jan 1, Michigan Feb 1)
    5. Has word count tracking (multiple numbers in 200-700 range plus status indicators)
    6. Contains substantial essay content (document > 1500 words)
    7. Has organizational structure (3+ headings, lists present)

    Partial Credit Scoring (after binary checks pass):
    - Table Quality (30 points): headers, data rows, status indicators
    - Deadline Organization (20 points): chronological order, all schools mentioned
    - Essay Content (25 points): multiple essays included, proper labeling
    - Word Count Accuracy (15 points): correctly identifies essays needing trimming
    - Action Items (10 points): includes priority action list
    - Document Formatting (10 points): professional appearance, visual hierarchy
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/Applications/essay_tracker.docx"
    temp_dir = None

    try:
        temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_essay_')
        
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(
            container_path,
            copy_from_env,
            'docx'
        )

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Document not found or failed to parse: {error}"
            }

        # Extract all text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        logger.info(f"Document loaded successfully. Length: {len(full_text)} characters")

        # Initialize scoring
        score = 0
        feedback_parts = []
        binary_checks_passed = True

        # ===================================================================
        # BINARY CHECKS (must pass all to get any credit)
        # ===================================================================

        # Binary Check 1: Title section with "Essay Tracker" and "Maya Chen"
        has_tracker_title = (
            "essay tracker" in full_text_lower or
            "college application" in full_text_lower or
            "application tracker" in full_text_lower
        )
        has_maya_chen = "maya chen" in full_text_lower or "maya" in full_text_lower

        if not (has_tracker_title and has_maya_chen):
            binary_checks_passed = False
            feedback_parts.append(
                "❌ Missing title section (should contain 'Essay Tracker' and 'Maya Chen')"
            )
        else:
            feedback_parts.append("✅ Title section present with student name")

        # Binary Check 2: Table exists with at least 5 rows
        table_count = count_tables(doc)
        has_sufficient_table = False
        
        if table_count < 1:
            binary_checks_passed = False
            feedback_parts.append("❌ No table found (need essay tracking table)")
        else:
            # Check if any table has at least 5 rows (1 header + 4 data rows minimum)
            for table in doc.tables:
                if len(table.rows) >= 5:
                    has_sufficient_table = True
                    break
            
            if has_sufficient_table:
                feedback_parts.append(f"✅ Found table with sufficient rows ({table_count} table(s) total)")
            else:
                binary_checks_passed = False
                max_rows = max([len(t.rows) for t in doc.tables]) if doc.tables else 0
                feedback_parts.append(
                    f"❌ Table too small (found {max_rows} rows, need at least 5)"
                )

        # Binary Check 3: Deadline information present
        has_berkeley_nov = (
            ("nov 30" in full_text_lower or "november 30" in full_text_lower) and
            "berkeley" in full_text_lower
        )
        has_mit_jan = "jan 1" in full_text_lower and "mit" in full_text_lower
        has_michigan_feb = (
            ("feb 1" in full_text_lower or "february 1" in full_text_lower) and
            "michigan" in full_text_lower
        )

        deadline_count = sum([has_berkeley_nov, has_mit_jan, has_michigan_feb])
        
        if deadline_count < 2:
            binary_checks_passed = False
            feedback_parts.append(
                f"❌ Missing deadline information (found {deadline_count}/3 key deadlines)"
            )
        else:
            feedback_parts.append(
                f"✅ Deadline information present ({deadline_count}/3 key dates verified)"
            )

        # Binary Check 4: Word count tracking
        # Look for numbers in the typical word count range (200-700)
        numbers_in_text = re.findall(r'\b([2-7]\d{2})\b', full_text)
        word_count_numbers = [int(n) for n in numbers_in_text if 200 <= int(n) <= 700]
        
        # Look for status indicators
        status_indicators = [
            "trim", "ok", "add", "over", "under", "✓", "⚠", "✅", "❌",
            "meets", "exceeds", "sufficient", "too long", "too short"
        ]
        has_status_indicators = any(
            indicator in full_text_lower for indicator in status_indicators
        )

        has_word_count_tracking = len(word_count_numbers) >= 3 and has_status_indicators

        if not has_word_count_tracking:
            binary_checks_passed = False
            feedback_parts.append(
                f"❌ Insufficient word count tracking (found {len(word_count_numbers)} counts, "
                f"status indicators: {has_status_indicators})"
            )
        else:
            feedback_parts.append(
                f"✅ Word count tracking present ({len(word_count_numbers)} word counts found)"
            )

        # Binary Check 5: Essay content included (substantial text)
        word_count = len(full_text.split())
        has_substantial_content = word_count > 1500

        # Also check for multiple essay indicators
        essay_keywords = [
            "personal statement", "community", "northwestern", "berkeley",
            "leadership", "creative", "brown", "essay"
        ]
        essay_keyword_count = sum(
            1 for keyword in essay_keywords if keyword in full_text_lower
        )

        if not has_substantial_content or essay_keyword_count < 4:
            binary_checks_passed = False
            feedback_parts.append(
                f"❌ Insufficient essay content (document: {word_count} words, "
                f"essay indicators: {essay_keyword_count}/8)"
            )
        else:
            feedback_parts.append(
                f"✅ Essay content included (document: {word_count} words, "
                f"{essay_keyword_count} essay types found)"
            )

        # Binary Check 6: Organizational structure (headings and lists)
        heading_count = 0
        list_item_count = 0
        
        for para in doc.paragraphs:
            # Check for heading styles
            if para.style.name.startswith('Heading'):
                heading_count += 1
            # Check for bold text that might be section headers
            elif para.runs and len(para.text.strip()) > 0:
                if para.runs[0].bold and len(para.text) < 100:
                    heading_count += 1
            
            # Check for list items
            if para.style.name.startswith('List') or para.text.strip().startswith(('•', '-', '·')):
                list_item_count += 1

        has_organization = heading_count >= 3 and (list_item_count >= 3 or "•" in full_text)

        if not has_organization:
            binary_checks_passed = False
            feedback_parts.append(
                f"❌ Weak organizational structure (headings: {heading_count}, "
                f"list items: {list_item_count})"
            )
        else:
            feedback_parts.append(
                f"✅ Good organizational structure ({heading_count} headings, "
                f"{list_item_count} list items)"
            )

        # If binary checks failed, return immediately with score 0
        if not binary_checks_passed:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        # ===================================================================
        # PARTIAL CREDIT SCORING (only if binary checks passed)
        # ===================================================================

        # Table Quality (30 points)
        table_score = 0
        if table_count >= 1:
            main_table = doc.tables[0]
            
            # Check for appropriate column headers (10 pts)
            if len(main_table.rows) > 0:
                header_row = main_table.rows[0]
                header_text = ' '.join([cell.text.lower() for cell in header_row.cells])
                
                header_keywords = ["essay", "word", "count", "status", "school", "limit"]
                matching_keywords = sum(1 for kw in header_keywords if kw in header_text)
                
                if matching_keywords >= 3:
                    table_score += 10
                    feedback_parts.append("✅ Table has appropriate column headers")
                elif matching_keywords >= 2:
                    table_score += 5
                    feedback_parts.append("⚠️  Table headers partially complete")
            
            # Check for sufficient data rows (10 pts)
            data_rows = len(main_table.rows) - 1  # Exclude header
            if data_rows >= 6:
                table_score += 10
                feedback_parts.append(f"✅ Table contains {data_rows} essay entries")
            elif data_rows >= 4:
                table_score += 7
                feedback_parts.append(f"⚠️  Table contains {data_rows} entries (expected 6+)")
            elif data_rows >= 2:
                table_score += 3
            
            # Check for status indicators in table (10 pts)
            table_full_text = '\n'.join([
                ' '.join([cell.text for cell in row.cells])
                for row in main_table.rows
            ])
            table_text_lower = table_full_text.lower()
            
            status_in_table = any(
                indicator in table_text_lower
                for indicator in ["trim", "ok", "add", "✓", "⚠", "over", "under"]
            )
            
            if status_in_table:
                table_score += 10
                feedback_parts.append("✅ Table includes status indicators")
            elif any(indicator in table_text_lower for indicator in ["yes", "no", "complete"]):
                table_score += 5

        score += table_score
        logger.info(f"Table quality score: {table_score}/30")

        # Deadline Organization (20 points)
        deadline_score = 0
        
        # Check for chronological order (10 pts)
        nov_pos = full_text_lower.find("nov 30")
        if nov_pos == -1:
            nov_pos = full_text_lower.find("november 30")
        jan1_pos = full_text_lower.find("jan 1")
        feb_pos = full_text_lower.find("feb 1")
        if feb_pos == -1:
            feb_pos = full_text_lower.find("february 1")
        
        if nov_pos != -1 and jan1_pos != -1 and feb_pos != -1:
            if nov_pos < jan1_pos < feb_pos:
                deadline_score += 10
                feedback_parts.append("✅ Deadlines listed in chronological order")
            else:
                deadline_score += 3
                feedback_parts.append("⚠️  Deadlines present but not in chronological order")
        
        # Check for all 8 schools mentioned (10 pts)
        schools = [
            "stanford", "northwestern", "berkeley", "yale",
            "brown", "mit", "michigan", "cornell"
        ]
        schools_found = sum(1 for school in schools if school in full_text_lower)
        
        deadline_score += int((schools_found / 8) * 10)
        feedback_parts.append(f"Schools mentioned: {schools_found}/8")
        
        score += deadline_score
        logger.info(f"Deadline organization score: {deadline_score}/20")

        # Essay Content (25 points)
        content_score = 0
        
        # Check for multiple essay full texts included (15 pts)
        # We look for substantial chunks of the actual essay content
        essay_content_indicators = [
            "debate", "food drive", "journalism", "medill",
            "environmental", "photography", "open curriculum"
        ]
        content_matches = sum(
            1 for indicator in essay_content_indicators if indicator in full_text_lower
        )
        
        if content_matches >= 5:
            content_score += 15
            feedback_parts.append(f"✅ Multiple essay texts included ({content_matches}/7 found)")
        elif content_matches >= 3:
            content_score += 10
            feedback_parts.append(f"⚠️  Some essay content included ({content_matches}/7 found)")
        elif content_matches >= 1:
            content_score += 5
        
        # Check for proper labeling with headings (10 pts)
        if heading_count >= 6:
            content_score += 10
            feedback_parts.append("✅ Essays properly labeled with section headings")
        elif heading_count >= 4:
            content_score += 7
        elif heading_count >= 3:
            content_score += 4
        
        score += content_score
        logger.info(f"Essay content score: {content_score}/25")

        # Word Count Accuracy (15 points)
        accuracy_score = 0
        
        # Check if identifies personal statement (687 words) as over limit (5 pts)
        has_687 = "687" in full_text
        has_ps_over_indication = any(
            phrase in full_text_lower
            for phrase in [
                "personal statement" and "over",
                "personal statement" and "trim",
                "687" and "trim",
                "687" and "over"
            ]
        )
        
        if has_687 and ("over" in full_text_lower or "trim" in full_text_lower):
            accuracy_score += 5
            feedback_parts.append("✅ Correctly identifies Personal Statement needs trimming")
        elif has_687:
            accuracy_score += 2
        
        # Check for other essay limit statuses (10 pts)
        limit_status_words = ["over", "under", "trim", "ok", "within", "exceeds", "meets"]
        limit_mentions = sum(full_text_lower.count(word) for word in limit_status_words)
        
        if limit_mentions >= 5:
            accuracy_score += 10
            feedback_parts.append(f"✅ Multiple essay statuses identified ({limit_mentions} mentions)")
        elif limit_mentions >= 3:
            accuracy_score += 7
        elif limit_mentions >= 1:
            accuracy_score += 3
        
        score += accuracy_score
        logger.info(f"Word count accuracy score: {accuracy_score}/15")

        # Action Items (10 points)
        action_score = 0
        
        action_keywords = [
            "priority", "action", "next steps", "to do", "todo",
            "must trim", "needs editing", "revise", "urgent"
        ]
        
        has_action_section = any(keyword in full_text_lower for keyword in action_keywords)
        
        if has_action_section:
            # Count how many action-related items are mentioned
            action_count = sum(1 for kw in action_keywords if kw in full_text_lower)
            if action_count >= 3:
                action_score += 10
                feedback_parts.append("✅ Comprehensive action items section included")
            elif action_count >= 1:
                action_score += 7
                feedback_parts.append("⚠️  Basic action items included")
        
        score += action_score
        logger.info(f"Action items score: {action_score}/10")

        # Document Formatting (10 points)
        format_score = 0
        
        # Professional appearance with consistent formatting (5 pts)
        if heading_count >= 4 and table_count >= 1:
            format_score += 5
            feedback_parts.append("✅ Professional document structure")
        elif heading_count >= 2:
            format_score += 3
        
        # Clear visual hierarchy (5 pts)
        has_varied_structure = (
            heading_count >= 3 and
            (list_item_count >= 2 or "•" in full_text) and
            table_count >= 1
        )
        
        if has_varied_structure:
            format_score += 5
            feedback_parts.append("✅ Clear visual hierarchy with varied elements")
        elif heading_count >= 2 and table_count >= 1:
            format_score += 3
        
        score += format_score
        logger.info(f"Document formatting score: {format_score}/10")

        # ===================================================================
        # FINAL SCORING
        # ===================================================================

        # Total possible score is 100 points from partial credit
        final_score = min(100, score) / 100.0
        
        # Pass threshold: 70% (70 points out of 100)
        passed = final_score >= 0.70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/100 ({final_score:.2%}), Passed: {passed}")

        return {
            "passed": passed,
            "score": final_score,
            "feedback": f"Score: {score}/100 points. {feedback}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification exception: {str(e)}"
        }
    
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)