#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_utilities@1
Checks that duplicate email validation was properly extracted to shared module
"""

import os
import re
import sys
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_consolidate_utilities(traj, env_info, task_info):
    """
    Verify the consolidate duplicate utilities task
    
    Checks:
    1. Shared utility module exists (20 pts)
    2. Module exports validation function (15 pts)
    3. Module contains regex pattern (10 pts)
    4. Module has documentation (5 pts)
    5-8. Files import from shared module (40 pts, 10 each)
    9. Duplicates removed (10 pts)
    10. Git commit exists (10 pts)
    Bonus: LoginForm bug fixed (5 pts)
    
    Returns:
        Dict with keys: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    results_dir = "/tmp/consolidate_results"
    temp_dir = tempfile.mkdtemp(prefix='verify_consolidate_')
    
    try:
        # Copy all exported files to local temp directory
        local_results = os.path.join(temp_dir, "results")
        os.makedirs(local_results, exist_ok=True)
        
        files_to_copy = [
            "emailValidator.js",
            "RegistrationForm.js",
            "LoginForm.js",
            "UserService.js",
            "NewsletterService.js",
            "git_log.txt",
            "last_commit.txt",
            "git_status.txt"
        ]
        
        copied_files = {}
        for filename in files_to_copy:
            try:
                src_path = f"{results_dir}/{filename}"
                dst_path = os.path.join(local_results, filename)
                copy_from_env(src_path, dst_path)
                if os.path.exists(dst_path) and os.path.getsize(dst_path) > 0:
                    copied_files[filename] = dst_path
                    logger.info(f"✅ Copied {filename}")
            except Exception as e:
                logger.warning(f"⚠️ Failed to copy {filename}: {e}")
        
        feedback_parts = []
        score = 0
        max_score = 100
        
        # ===== Check 1: Shared utility module exists (20 points) =====
        if "emailValidator.js" not in copied_files:
            feedback_parts.append("❌ CRITICAL: src/utils/emailValidator.js not found - must create shared module")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        validator_path = copied_files["emailValidator.js"]
        with open(validator_path, 'r', encoding='utf-8', errors='ignore') as f:
            validator_content = f.read()
        
        feedback_parts.append("✅ Shared utility module created (20 pts)")
        score += 20
        
        # ===== Check 2: Shared module exports a validation function (15 points) =====
        has_export = (
            'module.exports' in validator_content or
            'export ' in validator_content or
            'exports.' in validator_content
        )
        has_function = (
            'function validateEmail' in validator_content or
            'function isValidEmail' in validator_content or
            'const validateEmail' in validator_content or
            'const isValidEmail' in validator_content or
            'let validateEmail' in validator_content or
            'var validateEmail' in validator_content or
            'validateEmail =' in validator_content or
            'validateEmail:' in validator_content or
            'isValidEmail =' in validator_content
        )
        
        if not (has_export and has_function):
            feedback_parts.append("❌ Shared module must export a validation function (0/15 pts)")
            feedback_parts.append(f"   Has export: {has_export}, Has function: {has_function}")
        else:
            feedback_parts.append("✅ Shared module exports validation function (15 pts)")
            score += 15
        
        # ===== Check 3: Shared module contains email regex pattern (10 points) =====
        # Look for email regex pattern
        email_regex_patterns = [
            r'/\^?\[.*\]\+@\[.*\]\+\\\.\[.*\]\+\$?/',  # Escaped version
            r'@.*\.',  # Simple check for @ and .
        ]
        has_regex = any(re.search(pattern, validator_content) for pattern in email_regex_patterns)
        
        # Also check for literal regex string
        if not has_regex:
            has_regex = '@' in validator_content and ('test(' in validator_content or 'match(' in validator_content)
        
        if has_regex:
            feedback_parts.append("✅ Email regex pattern found (10 pts)")
            score += 10
        else:
            feedback_parts.append("⚠️ Email regex pattern not clearly detected (0/10 pts)")
        
        # ===== Check 4: Shared module has documentation comment (5 points) =====
        has_comment = bool(re.search(r'/\*.*?\*/|//.*', validator_content, re.DOTALL))
        if has_comment:
            feedback_parts.append("✅ Documentation comment present (5 pts)")
            score += 5
        else:
            feedback_parts.append("⚠️ Missing documentation comment (0/5 pts)")
        
        # ===== Checks 5-8: All 4 files import from shared module (40 points total) =====
        files_to_check = [
            ("RegistrationForm.js", "RegistrationForm", True),
            ("LoginForm.js", "LoginForm", True),
            ("UserService.js", "UserService", True),
            ("NewsletterService.js", "NewsletterService", False)
        ]
        
        files_with_import = 0
        files_without_duplicate = 0
        
        for filename, file_label, is_required in files_to_check:
            if filename not in copied_files:
                feedback_parts.append(f"⚠️ {filename} not found in results")
                continue
            
            filepath = copied_files[filename]
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Check for import statement
            has_import = (
                ('require(' in content and 'emailValidator' in content) or
                ('import' in content and 'emailValidator' in content) or
                ('from' in content and 'emailValidator' in content)
            )
            
            if has_import:
                files_with_import += 1
                feedback_parts.append(f"  ✅ {file_label} imports shared utility")
                score += 10
            else:
                if is_required:
                    feedback_parts.append(f"  ❌ {file_label} doesn't import shared utility")
                else:
                    # NewsletterService partial credit if validation not added
                    feedback_parts.append(f"  ⚠️ {file_label} doesn't import (optional)")
                    score += 5
            
            # Check that duplicate validation logic is removed
            has_inline_regex = bool(re.search(r'/\^?\[.*\]\+@\[.*\]\+\\\.\[.*\]\+\$?/', content))
            
            # Check for local validation function definitions
            has_local_validation = False
            
            # Check for method definitions in classes
            if 'class' in content and 'Service' in filename:
                has_local_validation = bool(
                    re.search(r'\s+(checkEmail|validateEmail|isValidEmail)\s*\([^)]*\)\s*\{', content)
                )
            else:
                # Check for function definitions
                has_local_validation = bool(
                    re.search(r'function\s+(checkEmail|validateEmail|isValidEmail)\s*\(', content)
                )
                if not has_local_validation:
                    # Check for arrow/const function definitions
                    has_local_validation = bool(
                        re.search(r'(const|let|var)\s+(checkEmail|validateEmail|isValidEmail)\s*=', content)
                    )
            
            if not has_inline_regex and not has_local_validation:
                files_without_duplicate += 1
        
        feedback_parts.append(f"📊 Import status: {files_with_import}/4 files import shared utility")
        
        # ===== Check 9: Duplicate logic removed (10 points) =====
        if files_without_duplicate >= 3:
            feedback_parts.append(f"✅ Duplicates removed from {files_without_duplicate}/4 files (10 pts)")
            score += 10
        elif files_without_duplicate >= 2:
            feedback_parts.append(f"⚠️ Duplicates removed from only {files_without_duplicate}/4 files (5 pts)")
            score += 5
        else:
            feedback_parts.append(f"❌ Duplicates still present in most files (0/10 pts)")
        
        # ===== Check 10: Git commit exists (10 points) =====
        if "git_log.txt" in copied_files:
            with open(copied_files["git_log.txt"], 'r', encoding='utf-8', errors='ignore') as f:
                git_log = f.read()
            
            # Look for relevant keywords in commit messages
            consolidation_keywords = [
                'consolidate', 'extract', 'refactor', 'duplicate',
                'shared', 'utility', 'utils', 'dedup', 'common'
            ]
            
            has_relevant_commit = any(
                keyword.lower() in git_log.lower() 
                for keyword in consolidation_keywords
            )
            
            # Check that it's not just the initial commit
            commit_lines = [line for line in git_log.split('\n') if line.strip() and line.strip() != "No commits"]
            has_new_commit = len(commit_lines) >= 2  # Initial + refactor commit
            
            if has_relevant_commit and has_new_commit:
                feedback_parts.append("✅ Git commit with relevant message found (10 pts)")
                score += 10
            elif has_new_commit:
                feedback_parts.append("⚠️ Git commit exists but message unclear (5 pts)")
                score += 5
            else:
                feedback_parts.append("❌ No new git commit found (0/10 pts)")
        else:
            feedback_parts.append("❌ Git log not found (0/10 pts)")
        
        # ===== Bonus Check: LoginForm bug fixed (5 points) =====
        if "LoginForm.js" in copied_files:
            with open(copied_files["LoginForm.js"], 'r', encoding='utf-8', errors='ignore') as f:
                login_content = f.read()
            
            # Check if bug is fixed - either by removing the function or adding return
            bug_fixed = False
            
            # If using shared import, bug is automatically fixed
            if 'require(' in login_content and 'emailValidator' in login_content:
                bug_fixed = True
            elif 'import' in login_content and 'emailValidator' in login_content:
                bug_fixed = True
            # Or if local function has return statement now
            elif 'isValidEmail' in login_content:
                has_return = bool(re.search(r'return\s+.*test\s*\(', login_content))
                bug_fixed = has_return
            
            if bug_fixed:
                feedback_parts.append("🎁 BONUS: LoginForm bug fixed! (5 pts)")
                score += 5
            else:
                feedback_parts.append("ℹ️ LoginForm bug not fixed (no bonus)")
        
        # ===== Final Scoring =====
        passed = score >= 70  # Need 70% to pass
        
        feedback_parts.append(f"\n{'='*60}")
        feedback_parts.append(f"📊 Final Score: {score}/{max_score} points")
        feedback_parts.append(f"{'='*60}")
        
        if passed:
            feedback_parts.append("✅ PASS: Duplicate code successfully consolidated!")
        else:
            feedback_parts.append("❌ FAIL: More consolidation work needed (need 70+ points)")
            feedback_parts.append("\nKey requirements:")
            feedback_parts.append("  • Create src/utils/emailValidator.js with exported function")
            feedback_parts.append("  • Update all files to import the shared utility")
            feedback_parts.append("  • Remove duplicate validation code")
            feedback_parts.append("  • Commit changes with descriptive message")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
