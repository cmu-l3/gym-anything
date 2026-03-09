#!/usr/bin/env python3
"""
Verifier for Setup Custom Problem Matcher task
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_problem_matcher(traj, env_info, task_info):
    """
    Verify that custom problem matcher is correctly configured.
    
    Checks:
    1. tasks.json exists and is valid JSON (10 pts)
    2. Contains a task with "build" and "hwc" in label (20 pts)
    3. Task has correct type and command (10 pts)
    4. Problem matcher exists (20 pts)
    5. Pattern has required structure (15 pts)
    6. Regex matches test strings (10 pts)
    7. Severity mapping is correct (10 pts)
    8. CONTRIBUTING.md exists with content (5 pts)
    
    Total: 100 points
    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_problem_matcher_')
    
    try:
        # Copy exported files
        tasks_json_path = os.path.join(temp_dir, "tasks.json")
        contributing_path = os.path.join(temp_dir, "contributing.md")
        
        try:
            copy_from_env("/tmp/tasks.json", tasks_json_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy tasks.json: {str(e)}"
            }
        
        try:
            copy_from_env("/tmp/contributing.md", contributing_path)
        except Exception as e:
            logger.warning(f"Failed to copy CONTRIBUTING.md: {e}")
        
        score = 0
        max_score = 100
        feedback_parts = []
        details = {}
        
        # === Check 1: tasks.json exists and is valid JSON (10 points) ===
        if not os.path.exists(tasks_json_path) or os.path.getsize(tasks_json_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ .vscode/tasks.json not found or empty",
                "details": {"tasks_json_exists": False}
            }
        
        score += 10
        feedback_parts.append("✅ tasks.json exists")
        details["tasks_json_exists"] = True
        
        # Parse JSON
        try:
            with open(tasks_json_path, 'r', encoding='utf-8') as f:
                tasks_config = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": score,
                "feedback": f"❌ tasks.json is not valid JSON: {str(e)}",
                "details": details
            }
        
        details["tasks_json_valid"] = True
        
        # === Check 2: Find the build task (20 points) ===
        tasks = tasks_config.get("tasks", [])
        if not isinstance(tasks, list) or len(tasks) == 0:
            return {
                "passed": False,
                "score": score,
                "feedback": "❌ No tasks found in tasks.json",
                "details": details
            }
        
        build_task = None
        for task in tasks:
            if not isinstance(task, dict):
                continue
            label = task.get("label", "").lower()
            if ("build" in label and "hwc" in label) or ("hwc" in label):
                build_task = task
                break
        
        if not build_task:
            # Try more lenient matching
            for task in tasks:
                if not isinstance(task, dict):
                    continue
                label = task.get("label", "").lower()
                command = task.get("command", "").lower()
                if "build" in label or "hwc" in label or "build.sh" in command:
                    build_task = task
                    break
        
        if not build_task:
            return {
                "passed": False,
                "score": score,
                "feedback": f"❌ No task with 'build' and 'hwc' in label found. Available tasks: {[t.get('label', 'unnamed') for t in tasks if isinstance(t, dict)]}",
                "details": details
            }
        
        score += 20
        task_label = build_task.get("label", "unnamed")
        feedback_parts.append(f"✅ Found task: '{task_label}'")
        details["build_task_found"] = True
        details["task_label"] = task_label
        
        # === Check 3: Task configuration (10 points) ===
        task_type = build_task.get("type", "")
        command = build_task.get("command", "")
        
        points_for_config = 0
        if task_type == "shell":
            points_for_config += 5
            feedback_parts.append("✅ Task type is 'shell'")
            details["task_type_correct"] = True
        else:
            feedback_parts.append(f"⚠️  Task type is '{task_type}' (expected 'shell')")
        
        if "build.sh" in command or "./build.sh" in command:
            points_for_config += 5
            feedback_parts.append("✅ Command references build.sh")
            details["command_correct"] = True
        else:
            feedback_parts.append(f"⚠️  Command '{command}' doesn't reference build.sh")
        
        score += points_for_config
        
        # === Check 4: Problem matcher exists (20 points) ===
        problem_matcher = build_task.get("problemMatcher")
        if not problem_matcher:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ No problemMatcher defined in task",
                "details": details
            }
        
        # Handle both object and array formats
        if isinstance(problem_matcher, list):
            if len(problem_matcher) == 0:
                return {
                    "passed": False,
                    "score": score,
                    "feedback": " | ".join(feedback_parts) + " | ❌ problemMatcher array is empty",
                    "details": details
                }
            problem_matcher = problem_matcher[0]
        elif isinstance(problem_matcher, str):
            # It's a reference to a predefined matcher, not good for our custom case
            feedback_parts.append(f"⚠️  problemMatcher is a string reference: '{problem_matcher}' (expected custom object)")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ problemMatcher should be a custom object, not a reference",
                "details": details
            }
        
        if not isinstance(problem_matcher, dict):
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + f" | ❌ problemMatcher has invalid type: {type(problem_matcher)}",
                "details": details
            }
        
        score += 20
        feedback_parts.append("✅ Problem matcher defined")
        details["problem_matcher_exists"] = True
        
        # === Check 5: Pattern structure (15 points) ===
        pattern = problem_matcher.get("pattern")
        if not pattern:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ No 'pattern' field in problemMatcher",
                "details": details
            }
        
        # Handle multi-line patterns (array of patterns)
        if isinstance(pattern, list):
            if len(pattern) == 0:
                return {
                    "passed": False,
                    "score": score,
                    "feedback": " | ".join(feedback_parts) + " | ❌ Pattern array is empty",
                    "details": details
                }
            pattern = pattern[0]  # Use first pattern for validation
        
        if not isinstance(pattern, dict):
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + f" | ❌ Pattern has invalid type: {type(pattern)}",
                "details": details
            }
        
        # Check required fields
        required_fields = ["regexp", "file", "line", "message"]
        missing_fields = [f for f in required_fields if f not in pattern]
        
        if missing_fields:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + f" | ❌ Pattern missing required fields: {missing_fields}",
                "details": details
            }
        
        # Severity field is important but we'll check it separately
        has_severity = "severity" in pattern
        
        score += 15
        feedback_parts.append("✅ Pattern has required structure (regexp, file, line, message)")
        details["pattern_structure_correct"] = True
        
        # === Check 6: Regex validation (10 points) ===
        regexp_str = pattern.get("regexp", "")
        if not regexp_str:
            feedback_parts.append("❌ Regex pattern is empty")
        else:
            test_strings = [
                "[HWC-ERROR] synthesis_engine.v:145:23 - Signal width mismatch: expected 8 bits, got 16",
                "[HWC-WARN] clock_divider.v:89:5 - Timing constraint may not be met",
                "[HWC-ERROR] memory_controller.v:234:12 - Undefined signal reference: addr_bus"
            ]
            
            try:
                regex = re.compile(regexp_str)
                matches = [regex.search(s) for s in test_strings]
                
                successful_matches = sum(1 for m in matches if m is not None)
                
                if successful_matches == len(test_strings):
                    score += 10
                    feedback_parts.append("✅ Regex matches all test error strings")
                    details["regex_matches_all"] = True
                    
                    # Store capture groups for diagnostics
                    if matches[0]:
                        details["regex_sample_groups"] = matches[0].groups() if hasattr(matches[0], 'groups') else []
                elif successful_matches > 0:
                    score += 5
                    feedback_parts.append(f"⚠️  Regex matches {successful_matches}/{len(test_strings)} test strings")
                    details["regex_matches_partial"] = True
                else:
                    feedback_parts.append("❌ Regex doesn't match any test error strings")
                    details["regex_matches_none"] = True
                
            except re.error as e:
                feedback_parts.append(f"❌ Invalid regex pattern: {str(e)}")
                details["regex_error"] = str(e)
        
        # === Check 7: Severity mapping (10 points) ===
        if not has_severity:
            feedback_parts.append("⚠️  No 'severity' field in pattern (errors won't be categorized)")
        else:
            # Check if severity mapping makes sense
            # Could be an integer index or use special mapping
            severity_field = pattern.get("severity")
            
            # Check if there's a severity mapping at the problem matcher level
            severity_mapping_exists = False
            if isinstance(severity_field, int):
                # It's a capture group index - good
                severity_mapping_exists = True
            
            # Check for owner field (sometimes severity needs proper owner)
            has_owner = "owner" in problem_matcher or "owner" in pattern
            
            if severity_mapping_exists or has_owner:
                score += 10
                feedback_parts.append("✅ Severity field configured")
                details["severity_configured"] = True
            else:
                score += 5
                feedback_parts.append("⚠️  Severity field exists but mapping unclear")
        
        # === Check 8: CONTRIBUTING.md (5 points) ===
        if os.path.exists(contributing_path) and os.path.getsize(contributing_path) > 0:
            with open(contributing_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            if len(content) >= 200:
                relevant_keywords = ["problem", "matcher", "error", "build", "task", "hwc", "regex"]
                has_keywords = any(kw in content.lower() for kw in relevant_keywords)
                
                if has_keywords:
                    score += 5
                    feedback_parts.append("✅ CONTRIBUTING.md exists with helpful content")
                    details["contributing_exists"] = True
                else:
                    score += 2
                    feedback_parts.append("⚠️  CONTRIBUTING.md exists but content may not be relevant")
            else:
                score += 2
                feedback_parts.append("⚠️  CONTRIBUTING.md exists but is too short")
        else:
            feedback_parts.append("⚠️  CONTRIBUTING.md not found (optional)")
        
        # === Final Assessment ===
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
