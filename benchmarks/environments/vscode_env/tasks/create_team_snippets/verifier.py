#!/usr/bin/env python3
"""
Verifier for create_team_snippets@1 task

Checks that Python snippets were created with proper structure and functionality:
- apilog snippet with logging setup and tab stops
- tryexcept snippet with error handling and tab stops
"""

import sys
import os
import logging
import json
import re
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_snippet_file(snippet_path):
    """
    Load and parse the snippet JSON file
    
    Returns:
        Tuple[bool, Dict[str, Any], str]: (success, snippets_dict, error_message)
    """
    if not os.path.exists(snippet_path):
        return False, {}, f"Snippet file not found at {snippet_path}"
    
    if os.path.getsize(snippet_path) == 0:
        return False, {}, "Snippet file is empty"
    
    try:
        with open(snippet_path, 'r', encoding='utf-8') as f:
            content = f.read()
            # Handle empty JSON object
            if content.strip() in ["{}", "{\n}", "{ }"]:
                return False, {}, "Snippet file contains only empty JSON object"
            snippets = json.loads(content)
        return True, snippets, ""
    except json.JSONDecodeError as e:
        return False, {}, f"Invalid JSON syntax: {e}"
    except Exception as e:
        return False, {}, f"Error reading file: {e}"


def verify_snippet_structure(snippet_name, snippet_data):
    """
    Verify a single snippet has required fields
    
    Returns:
        Tuple[bool, str]: (valid, error_message)
    """
    required_fields = ['prefix', 'body', 'description']
    
    for field in required_fields:
        if field not in snippet_data:
            return False, f"Missing required field: {field}"
    
    # Body must be a list
    if not isinstance(snippet_data['body'], list):
        return False, "Body must be an array of strings"
    
    if len(snippet_data['body']) == 0:
        return False, "Body is empty"
    
    # Prefix must be a non-empty string
    if not isinstance(snippet_data['prefix'], str) or not snippet_data['prefix']:
        return False, "Prefix must be a non-empty string"
    
    return True, ""


def verify_snippet_has_placeholders(snippet_data):
    """
    Check if snippet has tab stops/placeholders ($1, $2, ${1:default}, etc.)
    
    Returns:
        Tuple[bool, int]: (has_placeholders, count)
    """
    body_text = '\n'.join(snippet_data['body']) if isinstance(snippet_data['body'], list) else str(snippet_data['body'])
    
    # Look for $1, $2, ${1:default}, $0, etc.
    placeholder_pattern = r'\$\{?\d+:?[^}]*\}?'
    matches = re.findall(placeholder_pattern, body_text)
    
    return len(matches) > 0, len(matches)


def verify_apilog_snippet(snippet_data):
    """
    Verify the apilog snippet meets requirements
    
    Returns:
        Tuple[float, str]: (score_0_to_1, feedback)
    """
    score = 0.0
    feedback = []
    
    # Check structure (20%)
    valid, error = verify_snippet_structure('apilog', snippet_data)
    if not valid:
        return 0.0, f"Structure error: {error}"
    score += 0.2
    feedback.append("✅ Has required fields (prefix, body, description)")
    
    # Check prefix is reasonable (10%)
    prefix = snippet_data['prefix'].lower()
    if prefix in ['apilog', 'logapi', 'log', 'logging']:
        score += 0.1
        feedback.append(f"✅ Prefix '{snippet_data['prefix']}' is intuitive")
    else:
        feedback.append(f"⚠ Prefix '{snippet_data['prefix']}' works but 'apilog' is more intuitive")
        score += 0.05  # Partial credit
    
    # Check body content
    body_text = '\n'.join(snippet_data['body']).lower()
    
    # Must include logging module reference (20%)
    if 'logging' in body_text or 'logger' in body_text:
        score += 0.2
        feedback.append("✅ Includes logging functionality")
    else:
        feedback.append("❌ Missing logging functionality - no 'logging' or 'logger' found")
        return score, '; '.join(feedback)
    
    # Must have logger initialization (15%)
    if 'getlogger' in body_text or 'logging.getlogger' in body_text:
        score += 0.15
        feedback.append("✅ Has logger initialization (getLogger)")
    elif 'import logging' in body_text:
        score += 0.1
        feedback.append("⚠ Has logging import but missing getLogger (partial credit)")
    else:
        feedback.append("⚠ Missing logger initialization")
    
    # Must have logging call (15%)
    log_calls = ['logger.info', 'logger.debug', 'logger.warning', 'logger.error']
    has_log_call = any(call in body_text for call in log_calls)
    if has_log_call:
        score += 0.15
        feedback.append("✅ Contains logging call (logger.info/debug/etc)")
    else:
        feedback.append("⚠ Missing logging call (logger.info, logger.debug, etc)")
    
    # Check for placeholders (20%)
    has_placeholders, count = verify_snippet_has_placeholders(snippet_data)
    if has_placeholders:
        score += 0.2
        feedback.append(f"✅ Has {count} tab stop(s) for customization")
    else:
        feedback.append("❌ Missing tab stops ($1, $2, ${1:default}) - users can't customize")
    
    return score, '; '.join(feedback)


