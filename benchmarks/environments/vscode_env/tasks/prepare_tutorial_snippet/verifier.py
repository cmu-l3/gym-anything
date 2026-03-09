#!/usr/bin/env python3
"""
Verifier for Prepare Tutorial Snippet task
"""

import sys
import os
import ast
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_non_empty_lines(filepath: str) -> int:
    """Count non-empty, non-comment-only lines in file"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            count = 0
            for line in lines:
                stripped = line.strip()
                # Count lines that have content (not just whitespace or pure comments)
                if stripped and not stripped.startswith('#'):
                    count += 1
            return count
    except Exception as e:
        logger.error(f"Error counting lines: {e}")
        return 0


def count_comment_lines(filepath: str) -> int:
    """Count lines with comments"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            count = 0
            for line in lines:
                stripped = line.strip()
                if '#' in line:  # Has a comment
                    count += 1
            return count
    except Exception as e:
        logger.error(f"Error counting comments: {e}")
        return 0


def is_valid_python(filepath: str) -> tuple:
    """Check if file is syntactically valid Python"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            code = f.read()
        ast.parse(code)
        return True, ""
    except SyntaxError as e:
        return False, f"Syntax error at line {e.lineno}: {e.msg}"
    except Exception as e:
        return False, str(e)


def check_production_concerns_removed(filepath: str) -> tuple:
    """Verify production complexity was removed"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        issues = []
        
        # Check for Redis
        if 'redis' in content.lower() or 'Redis' in content:
            issues.append("Redis")
        
        # Check for logging
        if 'logging' in content or 'logger' in content:
            issues.append("logging")
        
        # Check for error handling (try/except) - should be simplified
        if 'try:' in content and 'except' in content:
            issues.append("try/except blocks")
        
        # Check for Config/MetricsCollector
        if 'Config' in content or 'MetricsCollector' in content or 'metrics' in content:
            issues.append("Config/Metrics")
        
        return len(issues) == 0, issues
    except Exception as e:
        logger.error(f"Error checking production concerns: {e}")
        return False, [f"Error: {e}"]


def check_core_logic_present(filepath: str) -> tuple:
    """Verify token bucket logic is present"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        missing = []
        
        # Look for key token bucket components
        # 1. Token refill logic (elapsed time calculation)
        has_elapsed_calc = 'elapsed' in content.lower() or ('time()' in content and '-' in content)
        if not has_elapsed_calc:
            missing.append("elapsed time calculation")
        
        # 2. Token refill (adding tokens back)
        has_token_refill = ('+' in content and ('token' in content.lower() or 'refill' in content.lower()))
        if not has_token_refill:
            missing.append("token refill logic")
        
        # 3. Token consumption (subtracting tokens)
        has_token_consumption = ('-=' in content or '- cost' in content or '- 1' in content) and 'token' in content.lower()
        if not has_token_consumption:
            missing.append("token consumption")
        
        # 4. Time tracking
        has_time_import = 'import time' in content or 'from time import' in content
        has_time_usage = 'time.time()' in content or 'time()' in content
        if not (has_time_import and has_time_usage):
            missing.append("time tracking")
        
        return len(missing) == 0, missing
    except Exception as e:
        logger.error(f"Error checking core logic: {e}")
        return False, [f"Error: {e}"]


def check_descriptive_names(filepath: str) -> tuple:
    """Check if variable names are educational (not abbreviated)"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Bad patterns (abbreviated variable names from production)
        bad_patterns = {
            'tkn': 'use "token" or "tokens" instead',
            'max_tkn': 'use "max_tokens" instead',
            'refill_rt': 'use "refill_rate" instead',
            'curr_tkns': 'use "current_tokens" instead',
            'new_tkns': 'use "new_tokens" instead',
            'last_t': 'use "last_time" or "last_refill_time" instead',
            ' rt': 'abbreviated name found',
            ' cfg': 'use "config" instead'
        }
        
        found_issues = []
        for pattern, suggestion in bad_patterns.items():
            if pattern in content:
                found_issues.append(f"'{pattern.strip()}' ({suggestion})")
        
        return len(found_issues) == 0, found_issues
    except Exception as e:
        logger.error(f"Error checking names: {e}")
        return False, [str(e)]


def verify_tutorial_snippet(traj, env_info, task_info):
    """
    Main verification function for prepare_tutorial_snippet task
    
    Checks:
    1. File exists at correct path
    2. Valid Python syntax
    3. Line count < 50 (simplified)
    4. Production concerns removed (Redis, logging, try/except, Config, Metrics)
    5. Core token bucket logic present
    6. Explanatory comments added (at least 3)
    7. Descriptive variable names used
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/tmp/simple_rate_limiter.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')

    try:
        # Copy the tutorial file
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy tutorial file: {str(e)}"
            }

        # Check if file exists and has content
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Tutorial file not created at /home/ga/workspace/tutorial/simple_rate_limiter.py or file is empty"
            }

        score = 0.0
        feedback_parts = []

        # Criterion 1: File exists (already passed)
        feedback_parts.append("✅ Tutorial file created")
        score += 0.15

        # Criterion 2: Valid Python syntax
        is_valid, syntax_error = is_valid_python(temp_file.name)
        if is_valid:
            feedback_parts.append("✅ Valid Python syntax")
            score += 0.15
        else:
            feedback_parts.append(f"❌ Syntax error: {syntax_error}")
            # Return early if syntax is invalid
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 3: Line count < 50
        line_count = count_non_empty_lines(temp_file.name)
        if line_count <= 50:
            feedback_parts.append(f"✅ File simplified to {line_count} lines (≤50)")
            score += 0.15
        else:
            feedback_parts.append(f"⚠️ File too long: {line_count} lines (should be ≤50)")
            score += 0.05

        # Criterion 4: Production concerns removed
        concerns_removed, issues = check_production_concerns_removed(temp_file.name)
        if concerns_removed:
            feedback_parts.append("✅ Production concerns removed")
            score += 0.20
        else:
            feedback_parts.append(f"❌ Production concerns found: {', '.join(issues)}")
            score += 0.05

        # Criterion 5: Core logic present
        logic_present, missing = check_core_logic_present(temp_file.name)
        if logic_present:
            feedback_parts.append("✅ Token bucket logic present")
            score += 0.15
        else:
            feedback_parts.append(f"❌ Missing core logic: {', '.join(missing)}")

        # Criterion 6: Explanatory comments
        comment_count = count_comment_lines(temp_file.name)
        if comment_count >= 3:
            feedback_parts.append(f"✅ {comment_count} explanatory comments added")
            score += 0.10
        else:
            feedback_parts.append(f"⚠️ Only {comment_count} comments (need ≥3 for tutorial)")
            score += 0.03

        # Criterion 7: Descriptive variable names
        names_ok, name_issues = check_descriptive_names(temp_file.name)
        if names_ok:
            feedback_parts.append("✅ Descriptive variable names used")
            score += 0.10
        else:
            feedback_parts.append(f"⚠️ Abbreviated names found: {', '.join(name_issues[:2])}")
            score += 0.03

        # Determine success
        passed = score >= 0.75

        # Add summary
        if passed:
            feedback_parts.append(f"🎉 Task completed! ({score:.0%})")
        else:
            feedback_parts.append(f"❌ Task incomplete ({score:.0%}, need ≥75%)")

        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": " | ".join(feedback_parts)
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
