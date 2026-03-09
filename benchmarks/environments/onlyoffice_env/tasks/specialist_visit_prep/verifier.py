#!/usr/bin/env python3
"""
Verifier for Specialist Visit Prep task
Verifies that a professional medical summary was created from messy notes
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_specialist_prep(traj, env_info, task_info):
    """
    Verify that the medical summary document was properly created and formatted.

    Scoring rubric (100 points total):
    - Document saved and parseable: 15 points
    - Contains ≥5 section headers: 15 points
    - Headers are bold formatted: 15 points
    - At least one header ≥14pt: 10 points
    - Medications mentioned with dosages: 15 points
    - Timeline with ≥3 dates: 10 points
    - Both allergies listed: 10 points
    - Reasonable length (200-800 words): 5 points
    - Multiple paragraphs/structure: 5 points
    
    Passing score: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/specialist_summary.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_medical_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document not found or failed to parse: {error}"
            }

        score = 0
        max_score = 100
        feedback_parts = []

        # Check 1: Document saved and parseable (15 points)
        score += 15
        feedback_parts.append("✅ Document saved and parseable (+15)")

        # Extract full text for content checks
        full_text = get_document_text(doc).lower()
        word_count = len(full_text.split())

        # Check 2: Section headers present (15 points)
        # Look for keywords that indicate the required sections
        section_keywords = [
            'medication',  # Current Medications
            'symptom',     # Symptom Timeline or Chief Complaint
            'test',        # Test Results
            'treatment',   # Treatments Tried
            'allerg',      # Allergies
            'family',      # Family History
            'complaint'    # Chief Complaint
        ]
        
        sections_found = sum(1 for keyword in section_keywords if keyword in full_text)
        
        if sections_found >= 5:
            score += 15
            feedback_parts.append(f"✅ Found {sections_found}/7 section topics (+15)")
        elif sections_found >= 3:
            partial_score = int(15 * (sections_found / 5))
            score += partial_score
            feedback_parts.append(f"⚠️ Found only {sections_found}/7 sections (+{partial_score})")
        else:
            feedback_parts.append(f"❌ Found only {sections_found}/7 sections (0)")

        # Check 3: Headers are bold (15 points)
        bold_count = 0
        bold_texts = []
        
        for para in doc.paragraphs:
            para_text = para.text.strip()
            if len(para_text) == 0:
                continue
                
            # Check if the paragraph has bold runs
            has_bold = False
            for run in para.runs:
                if run.bold and len(run.text.strip()) > 0:
                    has_bold = True
                    bold_texts.append(run.text.strip()[:30])
                    break
            
            if has_bold:
                bold_count += 1

        if bold_count >= 4:
            score += 15
            feedback_parts.append(f"✅ Found {bold_count} bold formatted sections (+15)")
        elif bold_count >= 2:
            partial_score = int(15 * (bold_count / 4))
            score += partial_score
            feedback_parts.append(f"⚠️ Found only {bold_count} bold sections (+{partial_score})")
        else:
            feedback_parts.append(f"❌ Insufficient bold formatting ({bold_count} found)")

        # Check 4: Large font header (10 points)
        has_large_font = False
        large_font_size = 0
        
        for para in doc.paragraphs:
            for run in para.runs:
                if run.font.size:
                    size_pt = run.font.size.pt
                    if size_pt >= 14:
                        has_large_font = True
                        large_font_size = max(large_font_size, size_pt)

        if has_large_font:
            score += 10
            feedback_parts.append(f"✅ Found larger font header ({large_font_size}pt) (+10)")
        else:
            feedback_parts.append("⚠️ No headers with larger font size (≥14pt)")

        # Check 5: Medications with dosages (15 points)
        has_omeprazole = 'omeprazole' in full_text
        has_ibuprofen = 'ibuprofen' in full_text
        has_dosage = bool(re.search(r'\d+\s*mg', full_text)) or 'iu' in full_text
        
        med_score = 0
        if has_omeprazole and has_ibuprofen and has_dosage:
            med_score = 15
            feedback_parts.append("✅ Medications with dosages present (+15)")
        elif (has_omeprazole or has_ibuprofen) and has_dosage:
            med_score = 8
            feedback_parts.append("⚠️ Partial medication information (+8)")
        elif has_omeprazole or has_ibuprofen:
            med_score = 4
            feedback_parts.append("⚠️ Medications mentioned but missing dosages (+4)")
        else:
            feedback_parts.append("❌ Missing medication details (0)")
        
        score += med_score

        # Check 6: Timeline dates (10 points)
        # Look for month names and dates
        date_patterns = [
            r'\bjan(?:uary)?\s*\d{1,2}',
            r'\bfeb(?:ruary)?\s*\d{1,2}',
            r'\bmar(?:ch)?\s*\d{1,2}',
            r'\bapr(?:il)?\s*\d{1,2}',
            r'\bmay\s*\d{1,2}',
        ]
        month_year_patterns = [
            r'\bjan(?:uary)?\s*\d{4}',
            r'\bfeb(?:ruary)?\s*\d{4}',
            r'\bmar(?:ch)?\s*\d{4}',
            r'\bapr(?:il)?\s*\d{4}',
            r'\bmay\s*\d{4}',
        ]
        
        date_matches = []
        for pattern in date_patterns + month_year_patterns:
            date_matches.extend(re.findall(pattern, full_text, re.IGNORECASE))
        
        # Also check for just month mentions in context
        month_mentions = len(re.findall(r'\b(jan|feb|mar|march|apr|april|may)\b', full_text, re.IGNORECASE))
        
        total_dates = len(set(date_matches)) if date_matches else month_mentions
        
        if total_dates >= 3:
            score += 10
            feedback_parts.append(f"✅ Found {total_dates} timeline dates (+10)")
        elif total_dates >= 2:
            score += 5
            feedback_parts.append(f"⚠️ Found only {total_dates} timeline dates (+5)")
        else:
            feedback_parts.append("❌ Insufficient timeline information (0)")

        # Check 7: Allergies (10 points)
        has_penicillin = 'penicillin' in full_text
        has_latex = 'latex' in full_text
        
        if has_penicillin and has_latex:
            score += 10
            feedback_parts.append("✅ Both allergies listed (Penicillin, Latex) (+10)")
        elif has_penicillin or has_latex:
            score += 5
            allergy_found = "Penicillin" if has_penicillin else "Latex"
            feedback_parts.append(f"⚠️ Only {allergy_found} listed (+5)")
        else:
            feedback_parts.append("❌ Allergies not mentioned (CRITICAL OMISSION)")

        # Check 8: Reasonable length (5 points)
        if 200 <= word_count <= 800:
            score += 5
            feedback_parts.append(f"✅ Appropriate length ({word_count} words) (+5)")
        elif 100 <= word_count < 200:
            score += 3
            feedback_parts.append(f"⚠️ Somewhat brief ({word_count} words) (+3)")
        elif word_count < 100:
            feedback_parts.append(f"❌ Too brief ({word_count} words) - needs more detail")
        else:
            feedback_parts.append(f"⚠️ Very long ({word_count} words) - may exceed 1 page (+3)")
            score += 3

        # Check 9: Multiple paragraphs/structure (5 points)
        para_count = len([p for p in doc.paragraphs if len(p.text.strip()) > 10])
        
        if para_count >= 7:
            score += 5
            feedback_parts.append(f"✅ Well-structured ({para_count} paragraphs) (+5)")
        elif para_count >= 4:
            score += 3
            feedback_parts.append(f"⚠️ Basic structure ({para_count} paragraphs) (+3)")
        else:
            feedback_parts.append(f"❌ Poor structure ({para_count} paragraphs) - needs better organization")

        # Final scoring
        passed = score >= 70
        normalized_score = score / max_score

        feedback = " | ".join(feedback_parts)
        final_feedback = f"Score: {score}/{max_score} | {feedback}"

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": final_feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
