#!/usr/bin/env python3
"""
Verifier for bypass_formatting_commits@1 task
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_git_blame_config(traj, env_info, task_info):
    """
    Verify that user configured git-blame-ignore-revs and identified the real author
    
    Checks:
    1. .git-blame-ignore-revs file exists and contains commit hashes
    2. File contains the correct formatting commit hashes
    3. Git config blame.ignoreRevsFile is set (bonus)
    4. Investigation report created
    5. Report identifies Alice Chen as the author
    6. Report contains correct commit hash (bonus)
    
    Returns:
        dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_bypass_')

    try:
        checks = {
            "ignore_file_exists": False,
            "ignore_file_has_commits": False,
            "correct_commits_identified": False,
            "git_config_set": False,
            "report_created": False,
            "report_identifies_alice": False,
            "correct_commit_hash": False
        }
        
        feedback_parts = []
        
        # Load reference commit hashes
        alice_commit = ""
        eslint_commit = ""
        prettier_commit = ""
        
        try:
            alice_temp = tempfile.NamedTemporaryFile(delete=False)
            copy_from_env("/tmp/alice_commit.txt", alice_temp.name)
            with open(alice_temp.name, 'r') as f:
                alice_commit = f.read().strip()
            os.unlink(alice_temp.name)
        except:
            logger.warning("Could not load alice_commit.txt")
        
        try:
            eslint_temp = tempfile.NamedTemporaryFile(delete=False)
            copy_from_env("/tmp/eslint_commit.txt", eslint_temp.name)
            with open(eslint_temp.name, 'r') as f:
                eslint_commit = f.read().strip()
            os.unlink(eslint_temp.name)
        except:
            logger.warning("Could not load eslint_commit.txt")
        
        try:
            prettier_temp = tempfile.NamedTemporaryFile(delete=False)
            copy_from_env("/tmp/prettier_commit.txt", prettier_temp.name)
            with open(prettier_temp.name, 'r') as f:
                prettier_commit = f.read().strip()
            os.unlink(prettier_temp.name)
        except:
            logger.warning("Could not load prettier_commit.txt")
        
        # Check 1: .git-blame-ignore-revs file exists and has content
        ignore_file_path = os.path.join(temp_dir, "git-blame-ignore-revs.txt")
        try:
            copy_from_env("/tmp/git-blame-ignore-revs.txt", ignore_file_path)
        except:
            logger.warning("Could not copy git-blame-ignore-revs.txt")
        
        if os.path.exists(ignore_file_path) and os.path.getsize(ignore_file_path) > 0:
            checks["ignore_file_exists"] = True
            feedback_parts.append("✅ .git-blame-ignore-revs file created")
            
            with open(ignore_file_path, 'r') as f:
                ignore_content = f.read()
            
            # Check 2: File contains commit hashes (at least 7-char hex strings)
            hash_pattern = r'\b[0-9a-f]{7,40}\b'
            hashes_found = re.findall(hash_pattern, ignore_content, re.IGNORECASE)
            
            if len(hashes_found) >= 2:
                checks["ignore_file_has_commits"] = True
                feedback_parts.append(f"✅ File contains {len(hashes_found)} commit hash(es)")
                
                # Check 3: Verify correct commits are present
                if eslint_commit and prettier_commit:
                    hashes_lower = [h.lower() for h in hashes_found]
                    
                    # Check if either full hash or short hash matches
                    prettier_found = any(
                        prettier_commit.lower().startswith(h) or h.startswith(prettier_commit[:7].lower())
                        for h in hashes_lower
                    )
                    eslint_found = any(
                        eslint_commit.lower().startswith(h) or h.startswith(eslint_commit[:7].lower())
                        for h in hashes_lower
                    )
                    
                    if prettier_found and eslint_found:
                        checks["correct_commits_identified"] = True
                        feedback_parts.append("✅ Correct formatting commits identified (ESLint + Prettier)")
                    elif prettier_found or eslint_found:
                        feedback_parts.append("⚠️ Only one formatting commit found (need both)")
                    else:
                        feedback_parts.append("⚠️ File has hashes but they may not be the formatting commits")
            else:
                feedback_parts.append(f"❌ File needs at least 2 commit hashes (found {len(hashes_found)})")
        else:
            feedback_parts.append("❌ .git-blame-ignore-revs file not created or empty")
        
        # Check 4: Git config set (bonus)
        git_config_path = os.path.join(temp_dir, "git_blame_config.txt")
        try:
            copy_from_env("/tmp/git_blame_config.txt", git_config_path)
            if os.path.exists(git_config_path):
                with open(git_config_path, 'r') as f:
                    config_content = f.read().strip()
                if config_content and ".git-blame-ignore-revs" in config_content:
                    checks["git_config_set"] = True
                    feedback_parts.append("⭐ Bonus: Git config blame.ignoreRevsFile is set")
        except:
            pass
        
        # Check 5 & 6: Investigation report
        report_found = False
        report_content = ""
        
        # Try multiple possible report filenames
        possible_reports = [
            "INVESTIGATION_REPORT.txt",
            "INVESTIGATION_REPORT.md",
            "investigation_report.txt",
            "bug_investigation.txt",
            "FINDINGS.txt",
            "findings.txt"
        ]
        
        for report_name in possible_reports:
            report_path = os.path.join(temp_dir, report_name)
            try:
                copy_from_env(f"/tmp/{report_name}", report_path)
                if os.path.exists(report_path) and os.path.getsize(report_path) > 0:
                    with open(report_path, 'r') as f:
                        report_content = f.read()
                    report_found = True
                    checks["report_created"] = True
                    feedback_parts.append(f"✅ Investigation report created ({report_name})")
                    break
            except:
                continue
        
        if not report_found:
            feedback_parts.append("❌ Investigation report not found (expected INVESTIGATION_REPORT.txt)")
        else:
            # Check if report identifies Alice
            report_lower = report_content.lower()
            if "alice" in report_lower:
                checks["report_identifies_alice"] = True
                feedback_parts.append("✅ Report correctly identifies Alice as the author")
                
                # Bonus: Check if report contains commit hash
                if alice_commit:
                    if alice_commit[:7].lower() in report_lower or alice_commit.lower() in report_lower:
                        checks["correct_commit_hash"] = True
                        feedback_parts.append("⭐ Bonus: Report contains Alice's commit hash")
            else:
                feedback_parts.append("❌ Report doesn't identify Alice Chen as the author")
        
        # Calculate score
        # Critical checks (must pass all for success)
        critical_checks = [
            checks["ignore_file_exists"],
            checks["ignore_file_has_commits"],
            checks["report_created"],
            checks["report_identifies_alice"]
        ]
        
        # Bonus checks
        bonus_checks = [
            checks["correct_commits_identified"],
            checks["git_config_set"],
            checks["correct_commit_hash"]
        ]
        
        if all(critical_checks):
            # Base reward for passing all critical checks
            base_reward = 80
            # Bonus points for additional checks
            bonus_reward = sum(bonus_checks) * 6.67  # Up to 20 points bonus
            score = min(100, int(base_reward + bonus_reward))
            passed = True
        else:
            # Partial credit based on what was completed
            critical_score = sum(critical_checks) / len(critical_checks) * 70
            bonus_score = sum(bonus_checks) / len(bonus_checks) * 10
            score = int(critical_score + bonus_score)
            passed = False
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "checks": checks
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
