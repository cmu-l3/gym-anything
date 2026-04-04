#!/usr/bin/env python3
"""
Verifier for Configure Conditional Git Identity task
"""

import sys
import os
import logging
import tempfile
import shutil
import re
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_git_config(content):
    """Parse git config INI-style format into dict structure"""
    config = {}
    current_section = None
    
    for line in content.split('\n'):
        line = line.strip()
        
        # Skip empty lines and comments
        if not line or line.startswith('#') or line.startswith(';'):
            continue
        
        # Section header
        section_match = re.match(r'\[([^\]]+)\]', line)
        if section_match:
            current_section = section_match.group(1)
            if current_section not in config:
                config[current_section] = {}
            continue
        
        # Key-value pair
        if current_section and '=' in line:
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip().strip('"')
            config[current_section][key] = value
    
    return config


def extract_conditional_includes(content):
    """Extract includeIf sections from git config"""
    includes = []
    lines = content.split('\n')
    
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # Look for includeIf sections
        if line.startswith('[includeIf'):
            match = re.match(r'\[includeIf\s+"([^"]+)"\]', line)
            if match:
                condition = match.group(1)
                
                # Look for path on next line
                if i + 1 < len(lines):
                    next_line = lines[i + 1].strip()
                    if next_line.startswith('path'):
                        path = next_line.split('=', 1)[1].strip().strip('"')
                        includes.append({
                            'condition': condition,
                            'path': path
                        })
        i += 1
    
    return includes


def normalize_path(path, home_dir='/home/ga'):
    """Normalize path by expanding ~ and resolving to absolute"""
    path = path.replace('~', home_dir)
    path = os.path.normpath(path)
    return path


def matches_gitdir_condition(condition, target_dir, home_dir='/home/ga'):
    """Check if a gitdir condition matches the target directory"""
    # Extract the path from condition (format: "gitdir:path")
    if not condition.startswith('gitdir:'):
        return False
    
    condition_path = condition[7:]  # Remove "gitdir:" prefix
    condition_path = normalize_path(condition_path, home_dir)
    target_dir = normalize_path(target_dir, home_dir)
    
    # Check if target is under condition path
    # Trailing slash in condition means match subdirectories
    if condition_path.endswith('/'):
        return target_dir.startswith(condition_path)
    else:
        return target_dir == condition_path


