#!/usr/bin/env python3
"""
Verifier for Foster Behavioral Log task

This verifier checks that a therapeutic foster parent has successfully transformed
scattered behavioral notes into a professional structured document suitable for
a placement review meeting.
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
    check_text_formatting,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_foster_behavioral_log(traj, env_info, task_info):
    """
    Verify that the foster behavioral log document was created correctly.

    Checks:
    1. File existence and validity (20 points)
    2. Document structure - title, date range, sections (25 points)
    3. Behavioral incident table - proper structure and data (25 points)
    4. Quantitative analysis - measurements and counts (15 points)
    5. Progress documentation - improvement language and comparisons (15 points)
    
    Bonus points (up to 20):
    - Professional formatting
    - Comprehensive data (8+ incidents)
    - Pattern recognition
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available"
        }

    container_path = "/home/ga/Documents/TextDocuments/jamie_placement_review.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_foster_')

    try:
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
                "feedback": f"Document not found or invalid: {error}"
            }

        score = 0
        feedback_parts = []

        # Extract full text for analysis
        full_text = get_document_text(doc).lower()
        
        # Check document isn't empty
        if len(full_text.strip()) < 100:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Document is too short or empty"
            }

        # ===================================================================
        # CHECK 1: File Existence and Basic Validity (20 points)
        # ===================================================================
        score += 20
        feedback_parts.append("✅ Document exists and is valid DOCX")

        # ===================================================================
        # CHECK 2: Document Structure (25 points)
        # ===================================================================
        structure_score = 0

        # Check for appropriate title
        title_terms = ["placement review", "behavioral tracking", "behavioral", "90-day", "jamie"]
        has_title = any(term in full_text for term in title_terms)
        
        if has_title:
            structure_score += 8
            feedback_parts.append("✅ Contains appropriate professional title")
        else:
            feedback_parts.append("❌ Missing professional title (e.g., 'Placement Review')")

        # Check for date range (September/Sept and November/Nov)
        has_sept = "september" in full_text or "sept" in full_text
        has_nov = "november" in full_text or "nov" in full_text
        
        if has_sept and has_nov:
            structure_score += 7
            feedback_parts.append("✅ Contains placement period date range")
        else:
            feedback_parts.append(f"❌ Missing date range (Sept: {has_sept}, Nov: {has_nov})")

        # Check for tables
        num_tables = count_tables(doc)
        if num_tables >= 2:
            structure_score += 10
            feedback_parts.append(f"✅ Contains {num_tables} tables (excellent structure)")
        elif num_tables == 1:
            structure_score += 5
            feedback_parts.append("⚠️  Only 1 table found (expected 2+)")
        else:
            feedback_parts.append("❌ No tables found - incident log should be in table format")

        score += structure_score

        # ===================================================================
        # CHECK 3: Behavioral Incident Table (25 points)
        # ===================================================================
        table_score = 0

        if num_tables > 0:
            # Analyze the first/largest table (likely the incident log)
            largest_table = max(doc.tables, key=lambda t: len(t.rows) * len(t.columns))
            num_cols = len(largest_table.columns)
            num_rows = len(largest_table.rows)

            # Check column count (should be 5: Date, Trigger, Behavior, Intervention, Resolution Time)
            if num_cols >= 5:
                table_score += 8
                feedback_parts.append(f"✅ Incident table has {num_cols} columns (sufficient detail)")
            elif num_cols >= 3:
                table_score += 4
                feedback_parts.append(f"⚠️  Table has {num_cols} columns (expected 5)")
            else:
                feedback_parts.append(f"❌ Table only has {num_cols} columns (need 5)")

            # Check row count (header + at least 6 data rows)
            if num_rows >= 7:
                table_score += 10
                feedback_parts.append(f"✅ Table has {num_rows} rows (comprehensive data)")
            elif num_rows >= 4:
                table_score += 5
                feedback_parts.append(f"⚠️  Table has {num_rows} rows (expected 7+)")
            else:
                feedback_parts.append(f"❌ Table has only {num_rows} rows (insufficient)")

            # Check for dates from raw notes
            date_patterns = [
                r'sept\s*\d+', r'september\s*\d+',
                r'oct\s*\d+', r'october\s*\d+',
                r'nov\s*\d+', r'november\s*\d+'
            ]
            found_dates = []
            for pattern in date_patterns:
                found_dates.extend(re.findall(pattern, full_text))
            
            if len(found_dates) >= 4:
                table_score += 4
                feedback_parts.append(f"✅ Found {len(found_dates)} dated incidents from notes")
            elif len(found_dates) >= 2:
                table_score += 2
                feedback_parts.append(f"⚠️  Found only {len(found_dates)} dated incidents")
            else:
                feedback_parts.append("❌ No dated incidents found in document")

            # Check for intervention terminology
            interventions = [
                "calm corner", "sensory brush", "weighted blanket",
                "visual schedule", "breathing", "deep breathing"
            ]
            found_interventions = [i for i in interventions if i in full_text]

            if len(found_interventions) >= 3:
                table_score += 3
                feedback_parts.append(f"✅ Found {len(found_interventions)} intervention strategies")
            elif len(found_interventions) >= 1:
                table_score += 1
                feedback_parts.append(f"⚠️  Found only {len(found_interventions)} interventions (expected 3+)")
            else:
                feedback_parts.append("❌ No intervention terminology found")

        else:
            feedback_parts.append("❌ Cannot verify table structure - no tables found")

        score += table_score

        # ===================================================================
        # CHECK 4: Quantitative Analysis (15 points)
        # ===================================================================
        quant_score = 0

        # Look for time measurements (minutes, hours)
        time_numbers = re.findall(r'\b(\d+)\s*(?:min|mins|minute|minutes|hour|hours|hrs)\b', full_text)
        
        # Look for counts/numbers that represent measurements
        count_numbers = re.findall(r'\b(\d+)\s*(?:incidents?|times?|observations?|behaviors?)\b', full_text)
        
        # Look for any numbers in context of measurement
        general_numbers = len(time_numbers) + len(count_numbers)

        if general_numbers >= 3:
            quant_score += 15
            feedback_parts.append(f"✅ Contains {general_numbers} quantitative measurements")
        elif general_numbers >= 2:
            quant_score += 10
            feedback_parts.append(f"⚠️  Contains {general_numbers} measurements (expected 3+)")
        elif general_numbers >= 1:
            quant_score += 5
            feedback_parts.append(f"⚠️  Only {general_numbers} measurement found")
        else:
            feedback_parts.append("❌ No quantitative measurements found")

        score += quant_score

        # ===================================================================
        # CHECK 5: Progress Documentation (15 points)
        # ===================================================================
        progress_score = 0

        # Check for progress-indicating language
        progress_terms = [
            "improvement", "progress", "decreased", "increased", "better",
            "improved", "reduction", "growth", "development", "emerging"
        ]
        found_progress_terms = [t for t in progress_terms if t in full_text]

        if len(found_progress_terms) >= 2:
            progress_score += 7
            feedback_parts.append(f"✅ Progress language present: {', '.join(found_progress_terms[:3])}")
        elif len(found_progress_terms) >= 1:
            progress_score += 3
            feedback_parts.append(f"⚠️  Limited progress language: {found_progress_terms[0]}")
        else:
            feedback_parts.append("❌ No progress indicators found")

        # Check for time comparisons (improvement from X to Y)
        comparison_patterns = [
            r'(\d+)\s*(?:min|mins|minute|minutes).*(?:to|→|down to|reduced to).*(\d+)\s*(?:min|mins|minute|minutes)',
            r'from\s+(\d+).*to\s+(\d+)',
        ]
        found_comparisons = False
        for pattern in comparison_patterns:
            if re.search(pattern, full_text):
                found_comparisons = True
                break

        if found_comparisons:
            progress_score += 5
            feedback_parts.append("✅ Contains time/measurement comparisons")
        else:
            feedback_parts.append("⚠️  No explicit comparisons found (e.g., '45 min to 5 min')")

        # Check for self-regulation mentions
        self_reg_terms = [
            "self-regulation", "self regulation", "independent", "without prompting",
            "on his own", "asked for", "himself", "self-aware"
        ]
        has_self_reg = any(term in full_text for term in self_reg_terms)

        if has_self_reg:
            progress_score += 3
            feedback_parts.append("✅ Documents self-regulation development")
        else:
            feedback_parts.append("⚠️  No self-regulation progress mentioned")

        score += progress_score

        # ===================================================================
        # BONUS POINTS (up to 20)
        # ===================================================================
        bonus_score = 0

        # Check for professional formatting (bold, italic for emphasis)
        has_formatting = False
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold or run.italic:
                    has_formatting = True
                    break
            if has_formatting:
                break

        if has_formatting:
            bonus_score += 5
            feedback_parts.append("🌟 Bonus: Professional formatting with emphasis")

        # Check for comprehensive data (8+ incidents in table)
        if num_tables > 0:
            max_rows = max(len(table.rows) for table in doc.tables)
            if max_rows >= 9:  # header + 8 data rows
                bonus_score += 5
                feedback_parts.append("🌟 Bonus: Comprehensive incident documentation (8+ entries)")

        # Check for pattern recognition/analysis
        pattern_terms = ["trigger", "pattern", "common", "tends to", "typically", "often", "frequency"]
        has_patterns = sum(1 for term in pattern_terms if term in full_text)
        
        if has_patterns >= 2:
            bonus_score += 5
            feedback_parts.append("🌟 Bonus: Pattern identification and analysis present")

        # Check for summary/statistics section
        summary_terms = ["summary", "statistics", "total", "average", "count"]
        has_summary = sum(1 for term in summary_terms if term in full_text)
        
        if has_summary >= 2:
            bonus_score += 5
            feedback_parts.append("🌟 Bonus: Summary statistics section included")

        score += bonus_score

        # ===================================================================
        # FINAL SCORING
        # ===================================================================
        # Normalize score to 0-1 range (max possible is 100 + 20 bonus = 120)
        final_score = min(score / 100.0, 1.0)
        
        # Pass threshold is 70% of base score (70/100)
        passed = final_score >= 0.70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": final_score,
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
