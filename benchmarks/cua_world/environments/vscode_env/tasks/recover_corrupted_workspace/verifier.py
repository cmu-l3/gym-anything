#!/usr/bin/env python3
"""
Verifier for Workspace Recovery task
"""

import sys
import os
import json
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    parse_vscode_settings,
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_valid_json(content):
    """Check if string is valid JSON"""
    try:
        json.loads(content)
        return True
    except json.JSONDecodeError:
        return False


def check_settings_valid(copy_from_env):
    """Check if settings files are valid JSON"""
    user_valid = False
    workspace_valid = False
    feedback = []
    
    # Check user settings
    temp_user = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/user_settings.json", temp_user.name)
        if os.path.exists(temp_user.name) and os.path.getsize(temp_user.name) > 0:
            content = read_file_content(temp_user.name)
            if is_valid_json(content):
                user_valid = True
                feedback.append("✅ User settings.json is valid JSON")
            else:
                feedback.append("❌ User settings.json has JSON syntax errors")
        else:
            feedback.append("⚠️  User settings.json not found")
    except Exception as e:
        feedback.append(f"⚠️  Could not check user settings: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_user.name):
            os.unlink(temp_user.name)
    
    # Check workspace settings
    temp_workspace = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/workspace_settings.json", temp_workspace.name)
        if os.path.exists(temp_workspace.name) and os.path.getsize(temp_workspace.name) > 0:
            content = read_file_content(temp_workspace.name)
            if is_valid_json(content):
                workspace_valid = True
                feedback.append("✅ Workspace settings.json is valid JSON")
            else:
                feedback.append("❌ Workspace settings.json has JSON syntax errors")
        else:
            feedback.append("⚠️  Workspace settings.json not found")
    except Exception as e:
        feedback.append(f"⚠️  Could not check workspace settings: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_workspace.name):
            os.unlink(temp_workspace.name)
    
    # At least one must be valid
    return user_valid or workspace_valid, feedback


def check_extensions_loaded(copy_from_env):
    """Check if Python extension loaded successfully"""
    temp_ext = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    feedback = []
    python_loaded = False
    
    try:
        copy_from_env("/tmp/extensions_list.txt", temp_ext.name)
        if os.path.exists(temp_ext.name):
            content = read_file_content(temp_ext.name).lower()
            lines = [line.strip() for line in content.split('\n') if line.strip()]
            
            # Check for Python extension
            for line in lines:
                if 'ms-python.python' in line or 'python' in line:
                    python_loaded = True
                    feedback.append(f"✅ Python extension found: {line[:50]}")
                    break
            
            if not python_loaded:
                feedback.append("❌ Python extension not found in extensions list")
                feedback.append(f"  Installed: {', '.join(lines[:5])}")
        else:
            feedback.append("⚠️  Extensions list not found")
    except Exception as e:
        feedback.append(f"⚠️  Could not check extensions: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_ext.name):
            os.unlink(temp_ext.name)
    
    return python_loaded, feedback


def check_no_errors_in_logs(copy_from_env):
    """Check if there are critical errors in logs"""
    feedback = []
    no_critical_errors = True
    
    # Check extension host log
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
    try:
        copy_from_env("/tmp/exthost.log", temp_log.name)
        if os.path.exists(temp_log.name) and os.path.getsize(temp_log.name) > 10:
            content = read_file_content(temp_log.name).lower()
            
            # Look for critical errors
            critical_patterns = ['failed to activate', 'cannot parse', 'syntax error', 'corrupted']
            error_count = 0
            for pattern in critical_patterns:
                if pattern in content:
                    error_count += 1
            
            if error_count > 2:  # Some errors might be historical
                no_critical_errors = False
                feedback.append(f"⚠️  Found {error_count} critical error patterns in logs")
            else:
                feedback.append("✅ No major errors in extension logs")
        else:
            # No log might mean clean state or unavailable
            feedback.append("ℹ️  Extension log not available (might be clean)")
    except Exception as e:
        feedback.append(f"ℹ️  Could not check logs: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_log.name):
            os.unlink(temp_log.name)
    
    return no_critical_errors, feedback


def check_language_server_active(copy_from_env):
    """Check if language server processes are running"""
    feedback = []
    server_active = False
    
    temp_proc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/python_processes.txt", temp_proc.name)
        if os.path.exists(temp_proc.name) and os.path.getsize(temp_proc.name) > 0:
            content = read_file_content(temp_proc.name)
            lines = content.strip().split('\n')
            
            # Look for language server processes
            for line in lines:
                if 'pylance' in line.lower() or 'jedi' in line.lower() or 'python-language-server' in line.lower():
                    server_active = True
                    feedback.append("✅ Language server process detected")
                    break
            
            if not server_active:
                # Check for any Python-related processes
                if len(lines) > 0 and lines[0]:
                    feedback.append("⚠️  Language server process not clearly identified")
                else:
                    feedback.append("⚠️  No Python language server processes found")
        else:
            feedback.append("⚠️  Process list not available")
    except Exception as e:
        feedback.append(f"ℹ️  Could not check processes: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_proc.name):
            os.unlink(temp_proc.name)
    
    return server_active, feedback


def check_recovery_documented(copy_from_env):
    """Check if recovery process was documented"""
    feedback = []
    documented = False
    quality_score = 0
    
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.md')
    try:
        copy_from_env("/tmp/recovery_log.md", temp_log.name)
        if os.path.exists(temp_log.name) and os.path.getsize(temp_log.name) > 10:
            content = read_file_content(temp_log.name)
            
            documented = True
            feedback.append("✅ RECOVERY_LOG.md found")
            
            # Check documentation quality
            content_lower = content.lower()
            
            # Check for key elements
            quality_checks = {
                'problem description': any(word in content_lower for word in ['broken', 'error', 'corrupt', 'failed', 'issue']),
                'diagnostic steps': any(word in content_lower for word in ['check', 'log', 'inspect', 'found', 'diagnose']),
                'solution': any(word in content_lower for word in ['fix', 'repair', 'solve', 'resolve', 'correct']),
                'settings': 'setting' in content_lower or 'json' in content_lower,
            }
            
            quality_score = sum(quality_checks.values())
            
            if quality_score >= 3:
                feedback.append(f"✅ Documentation quality: {quality_score}/4 elements present")
            elif quality_score >= 2:
                feedback.append(f"⚠️  Documentation quality: {quality_score}/4 elements present")
            else:
                feedback.append(f"❌ Documentation quality: {quality_score}/4 elements present (too brief)")
        else:
            feedback.append("❌ RECOVERY_LOG.md not found or empty")
    except Exception as e:
        feedback.append(f"❌ Could not check recovery log: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_log.name):
            os.unlink(temp_log.name)
    
    return documented, quality_score, feedback


def check_workspace_preserved(copy_from_env):
    """Check that original workspace files are preserved"""
    feedback = []
    preserved = False
    
    temp_files = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/workspace_files.txt", temp_files.name)
        if os.path.exists(temp_files.name):
            content = read_file_content(temp_files.name)
            
            # Check for key files
            required_files = ['main.py', 'helper.py', 'requirements.txt']
            found_count = sum(1 for f in required_files if f in content)
            
            if found_count == len(required_files):
                preserved = True
                feedback.append("✅ All workspace files preserved")
            elif found_count > 0:
                feedback.append(f"⚠️  Some workspace files preserved ({found_count}/{len(required_files)})")
            else:
                feedback.append("❌ Workspace files not found")
        else:
            feedback.append("⚠️  Could not verify workspace preservation")
    except Exception as e:
        feedback.append(f"ℹ️  Workspace check: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_files.name):
            os.unlink(temp_files.name)
    
    return preserved, feedback


def verify_workspace_recovery(traj, env_info, task_info):
    """
    Verify that workspace was successfully recovered from corruption.
    
    Scoring breakdown:
    - Settings valid (25 points): At least one settings file fixed
    - Extensions working (25 points): Python extension loads successfully
    - No active errors (15 points): No critical errors in logs
    - Language server active (15 points): Python language server running
    - Recovery documented (10 points): RECOVERY_LOG.md exists with quality content
    - Workspace preserved (10 points): Original files intact
    
    Pass threshold: 75%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    try:
        score = 0
        max_score = 100
        all_feedback = []
        
        # Criterion 1: Settings valid (25 points)
        settings_valid, settings_feedback = check_settings_valid(copy_from_env)
        if settings_valid:
            score += 25
            all_feedback.extend(settings_feedback)
        else:
            score += 0
            all_feedback.extend(settings_feedback)
        
        # Criterion 2: Extensions working (25 points)
        extensions_ok, ext_feedback = check_extensions_loaded(copy_from_env)
        if extensions_ok:
            score += 25
            all_feedback.extend(ext_feedback)
        else:
            score += 0
            all_feedback.extend(ext_feedback)
        
        # Criterion 3: No active errors (15 points)
        no_errors, error_feedback = check_no_errors_in_logs(copy_from_env)
        if no_errors:
            score += 15
        else:
            score += 8  # Partial credit
        all_feedback.extend(error_feedback)
        
        # Criterion 4: Language server active (15 points)
        server_active, server_feedback = check_language_server_active(copy_from_env)
        if server_active:
            score += 15
        else:
            score += 5  # Partial credit if just not detected
        all_feedback.extend(server_feedback)
        
        # Criterion 5: Recovery documented (10 points)
        documented, doc_quality, doc_feedback = check_recovery_documented(copy_from_env)
        if documented:
            # Score based on documentation quality
            doc_score = min(10, 4 + doc_quality * 2)
            score += doc_score
        all_feedback.extend(doc_feedback)
        
        # Criterion 6: Workspace preserved (10 points)
        workspace_ok, workspace_feedback = check_workspace_preserved(copy_from_env)
        if workspace_ok:
            score += 10
        else:
            score += 5  # Partial credit
        all_feedback.extend(workspace_feedback)
        
        # Determine pass/fail
        passed = score >= 75
        
        # Create summary
        summary = f"Recovery Score: {score}/{max_score} | "
        if passed:
            summary += "✅ WORKSPACE RECOVERED"
        else:
            summary += "❌ RECOVERY INCOMPLETE"
        
        feedback = summary + " | " + " | ".join(all_feedback)
        
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
