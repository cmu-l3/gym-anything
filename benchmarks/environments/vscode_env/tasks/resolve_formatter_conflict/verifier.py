#!/usr/bin/env python3
"""
Verifier for Resolve Formatter Conflict task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_formatter_integration(traj, env_info, task_info):
    """
    Verify that ESLint and Prettier are configured to work together.
    
    Checks:
    1. eslint-config-prettier is installed (in package.json devDependencies)
    2. .eslintrc.json extends array includes "prettier"
    3. Both files are valid JSON
    
    All criteria must pass for task success.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='formatter_conflict_verify_')
    
    try:
        workspace_base = "/home/ga/workspace/webapp"
        package_json_path = f"{workspace_base}/package.json"
        eslintrc_path = f"{workspace_base}/.eslintrc.json"
        
        local_package = os.path.join(temp_dir, "package.json")
        local_eslintrc = os.path.join(temp_dir, ".eslintrc.json")
        
        criteria_passed = 0
        total_criteria = 3
        feedback_parts = []
        
        # ===== Criterion 1: Check package.json for eslint-config-prettier =====
        package_json_valid = False
        eslint_config_prettier_installed = False
        
        try:
            copy_from_env(package_json_path, local_package)
            
            if not os.path.exists(local_package) or os.path.getsize(local_package) == 0:
                feedback_parts.append("❌ package.json not found or empty")
            else:
                with open(local_package, 'r', encoding='utf-8') as f:
                    package_data = json.load(f)
                package_json_valid = True
                
                # Check devDependencies for eslint-config-prettier
                dev_deps = package_data.get("devDependencies", {})
                
                if "eslint-config-prettier" in dev_deps:
                    eslint_config_prettier_installed = True
                    criteria_passed += 1
                    version = dev_deps["eslint-config-prettier"]
                    feedback_parts.append(f"✅ eslint-config-prettier installed (version: {version})")
                else:
                    feedback_parts.append(
                        "❌ eslint-config-prettier NOT found in package.json devDependencies. "
                        "Run: npm install --save-dev eslint-config-prettier"
                    )
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ package.json is invalid JSON: {str(e)[:100]}")
        except FileNotFoundError:
            feedback_parts.append("❌ package.json not found at expected location")
        except Exception as e:
            feedback_parts.append(f"❌ Error reading package.json: {str(e)[:100]}")
        
        # ===== Criterion 2: Check .eslintrc.json extends array =====
        eslintrc_valid = False
        prettier_in_extends = False
        
        try:
            copy_from_env(eslintrc_path, local_eslintrc)
            
            if not os.path.exists(local_eslintrc) or os.path.getsize(local_eslintrc) == 0:
                feedback_parts.append("❌ .eslintrc.json not found or empty")
            else:
                with open(local_eslintrc, 'r', encoding='utf-8') as f:
                    eslint_data = json.load(f)
                eslintrc_valid = True
                
                # Check extends field
                extends = eslint_data.get("extends", [])
                
                # extends can be a string or array
                if isinstance(extends, str):
                    extends = [extends]
                elif not isinstance(extends, list):
                    feedback_parts.append(f"❌ .eslintrc.json 'extends' field has invalid type: {type(extends)}")
                    extends = []
                
                # Check if "prettier" is in extends
                if "prettier" in extends:
                    prettier_in_extends = True
                    criteria_passed += 1
                    
                    # Extra validation: prettier should ideally be last
                    if extends[-1] == "prettier":
                        feedback_parts.append("✅ 'prettier' correctly added to extends array (as last element)")
                    else:
                        feedback_parts.append(
                            "✅ 'prettier' found in extends array (note: it should be last to properly override rules)"
                        )
                else:
                    feedback_parts.append(
                        "❌ 'prettier' NOT found in .eslintrc.json extends array. "
                        "Add it to disable conflicting ESLint formatting rules."
                    )
                    if extends:
                        feedback_parts.append(f"   Current extends: {extends}")
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ .eslintrc.json is invalid JSON: {str(e)[:100]}")
        except FileNotFoundError:
            feedback_parts.append("❌ .eslintrc.json not found at expected location")
        except Exception as e:
            feedback_parts.append(f"❌ Error reading .eslintrc.json: {str(e)[:100]}")
        
        # ===== Criterion 3: Both files are valid JSON =====
        if package_json_valid and eslintrc_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Both configuration files are valid JSON")
        else:
            invalid_files = []
            if not package_json_valid:
                invalid_files.append("package.json")
            if not eslintrc_valid:
                invalid_files.append(".eslintrc.json")
            feedback_parts.append(f"❌ Invalid JSON in: {', '.join(invalid_files)}")
        
        # ===== Calculate final result =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = (criteria_passed == total_criteria)  # All criteria must pass
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        if passed:
            summary = (
                "✅ Task completed successfully! "
                "ESLint and Prettier are now configured to work together without conflicts."
            )
        else:
            summary = f"❌ Task incomplete: {criteria_passed}/{total_criteria} criteria passed"
        
        final_feedback = f"{summary} | {feedback}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback
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
