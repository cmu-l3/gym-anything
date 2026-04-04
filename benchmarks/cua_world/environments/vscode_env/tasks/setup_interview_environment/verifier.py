#!/usr/bin/env python3
"""
Verifier for Interview Environment Setup task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_interview_environment(traj, env_info, task_info):
    """
    Verify that interview environment was set up correctly.

    Checks:
    1. Workspace directory structure exists (directory + .vscode/)
    2. Settings.json configured correctly (theme, font, auto-save, minimap, activityBar)
    3. Tasks.json contains all three language runners (Python, JavaScript, Java)
    4. All three starter files exist with proper templates
    5. Privacy: no personal project references in workspace files
    6. Professional appearance: settings meet interview standards
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='interview_verify_')

    try:
        # Copy exported files from /tmp
        local_settings = os.path.join(temp_dir, "settings.json")
        local_tasks = os.path.join(temp_dir, "tasks.json")
        local_structure = os.path.join(temp_dir, "structure.txt")
        
        starter_files = {
            'starter.py': os.path.join(temp_dir, "starter.py"),
            'starter.js': os.path.join(temp_dir, "starter.js"),
            'Starter.java': os.path.join(temp_dir, "Starter.java")
        }

        try:
            copy_from_env("/tmp/interview_settings.json", local_settings)
            copy_from_env("/tmp/interview_tasks.json", local_tasks)
            copy_from_env("/tmp/workspace_structure.txt", local_structure)
            
            for file_name, local_path in starter_files.items():
                copy_from_env(f"/tmp/interview_{file_name}", local_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy workspace data: {str(e)}"}

        total_score = 0
        max_score = 100
        feedback_parts = []

        # Criterion 1: Workspace directory structure (15 points)
        structure_score = 0
        if os.path.exists(local_structure) and os.path.getsize(local_structure) > 0:
            with open(local_structure, 'r') as f:
                structure = f.read()
                if '/home/ga/interview_workspace' in structure:
                    structure_score += 7
                    feedback_parts.append("✅ Workspace directory exists")
                else:
                    feedback_parts.append("❌ Workspace directory not found")
                
                if '/home/ga/interview_workspace/.vscode' in structure:
                    structure_score += 8
                    feedback_parts.append("✅ .vscode subdirectory exists")
                else:
                    feedback_parts.append("❌ .vscode subdirectory not found")
        else:
            feedback_parts.append("❌ Workspace structure not found")
        
        total_score += structure_score

        # Criterion 2: Settings.json configuration (25 points)
        settings_score = 0
        if os.path.exists(local_settings) and os.path.getsize(local_settings) > 0:
            try:
                settings = parse_vscode_settings(local_settings)
                
                # Check theme
                theme = settings.get('workbench.colorTheme', '')
                if theme in ['Default Light+', 'Default Dark+', 'Default Light Modern', 'Default Dark Modern']:
                    settings_score += 5
                    feedback_parts.append(f"✅ Professional theme: {theme}")
                else:
                    feedback_parts.append(f"❌ Theme not professional: {theme}")
                
                # Check font size
                font_size = settings.get('editor.fontSize')
                if font_size and 14 <= font_size <= 16:
                    settings_score += 5
                    feedback_parts.append(f"✅ Readable font size: {font_size}")
                else:
                    feedback_parts.append(f"❌ Font size not readable: {font_size}")
                
                # Check auto-save
                auto_save = settings.get('files.autoSave')
                if auto_save in ['afterDelay', 'onFocusChange']:
                    settings_score += 5
                    feedback_parts.append(f"✅ Auto-save enabled: {auto_save}")
                else:
                    feedback_parts.append(f"❌ Auto-save not configured: {auto_save}")
                
                # Check minimap disabled
                minimap = settings.get('editor.minimap.enabled')
                if minimap is False:
                    settings_score += 5
                    feedback_parts.append("✅ Minimap disabled for cleaner view")
                else:
                    feedback_parts.append(f"❌ Minimap not disabled: {minimap}")
                
                # Check activity bar hidden
                activity_bar = settings.get('workbench.activityBar.visible')
                if activity_bar is False:
                    settings_score += 5
                    feedback_parts.append("✅ Activity bar hidden for cleaner view")
                else:
                    feedback_parts.append(f"❌ Activity bar not hidden: {activity_bar}")
            
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Settings.json invalid JSON: {str(e)}")
        else:
            feedback_parts.append("❌ Settings.json not found or empty")
        
        total_score += settings_score

        # Criterion 3: Tasks.json multi-language setup (25 points)
        tasks_score = 0
        if os.path.exists(local_tasks) and os.path.getsize(local_tasks) > 0:
            try:
                with open(local_tasks, 'r') as f:
                    tasks_config = json.load(f)
                
                tasks = tasks_config.get('tasks', [])
                
                # Check for Python runner
                python_found = False
                for task in tasks:
                    command = task.get('command', '').lower()
                    if 'python3' in command and '${file}' in command:
                        python_found = True
                        break
                
                if python_found:
                    tasks_score += 8
                    feedback_parts.append("✅ Python runner configured")
                else:
                    feedback_parts.append("❌ Python runner not found")
                
                # Check for JavaScript runner
                js_found = False
                for task in tasks:
                    command = task.get('command', '').lower()
                    if 'node' in command and '${file}' in command:
                        js_found = True
                        break
                
                if js_found:
                    tasks_score += 8
                    feedback_parts.append("✅ JavaScript runner configured")
                else:
                    feedback_parts.append("❌ JavaScript runner not found")
                
                # Check for Java runner
                java_found = False
                for task in tasks:
                    command = task.get('command', '')
                    if 'javac' in command and 'java' in command:
                        java_found = True
                        break
                
                if java_found:
                    tasks_score += 9
                    feedback_parts.append("✅ Java runner configured")
                else:
                    feedback_parts.append("❌ Java runner not found")
            
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Tasks.json invalid JSON: {str(e)}")
        else:
            feedback_parts.append("❌ Tasks.json not found or empty")
        
        total_score += tasks_score

        # Criterion 4: Starter files exist with templates (25 points)
        starter_score = 0
        
        # Check starter.py
        py_path = starter_files['starter.py']
        if os.path.exists(py_path) and os.path.getsize(py_path) > 0:
            with open(py_path, 'r') as f:
                content = f.read()
                if 'def solve_problem' in content and 'Technical Interview' in content:
                    starter_score += 8
                    feedback_parts.append("✅ starter.py template correct")
                else:
                    feedback_parts.append("❌ starter.py template incomplete")
        else:
            feedback_parts.append("❌ starter.py not found")
        
        # Check starter.js
        js_path = starter_files['starter.js']
        if os.path.exists(js_path) and os.path.getsize(js_path) > 0:
            with open(js_path, 'r') as f:
                content = f.read()
                if 'function solveProblem' in content and 'Technical Interview' in content:
                    starter_score += 8
                    feedback_parts.append("✅ starter.js template correct")
                else:
                    feedback_parts.append("❌ starter.js template incomplete")
        else:
            feedback_parts.append("❌ starter.js not found")
        
        # Check Starter.java
        java_path = starter_files['Starter.java']
        if os.path.exists(java_path) and os.path.getsize(java_path) > 0:
            with open(java_path, 'r') as f:
                content = f.read()
                if 'class Starter' in content and 'public static void main' in content and 'Technical Interview' in content:
                    starter_score += 9
                    feedback_parts.append("✅ Starter.java template correct")
                else:
                    feedback_parts.append("❌ Starter.java template incomplete")
        else:
            feedback_parts.append("❌ Starter.java not found")
        
        total_score += starter_score

        # Criterion 5: Privacy check (10 points)
        privacy_score = 10
        privacy_issues = []
        
        # Check for personal project references in settings
        if os.path.exists(local_settings):
            with open(local_settings, 'r') as f:
                settings_content = f.read().lower()
                sensitive_patterns = ['/personal/', '/private/', 'password', 'api_key', 'token']
                for pattern in sensitive_patterns:
                    if pattern in settings_content:
                        privacy_issues.append(pattern)
        
        # Check starter files for sensitive content
        for file_path in starter_files.values():
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    content = f.read().lower()
                    if 'password' in content or 'secret' in content or 'api_key' in content:
                        privacy_issues.append(os.path.basename(file_path))
        
        if privacy_issues:
            privacy_score = 0
            feedback_parts.append(f"❌ Privacy issues found: {', '.join(privacy_issues)}")
        else:
            feedback_parts.append("✅ No privacy issues detected")
        
        total_score += privacy_score

        # Final score calculation
        passed = total_score >= 80
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
