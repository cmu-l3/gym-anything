#!/usr/bin/env python3
"""
Verifier for Tackle Technical Debt task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_technical_debt(traj, env_info, task_info):
    """
    Verify that technical debt items were properly addressed.
    
    Checks:
    1. Deprecated /v1/users endpoint removed (35 points)
    2. Database error handling improved (35 points)
    3. Timezone handling fixed (20 points)
    4. CHANGELOG.md created (10 points)
    
    Returns:
        dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='tech_debt_verify_')

    try:
        workspace = "/home/ga/workspace/webservice"
        
        feedback_parts = []
        score = 0
        
        # Copy all relevant files
        users_py_local = os.path.join(temp_dir, "users.py")
        database_py_local = os.path.join(temp_dir, "database.py")
        utils_py_local = os.path.join(temp_dir, "utils.py")
        changelog_local = os.path.join(temp_dir, "CHANGELOG.md")
        
        # Try copying from /tmp first (export_result.sh puts them there), fallback to workspace
        try:
            copy_from_env("/tmp/users.py", users_py_local)
        except:
            try:
                copy_from_env(f"{workspace}/routes/users.py", users_py_local)
            except Exception as e:
                logger.error(f"Failed to copy users.py: {e}")
                return {"passed": False, "score": 0, "feedback": "❌ Could not access routes/users.py"}
        
        try:
            copy_from_env("/tmp/database.py", database_py_local)
        except:
            try:
                copy_from_env(f"{workspace}/database.py", database_py_local)
            except Exception as e:
                logger.error(f"Failed to copy database.py: {e}")
                return {"passed": False, "score": 0, "feedback": "❌ Could not access database.py"}
        
        try:
            copy_from_env("/tmp/utils.py", utils_py_local)
        except:
            try:
                copy_from_env(f"{workspace}/utils.py", utils_py_local)
            except Exception as e:
                logger.error(f"Failed to copy utils.py: {e}")
                return {"passed": False, "score": 0, "feedback": "❌ Could not access utils.py"}
        
        try:
            copy_from_env("/tmp/CHANGELOG.md", changelog_local)
        except:
            try:
                copy_from_env(f"{workspace}/CHANGELOG.md", changelog_local)
            except:
                pass  # CHANGELOG is optional, checked later
        
        # Check 1: Deprecated endpoint removed (35 points)
        if not os.path.exists(users_py_local):
            return {"passed": False, "score": 0, "feedback": "❌ routes/users.py not found"}
        
        users_content = read_file_content(users_py_local)
        
        # Check if v1 endpoint is removed
        has_v1_function = "def get_users_v1" in users_content
        has_v1_route = "/v1/users" in users_content
        v1_removed = not has_v1_function and not has_v1_route
        
        # Check that v2 endpoint still exists
        has_v2_function = "def get_users_v2" in users_content
        
        if v1_removed and has_v2_function:
            score += 35
            feedback_parts.append("✅ Deprecated /v1/users endpoint removed (35 pts)")
        elif v1_removed and not has_v2_function:
            score += 10
            feedback_parts.append("⚠️ v1 endpoint removed but v2 also missing (10 pts)")
        elif not v1_removed:
            feedback_parts.append("❌ Deprecated /v1/users endpoint still exists (0 pts)")
        
        # Check 2: Database error handling improved (35 points)
        if not os.path.exists(database_py_local):
            feedback_parts.append("❌ database.py not found (0 pts)")
        else:
            database_content = read_file_content(database_py_local)
            
            # Check for try-except blocks
            has_try_except = "try:" in database_content and "except" in database_content
            has_execute_query = "def execute_query" in database_content
            
            # Check if FIXME comment is addressed (removed or updated)
            fixme_unaddressed = "FIXME: This has no error handling" in database_content
            
            # More lenient check: just needs try-except and FIXME updated
            if has_try_except and has_execute_query:
                if not fixme_unaddressed:
                    score += 35
                    feedback_parts.append("✅ Database error handling improved with try-except (35 pts)")
                else:
                    score += 25
                    feedback_parts.append("⚠️ Error handling added but FIXME comment not removed (25 pts)")
            else:
                if not has_try_except:
                    feedback_parts.append("❌ No try-except blocks added to database.py (0 pts)")
                else:
                    feedback_parts.append("❌ execute_query function missing or malformed (0 pts)")
        
        # Check 3: Timezone handling fixed (20 points)
        if not os.path.exists(utils_py_local):
            feedback_parts.append("❌ utils.py not found (0 pts)")
        else:
            utils_content = read_file_content(utils_py_local)
            
            # Check for proper timezone library usage
            uses_timezone_lib = (
                "timezone.utc" in utils_content or 
                "datetime.timezone.utc" in utils_content or
                "pytz" in utils_content or
                "tzinfo" in utils_content
            )
            
            # Check HACK comment is addressed
            hack_comment_present = "HACK: This is a terrible way" in utils_content
            
            # Check manual 'Z' appending is removed
            manual_z_append = ("+ 'Z'" in utils_content or '+ "Z"' in utils_content)
            
            # Function still exists
            has_function = "def get_current_utc_timestamp" in utils_content
            
            if uses_timezone_lib and not hack_comment_present and not manual_z_append and has_function:
                score += 20
                feedback_parts.append("✅ Timezone handling replaced with proper library (20 pts)")
            elif uses_timezone_lib and has_function:
                if hack_comment_present:
                    score += 10
                    feedback_parts.append("⚠️ Timezone lib used but HACK comment not removed (10 pts)")
                elif manual_z_append:
                    score += 10
                    feedback_parts.append("⚠️ Timezone lib used but still manually appending 'Z' (10 pts)")
                else:
                    score += 15
                    feedback_parts.append("⚠️ Timezone handling improved but not perfect (15 pts)")
            else:
                if not has_function:
                    feedback_parts.append("❌ get_current_utc_timestamp function missing (0 pts)")
                elif not uses_timezone_lib:
                    feedback_parts.append("❌ No proper timezone library usage detected (0 pts)")
        
        # Check 4: CHANGELOG.md created (10 points)
        if os.path.exists(changelog_local) and os.path.getsize(changelog_local) > 0:
            changelog_content = read_file_content(changelog_local)
            
            # Check if it documents the changes
            documents_endpoint = (
                "endpoint" in changelog_content.lower() or 
                "deprecated" in changelog_content.lower() or
                "v1" in changelog_content.lower()
            )
            documents_database = (
                "database" in changelog_content.lower() or 
                "error" in changelog_content.lower() or
                "exception" in changelog_content.lower()
            )
            documents_timezone = (
                "timezone" in changelog_content.lower() or 
                "datetime" in changelog_content.lower() or
                "utc" in changelog_content.lower()
            )
            
            documented_count = sum([documents_endpoint, documents_database, documents_timezone])
            
            if documented_count >= 3:
                score += 10
                feedback_parts.append("✅ CHANGELOG.md created with all changes documented (10 pts)")
            elif documented_count >= 2:
                score += 7
                feedback_parts.append("⚠️ CHANGELOG.md exists but missing some documentation (7 pts)")
            elif documented_count >= 1:
                score += 4
                feedback_parts.append("⚠️ CHANGELOG.md exists with minimal documentation (4 pts)")
            else:
                score += 2
                feedback_parts.append("⚠️ CHANGELOG.md exists but doesn't document changes (2 pts)")
        else:
            feedback_parts.append("❌ CHANGELOG.md not created or empty (0 pts)")
        
        # Calculate pass/fail
        passed = score >= 80
        
        # Build feedback message
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Total Score: {score}/100"
        
        if passed:
            feedback += "\n\n🎉 Task completed successfully! Technical debt has been addressed."
        else:
            feedback += "\n\n❌ Task incomplete. Need at least 80 points to pass. Please address the remaining technical debt items."
        
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
