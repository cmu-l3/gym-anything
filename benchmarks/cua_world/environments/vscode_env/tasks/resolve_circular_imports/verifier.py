#!/usr/bin/env python3
"""
Verifier for Resolve Circular Imports task
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_resolve_circular_imports(traj, env_info, task_info):
    """
    Verify that circular import dependencies were resolved.
    
    Checks:
    1. Required files still exist
    2. No circular dependencies (via madge or import analysis)
    3. A valid fix strategy was applied
    4. Application can load successfully
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='circular_imports_verify_')
    
    try:
        # Copy exported files
        export_dir = os.path.join(temp_dir, "src")
        os.makedirs(export_dir, exist_ok=True)
        
        required_files = {
            'validation.js': '/tmp/circular_imports_export/validation.js',
            'formatting.js': '/tmp/circular_imports_export/formatting.js',
            'database.js': '/tmp/circular_imports_export/database.js',
            'constants.js': '/tmp/circular_imports_export/constants.js'
        }
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Check all files exist
        files_exist = True
        for filename, container_path in required_files.items():
            local_path = os.path.join(export_dir, filename)
            try:
                copy_from_env(container_path, local_path)
                if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                    files_exist = False
                    feedback_parts.append(f"❌ File missing or empty: {filename}")
            except Exception as e:
                files_exist = False
                feedback_parts.append(f"❌ Failed to copy {filename}: {str(e)}")
        
        if files_exist:
            criteria_passed += 1
            feedback_parts.append("✅ All required files exist")
        
        if not files_exist:
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Check for circular dependencies
        no_circular = check_no_circular_dependencies(temp_dir, export_dir, copy_from_env)
        if no_circular:
            criteria_passed += 1
            feedback_parts.append("✅ No circular dependencies detected")
        else:
            feedback_parts.append("❌ Circular dependencies still exist")
        
        # Criterion 3: Check if a fix strategy was applied
        fix_strategy = check_fix_strategy_applied(export_dir)
        if fix_strategy['applied']:
            criteria_passed += 1
            feedback_parts.append(f"✅ Fix strategy applied: {fix_strategy['strategy']}")
        else:
            feedback_parts.append("❌ No valid fix strategy detected")
        
        # Criterion 4: Check if application can load
        app_loads = check_application_loads(temp_dir, copy_from_env)
        if app_loads:
            criteria_passed += 1
            feedback_parts.append("✅ Application loads successfully")
        else:
            feedback_parts.append("❌ Application fails to load")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def check_no_circular_dependencies(temp_dir, export_dir, copy_from_env):
    """Check if circular dependencies were removed"""
    
    # Method 1: Check madge output
    madge_result_path = os.path.join(temp_dir, "madge_result.json")
    try:
        copy_from_env("/tmp/circular_imports_madge.json", madge_result_path)
        if os.path.exists(madge_result_path):
            with open(madge_result_path, 'r') as f:
                content = f.read().strip()
                if content:
                    madge_data = json.loads(content)
                    # Empty array or object means no circular dependencies
                    if isinstance(madge_data, list) and len(madge_data) == 0:
                        return True
                    elif isinstance(madge_data, dict) and len(madge_data) == 0:
                        return True
    except Exception as e:
        logger.warning(f"Could not parse madge output: {e}")
    
    # Method 2: Manual import analysis
    return check_imports_manually(export_dir)


def check_imports_manually(export_dir):
    """Manually check for circular dependencies by parsing imports"""
    
    import_graph = {}
    files = ['validation.js', 'formatting.js', 'database.js']
    
    for filename in files:
        filepath = os.path.join(export_dir, filename)
        if not os.path.exists(filepath):
            continue
        
        content = read_file_content(filepath)
        # Find all require statements with relative paths
        imports = re.findall(r"require\s*\(\s*['\"]\./([\w-]+)['\"]", content)
        import_graph[filename] = imports
    
    # Check for the original cycle: validation → formatting → database → validation
    original_cycle = (
        'formatting' in import_graph.get('validation.js', []) and
        'database' in import_graph.get('formatting.js', []) and
        'validation' in import_graph.get('database.js', [])
    )
    
    # If original cycle is broken, that's good
    return not original_cycle


