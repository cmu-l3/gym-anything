#!/usr/bin/env python3
"""
Verifier for Extract Hardcoded Secrets task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# The secret that should be extracted
SECRET_KEY = "sk_live_51HxKQp2eZvKliHJxN9mYfB3K"


def verify_secrets_extracted(traj, env_info, task_info):
    """
    Verify that the hardcoded API key has been properly extracted to .env file.
    
    This is a security-critical task, so ALL criteria must pass.
    
    Checks:
    1. .env file exists and contains the API key
    2. .gitignore includes .env
    3. Hardcoded secret removed from main.py
    4. main.py properly imports and uses environment variables
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='secrets_verify_')
    
    try:
        # Copy exported files
        main_py_local = os.path.join(temp_dir, "main.py")
        dotenv_local = os.path.join(temp_dir, "dotenv_file")
        gitignore_local = os.path.join(temp_dir, "gitignore_file")
        
        try:
            copy_from_env("/tmp/main.py", main_py_local)
            copy_from_env("/tmp/dotenv_file", dotenv_local)
            copy_from_env("/tmp/gitignore_file", gitignore_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy files from environment: {str(e)}"
            }
        
        # Initialize check results
        checks = {
            "env_file_exists": False,
            "env_contains_key": False,
            "gitignore_updated": False,
            "secret_removed_from_code": False,
            "imports_env_loading": False,
            "uses_env_loading": False
        }
        
        feedback_parts = []
        
        # ============================================================
        # CHECK 1: .env file exists and contains the key
        # ============================================================
        if os.path.exists(dotenv_local) and os.path.getsize(dotenv_local) > 0:
            checks["env_file_exists"] = True
            env_content = read_file_content(dotenv_local)
            
            # Check if the secret key is present
            if SECRET_KEY in env_content:
                # Check if it's in proper KEY=VALUE format
                # Accept variations like API_KEY=, WEATHER_API_KEY=, etc.
                if re.search(r'(API_KEY|WEATHER_API_KEY)\s*=\s*["\']?' + re.escape(SECRET_KEY), env_content, re.IGNORECASE):
                    checks["env_contains_key"] = True
                    feedback_parts.append("✅ .env file created with API key in correct format")
                elif re.search(r'\w+\s*=\s*["\']?' + re.escape(SECRET_KEY), env_content):
                    checks["env_contains_key"] = True
                    feedback_parts.append("✅ .env file created with API key (non-standard variable name)")
                else:
                    feedback_parts.append("⚠️ .env contains the key but format may be incorrect")
            else:
                feedback_parts.append("❌ .env file exists but doesn't contain the API key")
        else:
            feedback_parts.append("❌ .env file not found or empty")
        
        # ============================================================
        # CHECK 2: .gitignore updated to include .env
        # ============================================================
        if os.path.exists(gitignore_local):
            gitignore_content = read_file_content(gitignore_local)
            
            # Check for .env entry (various patterns)
            if re.search(r'^\.env\s*$', gitignore_content, re.MULTILINE):
                checks["gitignore_updated"] = True
                feedback_parts.append("✅ .gitignore updated to exclude .env")
            elif '.env' in gitignore_content:
                checks["gitignore_updated"] = True
                feedback_parts.append("✅ .gitignore includes .env pattern")
            else:
                feedback_parts.append("❌ .gitignore doesn't include .env (SECURITY RISK!)")
        else:
            feedback_parts.append("❌ .gitignore file not found")
        
        # ============================================================
        # CHECK 3 & 4: main.py refactored properly
        # ============================================================
        if os.path.exists(main_py_local):
            main_content = read_file_content(main_py_local)
            
            # Check 3a: Hardcoded secret should NOT be in code anymore
            if SECRET_KEY not in main_content:
                checks["secret_removed_from_code"] = True
                feedback_parts.append("✅ Hardcoded secret removed from main.py")
            else:
                feedback_parts.append("❌ Hardcoded secret still present in main.py (SECURITY RISK!)")
            
            # Check 3b: Should import environment loading modules
            has_os_import = 'import os' in main_content
            has_dotenv_import = 'from dotenv import load_dotenv' in main_content or 'import dotenv' in main_content
            
            if has_os_import or has_dotenv_import:
                checks["imports_env_loading"] = True
                import_details = []
                if has_os_import:
                    import_details.append("os")
                if has_dotenv_import:
                    import_details.append("dotenv")
                feedback_parts.append(f"✅ Imports environment modules: {', '.join(import_details)}")
            else:
                feedback_parts.append("❌ Missing imports (need: import os and/or from dotenv import load_dotenv)")
            
            # Check 3c: Should use environment variable loading
            env_loading_patterns = [
                r'os\.environ\.get\s*\(\s*["\']API_KEY["\']',
                r'os\.getenv\s*\(\s*["\']API_KEY["\']',
                r'os\.environ\s*\[\s*["\']API_KEY["\']',
                r'os\.environ\.get\s*\(\s*["\']WEATHER_API_KEY["\']',
                r'os\.getenv\s*\(\s*["\']WEATHER_API_KEY["\']',
            ]
            
            has_env_loading = any(re.search(pattern, main_content) for pattern in env_loading_patterns)
            has_load_dotenv_call = 'load_dotenv()' in main_content or 'dotenv.load_dotenv()' in main_content
            
            if has_env_loading:
                checks["uses_env_loading"] = True
                if has_load_dotenv_call:
                    feedback_parts.append("✅ Code properly uses environment variables with load_dotenv()")
                else:
                    feedback_parts.append("✅ Code uses environment variables (consider adding load_dotenv() call)")
            else:
                feedback_parts.append("❌ Code doesn't load from environment variables (need os.getenv or os.environ.get)")
        else:
            feedback_parts.append("❌ main.py file not found")
        
        # ============================================================
        # SCORING: For security tasks, all critical checks must pass
        # ============================================================
        critical_checks = [
            checks["env_file_exists"],
            checks["env_contains_key"],
            checks["gitignore_updated"],
            checks["secret_removed_from_code"],
            checks["uses_env_loading"]
        ]
        
        # Count passed checks
        num_passed = sum(critical_checks)
        total_checks = len(critical_checks)
        
        # All critical checks must pass for security
        passed = all(critical_checks)
        score = int((num_passed / total_checks) * 100)
        
        # Add summary to feedback
        if passed:
            feedback_parts.insert(0, f"🎉 ALL CHECKS PASSED ({num_passed}/{total_checks})")
        else:
            feedback_parts.insert(0, f"⚠️ INCOMPLETE ({num_passed}/{total_checks} checks passed)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
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
        # Cleanup temporary directory
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
