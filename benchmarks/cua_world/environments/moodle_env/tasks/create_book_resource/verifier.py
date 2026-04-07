#!/usr/bin/env python3
"""Verifier for Create Book Resource task in Moodle."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_book_resource(traj, env_info, task_info):
    """
    Verify that the Book resource was created with correct chapters and content.

    Scoring (100 points):
    - Book exists in BIO101 with matching name (15 pts)
    - Numbering set to Numbers (10 pts)
    - 5 Chapters exist with correct titles and subchapter status (50 pts, 10 each)
    - Book is visible (5 pts)
    - Content spot checks (20 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chapters = metadata.get('chapters', [])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_book_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Book exists (15 points)
        book_found = result.get('book_found', False)
        initial_count = int(result.get('initial_book_count', 0))
        current_count = int(result.get('current_book_count', 0))
        
        if book_found:
            score += 15
            subscores["book_exists"] = True
            feedback_parts.append("Book resource found")
            
            # Anti-gaming: Check if newly created
            if current_count > initial_count:
                feedback_parts.append("(Newly created)")
            else:
                feedback_parts.append("(Warning: Count did not increase)")
        else:
            feedback_parts.append("Book resource NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"book_exists": False}
            }

        # Criterion 2: Numbering (10 points)
        # 1 = Numbers
        numbering = int(result.get('book_numbering', 0))
        if numbering == 1:
            score += 10
            subscores["numbering"] = True
            feedback_parts.append("Numbering: Numbers")
        else:
            subscores["numbering"] = False
            feedback_parts.append(f"Numbering incorrect (val={numbering})")

        # Criterion 3: Visibility (5 points)
        visible = int(result.get('book_visible', 0))
        if visible == 1:
            score += 5
            subscores["visible"] = True
            feedback_parts.append("Book is visible")
        else:
            subscores["visible"] = False
            feedback_parts.append("Book is hidden")

        # Criterion 4 & 5: Chapters & Content (70 points total)
        # We need to match actual chapters to expected chapters
        actual_chapters = result.get('chapters', [])
        
        if not actual_chapters:
            feedback_parts.append("No chapters found in book")
        
        # Verify specific chapters
        chapters_score = 0
        content_score = 0
        max_chapters_score = 50
        max_content_score = 20
        
        # Helper to find chapter
        def find_chapter(title_snippet, actual_list):
            for ch in actual_list:
                if title_snippet.lower() in ch.get('title', '').lower():
                    return ch
            return None

        # Check each expected chapter
        found_count = 0
        correct_structure_count = 0
        content_matches = 0
        
        for exp in expected_chapters:
            title_snip = exp['title']
            actual = find_chapter(title_snip, actual_chapters)
            
            if actual:
                found_count += 1
                
                # Check subchapter status
                is_sub = actual.get('subchapter', 0) == 1
                should_be_sub = exp['subchapter'] == 1
                
                if is_sub == should_be_sub:
                    correct_structure_count += 1
                else:
                    feedback_parts.append(f"Chapter '{title_snip}' wrong level (expected sub={should_be_sub}, got {is_sub})")

                # Check content
                content = actual.get('content', '')
                snippet = exp.get('content_snippet', '')
                if snippet.lower() in content.lower():
                    content_matches += 1
                else:
                    feedback_parts.append(f"Content missing in '{title_snip}'")
            else:
                feedback_parts.append(f"Missing chapter: '{title_snip}'")

        # Calculate score based on findings
        # 5 chapters expected. 10 points per chapter (existence + structure)
        # Simple scoring: 5 points for finding it, 5 points for correct structure
        
        for i in range(len(expected_chapters)):
            # We don't map 1-to-1 perfectly here to keep logic simple, 
            # just count total found and total correct structure
            pass
            
        # Refined scoring:
        # 10 pts per expected chapter if found
        chapters_score = (found_count / len(expected_chapters)) * 30
        
        # 20 pts for correct structure (subchapters)
        if found_count > 0:
            structure_score = (correct_structure_count / found_count) * 20
            chapters_score += structure_score
        
        # 20 pts for content
        if found_count > 0:
            content_score = (content_matches / found_count) * 20
        
        score += int(chapters_score + content_score)
        
        feedback_parts.append(f"Chapters found: {found_count}/{len(expected_chapters)}")
        feedback_parts.append(f"Structure correct: {correct_structure_count}/{found_count if found_count else 1}")
        feedback_parts.append(f"Content verified: {content_matches}/{found_count if found_count else 1}")

        passed = score >= 60

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}