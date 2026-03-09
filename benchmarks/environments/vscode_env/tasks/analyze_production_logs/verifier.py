#!/usr/bin/env python3
"""
Verifier for analyze_production_logs@1

Checks:
1. The payment_processor.py file was modified
2. A TODO comment was added
3. The TODO comment is at or near line 127 (±2 lines)
4. The TODO comment mentions relevant error context
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_log_analysis(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Identified the critical error in the log file
    2. Navigated to the correct source file (payment_processor.py)
    3. Added a TODO comment at or near line 127
    4. The comment references the error or production issue
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/src/payment_processor.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    
    try:
        # Copy the modified file from container
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ payment_processor.py not found or empty. Did you navigate to the correct file?"
            }
        
        # Read the modified file
        content = read_file_content(temp_file.name)
        lines = content.split('\n')
        
        criteria_passed = 0
        max_criteria = 3
        feedback_parts = []
        
        # Criterion 1: Check if TODO comment exists anywhere
        todo_pattern = re.compile(r'^\s*#\s*TODO', re.IGNORECASE)
        has_todo = any(todo_pattern.match(line) for line in lines)
        
        if not has_todo:
            # Check if TODO exists but not as a proper comment
            if 'TODO' in content.upper():
                return {
                    "passed": False,
                    "score": 10,
                    "feedback": "❌ TODO found in file but not as a proper Python comment (should start with # TODO)"
                }
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No TODO comment found in payment_processor.py. You need to add a TODO comment documenting the error."
            }
        
        criteria_passed += 1
        
        # Find all TODO comments and their line numbers
        todo_lines = []
        for i, line in enumerate(lines, start=1):
            if todo_pattern.match(line):
                todo_lines.append((i, line.strip()))
        
        feedback_parts.append(f"✅ TODO comment found (line{'s' if len(todo_lines) > 1 else ''}: {', '.join(str(t[0]) for t in todo_lines)})")
        
        # Criterion 2: Check if any TODO is near line 127 (within ±2 lines)
        target_line = 127
        tolerance = 2
        
        correct_location_todos = [
            (line_num, line_text) for line_num, line_text in todo_lines
            if abs(line_num - target_line) <= tolerance
        ]
        
        if not correct_location_todos:
            return {
                "passed": False,
                "score": 30,
                "feedback": (
                    f"⚠️ TODO comment found but not at correct location. "
                    f"Found at line{'s' if len(todo_lines) > 1 else ''} {', '.join(str(t[0]) for t in todo_lines)}, "
                    f"expected near line {target_line} (the line mentioned in the error stack trace)"
                )
            }
        
        criteria_passed += 1
        todo_line_num, todo_text = correct_location_todos[0]
        feedback_parts.append(f"✅ TODO at correct location (line {todo_line_num}, target was {target_line})")
        
        # Criterion 3: Check if the TODO comment mentions relevant keywords
        # (error, AttributeError, gateway, api_key, production, none, null, etc.)
        relevant_keywords = [
            'error', 'attributeerror', 'gateway', 'api', 'key', 'production',
            'none', 'nonetype', 'null', 'payment', 'credentials', 'missing',
            'fix', 'bug', 'issue', 'fail'
        ]
        
        todo_text_lower = todo_text.lower()
        matching_keywords = [kw for kw in relevant_keywords if kw in todo_text_lower]
        
        if matching_keywords:
            criteria_passed += 1
            feedback_parts.append(
                f"✅ TODO includes error context (mentions: {', '.join(matching_keywords[:3])})"
            )
            
            # Perfect score
            score = 100
            passed = True
            feedback = " | ".join(feedback_parts)
        else:
            # TODO at correct location but lacks context
            feedback_parts.append(
                "⚠️ TODO lacks error context (should mention error type, cause, or what needs fixing)"
            )
            feedback_parts.append(
                f"   Your TODO: '{todo_text[:60]}...'"
            )
            
            score = 70
            passed = True  # Still pass, but with lower score
            feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "❌ payment_processor.py not found. "
                "Did you navigate to the correct file from the error stack trace?"
            )
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
