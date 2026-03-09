#!/usr/bin/env python3
"""
Verifier for Neighborhood Petition task
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
    count_paragraphs,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_petition_document(traj, env_info, task_info):
    """
    Verify that neighborhood petition was created correctly.

    Checks:
    1. Document has petition-style title with traffic/safety keywords (20 pts)
    2. Document is addressed to authority (city council, officials) (15 pts)
    3. Contains problem statement about traffic/speeding (20 pts)
    4. Contains proposed solution (speed bump, stop sign) (15 pts)
    5. Has signature section with multiple signature lines (20 pts)
    6. Uses professional formatting (bold for headings) (10 pts)
    
    Pass threshold: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/traffic_safety_petition.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_petition_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load petition document: {error}"}

        score = 0
        feedback_parts = []

        # Extract full document text
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        logger.info(f"Document text length: {len(full_text)}")
        logger.info(f"Document preview: {full_text[:300]}")

        # Check if document is not essentially blank
        if len(full_text.strip()) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Document is essentially blank or too short (needs at least 100 characters)"
            }

        # Criterion 1: Petition Title (20 points)
        title_score = 0
        title_keywords = ['petition', 'traffic', 'safety', 'neighborhood', 'street', 'residential']
        title_found = False
        
        # Check first few paragraphs for title
        for para in doc.paragraphs[:5]:
            para_text = para.text.strip()
            para_lower = para_text.lower()
            
            # Check if this paragraph looks like a title
            if len(para_text) > 5 and any(keyword in para_lower for keyword in title_keywords):
                # Extra points if it has multiple keywords (more likely to be the actual title)
                keyword_count = sum(1 for kw in title_keywords if kw in para_lower)
                
                if keyword_count >= 2:
                    title_found = True
                    title_score += 10
                    feedback_parts.append(f"✅ Petition title found: '{para_text[:50]}...'")
                    
                    # Check if title is bold
                    has_bold = any(run.bold for run in para.runs if run.text.strip())
                    if has_bold:
                        title_score += 10
                        feedback_parts.append("✅ Title is properly formatted (bold)")
                    else:
                        title_score += 5
                        feedback_parts.append("⚠️ Title present but should be bold for emphasis")
                    break
                elif not title_found:  # First relevant paragraph, even if only one keyword
                    title_found = True
                    title_score += 8
                    feedback_parts.append(f"⚠️ Petition title found but could be more explicit")
                    
                    has_bold = any(run.bold for run in para.runs if run.text.strip())
                    if has_bold:
                        title_score += 7
                    else:
                        title_score += 3
                    break
        
        if not title_found:
            feedback_parts.append("❌ No clear petition title found in document header")
        
        score += title_score

        # Criterion 2: Addressee - City Council/Officials (15 points)
        addressee_keywords = ['council', 'city', 'officials', 'mayor', 'department', 'to:']
        addressee_patterns = ['to:', 'dear', 'attention:', 're:']
        
        # Look for addressee in first portion of document
        first_portion = full_text_lower[:500]
        
        has_addressee_keyword = any(keyword in first_portion for keyword in addressee_keywords)
        has_addressee_pattern = any(pattern in first_portion for pattern in addressee_patterns)
        
        if has_addressee_keyword:
            score += 15
            feedback_parts.append("✅ Document addresses proper authority (city council/officials)")
        elif has_addressee_pattern:
            score += 8
            feedback_parts.append("⚠️ Document has addressee format but should specify city council")
        else:
            feedback_parts.append("❌ Document should be addressed to city council or officials")

        # Criterion 3: Problem Statement (20 points)
        problem_keywords = ['speed', 'speeding', 'traffic', 'dangerous', 'danger', 'risk', 'children', 
                           'kids', 'safety', 'unsafe', 'cars', 'vehicles', 'fast', 'residential']
        problem_keyword_count = sum(1 for keyword in problem_keywords if keyword in full_text_lower)
        
        logger.info(f"Problem keywords found: {problem_keyword_count}")
        
        if problem_keyword_count >= 4:
            score += 20
            feedback_parts.append(f"✅ Problem statement present with {problem_keyword_count} relevant keywords")
        elif problem_keyword_count >= 3:
            score += 15
            feedback_parts.append(f"✅ Problem statement present ({problem_keyword_count} keywords)")
        elif problem_keyword_count >= 2:
            score += 8
            feedback_parts.append(f"⚠️ Problem statement partially present ({problem_keyword_count} keywords)")
        else:
            feedback_parts.append("❌ Problem statement missing or inadequate")

        # Criterion 4: Proposed Solution (15 points)
        solution_keywords = ['request', 'propose', 'proposed', 'solution', 'speed bump', 'bump', 
                            'stop sign', 'sign', 'traffic calming', 'install', 'installation', 
                            'demand', 'ask', 'seeking']
        solution_keyword_count = sum(1 for keyword in solution_keywords if keyword in full_text_lower)
        
        if solution_keyword_count >= 2:
            score += 15
            feedback_parts.append("✅ Proposed solution clearly stated")
        elif solution_keyword_count >= 1:
            score += 8
            feedback_parts.append("⚠️ Solution mentioned but could be more explicit")
        else:
            feedback_parts.append("❌ No clear proposed solution found")

        # Criterion 5: Signature Section (20 points)
        signature_score = 0
        
        # Check for signature heading/section
        if 'signature' in full_text_lower:
            signature_score += 5
            feedback_parts.append("✅ Signature section header found")
        
        # Count underscore patterns (signature lines)
        # Look for patterns like "____" or "___" which indicate blank signature lines
        underscore_pattern = r'_{3,}'
        underscore_matches = re.findall(underscore_pattern, full_text)
        underscore_count = len(underscore_matches)
        
        logger.info(f"Underscore signature lines found: {underscore_count}")
        
        if underscore_count >= 10:
            signature_score += 15
            feedback_parts.append(f"✅ Adequate signature lines present ({underscore_count} lines)")
        elif underscore_count >= 8:
            signature_score += 12
            feedback_parts.append(f"✅ Good number of signature lines ({underscore_count})")
        elif underscore_count >= 5:
            signature_score += 8
            feedback_parts.append(f"⚠️ Some signature lines present ({underscore_count}) but need at least 10")
        elif underscore_count >= 3:
            signature_score += 4
            feedback_parts.append(f"⚠️ Few signature lines ({underscore_count}), need at least 10")
        else:
            # Check if there are tables that might be used for signatures
            table_count = len(doc.tables)
            if table_count > 0:
                signature_score += 8
                feedback_parts.append(f"⚠️ Tables found ({table_count}), possibly for signatures but prefer underscored lines")
            else:
                feedback_parts.append("❌ Signature lines missing or insufficient")
        
        score += signature_score

        # Criterion 6: Professional Formatting (10 points)
        # Check for use of bold formatting (indicates structured document)
        bold_run_count = 0
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold and len(run.text.strip()) > 0:
                    bold_run_count += 1
        
        logger.info(f"Bold runs found: {bold_run_count}")
        
        if bold_run_count >= 4:
            score += 10
            feedback_parts.append(f"✅ Professional formatting with bold headings ({bold_run_count} bold sections)")
        elif bold_run_count >= 2:
            score += 7
            feedback_parts.append(f"✅ Good formatting ({bold_run_count} bold sections)")
        elif bold_run_count >= 1:
            score += 4
            feedback_parts.append("⚠️ Some formatting present but could use more structure")
        else:
            feedback_parts.append("⚠️ Document lacks formatting for professional appearance")

        # Bonus check: Document length (not scored, but informative)
        word_count = len(full_text.split())
        logger.info(f"Document word count: {word_count}")
        
        if word_count < 50:
            feedback_parts.append("⚠️ Document is quite short, consider adding more detail")

        # Calculate pass/fail
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/100, Passed: {passed}")

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)