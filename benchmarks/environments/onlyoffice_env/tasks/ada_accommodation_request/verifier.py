#!/usr/bin/env python3
"""
Verifier for ADA Accommodation Request task

Verifies that the agent created a professional, complete ADA accommodation
request document with proper structure, formatting, and content.
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


def verify_ada_request(traj, env_info, task_info):
    """
    Verify that ADA accommodation request document was created correctly.

    Criteria (6 total, need 4+ to pass at 67%):
    1. Document exists and is properly saved
    2. Professional structure and formatting
    3. Legal framework acknowledgment
    4. Medical documentation reference
    5. Specific accommodation requests
    6. Substantive content and completeness
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/ADA_Request/accommodation_request.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_ada_')

    try:
        # Criterion 1: File exists and is valid
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document not found or invalid: {error}"
            }

        # Extract text and metadata
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        word_count = len(full_text.split())
        
        criteria_met = 0
        feedback_parts = []
        
        # Criterion 1: Passed (file exists and is valid)
        criteria_met += 1
        feedback_parts.append(f"✅ C1: Document exists and is valid DOCX")
        
        # Criterion 2: Professional structure and formatting
        has_structure = False
        
        # Check for formal letter elements
        has_recipient = any(keyword in full_text_lower for keyword in [
            'to:', 'dear', 'hr department', 'human resources', 'director'
        ])
        
        # Check for subject line about accommodation
        has_subject = any(keyword in full_text_lower for keyword in [
            'subject:', 're:', 'regarding'
        ]) and any(keyword in full_text_lower for keyword in [
            'accommodation', 'ada', 'disability', 'request'
        ])
        
        # Check for bold formatting (indicates professional structure)
        has_bold = False
        bold_count = 0
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold and run.text.strip():
                    has_bold = True
                    bold_count += 1
                    if bold_count >= 2:
                        break
            if bold_count >= 2:
                break
        
        # Check paragraph structure (at least 4 distinct sections)
        non_empty_paras = [p for p in doc.paragraphs if p.text.strip() and len(p.text.strip()) > 10]
        has_sections = len(non_empty_paras) >= 4
        
        structure_score = sum([has_recipient, has_subject, has_bold, has_sections])
        
        if structure_score >= 3:
            criteria_met += 1
            has_structure = True
            feedback_parts.append(
                f"✅ C2: Professional structure (recipient: {has_recipient}, "
                f"subject: {has_subject}, bold: {has_bold}, sections: {has_sections})"
            )
        else:
            feedback_parts.append(
                f"❌ C2: Structure incomplete (score: {structure_score}/4 - "
                f"recipient: {has_recipient}, subject: {has_subject}, "
                f"bold: {has_bold}, sections: {has_sections})"
            )
        
        # Criterion 3: Legal framework acknowledgment
        legal_keywords = [
            'ada', 'americans with disabilities', 'reasonable accommodation',
            'disability', 'americans with disability act'
        ]
        legal_mentions = sum(1 for kw in legal_keywords if kw in full_text_lower)
        has_legal = legal_mentions >= 1
        
        # Check for professional/formal tone indicators
        formal_indicators = ['request', 'pursuant', 'accordance', 'formally', 'hereby']
        has_formal_tone = any(ind in full_text_lower for ind in formal_indicators)
        
        if has_legal and (legal_mentions >= 1 or has_formal_tone):
            criteria_met += 1
            feedback_parts.append(
                f"✅ C3: References ADA/legal framework ({legal_mentions} mentions)"
            )
        else:
            feedback_parts.append(
                f"❌ C3: Missing ADA/legal framework (found {legal_mentions} mentions)"
            )
        
        # Criterion 4: Medical documentation reference
        medical_keywords = [
            'medical', 'doctor', 'dr.', 'physician', 'diagnosis', 'condition',
            'migraine', 'health', 'documentation', 'clinical'
        ]
        medical_mentions = sum(1 for kw in medical_keywords if kw in full_text_lower)
        
        # Check for specific condition mentions
        condition_keywords = ['migraine', 'chronic', 'photosensitivity', 'light sensitivity']
        has_condition = any(kw in full_text_lower for kw in condition_keywords)
        
        # Check for work limitations connection
        limitation_keywords = [
            'limitation', 'difficulty', 'affect', 'impact', 'challenge',
            'trigger', 'symptom'
        ]
        has_limitations = any(kw in full_text_lower for kw in limitation_keywords)
        
        # Check document isn't overly long (not oversharing)
        not_oversharing = word_count < 1200
        
        medical_score = sum([medical_mentions >= 2, has_condition, has_limitations, not_oversharing])
        
        if medical_score >= 3:
            criteria_met += 1
            feedback_parts.append(
                f"✅ C4: Medical documentation referenced appropriately "
                f"(mentions: {medical_mentions}, condition: {has_condition}, "
                f"limitations: {has_limitations})"
            )
        else:
            feedback_parts.append(
                f"❌ C4: Medical reference incomplete (score: {medical_score}/4)"
            )
        
        # Criterion 5: Specific accommodation requests
        accommodation_keywords = [
            'lighting', 'light', 'lamp', 'fluorescent',
            'screen', 'monitor', 'filter', 'glare',
            'flexible', 'schedule', 'start time', 'hours',
            'work from home', 'remote', 'telework',
            'break', 'rest', 'pause',
            'quiet', 'workspace', 'office',
            'desk', 'ergonomic', 'equipment'
        ]
        
        accommodation_mentions = sum(1 for kw in accommodation_keywords if kw in full_text_lower)
        
        # Check for list structure or multiple distinct requests
        # Look for numbered lists or bullet points
        has_list_markers = bool(
            re.search(r'[1-9]\.|[-•*]', full_text) or
            any(para.style.name.startswith('List') for para in doc.paragraphs if para.style)
        )
        
        # Count distinct accommodation categories mentioned
        accommodation_categories = {
            'lighting': any(kw in full_text_lower for kw in ['lighting', 'light', 'lamp', 'fluorescent']),
            'screen': any(kw in full_text_lower for kw in ['screen', 'monitor', 'filter', 'glare']),
            'schedule': any(kw in full_text_lower for kw in ['flexible', 'schedule', 'start time', 'hours']),
            'remote': any(kw in full_text_lower for kw in ['work from home', 'remote', 'telework']),
            'breaks': any(kw in full_text_lower for kw in ['break', 'rest', 'pause']),
            'workspace': any(kw in full_text_lower for kw in ['quiet', 'workspace', 'office']),
            'equipment': any(kw in full_text_lower for kw in ['desk', 'ergonomic', 'equipment'])
        }
        categories_mentioned = sum(accommodation_categories.values())
        
        accommodation_score = sum([
            accommodation_mentions >= 3,
            categories_mentioned >= 3,
            has_list_markers or accommodation_mentions >= 5
        ])
        
        if accommodation_score >= 2:
            criteria_met += 1
            feedback_parts.append(
                f"✅ C5: Specific accommodations requested "
                f"({accommodation_mentions} keywords, {categories_mentioned} categories)"
            )
        else:
            feedback_parts.append(
                f"❌ C5: Insufficient accommodations "
                f"({accommodation_mentions} keywords, {categories_mentioned} categories, need 3+)"
            )
        
        # Criterion 6: Substantive content and completeness
        is_substantial = word_count >= 300
        
        # Check for explanation of how accommodations help
        help_keywords = [
            'help', 'allow', 'enable', 'improve', 'perform',
            'reduce', 'prevent', 'maintain', 'support', 'assist'
        ]
        has_explanation = sum(1 for kw in help_keywords if kw in full_text_lower) >= 2
        
        # Check for job performance connection
        job_keywords = [
            'job', 'work', 'duties', 'responsibilities', 'performance',
            'productivity', 'task', 'role', 'position'
        ]
        has_job_connection = any(kw in full_text_lower for kw in job_keywords)
        
        # Check for closing requesting next steps
        closing_keywords = [
            'meeting', 'discuss', 'conversation', 'next steps', 'follow up',
            'interactive process', 'review', 'schedule', 'available'
        ]
        has_closing = any(kw in full_text_lower for kw in closing_keywords)
        
        # Check document isn't just the template
        is_not_template = word_count > 200 and 'begin your letter' not in full_text_lower
        
        completeness_score = sum([
            is_substantial,
            has_explanation,
            has_job_connection,
            has_closing,
            is_not_template
        ])
        
        if completeness_score >= 4:
            criteria_met += 1
            feedback_parts.append(
                f"✅ C6: Document complete and substantial "
                f"({word_count} words, explanation: {has_explanation}, "
                f"job connection: {has_job_connection}, closing: {has_closing})"
            )
        else:
            feedback_parts.append(
                f"❌ C6: Document incomplete "
                f"(score: {completeness_score}/5, {word_count} words)"
            )
        
        # Calculate final score
        score = round((criteria_met / 6.0) * 100, 1)
        passed = score >= 67  # Need at least 4/6 criteria (67%)
        
        # Build detailed feedback
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        summary = f"Score: {criteria_met}/6 criteria met ({score}%). "
        if passed:
            summary += "✅ PASSED - Document meets ADA request standards."
        else:
            summary += "❌ FAILED - Document needs improvement."
        
        final_feedback = summary + " || " + feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback
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
