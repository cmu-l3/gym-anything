#!/usr/bin/env python3
"""
Verifier for rescue_pet_care_planner@1 task

Verifies that user created a well-organized care plan from unstructured notes.
Checks for medication information, dosage calculations, table formatting,
behavioral triggers, emergency contacts, and document organization.
"""

import sys
import os
import re
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify(traj, env_info, task_info):
    """
    Verify that user created a well-organized care plan from unstructured notes.
    
    Checks for:
    1. Medication information present (25 points)
    2. Correct dosage calculations for 45lb dog (20 points)
    3. Medication schedule formatted as table (15 points)
    4. Behavioral trigger documentation (20 points)
    5. Emergency contact information (15 points)
    6. Document organization with sections (15 points)
    7. Exercise/activity information with hip dysplasia considerations (10 points)
    
    Pass threshold: 60/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/Bailey_Care_Plan.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_rescue_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to parse document: {error}"
            }

        # Extract full text (lowercase for easier matching)
        full_text = get_document_text(doc).lower()

        if len(full_text) < 200:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Document appears to be empty or too short. Expected a detailed care plan with at least 200 characters."
            }

        # Check if document still contains only the instructions (user didn't complete task)
        if "start your organized care plan below" in full_text and len(full_text) < 400:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Document appears to contain only the starter instructions. Please organize Bailey's information into a care plan."
            }

        feedback_parts = []
        score = 0.0
        max_score = 100.0

        # ============================================================
        # Check 1: Medication information present (25 points)
        # ============================================================
        medications = ['carprofen', 'fluoxetine', 'glucosamine']
        meds_found = sum(1 for med in medications if med in full_text)

        if meds_found == 3:
            score += 15.0
            feedback_parts.append("✅ All three medications documented (Carprofen, Fluoxetine, Glucosamine)")
        elif meds_found >= 2:
            score += 10.0
            feedback_parts.append(f"⚠️ Only {meds_found}/3 medications found (missing at least one)")
        elif meds_found == 1:
            score += 5.0
            feedback_parts.append(f"❌ Only {meds_found}/3 medications found")
        else:
            feedback_parts.append("❌ No medication information found")

        # Check for administration details (with food, timing)
        admin_keywords = ['with food', 'morning', 'twice daily', 'once daily', 'meals']
        admin_found = sum(1 for keyword in admin_keywords if keyword in full_text)
        if admin_found >= 2:
            score += 10.0
            feedback_parts.append("✅ Medication administration details included")
        elif admin_found >= 1:
            score += 5.0
            feedback_parts.append("⚠️ Some medication administration details included")

        # ============================================================
        # Check 2: Correct dosage calculations (20 points)
        # Expected dosages for 45lb dog:
        # - Carprofen: 2.2 mg/lb × 45 = 99mg total, OR ~49-50mg per dose (twice daily)
        # - Fluoxetine: 1 mg/lb × 45 = 45mg once daily
        # - Glucosamine: 500mg twice daily (fixed dose)
        # ============================================================
        dosage_scores = 0

        # Check for Carprofen dosage (look for 99mg, 50mg, or 49mg)
        if re.search(r'\b(99|50|49)\s*mg', full_text):
            dosage_scores += 1

        # Check for Fluoxetine dosage (45mg)
        if re.search(r'\b45\s*mg', full_text):
            dosage_scores += 1

        # Check for Glucosamine dosage (500mg)
        if re.search(r'\b500\s*mg', full_text):
            dosage_scores += 1

        if dosage_scores == 3:
            score += 20.0
            feedback_parts.append("✅ All medication dosages calculated correctly for 45lb dog")
        elif dosage_scores == 2:
            score += 12.0
            feedback_parts.append(f"⚠️ Most dosage calculations correct ({dosage_scores}/3)")
        elif dosage_scores == 1:
            score += 6.0
            feedback_parts.append(f"⚠️ Some dosage calculations present ({dosage_scores}/3)")
        else:
            feedback_parts.append("❌ Dosage calculations missing or incorrect")

        # ============================================================
        # Check 3: Table present for medication schedule (15 points)
        # ============================================================
        table_count = count_tables(doc)

        if table_count >= 1:
            score += 15.0
            feedback_parts.append(f"✅ Medication schedule formatted as table ({table_count} table(s) found)")
        elif table_count == 0:
            # Check if medications are at least organized (even without table)
            if meds_found >= 2 and dosage_scores >= 2:
                score += 5.0
                feedback_parts.append("⚠️ No table found, but medications are documented (table format recommended)")
            else:
                feedback_parts.append("❌ No table found for medication schedule")

        # ============================================================
        # Check 4: Behavioral trigger documentation (20 points)
        # ============================================================
        # Looking for specific triggers mentioned in the raw data
        triggers = [
            ('vacuum', 'vacuum/cleaning equipment'),
            ('loud', 'loud noises'),
            ('yell', 'yelling/raised voices'),
            ('beard', 'beards'),
            ('hand', 'hand movements'),
            ('noise', 'sudden noises')
        ]

        triggers_found = 0
        for trigger_word, trigger_desc in triggers:
            if trigger_word in full_text:
                triggers_found += 1

        # Check for calming techniques/responses
        calming_keywords = ['soft voice', 'slow', 'calm', 'kong', 'brush', 'toy', 'purple duck']
        calming_found = sum(1 for keyword in calming_keywords if keyword in full_text)

        if triggers_found >= 4:
            score += 15.0
            feedback_parts.append(f"✅ Behavioral triggers well-documented ({triggers_found} triggers identified)")
        elif triggers_found >= 2:
            score += 10.0
            feedback_parts.append(f"⚠️ Some behavioral triggers documented ({triggers_found} found)")
        elif triggers_found >= 1:
            score += 5.0
            feedback_parts.append(f"⚠️ Minimal behavioral trigger documentation ({triggers_found} found)")
        else:
            feedback_parts.append("❌ Behavioral triggers not documented")

        if calming_found >= 2:
            score += 5.0
            feedback_parts.append("✅ Calming techniques included")

        # ============================================================
        # Check 5: Emergency contact information (15 points)
        # ============================================================
        # Remove all formatting from numbers for comparison
        text_no_formatting = full_text.replace('-', '').replace('(', '').replace(')', '').replace(' ', '')

        emergency_elements = [
            ('valley animal hospital', 'Emergency vet name'),
            ('5550199', 'Emergency vet phone (555-0199)'),
            ('poison control', 'Poison control'),
            ('8884264435', 'Poison control phone (888-426-4435)'),
            ('microchip', 'Microchip mention'),
            ('985112001234567', 'Microchip number')
        ]

        emergency_found = 0
        for elem_pattern, elem_desc in emergency_elements:
            if elem_pattern in text_no_formatting or elem_pattern in full_text:
                emergency_found += 1

        if emergency_found >= 4:
            score += 15.0
            feedback_parts.append(f"✅ Emergency contact information complete ({emergency_found}/6 elements)")
        elif emergency_found >= 2:
            score += 10.0
            feedback_parts.append(f"⚠️ Some emergency information present ({emergency_found}/6 elements)")
        elif emergency_found >= 1:
            score += 5.0
            feedback_parts.append(f"⚠️ Minimal emergency information ({emergency_found}/6 elements)")
        else:
            feedback_parts.append("❌ Emergency contact information missing")

        # ============================================================
        # Check 6: Document organization with sections (15 points)
        # ============================================================
        # Check for section organization keywords
        section_keywords = [
            'medication',
            'schedule',
            'behavioral',
            'trigger',
            'emergency',
            'exercise',
            'routine',
            'contact',
            'first week',
            'adjustment'
        ]

        sections_found = sum(1 for keyword in section_keywords if keyword in full_text)

        if sections_found >= 6:
            score += 15.0
            feedback_parts.append("✅ Document well-organized with clear sections")
        elif sections_found >= 4:
            score += 10.0
            feedback_parts.append("⚠️ Document has good organization")
        elif sections_found >= 2:
            score += 5.0
            feedback_parts.append("⚠️ Document has some organization but could be clearer")
        else:
            feedback_parts.append("❌ Document lacks clear organizational structure")

        # ============================================================
        # Check 7: Exercise/activity info considering hip dysplasia (10 points)
        # ============================================================
        exercise_keywords = [
            ('swimming', 'swimming recommendation'),
            ('walk', 'walking routine'),
            ('hip', 'hip dysplasia awareness'),
            ('dysplasia', 'dysplasia condition'),
            ('jump', 'jumping restrictions'),
            ('short walk', 'short walks recommendation')
        ]

        exercise_found = 0
        for keyword, desc in exercise_keywords:
            if keyword in full_text:
                exercise_found += 1

        if exercise_found >= 4:
            score += 10.0
            feedback_parts.append("✅ Exercise information with hip dysplasia considerations included")
        elif exercise_found >= 2:
            score += 5.0
            feedback_parts.append("⚠️ Some exercise information present")
        elif exercise_found >= 1:
            score += 2.0
            feedback_parts.append("⚠️ Minimal exercise information")

        # ============================================================
        # Bonus checks for comprehensiveness
        # ============================================================
        # Check for first week adjustment plan
        if 'first week' in full_text or 'week 1' in full_text or 'adjustment' in full_text:
            if 'decompress' in full_text or 'routine' in full_text or 'boring' in full_text:
                feedback_parts.append("✅ First week adjustment plan included")

        # Check for diet/feeding information
        if 'food' in full_text or 'feed' in full_text or 'meal' in full_text:
            if 'sensitive stomach' in full_text or 'twice daily' in full_text or '2x' in full_text:
                feedback_parts.append("✅ Dietary information included")

        # ============================================================
        # Determine pass/fail
        # ============================================================
        normalized_score = score / max_score
        passed = score >= 60.0  # Pass threshold: 60/100 points

        # Compile final feedback
        final_feedback = " | ".join(feedback_parts)

        logger.info(f"Verification complete: passed={passed}, score={score:.1f}/100")

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
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