def check_fix_strategy_applied(export_dir):
    """Check if a valid fix strategy was applied"""
    
    result = {'applied': False, 'strategy': 'none'}
    
    # Read all files
    files_content = {}
    for filename in ['validation.js', 'formatting.js', 'database.js', 'constants.js']:
        filepath = os.path.join(export_dir, filename)
        if os.path.exists(filepath):
            files_content[filename] = read_file_content(filepath)
    
    # Strategy A: Constants extraction
    constants_content = files_content.get('constants.js', '')
    has_exports = bool(
        re.search(r'module\.exports\s*=\s*\{[^}]+\}', constants_content) or
        re.search(r'exports\.\w+\s*=', constants_content) or
        ('errorPrefix' in constants_content and 'module.exports' in constants_content)
    )
    
    # Check if formatting.js or database.js now import from constants
    formatting_content = files_content.get('formatting.js', '')
    database_content = files_content.get('database.js', '')
    
    imports_constants = (
        "require('./constants')" in formatting_content or
        "require('./constants')" in database_content
    )
    
    if has_exports and imports_constants:
        result['applied'] = True
        result['strategy'] = 'Extracted shared constants to constants.js'
        return result
    
    # Strategy B: Lazy imports (require inside function)
    for filename, content in files_content.items():
        if filename == 'constants.js':
            continue
        # Look for require() inside function bodies (not at module top)
        # This is a heuristic: check if require appears after function keyword
        if re.search(r'function\s+\w+[^{]*\{[^}]*require\s*\(', content, re.DOTALL):
            result['applied'] = True
            result['strategy'] = 'Used lazy imports (require inside functions)'
            return result
    
    # Strategy C: Dependency inversion (removed problematic imports)
    # Check if the problematic import chain is broken
    formatting_no_db_import = "require('./database')" not in formatting_content
    database_no_validation_import = "require('./validation')" not in database_content
    validation_no_formatting_import = "require('./formatting')" not in files_content.get('validation.js', '')
    
    # At least one critical import should be removed
    if formatting_no_db_import or database_no_validation_import:
        # But make sure the files still have meaningful content
        if len(formatting_content) > 50 and len(database_content) > 50:
            result['applied'] = True
            result['strategy'] = 'Removed circular imports (dependency inversion)'
            return result
    
    # Check if constants.js has any meaningful content (even if not perfect)
    if len(constants_content) > 50:
        result['applied'] = True
        result['strategy'] = 'Modified constants.js (partial fix attempt)'
        return result
    
    return result


def check_application_loads(temp_dir, copy_from_env):
    """Check if the application loaded successfully"""
    
    # Copy exit code
    exit_code_path = os.path.join(temp_dir, "exit_code.txt")
    try:
        copy_from_env("/tmp/circular_imports_exit_code.txt", exit_code_path)
        if os.path.exists(exit_code_path):
            with open(exit_code_path, 'r') as f:
                exit_code = int(f.read().strip())
                if exit_code == 0:
                    return True
    except Exception as e:
        logger.warning(f"Could not read exit code: {e}")
    
    # Copy application output
    output_path = os.path.join(temp_dir, "app_output.txt")
    try:
        copy_from_env("/tmp/circular_imports_app_output.txt", output_path)
        if os.path.exists(output_path):
            with open(output_path, 'r') as f:
                output = f.read()
                # Look for success indicators
                if "All modules loaded successfully" in output:
                    return True
                # Check if there are no error messages
                if "TypeError" not in output and "Error" not in output and len(output) > 10:
                    return True
    except Exception as e:
        logger.warning(f"Could not read application output: {e}")
    
    return False
