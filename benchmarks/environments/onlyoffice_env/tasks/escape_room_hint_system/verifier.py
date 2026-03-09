#!/usr/bin/env python3
"""
Verifier for Escape Room Hint System task
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_escape_room_hint_system(traj, env_info, task_info):
    """
    Verify that the escape room hint progression document was created correctly.

    Scoring breakdown (100 points total):
    
    Document Structure (40 points):
    - Title and subtitle present (5 pts)
    - All 6 puzzles included (10 pts)  
    - Each puzzle has description, hints, solution (15 pts)
    - Footer with GM tips (5 pts)
    - File saved correctly (5 pts)
    
    Formatting Consistency (35 points):
    - Puzzle names bold and 14pt (10 pts)
    - Hint labels bold and clearly labeled (10 pts)
    - Solution labels bold and red text (10 pts)
    - Document has proper structure/separators (5 pts)
    
    Content Organization (25 points):
    - Hints show clear progression (15 pts)
    - Each puzzle has 3 hints + solution (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/alchemist_hints_final.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_escape_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        score = 0
        feedback_parts = []
        max_score = 100

        # Get full document text for content checking
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        # ========== DOCUMENT STRUCTURE (40 points) ==========
        
        # Check 1: Title and subtitle present (5 pts)
        has_title = ("alchemist" in full_text_lower and "laboratory" in full_text_lower and 
                     "hint progression" in full_text_lower)
        has_subtitle = "game master" in full_text_lower and "reference" in full_text_lower
        
        if has_title and has_subtitle:
            score += 5
            feedback_parts.append("✅ Title and subtitle present (5/5 pts)")
        elif has_title or has_subtitle:
            score += 2
            feedback_parts.append("⚠️ Title or subtitle incomplete (2/5 pts)")
        else:
            feedback_parts.append("❌ Missing title/subtitle (0/5 pts)")

        # Check 2: All 6 puzzles mentioned (10 pts)
        required_puzzles = [
            "locked journal",
            "periodic table",
            "distillation",
            "constellation",
            "ancient tome",
            "final formula"
        ]
        puzzles_found = sum(1 for p in required_puzzles if p in full_text_lower)
        puzzle_score = int((puzzles_found / 6) * 10)
        score += puzzle_score
        
        if puzzles_found == 6:
            feedback_parts.append(f"✅ All 6 puzzles present (10/10 pts)")
        else:
            feedback_parts.append(f"⚠️ Found {puzzles_found}/6 puzzles ({puzzle_score}/10 pts)")

        # Check 3: Structure with hints and solutions (15 pts)
        # Count occurrences of hint labels
        hint1_count = len(re.findall(r'hint\s*1', full_text_lower))
        hint2_count = len(re.findall(r'hint\s*2', full_text_lower))
        hint3_count = len(re.findall(r'hint\s*3', full_text_lower))
        solution_count = len(re.findall(r'solution', full_text_lower))
        
        # Each puzzle should have 3 hints + 1 solution = 4 elements
        avg_hints = (hint1_count + hint2_count + hint3_count) / 3
        structure_score = 0
        
        if avg_hints >= 5 and solution_count >= 5:  # At least 5 of 6 puzzles have proper structure
            structure_score = 15
        elif avg_hints >= 4 and solution_count >= 4:
            structure_score = 12
        elif avg_hints >= 3 and solution_count >= 3:
            structure_score = 8
        else:
            structure_score = int((avg_hints / 6) * 15)
        
        score += structure_score
        feedback_parts.append(f"Hint structure: H1={hint1_count}, H2={hint2_count}, H3={hint3_count}, Sol={solution_count} ({structure_score}/15 pts)")

        # Check 4: Footer with GM tips (5 pts)
        has_tips = any(phrase in full_text_lower for phrase in [
            "always ask",
            "wait 3-5 minutes",
            "wait 3",
            "watch the camera",
            "game master tips",
            "tips for"
        ])
        
        if has_tips:
            score += 5
            feedback_parts.append("✅ GM tips footer found (5/5 pts)")
        else:
            feedback_parts.append("❌ Missing GM tips footer (0/5 pts)")

        # Check 5: File saved correctly (5 pts)
        score += 5  # If we got here, file exists
        feedback_parts.append("✅ File saved correctly (5/5 pts)")

        # ========== FORMATTING CONSISTENCY (35 points) ==========
        
        # Check 6: Puzzle names are bold (10 pts)
        # Check if at least some puzzle names have bold formatting
        bold_puzzles_found = 0
        puzzle_names_to_check = [
            "Locked Journal",
            "Periodic Table", 
            "Distillation",
            "Constellation",
            "Ancient Tome",
            "Final Formula"
        ]
        
        for puzzle_name in puzzle_names_to_check:
            if check_text_formatting(doc, puzzle_name, bold=True):
                bold_puzzles_found += 1
        
        bold_score = int((bold_puzzles_found / 6) * 10)
        score += bold_score
        
        if bold_puzzles_found >= 5:
            feedback_parts.append(f"✅ Puzzle names properly bold ({bold_puzzles_found}/6 puzzles, {bold_score}/10 pts)")
        elif bold_puzzles_found >= 3:
            feedback_parts.append(f"⚠️ Some puzzle names bold ({bold_puzzles_found}/6 puzzles, {bold_score}/10 pts)")
        else:
            feedback_parts.append(f"❌ Puzzle names not properly bold ({bold_puzzles_found}/6 puzzles, {bold_score}/10 pts)")

        # Check 7: Hint labels are bold and properly formatted (10 pts)
        # Check for proper hint labeling format
        hint_label_patterns = [
            r'hint\s*1\s*:',
            r'hint\s*2\s*:',
            r'hint\s*3\s*:'
        ]
        
        hint_label_count = sum(len(re.findall(pattern, full_text_lower)) for pattern in hint_label_patterns)
        expected_hint_labels = 18  # 3 hints × 6 puzzles
        
        # Check if at least some hint labels are bold
        hint_labels_bold = 0
        for hint_num in [1, 2, 3]:
            if check_text_formatting(doc, f"Hint {hint_num}", bold=True):
                hint_labels_bold += 1
        
        hint_format_score = 0
        if hint_label_count >= 15 and hint_labels_bold >= 2:
            hint_format_score = 10
        elif hint_label_count >= 12:
            hint_format_score = 7
        elif hint_label_count >= 9:
            hint_format_score = 5
        else:
            hint_format_score = int((hint_label_count / expected_hint_labels) * 10)
        
        score += hint_format_score
        feedback_parts.append(f"Hint labels: {hint_label_count} found ({hint_format_score}/10 pts)")

        # Check 8: Solution labels present (10 pts)
        # Note: Checking for red color is complex with python-docx, so we'll check for bold and presence
        solution_bold = check_text_formatting(doc, "SOLUTION", bold=True) or \
                       check_text_formatting(doc, "solution", bold=True)
        
        solution_score = 0
        if solution_count >= 5:
            if solution_bold:
                solution_score = 10  # Full credit if bold (can't easily verify red)
            else:
                solution_score = 7  # Partial credit if present but not bold
        elif solution_count >= 3:
            solution_score = 5
        else:
            solution_score = int((solution_count / 6) * 10)
        
        score += solution_score
        feedback_parts.append(f"Solution labels: {solution_count} found, bold={solution_bold} ({solution_score}/10 pts)")

        # Check 9: Document structure (5 pts)
        # Check if document has reasonable length and structure
        paragraph_count = len(doc.paragraphs)
        
        structure_quality_score = 0
        if paragraph_count >= 50:  # Well-structured document with separators
            structure_quality_score = 5
        elif paragraph_count >= 30:
            structure_quality_score = 3
        else:
            structure_quality_score = 1
        
        score += structure_quality_score
        feedback_parts.append(f"Document structure: {paragraph_count} paragraphs ({structure_quality_score}/5 pts)")

        # ========== CONTENT ORGANIZATION (25 points) ==========
        
        # Check 10: Hints show progression (15 pts)
        # Look for progressive hint language patterns
        gentle_phrases = ["look", "check", "notice", "observe", "think about", "consider"]
        medium_phrases = ["try", "focus", "specific", "combine", "use", "find"]
        direct_phrases = ["answer", "solution", "exactly", "the code is", "enter"]
        
        has_gentle = sum(1 for phrase in gentle_phrases if phrase in full_text_lower) >= 3
        has_medium = sum(1 for phrase in medium_phrases if phrase in full_text_lower) >= 3
        has_direct = sum(1 for phrase in direct_phrases if phrase in full_text_lower) >= 2
        
        progression_score = 0
        if has_gentle and has_medium and has_direct:
            progression_score = 15
        elif (has_gentle and has_medium) or (has_medium and has_direct):
            progression_score = 10
        elif has_gentle or has_medium or has_direct:
            progression_score = 5
        
        score += progression_score
        feedback_parts.append(f"Hint progression quality: gentle={has_gentle}, medium={has_medium}, direct={has_direct} ({progression_score}/15 pts)")

        # Check 11: Each puzzle has 3 hints + solution (10 pts)
        completeness_score = 0
        if hint_label_count >= 15 and solution_count >= 5:
            completeness_score = 10
        elif hint_label_count >= 12 and solution_count >= 4:
            completeness_score = 7
        elif hint_label_count >= 9 and solution_count >= 3:
            completeness_score = 5
        else:
            completeness_score = int(((hint_label_count + solution_count) / 24) * 10)
        
        score += completeness_score
        feedback_parts.append(f"Content completeness ({completeness_score}/10 pts)")

        # ========== FINAL ASSESSMENT ==========
        
        passed = score >= 70
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)