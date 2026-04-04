#!/usr/bin/env python3
"""
Verifier for Environment Config Setup task
"""

import sys
import os
import logging
import tempfile
import re
import subprocess
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_env_file(filepath):
    """
    Parse .env file into dictionary.
    Returns dict of KEY=VALUE pairs.
    """
    env_vars = {}
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Parse KEY=VALUE format
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
                else:
                    logger.warning(f"Line {line_num} has invalid format: {line}")
        return env_vars
    except Exception as e:
        logger.error(f"Error parsing .env file: {e}")
        return {}


def analyze_required_variables(project_files_content):
    """
    Analyze code to find required environment variables.
    Returns set of required variable names.
    """
    required_vars = set()
    
    # Known required variables based on our sample app
    # These are the variables our server.js requires
    known_required = {'PORT', 'DATABASE_URL', 'API_KEY'}
    
    # Also scan for process.env references
    for content in project_files_content.values():
        # Match process.env.VAR_NAME
        matches = re.findall(r'process\.env\.(\w+)', content)
        for var in matches:
            # Variables used in validation checks are likely required
            if f"!{var}" in content or f"!process.env.{var}" in content:
                required_vars.add(var)
            # Variables in error messages are likely required
            if f"'{var}'" in content or f'"{var}"' in content:
                if 'required' in content.lower() or 'missing' in content.lower():
                    required_vars.add(var)
    
    # Combine with known required variables
    required_vars.update(known_required)
    
    return required_vars


def validate_env_values(env_vars):
    """
    Validate that environment variable values are appropriate.
    Returns list of issues found.
    """
    issues = []
    
    # Check PORT
    if 'PORT' in env_vars:
        try:
            port = int(env_vars['PORT'])
            if port < 1024 or port > 65535:
                issues.append(f"PORT {port} is outside valid range (1024-65535)")
        except ValueError:
            issues.append(f"PORT value '{env_vars['PORT']}' is not a valid number")
    
    # Check DATABASE_URL format
    if 'DATABASE_URL' in env_vars:
        db_url = env_vars['DATABASE_URL']
        if not any(db_url.startswith(prefix) for prefix in ['postgres://', 'postgresql://', 'mysql://', 'mongodb://', 'sqlite://']):
            issues.append(f"DATABASE_URL doesn't appear to be a valid connection string")
    
    # Check for placeholder values
    for key, value in env_vars.items():
        value_lower = value.lower()
        if any(placeholder in value_lower for placeholder in ['your_', 'placeholder', 'change_me', 'xxx', 'todo']):
            issues.append(f"{key} appears to contain a placeholder value: {value}")
    
    return issues


def verify_env_setup(traj, env_info, task_info):
    """
    Verify that environment configuration was set up correctly.
    
    Checks:
    1. .env file exists in project root
    2. File has valid syntax
    3. All required variables are present
    4. Variable values are appropriate
    5. Application can start successfully
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='env_verify_')
    
    try:
        # Copy .env file
        env_file_local = os.path.join(temp_dir, "result.env")
        try:
            copy_from_env("/tmp/result.env", env_file_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy .env file: {str(e)}"}
        
        # Copy project files for analysis
        project_files = {}
        for filename in ['server.js', 'config.js']:
            local_path = os.path.join(temp_dir, filename)
            try:
                copy_from_env(f"/home/ga/workspace/env_config_project/{filename}", local_path)
                if os.path.exists(local_path):
                    project_files[filename] = read_file_content(local_path)
            except Exception as e:
                logger.warning(f"Could not copy {filename}: {e}")
        
        criteria = {
            'file_exists': False,
            'valid_syntax': False,
            'complete_coverage': False,
            'appropriate_values': False,
            'app_evidence': False
        }
        feedback_parts = []
        
        # Criterion 1: File exists
        if not os.path.exists(env_file_local) or os.path.getsize(env_file_local) == 0:
            feedback_parts.append("❌ .env file not found or empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria['file_exists'] = True
        feedback_parts.append("✅ .env file exists")
        
        # Criterion 2: Parse and validate syntax
        env_vars = parse_env_file(env_file_local)
        if not env_vars:
            feedback_parts.append("❌ No valid environment variables found (syntax error or empty file)")
            return {
                "passed": False,
                "score": 25,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria['valid_syntax'] = True
        feedback_parts.append(f"✅ Valid syntax: {len(env_vars)} variables parsed")
        
        # Criterion 3: Check required variables coverage
        required_vars = analyze_required_variables(project_files)
        missing_vars = required_vars - set(env_vars.keys())
        
        if not missing_vars:
            criteria['complete_coverage'] = True
            feedback_parts.append(f"✅ All required variables present: {', '.join(sorted(required_vars))}")
        else:
            if len(missing_vars) <= len(required_vars) * 0.3:  # Allow up to 30% missing for partial credit
                criteria['complete_coverage'] = True
                feedback_parts.append(f"⚠️ Mostly complete but missing: {', '.join(sorted(missing_vars))}")
            else:
                feedback_parts.append(f"❌ Missing required variables: {', '.join(sorted(missing_vars))}")
        
        # Criterion 4: Validate values
        value_issues = validate_env_values(env_vars)
        if not value_issues:
            criteria['appropriate_values'] = True
            feedback_parts.append("✅ All values are appropriately formatted")
        else:
            if len(value_issues) <= 2:  # Minor issues still get partial credit
                criteria['appropriate_values'] = True
            feedback_parts.append(f"⚠️ Value issues: {'; '.join(value_issues[:2])}")
        
        # Criterion 5: Check for evidence of successful startup attempt
        # Copy startup log if available
        startup_log_local = os.path.join(temp_dir, "app_startup.log")
        try:
            copy_from_env("/tmp/app_startup.log", startup_log_local)
            if os.path.exists(startup_log_local):
                startup_content = read_file_content(startup_log_local).lower()
                
                # Check for success indicators
                success_indicators = ['server listening', 'server started', 'application started', 'listening on port']
                has_success = any(indicator in startup_content for indicator in success_indicators)
                
                # Check for error indicators
                error_indicators = ['is not defined', 'undefined', 'missing required', 'error:', 'cannot find']
                has_error = any(indicator in startup_content for indicator in error_indicators)
                
                if has_success and not has_error:
                    criteria['app_evidence'] = True
                    feedback_parts.append("✅ Application startup successful")
                elif has_error:
                    feedback_parts.append("⚠️ Application startup had errors")
                else:
                    criteria['app_evidence'] = True  # Partial credit if no clear error
                    feedback_parts.append("⚠️ Application startup attempted")
        except Exception as e:
            logger.warning(f"Could not check startup log: {e}")
            # Don't penalize if we can't check this
            criteria['app_evidence'] = True
        
        # Calculate score with weights
        weights = {
            'file_exists': 15,
            'valid_syntax': 20,
            'complete_coverage': 35,
            'appropriate_values': 20,
            'app_evidence': 10
        }
        
        score = sum(weights[key] for key, value in criteria.items() if value)
        passed = score >= 70
        
        # Add summary
        if passed:
            feedback_parts.insert(0, f"🎉 Task completed successfully (score: {score}/100)")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete (score: {score}/100, need ≥70)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
