#!/usr/bin/env python3
"""
Verifier for Record Macro Workflow task
Checks that functions were transformed using pattern-based editing
"""

import sys
import os
import re
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_macro_workflow(traj, env_info, task_info):
    """
    Verify that all functions were transformed with consistent pattern
    
    Checks:
    1. Logging import added (10 points)
    2. All 20 functions have type hints (40 points - 2 per function)
    3. All functions have logging statement (25 points)
    4. All functions have try-except blocks (25 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/macro_task/data_processors.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    
    try:
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name):
            return {"passed": False, "score": 0, "feedback": "File not found at expected location"}
        
        if os.path.getsize(temp_file.name) == 0:
            return {"passed": False, "score": 0, "feedback": "File is empty"}
        
        content = read_file_content(temp_file.name)
        
        if not content:
            return {"passed": False, "score": 0, "feedback": "Failed to read file content"}
        
        score = 0
        feedback_parts = []
        
        # Check 1: Logging import (10 points)
        if re.search(r'^import\s+logging', content, re.MULTILINE):
            score += 10
            feedback_parts.append("✅ Logging import added")
        else:
            feedback_parts.append("❌ Missing 'import logging' statement")
        
        # Define function names
        function_names = [
            "user", "order", "product", "inventory", "shipping",
            "payment", "customer", "vendor", "warehouse", "category",
            "tag", "review", "rating", "comment", "feedback",
            "analytics", "metrics", "report", "export", "import"
        ]
        
        # Check 2: Type hints on function signatures (40 points - 2 per function)
        type_hint_count = 0
        for func_name in function_names:
            # Pattern to match function with type hints
            # More flexible pattern to handle various spacing
            type_hint_pattern = rf'def\s+process_{func_name}_data\s*\(\s*raw_data\s*:\s*str\s*\)\s*->\s*str\s*:'
            if re.search(type_hint_pattern, content):
                type_hint_count += 1
        
        type_hint_score = (type_hint_count / 20) * 40
        score += type_hint_score
        feedback_parts.append(f"{'✅' if type_hint_count >= 18 else '⚠️'} {type_hint_count}/20 functions have type hints")
        
        # Check 3: Logging statements (25 points)
        logging_count = 0
        for func_name in function_names:
            # Check for logging statement with function name
            # Pattern: logging.info(f"Processing {name} data") or logging.info(f'Processing {name} data')
            logging_pattern = rf'logging\.info\s*\(\s*f["\']Processing\s+{func_name}\s+data["\']'
            if re.search(logging_pattern, content, re.IGNORECASE):
                logging_count += 1
        
        logging_score = (logging_count / 20) * 25
        score += logging_score
        feedback_parts.append(f"{'✅' if logging_count >= 18 else '⚠️'} {logging_count}/20 functions have logging statements")
        
        # Check 4: Try-except blocks (25 points)
        # Count try blocks (should be at least 18-20)
        try_count = len(re.findall(r'\btry\s*:', content))
        except_count = len(re.findall(r'\bexcept\s+Exception\s+as\s+\w+\s*:', content))
        
        # Use the minimum of try and except counts
        try_except_count = min(try_count, except_count)
        
        try_except_score = min((try_except_count / 20) * 25, 25)
        score += try_except_score
        
        if try_except_count >= 18:
            feedback_parts.append(f"✅ {try_except_count} try-except blocks found")
        else:
            feedback_parts.append(f"⚠️ Only {try_except_count}/20 try-except blocks found")
        
        # Additional check: verify at least some error logging exists
        error_logging_count = len(re.findall(r'logging\.error', content))
        if error_logging_count >= 15:
            feedback_parts.append(f"✅ Error logging present ({error_logging_count} statements)")
        elif error_logging_count > 0:
            feedback_parts.append(f"⚠️ Some error logging found ({error_logging_count} statements)")
        
        # Success threshold: 80/100
        passed = score >= 80
        
        feedback = " | ".join(feedback_parts)
        
        if passed:
            final_feedback = f"✅ PASS - Score: {score:.1f}/100 | {feedback}"
        else:
            final_feedback = f"❌ FAIL - Score: {score:.1f}/100 | {feedback}"
        
        logger.info(final_feedback)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": final_feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
