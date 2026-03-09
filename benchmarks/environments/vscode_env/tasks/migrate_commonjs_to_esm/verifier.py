#!/usr/bin/env python3
"""
Verifier for Migrate CommonJS to ESM task
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def remove_comments(content):
    """Remove JavaScript comments to avoid false positives in verification."""
    # Remove single-line comments
    content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
    # Remove multi-line comments
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    return content


def verify_migration(traj, env_info, task_info):
    """
    Verify that CommonJS to ESM migration was completed successfully.
    
    Checks:
    1. package.json contains "type": "module"
    2. No require() calls remain in source files (except in comments)
    3. All source files use import statements
    4. No module.exports or exports. assignments remain
    5. JSON configuration is loaded in ESM-compatible way
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='esm_verify_')
    
    try:
        feedback_parts = []
        issues = []
        criteria_passed = 0
        total_criteria = 0
        
        # Define all files to check
        source_files = [
            'src/auth.js',
            'src/utils/hash.js',
            'src/config.js',
            'test/auth.test.js'
        ]
        
        # Check 1: Verify package.json has "type": "module"
        total_criteria += 1
        pkg_path = '/home/ga/workspace/auth-service/package.json'
        local_pkg = os.path.join(temp_dir, 'package.json')
        
        try:
            copy_from_env(pkg_path, local_pkg)
            
            if not os.path.exists(local_pkg) or os.path.getsize(local_pkg) == 0:
                issues.append('package.json not found or empty')
                feedback_parts.append('❌ package.json not found or empty')
            else:
                with open(local_pkg, 'r', encoding='utf-8') as f:
                    pkg_data = json.load(f)
                
                if pkg_data.get('type') == 'module':
                    criteria_passed += 1
                    feedback_parts.append('✅ package.json has "type": "module"')
                else:
                    issues.append('package.json missing "type": "module"')
                    feedback_parts.append('❌ package.json must have "type": "module"')
        except json.JSONDecodeError as e:
            issues.append(f'package.json is not valid JSON: {e}')
            feedback_parts.append('❌ package.json is not valid JSON')
        except Exception as e:
            issues.append(f'Could not read package.json: {e}')
            feedback_parts.append(f'❌ Could not verify package.json: {str(e)[:50]}')
        
        # Check 2-5: Verify each source file
        for source_file in source_files:
            container_path = f'/home/ga/workspace/auth-service/{source_file}'
            local_path = os.path.join(temp_dir, source_file.replace('/', '_'))
            filename = source_file.split('/')[-1]
            
            try:
                copy_from_env(container_path, local_path)
                
                if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                    issues.append(f'{filename}: File not found or empty')
                    feedback_parts.append(f'❌ {filename} not found or empty')
                    total_criteria += 4  # Skip criteria for this file
                    continue
                
                content = read_file_content(local_path)
                content_no_comments = remove_comments(content)
                
                # Check 2: No require() calls (per file)
                total_criteria += 1
                require_pattern = r'\brequire\s*\('
                if re.search(require_pattern, content_no_comments):
                    issues.append(f'{filename}: Still contains require() calls')
                    feedback_parts.append(f'❌ {filename} still uses require()')
                else:
                    criteria_passed += 1
                    feedback_parts.append(f'✅ {filename} has no require() calls')
                
                # Check 3: Has import statements (per file)
                total_criteria += 1
                if 'import ' in content:
                    criteria_passed += 1
                    feedback_parts.append(f'✅ {filename} uses import statements')
                else:
                    issues.append(f'{filename}: No import statements found')
                    feedback_parts.append(f'❌ {filename} missing import statements')
                
                # Check 4: No module.exports or exports. (per file)
                total_criteria += 1
                exports_pattern = r'\b(module\.exports|exports\.)\s*[=\[]'
                if re.search(exports_pattern, content_no_comments):
                    issues.append(f'{filename}: Still uses CommonJS exports')
                    feedback_parts.append(f'❌ {filename} still uses module.exports or exports')
                else:
                    criteria_passed += 1
                    feedback_parts.append(f'✅ {filename} uses ESM export syntax')
                
                # Check 5: Special check for config.js JSON import
                if 'config.js' in filename:
                    total_criteria += 1
                    # Check if JSON is imported in an ESM-compatible way
                    has_proper_json_import = (
                        ('assert' in content and 'type' in content and 'json' in content.lower()) or
                        ('import.meta.url' in content and 'readFileSync' in content)
                    )
                    
                    if has_proper_json_import:
                        criteria_passed += 1
                        feedback_parts.append(f'✅ {filename} uses ESM-compatible JSON loading')
                    else:
                        issues.append(f'{filename}: JSON import may not be ESM-compliant')
                        feedback_parts.append(f'⚠️  {filename} JSON import should use assert or import.meta.url')
            
            except Exception as e:
                logger.error(f"Error verifying {source_file}: {e}")
                issues.append(f'{filename}: Verification error - {str(e)[:50]}')
                feedback_parts.append(f'❌ {filename}: Could not verify - {str(e)[:40]}')
                total_criteria += 4  # Account for skipped checks
        
        # Calculate final score
        if total_criteria == 0:
            score = 0
            success = False
            summary = '❌ FAILED: Could not verify any files'
        else:
            score = int((criteria_passed / total_criteria) * 100)
            success = score >= 75  # Need 75% to pass
            
            if not issues:
                summary = '✅ COMPLETE: Successfully migrated from CommonJS to ES Modules!'
            elif score >= 75:
                summary = f'✅ PASSED: Migration mostly complete ({criteria_passed}/{total_criteria} criteria met)'
            elif score >= 50:
                summary = f'⚠️  PARTIAL: Migration incomplete ({criteria_passed}/{total_criteria} criteria met)'
            else:
                summary = f'❌ INCOMPLETE: Migration has significant issues ({criteria_passed}/{total_criteria} criteria met)'
        
        # Build detailed feedback
        feedback = f"{summary}\n\n" + "\n".join(feedback_parts)
        
        if issues and score < 75:
            feedback += "\n\n**Issues to fix:**\n" + "\n".join(f"  • {issue}" for issue in issues[:5])
            if len(issues) > 5:
                feedback += f"\n  ... and {len(issues) - 5} more issues"
        
        return {
            "passed": success,
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
