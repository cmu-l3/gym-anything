#!/usr/bin/env python3
"""
Verifier for Handmade Soap Care Sheet task

Verifies that a professional product care instruction sheet was created with:
- Proper document structure (sections with headings)
- Bold safety warnings
- Use of bullet lists
- Organized troubleshooting content
- Professional appearance
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_handmade_soap_care_sheet(traj, env_info, task_info):
    """
    Verify that the soap care instruction sheet is properly formatted and organized.
    
    Scoring breakdown (100 points total):
    - File existence: 10 points
    - Document structure: 25 points
    - Safety warnings formatting: 20 points
    - Use of lists: 20 points
    - Troubleshooting content: 15 points
    - Professional appearance: 10 points
    
    Passing score: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available"
        }
    
    container_path = "/home/ga/Documents/TextDocuments/Soap_Care_Instructions.docx"
    temp_dir = None
    
    try:
        points = 0
        max_points = 100
        feedback_parts = []
        
        # 1. File Existence and Format (10 points)
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document not found or cannot be parsed: {error}"
            }
        
        points += 10
        feedback_parts.append("✅ Document exists and is valid DOCX (10/10)")
        
        # Get full text and analyze structure
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Remove the hint text if present
        full_text_lower_clean = full_text_lower.replace("instructions: organize the notes from soap_care_notes.txt", "")
        
        # Check if document has substantial content (not just the template)
        if len(full_text_lower_clean) < 200:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": "❌ Document appears to be mostly empty or unchanged from template"
            }
        
        # 2. Document Structure - Title and Sections (25 points)
        structure_points = 0
        
        # Check for title in first few paragraphs
        title_found = False
        for i, para in enumerate(doc.paragraphs[:3]):
            para_text = para.text.lower()
            if any(phrase in para_text for phrase in ['soap care', 'care instructions', 'product care', 'natural soap']):
                title_found = True
                break
        
        if title_found:
            structure_points += 5
            feedback_parts.append("✅ Title present")
        else:
            feedback_parts.append("⚠️ Title not clearly identified")
        
        # Check for required sections
        required_sections = {
            'storage': ['storage', 'handling', 'how to store', 'storing'],
            'safety': ['safety', 'warnings', 'caution', 'important'],
            'faq': ['faq', 'frequently asked', 'common questions', 'questions', 'q&a', 'q & a'],
            'troubleshooting': ['troubleshooting', 'common issues', 'problems', 'problem solving', 'issues']
        }
        
        sections_found = []
        for section_name, patterns in required_sections.items():
            if any(pattern in full_text_lower for pattern in patterns):
                sections_found.append(section_name)
        
        sections_count = len(sections_found)
        structure_points += min(sections_count * 4, 12)  # Up to 12 points for 3+ sections
        
        # Check if sections use proper heading styles
        heading_count = 0
        heading_texts = []
        for para in doc.paragraphs:
            if para.style.name.startswith('Heading') or para.style.name == 'Title':
                heading_count += 1
                heading_texts.append(para.text.lower())
        
        if heading_count >= 4:
            structure_points += 8
        elif heading_count >= 3:
            structure_points += 6
        elif heading_count >= 2:
            structure_points += 3
        
        points += structure_points
        feedback_parts.append(
            f"{'✅' if structure_points >= 20 else '⚠️'} Document structure: {structure_points}/25 "
            f"(sections: {sections_count}/4, headings: {heading_count})"
        )
        
        # 3. Safety Warnings Formatting (20 points)
        safety_points = 0
        
        # Check for bold safety warnings - specifically "avoid eyes" and "discontinue if irritation"
        avoid_eyes_variations = ['avoid eye', 'avoid contact with eye', 'keep away from eye', 'do not get in eye']
        discontinue_variations = ['discontinue', 'stop use', 'stop using', 'cease use']
        irritation_keywords = ['irritation', 'rash', 'reaction', 'sensitivity']
        
        # Check if avoid eyes warning exists and is bold
        avoid_eyes_found = False
        avoid_eyes_bold = False
        for para in doc.paragraphs:
            para_lower = para.text.lower()
            if any(phrase in para_lower for phrase in avoid_eyes_variations):
                avoid_eyes_found = True
                # Check if any run containing this text is bold
                for run in para.runs:
                    run_lower = run.text.lower()
                    if any(phrase in run_lower for phrase in avoid_eyes_variations) or 'eye' in run_lower:
                        if run.bold:
                            avoid_eyes_bold = True
                            break
                if avoid_eyes_bold:
                    break
        
        if avoid_eyes_bold:
            safety_points += 10
            feedback_parts.append("✅ 'Avoid eyes' warning is bold")
        elif avoid_eyes_found:
            safety_points += 5
            feedback_parts.append("⚠️ 'Avoid eyes' warning found but not bold")
        else:
            feedback_parts.append("❌ 'Avoid eyes' warning not found")
        
        # Check if discontinue/irritation warning exists and is bold
        discontinue_found = False
        discontinue_bold = False
        for para in doc.paragraphs:
            para_lower = para.text.lower()
            has_discontinue = any(phrase in para_lower for phrase in discontinue_variations)
            has_irritation = any(keyword in para_lower for keyword in irritation_keywords)
            
            if has_discontinue or has_irritation:
                discontinue_found = True
                # Check if relevant text is bold
                for run in para.runs:
                    run_lower = run.text.lower()
                    if any(phrase in run_lower for phrase in discontinue_variations + irritation_keywords):
                        if run.bold:
                            discontinue_bold = True
                            break
                if discontinue_bold:
                    break
        
        if discontinue_bold:
            safety_points += 10
            feedback_parts.append("✅ 'Discontinue if irritation' warning is bold")
        elif discontinue_found:
            safety_points += 5
            feedback_parts.append("⚠️ Discontinue/irritation warning found but not bold")
        else:
            feedback_parts.append("❌ Discontinue/irritation warning not found")
        
        points += safety_points
        
        # 4. Use of Lists for Scannability (20 points)
        list_points = 0
        
        # Count bullet/numbered list items
        list_item_count = 0
        for para in doc.paragraphs:
            style_name = para.style.name.lower()
            if 'list' in style_name or 'bullet' in style_name:
                list_item_count += 1
        
        # Award points based on list usage
        if list_item_count >= 12:
            list_points = 20
        elif list_item_count >= 9:
            list_points = 17
        elif list_item_count >= 6:
            list_points = 13
        elif list_item_count >= 4:
            list_points = 8
        elif list_item_count >= 2:
            list_points = 4
        
        points += list_points
        feedback_parts.append(
            f"{'✅' if list_points >= 13 else '⚠️'} Uses bullet lists: {list_points}/20 "
            f"({list_item_count} list items)"
        )
        
        # 5. Troubleshooting Structure (15 points)
        troubleshooting_points = 0
        
        # Check if troubleshooting section exists
        has_troubleshooting = any(
            pattern in full_text_lower 
            for pattern in ['troubleshooting', 'common issues', 'common problems', 'problem:', 'issue:']
        )
        
        if has_troubleshooting:
            troubleshooting_points += 5
            
            # Check for specific issues mentioned from the notes
            issues_to_check = [
                ('white film', ['white film', 'soda ash', 'white residue']),
                ('soft/mushy', ['soft', 'mushy', 'dissolv']),
                ('cracked', ['crack', 'broke', 'split']),
                ('scent fading', ['scent fad', 'smell fad', 'fragrance fad', 'aroma fad']),
                ('slimy', ['slimy', 'slippery', 'glycerin'])
            ]
            
            issues_found = 0
            for issue_name, patterns in issues_to_check:
                if any(pattern in full_text_lower for pattern in patterns):
                    issues_found += 1
            
            # Award points for including multiple troubleshooting items
            troubleshooting_points += min(issues_found * 2, 10)
            
            feedback_parts.append(
                f"✅ Troubleshooting section with {issues_found} common issues addressed"
            )
        else:
            feedback_parts.append("❌ Troubleshooting section not found")
        
        points += troubleshooting_points
        
        # 6. Professional Appearance (10 points)
        professional_points = 0
        
        # Check for excessive ALL CAPS (allow title but nothing else)
        all_caps_sentences = []
        for para in doc.paragraphs[1:]:  # Skip title
            text = para.text.strip()
            if text and len(text) > 20 and text.isupper():
                all_caps_sentences.append(text[:50])
        
        if len(all_caps_sentences) == 0:
            professional_points += 3
        elif len(all_caps_sentences) <= 1:
            professional_points += 2
        
        # Check for formatting variety
        has_bold = False
        has_italic = False
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold:
                    has_bold = True
                if run.italic:
                    has_italic = True
                if has_bold and has_italic:
                    break
        
        formatting_elements = sum([
            has_bold,
            heading_count > 0,
            list_item_count > 0
        ])
        
        professional_points += min(formatting_elements * 2, 4)
        
        # Check if content is actually reorganized (not just pasted notes)
        # Look for the original messy format indicators
        messy_indicators = [
            'customer asked why',
            'told them',
            'explained our',
            'reminded them'
        ]
        messy_count = sum(1 for indicator in messy_indicators if indicator in full_text_lower)
        
        if messy_count == 0 and sections_count >= 3:
            professional_points += 3
        elif messy_count <= 1 and sections_count >= 2:
            professional_points += 2
        
        points += professional_points
        feedback_parts.append(
            f"{'✅' if professional_points >= 7 else '⚠️'} Professional appearance: {professional_points}/10"
        )
        
        # Final scoring
        score = points / max_points
        passed = score >= 0.70
        
        # Create summary
        summary = f"{'✅ PASSED' if passed else '❌ FAILED'} - Score: {points}/{max_points} ({score*100:.0f}%)"
        feedback = summary + " | " + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)