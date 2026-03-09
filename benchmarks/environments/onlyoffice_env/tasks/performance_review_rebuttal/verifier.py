#!/usr/bin/env python3
"""
Verifier for Performance Review Rebuttal task

Checks that the rebuttal document has:
1. Proper header information
2. Section headers addressing both criticisms
3. Evidence table with sufficient rows (meeting attendance)
4. Bold formatting on key terms
5. Professional closing statement
6. Sufficient length (thoroughness)
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


def verify_performance_review_rebuttal(traj, env_info, task_info):
    """
    Verify the performance review rebuttal document meets requirements.
    
    Requirements:
    1. Document contains header information (employee name, ID, dates)
    2. Document has section headers for two criticisms
    3. Contains a table with at least 8 rows (for meeting attendance evidence)
    4. Key phrases are formatted in bold (section headers, emphasis)
    5. Document has professional closing statement
    6. Minimum length indicates thorough response (300+ words)
    7. Placeholders are removed (actual content added)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/Performance_Review_Rebuttal.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_rebuttal_')

    try:
        logger.info(f"Verifying document at {container_path}")
        
        # Copy and parse document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to parse document: {error}"
            }
        
        # Extract all text
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        feedback_parts = []
        score = 0.0
        max_score = 100.0
        
        # Check 0: Placeholders should be removed (critical check)
        placeholder_keywords = [
            '[section 1',
            '[section 2',
            '[create a table',
            '[add your professional closing',
            'placeholder'
        ]
        
        placeholders_remaining = sum(1 for kw in placeholder_keywords if kw in full_text_lower)
        
        if placeholders_remaining > 0:
            feedback_parts.append(f"❌ Document still contains {placeholders_remaining} placeholder(s) - task not completed")
            # Severe penalty but not zero to show some progress
            score = max(score, 10.0)
        else:
            score += 10
            feedback_parts.append("✅ All placeholders replaced with actual content")
        
        # Check 1: Header information present (15 points)
        header_terms = ['employee name', 'employee id', 'review period', 'date']
        header_found = sum(1 for term in header_terms if term in full_text_lower)
        
        if header_found >= 3:
            score += 15
            feedback_parts.append(f"✅ Header information present ({header_found}/4 fields)")
        elif header_found >= 2:
            score += 8
            feedback_parts.append(f"⚠️  Partial header information ({header_found}/4 fields)")
        else:
            feedback_parts.append(f"❌ Missing header information (found {header_found}/4 required fields)")
        
        # Check 2: Both criticisms addressed with section headers (20 points)
        # Look for keywords related to both criticisms
        criticism1_keywords = ['meeting', 'attendance', 'standup', 'participated', 'criticism #1', 'criticism 1', 'first criticism']
        criticism2_keywords = ['deadline', 'vendor', 'integration', 'project', 'criticism #2', 'criticism 2', 'second criticism']
        
        # Check if criticism 1 is addressed
        criticism1_addressed = any(kw in full_text_lower for kw in criticism1_keywords)
        criticism2_addressed = any(kw in full_text_lower for kw in criticism2_keywords)
        
        criticisms_addressed = sum([criticism1_addressed, criticism2_addressed])
        
        if criticisms_addressed == 2:
            score += 20
            feedback_parts.append("✅ Both criticisms addressed in document")
        elif criticisms_addressed == 1:
            score += 10
            feedback_parts.append("⚠️  Only one criticism addressed (both required)")
        else:
            feedback_parts.append("❌ Neither criticism clearly addressed")
        
        # Check 3: Table exists with sufficient rows (25 points)
        num_tables = count_tables(doc)
        
        if num_tables >= 1:
            table = doc.tables[0]
            num_rows = len(table.rows)
            num_cols = len(table.columns) if table.rows else 0
            
            if num_rows >= 8:  # Header + at least 7 data rows
                score += 25
                feedback_parts.append(f"✅ Evidence table present with {num_rows} rows (meeting attendance log)")
            elif num_rows >= 5:
                score += 15
                feedback_parts.append(f"⚠️  Table present but sparse ({num_rows} rows, expected 8+)")
            elif num_rows >= 3:
                score += 8
                feedback_parts.append(f"⚠️  Table too small ({num_rows} rows, need 8+ for credible evidence)")
            else:
                score += 3
                feedback_parts.append(f"⚠️  Table minimal ({num_rows} rows)")
                
            # Bonus check: verify table has reasonable columns (3+)
            if num_cols >= 3:
                feedback_parts.append(f"  └─ Table has {num_cols} columns (good structure)")
            elif num_cols >= 2:
                feedback_parts.append(f"  └─ Table has {num_cols} columns (acceptable)")
        else:
            feedback_parts.append("❌ No evidence table found (required for meeting attendance documentation)")
        
        # Check 4: Bold formatting used for emphasis (15 points)
        # Look for bold formatting on common section header terms
        bold_checks = [
            'criticism',
            'response',
            'evidence',
            'rebuttal',
            'meeting',
            'attendance',
            'project',
            'deadline'
        ]
        
        bold_found = 0
        for term in bold_checks:
            if check_text_formatting(doc, term, bold=True):
                bold_found += 1
        
        if bold_found >= 3:
            score += 15
            feedback_parts.append(f"✅ Key terms formatted in bold ({bold_found} found)")
        elif bold_found >= 2:
            score += 10
            feedback_parts.append(f"⚠️  Some bold formatting present ({bold_found} terms)")
        elif bold_found >= 1:
            score += 5
            feedback_parts.append(f"⚠️  Minimal bold formatting ({bold_found} term)")
        else:
            feedback_parts.append("❌ No bold formatting detected (professional documents use emphasis)")
        
        # Check 5: Professional closing (10 points)
        closing_phrases = [
            'respectfully',
            'sincerely',
            'thank you for',
            'appreciate your consideration',
            'happy to discuss',
            'available to',
            'request that this rebuttal',
            'look forward',
            'open to further discussion'
        ]
        
        closing_found = sum(1 for phrase in closing_phrases if phrase in full_text_lower)
        
        if closing_found >= 2:
            score += 10
            feedback_parts.append("✅ Professional closing statement present")
        elif closing_found >= 1:
            score += 5
            feedback_parts.append("⚠️  Basic closing present (could be more professional)")
        else:
            feedback_parts.append("❌ Missing professional closing statement")
        
        # Check 6: Document length/thoroughness (15 points)
        word_count = len(full_text.split())
        
        if word_count >= 400:
            score += 15
            feedback_parts.append(f"✅ Document is thorough ({word_count} words)")
        elif word_count >= 300:
            score += 12
            feedback_parts.append(f"✅ Document is adequate ({word_count} words)")
        elif word_count >= 200:
            score += 8
            feedback_parts.append(f"⚠️  Document is brief ({word_count} words, 300+ recommended)")
        elif word_count >= 150:
            score += 4
            feedback_parts.append(f"⚠️  Document quite short ({word_count} words)")
        else:
            feedback_parts.append(f"❌ Document too short ({word_count} words, needs detail for credibility)")
        
        # Normalize score
        score = min(score, max_score)
        
        # Determine pass/fail (70% threshold)
        passed = score >= 70.0
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score / max_score,
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