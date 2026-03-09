#!/usr/bin/env python3
"""
Verifier for Podcast Show Notes formatting task

Verifies transformation of rough interview notes into professional show notes
with proper heading hierarchy, formatting, and content organization.
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


def verify_podcast_shownotes(traj, env_info, task_info):
    """
    Verify podcast show notes formatting task.
    
    Checks:
    1. H1 heading for episode title with guest name (15 points)
    2. Multiple H2 section headings (15 points)
    3. Guest bio section with credentials (15 points)
    4. Topics section with bullet formatting (15 points)
    5. Timestamp formatting with bold [MM:SS] (20 points)
    6. Quotes section present (10 points)
    7. Resources section with content (10 points)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # Check both possible paths
    container_paths = [
        "/home/ga/Documents/TextDocuments/episode_12_shownotes.docx",
        "/home/ga/Documents/TextDocuments/history_podcast_rough_notes.docx"
    ]
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_shownotes_')
    doc = None
    success = False
    
    try:
        # Try both possible file locations
        for container_path in container_paths:
            success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
            if success:
                logger.info(f"Successfully loaded document from: {container_path}")
                break
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load document: {error}"
            }
        
        feedback_parts = []
        score = 0.0
        max_score = 100.0
        
        # Extract full text for content analysis
        full_text = get_document_text(doc).lower()
        
        # Check 1: H1 Heading for Episode Title (15 points)
        h1_found = False
        h1_content = ""
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'Heading 1' in style_name or 'Title' in style_name:
                h1_content = para.text.lower()
                # Check if it contains episode reference and guest name
                if ('episode' in h1_content or 'ep' in h1_content) and \
                   ('hammond' in h1_content or 'patricia' in h1_content):
                    h1_found = True
                    score += 15
                    feedback_parts.append("✅ Episode title formatted as H1 with guest name")
                    break
        
        if not h1_found:
            if h1_content:
                feedback_parts.append(f"❌ H1 present but missing episode/guest info: '{h1_content[:50]}'")
            else:
                feedback_parts.append("❌ No H1 heading found for episode title")
        
        # Check 2: Multiple H2 Section Headings (15 points)
        h2_headings = []
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'Heading 2' in style_name:
                h2_headings.append(para.text.lower())
        
        h2_count = len(h2_headings)
        if h2_count >= 5:
            score += 15
            feedback_parts.append(f"✅ Excellent section structure ({h2_count} H2 headings)")
        elif h2_count >= 4:
            score += 12
            feedback_parts.append(f"✅ Good section structure ({h2_count} H2 headings)")
        elif h2_count >= 2:
            score += 8
            feedback_parts.append(f"⚠️ Basic structure ({h2_count} H2 headings, expected 5+)")
        else:
            feedback_parts.append(f"❌ Insufficient heading structure ({h2_count} H2 headings)")
        
        # Check 3: Guest Bio Section (15 points)
        bio_section_heading = any(
            'guest' in h or 'about' in h or 'bio' in h 
            for h in h2_headings
        )
        bio_content_keywords = ['historian', 'historical society', 'director', 'books']
        bio_keywords_found = sum(1 for kw in bio_content_keywords if kw in full_text)
        
        if bio_section_heading and bio_keywords_found >= 3:
            score += 15
            feedback_parts.append("✅ Guest bio section with comprehensive credentials")
        elif bio_section_heading and bio_keywords_found >= 2:
            score += 10
            feedback_parts.append("✅ Guest bio section present with partial credentials")
        elif bio_keywords_found >= 2:
            score += 5
            feedback_parts.append("⚠️ Bio content present but section heading unclear")
        else:
            feedback_parts.append("❌ Missing or incomplete guest bio section")
        
        # Check 4: Topics Section with Bullets (15 points)
        topics_section_heading = any(
            'topic' in h and ('discuss' in h or 'cover' in h)
            for h in h2_headings
        )
        
        # Check for bullet list paragraphs
        bullet_count = 0
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'List' in style_name or para.text.strip().startswith('•') or para.text.strip().startswith('-'):
                bullet_count += 1
        
        # Check for expected topic keywords
        topic_keywords = ['urban renewal', 'displacement', 'highway', 'preservation', 'planning']
        topics_covered = sum(1 for kw in topic_keywords if kw in full_text)
        
        if topics_section_heading and bullet_count >= 3 and topics_covered >= 3:
            score += 15
            feedback_parts.append(f"✅ Topics section with bullet list ({bullet_count} bullets)")
        elif topics_section_heading and topics_covered >= 3:
            score += 10
            feedback_parts.append("✅ Topics section present (could improve bullet formatting)")
        elif topics_covered >= 3:
            score += 5
            feedback_parts.append("⚠️ Topic content present but section/formatting needs work")
        else:
            feedback_parts.append("❌ Missing or incomplete topics section")
        
        # Check 5: Timestamp Formatting (20 points)
        # Look for [MM:SS] pattern
        timestamp_pattern = re.compile(r'\[(\d{1,2}):(\d{2})\]')
        timestamps_found = timestamp_pattern.findall(full_text)
        
        # Check if timestamps are bold
        timestamps_bold_count = 0
        for para in doc.paragraphs:
            for run in para.runs:
                if timestamp_pattern.search(run.text):
                    if run.bold:
                        timestamps_bold_count += 1
        
        if len(timestamps_found) >= 4 and timestamps_bold_count >= 3:
            score += 20
            feedback_parts.append(f"✅ {len(timestamps_found)} timestamps properly formatted and bold")
        elif len(timestamps_found) >= 3 and timestamps_bold_count >= 2:
            score += 15
            feedback_parts.append(f"✅ {len(timestamps_found)} timestamps with {timestamps_bold_count} bold")
        elif len(timestamps_found) >= 3:
            score += 12
            feedback_parts.append(f"✅ {len(timestamps_found)} timestamps found (improve bold formatting)")
        elif len(timestamps_found) >= 1:
            score += 8
            feedback_parts.append(f"⚠️ Only {len(timestamps_found)} timestamp(s) found")
        else:
            feedback_parts.append("❌ No properly formatted timestamps [MM:SS]")
        
        # Check 6: Quotes Section (10 points)
        quotes_section_heading = any(
            'quote' in h 
            for h in h2_headings
        )
        
        # Check for quotation marks
        quotation_marks = ['"', '"', '"', '\"']
        has_quotes = any(qm in full_text for qm in quotation_marks)
        
        # Check for expected quote content
        quote_keywords = ['highway', 'divide', 'shattered', 'community', 'progress', 'families']
        quote_content = sum(1 for kw in quote_keywords if kw in full_text)
        
        if quotes_section_heading and has_quotes and quote_content >= 2:
            score += 10
            feedback_parts.append("✅ Quotes section with formatted quotations")
        elif quotes_section_heading and has_quotes:
            score += 7
            feedback_parts.append("✅ Quotes section present")
        elif has_quotes:
            score += 3
            feedback_parts.append("⚠️ Quotations found but section heading unclear")
        else:
            feedback_parts.append("❌ Missing quotes section")
        
        # Check 7: Resources Section (10 points)
        resources_section_heading = any(
            'resource' in h or 'reference' in h or 'mentioned' in h
            for h in h2_headings
        )
        
        resource_items = ['archives', 'jacobs', 'minutes', 'historical society', 'city planning']
        resources_found = sum(1 for item in resource_items if item in full_text)
        
        if resources_section_heading and resources_found >= 2:
            score += 10
            feedback_parts.append("✅ Resources section with multiple items")
        elif resources_section_heading:
            score += 5
            feedback_parts.append("⚠️ Resources section present but needs more items")
        elif resources_found >= 2:
            score += 3
            feedback_parts.append("⚠️ Resource content present but section heading unclear")
        else:
            feedback_parts.append("❌ Missing resources section")
        
        # Normalize score
        final_score = score / max_score
        passed = final_score >= 0.70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
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
