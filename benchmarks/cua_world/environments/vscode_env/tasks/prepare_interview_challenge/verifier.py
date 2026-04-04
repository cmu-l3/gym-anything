#!/usr/bin/env python3
"""
Verifier for Prepare Interview Challenge task
"""

import sys
import os
import logging
import tempfile
import shutil
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_interview_challenge(traj, env_info, task_info):
    """
    Verify that interview challenge workspace was created correctly.

    Checks:
    1. Folder structure complete (challenge/, tests/, evaluation/)
    2. Starter code valid (solution.py with signature, docstring, type hints, no implementation)
    3. Test suite comprehensive (test_solution.py with ≥5 test cases)
    4. Rubric well-defined (rubric.md with criteria and points)
    5. Instructions clear (README.md with problem, examples, constraints, time limit)
    6. VSCode configured (settings.json with hidden folders)
    7. Professional quality (consistent formatting, all key files present)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='interview_verify_')

    try:
        # Copy entire workspace directory
        workspace_remote = "/home/ga/workspace/interview_challenge"
        workspace_local = os.path.join(temp_dir, "interview_challenge")
        os.makedirs(workspace_local, exist_ok=True)

        # Try to copy the entire directory structure
        # We'll copy individual files since copy_from_env likely copies files, not directories
        files_to_check = [
            "challenge/solution.py",
            "tests/test_solution.py",
            "evaluation/rubric.md",
            "README.md",
            ".vscode/settings.json"
        ]

        copied_files = {}
        for rel_path in files_to_check:
            remote_path = os.path.join(workspace_remote, rel_path)
            local_path = os.path.join(workspace_local, rel_path)
            
            # Create parent directory
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            
            try:
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    copied_files[rel_path] = local_path
                    logger.info(f"✓ Copied {rel_path}")
                else:
                    logger.warning(f"✗ File empty or not found: {rel_path}")
            except Exception as e:
                logger.warning(f"✗ Failed to copy {rel_path}: {e}")

        criteria = {
            "folder_structure": False,
            "starter_code_valid": False,
            "test_suite_comprehensive": False,
            "rubric_defined": False,
            "instructions_clear": False,
            "vscode_configured": False,
            "professional_quality": False
        }
        
        feedback_parts = []

        # Criterion 1: Check folder structure (inferred from files)
        has_challenge = "challenge/solution.py" in copied_files
        has_tests = "tests/test_solution.py" in copied_files
        has_evaluation = "evaluation/rubric.md" in copied_files
        
        if has_challenge and has_tests and has_evaluation:
            criteria["folder_structure"] = True
            feedback_parts.append("✅ Folder structure complete (challenge/, tests/, evaluation/)")
        else:
            missing = []
            if not has_challenge:
                missing.append("challenge/")
            if not has_tests:
                missing.append("tests/")
            if not has_evaluation:
                missing.append("evaluation/")
            feedback_parts.append(f"❌ Missing folders: {', '.join(missing)}")

        # Criterion 2: Validate starter code (solution.py)
        if "challenge/solution.py" in copied_files:
            solution_path = copied_files["challenge/solution.py"]
            content = read_file_content(solution_path)
            
            has_import = "from typing import List" in content or "import typing" in content
            has_signature = "def two_sum" in content
            has_type_hints = "List[int]" in content or "list[int]" in content.lower()
            has_docstring = '"""' in content or "'''" in content
            no_implementation = (
                "pass" in content or 
                "NotImplementedError" in content or
                (content.count("return") == 0 and "pass" not in content)  # No return statement
            )
            
            # Check it's not fully implemented (shouldn't have actual logic)
            has_logic = any(keyword in content for keyword in ["for ", "while ", "if nums[", "dict(", "{}"])
            if has_logic:
                no_implementation = False
            
            checks = [has_signature, has_type_hints, has_docstring, no_implementation]
            if sum(checks) >= 3:  # At least 3 out of 4
                criteria["starter_code_valid"] = True
                feedback_parts.append("✅ Starter code valid (signature, docstring, type hints, no implementation)")
            else:
                issues = []
                if not has_signature:
                    issues.append("missing 'def two_sum'")
                if not has_type_hints:
                    issues.append("missing type hints")
                if not has_docstring:
                    issues.append("missing docstring")
                if not no_implementation:
                    issues.append("contains implementation")
                feedback_parts.append(f"❌ Starter code issues: {', '.join(issues)}")
        else:
            feedback_parts.append("❌ solution.py not found")

        # Criterion 3: Check test suite (test_solution.py)
        if "tests/test_solution.py" in copied_files:
            test_path = copied_files["tests/test_solution.py"]
            content = read_file_content(test_path)
            
            test_count = content.count("def test_")
            has_framework = (
                "import pytest" in content or 
                "import unittest" in content or
                "from unittest" in content
            )
            has_edge_cases = any(term in content.lower() for term in ["edge", "empty", "none", "[]", "duplicate", "negative"])
            
            if test_count >= 5 and has_framework:
                criteria["test_suite_comprehensive"] = True
                feedback_parts.append(f"✅ Test suite comprehensive ({test_count} test cases with framework)")
            else:
                issues = []
                if test_count < 5:
                    issues.append(f"only {test_count} test cases (need ≥5)")
                if not has_framework:
                    issues.append("missing pytest/unittest import")
                feedback_parts.append(f"❌ Test suite issues: {', '.join(issues)}")
        else:
            feedback_parts.append("❌ test_solution.py not found")

        # Criterion 4: Validate rubric (rubric.md)
        if "evaluation/rubric.md" in copied_files:
            rubric_path = copied_files["evaluation/rubric.md"]
            content = read_file_content(rubric_path)
            
            has_criteria = sum([
                term in content.lower() 
                for term in ["correctness", "efficiency", "quality", "performance", "style", "score", "points"]
            ]) >= 2
            has_points = any(char.isdigit() for char in content)
            is_substantial = len(content) > 150
            
            if has_criteria and has_points and is_substantial:
                criteria["rubric_defined"] = True
                feedback_parts.append("✅ Rubric well-defined (criteria, points)")
            else:
                issues = []
                if not has_criteria:
                    issues.append("missing evaluation criteria")
                if not has_points:
                    issues.append("missing point values")
                if not is_substantial:
                    issues.append(f"too short ({len(content)} chars)")
                feedback_parts.append(f"❌ Rubric issues: {', '.join(issues)}")
        else:
            feedback_parts.append("❌ rubric.md not found")

        # Criterion 5: Check README instructions
        if "README.md" in copied_files:
            readme_path = copied_files["README.md"]
            content = read_file_content(readme_path)
            
            has_problem = "two sum" in content.lower() or ("two" in content.lower() and "sum" in content.lower())
            has_example = "example" in content.lower() or ("input" in content.lower() and "output" in content.lower())
            has_constraints = "constraint" in content.lower() or "limit" in content.lower() or "range" in content.lower()
            has_time_limit = "minute" in content.lower() or "30" in content or "time" in content.lower()
            is_substantial = len(content) > 200
            
            checks = [has_problem, has_example, has_constraints or has_time_limit, is_substantial]
            if sum(checks) >= 3:
                criteria["instructions_clear"] = True
                feedback_parts.append("✅ Instructions clear (problem, examples, constraints)")
            else:
                issues = []
                if not has_problem:
                    issues.append("missing Two Sum problem description")
                if not has_example:
                    issues.append("missing examples")
                if not has_constraints and not has_time_limit:
                    issues.append("missing constraints/time limit")
                feedback_parts.append(f"❌ README issues: {', '.join(issues)}")
        else:
            feedback_parts.append("❌ README.md not found")

        # Criterion 6: Check VSCode settings
        if ".vscode/settings.json" in copied_files:
            settings_path = copied_files[".vscode/settings.json"]
            try:
                with open(settings_path, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                
                has_exclude = "files.exclude" in settings
                has_autosave = "files.autoSave" in settings
                
                # Check if tests/ and evaluation/ are hidden
                hidden_folders = False
                if has_exclude:
                    exclude_settings = settings.get("files.exclude", {})
                    tests_hidden = any("tests" in str(k).lower() for k in exclude_settings.keys())
                    eval_hidden = any("eval" in str(k).lower() for k in exclude_settings.keys())
                    hidden_folders = tests_hidden or eval_hidden
                
                if has_exclude or has_autosave or hidden_folders:
                    criteria["vscode_configured"] = True
                    feedback_parts.append("✅ VSCode configured (settings.json present)")
                else:
                    feedback_parts.append("⚠️ settings.json exists but minimal configuration")
                    criteria["vscode_configured"] = True  # Give credit for having the file
            except json.JSONDecodeError:
                feedback_parts.append("❌ settings.json has invalid JSON")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading settings.json: {str(e)}")
        else:
            feedback_parts.append("❌ .vscode/settings.json not found")

        # Criterion 7: Professional quality check
        required_files = [
            "challenge/solution.py",
            "tests/test_solution.py",
            "evaluation/rubric.md",
            "README.md"
        ]
        all_required_present = all(f in copied_files for f in required_files)
        
        total_content_length = sum(
            len(read_file_content(copied_files[f])) 
            for f in copied_files 
            if f in required_files
        )
        
        if all_required_present and total_content_length > 800:  # Reasonable amount of content
            criteria["professional_quality"] = True
            feedback_parts.append("✅ Professional quality (all key files present, substantial content)")
        else:
            issues = []
            if not all_required_present:
                missing = [f for f in required_files if f not in copied_files]
                issues.append(f"missing {len(missing)} file(s)")
            if total_content_length <= 800:
                issues.append(f"insufficient content ({total_content_length} chars)")
            feedback_parts.append(f"❌ Quality issues: {', '.join(issues)}")

        # Calculate score
        passed_count = sum(criteria.values())
        score = int((passed_count / 7) * 100)
        passed = score >= 80

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
