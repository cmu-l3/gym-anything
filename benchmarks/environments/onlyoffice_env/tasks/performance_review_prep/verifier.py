#!/usr/bin/env python3
"""
Verifier for Performance Review Prep task

Checks transformation of messy achievement notes into professional brag sheet:
1. Document structure (Heading 1 title + multiple Heading 2 sections)
2. Consistent bullet point formatting
3. Quantification with bold emphasis on metrics
4. Strong action verbs (not weak language)
5. Professional organization
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, List, Tuple, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_paragraphs_with_style(doc: Any, style_name: str) -> int:
    """Count paragraphs with specific style (e.g., 'Heading 1', 'Heading 2')"""
    count = 0
    try:
        for para in doc.paragraphs:
            if para.style.name == style_name:
                count += 1
    except Exception as e:
        logger.warning(f"Error counting paragraphs with style {style_name}: {e}")
    return count


def count_bullet_paragraphs(doc: Any) -> int:
    """Count paragraphs formatted as bullets (List Bullet style or bullet numbering)"""
    count = 0
    try:
        for para in doc.paragraphs:
            # Check if it's a list bullet style
            if para.style.name in ['List Bullet', 'List Bullet 2', 'List Bullet 3']:
                count += 1
            # Check if paragraph has numbering format (bullet or numbered)
            elif para._element.pPr is not None:
                numPr = para._element.pPr.find('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}numPr')
                if numPr is not None:
                    count += 1
    except Exception as e:
        logger.warning(f"Error counting bullet paragraphs: {e}")
    return count


def count_non_heading_content_paragraphs(doc: Any) -> int:
    """Count content paragraphs (excluding headings and empty paragraphs)"""
    count = 0
    try:
        for para in doc.paragraphs:
            # Skip headings
            if 'Heading' in para.style.name:
                continue
            # Skip empty or very short paragraphs
            if len(para.text.strip()) < 10:
                continue
            count += 1
    except Exception as e:
        logger.warning(f"Error counting content paragraphs: {e}")
    return count


def extract_numbers_from_doc(doc: Any) -> List[Tuple[str, bool]]:
    """
    Extract all numeric values from document and check if they're bold
    Returns list of tuples: (numeric_string, is_bold)
    """
    numbers = []
    number_pattern = re.compile(r'\b\d+(?:[.,]\d+)?(?:%|K|M)?\b')
    
    try:
        for para in doc.paragraphs:
            for run in para.runs:
                # Find all numbers in this run
                matches = number_pattern.findall(run.text)
                for match in matches:
                    is_bold = run.bold if run.bold is not None else False
                    numbers.append((match, is_bold))
    except Exception as e:
        logger.warning(f"Error extracting numbers: {e}")
    
    return numbers


def count_bold_numeric_values(doc: Any) -> int:
    """Count how many numeric values are bolded"""
    numbers = extract_numbers_from_doc(doc)
    return sum(1 for _, is_bold in numbers if is_bold)


def count_total_numeric_values(doc: Any) -> int:
    """Count total numeric values in document"""
    numbers = extract_numbers_from_doc(doc)
    return len(numbers)


def analyze_language_quality(doc: Any) -> Dict[str, int]:
    """
    Analyze language quality by counting weak vs strong verbs
    Returns dict with weak_count and strong_count
    """
    weak_verbs = [
        'helped', 'help', 'helped with',
        'worked on', 'worked with', 'work on',
        'participated', 'participate', 'participated in',
        'assisted', 'assist',
        'contributed to', 'contribute to'
    ]
    
    strong_verbs = [
        'led', 'lead',
        'delivered', 'deliver',
        'implemented', 'implement',
        'launched', 'launch',
        'achieved', 'achieve',
        'increased', 'increase',
        'reduced', 'reduce',
        'improved', 'improve',
        'completed', 'complete',
        'organized', 'organize',
        'facilitated', 'facilitate',
        'coordinated', 'coordinate',
        'streamlined', 'streamline',
        'optimized', 'optimize',
        'designed', 'design',
        'created', 'create',
        'established', 'establish'
    ]
    
    text_lower = get_document_text(doc).lower()
    
    weak_count = sum(text_lower.count(verb) for verb in weak_verbs)
    strong_count = sum(text_lower.count(verb) for verb in strong_verbs)
    
    return {
        'weak_count': weak_count,
        'strong_count': strong_count
    }


def verify_performance_review_prep(traj, env_info, task_info):
    """
    Verify that messy achievement notes were transformed into professional brag sheet.

    Scoring breakdown (100 points total):
    - Structure (20 pts): Heading 1 title + 3+ Heading 2 sections
    - Formatting (20 pts): Consistent bullet formatting (>80% of content)
    - Quantification (25 pts): ≥70% of achievements have numeric metrics
    - Language (20 pts): Strong action verbs dominate (>3x weak verbs)
    - Metric emphasis (15 pts): ≥70% of numbers are bolded
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Try both the expected filename and the original draft name
    possible_paths = [
        "/home/ga/Documents/TextDocuments/Maya_Thompson_2024_Brag_Sheet.docx",
        "/home/ga/Documents/TextDocuments/achievement_notes_2024_DRAFT.docx"
    ]
    
    doc = None
    used_path = None
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_review_')

    try:
        # Try to find the document
        for container_path in possible_paths:
            success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
            if success:
                used_path = container_path
                logger.info(f"Successfully loaded document from: {container_path}")
                break
        
        if not doc:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to load document from any expected location. Tried: {', '.join(possible_paths)}"
            }

        score = 0
        feedback_parts = []
        details = {}

        # ============================================================
        # Criterion 1: Document Structure (20 points)
        # ============================================================
        heading1_count = count_paragraphs_with_style(doc, 'Heading 1')
        heading2_count = count_paragraphs_with_style(doc, 'Heading 2')
        
        structure_score = 0
        if heading1_count >= 1 and heading2_count >= 3:
            structure_score = 20
            feedback_parts.append(f"✅ Professional structure: {heading1_count} main title, {heading2_count} sections")
        elif heading1_count >= 1 and heading2_count >= 2:
            structure_score = 12
            feedback_parts.append(f"⚠️ Partial structure: {heading1_count} title, {heading2_count} sections (need 3+)")
        elif heading2_count >= 2:
            structure_score = 8
            feedback_parts.append(f"⚠️ Minimal structure: {heading2_count} sections but missing main title")
        else:
            feedback_parts.append(f"❌ Weak structure: {heading1_count} title, {heading2_count} sections (need 1 title + 3+ sections)")
        
        score += structure_score
        details['structure_score'] = structure_score
        details['heading1_count'] = heading1_count
        details['heading2_count'] = heading2_count

        # ============================================================
        # Criterion 2: Consistent Bullet Formatting (20 points)
        # ============================================================
        bullet_count = count_bullet_paragraphs(doc)
        content_para_count = count_non_heading_content_paragraphs(doc)
        
        formatting_score = 0
        if content_para_count > 0:
            bullet_ratio = bullet_count / content_para_count
            
            if bullet_ratio >= 0.80:
                formatting_score = 20
                feedback_parts.append(f"✅ Excellent formatting: {int(bullet_ratio*100)}% consistent bullets")
            elif bullet_ratio >= 0.60:
                formatting_score = 12
                feedback_parts.append(f"⚠️ Good formatting: {int(bullet_ratio*100)}% bullets (aim for 80%+)")
            elif bullet_ratio >= 0.40:
                formatting_score = 6
                feedback_parts.append(f"⚠️ Partial formatting: {int(bullet_ratio*100)}% bullets (inconsistent)")
            else:
                feedback_parts.append(f"❌ Poor formatting: {int(bullet_ratio*100)}% bullets (need consistent formatting)")
            
            details['bullet_ratio'] = bullet_ratio
        else:
            feedback_parts.append("❌ No content paragraphs found")
            details['bullet_ratio'] = 0
        
        score += formatting_score
        details['formatting_score'] = formatting_score

        # ============================================================
        # Criterion 3: Quantification (25 points)
        # ============================================================
        total_numbers = count_total_numeric_values(doc)
        
        # Estimate "achievements" as non-heading, non-empty paragraphs
        achievement_count = content_para_count if content_para_count > 0 else 1
        
        quantification_score = 0
        if total_numbers >= achievement_count * 0.7:
            quantification_score = 25
            quantification_rate = min(total_numbers / achievement_count, 1.0)
            feedback_parts.append(f"✅ Strong quantification: ~{int(quantification_rate*100)}% achievements have metrics")
        elif total_numbers >= achievement_count * 0.5:
            quantification_score = 15
            quantification_rate = total_numbers / achievement_count
            feedback_parts.append(f"⚠️ Moderate quantification: ~{int(quantification_rate*100)}% (aim for 70%+)")
        elif total_numbers >= achievement_count * 0.3:
            quantification_score = 8
            quantification_rate = total_numbers / achievement_count
            feedback_parts.append(f"⚠️ Weak quantification: ~{int(quantification_rate*100)}% (need more metrics)")
        else:
            quantification_rate = total_numbers / achievement_count if achievement_count > 0 else 0
            feedback_parts.append(f"❌ Insufficient quantification: ~{int(quantification_rate*100)}% (too few metrics)")
        
        score += quantification_score
        details['quantification_score'] = quantification_score
        details['total_numbers'] = total_numbers
        details['achievement_count'] = achievement_count

        # ============================================================
        # Criterion 4: Strong Language (20 points)
        # ============================================================
        language_analysis = analyze_language_quality(doc)
        weak_count = language_analysis['weak_count']
        strong_count = language_analysis['strong_count']
        
        language_score = 0
        if strong_count > weak_count * 3 and strong_count >= 5:
            language_score = 20
            feedback_parts.append(f"✅ Strong action verbs: {strong_count} strong vs {weak_count} weak")
        elif strong_count > weak_count and strong_count >= 3:
            language_score = 12
            feedback_parts.append(f"⚠️ Mixed language: {strong_count} strong vs {weak_count} weak (strengthen more)")
        elif strong_count >= weak_count:
            language_score = 6
            feedback_parts.append(f"⚠️ Weak language persists: {strong_count} strong vs {weak_count} weak")
        else:
            feedback_parts.append(f"❌ Language not improved: {strong_count} strong vs {weak_count} weak verbs")
        
        score += language_score
        details['language_score'] = language_score
        details['strong_verb_count'] = strong_count
        details['weak_verb_count'] = weak_count

        # ============================================================
        # Criterion 5: Bold Metric Emphasis (15 points)
        # ============================================================
        bold_numbers = count_bold_numeric_values(doc)
        
        emphasis_score = 0
        if total_numbers > 0:
            bold_ratio = bold_numbers / total_numbers
            
            if bold_ratio >= 0.70:
                emphasis_score = 15
                feedback_parts.append(f"✅ Metrics emphasized: {bold_numbers}/{total_numbers} numbers bolded ({int(bold_ratio*100)}%)")
            elif bold_ratio >= 0.50:
                emphasis_score = 9
                feedback_parts.append(f"⚠️ Partial emphasis: {bold_numbers}/{total_numbers} numbers bolded (aim for 70%+)")
            elif bold_ratio >= 0.30:
                emphasis_score = 4
                feedback_parts.append(f"⚠️ Weak emphasis: {bold_numbers}/{total_numbers} numbers bolded (need more)")
            else:
                feedback_parts.append(f"❌ Metrics not emphasized: only {bold_numbers}/{total_numbers} numbers bolded")
            
            details['bold_ratio'] = bold_ratio
        else:
            feedback_parts.append("⚠️ No metrics found to emphasize")
            details['bold_ratio'] = 0
        
        score += emphasis_score
        details['emphasis_score'] = emphasis_score
        details['bold_numbers'] = bold_numbers

        # ============================================================
        # Final Assessment
        # ============================================================
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        # Add filename info to feedback if not using expected name
        if used_path and "DRAFT" in used_path:
            feedback += " | ⚠️ Document not renamed to 'Maya_Thompson_2024_Brag_Sheet.docx'"

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
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