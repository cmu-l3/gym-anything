#!/usr/bin/env python3
"""
Verifier for medication_history_reconstruction@1
Checks that user created comprehensive medication history from fragmented sources
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


def verify_medication_history_reconstruction(traj, env_info, task_info):
    """
    Verify medication history document meets requirements.
    
    Checks:
    1. Patient identification present (name and DOB)
    2. Current medications section with at least 2 medications
    3. Past medications section with at least 4 medications
    4. Discontinuation reasons documented
    5. Adverse reactions/allergies section
    6. Proper formatting (headings or bold)
    7. Document depth (word count)
    8. Chronological information present
    
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/medication_history_sarah_chen.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_med_history_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not open document: {error}"
            }

        # Extract full text
        full_text = get_document_text(doc)
        text_lower = full_text.lower()
        
        if len(full_text) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Document appears empty or too short (less than 100 characters)"
            }

        criteria_passed = 0
        max_criteria = 10
        feedback_parts = []

        # ===== Criterion 1: Patient identification (10 points) =====
        has_name = "sarah chen" in text_lower or "chen, sarah" in text_lower
        has_dob = any(pattern in text_lower for pattern in [
            "march 15, 1988", "3/15/1988", "03/15/1988", "15 march 1988",
            "march 15 1988", "3-15-1988"
        ]) or ("1988" in full_text and ("march" in text_lower or "3/15" in full_text))
        
        if has_name and has_dob:
            criteria_passed += 1
            feedback_parts.append("✅ Patient identification complete")
        elif has_name:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Patient name present but DOB unclear")
        else:
            feedback_parts.append("❌ Missing patient identification")

        # ===== Criterion 2: Current medications section (10 points) =====
        current_section_patterns = [
            r'\bcurrent\s+medication',
            r'\bactive\s+medication',
            r'\bcurrently\s+taking',
            r'\bpresent\s+medication'
        ]
        current_section_found = any(re.search(pattern, text_lower) for pattern in current_section_patterns)
        
        if current_section_found:
            feedback_parts.append("✅ Current medications section identified")
            criteria_passed += 0.5
            
            # Look for medications with dosages in the first 40% of document
            # (assumes current meds come before past meds)
            first_portion = full_text[:int(len(full_text) * 0.4)]
            
            # Count distinct current medications (propranolol and escitalopram)
            current_meds_count = 0
            if "propranolol" in first_portion.lower() and re.search(r'40\s*mg', first_portion):
                current_meds_count += 1
            if "escitalopram" in first_portion.lower() and re.search(r'10\s*mg', first_portion):
                current_meds_count += 1
            
            # Also check for sumatriptan as rescue medication
            if "sumatriptan" in first_portion.lower() and re.search(r'50\s*mg', first_portion):
                current_meds_count += 1
            
            if current_meds_count >= 2:
                criteria_passed += 0.5
                feedback_parts.append(f"✅ Found {current_meds_count} current medications with dosages")
            elif current_meds_count == 1:
                criteria_passed += 0.25
                feedback_parts.append(f"⚠️ Only found {current_meds_count} current medication")
            else:
                feedback_parts.append("❌ Current medications not adequately documented")
        else:
            feedback_parts.append("❌ No clear 'Current Medications' section found")

        # ===== Criterion 3: Past medications section (20 points) =====
        past_section_patterns = [
            r'\bpast\s+medication',
            r'\bdiscontinued\s+medication',
            r'\bprevious\s+medication',
            r'\bformer\s+medication',
            r'\bstopped\s+medication'
        ]
        past_section_found = any(re.search(pattern, text_lower) for pattern in past_section_patterns)
        
        if past_section_found:
            feedback_parts.append("✅ Past medications section identified")
            criteria_passed += 0.5
            
            # Count distinct medication names mentioned
            medication_names = [
                'amitriptyline', 'topiramate', 'sertraline', 'trazodone'
            ]
            found_meds = [med for med in medication_names if med in text_lower]
            
            if len(found_meds) >= 4:
                criteria_passed += 1.0
                feedback_parts.append(f"✅ Excellent: Found all {len(found_meds)} past medications")
            elif len(found_meds) >= 3:
                criteria_passed += 0.75
                feedback_parts.append(f"✅ Good: Found {len(found_meds)} past medications")
            elif len(found_meds) >= 2:
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Found only {len(found_meds)} past medications (expected 4+)")
            else:
                criteria_passed += 0.25
                feedback_parts.append(f"❌ Insufficient past medications documented ({len(found_meds)} found)")
            
            # Check for discontinuation reasons
            reason_patterns = [
                r'stopped\s+(due\s+to|because|after)',
                r'discontinued\s+(due\s+to|because|after)',
                r'switch(ed|ing)\s+to',
                r'caused?\s+(by|too|severe)',
                r'side\s+effect',
                r'made\s+.{1,50}(drowsy|sleepy|anxious|worse|stupid|tingl)',
                r'(too|very)\s+(drowsy|sleepy|tired)',
                r'worsened?\s+anxiety'
            ]
            
            reasons_count = 0
            for pattern in reason_patterns:
                matches = re.findall(pattern, text_lower)
                reasons_count += len(matches)
            
            if reasons_count >= 3:
                criteria_passed += 0.5
                feedback_parts.append(f"✅ Discontinuation reasons well documented ({reasons_count} mentions)")
            elif reasons_count >= 2:
                criteria_passed += 0.35
                feedback_parts.append(f"✅ Some discontinuation reasons present ({reasons_count} mentions)")
            elif reasons_count >= 1:
                criteria_passed += 0.15
                feedback_parts.append(f"⚠️ Limited discontinuation reasons ({reasons_count} found)")
            else:
                feedback_parts.append("❌ No clear discontinuation reasons documented")
        else:
            feedback_parts.append("❌ No clear 'Past Medications' section found")

        # ===== Criterion 4: Adverse reactions/allergies section (15 points) =====
        allergy_section_patterns = [
            r'\ballerg(y|ies)',
            r'\badverse\s+reaction',
            r'\bbad\s+reaction',
            r'\bdrug\s+reaction',
            r'\breaction'
        ]
        allergy_section = any(re.search(pattern, text_lower) for pattern in allergy_section_patterns)
        
        if allergy_section:
            criteria_passed += 0.5
            feedback_parts.append("✅ Allergies/reactions section present")
            
            # Check for specific documented reactions
            has_trazodone = 'trazodone' in text_lower and 'hive' in text_lower
            has_sertraline = 'sertraline' in text_lower and ('anxiety' in text_lower or 'palpitation' in text_lower)
            
            if has_trazodone and has_sertraline:
                criteria_passed += 1.0
                feedback_parts.append("✅ Both major adverse reactions documented (trazodone hives, sertraline anxiety)")
            elif has_trazodone or has_sertraline:
                criteria_passed += 0.5
                if has_trazodone:
                    feedback_parts.append("✅ Trazodone allergy documented")
                else:
                    feedback_parts.append("✅ Sertraline adverse reaction documented")
            else:
                # Check if any reactions are mentioned at all
                reaction_keywords = ['hive', 'rash', 'anxious', 'palpitation', 'allerg']
                has_any_reaction = any(keyword in text_lower for keyword in reaction_keywords)
                if has_any_reaction:
                    criteria_passed += 0.25
                    feedback_parts.append("⚠️ Some adverse reactions mentioned but details unclear")
                else:
                    feedback_parts.append("⚠️ Reactions section present but specific reactions not documented")
        else:
            feedback_parts.append("❌ No allergies/reactions section found")

        # ===== Criterion 5: Document formatting (10 points) =====
        # Check for use of headings or bold formatting
        has_headings = False
        has_bold = False
        
        try:
            # Check for heading styles
            for para in doc.paragraphs:
                if para.style.name.startswith('Heading'):
                    has_headings = True
                    break
            
            # Check for bold text
            for para in doc.paragraphs:
                for run in para.runs:
                    if run.bold:
                        has_bold = True
                        break
                if has_bold:
                    break
        except:
            pass
        
        if has_headings:
            criteria_passed += 1
            feedback_parts.append("✅ Document uses heading styles for organization")
        elif has_bold:
            criteria_passed += 0.75
            feedback_parts.append("✅ Document uses bold formatting for section headers")
        else:
            criteria_passed += 0.25
            feedback_parts.append("⚠️ Document could benefit from better formatting (headings or bold)")

        # ===== Criterion 6: Document depth/comprehensiveness (10 points) =====
        word_count = len(full_text.split())
        
        if word_count >= 400:
            criteria_passed += 1
            feedback_parts.append(f"✅ Document is comprehensive ({word_count} words)")
        elif word_count >= 300:
            criteria_passed += 0.75
            feedback_parts.append(f"✅ Document has good detail ({word_count} words)")
        elif word_count >= 200:
            criteria_passed += 0.5
            feedback_parts.append(f"✅ Document has adequate detail ({word_count} words)")
        elif word_count >= 150:
            criteria_passed += 0.25
            feedback_parts.append(f"⚠️ Document is somewhat brief ({word_count} words)")
        else:
            feedback_parts.append(f"❌ Document lacks depth ({word_count} words)")

        # ===== Criterion 7: Chronological information (10 points) =====
        # Check for presence of dates/years
        date_patterns = [
            r'\b(202[0-4])\b',  # Years 2020-2024
            r'\b(19\d{2})\b',   # Years for DOB
            r'\b(20\d{2})\b',   # Any 2000s year
            r'\b\d{1,2}/\d{1,2}/\d{2,4}\b',  # Date formats
            r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}\b'
        ]
        
        date_matches = []
        for pattern in date_patterns:
            date_matches.extend(re.findall(pattern, text_lower))
        
        unique_dates = set(date_matches)
        
        if len(unique_dates) >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Strong chronological documentation ({len(unique_dates)} date references)")
        elif len(unique_dates) >= 3:
            criteria_passed += 0.75
            feedback_parts.append(f"✅ Good chronological information ({len(unique_dates)} date references)")
        elif len(unique_dates) >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some chronological information ({len(unique_dates)} date references)")
        else:
            criteria_passed += 0.25
            feedback_parts.append(f"⚠️ Limited chronological information")

        # ===== Criterion 8: Information synthesis quality (10 points) =====
        # Check if user synthesized information correctly (dosage adjustments, timelines, etc.)
        synthesis_score = 0
        
        # Check for propranolol dosage progression (20mg -> 40mg)
        if '20' in full_text and '40' in full_text and 'propranolol' in text_lower:
            if 'increas' in text_lower or 'adjust' in text_lower or 'chang' in text_lower:
                synthesis_score += 0.35
        
        # Check for topiramate dosage info and side effects
        if 'topiramate' in text_lower:
            if any(word in text_lower for word in ['tingl', 'hands', 'feet', 'stupid', 'cognitive']):
                synthesis_score += 0.35
        
        # Check for amitriptyline and drowsiness
        if 'amitriptyline' in text_lower:
            if any(word in text_lower for word in ['drowsy', 'sleepy', 'tired', 'sleep']):
                synthesis_score += 0.3
        
        criteria_passed += synthesis_score
        if synthesis_score >= 0.8:
            feedback_parts.append("✅ Excellent information synthesis from sources")
        elif synthesis_score >= 0.5:
            feedback_parts.append("✅ Good synthesis of source information")
        elif synthesis_score > 0:
            feedback_parts.append("⚠️ Some source information synthesized")

        # ===== Criterion 9: Document structure (5 points) =====
        # Check if sections are clearly delineated
        section_count = 0
        section_keywords = ['current', 'past', 'previous', 'discontinued', 'allerg', 'reaction', 'adverse']
        
        for keyword in section_keywords:
            # Count lines that look like section headers (short lines with keywords)
            for para in doc.paragraphs:
                para_text = para.text.strip()
                if len(para_text) < 50 and keyword in para_text.lower():
                    section_count += 1
                    break
        
        if section_count >= 3:
            criteria_passed += 0.5
            feedback_parts.append("✅ Well-structured document with clear sections")
        elif section_count >= 2:
            criteria_passed += 0.35
            feedback_parts.append("✅ Document has some sectioning")
        else:
            criteria_passed += 0.15
            feedback_parts.append("⚠️ Document structure could be clearer")

        # ===== Calculate final score =====
        score = int((criteria_passed / max_criteria) * 100)
        
        # Passing threshold: 65%
        passed = score >= 65

        # Compile feedback
        feedback = " | ".join(feedback_parts)
        final_feedback = f"Score: {criteria_passed:.2f}/{max_criteria} ({score}%) | {feedback}"

        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything
def verify(copy_from_env_fn):
    """
    Compatibility wrapper for gym-anything framework
    """
    # The framework passes different arguments depending on version
    # Handle both cases
    def verify_wrapper(traj=None, env_info=None, task_info=None):
        if env_info is None:
            # Called with just copy function
            env_info = {'copy_from_env': copy_from_env_fn}
        return verify_medication_history_reconstruction(traj, env_info, task_info)
    
    return verify_wrapper