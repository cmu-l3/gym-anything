#!/usr/bin/env python3
"""
Verifier for Rotate Exposed Credentials task

This verifier checks that:
1. The exposed Stripe API key was replaced in all production files
2. The new rotated key is present in all production files
3. Test mock keys remain unchanged in test files
4. Documentation placeholders remain unchanged in README
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

# Key constants
EXPOSED_KEY = "sk_live_A7xK9mP2nQ4rL8vB3wE6yT1"
NEW_KEY = "sk_live_Z9yN2mR5pK8qX3vL7wT4jE6"
MOCK_KEY = "sk_test_mock_12345"
DOC_PLACEHOLDER = "sk_live_your_key_here"


def verify_credential_rotation(traj, env_info, task_info):
    """
    Verify that exposed credentials were rotated correctly.
    
    Checks:
    1. Exposed key removed from 5 production files
    2. New key present in 5 production files
    3. Mock key preserved in 2 test files
    4. Documentation placeholder preserved in README
    
    All criteria must pass (100%) for security tasks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace = "/home/ga/workspace/payment_service"
    
    # Define files to check
    production_files = [
        "src/payment_client.py",
        "src/utils/stripe_helper.js",
        "config/production.yaml",
        ".env.example",
        ".env.local"
    ]
    
    test_files = [
        "tests/test_payment.py",
        "tests/stripe.test.js"
    ]
    
    doc_files = [
        "README.md"
    ]
    
    all_files = production_files + test_files + doc_files
    
    temp_dir = tempfile.mkdtemp(prefix='credential_verify_')
    
    try:
        # Copy all files for verification
        file_contents = {}
        missing_files = []
        
        for rel_path in all_files:
            container_path = os.path.join(workspace, rel_path)
            local_filename = rel_path.replace('/', '_').replace('.', '_')
            local_path = os.path.join(temp_dir, local_filename)
            
            try:
                copy_from_env(container_path, local_path)
                
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    with open(local_path, 'r', encoding='utf-8', errors='ignore') as f:
                        file_contents[rel_path] = f.read()
                else:
                    missing_files.append(rel_path)
                    logger.warning(f"File not found or empty: {rel_path}")
            except Exception as e:
                missing_files.append(rel_path)
                logger.error(f"Failed to copy {rel_path}: {e}")
        
        if missing_files:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Missing files: {', '.join(missing_files)}"
            }
        
        # Track results
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 8  # 5 prod files × 2 checks + 2 test files + 1 doc file
        
        # Check production files: exposed key should NOT exist, new key SHOULD exist
        for file_path in production_files:
            content = file_contents.get(file_path, "")
            
            # Check 1: Exposed key should NOT be present
            if EXPOSED_KEY in content:
                feedback_parts.append(f"❌ {file_path}: Exposed key still present (SECURITY RISK)")
            else:
                criteria_passed += 1
                # feedback_parts.append(f"✅ {file_path}: Exposed key removed")
            
            # Check 2: New key SHOULD be present
            if NEW_KEY in content:
                criteria_passed += 1
                # feedback_parts.append(f"✅ {file_path}: New key present")
            else:
                feedback_parts.append(f"❌ {file_path}: New key not found")
        
        # Summary for production files
        prod_checks_passed = criteria_passed
        if prod_checks_passed == len(production_files) * 2:
            feedback_parts.insert(0, f"✅ All {len(production_files)} production files updated correctly")
        
        # Check test files: mock key should still exist, new key should NOT be present
        for file_path in test_files:
            content = file_contents.get(file_path, "")
            
            # Mock key should still exist
            if MOCK_KEY in content:
                # Check that new production key was NOT added to tests
                if NEW_KEY not in content:
                    criteria_passed += 1
                    # feedback_parts.append(f"✅ {file_path}: Mock key preserved, production key not added")
                else:
                    feedback_parts.append(f"❌ {file_path}: Production key incorrectly added to test file")
            else:
                feedback_parts.append(f"❌ {file_path}: Mock key was incorrectly changed")
        
        # Summary for test files
        test_checks = criteria_passed - prod_checks_passed
        if test_checks == len(test_files):
            feedback_parts.insert(1, f"✅ Test files preserved correctly (mock keys unchanged)")
        
        # Check README: placeholder should still exist, new key should NOT be present
        readme_content = file_contents.get("README.md", "")
        
        if DOC_PLACEHOLDER in readme_content:
            if NEW_KEY not in readme_content:
                criteria_passed += 1
                feedback_parts.append("✅ README.md: Documentation placeholder preserved")
            else:
                feedback_parts.append("❌ README.md: Production key incorrectly added to documentation")
        else:
            feedback_parts.append("❌ README.md: Documentation placeholder was incorrectly changed")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        
        # For security tasks, we require 100% pass rate
        passed = (criteria_passed == total_criteria)
        
        # Add summary at the beginning
        if passed:
            summary = f"🔒 Security task completed successfully: {criteria_passed}/{total_criteria} checks passed"
        else:
            summary = f"❌ Security task failed: {criteria_passed}/{total_criteria} checks passed (requires 100%)"
        
        feedback_parts.insert(0, summary)
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
