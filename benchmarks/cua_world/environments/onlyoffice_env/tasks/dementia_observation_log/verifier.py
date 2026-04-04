#!/usr/bin/env python3
"""
Verifier for Dementia Observation Log task
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
    count_paragraphs,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dementia_observation_log(traj, env_info, task_info):
    """
    Verify the dementia observation log document.
    
    Checks:
    1. Document exists and is valid DOCX
    2. Contains patient identification/header information
    3. Contains observation period or date range
    4. Multiple incidents documented with dates
    5. Multiple behavior categories represented
    6. Pattern analysis section present
    7. Questions for doctor included
    8. Professional formatting (bold headers, organized structure)
    9. Instructions template removed (document is completed)
    10. Appropriate length/detail (not just the template)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/mom_behavioral_log_neuro.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_dementia_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load document: {error}"}

        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        feedback = []
        score = 0.0
        max_score = 10.0

        # Check 0: Verify template instructions were removed (document is completed, not just template)
        template_markers = ["delete these instructions", "begin your structured log here", "task instructions:"]
        has_template = any(marker in full_text_lower for marker in template_markers)
        
        if has_template:
            feedback.append("❌ Template instructions not removed - document appears incomplete")
            # If template is still there, likely nothing was done
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Document still contains template instructions. Please complete the task by creating the structured behavioral log."
            }
        
        # Check length - should be substantial
        para_count = count_paragraphs(doc)
        word_count = len(full_text.split())
        
        if word_count < 200:
            feedback.append(f"⚠️ Document too short ({word_count} words) - may be incomplete")
        
        # Check 1: Contains patient identification/header (1 point)
        header_indicators = ["behavioral observation log", "observation log", "margaret", "chen", "patient"]
        header_score = sum(1 for indicator in header_indicators if indicator in full_text_lower)
        
        if header_score >= 2:
            score += 1.0
            feedback.append("✓ Patient identification header present")
        else:
            feedback.append("✗ Missing patient identification header")

        # Check 2: Contains observation period/date range (1 point)
        date_indicators = ["january", "1/", "2024", "observation period", "period:", "dates:"]
        has_dates = any(indicator in full_text_lower for indicator in date_indicators)
        
        # Also check for specific date mentions
        date_pattern = r'1/\d{1,2}|january\s+\d{1,2}|jan\s+\d{1,2}'
        date_matches = re.findall(date_pattern, full_text_lower)
        
        if has_dates or len(date_matches) >= 2:
            score += 1.0
            feedback.append("✓ Observation period/dates indicated")
        else:
            feedback.append("✗ Missing observation period or date references")

        # Check 3: Multiple incidents documented (2 points)
        # Count date references (should be at least 6-8 for the incidents)
        date_count = len(re.findall(r'1/\d{1,2}', full_text)) + len(re.findall(r'january\s+\d{1,2}', full_text_lower))
        
        # Also look for incident-related keywords
        incident_keywords = ["visit", "found", "stove", "forgot", "confused", "called", "crying", 
                            "grocery", "lost", "mail", "agitated", "pacing", "wearing coat", "microwave"]
        incident_mentions = sum(1 for keyword in incident_keywords if keyword in full_text_lower)
        
        if date_count >= 6 and incident_mentions >= 5:
            score += 2.0
            feedback.append(f"✓ Multiple incidents documented ({date_count} date refs, {incident_mentions} incident keywords)")
        elif date_count >= 4 or incident_mentions >= 3:
            score += 1.0
            feedback.append(f"⚠ Some incidents documented but fewer than expected ({date_count} dates, {incident_mentions} incidents)")
        else:
            feedback.append(f"✗ Insufficient incidents documented ({date_count} dates, {incident_mentions} incidents)")

        # Check 4: Multiple behavior categories present (2 points)
        categories_found = []
        category_keywords = {
            'memory': ['memory', 'forgot', 'remember', 'asked multiple times', 'couldn\'t remember', 'forgetful'],
            'safety': ['safety', 'stove', 'burner', 'lost', 'danger', 'concern'],
            'mood': ['mood', 'agitation', 'agitated', 'crying', 'distress', 'upset', 'paranoid', 'suspicious', 'restless', 'pacing'],
            'orientation': ['orientation', 'confused', 'thought it was', 'day of the week', 'reorient', 'disoriented', 'sunday'],
            'adl': ['adl', 'activities of daily living', 'microwave', 'mail', 'bills', 'coat', 'thermostat', 'daily activities']
        }
        
        for category, keywords in category_keywords.items():
            if any(kw in full_text_lower for kw in keywords):
                categories_found.append(category)
        
        if len(categories_found) >= 4:
            score += 2.0
            feedback.append(f"✓ Multiple behavior categories covered ({len(categories_found)} categories: {', '.join(categories_found)})")
        elif len(categories_found) >= 2:
            score += 1.0
            feedback.append(f"⚠ Some categories present but limited diversity ({len(categories_found)} categories)")
        else:
            feedback.append("✗ Insufficient behavioral category diversity")

        # Check 5: Pattern summary/analysis section (2 points)
        pattern_indicators = ["pattern", "frequency", "sundowning", "evening", "time of day", 
                             "summary", "trends", "typically", "often", "repeatedly", "recurring",
                             "3 times", "multiple times", "getting worse"]
        pattern_mentions = sum(1 for indicator in pattern_indicators if indicator in full_text_lower)
        
        # Look for analytical language
        analysis_phrases = ["appears to", "seems to", "indicates", "suggests", "shows", "demonstrates",
                           "increasing", "worsening", "improving", "consistent with"]
        analysis_count = sum(1 for phrase in analysis_phrases if phrase in full_text_lower)
        
        total_pattern_score = pattern_mentions + analysis_count
        
        if total_pattern_score >= 3:
            score += 2.0
            feedback.append(f"✓ Pattern analysis present ({total_pattern_score} indicators)")
        elif total_pattern_score >= 1:
            score += 1.0
            feedback.append(f"⚠ Limited pattern analysis ({total_pattern_score} indicators)")
        else:
            feedback.append("✗ Missing pattern summary/analysis")

        # Check 6: Questions/concerns for doctor (1 point)
        question_indicators = ["question", "medication", "adjust", "increase care", "safety", 
                              "consider", "should we", "is it time", "do we need", "donepezil",
                              "neurologist", "doctor", "recommendation"]
        questions_found = sum(1 for q in question_indicators if q in full_text_lower)
        
        # Look for question marks
        question_marks = full_text.count("?")
        
        if questions_found >= 2 or question_marks >= 2:
            score += 1.0
            feedback.append(f"✓ Questions for doctor included ({question_marks} question marks)")
        else:
            feedback.append("✗ Missing questions for neurologist")

        # Check 7: Professional formatting (1 point)
        # Check for bold text (headers)
        has_bold = any(run.bold for para in doc.paragraphs for run in para.runs if run.bold)
        
        # Check for reasonable structure (multiple paragraphs)
        has_structure = para_count >= 15  # Should be well-organized with multiple sections
        
        if has_bold and has_structure:
            score += 1.0
            feedback.append(f"✓ Professional formatting with clear structure ({para_count} paragraphs)")
        elif has_structure:
            score += 0.5
            feedback.append(f"⚠ Document has structure but could use better formatting ({para_count} paragraphs)")
        else:
            feedback.append(f"✗ Poor formatting/structure ({para_count} paragraphs)")

        # Check 8: Contains key details from raw notes (1 point)
        # Check for specific details that should be included
        key_details = ["tom", "sarah", "stove", "empty pot", "dad", "2019", "funeral", 
                      "grocery", "cereal aisle", "thermostat", "72", "winter coat"]
        details_found = sum(1 for detail in key_details if detail in full_text_lower)
        
        if details_found >= 6:
            score += 1.0
            feedback.append(f"✓ Key details from observations included ({details_found}/12)")
        elif details_found >= 3:
            score += 0.5
            feedback.append(f"⚠ Some details included but missing others ({details_found}/12)")
        else:
            feedback.append(f"✗ Missing key details from raw notes ({details_found}/12)")

        # Normalize score
        final_score = score / max_score
        passed = final_score >= 0.70
        
        feedback_text = " | ".join(feedback)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback_text
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
