#!/usr/bin/env python3
"""
Verifier for Integrate Custom Build Tool task
"""

import sys
import os
import logging
import tempfile
import json
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_build_tool_integration(traj, env_info, task_info):
    """
    Verify that custom build tool problem matcher is correctly configured.
    
    Checks:
    1. .vscode/tasks.json file exists
    2. Valid JSON structure with tasks array
    3. Build task exists that runs fastbuild
    4. Custom problem matcher is configured (not a built-in reference)
    5. Regex pattern correctly captures file, line, severity, message
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Copy tasks.json from container
        container_path = "/tmp/tasks.json"
        
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            logger.error(f"Failed to copy tasks.json: {e}")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "❌ .vscode/tasks.json file not found. Did you create the tasks.json file in the .vscode directory?"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "❌ tasks.json file is empty or was not created"
            }
        
        # Parse JSON
        try:
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Invalid JSON syntax in tasks.json: {str(e)}"
            }
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Valid JSON structure with tasks array
        if 'tasks' not in data:
            feedback_parts.append("❌ tasks.json must have a 'tasks' array at top level")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not isinstance(data['tasks'], list) or len(data['tasks']) == 0:
            feedback_parts.append("❌ 'tasks' must be a non-empty array")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Valid JSON structure with tasks array")
        
        # Criterion 2: Find build task that references fastbuild
        build_task = None
        for task in data['tasks']:
            command = task.get('command', '').lower()
            label = task.get('label', '').lower()
            
            if 'fastbuild' in command or 'fastbuild' in label:
                build_task = task
                break
        
        if not build_task:
            feedback_parts.append("❌ No task found that runs 'fastbuild'. Expected task with 'fastbuild' in command or label")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        task_label = build_task.get('label', 'unnamed task')
        feedback_parts.append(f"✅ Build task found: '{task_label}'")
        
        # Criterion 3: Verify task type and command
        if build_task.get('type') != 'shell':
            feedback_parts.append(f"⚠️ Task type should be 'shell', got '{build_task.get('type')}'")
        
        command = build_task.get('command', '')
        if 'fastbuild' not in command:
            feedback_parts.append(f"⚠️ Command should reference 'fastbuild', got: {command}")
        
        criteria_passed += 1
        feedback_parts.append(f"✅ Task runs fastbuild command")
        
        # Criterion 4: Verify problem matcher exists and is custom
        if 'problemMatcher' not in build_task:
            feedback_parts.append("❌ Task must have a 'problemMatcher' property")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        problem_matcher = build_task['problemMatcher']
        
        # Check if it's a string reference (built-in) - we want custom
        if isinstance(problem_matcher, str):
            feedback_parts.append(f"❌ Using built-in problem matcher '{problem_matcher}'. You should create a CUSTOM problem matcher object for the fastbuild format")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Handle array of matchers
        if isinstance(problem_matcher, list):
            if len(problem_matcher) == 0:
                feedback_parts.append("❌ problemMatcher array is empty")
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
            problem_matcher = problem_matcher[0]  # Take first matcher
        
        if not isinstance(problem_matcher, dict):
            feedback_parts.append(f"❌ Problem matcher should be an object with 'pattern' field, got: {type(problem_matcher)}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Custom problem matcher configured")
        
        # Criterion 5: Verify regex pattern
        if 'pattern' not in problem_matcher:
            feedback_parts.append("❌ Problem matcher must have a 'pattern' field")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        pattern = problem_matcher['pattern']
        
        # Handle multi-line patterns (array)
        if isinstance(pattern, list):
            if len(pattern) == 0:
                feedback_parts.append("❌ Pattern array is empty")
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
            pattern = pattern[0]  # Check first pattern
        
        if not isinstance(pattern, dict):
            feedback_parts.append(f"❌ Pattern should be an object with 'regexp' field, got: {type(pattern)}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if 'regexp' not in pattern:
            feedback_parts.append("❌ Pattern must have a 'regexp' field with the regex")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        regex_pattern = pattern['regexp']
        
        # Test regex against sample error lines
        test_cases = [
            "src/main.cpp:15: ERROR: undefined variable 'counter'",
            "src/utils.cpp:42: WARNING: implicit type conversion from double to int",
            "src/parser.cpp:108: ERROR: expected ';' before '}' token",
        ]
        
        try:
            compiled_regex = re.compile(regex_pattern)
        except re.error as e:
            feedback_parts.append(f"❌ Invalid regex pattern: {str(e)}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        matches = 0
        capture_groups_ok = True
        
        for test_line in test_cases:
            match = compiled_regex.search(test_line)
            if match:
                matches += 1
                groups = match.groups()
                
                # Verify we capture at least 4 groups (file, line, severity, message)
                if len(groups) < 4:
                    capture_groups_ok = False
                    feedback_parts.append(f"⚠️ Regex captures only {len(groups)} groups, expected at least 4 (file, line, severity, message)")
                    break
        
        if matches == 0:
            feedback_parts.append(f"❌ Regex pattern does not match any test error lines. Pattern: '{regex_pattern}'")
            feedback_parts.append("Expected format: '<file>:<line>: <severity>: <message>'")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if matches < len(test_cases):
            feedback_parts.append(f"⚠️ Regex only matched {matches}/{len(test_cases)} test cases")
        
        if not capture_groups_ok:
            # Already added feedback above
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append(f"✅ Regex pattern valid and matches all {matches} test error lines")
        
        # Optional checks (warnings, not failures)
        if 'fileLocation' not in problem_matcher:
            feedback_parts.append("⚠️ Consider adding 'fileLocation' field (e.g., 'relative' or ['relative', '${workspaceFolder}'])")
        
        if 'owner' not in problem_matcher:
            feedback_parts.append("⚠️ Consider adding 'owner' field (e.g., 'fastbuild') for better problem categorization")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # 4/5 criteria = 80%
        
        # Add summary
        if passed:
            feedback_parts.insert(0, f"🎉 Task completed successfully! ({criteria_passed}/{total_criteria} criteria)")
        
        feedback = " | ".join(feedback_parts)
        
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
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
