#!/usr/bin/env python3
"""
Verifier for Chrome DevTools Snippet Creation Task (devtools_snippet_create@1)
Task: Create a JavaScript snippet that changes page title and logs to console

Verification Strategy:
1. Primary: Check if document title was changed (proves execution)
2. Secondary: Search for snippet files in Chrome profile directories
3. Tertiary: Parse IndexedDB or File System for snippet content
4. Quaternary: Check for snippet-related strings in exported data

Scoring based on evidence found across multiple verification methods.
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected snippet details
EXPECTED_SNIPPET_NAME = "PageTitleChanger"
EXPECTED_TITLE_CHANGE = "Modified by DevTools Snippet"
EXPECTED_LOG_MESSAGE = "Snippet executed successfully"
EXPECTED_CODE_FRAGMENTS = [
    "document.title",
    "Modified by DevTools Snippet",
    "console.log",
    "Snippet executed successfully"
]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for devtools_snippet_create@1.
    
    Uses multiple verification methods with scoring:
    - Title change (30 points): Proves snippet was executed
    - Snippet file found (30 points): Proves snippet was created and saved
    - Correct code content (20 points): Snippet contains expected JavaScript
    - Correct name (20 points): Snippet named "PageTitleChanger"
    
    Pass threshold: 60% (need at least 60 points out of 100)
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }
    
    try:
        # Initialize scoring
        total_score = 0
        max_score = 100
        criteria = {
            "title_changed": False,
            "snippet_found": False,
            "correct_code": False,
            "correct_name": False
        }
        feedback_parts = []
        
        # Criterion 1: Check if document title was changed (execution proof)
        logger.info("Checking if document title was changed...")
        title_score, title_changed, title_feedback = verify_title_change(copy_from_env)
        total_score += title_score
        criteria["title_changed"] = title_changed
        feedback_parts.append(title_feedback)
        
        # Criterion 2-4: Check for snippet files and content
        logger.info("Searching for snippet files in Chrome profile...")
        snippet_score, snippet_criteria, snippet_feedback = verify_snippet_files(copy_from_env)
        total_score += snippet_score
        criteria["snippet_found"] = snippet_criteria["found"]
        criteria["correct_code"] = snippet_criteria["correct_code"]
        criteria["correct_name"] = snippet_criteria["correct_name"]
        feedback_parts.extend(snippet_feedback)
        
        # Calculate final score and pass/fail
        passed = total_score >= 60
        
        # Generate summary feedback
        summary_parts = [
            f"{'='*60}",
            f"DevTools Snippet Creation Verification",
            f"{'='*60}",
            f"Criteria Results:",
            f"  1. Title changed to '{EXPECTED_TITLE_CHANGE}': {'✓' if criteria['title_changed'] else '✗'}",
            f"  2. Snippet file found in profile: {'✓' if criteria['snippet_found'] else '✗'}",
            f"  3. Snippet contains correct code: {'✓' if criteria['correct_code'] else '✗'}",
            f"  4. Snippet named '{EXPECTED_SNIPPET_NAME}': {'✓' if criteria['correct_name'] else '✗'}",
            f"",
            f"Detailed Findings:",
        ]
        summary_parts.extend([f"  {line}" for line in feedback_parts])
        summary_parts.extend([
            f"",
            f"{'='*60}",
            f"Final Score: {total_score}/{max_score} points",
            f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}",
            f"{'='*60}"
        ])
        
        feedback = "\n".join(summary_parts)
        
        logger.info(f"Verification complete: passed={passed}, score={total_score}")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback,
            "details": criteria
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_title_change(copy_from_env) -> Tuple[int, bool, str]:
    """
    Verify that the document title was changed by the snippet.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (score: int, changed: bool, feedback: str)
    """
    try:
        # Get initial and final titles
        initial_title = get_file_content(copy_from_env, "/tmp/initial_page_title.txt")
        final_title = get_file_content(copy_from_env, "/tmp/final_page_title.txt")
        
        if not initial_title or not final_title:
            return 0, False, "✗ Could not retrieve page titles for comparison"
        
        logger.info(f"Initial title: '{initial_title}'")
        logger.info(f"Final title: '{final_title}'")
        
        # Check if title changed to expected value
        if EXPECTED_TITLE_CHANGE in final_title:
            return 30, True, f"✓ Title successfully changed to '{EXPECTED_TITLE_CHANGE}' (30 pts)"
        elif final_title != initial_title:
            return 15, False, f"⚠ Title changed but not to expected value: '{final_title}' (15 pts)"
        else:
            return 0, False, f"✗ Title unchanged: '{final_title}' (0 pts)"
            
    except Exception as e:
        logger.error(f"Error verifying title change: {e}")
        return 0, False, f"✗ Error checking title: {str(e)}"


def verify_snippet_files(copy_from_env) -> Tuple[int, Dict[str, bool], List[str]]:
    """
    Search for snippet files in Chrome profile directories.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (score: int, criteria: dict, feedback: list)
    """
    score = 0
    criteria = {
        "found": False,
        "correct_code": False,
        "correct_name": False
    }
    feedback = []
    
    try:
        # Strategy 1: Check search results file
        search_results = get_file_content(copy_from_env, "/tmp/snippet_search_results.txt")
        if search_results and EXPECTED_SNIPPET_NAME in search_results:
            criteria["found"] = True
            criteria["correct_name"] = True
            score += 30  # File found
            score += 20  # Name correct
            feedback.append(f"✓ Snippet '{EXPECTED_SNIPPET_NAME}' found in search (50 pts)")
            
            # Check if code fragments are present
            code_matches = sum(1 for fragment in EXPECTED_CODE_FRAGMENTS if fragment in search_results)
            if code_matches >= 3:
                criteria["correct_code"] = True
                score += 20
                feedback.append(f"✓ Snippet contains correct code ({code_matches}/4 fragments found) (20 pts)")
            elif code_matches > 0:
                score += 10
                feedback.append(f"⚠ Snippet partially correct ({code_matches}/4 code fragments) (10 pts)")
            
            return score, criteria, feedback
        
        # Strategy 2: Try to parse IndexedDB files (complex, best-effort)
        indexeddb_content = search_chrome_directory(copy_from_env, "/tmp/chrome_indexeddb/")
        if indexeddb_content:
            if EXPECTED_SNIPPET_NAME in indexeddb_content:
                criteria["found"] = True
                criteria["correct_name"] = True
                score += 30  # File found
                score += 20  # Name correct
                feedback.append(f"✓ Snippet '{EXPECTED_SNIPPET_NAME}' found in IndexedDB (50 pts)")
                
                # Check code
                code_matches = sum(1 for fragment in EXPECTED_CODE_FRAGMENTS if fragment in indexeddb_content)
                if code_matches >= 3:
                    criteria["correct_code"] = True
                    score += 20
                    feedback.append(f"✓ Code verified in IndexedDB (20 pts)")
                elif code_matches > 0:
                    score += 10
                    feedback.append(f"⚠ Partial code match (10 pts)")
                
                return score, criteria, feedback
        
        # Strategy 3: Check File System directory
        filesystem_content = search_chrome_directory(copy_from_env, "/tmp/chrome_filesystem/")
        if filesystem_content:
            if EXPECTED_SNIPPET_NAME in filesystem_content:
                criteria["found"] = True
                criteria["correct_name"] = True
                score += 30
                score += 20
                feedback.append(f"✓ Snippet found in File System (50 pts)")
                
                code_matches = sum(1 for fragment in EXPECTED_CODE_FRAGMENTS if fragment in filesystem_content)
                if code_matches >= 3:
                    criteria["correct_code"] = True
                    score += 20
                    feedback.append(f"✓ Code verified (20 pts)")
                elif code_matches > 0:
                    score += 10
                    feedback.append(f"⚠ Partial code (10 pts)")
                
                return score, criteria, feedback
        
        # Strategy 4: Check Preferences file for DevTools settings
        prefs_content = get_file_content(copy_from_env, "/tmp/chrome_preferences.json")
        if prefs_content:
            try:
                prefs = json.loads(prefs_content)
                # Check if devtools preferences exist and were modified
                devtools_prefs = prefs.get('devtools', {})
                if devtools_prefs:
                    # Award partial credit for DevTools interaction
                    score += 10
                    feedback.append("⚠ DevTools preferences found (suggests interaction) (10 pts)")
            except json.JSONDecodeError:
                pass
        
        # If we get here, no snippet was found
        if score == 0:
            feedback.append("✗ No snippet file found in Chrome profile (0 pts)")
        
        return score, criteria, feedback
        
    except Exception as e:
        logger.error(f"Error verifying snippet files: {e}")
        feedback.append(f"✗ Error searching for snippet: {str(e)}")
        return score, criteria, feedback


def get_file_content(copy_from_env, container_path: str) -> Optional[str]:
    """
    Copy a file from container and return its content.
    
    Args:
        copy_from_env: Function to copy files
        container_path: Path in container
        
    Returns:
        File content as string, or None if failed
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env(container_path, temp_path)
        
        with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().strip()
        
        os.unlink(temp_path)
        return content
        
    except Exception as e:
        logger.debug(f"Could not read {container_path}: {e}")
        return None


def search_chrome_directory(copy_from_env, container_dir: str) -> Optional[str]:
    """
    Search through a Chrome directory for snippet-related content.
    
    Args:
        copy_from_env: Function to copy files
        container_dir: Directory path in container
        
    Returns:
        Concatenated content of searchable files, or None
    """
    try:
        # Get file manifest
        manifest = get_file_content(copy_from_env, "/tmp/chrome_files_manifest.txt")
        if not manifest:
            return None
        
        # Look for relevant files in manifest
        files = [line.strip() for line in manifest.split('\n') if line.strip()]
        
        # Try to read a sample of files (limit to avoid timeout)
        combined_content = []
        for file_path in files[:20]:  # Limit to first 20 files
            if any(ext in file_path.lower() for ext in ['.log', '.ldb', '.json', '.txt']):
                # Try to get a relative path from /tmp/chrome_*
                relative_path = file_path
                content = get_file_content(copy_from_env, relative_path)
                if content:
                    combined_content.append(content)
        
        return '\n'.join(combined_content) if combined_content else None
        
    except Exception as e:
        logger.debug(f"Error searching directory {container_dir}: {e}")
        return None
