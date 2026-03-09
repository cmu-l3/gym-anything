#!/usr/bin/env python3
"""
Verifier for Oral History Compilation task
Checks proper document formatting, table structure, timeline, and quotes
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


def verify_oral_history_compilation(traj, env_info, task_info):
    """
    Verify oral history compilation document meets formatting requirements
    
    Checks:
    1. Title present and bold
    2. All 4 section headings present
    3. Table with correct structure (4 columns, 4+ data rows)
    4. Timeline with 4+ dated events
    5. Quotes with italic formatting and attributions
    6. Historical Context section with sufficient content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/oral_history_final.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_oral_history_')
    
    feedback_parts = []
    score = 0.0
    max_score = 100.0
    
    try:
        # Parse document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Document not found or could not be parsed: {error}"
            }
        
        # Extract full text for content checks
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Check 1: Title present and formatted (15 points)
        title_text = "Old Market District Oral History Project"
        if title_text.lower() in full_text_lower:
            score += 7.5
            feedback_parts.append("✅ Title present")
            
            # Check if title is bold
            if check_text_formatting(doc, title_text, bold=True):
                score += 7.5
                feedback_parts.append("✅ Title formatted (bold)")
            else:
                feedback_parts.append("⚠️ Title should be bold")
        else:
            feedback_parts.append("❌ Title missing or incorrect")
        
        # Check 2: Required section headings (20 points, 5 each)
        required_sections = [
            ("interviewees", "Interviewees"),
            ("key events timeline", "Key Events Timeline"),
            ("notable accounts", "Notable Accounts"),
            ("historical context", "Historical Context")
        ]
        
        sections_found = 0
        for section_lower, section_name in required_sections:
            if section_lower in full_text_lower:
                sections_found += 1
                score += 5
                feedback_parts.append(f"✅ Section '{section_name}' present")
            else:
                feedback_parts.append(f"❌ Section '{section_name}' missing")
        
        # Check 3: Table present with correct structure (20 points)
        table_count = count_tables(doc)
        if table_count >= 1:
            score += 10
            feedback_parts.append(f"✅ Table present ({table_count} found)")
            
            # Check table structure
            table = doc.tables[0]
            col_count = len(table.columns)
            row_count = len(table.rows)
            
            if col_count >= 4:
                score += 5
                feedback_parts.append(f"✅ Table has {col_count} columns")
            else:
                feedback_parts.append(f"⚠️ Table has only {col_count} columns (need 4)")
            
            # Check for at least 4 data rows (plus header = 5 total)
            if row_count >= 5:
                score += 5
                feedback_parts.append(f"✅ Table has {row_count-1} data rows")
            elif row_count >= 3:
                score += 2.5
                feedback_parts.append(f"⚠️ Table has only {row_count-1} data rows (need 4)")
            else:
                feedback_parts.append(f"❌ Table has insufficient rows")
        else:
            feedback_parts.append("❌ No table found")
        
        # Check 4: Timeline entries with years (15 points)
        # Look for year patterns (1950-1979)
        year_pattern = r'\b(19[5-7]\d)\b'
        years_found = re.findall(year_pattern, full_text)
        unique_years = len(set(years_found))
        
        if unique_years >= 4:
            score += 15
            feedback_parts.append(f"✅ Timeline has {unique_years} dated events")
        elif unique_years >= 3:
            score += 10
            feedback_parts.append(f"⚠️ Timeline has {unique_years} events (need 4)")
        elif unique_years >= 2:
            score += 5
            feedback_parts.append(f"⚠️ Timeline has only {unique_years} events (need 4)")
        else:
            feedback_parts.append("❌ Timeline missing or insufficient dated events")
        
        # Check 5: Quoted accounts with formatting (20 points)
        # Count italic text runs (quotes should be italicized)
        italic_count = 0
        for para in doc.paragraphs:
            for run in para.runs:
                # Only count substantial italic text (not just punctuation)
                if run.italic and len(run.text.strip()) > 20:
                    italic_count += 1
        
        # Look for attribution markers (em dash or hyphen with name)
        # Matches: "— Robert Chen" or "- Dorothy Williams" etc.
        attribution_pattern = r'[—\-]\s*[A-Z][a-z]+\s+[A-Z][a-z]+'
        attributions_found = len(re.findall(attribution_pattern, full_text))
        
        # Also look for names from interviews in the document
        interviewee_names = ["Chen", "Williams", "Murphy", "Goldman"]
        names_in_attributions = sum(1 for name in interviewee_names if name in full_text)
        
        if italic_count >= 3 and attributions_found >= 3:
            score += 20
            feedback_parts.append(f"✅ {italic_count} quotes formatted, {attributions_found} attributions")
        elif italic_count >= 2 and attributions_found >= 2:
            score += 12
            feedback_parts.append(f"⚠️ {italic_count} quotes formatted, {attributions_found} attributions (need 3)")
        elif italic_count >= 1 or attributions_found >= 1:
            score += 6
            feedback_parts.append(f"⚠️ Only {italic_count} quotes, {attributions_found} attributions (need 3)")
        else:
            feedback_parts.append("❌ Quotes missing proper formatting or attributions")
        
        # Check 6: Historical Context section has content (10 points)
        # Find Historical Context section and check if it has substantial text
        context_section_idx = full_text_lower.find("historical context")
        if context_section_idx != -1:
            # Get text after "Historical Context" heading
            # Try to isolate just that section (until next section or end)
            context_text = full_text[context_section_idx + len("historical context"):]
            
            # Try to find where next section might start (or take first 500 chars)
            context_text = context_text[:500]
            
            # Remove the heading itself and count words
            context_words = context_text.split()
            word_count = len([w for w in context_words if len(w) > 2])  # Exclude very short words
            
            if word_count >= 50:
                score += 10
                feedback_parts.append(f"✅ Historical Context has {word_count} words")
            elif word_count >= 30:
                score += 6
                feedback_parts.append(f"⚠️ Historical Context has {word_count} words (need 50+)")
            elif word_count >= 15:
                score += 3
                feedback_parts.append(f"⚠️ Historical Context is brief ({word_count} words)")
            else:
                feedback_parts.append(f"❌ Historical Context too short ({word_count} words)")
        else:
            feedback_parts.append("❌ Historical Context section not found")
        
        # Determine pass/fail (threshold 75%)
        passed = score >= 75.0
        
        # Compile feedback
        feedback = " | ".join(feedback_parts)
        summary = f"Score: {score:.1f}/100. "
        if passed:
            summary += "Document meets historical society formatting standards."
        else:
            summary += "Document needs more work to meet formatting requirements."
        
        final_feedback = summary + " | " + feedback
        
        return {
            "passed": passed,
            "score": int(score),
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