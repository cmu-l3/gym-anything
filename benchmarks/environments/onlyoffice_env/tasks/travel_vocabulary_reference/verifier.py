#!/usr/bin/env python3
"""
Verifier for Travel Vocabulary Reference task

Verifies that the Spanish travel vocabulary reference document was created correctly
with proper structure, content, and formatting.
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


def verify_travel_vocabulary_reference(traj, env_info, task_info):
    """
    Verify Spanish travel vocabulary reference document.
    
    Checks:
    1. Document exists and is valid DOCX
    2. Contains all 4 required category sections
    3. Contains Spanish vocabulary (Spanish characters or words)
    4. Contains English translations
    5. Has bold/italic emphasis on key phrases (at least 4)
    6. Emphasis is distributed across document (not all in one place)
    7. Sufficient vocabulary content (at least 15 non-empty paragraphs)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/spanish_vocab_reference.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_vocab_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        # Extract full text for content analysis
        full_text = get_document_text(doc).lower()
        
        # Criterion 1: Check for all 4 required categories
        categories = {
            'restaurant': ['restaurant', 'dining', 'food', 'comida', 'restaurante', 'meal', 'eat'],
            'hotel': ['hotel', 'accommodation', 'hospedaje', 'alojamiento', 'room', 'stay'],
            'direction': ['direction', 'transport', 'dirección', 'transporte', 'navigation', 'way', 'donde'],
            'emergency': ['emergency', 'help', 'emergencia', 'ayuda', 'urgent', 'doctor', 'police']
        }
        
        categories_found = 0
        category_details = []
        for cat_name, keywords in categories.items():
            # Check if any keyword appears in document
            if any(kw in full_text for kw in keywords):
                categories_found += 1
                category_details.append(cat_name)
        
        if categories_found >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 4 categories present ({', '.join(category_details)})")
        elif categories_found >= 3:
            feedback_parts.append(f"⚠️ Only {categories_found}/4 categories detected ({', '.join(category_details)})")
        else:
            feedback_parts.append(f"❌ Only {categories_found}/4 categories detected")

        # Criterion 2: Check for Spanish content
        # Look for Spanish special characters
        spanish_chars = ['ñ', 'á', 'é', 'í', 'ó', 'ú', 'ü', '¿', '¡']
        has_spanish_chars = any(char in full_text for char in spanish_chars)
        
        # Look for common Spanish words
        spanish_words = ['por favor', 'gracias', 'donde', 'esta', 'necesito', 
                        'ayuda', 'hablo', 'habla', 'mesa', 'cuenta', 'una', 'dos']
        spanish_word_count = sum(1 for word in spanish_words if word in full_text)
        
        has_spanish = has_spanish_chars or spanish_word_count >= 3
        
        if has_spanish:
            criteria_passed += 1
            if has_spanish_chars:
                feedback_parts.append("✅ Spanish vocabulary detected (special characters found)")
            else:
                feedback_parts.append(f"✅ Spanish vocabulary detected ({spanish_word_count} common words)")
        else:
            feedback_parts.append("❌ No Spanish vocabulary detected")

        # Criterion 3: Check for English translations
        # Common English words that would appear in translations
        english_words = ['the', 'please', 'where', 'need', 'help', 'table', 
                        'room', 'two', 'check', 'reservation', 'bathroom']
        english_word_count = sum(1 for word in english_words if word in full_text)
        
        # Also check for dash/hyphen patterns that suggest translation pairs
        translation_pattern_count = full_text.count(' - ') + full_text.count(' – ')
        
        if english_word_count >= 5 or translation_pattern_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ English translations present ({english_word_count} common words, {translation_pattern_count} pairs)")
        else:
            feedback_parts.append(f"❌ Insufficient English translation text ({english_word_count} words)")

        # Criterion 4: Check for bold/italic formatting
        formatted_runs = []
        formatted_text_samples = []
        
        for para in doc.paragraphs:
            for run in para.runs:
                if (run.bold or run.italic) and len(run.text.strip()) > 0:
                    formatted_runs.append(run.text)
                    # Store sample of formatted text (first 30 chars)
                    sample = run.text.strip()[:30]
                    if sample and sample not in formatted_text_samples:
                        formatted_text_samples.append(sample)
        
        # Filter out formatting from the template instructions
        substantive_formatted = [r for r in formatted_runs 
                                if not any(skip in r.lower() for skip in 
                                          ['instructions:', 'spanish travel', 'create sections', 'remember:'])]
        
        if len(substantive_formatted) >= 4:
            criteria_passed += 1
            sample_text = ', '.join([f'"{s}"' for s in formatted_text_samples[:3]])
            feedback_parts.append(f"✅ {len(substantive_formatted)} key phrases emphasized (e.g., {sample_text})")
        elif len(substantive_formatted) >= 2:
            feedback_parts.append(f"⚠️ Only {len(substantive_formatted)} phrases emphasized (need 4+)")
        else:
            feedback_parts.append(f"❌ Only {len(substantive_formatted)} phrases emphasized (need 4+)")

        # Criterion 5: Check formatting distribution across document
        if len(substantive_formatted) >= 3:
            # Check if formatted text appears in different paragraphs
            para_positions_with_formatting = []
            
            for idx, para in enumerate(doc.paragraphs):
                has_formatting = any((run.bold or run.italic) and len(run.text.strip()) > 0 
                                   for run in para.runs)
                if has_formatting:
                    para_positions_with_formatting.append(idx)
            
            # Check if formatting is spread across document (at least 3 different paragraphs)
            # and not all concentrated in one small region
            if len(para_positions_with_formatting) >= 3:
                # Check spread: difference between first and last should be significant
                position_spread = max(para_positions_with_formatting) - min(para_positions_with_formatting)
                
                if position_spread >= 5:  # At least 5 paragraphs apart
                    criteria_passed += 1
                    feedback_parts.append("✅ Emphasis distributed across sections")
                else:
                    feedback_parts.append("⚠️ Emphasis present but concentrated in one area")
            else:
                feedback_parts.append("❌ Emphasis not distributed across document")
        else:
            feedback_parts.append("❌ Insufficient emphasis for distribution check")

        # Criterion 6: Check for sufficient vocabulary content
        # Count non-empty paragraphs that aren't just the template instructions
        non_empty_paragraphs = [p for p in doc.paragraphs if len(p.text.strip()) > 10]
        
        # Filter out template instruction paragraphs
        content_paragraphs = [p for p in non_empty_paragraphs 
                            if not any(skip in p.text.lower() for skip in 
                                      ['instructions:', 'create sections', 'add spanish-english', 
                                       'remember:', '====', '[create sections'])]
        
        # Count actual vocabulary entries (paragraphs that likely contain vocab)
        # Look for patterns like "word - translation" or just substantive content
        vocab_entry_count = len(content_paragraphs)
        
        if vocab_entry_count >= 15:
            criteria_passed += 1
            feedback_parts.append(f"✅ Sufficient content ({vocab_entry_count} vocabulary entries)")
        elif vocab_entry_count >= 10:
            feedback_parts.append(f"⚠️ Moderate content ({vocab_entry_count}/15 vocabulary entries)")
        else:
            feedback_parts.append(f"❌ Insufficient content ({vocab_entry_count}/15 vocabulary entries)")

        # Criterion 7: Check document is reasonable length (not too long)
        total_paragraphs = len(doc.paragraphs)
        
        if total_paragraphs <= 150:  # Reasonable for a reference document
            criteria_passed += 1
            feedback_parts.append(f"✅ Appropriate document length ({total_paragraphs} paragraphs)")
        else:
            feedback_parts.append(f"⚠️ Document may be too long ({total_paragraphs} paragraphs)")

        # Calculate score and determine pass/fail
        score = (criteria_passed / total_criteria) * 100
        passed = score >= 75  # Need at least 6 out of 7 criteria (≈85.7%) or 5 with high partial credit

        # Adjust pass threshold slightly if we're close
        if score >= 71 and categories_found >= 4 and len(substantive_formatted) >= 3:
            # Give benefit of doubt if core requirements met
            passed = True

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
