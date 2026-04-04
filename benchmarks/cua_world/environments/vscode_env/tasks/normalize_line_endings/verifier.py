#!/usr/bin/env python3
"""
Verifier for normalize_line_endings@1
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_line_endings(traj, env_info, task_info):
    """
    Verify line ending normalization task
    
    Checks:
    1. VSCode workspace configured with files.eol = "lf" (25%)
    2. Text files converted to LF endings (35%)
    3. .gitattributes created with proper rules (25%)
    4. Git status shows minimal changes (15%)
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='verify_line_endings_')
    
    try:
        score = 0.0
        max_score = 4.0
        feedback_parts = []
        
        workspace_path = "/home/ga/workspace/payment-service"
        
        # === Criterion 1: VSCode workspace settings (25% = 1.0 point) ===
        settings_container_path = f"{workspace_path}/.vscode/settings.json"
        settings_local = os.path.join(temp_dir, "settings.json")
        
        try:
            copy_from_env(settings_container_path, settings_local)
            
            if os.path.exists(settings_local) and os.path.getsize(settings_local) > 0:
                with open(settings_local, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                
                eol_setting = settings.get("files.eol")
                if eol_setting in ["lf", "\n"]:
                    score += 1.0
                    feedback_parts.append("✅ VSCode configured for LF endings")
                else:
                    feedback_parts.append(f"❌ VSCode files.eol is '{eol_setting}', expected 'lf'")
            else:
                feedback_parts.append("❌ .vscode/settings.json not found or empty")
        except Exception as e:
            feedback_parts.append(f"❌ Could not read .vscode/settings.json: {str(e)[:50]}")
        
        # === Criterion 2: File conversions (35% = 1.4 points) ===
        files_to_check = [
            ("src/api.py", "api.py"),
            ("src/models.py", "models.py"),
            ("src/utils.js", "utils.js"),
            ("tests/test_api.py", "test_api.py"),
            ("scripts/deploy.sh", "deploy.sh"),
            ("docs/README.md", "README.md"),
            ("config/settings.json", "settings_config.json")  # Renamed to avoid conflict
        ]
        
        lf_count = 0
        total_files = len(files_to_check)
        
        for container_rel_path, local_name in files_to_check:
            container_path = f"{workspace_path}/{container_rel_path}"
            local_path = os.path.join(temp_dir, local_name)
            
            try:
                copy_from_env(container_path, local_path)
                
                if os.path.exists(local_path):
                    if has_lf_endings(local_path):
                        lf_count += 1
                    else:
                        logger.info(f"File {container_rel_path} still has CRLF")
            except Exception as e:
                logger.warning(f"Could not check {container_rel_path}: {e}")
        
        # Award proportional score
        conversion_score = (lf_count / total_files) * 1.4
        score += conversion_score
        
        if lf_count == total_files:
            feedback_parts.append(f"✅ All {total_files} files converted to LF")
        elif lf_count > 0:
            feedback_parts.append(f"⚠️ {lf_count}/{total_files} files converted to LF")
        else:
            feedback_parts.append(f"❌ No files converted to LF (0/{total_files})")
        
        # Extra check: deploy.sh specifically (critical file)
        deploy_local = os.path.join(temp_dir, "deploy.sh")
        if os.path.exists(deploy_local):
            if has_lf_endings(deploy_local):
                feedback_parts.append("✅ Critical file deploy.sh has LF endings")
            else:
                feedback_parts.append("⚠️ deploy.sh still has CRLF (blocks execution)")
        
        # === Criterion 3: .gitattributes (25% = 1.0 point) ===
        gitattributes_container = f"{workspace_path}/.gitattributes"
        gitattributes_local = os.path.join(temp_dir, "gitattributes")
        
        try:
            copy_from_env(gitattributes_container, gitattributes_local)
            
            if os.path.exists(gitattributes_local) and os.path.getsize(gitattributes_local) > 0:
                with open(gitattributes_local, 'r', encoding='utf-8') as f:
                    content = f.read().lower()
                
                # Check for comprehensive rules
                has_text_auto = "text=auto" in content
                has_eol_lf = "eol=lf" in content
                has_wildcard = ("* " in content or "*\t" in content)
                has_shell_rule = "*.sh" in content
                
                if has_eol_lf and (has_text_auto or has_wildcard):
                    score += 1.0
                    feedback_parts.append("✅ .gitattributes properly configured")
                elif has_eol_lf or (has_shell_rule and "eol=lf" in content):
                    score += 0.5
                    feedback_parts.append("⚠️ .gitattributes partially configured")
                else:
                    feedback_parts.append("❌ .gitattributes lacks proper eol=lf rules")
            else:
                feedback_parts.append("❌ .gitattributes not found")
        except Exception as e:
            feedback_parts.append(f"❌ Could not read .gitattributes: {str(e)[:50]}")
        
        # === Criterion 4: Git status (15% = 0.6 points) ===
        git_status_container = "/tmp/line_endings_output/git_status.txt"
        git_status_local = os.path.join(temp_dir, "git_status.txt")
        
        try:
            copy_from_env(git_status_container, git_status_local)
            
            if os.path.exists(git_status_local):
                with open(git_status_local, 'r', encoding='utf-8') as f:
                    status_content = f.read().strip()
                
                if status_content:
                    lines = status_content.split('\n')
                    modified_files = [l for l in lines if l.strip()]
                    num_modified = len(modified_files)
                    
                    # Should only see .vscode/settings.json and .gitattributes as new/modified
                    if num_modified <= 2:
                        score += 0.6
                        feedback_parts.append(f"✅ Git shows minimal changes ({num_modified} files)")
                    elif num_modified <= 5:
                        score += 0.3
                        feedback_parts.append(f"⚠️ Git shows some changes ({num_modified} files)")
                    else:
                        feedback_parts.append(f"❌ Git shows many changes ({num_modified} files)")
                else:
                    # Empty git status means clean working tree (could be good if everything was committed)
                    score += 0.6
                    feedback_parts.append("✅ Git working tree is clean")
        except Exception as e:
            logger.warning(f"Could not check git status: {e}")
            feedback_parts.append("⚠️ Could not verify git status")
        
        # Calculate final score
        final_score = int(min(score / max_score, 1.0) * 100)
        passed = final_score >= 70  # 70% threshold
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {final_score}/100 (passed: {passed})")
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def has_lf_endings(filepath: str) -> bool:
    """
    Check if file has LF (Unix) line endings, not CRLF
    
    Args:
        filepath: Path to file to check
        
    Returns:
        True if file uses LF endings exclusively (no CRLF detected)
    """
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
        
        # Check for CRLF (b'\r\n')
        has_crlf = b'\r\n' in content
        
        # If file has CRLF, it's not normalized
        if has_crlf:
            return False
        
        # If file has LF but no CRLF, it's good
        has_lf = b'\n' in content
        if has_lf:
            return True
        
        # If file has no line endings at all (empty or single line), consider it valid
        return True
    
    except Exception as e:
        logger.error(f"Error checking line endings for {filepath}: {e}")
        return False
