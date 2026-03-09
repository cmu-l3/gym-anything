#!/usr/bin/env python3
"""
Verifier for Chrome Custom Spell Check Dictionary Task (custom_spell_check_dictionary@1)
Task: Add custom technical terms (TensorFlow, Kubernetes, PostgreSQL, Dockerfile) to Chrome's spell check dictionary

Verification Strategy:
- Copy Custom Dictionary.txt from Chrome profile directory
- Parse the file (plain text, one word per line, UTF-8 encoded)
- Check for presence of all 4 required words with exact case-sensitive matching
- Score based on number of words found (25% per word)
- Pass threshold: 75% (requires at least 3 out of 4 words)
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        temp_dir = os.path.join(os.getcwd(), "temp_chrome_verification")
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for custom_spell_check_dictionary@1.
    
    Verifies that Chrome's custom dictionary contains the required technical terms.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information (contains required_words)
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str), and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    # Get required words from task_info, with defaults
    required_words = task_info.get('required_words', 
                                   ["TensorFlow", "Kubernetes", "PostgreSQL", "Dockerfile"])
    
    logger.info(f"Verifying custom dictionary contains: {required_words}")

    try:
        # Get custom dictionary file contents
        success, dict_path, dict_content, error_msg = get_custom_dictionary(copy_from_env)
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access custom dictionary: {error_msg}",
                "details": {
                    "required_words": required_words,
                    "found_words": [],
                    "missing_words": required_words
                }
            }
        
        # Parse and verify dictionary contents
        result = verify_custom_words(dict_content, required_words)
        
        # Clean up temporary files
        if dict_path and os.path.exists(dict_path):
            try:
                os.unlink(dict_path)
            except:
                pass
        
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "details": {
                "error": str(e)
            }
        }


def get_custom_dictionary(copy_from_env) -> Tuple[bool, str, List[str], str]:
    """
    Retrieve and parse Chrome's custom dictionary file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (success, local_path, word_list, error_message)
    """
    try:
        # Try multiple possible locations for the dictionary file
        possible_paths = [
            "/tmp/custom_dictionary_export.txt",
            "/home/ga/.config/google-chrome-cdp/Default/Custom Dictionary.txt",
            "/home/ga/.config/google-chrome/Default/Custom Dictionary.txt"
        ]
        
        temp_file = None
        dict_content = []
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Attempting to copy custom dictionary from: {container_path}")
                
                # Create temporary file
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
                temp_path = temp_file.name
                temp_file.close()
                
                # Try to copy from container
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path):
                    file_size = os.path.getsize(temp_path)
                    
                    # Read the file
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        lines = f.readlines()
                    
                    # Parse words (strip whitespace from each line, skip empty lines)
                    dict_content = [line.strip() for line in lines if line.strip()]
                    
                    source_path = container_path
                    logger.info(f"✓ Successfully copied custom dictionary from: {container_path}")
                    logger.info(f"✓ Dictionary contains {len(dict_content)} word(s)")
                    logger.info(f"✓ Words in dictionary: {dict_content[:20]}")  # Log first 20 words
                    
                    return True, temp_path, dict_content, ""
                else:
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)
                        
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if temp_file and os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except:
                        pass
                continue
        
        # If we get here, none of the paths worked
        return False, "", [], "Custom Dictionary.txt not found in any expected location"
        
    except Exception as e:
        logger.error(f"Error getting custom dictionary: {e}")
        return False, "", [], f"Error accessing custom dictionary: {str(e)}"


def verify_custom_words(dict_content: List[str], required_words: List[str]) -> Dict[str, Any]:
    """
    Verify that required words are present in the custom dictionary.
    
    Args:
        dict_content: List of words from custom dictionary
        required_words: List of words that should be present
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    # Convert to sets for comparison (case-sensitive!)
    dict_words_set = set(dict_content)
    required_set = set(required_words)
    
    # Find which words are present and which are missing
    found_words = required_set.intersection(dict_words_set)
    missing_words = required_set - found_words
    
    # Check for case-insensitive matches (to provide helpful feedback)
    case_mismatches = []
    dict_words_lower = {word.lower(): word for word in dict_content}
    for missing in missing_words:
        if missing.lower() in dict_words_lower:
            actual_word = dict_words_lower[missing.lower()]
            case_mismatches.append((missing, actual_word))
    
    # Calculate score (25 points per word = 100 total)
    num_found = len(found_words)
    num_required = len(required_words)
    score = int((num_found / num_required) * 100)
    
    # Pass threshold: 75% (requires 3 out of 4 words)
    passed = score >= 75
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Custom dictionary verification: {num_found}/{num_required} required words found")
    
    if found_words:
        feedback_parts.append(f"✓ Found correctly: {', '.join(sorted(found_words))}")
    
    if missing_words:
        feedback_parts.append(f"✗ Missing: {', '.join(sorted(missing_words))}")
    
    if case_mismatches:
        feedback_parts.append("⚠ Case sensitivity issues detected:")
        for expected, actual in case_mismatches:
            feedback_parts.append(f"  - Expected '{expected}' but found '{actual}' (wrong capitalization)")
    
    # Add context about dictionary size
    if dict_content:
        feedback_parts.append(f"ℹ Total words in dictionary: {len(dict_content)}")
    else:
        feedback_parts.append("⚠ Custom dictionary is empty")
    
    # Final verdict
    if passed:
        if num_found == num_required:
            feedback_parts.append("🎉 Excellent! All required words added correctly with proper capitalization.")
        else:
            feedback_parts.append(f"✅ Task passed with {num_found}/{num_required} words (minimum 3 required).")
    else:
        if num_found == 0:
            feedback_parts.append("❌ No required words found. Please add technical terms to custom dictionary.")
        else:
            feedback_parts.append(f"❌ Insufficient words added ({num_found}/{num_required}, need at least 3).")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    logger.info(f"Found: {sorted(found_words)}, Missing: {sorted(missing_words)}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "required_words": sorted(required_words),
            "found_words": sorted(list(found_words)),
            "missing_words": sorted(list(missing_words)),
            "case_mismatches": case_mismatches,
            "total_dict_size": len(dict_content),
            "num_found": num_found,
            "num_required": num_required
        }
    }
