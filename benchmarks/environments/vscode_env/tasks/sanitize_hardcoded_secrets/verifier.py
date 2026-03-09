#!/usr/bin/env python3
"""
Verifier for Sanitize Hardcoded Secrets task

Checks that all hardcoded secrets were properly moved to .env file
and source code was updated to use environment variables.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Define the secrets we expect to find
EXPECTED_SECRETS = {
    'STRIPE_API_KEY': 'sk_live_51Hx',  # Start of Stripe key
    'DB_PASSWORD': 'P@ssw0rd!2024_SecureDB_Prod',
    'AWS_ACCESS_KEY_ID': 'AKIAIOSFODNN7EXAMPLE',
    'AWS_SECRET_ACCESS_KEY': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
}


def verify_secrets_sanitized(traj, env_info, task_info):
    """
    Verify that hardcoded secrets were properly sanitized.
    
    Critical checks:
    1. .env file exists and contains all 4 secrets
    2. Source files no longer contain hardcoded secret strings
    3. Source files use os.getenv() or os.environ
    4. .gitignore includes .env
    5. .env is not staged in Git
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='secrets_verify_')
    
    try:
        # Copy exported files
        files_to_copy = {
            'app.py': '/tmp/app.py',
            'db_connector.py': '/tmp/db_connector.py',
            'payment_handler.py': '/tmp/payment_handler.py',
            '.env': '/tmp/.env',
            '.gitignore': '/tmp/.gitignore',
            'git_status.txt': '/tmp/git_status.txt',
            'git_staged.txt': '/tmp/git_staged.txt',
            'git_tracked_env.txt': '/tmp/git_tracked_env.txt'
        }
        
        local_files = {}
        for name, remote_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, name)
            try:
                copy_from_env(remote_path, local_path)
                local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {name}: {e}")
                local_files[name] = None
        
        checks = {
            'env_file_exists': False,
            'env_has_stripe': False,
            'env_has_db_password': False,
            'env_has_aws_key_id': False,
            'env_has_aws_secret': False,
            'source_no_stripe': False,
            'source_no_db_password': False,
            'source_no_aws_keys': False,
            'source_uses_getenv': False,
            'gitignore_blocks_env': False,
            'env_not_in_git': False
        }
        
        feedback_parts = []
        
        # ==== CHECK 1: .env file exists and has all secrets ====
        env_path = local_files.get('.env')
        if env_path and os.path.exists(env_path):
            env_content = read_file_content(env_path)
            
            if env_content != "NO_ENV_FILE" and len(env_content) > 10:
                checks['env_file_exists'] = True
                
                # Check for each secret in .env
                if 'STRIPE_API_KEY' in env_content and 'sk_live_' in env_content:
                    checks['env_has_stripe'] = True
                else:
                    feedback_parts.append("❌ .env missing STRIPE_API_KEY")
                
                if 'DB_PASSWORD' in env_content and 'P@ssw0rd' in env_content:
                    checks['env_has_db_password'] = True
                else:
                    feedback_parts.append("❌ .env missing DB_PASSWORD")
                
                if 'AWS_ACCESS_KEY_ID' in env_content and 'AKIA' in env_content:
                    checks['env_has_aws_key_id'] = True
                else:
                    feedback_parts.append("❌ .env missing AWS_ACCESS_KEY_ID")
                
                if 'AWS_SECRET_ACCESS_KEY' in env_content and 'wJalrXUtnFEMI' in env_content:
                    checks['env_has_aws_secret'] = True
                else:
                    feedback_parts.append("❌ .env missing AWS_SECRET_ACCESS_KEY")
            else:
                feedback_parts.append("❌ .env file not created or empty")
        else:
            feedback_parts.append("❌ .env file not found")
        
        # ==== CHECK 2: Source files no longer contain hardcoded secrets ====
        all_source_content = ""
        
        for filename in ['app.py', 'db_connector.py', 'payment_handler.py']:
            file_path = local_files.get(filename)
            if file_path and os.path.exists(file_path):
                content = read_file_content(file_path)
                all_source_content += content + "\n"
        
        # Check that hardcoded secrets are NOT in source
        if 'sk_live_51H' not in all_source_content:
            checks['source_no_stripe'] = True
        else:
            feedback_parts.append("❌ Stripe key still hardcoded in source")
        
        if 'P@ssw0rd!2024_SecureDB_Prod' not in all_source_content:
            checks['source_no_db_password'] = True
        else:
            feedback_parts.append("❌ DB password still hardcoded in source")
        
        has_aws_secrets = ('AKIAIOSFODNN7EXAMPLE' in all_source_content or 
                          'wJalrXUtnFEMI/K7MDENG' in all_source_content)
        if not has_aws_secrets:
            checks['source_no_aws_keys'] = True
        else:
            feedback_parts.append("❌ AWS credentials still hardcoded in source")
        
        # ==== CHECK 3: Source uses os.getenv() or os.environ ====
        uses_getenv = bool(re.search(r'os\.getenv\s*\(|os\.environ\.get\s*\(|os\.environ\[', all_source_content))
        if uses_getenv:
            checks['source_uses_getenv'] = True
        else:
            feedback_parts.append("❌ Source doesn't use os.getenv() or os.environ")
        
        # ==== CHECK 4: .gitignore includes .env ====
        gitignore_path = local_files.get('.gitignore')
        if gitignore_path and os.path.exists(gitignore_path):
            gitignore_content = read_file_content(gitignore_path)
            if re.search(r'(^|\n)\.env($|\n|\.)', gitignore_content):
                checks['gitignore_blocks_env'] = True
            else:
                feedback_parts.append("❌ .gitignore doesn't include .env")
        else:
            feedback_parts.append("❌ .gitignore file not found")
        
        # ==== CHECK 5: .env not staged or tracked in Git ====
        git_staged_path = local_files.get('git_staged.txt')
        git_tracked_path = local_files.get('git_tracked_env.txt')
        
        env_not_leaked = True
        
        # Check staged changes don't contain secrets
        if git_staged_path and os.path.exists(git_staged_path):
            staged_content = read_file_content(git_staged_path)
            if any(secret in staged_content for secret in ['sk_live_', 'P@ssw0rd', 'AKIA', 'wJalrXUtnFEMI']):
                env_not_leaked = False
                feedback_parts.append("❌ Secrets found in staged Git changes")
        
        # Check .env is not tracked
        if git_tracked_path and os.path.exists(git_tracked_path):
            tracked_content = read_file_content(git_tracked_path)
            if '.env' in tracked_content and len(tracked_content.strip()) > 0:
                env_not_leaked = False
                feedback_parts.append("❌ .env file is tracked by Git")
        
        if env_not_leaked:
            checks['env_not_in_git'] = True
        
        # ==== SCORING ====
        # Critical checks that must pass
        critical_checks = [
            'env_file_exists',
            'source_no_stripe',
            'source_no_db_password', 
            'source_no_aws_keys',
            'gitignore_blocks_env',
            'env_not_in_git'
        ]
        
        # Important but not critical
        important_checks = [
            'env_has_stripe',
            'env_has_db_password',
            'env_has_aws_key_id',
            'env_has_aws_secret',
            'source_uses_getenv'
        ]
        
        critical_passed = sum(checks[k] for k in critical_checks)
        important_passed = sum(checks[k] for k in important_checks)
        
        total_checks = len(critical_checks) + len(important_checks)
        total_passed = critical_passed + important_passed
        
        # Calculate score (critical checks weighted more heavily)
        score = int(((critical_passed / len(critical_checks)) * 0.6 + 
                    (important_passed / len(important_checks)) * 0.4) * 100)
        
        # Must pass all critical checks to fully pass
        passed = critical_passed == len(critical_checks) and score >= 75
        
        # Generate summary feedback
        if passed:
            summary = "✅ All secrets successfully sanitized and secured"
        elif critical_passed >= len(critical_checks) - 1:
            summary = f"⚠️ Nearly complete but critical issue: {feedback_parts[0] if feedback_parts else 'unknown'}"
        else:
            summary = f"❌ Failed: {', '.join(feedback_parts[:3]) if feedback_parts else 'Multiple issues'}"
        
        if not feedback_parts:
            feedback_parts.append("✅ All security checks passed")
        
        final_feedback = summary + " | " + " | ".join(feedback_parts[:5])
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback,
            "details": checks
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        try:
            import shutil
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception as e:
            logger.warning(f"Failed to cleanup temp dir: {e}")
