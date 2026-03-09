#!/usr/bin/env python3
"""
Verifier for Competitive Coding Setup task
"""

import sys
import os
import logging
import tempfile
import shutil
import subprocess
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_competitive_setup(traj, env_info, task_info):
    """
    Verify competitive programming setup is complete and functional.
    
    Checks:
    1. tasks.json exists and contains "Run All Tests" task (1.0 point)
    2. keybindings.json exists and has Ctrl+Shift+T binding (1.0 point)
    3. Snippet file exists and has "cp" snippet (1.0 point)
    4. Solution file has implementation (0.5 point)
    5. Solution passes all test cases (1.5 points)
    
    Total: 5.0 points, pass threshold: 3.5 (70%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    workspace_dir = "/home/ga/workspace/cp_contest"
    feedback_parts = []
    score = 0.0
    max_score = 5.0
    
    temp_dir = tempfile.mkdtemp(prefix='cp_verify_')
    
    try:
        # Criterion 1: Verify tasks.json exists and has "Run All Tests" task (1.0 point)
        tasks_json_path = os.path.join(workspace_dir, ".vscode", "tasks.json")
        
        try:
            local_tasks = os.path.join(temp_dir, "tasks.json")
            copy_from_env(tasks_json_path, local_tasks)
            
            if os.path.exists(local_tasks) and os.path.getsize(local_tasks) > 0:
                with open(local_tasks, 'r', encoding='utf-8') as f:
                    tasks_config = json.load(f)
                
                has_test_task = False
                task_label = None
                for task in tasks_config.get('tasks', []):
                    label = task.get('label', '')
                    if 'run' in label.lower() and 'test' in label.lower():
                        has_test_task = True
                        task_label = label
                        break
                
                if has_test_task:
                    score += 1.0
                    feedback_parts.append(f"✅ tasks.json contains test task: '{task_label}'")
                else:
                    feedback_parts.append("❌ tasks.json missing 'Run All Tests' task")
            else:
                feedback_parts.append("❌ tasks.json not found or empty")
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ tasks.json invalid JSON: {str(e)[:50]}")
        except Exception as e:
            feedback_parts.append(f"❌ Failed to verify tasks.json: {str(e)[:50]}")
        
        # Criterion 2: Verify keybindings.json has Ctrl+Shift+T binding (1.0 point)
        keybindings_path = os.path.join(workspace_dir, ".vscode", "keybindings.json")
        
        try:
            local_keybindings = os.path.join(temp_dir, "keybindings.json")
            copy_from_env(keybindings_path, local_keybindings)
            
            if os.path.exists(local_keybindings) and os.path.getsize(local_keybindings) > 0:
                with open(local_keybindings, 'r', encoding='utf-8') as f:
                    keybindings = json.load(f)
                
                has_shortcut = False
                for binding in keybindings:
                    key = binding.get('key', '').lower()
                    if 'ctrl+shift+t' in key.replace(' ', ''):
                        has_shortcut = True
                        break
                
                if has_shortcut:
                    score += 1.0
                    feedback_parts.append("✅ Keybinding for Ctrl+Shift+T exists")
                else:
                    feedback_parts.append("❌ Ctrl+Shift+T keybinding not found")
            else:
                feedback_parts.append("❌ keybindings.json not found or empty")
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ keybindings.json invalid JSON: {str(e)[:50]}")
        except Exception as e:
            feedback_parts.append(f"❌ Failed to verify keybindings.json: {str(e)[:50]}")
        
        # Criterion 3: Verify snippet exists (1.0 point)
        snippets_path = os.path.join(workspace_dir, ".vscode", "cp_template.code-snippets")
        
        try:
            local_snippets = os.path.join(temp_dir, "cp_template.code-snippets")
            copy_from_env(snippets_path, local_snippets)
            
            if os.path.exists(local_snippets) and os.path.getsize(local_snippets) > 0:
                with open(local_snippets, 'r', encoding='utf-8') as f:
                    snippets = json.load(f)
                
                has_cp_snippet = False
                for key, value in snippets.items():
                    prefix = value.get('prefix', '') if isinstance(value, dict) else ''
                    if 'cp' in prefix.lower() or 'cp' in key.lower():
                        has_cp_snippet = True
                        break
                
                if has_cp_snippet:
                    score += 1.0
                    feedback_parts.append("✅ Competitive programming snippet exists")
                else:
                    feedback_parts.append("❌ No 'cp' snippet found")
            else:
                feedback_parts.append("❌ Snippet file not found or empty")
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ Snippet file invalid JSON: {str(e)[:50]}")
        except Exception as e:
            feedback_parts.append(f"❌ Failed to verify snippets: {str(e)[:50]}")
        
        # Criterion 4: Verify solution file has content (0.5 point)
        solution_path = os.path.join(workspace_dir, "problem_A.py")
        
        try:
            local_solution = os.path.join(temp_dir, "problem_A.py")
            copy_from_env(solution_path, local_solution)
            
            if os.path.exists(local_solution):
                with open(local_solution, 'r', encoding='utf-8') as f:
                    solution_content = f.read()
                
                # Filter out comments and empty lines
                lines = [line.strip() for line in solution_content.split('\n') 
                        if line.strip() and not line.strip().startswith('#')]
                
                if len(lines) > 0 and len(solution_content.strip()) > 50:
                    score += 0.5
                    feedback_parts.append("✅ Solution file has implementation")
                else:
                    feedback_parts.append("❌ Solution file is empty or only has comments")
            else:
                feedback_parts.append("❌ Solution file not found")
        except Exception as e:
            feedback_parts.append(f"❌ Failed to verify solution file: {str(e)[:50]}")
        
        # Criterion 5: Verify solution correctness by running tests (1.5 points)
        try:
            # Copy solution and test files
            local_solution = os.path.join(temp_dir, "problem_A.py")
            test_cases_dir = os.path.join(temp_dir, "test_cases")
            os.makedirs(test_cases_dir, exist_ok=True)
            
            # Try to copy solution if not already copied
            if not os.path.exists(local_solution):
                copy_from_env(solution_path, local_solution)
            
            # Copy test cases
            test_files_copied = True
            for i in [1, 2, 3]:
                try:
                    copy_from_env(
                        f"{workspace_dir}/test_cases/input_{i}.txt",
                        f"{test_cases_dir}/input_{i}.txt"
                    )
                    copy_from_env(
                        f"{workspace_dir}/test_cases/expected_{i}.txt",
                        f"{test_cases_dir}/expected_{i}.txt"
                    )
                except Exception as e:
                    logger.warning(f"Failed to copy test case {i}: {e}")
                    test_files_copied = False
            
            if test_files_copied and os.path.exists(local_solution):
                # Run tests
                all_passed = True
                passed_count = 0
                
                for i in [1, 2, 3]:
                    input_file = f"{test_cases_dir}/input_{i}.txt"
                    expected_file = f"{test_cases_dir}/expected_{i}.txt"
                    
                    if not os.path.exists(input_file) or not os.path.exists(expected_file):
                        continue
                    
                    try:
                        with open(input_file, 'r') as f_in:
                            result = subprocess.run(
                                ['python3', local_solution],
                                stdin=f_in,
                                capture_output=True,
                                text=True,
                                timeout=5
                            )
                        
                        with open(expected_file, 'r') as f_exp:
                            expected_output = f_exp.read().strip()
                        
                        actual_output = result.stdout.strip()
                        
                        if actual_output == expected_output:
                            passed_count += 1
                        else:
                            all_passed = False
                            feedback_parts.append(
                                f"❌ Test {i} failed: expected '{expected_output}', got '{actual_output}'"
                            )
                    
                    except subprocess.TimeoutExpired:
                        all_passed = False
                        feedback_parts.append(f"❌ Test {i} timed out (infinite loop?)")
                    except Exception as e:
                        all_passed = False
                        feedback_parts.append(f"❌ Test {i} error: {str(e)[:50]}")
                
                if all_passed and passed_count == 3:
                    score += 1.5
                    feedback_parts.append("✅ All test cases passed!")
                elif passed_count > 0:
                    # Partial credit
                    partial_score = (passed_count / 3) * 1.5
                    score += partial_score
                    feedback_parts.append(f"⚠️ {passed_count}/3 test cases passed")
                else:
                    feedback_parts.append("❌ No test cases passed")
            else:
                feedback_parts.append("❌ Could not run tests (missing files)")
        
        except Exception as e:
            logger.error(f"Error running tests: {e}", exc_info=True)
            feedback_parts.append(f"❌ Failed to run tests: {str(e)[:50]}")
        
        # Calculate final result
        passed = score >= (max_score * 0.7)  # Need 70% (3.5/5.0) to pass
        score_percent = int((score / max_score) * 100)
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\nFinal Score: {score:.1f}/{max_score:.1f} ({score_percent}%)"
        
        return {
            'passed': passed,
            'score': score / max_score,
            'feedback': feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
