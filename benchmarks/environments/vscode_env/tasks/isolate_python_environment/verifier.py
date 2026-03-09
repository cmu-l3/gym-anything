#!/usr/bin/env python3
"""
Verifier for Isolate Python Environment task
"""

import sys
import os
import logging
import tempfile
import json
import re
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_python_environment(traj, env_info, task_info):
    """
    Verify that Python virtual environment was set up correctly.
    
    Checks:
    1. Virtual environment exists at /home/ga/workspace/sales_analysis/venv/
    2. Required packages installed with correct versions (pandas, numpy, matplotlib)
    3. VSCode workspace settings point to venv interpreter
    4. Imports work from venv Python (functional test)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='venv_verify_')
    
    try:
        criteria_passed = 0
        feedback_parts = []
        
        # Copy exported data files
        venv_status_path = os.path.join(temp_dir, "venv_status.txt")
        venv_packages_path = os.path.join(temp_dir, "venv_packages.txt")
        venv_versions_path = os.path.join(temp_dir, "venv_versions.txt")
        venv_import_test_path = os.path.join(temp_dir, "venv_import_test.txt")
        vscode_settings_path = os.path.join(temp_dir, "vscode_workspace_settings.json")
        site_packages_path = os.path.join(temp_dir, "site_packages_contents.txt")
        
        # Copy all files
        files_to_copy = {
            "/tmp/venv_status.txt": venv_status_path,
            "/tmp/venv_packages.txt": venv_packages_path,
            "/tmp/venv_versions.txt": venv_versions_path,
            "/tmp/venv_import_test.txt": venv_import_test_path,
            "/tmp/vscode_workspace_settings.json": vscode_settings_path,
            "/tmp/site_packages_contents.txt": site_packages_path,
        }
        
        for container_path, local_path in files_to_copy.items():
            try:
                copy_from_env(container_path, local_path)
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
                # Create empty file so we can continue
                open(local_path, 'w').close()
        
        # ===== CRITERION 1: Virtual environment exists =====
        venv_exists = False
        if os.path.exists(venv_status_path):
            with open(venv_status_path, 'r') as f:
                content = f.read().strip()
                if "exists" in content.lower():
                    venv_exists = True
                    criteria_passed += 1
                    feedback_parts.append("✅ Virtual environment created at /home/ga/workspace/sales_analysis/venv/")
                else:
                    feedback_parts.append("❌ Virtual environment not found")
        else:
            feedback_parts.append("❌ Could not check virtual environment status")
        
        # ===== CRITERION 2: Required packages installed =====
        packages_correct = False
        if venv_exists:
            required_packages = {'pandas', 'numpy', 'matplotlib'}
            found_packages = set()
            
            # Method 1: Check pip list output
            if os.path.exists(venv_packages_path) and os.path.getsize(venv_packages_path) > 0:
                with open(venv_packages_path, 'r') as f:
                    packages_content = f.read().lower()
                    for pkg in required_packages:
                        if pkg in packages_content:
                            found_packages.add(pkg)
            
            # Method 2: Check site-packages directory listing
            if os.path.exists(site_packages_path) and os.path.getsize(site_packages_path) > 0:
                with open(site_packages_path, 'r') as f:
                    site_content = f.read().lower()
                    for pkg in required_packages:
                        if pkg in site_content:
                            found_packages.add(pkg)
            
            if found_packages == required_packages:
                packages_correct = True
                criteria_passed += 1
                
                # Try to get version info
                version_info = ""
                if os.path.exists(venv_versions_path) and os.path.getsize(venv_versions_path) > 0:
                    with open(venv_versions_path, 'r') as f:
                        version_info = f.read().strip()
                        if version_info:
                            version_info = f" ({version_info.replace(chr(10), ', ')})"
                
                feedback_parts.append(f"✅ All required packages installed in venv{version_info}")
            else:
                missing = required_packages - found_packages
                if missing:
                    feedback_parts.append(f"❌ Missing packages in venv: {', '.join(missing)}")
                else:
                    feedback_parts.append("❌ Could not verify package installation")
        else:
            feedback_parts.append("⚠️ Skipping package check (no venv)")
        
        # ===== CRITERION 3: VSCode settings point to venv =====
        settings_correct = False
        if os.path.exists(vscode_settings_path) and os.path.getsize(vscode_settings_path) > 0:
            try:
                with open(vscode_settings_path, 'r') as f:
                    settings = json.load(f)
                
                # Check for interpreter path setting
                interpreter_path = (
                    settings.get('python.defaultInterpreterPath') or 
                    settings.get('python.pythonPath') or
                    ""
                )
                
                if interpreter_path:
                    # Check if it points to venv (allow various formats)
                    if any(pattern in interpreter_path.lower() for pattern in [
                        'venv/bin/python',
                        'venv\\bin\\python',
                        'venv/scripts/python',
                        'sales_analysis/venv'
                    ]):
                        settings_correct = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ VSCode interpreter configured: {interpreter_path}")
                    else:
                        feedback_parts.append(f"❌ VSCode interpreter not pointing to venv: {interpreter_path}")
                else:
                    feedback_parts.append("❌ Python interpreter not configured in VSCode workspace settings")
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Invalid JSON in VSCode settings: {e}")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading VSCode settings: {e}")
        else:
            feedback_parts.append("❌ VSCode workspace settings.json not found or empty")
        
        # ===== CRITERION 4: Functional test - imports work =====
        imports_work = False
        if os.path.exists(venv_import_test_path) and os.path.getsize(venv_import_test_path) > 0:
            with open(venv_import_test_path, 'r') as f:
                import_result = f.read().strip()
                if 'IMPORTS_SUCCESS' in import_result:
                    imports_work = True
                    criteria_passed += 1
                    feedback_parts.append("✅ All imports successful from venv Python")
                elif 'IMPORTS_FAILED' in import_result:
                    feedback_parts.append("❌ Import test failed (packages may not be installed correctly)")
                elif 'NO_VENV' in import_result:
                    feedback_parts.append("⚠️ Import test skipped (no venv)")
                else:
                    # Check if there's error info in the output
                    if 'error' in import_result.lower() or 'exception' in import_result.lower():
                        error_msg = import_result[:100]
                        feedback_parts.append(f"❌ Import error: {error_msg}")
                    else:
                        feedback_parts.append("⚠️ Import test result unclear")
        else:
            feedback_parts.append("⚠️ Import test results not available")
        
        # Calculate score
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "criteria": {
                "venv_exists": venv_exists,
                "packages_installed": packages_correct,
                "vscode_configured": settings_correct,
                "imports_work": imports_work
            }
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
