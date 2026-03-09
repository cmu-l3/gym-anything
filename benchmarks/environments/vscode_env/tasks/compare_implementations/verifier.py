#!/usr/bin/env python3
"""
Verifier for Compare Implementations task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_comparison_task(traj, env_info, task_info):
    """
    Verify that implementation comparison was performed correctly.

    Checks:
    1. Both implementation files exist and contain expected patterns
    2. comparison_notes.txt exists
    3. Comparison notes mention the key optimization (memoization/lru_cache)
    4. Notes demonstrate actual comparison (not just generic text)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_compare_verify_')

    try:
        criteria_passed = 0
        max_criteria = 4
        feedback_parts = []

        # Criterion 1: Check both implementation files exist and have expected content
        trad_file_container = "/home/ga/workspace/pipelines/traditional_pipeline.py"
        func_file_container = "/home/ga/workspace/pipelines/functional_pipeline.py"

        trad_file_local = os.path.join(temp_dir, "traditional_pipeline.py")
        func_file_local = os.path.join(temp_dir, "functional_pipeline.py")

        try:
            copy_from_env(trad_file_container, trad_file_local)
            copy_from_env(func_file_container, func_file_local)

            trad_exists = os.path.exists(trad_file_local) and os.path.getsize(trad_file_local) > 0
            func_exists = os.path.exists(func_file_local) and os.path.getsize(func_file_local) > 0

            if trad_exists and func_exists:
                # Verify content patterns
                trad_content = read_file_content(trad_file_local)
                func_content = read_file_content(func_file_local)

                # Traditional file should have loops
                has_traditional_pattern = ('for ' in trad_content or 'while ' in trad_content) and 'def process_data' in trad_content

                # Functional file should have functional patterns and memoization
                has_functional_pattern = (
                    ('map(' in func_content or 'filter(' in func_content or 'reduce(' in func_content) and
                    '@lru_cache' in func_content and
                    'def process_data' in func_content
                )

                if has_traditional_pattern and has_functional_pattern:
                    criteria_passed += 1
                    feedback_parts.append("✅ Both implementation files present with correct patterns")
                else:
                    missing = []
                    if not has_traditional_pattern:
                        missing.append("traditional patterns")
                    if not has_functional_pattern:
                        missing.append("functional patterns with memoization")
                    feedback_parts.append(f"❌ Implementation files incomplete or missing: {', '.join(missing)}")
            else:
                feedback_parts.append("❌ One or both implementation files not found")

        except Exception as e:
            feedback_parts.append(f"❌ Error accessing implementation files: {str(e)}")

        # Criterion 2: Check comparison_notes.txt exists
        notes_file_container = "/home/ga/workspace/comparison_notes.txt"
        notes_file_local = os.path.join(temp_dir, "comparison_notes.txt")

        notes_exist = False
        notes_content = ""

        try:
            copy_from_env(notes_file_container, notes_file_local)
            if os.path.exists(notes_file_local) and os.path.getsize(notes_file_local) > 0:
                notes_exist = True
                notes_content = read_file_content(notes_file_local)
                criteria_passed += 1
                feedback_parts.append("✅ comparison_notes.txt file created")
            else:
                feedback_parts.append("❌ comparison_notes.txt not found or empty")
        except Exception as e:
            feedback_parts.append(f"❌ comparison_notes.txt not found: {str(e)}")

        # Criterion 3: Check if notes mention the optimization
        if notes_exist and notes_content:
            optimization_keywords = [
                'memoization', 'memoize', 'memo',
                'lru_cache', 'lru cache', '@lru_cache',
                'cache', 'caching', 'cached',
                'decorator',
                'functools'
            ]

            content_lower = notes_content.lower()
            mentioned_keywords = [kw for kw in optimization_keywords if kw in content_lower]

            if mentioned_keywords:
                criteria_passed += 1
                feedback_parts.append(f"✅ Optimization identified in notes (keywords: {', '.join(mentioned_keywords[:3])})")
            else:
                feedback_parts.append("❌ Notes do not mention the key optimization (memoization/lru_cache)")

        # Criterion 4: Check if notes demonstrate actual comparison (has some specificity)
        if notes_exist and notes_content:
            # Check for specificity - mentions of file names, function names, or technical details
            specificity_indicators = [
                'functional_pipeline' in content_lower,
                'traditional_pipeline' in content_lower,
                'functional' in content_lower and 'traditional' in content_lower,
                'loop' in content_lower or 'for loop' in content_lower,
                'map' in content_lower or 'filter' in content_lower,
                len(notes_content.strip()) >= 20,  # At least 20 characters
                'process' in content_lower or 'function' in content_lower
            ]

            if sum(specificity_indicators) >= 2:
                criteria_passed += 1
                feedback_parts.append("✅ Notes show evidence of actual comparison (contains specific details)")
            else:
                feedback_parts.append("⚠️ Notes are too generic (may not reflect actual comparison)")
        else:
            feedback_parts.append("❌ No comparison notes to analyze")

        # Calculate score
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        # Add summary
        if passed:
            summary = f"Task completed: {criteria_passed}/{max_criteria} criteria met"
        else:
            summary = f"Task incomplete: {criteria_passed}/{max_criteria} criteria met (need ≥3)"

        final_feedback = f"{summary}. {feedback}"

        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
