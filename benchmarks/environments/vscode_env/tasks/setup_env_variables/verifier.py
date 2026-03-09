#!/usr/bin/env python3
"""
Verifier for Environment Variables Configuration task
"""

import sys
import os
import json
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_env_file(filepath):
    """
    Parse .env file into key-value dictionary
    Handles KEY=value format with optional quotes
    """
    env_vars = {}
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Parse KEY=value
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Remove quotes if present
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    elif value.startswith("'") and value.endswith("'"):
                        value = value[1:-1]
                    
                    env_vars[key] = value
    except Exception as e:
        logger.error(f"Error parsing .env file: {e}")
    
    return env_vars


def verify_env_setup(traj, env_info, task_info):
    """
    Verify that environment variables configuration is correct.
    
    Checks:
    1. .env file exists with all 4 required variables (DATABASE_URL, API_KEY, PORT, NODE_ENV)
    2. Variable values are correct or reasonable
    3. launch.json has envFile property pointing to .env
    4. launch.json is valid JSON
    5. .env is in .gitignore (security bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_env_')
    
    try:
        # Copy exported files
        env_file_local = os.path.join(temp_dir, "result_env_file.txt")
        launch_json_local = os.path.join(temp_dir, "result_launch.json")
        gitignore_local = os.path.join(temp_dir, "result_gitignore.txt")
        
        try:
            copy_from_env("/tmp/result_env_file.txt", env_file_local)
            copy_from_env("/tmp/result_launch.json", launch_json_local)
            copy_from_env("/tmp/result_gitignore.txt", gitignore_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy result files: {str(e)}"}
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # === Criterion 1: .env file exists and is not empty (10 points) ===
        env_file_exists = False
        if os.path.exists(env_file_local) and os.path.getsize(env_file_local) > 0:
            with open(env_file_local, 'r') as f:
                content = f.read().strip()
                if content != "FILE_NOT_FOUND":
                    env_file_exists = True
                    criteria_passed += 0.25  # Partial credit for file existence
                    feedback_parts.append("✅ .env file created")
        
        if not env_file_exists:
            feedback_parts.append("❌ .env file not found or empty")
            # Early return with low score if .env doesn't exist
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # === Criterion 2: .env file contains all required variables with correct values (30 points) ===
        env_vars = parse_env_file(env_file_local)
        
        required_vars = {
            'DATABASE_URL': 'postgresql://localhost:5432/myapp',
            'API_KEY': 'sk_test_abc123xyz789',
            'PORT': '3000',
            'NODE_ENV': 'development'
        }
        
        vars_correct = 0
        for var_name, expected_value in required_vars.items():
            if var_name in env_vars:
                actual_value = env_vars[var_name]
                # Check if value is correct (exact match or reasonable alternative)
                if actual_value == expected_value:
                    vars_correct += 1
                    feedback_parts.append(f"✅ {var_name} correct")
                elif actual_value.strip():  # Has some value, partial credit
                    # For PORT, accept any numeric value
                    if var_name == 'PORT' and actual_value.isdigit():
                        vars_correct += 0.75
                        feedback_parts.append(f"⚠️ {var_name}={actual_value} (expected {expected_value})")
                    # For DATABASE_URL, accept any postgres connection string
                    elif var_name == 'DATABASE_URL' and 'postgres' in actual_value.lower():
                        vars_correct += 0.75
                        feedback_parts.append(f"⚠️ {var_name} has postgres connection (expected exact match)")
                    # For others, partial credit for having a value
                    else:
                        vars_correct += 0.5
                        feedback_parts.append(f"⚠️ {var_name} present but value differs")
                else:
                    feedback_parts.append(f"❌ {var_name} is empty")
            else:
                feedback_parts.append(f"❌ {var_name} missing")
        
        # Award points proportionally (up to 1.5 criteria worth)
        vars_score = (vars_correct / len(required_vars)) * 1.5
        criteria_passed += vars_score
        
        # === Criterion 3: launch.json exists and is valid JSON (10 points) ===
        launch_json_valid = False
        launch_config = None
        
        if os.path.exists(launch_json_local) and os.path.getsize(launch_json_local) > 0:
            try:
                with open(launch_json_local, 'r') as f:
                    content = f.read().strip()
                    if content != "FILE_NOT_FOUND":
                        launch_config = json.loads(content)
                        launch_json_valid = True
                        criteria_passed += 0.5
                        feedback_parts.append("✅ launch.json is valid JSON")
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ launch.json has invalid JSON syntax: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ launch.json not found")
        
        # === Criterion 4: launch.json has envFile property (20 points) ===
        has_env_file_property = False
        
        if launch_json_valid and launch_config:
            configurations = launch_config.get('configurations', [])
            
            for config in configurations:
                if 'envFile' in config:
                    env_file_path = config['envFile']
                    # Check if path points to .env file
                    if '.env' in env_file_path:
                        has_env_file_property = True
                        criteria_passed += 1.5
                        feedback_parts.append(f"✅ envFile property found: {env_file_path}")
                        break
            
            if not has_env_file_property:
                feedback_parts.append("❌ envFile property not found in launch.json configurations")
        elif not launch_json_valid:
            feedback_parts.append("❌ Cannot check envFile (launch.json invalid)")
        
        # === Criterion 5: .env is in .gitignore (security bonus, 10 points) ===
        env_in_gitignore = False
        
        if os.path.exists(gitignore_local):
            with open(gitignore_local, 'r') as f:
                gitignore_content = f.read()
                # Check for .env patterns
                if re.search(r'(^|\n)\.env($|\n|\*)', gitignore_content, re.MULTILINE):
                    env_in_gitignore = True
                    criteria_passed += 0.75
                    feedback_parts.append("✅ .env in .gitignore (good security practice)")
                else:
                    feedback_parts.append("⚠️ .env not in .gitignore (security concern)")
        
        # Calculate final score (out of 100)
        score = int((criteria_passed / total_criteria) * 100)
        score = min(score, 100)  # Cap at 100
        
        # Pass threshold: 70%
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