def verify_tryexcept_snippet(snippet_data):
    """
    Verify the tryexcept snippet meets requirements
    
    Returns:
        Tuple[float, str]: (score_0_to_1, feedback)
    """
    score = 0.0
    feedback = []
    
    # Check structure (20%)
    valid, error = verify_snippet_structure('tryexcept', snippet_data)
    if not valid:
        return 0.0, f"Structure error: {error}"
    score += 0.2
    feedback.append("✅ Has required fields (prefix, body, description)")
    
    # Check prefix (10%)
    prefix = snippet_data['prefix'].lower()
    if prefix in ['tryexcept', 'try', 'except', 'tryex', 'errorhandling', 'errorhandle']:
        score += 0.1
        feedback.append(f"✅ Prefix '{snippet_data['prefix']}' is intuitive")
    else:
        feedback.append(f"⚠ Prefix '{snippet_data['prefix']}' works but 'tryexcept' is clearer")
        score += 0.05
    
    # Check body content
    body_text = '\n'.join(snippet_data['body']).lower()
    
    # Must include try block (15%)
    if 'try:' in body_text or 'try' in body_text:
        score += 0.15
        feedback.append("✅ Has try block")
    else:
        feedback.append("❌ Missing try block")
        return score, '; '.join(feedback)
    
    # Must include except block (15%)
    if 'except' in body_text:
        score += 0.15
        feedback.append("✅ Has except block")
    else:
        feedback.append("❌ Missing except block")
        return score, '; '.join(feedback)
    
    # Should use specific exception (not bare except) (10%)
    if 'exception as' in body_text or 'error as' in body_text or re.search(r'except \w+error as', body_text):
        score += 0.1
        feedback.append("✅ Uses specific exception handling (Exception as e)")
    elif 'except:' in body_text and 'except ' not in body_text.replace('except:', ''):
        feedback.append("⚠ Uses bare 'except:' - should specify exception type")
    else:
        feedback.append("⚠ Exception handling could be more specific")
        score += 0.05  # Partial credit
    
    # Must include error logging (15%)
    has_logging = any(keyword in body_text for keyword in ['logger', 'logging', 'log.error', 'print'])
    if 'logger.error' in body_text or 'logger.exception' in body_text:
        score += 0.15
        feedback.append("✅ Includes proper error logging (logger.error)")
    elif has_logging:
        score += 0.1
        feedback.append("⚠ Has logging but should use logger.error (partial credit)")
    else:
        feedback.append("⚠ No error logging - team pattern should include logger.error()")
    
    # Check for placeholders (15%)
    has_placeholders, count = verify_snippet_has_placeholders(snippet_data)
    if has_placeholders:
        score += 0.15
        feedback.append(f"✅ Has {count} tab stop(s) for customization")
    else:
        feedback.append("❌ Missing tab stops - users can't customize exception type, operation, etc.")
    
    return score, '; '.join(feedback)


