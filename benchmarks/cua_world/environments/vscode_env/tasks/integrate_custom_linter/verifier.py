#!/usr/bin/env python3
"""
Verifier for Integrate Custom Linter task
"""

import sys
import os
import re
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_custom_linter_integration(traj, env_info, task_info):
    """
    Verify that custom linter was integrated with problem matcher.
    
    Checks:
    1. .vscode/tasks.json exists and is valid JSON
    2. Task configured with medscan command
    3. Problem matcher defined (not just a string reference)
    4. Regex pattern exists and matches sample output
    5. Required field mappings present (file, line, column, message)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='linter_verify_')
    
    try:
        # Copy tasks.json from /tmp (exported by export_result.sh)
        tasks_json_local = os.path.join(temp_dir, "tasks.json")
        
        try:
            copy_from_env("/tmp/tasks.json", tasks_json_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy tasks.json: {str(e)}"}
        
        if not os.path.exists(tasks_json_local) or os.path.getsize(tasks_json_local) == 0:
            return {"passed": False, "score": 0, "feedback": "tasks.json not found or empty"}
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Valid JSON
        try:
            with open(tasks_json_local, 'r', encoding='utf-8') as f:
                tasks_config = json.load(f)
            criteria_passed += 1
            feedback_parts.append("✅ tasks.json is valid JSON")
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ tasks.json is not valid JSON: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check tasks array exists
        if "tasks" not in tasks_config or not isinstance(tasks_config["tasks"], list):
            feedback_parts.append("❌ No tasks array found in tasks.json")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if len(tasks_config["tasks"]) == 0:
            feedback_parts.append("❌ tasks array is empty")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Find task with medscan command
        medscan_task = None
        for task in tasks_config["tasks"]:
            command = task.get("command", "")
            if isinstance(command, str) and "medscan" in command.lower():
                medscan_task = task
                break
        
        if medscan_task:
            criteria_passed += 1
            feedback_parts.append(f"✅ Task with medscan command found: '{medscan_task.get('label', 'unnamed')}'")
        else:
            feedback_parts.append("❌ No task with medscan command found")
            # Check if any task exists
            if tasks_config["tasks"]:
                sample_commands = [t.get("command", "N/A") for t in tasks_config["tasks"][:2]]
                feedback_parts.append(f"   Found commands: {sample_commands}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 3: Problem matcher defined (not just string reference)
        problem_matcher = medscan_task.get("problemMatcher")
        
        if not problem_matcher:
            feedback_parts.append("❌ No problemMatcher defined in task")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # If problemMatcher is a string (like "$tsc"), it's a reference, not custom
        if isinstance(problem_matcher, str):
            feedback_parts.append(f"❌ problemMatcher is a string reference ('{problem_matcher}'), need custom definition")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # If it's a list, check first element
        if isinstance(problem_matcher, list):
            if len(problem_matcher) == 0:
                feedback_parts.append("❌ problemMatcher array is empty")
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
            problem_matcher = problem_matcher[0]
        
        if not isinstance(problem_matcher, dict):
            feedback_parts.append(f"❌ problemMatcher is not properly defined (type: {type(problem_matcher)})")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Custom problemMatcher defined")
        
        # Criterion 4: Regex pattern exists and matches sample output
        pattern = problem_matcher.get("pattern", {})
        
        if not isinstance(pattern, dict):
            feedback_parts.append("❌ problemMatcher.pattern is not an object")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        regexp = pattern.get("regexp", "")
        
        if not regexp:
            feedback_parts.append("❌ No regexp defined in pattern")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Test regex against sample medscan output
        sample_outputs = [
            "SECURITY: /home/ga/workspace/medscan_project/src/auth.py:23:15: SQL injection vulnerability detected [HIGH]",
            "WARNING: /home/ga/workspace/medscan_project/src/utils.py:12:1: Unsafe deserialization pattern [MEDIUM]",
        ]
        
        regex_works = False
        match_obj = None
        
        try:
            for sample in sample_outputs:
                match_obj = re.match(regexp, sample)
                if match_obj:
                    regex_works = True
                    break
        except re.error as e:
            feedback_parts.append(f"❌ Invalid regex pattern: {str(e)}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if regex_works and match_obj:
            criteria_passed += 1
            num_groups = len(match_obj.groups())
            feedback_parts.append(f"✅ Regex pattern matches medscan output ({num_groups} capture groups)")
        else:
            feedback_parts.append(f"❌ Regex pattern doesn't match medscan output format")
            feedback_parts.append(f"   Pattern: {regexp[:80]}...")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 5: Required field mappings present
        required_fields = ["file", "line", "message"]
        optional_fields = ["column", "severity"]
        
        present_fields = []
        missing_fields = []
        
        for field in required_fields:
            if field in pattern:
                present_fields.append(field)
            else:
                missing_fields.append(field)
        
        # Check optional fields
        for field in optional_fields:
            if field in pattern:
                present_fields.append(field)
        
        if len(missing_fields) == 0:
            criteria_passed += 1
            feedback_parts.append(f"✅ All required field mappings present: {present_fields}")
        else:
            feedback_parts.append(f"❌ Missing field mappings: {missing_fields}")
            if present_fields:
                feedback_parts.append(f"   Present: {present_fields}")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_passed": criteria_passed,
                "total_criteria": total_criteria,
                "regex_groups": len(match_obj.groups()) if match_obj else 0,
                "field_mappings": present_fields
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
