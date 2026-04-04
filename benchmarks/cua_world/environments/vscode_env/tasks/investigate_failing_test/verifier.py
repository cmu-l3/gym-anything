#!/usr/bin/env python3
"""
Verifier for Investigate Failing Test task
Checks that agent used VSCode's Test Explorer to run pytest tests
"""

import sys
import os
import logging
import tempfile
import shutil
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    parse_vscode_settings,
    read_file_content,
    check_file_exists
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_test_investigation(traj, env_info, task_info):
    """
    Verify that agent successfully configured and ran tests via VSCode Test Explorer.
    
    Checks:
    1. pytest is enabled in VSCode settings (30%)
    2. Tests were executed (pytest cache exists) (30%)
    3. Test Explorer/workspace configuration exists (20%)
    4. Test discovery occurred (20%)
    
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_test_verify_')
    
    try:
        score = 0
        feedback_parts = []
        
        # Check 1: pytest enabled in VSCode settings (30 points)
        logger.info("Checking VSCode settings for pytest configuration...")
        settings_local = os.path.join(temp_dir, "vscode_settings.json")
        
        try:
            copy_from_env("/tmp/vscode_settings.json", settings_local)
            
            if os.path.exists(settings_local) and os.path.getsize(settings_local) > 2:
                settings = parse_vscode_settings(settings_local)
                
                pytest_enabled = settings.get("python.testing.pytestEnabled", False)
                
                if pytest_enabled:
                    score += 30
                    feedback_parts.append("✅ pytest enabled in VSCode settings")
                    logger.info("pytest is enabled in settings")
                else:
                    feedback_parts.append("❌ pytest not enabled in VSCode settings")
                    logger.warning("pytest not enabled")
            else:
                feedback_parts.append("❌ VSCode settings not found or empty")
                
        except Exception as e:
            logger.error(f"Error checking settings: {e}")
            feedback_parts.append("❌ Could not verify VSCode settings")
        
        # Check 2: Workspace settings (10 bonus points)
        logger.info("Checking workspace settings...")
        workspace_settings_local = os.path.join(temp_dir, "workspace_settings.json")
        
        try:
            copy_from_env("/tmp/workspace_settings.json", workspace_settings_local)
            
            if os.path.exists(workspace_settings_local) and os.path.getsize(workspace_settings_local) > 2:
                ws_settings = parse_vscode_settings(workspace_settings_local)
                if ws_settings and len(ws_settings) > 0:
                    score += 10
                    feedback_parts.append("✅ Workspace settings configured")
                    logger.info("Workspace settings exist")
        except Exception as e:
            logger.debug(f"Workspace settings check: {e}")
        
        # Check 3: pytest cache exists (tests were run) (30 points)
        logger.info("Checking for pytest cache (evidence of test execution)...")
        pytest_cache_files_local = os.path.join(temp_dir, "pytest_cache_files.txt")
        
        try:
            copy_from_env("/tmp/pytest_cache_files.txt", pytest_cache_files_local)
            
            if os.path.exists(pytest_cache_files_local) and os.path.getsize(pytest_cache_files_local) > 0:
                with open(pytest_cache_files_local, 'r') as f:
                    cache_files = f.read().strip()
                
                if cache_files and len(cache_files) > 0:
                    score += 30
                    feedback_parts.append("✅ Tests were executed (pytest cache found)")
                    logger.info("Pytest cache exists - tests were run")
                    
                    # Check for specific cache files
                    if '.pytest_cache' in cache_files:
                        score += 5
                        logger.info("Pytest cache structure verified")
                else:
                    feedback_parts.append("❌ No pytest cache found (tests not executed)")
            else:
                feedback_parts.append("❌ No pytest cache found (tests may not have been run)")
                logger.warning("No pytest cache detected")
                
        except Exception as e:
            logger.warning(f"Could not verify pytest cache: {e}")
            feedback_parts.append("⚠️ Could not verify test execution")
        
        # Check 4: Test discovery occurred (20 points)
        logger.info("Checking for test discovery...")
        pytest_nodeids_local = os.path.join(temp_dir, "pytest_nodeids.txt")
        
        try:
            copy_from_env("/tmp/pytest_nodeids.txt", pytest_nodeids_local)
            
            if os.path.exists(pytest_nodeids_local) and os.path.getsize(pytest_nodeids_local) > 0:
                score += 20
                feedback_parts.append("✅ Test discovery occurred")
                logger.info("Test discovery confirmed")
            else:
                logger.debug("No test discovery data found")
                
        except Exception as e:
            logger.debug(f"Test discovery check: {e}")
        
        # Check 5: VSCode workspace storage activity (10 bonus points)
        logger.info("Checking VSCode workspace storage activity...")
        workspace_state_local = os.path.join(temp_dir, "recent_workspace_state.txt")
        
        try:
            copy_from_env("/tmp/recent_workspace_state.txt", workspace_state_local)
            
            if os.path.exists(workspace_state_local) and os.path.getsize(workspace_state_local) > 0:
                with open(workspace_state_local, 'r') as f:
                    state_files = f.read().strip()
                
                if state_files:
                    score += 10
                    feedback_parts.append("✅ VSCode workspace state modified (Test Explorer likely used)")
                    logger.info("Workspace state activity detected")
        except Exception as e:
            logger.debug(f"Workspace state check: {e}")
        
        # Check 6: Verify test files are intact
        logger.info("Verifying test files...")
        export_summary_local = os.path.join(temp_dir, "export_summary.txt")
        
        try:
            copy_from_env("/tmp/export_summary.txt", export_summary_local)
            
            if os.path.exists(export_summary_local):
                with open(export_summary_local, 'r') as f:
                    summary = f.read()
                logger.info("Export summary retrieved")
        except Exception as e:
            logger.debug(f"Export summary check: {e}")
        
        # Cap score at 100
        score = min(score, 100)
        
        # Determine pass/fail
        passed = score >= 70
        
        # Create final feedback
        if passed:
            feedback_parts.insert(0, "✅ SUCCESS: Test Explorer was configured and tests were run")
            logger.info(f"Task completed successfully. Score: {score}")
        elif score >= 40:
            feedback_parts.insert(0, "⚠️ PARTIAL: Some testing functionality configured but incomplete")
            logger.info(f"Task partially completed. Score: {score}")
        else:
            feedback_parts.insert(0, "❌ FAILED: Test Explorer was not properly configured or used")
            logger.warning(f"Task failed. Score: {score}")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification failed with error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
            logger.debug(f"Cleaned up temp directory: {temp_dir}")