def verify_task(traj, env_info, task_info):
    """
    Main verification function for create_team_snippets task
    
    Returns:
        Dict with keys: passed (bool), score (int 0-100), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_snippet_path = "/tmp/python.json"
    temp_dir = tempfile.mkdtemp(prefix='snippet_verify_')
    local_snippet_path = os.path.join(temp_dir, 'python.json')
    
    feedback_dict = {
        'task': 'create_team_snippets@1',
        'passed': False,
        'score': 0,
        'feedback': ''
    }
    
    try:
        # Copy snippet file from container
        try:
            copy_from_env(container_snippet_path, local_snippet_path)
        except Exception as e:
            logger.error(f"Failed to copy snippet file: {e}")
            feedback_dict['feedback'] = f"Could not access snippet file: {e}"
            return feedback_dict
        
        # Load and parse snippet file
        success, snippets, error = load_snippet_file(local_snippet_path)
        if not success:
            logger.error(f"Snippet file error: {error}")
            feedback_dict['feedback'] = error
            return feedback_dict
        
        if not snippets:
            feedback_dict['feedback'] = "Snippet file is empty or contains no snippets"
            return feedback_dict
        
        logger.info(f"Found {len(snippets)} snippet(s) in file: {list(snippets.keys())}")
        
        # Find apilog snippet (case-insensitive search)
        snippet_names_lower = {k.lower(): k for k in snippets.keys()}
        
        apilog_key = None
        for possible in ['apilog', 'api-log', 'api_log', 'api log', 'logapi', 'log-api']:
            if possible in snippet_names_lower:
                apilog_key = snippet_names_lower[possible]
                break
        
        # Also check by prefix
        if not apilog_key:
            for key, data in snippets.items():
                if isinstance(data, dict) and 'prefix' in data:
                    if data['prefix'].lower() in ['apilog', 'logapi', 'log']:
                        apilog_key = key
                        break
        
        # Find tryexcept snippet
        tryexcept_key = None
        for possible in ['tryexcept', 'try-except', 'try_except', 'try except', 'errorhandling', 'error-handling', 'try']:
            if possible in snippet_names_lower:
                tryexcept_key = snippet_names_lower[possible]
                break
        
        # Also check by prefix
        if not tryexcept_key:
            for key, data in snippets.items():
                if isinstance(data, dict) and 'prefix' in data:
                    if data['prefix'].lower() in ['tryexcept', 'try', 'except', 'tryex']:
                        tryexcept_key = key
                        break
        
        feedback_parts = []
        total_score = 0.0
        
        # Verify apilog snippet (50% of total)
        if apilog_key:
            logger.info(f"Verifying apilog snippet: '{apilog_key}'")
            apilog_score, apilog_feedback = verify_apilog_snippet(snippets[apilog_key])
            total_score += apilog_score * 0.5
            feedback_parts.append(f"[apilog: {apilog_score*100:.0f}%] {apilog_feedback}")
            logger.info(f"apilog score: {apilog_score:.2f}")
        else:
            feedback_parts.append("❌ [apilog] Required snippet 'apilog' not found")
            logger.warning("apilog snippet not found in file")
        
        # Verify tryexcept snippet (50% of total)
        if tryexcept_key:
            logger.info(f"Verifying tryexcept snippet: '{tryexcept_key}'")
            tryexcept_score, tryexcept_feedback = verify_tryexcept_snippet(snippets[tryexcept_key])
            total_score += tryexcept_score * 0.5
            feedback_parts.append(f"[tryexcept: {tryexcept_score*100:.0f}%] {tryexcept_feedback}")
            logger.info(f"tryexcept score: {tryexcept_score:.2f}")
        else:
            feedback_parts.append("❌ [tryexcept] Required snippet 'tryexcept' not found")
            logger.warning("tryexcept snippet not found in file")
        
        # Calculate final score
        final_score_pct = int(total_score * 100)
        passed = final_score_pct >= 70  # 70% threshold
        
        feedback_dict['passed'] = passed
        feedback_dict['score'] = final_score_pct
        feedback_dict['feedback'] = ' | '.join(feedback_parts)
        
        logger.info(f"Final verification: score={final_score_pct}%, passed={passed}")
        
        return feedback_dict
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
