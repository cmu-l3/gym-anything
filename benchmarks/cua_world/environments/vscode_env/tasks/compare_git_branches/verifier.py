#!/usr/bin/env python3
"""
Verifier for Compare Git Branches task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_branch_comparison(traj, env_info, task_info):
    """
    Verify that the agent successfully compared Git branches in VSCode.
    
    Checks:
    1. Git repository setup (branches exist, file differs between them)
    2. Evidence of comparison activity (window titles, file access)
    3. Correct file targeted (database.py)
    4. Diff-related indicators in window state
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='git_compare_verify_')
    
    try:
        score = 0
        max_score = 100
        feedback_parts = []
        
        # === SETUP VERIFICATION (20 points) ===
        # Verify Git branches exist and file differs
        setup_score = 0
        
        branches_file = os.path.join(temp_dir, "git_branches.txt")
        try:
            copy_from_env("/tmp/git_branches.txt", branches_file)
            if os.path.exists(branches_file):
                branches_content = read_file_content(branches_file)
                has_main = 'main' in branches_content
                has_feature = 'feature-auth' in branches_content
                
                if has_main and has_feature:
                    setup_score += 10
                    feedback_parts.append("✅ Both branches exist (main, feature-auth)")
                else:
                    feedback_parts.append(f"⚠️ Missing branches (main: {has_main}, feature-auth: {has_feature})")
        except Exception as e:
            logger.warning(f"Could not verify branches: {e}")
            feedback_parts.append("⚠️ Could not verify branch setup")
        
        # Verify file differs between branches
        diff_file = os.path.join(temp_dir, "git_diff_database.txt")
        try:
            copy_from_env("/tmp/git_diff_database.txt", diff_file)
            if os.path.exists(diff_file):
                diff_content = read_file_content(diff_file)
                if diff_content.strip() and len(diff_content) > 50:
                    setup_score += 10
                    feedback_parts.append("✅ File config/database.py differs between branches")
                else:
                    feedback_parts.append("⚠️ No differences found in database.py")
        except Exception as e:
            logger.warning(f"Could not verify file diff: {e}")
        
        score += setup_score
        
        # === WINDOW STATE VERIFICATION (40 points) ===
        window_score = 0
        
        # Check window titles for diff-related keywords
        window_list_file = os.path.join(temp_dir, "window_list.txt")
        active_window_file = os.path.join(temp_dir, "active_window_title.txt")
        
        window_titles = []
        try:
            copy_from_env("/tmp/window_list.txt", window_list_file)
            if os.path.exists(window_list_file):
                window_content = read_file_content(window_list_file)
                window_titles.extend(window_content.lower().split('\n'))
        except:
            pass
        
        try:
            copy_from_env("/tmp/active_window_title.txt", active_window_file)
            if os.path.exists(active_window_file):
                active_title = read_file_content(active_window_file).lower()
                window_titles.append(active_title)
        except:
            pass
        
        # Look for diff-related indicators in window titles
        diff_indicators = ['database.py', 'diff', 'compare', 'main', 'feature', 'working tree']
        found_indicators = []
        
        for title in window_titles:
            if not title.strip():
                continue
            for indicator in diff_indicators:
                if indicator in title:
                    found_indicators.append(indicator)
        
        if 'database.py' in found_indicators:
            window_score += 20
            feedback_parts.append("✅ database.py found in window title")
        else:
            feedback_parts.append("❌ database.py not found in window titles")
        
        # Check for diff/compare indicators
        diff_keywords = ['diff', 'compare', 'working tree']
        has_diff_keyword = any(kw in found_indicators for kw in diff_keywords)
        if has_diff_keyword:
            window_score += 10
            feedback_parts.append(f"✅ Diff-related keyword found: {[kw for kw in diff_keywords if kw in found_indicators]}")
        
        # Check for branch names in window titles
        branch_keywords = ['main', 'feature']
        has_branch_keyword = any(kw in found_indicators for kw in branch_keywords)
        if has_branch_keyword:
            window_score += 10
            feedback_parts.append("✅ Branch names found in window title")
        
        score += window_score
        
        # === SOURCE CONTROL ACCESS (20 points) ===
        # Check if Source Control related windows/views are present
        source_control_score = 0
        
        # Check window list for Source Control indicators
        all_window_text = ' '.join(window_titles).lower()
        if 'source control' in all_window_text or 'scm' in all_window_text:
            source_control_score += 10
            feedback_parts.append("✅ Source Control access detected")
        
        # Check for Git-related activity
        if 'git' in all_window_text:
            source_control_score += 10
            feedback_parts.append("✅ Git-related activity detected")
        
        score += source_control_score
        
        # === FILE ACCESS VERIFICATION (20 points) ===
        file_access_score = 0
        
        # Check if database.py files from both branches were accessed
        main_file = os.path.join(temp_dir, "database_main.py")
        feature_file = os.path.join(temp_dir, "database_feature.py")
        
        try:
            copy_from_env("/tmp/database_main.py", main_file)
            if os.path.exists(main_file) and os.path.getsize(main_file) > 0:
                main_content = read_file_content(main_file)
                if 'DATABASE_HOST' in main_content and 'password123' in main_content:
                    file_access_score += 10
                    feedback_parts.append("✅ Main branch file content retrieved")
        except:
            pass
        
        try:
            copy_from_env("/tmp/database_feature.py", feature_file)
            if os.path.exists(feature_file) and os.path.getsize(feature_file) > 0:
                feature_content = read_file_content(feature_file)
                if 'os.getenv' in feature_content and 'POOL_SIZE' in feature_content:
                    file_access_score += 10
                    feedback_parts.append("✅ Feature branch file content retrieved")
        except:
            pass
        
        score += file_access_score
        
        # === FINAL SCORING ===
        score = min(score, max_score)
        passed = score >= 70
        
        # Add summary feedback
        if score >= 90:
            feedback_parts.insert(0, "🎉 Excellent: Strong evidence of branch comparison")
        elif score >= 70:
            feedback_parts.insert(0, "✅ Good: Branch comparison activity detected")
        elif score >= 50:
            feedback_parts.insert(0, "⚠️ Partial: Some Git activity but comparison unclear")
        else:
            feedback_parts.insert(0, "❌ Insufficient evidence of branch comparison")
        
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
        cleanup_verification_temp(temp_dir)
