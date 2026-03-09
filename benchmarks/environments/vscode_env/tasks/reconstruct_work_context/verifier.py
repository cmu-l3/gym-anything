#!/usr/bin/env python3
"""
Verifier for Reconstruct Work Context task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_work_context(traj, env_info, task_info):
    """
    Verify that work context reconstruction was completed successfully.
    
    Checks:
    1. WORK_CONTEXT.md exists in workspace root
    2. Contains required sections (Modified Files, TODOs, Current Status, Next Steps)
    3. References actual modified files from the workspace
    4. Lists TODO/FIXME items with locations
    5. Has structured format (headers, lists)
    6. Document is substantial (>500 characters)
    7. Git commands were likely used (bash history check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_context_')
    
    try:
        # Copy exported files
        result_file_path = "/tmp/work_context_result.md"
        bash_history_path = "/tmp/bash_history.txt"
        bash_history_file_path = "/tmp/bash_history_file.txt"
        workspace_listing_path = "/tmp/workspace_listing.txt"
        
        local_result = os.path.join(temp_dir, "work_context.md")
        local_bash_history = os.path.join(temp_dir, "bash_history.txt")
        local_bash_history_file = os.path.join(temp_dir, "bash_history_file.txt")
        local_workspace_listing = os.path.join(temp_dir, "workspace_listing.txt")
        
        # Copy result file
        try:
            copy_from_env(result_file_path, local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {"passed": False, "score": 0, "feedback": f"Failed to copy WORK_CONTEXT.md: {str(e)}"}
        
        # Copy bash history files (optional, for criterion 7)
        try:
            copy_from_env(bash_history_path, local_bash_history)
        except:
            logger.warning("Could not copy bash_history.txt")
        
        try:
            copy_from_env(bash_history_file_path, local_bash_history_file)
        except:
            logger.warning("Could not copy bash_history_file.txt")
        
        try:
            copy_from_env(workspace_listing_path, local_workspace_listing)
        except:
            logger.warning("Could not copy workspace_listing.txt")
        
        # Check if file exists and is not the "NOT_FOUND" marker
        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "❌ WORK_CONTEXT.md not found in workspace root"}
        
        content = read_file_content(local_result)
        
        if content == "NOT_FOUND" or len(content) < 50:
            return {"passed": False, "score": 0, "feedback": "❌ WORK_CONTEXT.md not found or is empty"}
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: Document exists (already verified above)
        criteria_passed += 1
        feedback_parts.append("✅ Document exists")
        
        # Criterion 2: Contains required sections
        required_sections = [
            ('modified files', 'Modified Files'),
            ('outstanding todo', 'Outstanding TODOs'),
            ('current status', 'Current Status'),
            ('next steps', 'Next Steps')
        ]
        
        sections_found = 0
        missing_sections = []
        content_lower = content.lower()
        
        for pattern, section_name in required_sections:
            if pattern in content_lower:
                sections_found += 1
            else:
                missing_sections.append(section_name)
        
        if sections_found >= 3:  # At least 3 out of 4 sections
            criteria_passed += 1
            if sections_found == 4:
                feedback_parts.append("✅ All required sections present")
            else:
                feedback_parts.append(f"✅ {sections_found}/4 required sections present")
        else:
            feedback_parts.append(f"❌ Only {sections_found}/4 sections found. Missing: {', '.join(missing_sections)}")
        
        # Criterion 3: References actual modified files
        expected_files = ['user_routes.py', 'validators.py', 'user.py', 'test_']
        files_mentioned = sum(1 for f in expected_files if f in content)
        
        if files_mentioned >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ References {files_mentioned} modified files")
        else:
            feedback_parts.append(f"❌ Only {files_mentioned} modified files mentioned (expected at least 3)")
        
        # Criterion 4: Lists TODO/FIXME items with locations
        # Look for patterns like "TODO:", "FIXME:", file:line, etc.
        todo_patterns = [
            r'(TODO|FIXME)',  # Basic TODO/FIXME mention
            r'(\.py:\d+)',    # File:line format
            r'(`[^`]+\.py[^`]*`)',  # Backtick code format with .py files
        ]
        
        todo_mentions = 0
        for pattern in todo_patterns:
            matches = re.findall(pattern, content, re.IGNORECASE)
            todo_mentions += len(matches)
        
        if todo_mentions >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Lists TODO/FIXME items ({todo_mentions} references)")
        else:
            feedback_parts.append(f"❌ Insufficient TODO/FIXME references ({todo_mentions} found, expected 3+)")
        
        # Criterion 5: Has structured format (headers and lists)
        has_headers = bool(re.search(r'^#+\s', content, re.MULTILINE))
        has_lists = bool(re.search(r'^[\s]*[-*\d+]\s', content, re.MULTILINE))
        
        if has_headers and has_lists:
            criteria_passed += 1
            feedback_parts.append("✅ Document has structured format (headers and lists)")
        elif has_headers or has_lists:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Document has partial structure")
        else:
            feedback_parts.append("❌ Document lacks structure (no headers or lists)")
        
        # Criterion 6: Document is substantial (>500 characters)
        if len(content) >= 500:
            criteria_passed += 1
            feedback_parts.append(f"✅ Document is substantial ({len(content)} chars)")
        else:
            feedback_parts.append(f"❌ Document too short ({len(content)} chars, expected 500+)")
        
        # Criterion 7: Git commands were used (check bash history)
        git_commands_used = False
        bash_content = ""
        
        if os.path.exists(local_bash_history):
            bash_content += read_file_content(local_bash_history)
        
        if os.path.exists(local_bash_history_file):
            bash_content += read_file_content(local_bash_history_file)
        
        if bash_content:
            git_commands = ['git status', 'git diff', 'git log', 'git branch']
            if any(cmd in bash_content.lower() for cmd in git_commands):
                git_commands_used = True
        
        # Alternative: check if git-related content is in the document
        # (user might have used GUI instead of terminal)
        if not git_commands_used:
            # Give partial credit if document shows understanding of git state
            if 'branch' in content_lower or 'commit' in content_lower or 'staged' in content_lower:
                git_commands_used = True
        
        if git_commands_used:
            criteria_passed += 1
            feedback_parts.append("✅ Git investigation performed")
        else:
            feedback_parts.append("⚠️ No evidence of git commands (optional)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 5/7 criteria
        
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
