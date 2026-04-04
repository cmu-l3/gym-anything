#!/usr/bin/env python3
"""
Verifier for Memorial Service Program task

This verifies that the agent successfully synthesized information from 
fragmented notes and created a properly formatted memorial service program.
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


def verify_memorial_service_program(traj, env_info, task_info):
    """
    Verify the memorial service program document.
    
    Checks for:
    1. Correct deceased information (name, dates) - 2 points
    2. Service details (date, time, location) - 1.5 points
    3. Order of service with all participants - 2 points
    4. Music selections listed - 1 point
    5. Poem included with proper content - 1 point
    6. Reception details - 1 point
    7. Remote attendance info - 0.5 points
    8. Memorial donation information - 0.5 points
    9. Document structure (Order of Service heading) - 0.5 points
    
    Total: 10 points, scaled to 0-100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/MemorialService/final_service_program.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_memorial_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Could not open document: {error}"
            }
        
        # Extract all text
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Check if document has reasonable content
        if len(full_text.strip()) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Document appears to be empty or too short"
            }
        
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # Criterion 1: Deceased information (2 points)
        deceased_checks = 0
        deceased_feedback = []
        
        # Check for full name (various formats accepted)
        if "margaret ellen rodriguez" in full_text_lower or \
           "margaret e. rodriguez" in full_text_lower or \
           ("margaret" in full_text_lower and "rodriguez" in full_text_lower):
            deceased_checks += 1
            deceased_feedback.append("name")
        
        # Check for birth year 1952
        if "1952" in full_text:
            deceased_checks += 1
            deceased_feedback.append("birth year")
        
        # Check for death year 2025
        if "2025" in full_text:
            deceased_checks += 1
            deceased_feedback.append("death year")
        
        # Check for service title (Celebration of Life or Memorial Service)
        if "celebration of life" in full_text_lower or "memorial service" in full_text_lower:
            deceased_checks += 1
            deceased_feedback.append("service title")
        
        if deceased_checks >= 3:
            score += 2.0
            feedback_parts.append(f"✅ Deceased information present ({', '.join(deceased_feedback)})")
        elif deceased_checks >= 2:
            score += 1.0
            feedback_parts.append(f"⚠️ Partial deceased information ({', '.join(deceased_feedback)})")
        else:
            feedback_parts.append(f"❌ Missing deceased information (found: {', '.join(deceased_feedback) if deceased_feedback else 'none'})")
        
        # Criterion 2: Service details (1.5 points)
        service_checks = 0
        service_feedback = []
        
        # Check for date (various formats)
        date_patterns = ["january 25", "jan 25", "jan. 25", "1/25", "01/25", "25th"]
        if any(pattern in full_text_lower for pattern in date_patterns):
            service_checks += 1
            service_feedback.append("date")
        
        # Check for time
        time_patterns = ["2:00", "2 pm", "2pm", "2 p.m.", "two pm"]
        if any(pattern in full_text_lower for pattern in time_patterns):
            service_checks += 1
            service_feedback.append("time")
        
        # Check for location
        if "riverside community chapel" in full_text_lower or \
           ("riverside" in full_text_lower and "chapel" in full_text_lower) or \
           "847 oak" in full_text_lower:
            service_checks += 1
            service_feedback.append("location")
        
        if service_checks == 3:
            score += 1.5
            feedback_parts.append("✅ Service date/time/location complete")
        elif service_checks == 2:
            score += 1.0
            feedback_parts.append(f"⚠️ Service details partially present ({', '.join(service_feedback)})")
        elif service_checks == 1:
            score += 0.5
            feedback_parts.append(f"⚠️ Minimal service details ({', '.join(service_feedback)})")
        else:
            feedback_parts.append("❌ Service details missing")
        
        # Criterion 3: Order of service participants (2 points)
        participant_checks = 0
        participant_feedback = []
        
        required_participants = [
            ("pastor michael chen", "pastor chen", "Pastor Chen"),
            ("david rodriguez", "david", "eulogy"),
            ("jennifer martinez", "jennifer", "readings"),
            ("emma wilson", "emma", "granddaughter"),
            ("sarah rodriguez", "sarah", "niece")
        ]
        
        for participant_variants in required_participants:
            if any(variant.lower() in full_text_lower for variant in participant_variants):
                participant_checks += 1
                participant_feedback.append(participant_variants[2] if len(participant_variants) > 2 else participant_variants[0])
        
        if participant_checks >= 4:
            score += 2.0
            feedback_parts.append(f"✅ Participants listed ({participant_checks}/5)")
        elif participant_checks >= 3:
            score += 1.5
            feedback_parts.append(f"⚠️ Most participants listed ({participant_checks}/5)")
        elif participant_checks >= 2:
            score += 1.0
            feedback_parts.append(f"⚠️ Some participants listed ({participant_checks}/5)")
        else:
            feedback_parts.append(f"❌ Missing most participants ({participant_checks}/5)")
        
        # Criterion 4: Music selections (1 point)
        music_checks = 0
        music_feedback = []
        
        if "amazing grace" in full_text_lower:
            music_checks += 1
            music_feedback.append("Amazing Grace")
        
        if "wonderful world" in full_text_lower or "what a wonderful" in full_text_lower:
            music_checks += 1
            music_feedback.append("What a Wonderful World")
        
        # Check for choir mention
        if "choir" in full_text_lower or "gospel" in full_text_lower:
            music_feedback.append("choir")
        
        if music_checks == 2:
            score += 1.0
            feedback_parts.append(f"✅ Both musical selections listed ({', '.join(music_feedback)})")
        elif music_checks == 1:
            score += 0.5
            feedback_parts.append(f"⚠️ One musical selection listed ({', '.join(music_feedback)})")
        else:
            feedback_parts.append("❌ Music selections missing")
        
        # Criterion 5: Poem included (1 point)
        poem_check = False
        poem_feedback = []
        
        # Check for poem title
        if "do not stand at my grave" in full_text_lower and "weep" in full_text_lower:
            poem_check = True
            poem_feedback.append("title")
        
        # Check for poem content (multiple key phrases)
        poem_phrases = [
            "thousand winds",
            "diamond glints",
            "sunlight on ripened grain",
            "gentle autumn rain",
            "i am not there",
            "i did not die"
        ]
        
        poem_phrase_count = sum(1 for phrase in poem_phrases if phrase in full_text_lower)
        
        if poem_phrase_count >= 3:
            poem_check = True
            poem_feedback.append(f"{poem_phrase_count} key phrases")
        
        if poem_check:
            score += 1.0
            feedback_parts.append(f"✅ Poem included ({', '.join(poem_feedback)})")
        elif poem_phrase_count >= 1:
            score += 0.5
            feedback_parts.append(f"⚠️ Poem partially included ({poem_phrase_count} phrases)")
        else:
            feedback_parts.append("❌ Poem missing or incomplete")
        
        # Criterion 6: Reception details (1 point)
        reception_checks = 0
        reception_feedback = []
        
        if "martinez family restaurant" in full_text_lower or \
           ("martinez" in full_text_lower and "restaurant" in full_text_lower) or \
           "1240 river road" in full_text_lower:
            reception_checks += 1
            reception_feedback.append("location")
        
        if "vegetarian" in full_text_lower or "veggie" in full_text_lower:
            reception_checks += 1
            reception_feedback.append("dietary info")
        
        if "refreshment" in full_text_lower or "reception" in full_text_lower:
            reception_feedback.append("reception mentioned")
        
        if reception_checks >= 1:
            score += 1.0
            feedback_parts.append(f"✅ Reception details included ({', '.join(reception_feedback)})")
        else:
            feedback_parts.append("❌ Reception information missing")
        
        # Criterion 7: Remote attendance (0.5 points)
        if "zoom" in full_text_lower or \
           "remote" in full_text_lower or \
           "unable to attend" in full_text_lower or \
           "those who cannot" in full_text_lower:
            score += 0.5
            feedback_parts.append("✅ Remote attendance info included")
        else:
            feedback_parts.append("❌ Remote attendance info missing")
        
        # Criterion 8: Memorial donations (0.5 points)
        if ("animal shelter" in full_text_lower or "riverside animal" in full_text_lower) or \
           ("donation" in full_text_lower and ("lieu" in full_text_lower or "instead" in full_text_lower)):
            score += 0.5
            feedback_parts.append("✅ Donation information included")
        else:
            feedback_parts.append("❌ Donation information missing")
        
        # Criterion 9: Document structure (0.5 points)
        if "order of service" in full_text_lower:
            score += 0.5
            feedback_parts.append("✅ Proper document structure (Order of Service)")
        else:
            feedback_parts.append("⚠️ Missing 'Order of Service' heading")
        
        # Additional check: Document length (reasonable)
        para_count = count_paragraphs(doc)
        if para_count >= 10:
            feedback_parts.append(f"Document structure: {para_count} paragraphs")
        
        # Normalize score to 0-100
        final_score = (score / max_score) * 100
        passed = final_score >= 70  # 70% threshold
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(final_score),
            "feedback": f"Score: {final_score:.0f}/100 - {feedback}"
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