def verify_conditional_git_identity(traj, env_info, task_info):
    """
    Verify that conditional Git identity configuration is set up correctly.
    
    Checks:
    1. Include files exist (personal-identity.inc and company-identity.inc)
    2. Global config contains conditional includeIf directives
    3. Paths correctly target personal-projects and company-work
    4. Email addresses are different in each include file
    5. Functional resolution works correctly per directory
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='git_identity_verify_')
    
    try:
        # Copy exported config files
        global_config_path = os.path.join(temp_dir, "gitconfig_global.txt")
        personal_inc_path = os.path.join(temp_dir, "personal_identity_inc.txt")
        company_inc_path = os.path.join(temp_dir, "company_identity_inc.txt")
        
        email_personal_path = os.path.join(temp_dir, "git_email_personal.txt")
        email_company_path = os.path.join(temp_dir, "git_email_company.txt")
        
        try:
            copy_from_env("/tmp/gitconfig_global.txt", global_config_path)
            copy_from_env("/tmp/personal_identity_inc.txt", personal_inc_path)
            copy_from_env("/tmp/company_identity_inc.txt", company_inc_path)
            copy_from_env("/tmp/git_email_personal.txt", email_personal_path)
            copy_from_env("/tmp/git_email_company.txt", email_company_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy config files: {str(e)}"}
        
        criteria_passed = 0
        feedback_parts = []
        
        # Criterion 1: Check include files exist and are valid
        personal_inc_valid = False
        company_inc_valid = False
        personal_email = None
        company_email = None
        
        if os.path.exists(personal_inc_path) and os.path.getsize(personal_inc_path) > 10:
            with open(personal_inc_path, 'r') as f:
                content = f.read()
                if 'No personal-identity.inc found' not in content:
                    config = parse_git_config(content)
                    if 'user' in config and 'email' in config['user']:
                        personal_email = config['user']['email']
                        personal_inc_valid = True
        
        if os.path.exists(company_inc_path) and os.path.getsize(company_inc_path) > 10:
            with open(company_inc_path, 'r') as f:
                content = f.read()
                if 'No company-identity.inc found' not in content:
                    config = parse_git_config(content)
                    if 'user' in config and 'email' in config['user']:
                        company_email = config['user']['email']
                        company_inc_valid = True
        
        if personal_inc_valid and company_inc_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Both include files exist with valid configuration")
        else:
            missing = []
            if not personal_inc_valid:
                missing.append("personal-identity.inc")
            if not company_inc_valid:
                missing.append("company-identity.inc")
            feedback_parts.append(f"❌ Missing or invalid include files: {', '.join(missing)}")
        
        # Criterion 2: Check global config contains conditional includes
        has_conditional_includes = False
        includes = []
        
        if os.path.exists(global_config_path) and os.path.getsize(global_config_path) > 10:
            with open(global_config_path, 'r') as f:
                content = f.read()
                if 'No ~/.gitconfig found' not in content:
                    includes = extract_conditional_includes(content)
                    if len(includes) >= 2:
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Found {len(includes)} conditional include directives")
                        has_conditional_includes = True
                    else:
                        feedback_parts.append(f"❌ Expected at least 2 conditional includes, found {len(includes)}")
        
        if not has_conditional_includes:
            feedback_parts.append("❌ No conditional includeIf directives in ~/.gitconfig")
        
        # Criterion 3: Check paths correctly target directories
        has_personal_path = False
        has_company_path = False
        
        for include in includes:
            condition = include['condition']
            if 'personal-projects' in condition or 'personal_projects' in condition:
                has_personal_path = True
            if 'company-work' in condition or 'company_work' in condition:
                has_company_path = True
        
        if has_personal_path and has_company_path:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional paths target both personal-projects and company-work")
        else:
            missing_paths = []
            if not has_personal_path:
                missing_paths.append("personal-projects")
            if not has_company_path:
                missing_paths.append("company-work")
            feedback_parts.append(f"❌ Missing directory targeting: {', '.join(missing_paths)}")
        
        # Criterion 4: Check email addresses are different
        if personal_email and company_email:
            if personal_email != company_email:
                criteria_passed += 1
                feedback_parts.append(f"✅ Distinct email addresses: {personal_email} vs {company_email}")
            else:
                feedback_parts.append(f"❌ Email addresses must be different (both are: {personal_email})")
        else:
            feedback_parts.append("❌ Could not extract email addresses from include files")
        
        # Criterion 5: Check functional resolution
        personal_resolved_email = None
        company_resolved_email = None
        
        if os.path.exists(email_personal_path):
            with open(email_personal_path, 'r') as f:
                personal_resolved_email = f.read().strip()
        
        if os.path.exists(email_company_path):
            with open(email_company_path, 'r') as f:
                company_resolved_email = f.read().strip()
        
        functional_test_passed = False
        if personal_resolved_email and company_resolved_email:
            if personal_resolved_email != 'error' and company_resolved_email != 'error':
                if personal_resolved_email != company_resolved_email:
                    # Check if resolved emails match the configured ones
                    if (personal_email and personal_resolved_email == personal_email and
                        company_email and company_resolved_email == company_email):
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Configuration resolves correctly: personal={personal_resolved_email}, company={company_resolved_email}")
                        functional_test_passed = True
                    else:
                        feedback_parts.append(f"⚠️ Emails resolve but don't match configured values: personal={personal_resolved_email} (expected {personal_email}), company={company_resolved_email} (expected {company_email})")
                else:
                    feedback_parts.append(f"❌ Both directories resolve to same email: {personal_resolved_email}")
            else:
                feedback_parts.append("❌ Git config resolution failed in one or both directories")
        else:
            feedback_parts.append("❌ Could not test functional resolution")
        
        # Calculate score
        score = int((criteria_passed / 5) * 100)
        passed = score >= 80
        
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
