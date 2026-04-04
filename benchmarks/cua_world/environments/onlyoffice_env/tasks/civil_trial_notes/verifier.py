#!/usr/bin/env python3
"""
Verifier for civil_trial_notes@1 task
Verifies proper structuring and formatting of jury trial notes
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_civil_trial_notes(traj, env_info, task_info):
    """
    Verify that civil trial notes document meets all structural and formatting requirements.
    
    Checks:
    1. Document structure (30 points): Title, case number, juror ID, required sections
    2. Witness testimony table (25 points): 5 columns, 4+ entries, bold names, specific witnesses
    3. Evidence log (15 points): Plaintiff's and Defendant's exhibits with proper naming
    4. Timeline section (15 points): Time markers, chronological events, disputed items
    5. Contradictions section (10 points): Numbered contradictions present
    6. Questions section (5 points): Questions listed with question marks
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/trial_notes_template.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_trial_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        # Get full text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        feedback_parts = []
        score = 0
        max_score = 100

        # ============================================================================
        # CRITERION 1: Document Structure (30 points)
        # ============================================================================
        structure_score = 0
        
        # Check title includes both "Civil Trial Notes" and case name
        has_title = "civil trial notes" in full_text_lower and "martinez" in full_text_lower and "chen" in full_text_lower
        if has_title:
            structure_score += 5
            feedback_parts.append("✅ Title includes case name")
        else:
            feedback_parts.append("❌ Missing proper title with 'Civil Trial Notes - Martinez v. Chen'")
        
        # Check case number present
        has_case_number = "cv-2024-8847" in full_text_lower or "cv 2024 8847" in full_text_lower
        if has_case_number:
            structure_score += 5
            feedback_parts.append("✅ Case number CV-2024-8847 present")
        else:
            feedback_parts.append("❌ Missing case number CV-2024-8847")
        
        # Check juror identifier
        has_juror_id = "juror #7" in full_text_lower or "juror 7" in full_text_lower or "juror#7" in full_text_lower
        if has_juror_id:
            structure_score += 5
            feedback_parts.append("✅ Juror #7 identifier present")
        else:
            feedback_parts.append("❌ Missing juror identifier")
        
        # Check for required sections (case insensitive)
        required_sections = [
            ("case summary", "Case Summary"),
            ("witness testimony", "Witness Testimony"),
            ("evidence presented", "Evidence Presented"),
            ("timeline of events", "Timeline of Events"),
            ("contradiction", "Contradictions"),
            ("question", "Questions for Deliberation")
        ]
        
        sections_found = 0
        missing_sections = []
        for section_key, section_name in required_sections:
            if section_key in full_text_lower:
                sections_found += 1
            else:
                missing_sections.append(section_name)
        
        section_score = int((sections_found / len(required_sections)) * 15)
        structure_score += section_score
        
        if sections_found == len(required_sections):
            feedback_parts.append(f"✅ All {len(required_sections)} required sections present")
        else:
            feedback_parts.append(f"⚠️ Found {sections_found}/{len(required_sections)} sections (missing: {', '.join(missing_sections)})")
        
        score += structure_score

        # ============================================================================
        # CRITERION 2: Witness Testimony Table (25 points)
        # ============================================================================
        table_score = 0
        table_count = count_tables(doc)
        
        if table_count >= 1:
            table_score += 5
            feedback_parts.append("✅ Table present in document")
            
            # Analyze first table
            table = doc.tables[0]
            num_cols = len(table.columns)
            num_rows = len(table.rows)
            
            # Check for 5 columns
            if num_cols == 5:
                table_score += 5
                feedback_parts.append("✅ Table has exactly 5 columns")
            else:
                feedback_parts.append(f"❌ Table has {num_cols} columns (expected 5)")
            
            # Extract all table text and analyze
            table_text_full = ""
            table_text_lower = ""
            for row in table.rows:
                for cell in row.cells:
                    table_text_full += cell.text + " | "
                    table_text_lower += cell.text.lower() + " | "
            
            # Check for appropriate column headers
            required_headers = ["witness", "side", "time", "testimony", "credibility"]
            headers_found = sum(1 for h in required_headers if h in table_text_lower)
            
            if headers_found >= 4:
                table_score += 5
                feedback_parts.append(f"✅ Table headers appropriate ({headers_found}/5 key terms)")
            else:
                feedback_parts.append(f"⚠️ Table headers may be incorrect ({headers_found}/5 key terms found)")
            
            # Check for at least 4 data rows (plus 1 header = 5 total rows minimum)
            if num_rows >= 5:
                table_score += 5
                feedback_parts.append(f"✅ Table has {num_rows-1} witness entries (expected 4+)")
            else:
                feedback_parts.append(f"❌ Table has only {num_rows-1} entries (expected 4+)")
            
            # Check for specific required witnesses
            required_witnesses = ["kim", "park", "rodriguez", "watkins"]
            witnesses_found = sum(1 for w in required_witnesses if w in table_text_lower)
            
            witness_score = int((witnesses_found / 4) * 5)
            table_score += witness_score
            
            if witnesses_found == 4:
                feedback_parts.append("✅ All 4 required witnesses present (Kim, Park, Rodriguez, Watkins)")
            else:
                missing_witnesses = [w.title() for w in required_witnesses if w not in table_text_lower]
                feedback_parts.append(f"⚠️ Only {witnesses_found}/4 required witnesses found (missing: {', '.join(missing_witnesses)})")
            
            # Check for bold formatting in witness names (check first column cells)
            # This is a best-effort check since bold detection can be tricky
            has_bold_in_table = False
            try:
                for row_idx, row in enumerate(table.rows):
                    if row_idx == 0:  # Skip header row
                        continue
                    first_cell = row.cells[0]
                    for paragraph in first_cell.paragraphs:
                        for run in paragraph.runs:
                            if run.bold and len(run.text.strip()) > 2:
                                has_bold_in_table = True
                                break
            except:
                pass
            
            if has_bold_in_table:
                feedback_parts.append("✅ Bold formatting detected in table (likely witness names)")
        else:
            feedback_parts.append("❌ No table found (witness testimony table required)")
        
        score += table_score

        # ============================================================================
        # CRITERION 3: Evidence Log (15 points)
        # ============================================================================
        evidence_score = 0
        
        # Check for plaintiff's exhibits section
        has_plaintiff_exhibits = "plaintiff" in full_text_lower and "exhibit" in full_text_lower
        if has_plaintiff_exhibits:
            evidence_score += 5
            
            # Count plaintiff exhibits (P-1, P-2, P-3, etc.)
            p_exhibits = []
            for i in range(1, 10):
                if f"p-{i}" in full_text_lower or f"p {i}" in full_text_lower:
                    p_exhibits.append(i)
            
            if len(p_exhibits) >= 3:
                evidence_score += 5
                feedback_parts.append(f"✅ Found {len(p_exhibits)} plaintiff exhibits (P-#)")
            else:
                feedback_parts.append(f"⚠️ Only {len(p_exhibits)} plaintiff exhibits (expected 3+)")
        else:
            feedback_parts.append("❌ Plaintiff's exhibits section missing or not clearly labeled")
        
        # Check for defendant's exhibits section
        has_defendant_exhibits = "defendant" in full_text_lower and "exhibit" in full_text_lower
        if has_defendant_exhibits:
            evidence_score += 2
            
            # Count defendant exhibits (D-1, D-2, etc.)
            d_exhibits = []
            for i in range(1, 10):
                if f"d-{i}" in full_text_lower or f"d {i}" in full_text_lower:
                    d_exhibits.append(i)
            
            if len(d_exhibits) >= 2:
                evidence_score += 3
                feedback_parts.append(f"✅ Found {len(d_exhibits)} defendant exhibits (D-#)")
            else:
                feedback_parts.append(f"⚠️ Only {len(d_exhibits)} defendant exhibits (expected 2+)")
        else:
            feedback_parts.append("❌ Defendant's exhibits section missing or not clearly labeled")
        
        score += evidence_score

        # ============================================================================
        # CRITERION 4: Timeline Section (15 points)
        # ============================================================================
        timeline_score = 0
        
        # Check for timeline section
        has_timeline = "timeline" in full_text_lower
        if has_timeline:
            timeline_score += 5
            feedback_parts.append("✅ Timeline of Events section present")
            
            # Count time markers (various formats: 2:35 PM, 2:35pm, 14:35, etc.)
            time_patterns = [
                r'\d{1,2}:\d{2}\s*(?:am|pm|AM|PM)',  # 2:35 PM
                r'\d{1,2}:\d{2}\s*[AaPp][Mm]',       # 2:35pm
                r'(?:^|\s)\d{1,2}:\d{2}(?:\s|$)',    # 2:35 (standalone)
            ]
            
            time_markers = set()
            for pattern in time_patterns:
                matches = re.findall(pattern, full_text, re.MULTILINE)
                time_markers.update(matches)
            
            # Also look for time-like patterns near timeline section
            timeline_section_start = full_text_lower.find("timeline")
            if timeline_section_start > 0:
                timeline_section = full_text[timeline_section_start:timeline_section_start+2000]
                timeline_time_markers = re.findall(r'\d{1,2}:\d{2}', timeline_section)
            else:
                timeline_time_markers = []
            
            total_time_markers = len(time_markers) + len(timeline_time_markers)
            
            if total_time_markers >= 5:
                timeline_score += 5
                feedback_parts.append(f"✅ Found {total_time_markers} time markers in timeline")
            else:
                feedback_parts.append(f"⚠️ Only {total_time_markers} time markers found (expected 5+)")
            
            # Check for "disputed" marking (should be in italics ideally)
            has_disputed = "disputed" in full_text_lower
            if has_disputed:
                timeline_score += 5
                feedback_parts.append("✅ Disputed entry marked in timeline")
            else:
                feedback_parts.append("⚠️ No 'disputed' marking found in timeline")
        else:
            feedback_parts.append("❌ Timeline of Events section missing")
        
        score += timeline_score

        # ============================================================================
        # CRITERION 5: Contradictions Section (10 points)
        # ============================================================================
        contradictions_score = 0
        
        # Check for contradictions section
        has_contradictions = "contradiction" in full_text_lower
        if has_contradictions:
            contradictions_score += 5
            feedback_parts.append("✅ Contradictions section present")
            
            # Count numbered items (various formats: 1., 1), 1:, etc.)
            numbered_patterns = [
                r'(?:^|\n)\s*\d+\.\s+',    # 1.
                r'(?:^|\n)\s*\d+\)\s+',    # 1)
                r'(?:^|\n)\s*\d+:\s+',     # 1:
            ]
            
            numbered_items = set()
            for pattern in numbered_patterns:
                matches = re.findall(pattern, full_text, re.MULTILINE)
                numbered_items.update(matches)
            
            # Alternative: count lines that start with numbers
            contradiction_section_start = full_text_lower.find("contradiction")
            if contradiction_section_start > 0:
                # Extract contradiction section (next 1000 chars)
                contradiction_section = full_text[contradiction_section_start:contradiction_section_start+1500]
                numbered_lines = re.findall(r'(?:^|\n)\s*\d+[\.\):]', contradiction_section, re.MULTILINE)
            else:
                numbered_lines = []
            
            total_numbered = max(len(numbered_items), len(numbered_lines))
            
            if total_numbered >= 3:
                contradictions_score += 5
                feedback_parts.append(f"✅ Found {total_numbered} numbered contradictions")
            else:
                feedback_parts.append(f"⚠️ Only {total_numbered} contradictions numbered (expected 3+)")
        else:
            feedback_parts.append("❌ Contradictions section missing")
        
        score += contradictions_score

        # ============================================================================
        # CRITERION 6: Questions Section (5 points)
        # ============================================================================
        questions_score = 0
        
        # Check for questions section
        has_questions_section = "question" in full_text_lower and "deliberation" in full_text_lower
        if has_questions_section:
            questions_score += 2
            
            # Count question marks in document (or specifically in questions section)
            question_marks = full_text.count('?')
            
            if question_marks >= 3:
                questions_score += 3
                feedback_parts.append(f"✅ Found {question_marks} questions (with '?')")
            else:
                feedback_parts.append(f"⚠️ Only {question_marks} questions found (expected 3+)")
        else:
            feedback_parts.append("❌ Questions for Deliberation section missing")
        
        score += questions_score

        # ============================================================================
        # Final scoring and determination
        # ============================================================================
        
        # Normalize score to 0-1 range
        normalized_score = score / max_score
        
        # Pass threshold: 70% (70 points out of 100)
        passed = score >= 70
        
        # Compile feedback
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        summary = f"Total score: {score}/{max_score} points"
        if passed:
            summary += " - PASSED ✅"
        else:
            summary += f" - FAILED (need {70-score} more points) ❌"
        
        final_feedback = f"{summary} | {feedback}"

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": final_feedback
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


# Entry point for gym-anything framework
def verify(container_id: str, copy_from_env, temp_dir: str = None) -> dict:
    """
    Entry point called by gym-anything framework.
    
    Args:
        container_id: Container ID (not used directly)
        copy_from_env: Function to copy files from container
        temp_dir: Temporary directory (not used, we create our own)
    
    Returns:
        dict with 'passed', 'score', and 'feedback' keys
    """
    # Create mock trajectory and environment info for compatibility
    traj = None
    env_info = {'copy_from_env': copy_from_env}
    task_info = {}
    
    return verify_civil_trial_notes(traj, env_info, task_info)