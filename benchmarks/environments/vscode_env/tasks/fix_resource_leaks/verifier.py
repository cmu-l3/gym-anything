#!/usr/bin/env python3
"""
Verifier for Fix Resource Leaks task
Uses AST parsing to detect proper resource management patterns
"""

import sys
import os
import logging
import tempfile
import ast
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_python_file(filepath):
    """Parse Python file and return AST, or None if syntax error"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        tree = ast.parse(content)
        return tree, content
    except SyntaxError as e:
        logger.error(f"Syntax error in {filepath}: {e}")
        return None, None
    except Exception as e:
        logger.error(f"Error parsing {filepath}: {e}")
        return None, None


def check_app_py_fixed(filepath):
    """
    Check if app.py leak is fixed
    Original issue: Line 23 - log_file = open(...) without close
    Valid fixes: 
    - Wrapped in 'with open(...) as log_file:'
    - Added log_file.close() after usage
    - Added finally block with close
    """
    tree, content = parse_python_file(filepath)
    if tree is None:
        return False
    
    # Check for 'with open' pattern in setup_logging function
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == 'setup_logging':
            # Look for With statement containing 'open'
            for child in ast.walk(node):
                if isinstance(child, ast.With):
                    for item in child.items:
                        if isinstance(item.context_expr, ast.Call):
                            func = item.context_expr.func
                            if (isinstance(func, ast.Name) and func.id == 'open'):
                                return True
                            if (isinstance(func, ast.Attribute) and func.attr == 'open'):
                                return True
    
    # Alternative: Check for explicit .close() call
    if 'log_file.close()' in content or 'log_file .close()' in content:
        return True
    
    # Check for finally block with close
    if re.search(r'finally:.*log_file.*close\(\)', content, re.DOTALL):
        return True
    
    return False


def check_db_py_fixed(filepath):
    """
    Check if db.py leak is fixed
    Original issue: Connection not closed in error path of execute_query
    Valid fixes:
    - Wrapped connection in 'with' statement
    - Added finally block with conn.close()
    """
    tree, content = parse_python_file(filepath)
    if tree is None:
        return False
    
    # Look for execute_query method
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == 'execute_query':
            # Check for Try-Finally pattern with close in finally
            for child in ast.walk(node):
                if isinstance(child, ast.Try) and child.finalbody:
                    # Check if finally block contains close
                    finally_code = ast.unparse(child.finalbody) if hasattr(ast, 'unparse') else ''
                    if 'close()' in finally_code or 'close()' in content[child.finalbody[0].lineno:]:
                        return True
    
    # Check for with statement around connection
    if 'with psycopg2.connect' in content:
        return True
    
    # Check for explicit finally with conn.close()
    if re.search(r'finally:.*conn.*close\(\)', content, re.DOTALL):
        return True
    
    return False


def check_file_processor_py_fixed(filepath):
    """
    Check if file_processor.py leak is fixed
    Original issue: Line 67 - tmp = tempfile.NamedTemporaryFile(...) not closed
    Valid fixes:
    - Wrapped in 'with tempfile.NamedTemporaryFile(...) as tmp:'
    - Added tmp.close() explicitly
    """
    tree, content = parse_python_file(filepath)
    if tree is None:
        return False
    
    # Check for 'with tempfile.NamedTemporaryFile' pattern
    if 'with tempfile.NamedTemporaryFile' in content:
        return True
    
    # Check for explicit tmp.close()
    if re.search(r'tmp\s*=.*NamedTemporaryFile.*\n.*tmp\.close\(\)', content, re.DOTALL):
        return True
    
    # Check for finally block with tmp.close()
    if 'NamedTemporaryFile' in content and re.search(r'finally:.*tmp.*close\(\)', content, re.DOTALL):
        return True
    
    return False


def check_report_generator_py_fixed(filepath):
    """
    Check if report_generator.py leak is fixed
    Original issues: 
    - Line 89: response = requests.get(...) not closed
    - Also resp and r in other functions
    Valid fixes:
    - Added response.close() or resp.close() or r.close()
    - Used 'with requests.get(...) as response:'
    - Added finally blocks
    
    Must fix at least 2 out of 3 request leaks
    """
    tree, content = parse_python_file(filepath)
    if tree is None:
        return False
    
    fixes_count = 0
    
    # Check for response.close() in fetch_report_data
    if 'response.close()' in content or 'response .close()' in content:
        fixes_count += 1
    
    # Check for resp.close() in download_external_resource
    if 'resp.close()' in content or 'resp .close()' in content:
        fixes_count += 1
    
    # Check for r.close() in check_api_health
    if re.search(r'r\.close\(\)', content):
        fixes_count += 1
    
    # Check for with statement patterns
    if 'with requests.get' in content:
        fixes_count += 1
    
    # Check for finally blocks with close
    if re.search(r'finally:.*\.(response|resp|r).*close\(\)', content, re.DOTALL):
        fixes_count += 1
    
    # Need at least 2 fixes for this to pass
    return fixes_count >= 2


def check_backup_py_fixed(filepath):
    """
    Check if backup.py leak is fixed
    Original issue: Lines 112-118 - multiple files opened in loop without closing
    Valid fixes:
    - Wrapped each open() in 'with' statement
    - Added explicit .close() after each file operation
    - Used try-finally for cleanup
    
    Must fix at least 2 out of 3 file operations in the function
    """
    tree, content = parse_python_file(filepath)
    if tree is None:
        return False
    
    fixes_count = 0
    
    # Look for backup_configuration_files function
    backup_func_content = ""
    lines = content.split('\n')
    in_function = False
    for i, line in enumerate(lines):
        if 'def backup_configuration_files' in line:
            in_function = True
        elif in_function and line.startswith('def ') and 'backup_configuration_files' not in line:
            break
        if in_function:
            backup_func_content += line + '\n'
    
    if not backup_func_content:
        backup_func_content = content
    
    # Count with statements for file operations
    with_open_count = backup_func_content.count('with open(')
    if with_open_count >= 2:
        fixes_count += 2
    elif with_open_count == 1:
        fixes_count += 1
    
    # Count explicit close() calls
    close_count = backup_func_content.count('.close()')
    if close_count >= 3:
        fixes_count += 2
    elif close_count >= 1:
        fixes_count += 1
    
    # Check for finally blocks
    if re.search(r'finally:.*close\(\)', backup_func_content, re.DOTALL):
        fixes_count += 1
    
    # Need significant fixes (at least 2 evidences of proper resource management)
    return fixes_count >= 2


def verify_resource_leaks_fixed(traj, env_info, task_info):
    """
    Main verifier for resource leaks task
    
    Checks all 5 files for proper resource management:
    1. app.py - file logging leak
    2. db.py - database connection leak
    3. file_processor.py - temporary file leak
    4. report_generator.py - HTTP response leaks
    5. backup.py - multiple file leaks in loop
    
    Pass threshold: 4 out of 5 fixes (80%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='verify_leaks_')
    
    try:
        files_to_check = [
            ('app.py', check_app_py_fixed, 'app.py file logging leak'),
            ('db.py', check_db_py_fixed, 'db.py connection leak in error path'),
            ('file_processor.py', check_file_processor_py_fixed, 'file_processor.py temporary file leak'),
            ('report_generator.py', check_report_generator_py_fixed, 'report_generator.py HTTP response leaks'),
            ('backup.py', check_backup_py_fixed, 'backup.py multiple file leaks in loop')
        ]
        
        results = []
        feedback_parts = []
        
        for filename, check_func, description in files_to_check:
            container_path = f"/home/ga/workspace/flask_api/{filename}"
            local_path = os.path.join(temp_dir, filename)
            
            try:
                copy_from_env(container_path, local_path)
                
                if not os.path.exists(local_path):
                    results.append(False)
                    feedback_parts.append(f"❌ {filename} not found")
                    continue
                
                # Verify syntax is valid
                tree, content = parse_python_file(local_path)
                if tree is None:
                    results.append(False)
                    feedback_parts.append(f"❌ {filename} has syntax errors")
                    continue
                
                # Check if leak is fixed
                is_fixed = check_func(local_path)
                results.append(is_fixed)
                
                if is_fixed:
                    feedback_parts.append(f"✅ {filename} - leak fixed")
                else:
                    feedback_parts.append(f"❌ {filename} - leak NOT fixed")
                    
            except Exception as e:
                results.append(False)
                feedback_parts.append(f"❌ {filename} - error: {str(e)[:50]}")
                logger.error(f"Error checking {filename}: {e}")
        
        # Calculate score
        fixes_count = sum(results)
        score = int((fixes_count / len(results)) * 100)
        passed = score >= 80  # Need 4 out of 5 fixes
        
        feedback = " | ".join(feedback_parts)
        summary = f"Fixed {fixes_count}/5 resource leaks"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"{summary} | {feedback}",
            "details": {
                "app_py_fixed": results[0],
                "db_py_fixed": results[1],
                "file_processor_py_fixed": results[2],
                "report_generator_py_fixed": results[3],
                "backup_py_fixed": results[4],
                "fixes_count": fixes_count,
                "required_fixes": 4
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
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
