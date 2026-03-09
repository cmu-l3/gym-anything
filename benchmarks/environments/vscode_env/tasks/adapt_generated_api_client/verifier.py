#!/usr/bin/env python3
"""
Verifier for Adapt Generated API Client task
"""

import sys
import os
import logging
import tempfile
import re
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_api_client_adaptation(traj, env_info, task_info):
    """
    Verify that application code was adapted to generated API client breaking changes.

    Checks:
    1. TypeScript compilation succeeds (exit code 0)
    2. Application code updated with nested property access (user.profile.email)
    3. Generated API client file unchanged (checksum matches)
    4. Old direct access patterns removed (user.email without .profile)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_api_')

    try:
        criteria_passed = 0
        feedback_parts = []

        # Copy exported files
        local_files = {}
        files_to_copy = {
            'build_exit_code': '/tmp/build_exit_code.txt',
            'tsc_exit_code': '/tmp/tsc_exit_code.txt',
            'build_output': '/tmp/final_build_output.log',
            'tsc_output': '/tmp/tsc_output.log',
            'user_service': '/tmp/UserService.ts',
            'user_controller': '/tmp/UserController.ts',
            'user_profile': '/tmp/UserProfile.tsx',
            'api_client': '/tmp/api-client.ts',
            'checksum': '/tmp/api_client_checksum.txt',
            'original_checksum': '/tmp/api_client_original_checksum.txt'
        }

        for key, container_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, os.path.basename(container_path))
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path):
                    local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")

        # Criterion 1: TypeScript compilation succeeds
        compilation_success = False
        if 'tsc_exit_code' in local_files:
            try:
                with open(local_files['tsc_exit_code'], 'r') as f:
                    exit_code = int(f.read().strip())
                if exit_code == 0:
                    criteria_passed += 1
                    feedback_parts.append("✅ TypeScript compilation successful (no errors)")
                    compilation_success = True
                else:
                    # Try to get error details
                    error_msg = ""
                    if 'tsc_output' in local_files:
                        with open(local_files['tsc_output'], 'r') as f:
                            error_msg = f.read()[:300]
                    feedback_parts.append(f"❌ TypeScript compilation failed (exit code {exit_code})")
                    if error_msg:
                        feedback_parts.append(f"   Error preview: {error_msg}")
            except Exception as e:
                feedback_parts.append(f"❌ Could not read compilation result: {e}")
        else:
            feedback_parts.append("❌ Compilation result not found")

        # Criterion 2: Application code updated with nested property access
        updated_files_count = 0
        files_to_check = ['user_service', 'user_controller', 'user_profile']
        
        # Pattern to find correct nested access: user.profile.email or user.profile.name
        correct_pattern = re.compile(r'\buser\.profile\.(email|name)\b', re.IGNORECASE)
        
        for file_key in files_to_check:
            if file_key in local_files:
                try:
                    with open(local_files[file_key], 'r') as f:
                        content = f.read()
                    
                    if correct_pattern.search(content):
                        updated_files_count += 1
                except Exception as e:
                    logger.warning(f"Error reading {file_key}: {e}")

        if updated_files_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Application code updated ({updated_files_count}/3 files show correct nested access)")
        else:
            feedback_parts.append(f"❌ Insufficient updates ({updated_files_count}/3 files have nested access patterns)")

        # Criterion 3: Generated file unchanged (checksum verification)
        generated_file_unchanged = False
        if 'checksum' in local_files and 'original_checksum' in local_files:
            try:
                with open(local_files['checksum'], 'r') as f:
                    current_checksum = f.read().strip()
                with open(local_files['original_checksum'], 'r') as f:
                    original_checksum = f.read().strip()
                
                if current_checksum and original_checksum and current_checksum == original_checksum:
                    criteria_passed += 1
                    feedback_parts.append("✅ Generated API client file unchanged (correct approach)")
                    generated_file_unchanged = True
                else:
                    feedback_parts.append("❌ Generated file was modified (should only change application code)")
            except Exception as e:
                feedback_parts.append(f"⚠️ Could not verify file integrity: {e}")
        else:
            feedback_parts.append("⚠️ Checksum files not found")

        # Criterion 4: Old direct access patterns removed
        # Check that old patterns (user.email, user.name) WITHOUT .profile are NOT present
        old_pattern = re.compile(r'\buser\.(email|name)\b', re.IGNORECASE)
        old_patterns_found = False
        files_with_old_patterns = []

        for file_key in files_to_check:
            if file_key in local_files:
                try:
                    with open(local_files[file_key], 'r') as f:
                        content = f.read()
                    
                    # Find all matches
                    matches = old_pattern.findall(content)
                    if matches:
                        # Check if any match is NOT preceded by .profile
                        # We need to check the full match context
                        for match in old_pattern.finditer(content):
                            # Get some context before the match
                            start = max(0, match.start() - 10)
                            context = content[start:match.end()]
                            # If it doesn't have .profile before user, it's an old pattern
                            if '.profile.user.' not in context and 'profile.user.' not in context:
                                old_patterns_found = True
                                files_with_old_patterns.append(file_key)
                                break
                except Exception as e:
                    logger.warning(f"Error checking old patterns in {file_key}: {e}")

        if not old_patterns_found and updated_files_count > 0:
            criteria_passed += 1
            feedback_parts.append("✅ Old direct property access patterns removed")
        elif old_patterns_found:
            feedback_parts.append(f"❌ Old patterns still exist in: {', '.join(files_with_old_patterns)}")
        else:
            feedback_parts.append("❌ No evidence of proper updates")

        # Calculate score
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Score: {criteria_passed}/4 criteria met ({score}%)"

        if passed:
            feedback += "\n✅ Task completed successfully!"
        else:
            feedback += "\n❌ Task incomplete. Need 3/4 criteria to pass."

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
