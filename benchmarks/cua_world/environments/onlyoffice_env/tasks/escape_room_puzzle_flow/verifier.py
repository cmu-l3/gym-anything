#!/usr/bin/env python3
"""
Verifier for Escape Room Puzzle Flow task
Checks that messy notes were transformed into professional Master Flow Document
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
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_escape_room_document(traj, env_info, task_info):
    """
    Verify that escape room notes were transformed into professional document.

    Checks:
    1. Required sections present (5 sections: Overview, Flow Map, Puzzle Details, Reset, Hints)
    2. All 8 puzzles documented (bookshelf, UV, crystal, ingredient, secret panel, chest, telescope, philosopher)
    3. Dependency structure present (table or clear list)
    4. Reset checklist has ≥6 items
    5. Hints/Common Issues section has ≥3 entries
    6. Professional formatting (proper headings, adequate length ≥800 words)
    
    Pass threshold: 5 out of 6 criteria (83%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/alchemist_room_notes.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_escape_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        criteria_passed = 0
        feedback_parts = []

        # Get full document text for analysis
        doc_text = get_document_text(doc)
        doc_text_lower = doc_text.lower()

        # Extract all paragraph texts and styles for section detection
        paragraphs_with_styles = []
        for para in doc.paragraphs:
            paragraphs_with_styles.append({
                'text': para.text,
                'style': para.style.name if para.style else '',
                'text_lower': para.text.lower()
            })

        # Criterion 1: Required sections present
        # Look for sections in headings or prominent text
        required_sections = {
            'overview': ['overview', 'room overview', 'introduction'],
            'flow': ['flow', 'puzzle flow', 'dependency', 'dependencies', 'puzzle map', 'flow map'],
            'details': ['puzzle details', 'individual puzzle', 'puzzle descriptions', 'detailed puzzles'],
            'reset': ['reset', 'reset checklist', 'reset procedure', 'resetting'],
            'hints': ['hints', 'common issues', 'common mistakes', 'player mistakes', 'issues']
        }

        sections_found = {key: False for key in required_sections.keys()}
        
        for para_info in paragraphs_with_styles:
            # Check if it's a heading or prominent text
            is_heading = 'heading' in para_info['style'].lower() or para_info['text'].isupper()
            
            if is_heading or len(para_info['text']) < 60:  # Short lines might be section headers
                for section_key, keywords in required_sections.items():
                    if any(keyword in para_info['text_lower'] for keyword in keywords):
                        sections_found[section_key] = True

        sections_count = sum(sections_found.values())
        if sections_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ All {sections_count}/5 required sections present")
        elif sections_count >= 4:
            feedback_parts.append(f"⚠️ Only {sections_count}/5 sections found (missing: {[k for k, v in sections_found.items() if not v]})")
        else:
            feedback_parts.append(f"❌ Only {sections_count}/5 sections found (need 5)")

        # Criterion 2: All 8 puzzles documented
        puzzle_keywords = [
            'bookshelf',
            'uv light',
            'crystal',
            'ingredient',
            'secret panel',
            'chest',
            'telescope',
            'philosopher'
        ]

        puzzles_found = 0
        puzzle_status = []
        for puzzle in puzzle_keywords:
            if puzzle in doc_text_lower:
                puzzles_found += 1
                puzzle_status.append(puzzle)
        
        if puzzles_found >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 8 puzzles documented")
        elif puzzles_found >= 6:
            feedback_parts.append(f"⚠️ Only {puzzles_found}/8 puzzles found (partial credit)")
        else:
            feedback_parts.append(f"❌ Only {puzzles_found}/8 puzzles documented")

        # Criterion 3: Dependency structure present (table or organized list)
        table_count = count_tables(doc)
        has_table = table_count >= 1
        
        # Also check for structured dependency information in text
        has_dependency_keywords = any(keyword in doc_text_lower for keyword in 
                                     ['depends on', 'requires', 'unlocks', 'prerequisite', 'opens'])
        
        if has_table:
            criteria_passed += 1
            feedback_parts.append(f"✅ Dependency structure present (table found)")
        elif has_dependency_keywords:
            criteria_passed += 1
            feedback_parts.append(f"✅ Dependency structure present (dependency relationships documented)")
        else:
            feedback_parts.append(f"❌ No clear dependency structure (no table or dependency info)")

        # Criterion 4: Reset checklist has ≥6 items
        # Find reset section and count list items
        reset_items = 0
        in_reset_section = False
        
        for i, para_info in enumerate(paragraphs_with_styles):
            # Detect reset section start
            if any(keyword in para_info['text_lower'] for keyword in ['reset', 'reset checklist']):
                if 'heading' in para_info['style'].lower() or para_info['text'].isupper() or len(para_info['text']) < 50:
                    in_reset_section = True
                    continue
            
            # Count items in reset section (look for bullets, numbers, dashes, checkboxes)
            if in_reset_section:
                # Stop at next major section
                if 'heading' in para_info['style'].lower() and len(para_info['text']) < 50:
                    break
                
                # Count as item if it starts with bullet-like character or is a short descriptive line
                text_stripped = para_info['text'].strip()
                if text_stripped and (
                    text_stripped[0] in ['-', '•', '○', '●', '□', '☐', '✓', '✔'] or
                    text_stripped[0].isdigit() or
                    (len(text_stripped) < 100 and len(text_stripped) > 10)
                ):
                    reset_items += 1
        
        if reset_items >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Reset checklist complete ({reset_items} items)")
        elif reset_items >= 4:
            feedback_parts.append(f"⚠️ Reset checklist has {reset_items} items (need 6)")
        else:
            feedback_parts.append(f"❌ Reset checklist incomplete ({reset_items} items, need 6)")

        # Criterion 5: Hints/Common Issues section has ≥3 entries
        hint_items = 0
        in_hints_section = False
        
        for i, para_info in enumerate(paragraphs_with_styles):
            # Detect hints section start
            if any(keyword in para_info['text_lower'] for keyword in ['hints', 'common issues', 'common mistakes']):
                if 'heading' in para_info['style'].lower() or para_info['text'].isupper() or len(para_info['text']) < 50:
                    in_hints_section = True
                    continue
            
            # Count items in hints section
            if in_hints_section:
                # Stop at next major section
                if 'heading' in para_info['style'].lower() and len(para_info['text']) < 50:
                    break
                
                text_stripped = para_info['text'].strip()
                if text_stripped and (
                    text_stripped[0] in ['-', '•', '○', '●', '□', '☐'] or
                    text_stripped[0].isdigit() or
                    (len(text_stripped) < 150 and len(text_stripped) > 15)
                ):
                    hint_items += 1
        
        if hint_items >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Hints section complete ({hint_items} entries)")
        elif hint_items >= 2:
            feedback_parts.append(f"⚠️ Hints section has {hint_items} entries (need 3)")
        else:
            feedback_parts.append(f"❌ Hints section incomplete ({hint_items} entries, need 3)")

        # Criterion 6: Professional formatting and adequate length
        word_count = len(doc_text.split())
        has_adequate_length = word_count >= 800
        
        # Check for heading usage
        heading_count = sum(1 for para_info in paragraphs_with_styles 
                          if 'heading' in para_info['style'].lower())
        has_headings = heading_count >= 5
        
        if has_adequate_length and has_headings:
            criteria_passed += 1
            feedback_parts.append(f"✅ Professional formatting ({word_count} words, {heading_count} headings)")
        elif has_adequate_length or has_headings:
            if has_adequate_length:
                feedback_parts.append(f"⚠️ Good length ({word_count} words) but needs more headings ({heading_count} found)")
            else:
                feedback_parts.append(f"⚠️ Good structure ({heading_count} headings) but needs more detail ({word_count} words, need 800+)")
        else:
            feedback_parts.append(f"❌ Document too brief ({word_count} words, need 800+) and lacks structure")

        # Calculate score and determine pass/fail
        score = int((criteria_passed / 6) * 100)
        passed = criteria_passed >= 5  # Need 5 out of 6 criteria (83%)

        feedback = " | ".join(feedback_parts)

        logger.info(f"Verification complete: {criteria_passed}/6 criteria passed, score={score}%")

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