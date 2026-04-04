#!/usr/bin/env python3
"""
Verifier for Board Game Quick Reference task

Checks that the document:
1. Contains required sections (Turn Structure, Common Actions, Phase Reference)
2. Uses heading styles for structure
3. Uses bold formatting for emphasis
4. Uses lists (bullets or numbers) for organization
5. Has reasonable length (not too short, not too long for one page)
6. Contains actual content (not just placeholders)
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


def verify_boardgame_quickref(traj, env_info, task_info):
    """
    Verify that the quick reference document meets requirements.
    
    Scoring breakdown (6 points total):
    - 1.5 points: Required sections present (Turn Structure, Common Actions, Phase)
    - 1.0 point: Uses heading styles
    - 1.0 point: Uses bold formatting
    - 1.0 point: Uses organized lists
    - 0.5 points: Appropriate length
    - 1.0 point: Contains substantive content
    
    Pass threshold: 4.0/6.0 points (67%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/GameReference.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_gameref_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success or doc is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse document: {error}"
            }

        score = 0.0
        max_score = 6.0
        feedback_parts = []

        # Get full document text
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Basic sanity check - document should have meaningful content
        if len(full_text.strip()) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Document is nearly empty ({len(full_text)} characters). Expected a complete quick reference."
            }

        # CRITERION 1: Required sections present (1.5 points)
        required_sections = {
            'turn structure': False,
            'common actions': False,
            'phase': False  # Matches "Phase Reference", "Phases", etc.
        }
        
        # Also check for variations
        section_variations = {
            'turn structure': ['turn structure', 'turn sequence', 'turn order', 'game turn'],
            'common actions': ['common actions', 'available actions', 'action list', 'player actions', 'actions'],
            'phase': ['phase reference', 'phases', 'game phases', 'phase detail']
        }
        
        for section_key in required_sections:
            for variation in section_variations[section_key]:
                if variation in full_text_lower:
                    required_sections[section_key] = True
                    break
        
        sections_found = sum(required_sections.values())
        
        if sections_found == 3:
            score += 1.5
            feedback_parts.append("✅ All required sections present (Turn Structure, Common Actions, Phase)")
        elif sections_found == 2:
            score += 1.0
            feedback_parts.append(f"⚠ Found 2/3 required sections")
        elif sections_found == 1:
            score += 0.5
            feedback_parts.append(f"⚠ Found only 1/3 required sections")
        else:
            feedback_parts.append("❌ Missing required sections")

        # CRITERION 2: Uses heading styles (1.0 point)
        heading_count = 0
        for para in doc.paragraphs:
            if para.style.name.startswith('Heading'):
                heading_count += 1
        
        if heading_count >= 3:
            score += 1.0
            feedback_parts.append(f"✅ Uses heading styles ({heading_count} headings)")
        elif heading_count >= 1:
            score += 0.5
            feedback_parts.append(f"⚠ Limited heading usage ({heading_count} headings, expected 3+)")
        else:
            feedback_parts.append("❌ No heading styles detected")

        # CRITERION 3: Uses bold formatting (1.0 point)
        bold_count = 0
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold and len(run.text.strip()) > 0:
                    bold_count += 1
        
        if bold_count >= 5:
            score += 1.0
            feedback_parts.append(f"✅ Uses bold text for emphasis ({bold_count} instances)")
        elif bold_count >= 2:
            score += 0.5
            feedback_parts.append(f"⚠ Limited bold usage ({bold_count} instances)")
        else:
            feedback_parts.append("❌ No bold formatting detected")

        # CRITERION 4: Uses lists (1.0 point)
        list_item_count = 0
        
        # Method 1: Check for list styles
        for para in doc.paragraphs:
            style_name = para.style.name.lower()
            if 'list' in style_name or 'bullet' in style_name:
                list_item_count += 1
        
        # Method 2: Check for numbering properties (more reliable)
        numbered_list_count = 0
        for para in doc.paragraphs:
            # Check if paragraph has numbering
            if para._element.xpath('.//w:numPr'):
                numbered_list_count += 1
        
        total_list_items = max(list_item_count, numbered_list_count)
        
        if total_list_items >= 5:
            score += 1.0
            feedback_parts.append(f"✅ Uses organized lists ({total_list_items} list items)")
        elif total_list_items >= 3:
            score += 0.7
            feedback_parts.append(f"⚠ Some list usage ({total_list_items} items, expected 5+)")
        elif total_list_items >= 1:
            score += 0.3
            feedback_parts.append(f"⚠ Minimal list usage ({total_list_items} items)")
        else:
            feedback_parts.append("❌ No lists detected (bullet/numbered lists improve scannability)")

        # CRITERION 5: Appropriate length (0.5 points)
        # One-page reference should be roughly 200-1000 words
        word_count = len(full_text.split())
        
        if 200 <= word_count <= 1000:
            score += 0.5
            feedback_parts.append(f"✅ Appropriate length ({word_count} words)")
        elif 150 <= word_count < 200:
            score += 0.3
            feedback_parts.append(f"⚠ Slightly short ({word_count} words, target 200-1000)")
        elif 1000 < word_count <= 1500:
            score += 0.3
            feedback_parts.append(f"⚠ Slightly long ({word_count} words, may exceed one page)")
        elif word_count > 1500:
            score += 0.1
            feedback_parts.append(f"⚠ Too long ({word_count} words, should be one-page reference)")
        else:
            feedback_parts.append(f"❌ Too short ({word_count} words, insufficient content)")

        # CRITERION 6: Contains substantive content (1.0 point)
        # Check that it's not just the instruction text
        instruction_phrases = [
            "create a one-page quick reference",
            "your reference sheet should include",
            "use headings, bold text, and lists"
        ]
        
        is_mostly_instructions = all(phrase in full_text_lower for phrase in instruction_phrases)
        
        # Check for game-specific content
        game_content_indicators = [
            'resource', 'action', 'phase', 'player', 'turn', 
            'card', 'colony', 'metal', 'energy', 'build'
        ]
        
        game_content_count = sum(1 for indicator in game_content_indicators if indicator in full_text_lower)
        
        if not is_mostly_instructions and game_content_count >= 5:
            score += 1.0
            feedback_parts.append(f"✅ Contains substantive game content")
        elif not is_mostly_instructions and game_content_count >= 3:
            score += 0.6
            feedback_parts.append(f"⚠ Contains some game content (could be more detailed)")
        elif is_mostly_instructions:
            feedback_parts.append("❌ Document still contains instruction text (not replaced with actual reference)")
        else:
            feedback_parts.append("❌ Insufficient game-specific content")

        # Check if document was actually edited beyond initial template
        if is_mostly_instructions and word_count < 150:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Document was not edited - still contains only instruction text"
            }

        # Determine pass/fail
        # Pass threshold: 4.0/6.0 (67%)
        passed = score >= 4.0
        
        # Normalize score to 0-100 range
        score_normalized = int((score / max_score) * 100)
        
        # Compile feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | Total: {score:.1f}/{max_score} points"

        return {
            "passed": passed,
            "score": score_normalized,
            "feedback": feedback
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