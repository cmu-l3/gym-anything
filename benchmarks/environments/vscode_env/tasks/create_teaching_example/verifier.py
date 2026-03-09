#!/usr/bin/env python3
"""
Verifier for Create Teaching Example task

Checks that a self-contained, beginner-friendly JavaScript teaching example
demonstrating callbacks, Promises, and async/await was created.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_teaching_example(traj, env_info, task_info):
    """
    Verify the teaching example file was created correctly.
    
    Checks:
    1. File exists at correct path
    2. File length appropriate (150-300 lines)
    3. Has comprehensive header comment block
    4. Contains callback implementation
    5. Contains Promise implementation
    6. Contains async/await implementation
    7. Has educational comments
    8. Includes console logging
    9. Self-contained (no external dependencies)
    10. Has error handling
    
    Pass threshold: 70% (7/10 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    target_file = "/home/ga/workspace/teaching-materials/async-await-demo.js"
    
    # Create temp file for verification
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    
    try:
        # Try to copy the file
        copy_from_env(target_file, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            logger.error("File not found or empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File not found or empty: async-await-demo.js must be created at /home/ga/workspace/teaching-materials/"
            }
        
        # Read file content
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            content = f.read()
        
        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []
        
        # Criterion 1: File exists (already verified above)
        criteria_passed += 1
        feedback_parts.append("✅ File created successfully")
        
        # Criterion 2: Check file length (150-300 lines)
        line_count = len(content.split('\n'))
        if 150 <= line_count <= 300:
            criteria_passed += 1
            feedback_parts.append(f"✅ Appropriate length: {line_count} lines")
        elif line_count < 150:
            feedback_parts.append(f"⚠️ File too short: {line_count} lines (expected 150-300)")
        else:
            feedback_parts.append(f"⚠️ File too long: {line_count} lines (might overwhelm beginners)")
        
        # Criterion 3: Check for header comment block (should be substantial)
        # Look for multi-line comment at the start
        header_match = re.search(r'/\*\*?[\s\S]{100,800}?\*/', content[:1500])
        if header_match:
            criteria_passed += 1
            feedback_parts.append("✅ Has comprehensive header comment block")
        else:
            # Check for series of single-line comments at start
            first_lines = '\n'.join(content.split('\n')[:20])
            comment_lines = len([l for l in first_lines.split('\n') if l.strip().startswith('//')])
            if comment_lines >= 10:
                criteria_passed += 1
                feedback_parts.append("✅ Has detailed header comments")
            else:
                feedback_parts.append("❌ Missing comprehensive header comment block")
        
        # Criterion 4: Check for callback implementation
        callback_patterns = [
            r'callback\s*\(',
            r'function\s*\(\s*err',
            r'\bfunction\s*\([^)]*callback',
            r'\.on\s*\(\s*[\'"]error',
            r'\.on\s*\(\s*[\'"]data',
        ]
        has_callbacks = any(re.search(pattern, content, re.IGNORECASE) for pattern in callback_patterns)
        
        if has_callbacks:
            criteria_passed += 1
            feedback_parts.append("✅ Includes callback-based implementation")
        else:
            feedback_parts.append("❌ Missing callback implementation")
        
        # Criterion 5: Check for Promise implementation
        promise_patterns = [
            r'\.then\s*\(',
            r'new\s+Promise',
            r'\.catch\s*\(',
            r'Promise\.resolve',
            r'Promise\.reject',
        ]
        has_promises = any(re.search(pattern, content) for pattern in promise_patterns)
        
        if has_promises:
            criteria_passed += 1
            feedback_parts.append("✅ Includes Promise-based implementation")
        else:
            feedback_parts.append("❌ Missing Promise implementation")
        
        # Criterion 6: Check for async/await implementation
        async_patterns = [
            r'async\s+function',
            r'await\s+\w+',
        ]
        has_async_await = any(re.search(pattern, content) for pattern in async_patterns)
        
        if has_async_await:
            criteria_passed += 1
            feedback_parts.append("✅ Includes async/await implementation")
        else:
            feedback_parts.append("❌ Missing async/await implementation")
        
        # Criterion 7: Check for educational comments
        comment_lines = [line for line in content.split('\n') if line.strip().startswith('//') or ('/*' in line and '*/' in line)]
        comment_ratio = len(comment_lines) / max(line_count, 1)
        
        # Look for explanatory keywords in comments
        educational_keywords = ['why', 'because', 'notice', 'important', 'pitfall', 'avoid', 
                               'better', 'student', 'beginner', 'learn', 'understand', 'demonstrate',
                               'example', 'shows', 'this is', 'note that']
        educational_comment_count = sum(
            1 for line in comment_lines 
            if any(kw in line.lower() for kw in educational_keywords)
        )
        
        if comment_ratio >= 0.20 and educational_comment_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Well-commented with educational focus ({educational_comment_count} explanatory comments)")
        elif comment_ratio >= 0.10 or educational_comment_count >= 3:
            criteria_passed += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ Has comments but could be more educational ({educational_comment_count} explanatory comments)")
        else:
            feedback_parts.append(f"❌ Insufficient educational comments")
        
        # Criterion 8: Check for console logging (demonstration output)
        console_logs = len(re.findall(r'console\.(log|info|error|warn)', content, re.IGNORECASE))
        if console_logs >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Includes demonstration output ({console_logs} console statements)")
        elif console_logs >= 3:
            criteria_passed += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ Limited console output ({console_logs} statements, expected 6+)")
        else:
            feedback_parts.append(f"❌ Insufficient console logging")
        
        # Criterion 9: Check it's self-contained (no require of non-built-ins)
        requires = re.findall(r"require\s*\(\s*['\"](.+?)['\"]\s*\)", content)
        builtin_modules = ['http', 'https', 'fs', 'path', 'url', 'util', 'events', 
                          'stream', 'buffer', 'crypto', 'os', 'querystring']
        non_builtin_requires = [r for r in requires if r not in builtin_modules and not r.startswith('.')]
        
        if len(non_builtin_requires) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Self-contained (no external dependencies)")
        else:
            feedback_parts.append(f"❌ Has external dependencies: {non_builtin_requires}")
        
        # Criterion 10: Check for error handling
        error_handling_patterns = [
            r'try\s*\{',
            r'catch\s*\(',
            r'\.catch\s*\(',
            r'if\s*\(\s*err',
            r'error\s*\)',
        ]
        has_error_handling = any(re.search(pattern, content, re.IGNORECASE) for pattern in error_handling_patterns)
        
        if has_error_handling:
            criteria_passed += 1
            feedback_parts.append("✅ Includes error handling")
        else:
            feedback_parts.append("❌ Missing error handling")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        # Additional quality checks (informational, doesn't affect score)
        if 'jsonplaceholder' in content.lower():
            feedback_parts.append("ℹ️ Uses JSONPlaceholder API as specified")
        
        if re.search(r'node\s+\w+\.js', content, re.IGNORECASE):
            feedback_parts.append("ℹ️ Includes usage instructions")
        
        # Compile feedback
        feedback = " | ".join(feedback_parts)
        
        logger.info("\n=== Verification Results ===")
        for item in feedback_parts:
            logger.info(item)
        logger.info(f"\nCriteria passed: {criteria_passed}/{total_criteria}")
        logger.info(f"Final Score: {score}%")
        logger.info(f"Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp file
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
