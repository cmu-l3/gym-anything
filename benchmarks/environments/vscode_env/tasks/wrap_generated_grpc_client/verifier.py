#!/usr/bin/env python3
"""
Verifier for Wrap Generated gRPC Client task
"""

import sys
import os
import logging
import tempfile
import re
import ast

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_file_exists_in_env(copy_fn, container_path):
    """Check if file exists by trying to copy it"""
    temp = tempfile.NamedTemporaryFile(delete=False)
    try:
        copy_fn(container_path, temp.name)
        exists = os.path.exists(temp.name) and os.path.getsize(temp.name) > 0
        return exists
    except:
        return False
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def get_file_content(copy_fn, container_path):
    """Get file content from container"""
    temp = tempfile.NamedTemporaryFile(delete=False, mode='w+')
    try:
        copy_fn(container_path, temp.name)
        if os.path.exists(temp.name):
            with open(temp.name, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()
        return ""
    except Exception as e:
        logger.warning(f"Failed to get content from {container_path}: {e}")
        return ""
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_wrapper_implementation(traj, env_info, task_info):
    """
    Verify that gRPC client wrapper was implemented correctly.
    
    Checks:
    1. Wrapper file exists at src/user_service_client.py
    2. Contains a class definition
    3. References the generated client
    4. Implements retry logic
    5. Implements validation checks
    6. Example file updated to use wrapper
    7. Documentation present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    try:
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: Check wrapper file exists
        wrapper_path = "/tmp/user_service_client.py"
        wrapper_exists = False
        wrapper_content = ""
        
        if os.path.exists(wrapper_path) and os.path.getsize(wrapper_path) > 10:
            wrapper_exists = True
            with open(wrapper_path, 'r', encoding='utf-8', errors='ignore') as f:
                wrapper_content = f.read()
        
        if wrapper_exists and wrapper_content:
            criteria_passed += 1
            feedback_parts.append("✅ Wrapper file created at src/user_service_client.py")
        else:
            feedback_parts.append("❌ Wrapper file not found at src/user_service_client.py")
            # Early return if wrapper doesn't exist
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts) + " | Cannot verify further without wrapper file"
            }
        
        # Criterion 2: Check for class definition
        has_class = False
        class_match = re.search(r'class\s+(\w+)', wrapper_content)
        if class_match:
            has_class = True
            criteria_passed += 1
            class_name = class_match.group(1)
            feedback_parts.append(f"✅ Class '{class_name}' defined in wrapper")
        else:
            feedback_parts.append("❌ No class definition found in wrapper")
        
        # Criterion 3: Check wrapper references generated client
        references_generated = (
            'UserServiceStub' in wrapper_content or
            'user_service_pb2_grpc' in wrapper_content or
            'from generated' in wrapper_content or
            'import generated' in wrapper_content
        )
        if references_generated:
            criteria_passed += 1
            feedback_parts.append("✅ Wrapper references generated client")
        else:
            feedback_parts.append("❌ Wrapper doesn't reference generated client (UserServiceStub)")
        
        # Criterion 4: Check for retry logic
        retry_indicators = [
            'retry', 'attempt', 'range(3)', 'range(2)', 
            'for _ in range', 'for attempt in range',
            'while attempt', 'max_attempts', 'tenacity'
        ]
        wrapper_lower = wrapper_content.lower()
        has_retry = any(indicator.lower() in wrapper_lower for indicator in retry_indicators)
        
        # Also check for sleep (part of backoff)
        has_sleep = 'sleep' in wrapper_lower or 'time.sleep' in wrapper_content
        
        if has_retry and has_sleep:
            criteria_passed += 1
            feedback_parts.append("✅ Retry logic with backoff detected")
        elif has_retry:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Retry logic found but no sleep/backoff detected")
        else:
            feedback_parts.append("❌ No retry logic found (need loop with attempts and sleep)")
        
        # Criterion 5: Check for validation
        validation_indicators = [
            'age >= 18', 'age>=18', 'age < 18', 'age<18',
            'if age', 'ValueError', 'raise ValueError',
            'assert age', 'age > 17', 'age>17'
        ]
        has_validation = any(indicator in wrapper_content for indicator in validation_indicators)
        
        if has_validation:
            criteria_passed += 1
            feedback_parts.append("✅ Age validation detected (age >= 18 check)")
        else:
            feedback_parts.append("❌ No age validation found (should check age >= 18)")
        
        # Criterion 6: Check if example was updated
        example_path = "/tmp/client_example.py"
        example_content = ""
        
        if os.path.exists(example_path):
            with open(example_path, 'r', encoding='utf-8', errors='ignore') as f:
                example_content = f.read()
        
        uses_wrapper = (
            'from src.user_service_client import' in example_content or
            'from src import user_service_client' in example_content or
            'import src.user_service_client' in example_content
        )
        
        # Check it's NOT still using generated directly (in the import section)
        still_uses_generated = 'from generated.user_service_pb2_grpc import UserServiceStub' in example_content
        
        if uses_wrapper and not still_uses_generated:
            criteria_passed += 1
            feedback_parts.append("✅ Example updated to use wrapper instead of generated client")
        elif uses_wrapper:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Example imports wrapper but still imports generated client")
        else:
            feedback_parts.append("❌ Example not updated (should import from src.user_service_client)")
        
        # Criterion 7: Check for documentation
        doc_indicators = [
            '"""', "'''",  # Docstrings
            '# Wrapper', '# wrapper',
            '# Generated', '# generated',
            'DO NOT EDIT', 'overwritten',
            'regenerat', 'generated files'
        ]
        has_docs = any(indicator in wrapper_content for indicator in doc_indicators)
        
        if has_docs:
            criteria_passed += 1
            feedback_parts.append("✅ Documentation/comments explaining wrapper pattern found")
        else:
            feedback_parts.append("❌ No documentation found (add docstring explaining why wrapper exists)")
        
        # Bonus check: Generated files weren't modified
        if os.path.exists('/tmp/grpc_original_checksum.txt') and os.path.exists('/tmp/grpc_final_checksum.txt'):
            with open('/tmp/grpc_original_checksum.txt', 'r') as f:
                original = f.read().strip()
            with open('/tmp/grpc_final_checksum.txt', 'r') as f:
                final = f.read().strip()
            
            if original == final and original != "0":
                feedback_parts.append("🌟 BONUS: Generated files untouched (good practice!)")
            elif original != "0":
                feedback_parts.append("⚠️ Warning: Generated file may have been modified")
        
        # Calculate score (criteria_passed can be fractional due to partial credit)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 5/7 criteria
        
        feedback_parts.insert(0, f"Criteria: {criteria_passed:.1f}/{total_criteria}")
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
