#!/usr/bin/env python3
"""
Verifier for Create Minimal Reproduction task (create_minimal_repro@1)
Checks that agent created a proper minimal reproduction package
"""

import sys
import os
import logging
import tempfile
import ast
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_minimal_repro(traj, env_info, task_info):
    """
    Verify that a minimal reproduction was created correctly.
    
    Checks:
    1. Reproduction directory exists
    2. Required files exist (repro.py, README.md, requirements.txt)
    3. No extra files (should be minimal)
    4. repro.py is minimal (<20 lines)
    5. repro.py contains date parsing bug code
    6. repro.py imports ONLY dateutil (no local imports)
    7. repro.py is syntactically valid
    8. README.md contains required sections
    9. requirements.txt contains only python-dateutil with version
    
    Returns:
        dict with 'passed', 'score', 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    REPRO_DIR = "/home/ga/workspace/bug-reproduction"
    REQUIRED_FILES = ["repro.py", "README.md", "requirements.txt"]
    
    criteria_passed = 0
    total_criteria = 9
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp(prefix='verify_repro_')
    
    try:
        # Check 1: Reproduction directory exists
        structure_file = os.path.join(temp_dir, "structure.txt")
        try:
            copy_from_env("/tmp/repro_structure.txt", structure_file)
            with open(structure_file, 'r') as f:
                structure = f.read()
            
            if "Directory does not exist" in structure:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Reproduction directory not found: {REPRO_DIR}"
                }
            criteria_passed += 1
            feedback_parts.append("✅ Reproduction directory exists")
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Error checking directory: {str(e)}"
            }
        
        # Check 2: Required files exist
        files_present = {"repro.py": False, "README.md": False, "requirements.txt": False}
        
        for filename in REQUIRED_FILES:
            local_path = os.path.join(temp_dir, filename)
            try:
                copy_from_env(f"{REPRO_DIR}/{filename}", local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    files_present[filename] = True
            except:
                pass
        
        missing_files = [f for f, present in files_present.items() if not present]
        if missing_files:
            feedback_parts.append(f"❌ Missing files: {', '.join(missing_files)}")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ All required files present")
        
        # Check 3: No extra files (being lenient, just checking structure)
        # Parse structure to count files
        files_in_dir = []
        for line in structure.split('\n'):
            if line.strip() and not line.startswith('total') and not line.startswith('d'):
                # Extract filename from ls -la output
                parts = line.split()
                if len(parts) >= 9:
                    filename = parts[-1]
                    if filename not in ['.', '..'] and not filename.startswith('.git'):
                        files_in_dir.append(filename)
        
        extra_files = [f for f in files_in_dir if f not in REQUIRED_FILES]
        if len(extra_files) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Clean structure (no extra files)")
        else:
            # Not failing, just noting
            feedback_parts.append(f"⚠️ Extra files found: {extra_files}")
        
        # Check 4-7: Verify repro.py content
        repro_py_path = os.path.join(temp_dir, "repro.py")
        if not os.path.exists(repro_py_path):
            feedback_parts.append("❌ repro.py not accessible")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        repro_content = read_file_content(repro_py_path)
        
        # Check 4: File is minimal (<20 non-comment/non-blank lines)
        code_lines = [
            line for line in repro_content.split('\n')
            if line.strip() and not line.strip().startswith('#')
        ]
        
        if len(code_lines) <= 20:
            criteria_passed += 1
            feedback_parts.append(f"✅ Code is minimal ({len(code_lines)} lines)")
        else:
            feedback_parts.append(f"❌ Code too long ({len(code_lines)} lines, expected ≤20)")
        
        # Check 5: Contains date parsing issue
        has_parse = 'parse' in repro_content.lower()
        has_pst = 'pst' in repro_content.lower()
        has_dateutil = 'dateutil' in repro_content.lower()
        
        if has_parse and has_pst and has_dateutil:
            criteria_passed += 1
            feedback_parts.append("✅ Contains date parsing bug code")
        else:
            missing = []
            if not has_parse:
                missing.append("parse call")
            if not has_pst:
                missing.append("PST timezone")
            if not has_dateutil:
                missing.append("dateutil reference")
            feedback_parts.append(f"❌ Missing bug reproduction elements: {', '.join(missing)}")
        
        # Check 6: Imports ONLY dateutil (no local imports)
        try:
            tree = ast.parse(repro_content)
            imports = []
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.extend([alias.name for alias in node.names])
                elif isinstance(node, ast.ImportFrom):
                    if node.module:
                        imports.append(node.module)
            
            # Check for local imports (bad)
            local_imports = ['utils', 'validators', 'config', 'main']
            has_local = any(imp in local_imports for imp in imports if imp)
            
            # Check for dateutil (good)
            has_dateutil_import = any('dateutil' in imp for imp in imports if imp)
            
            if has_dateutil_import and not has_local:
                criteria_passed += 1
                feedback_parts.append("✅ Clean imports (only dateutil)")
            elif has_local:
                local_found = [imp for imp in imports if imp in local_imports]
                feedback_parts.append(f"❌ Has local imports: {local_found}")
            elif not has_dateutil_import:
                feedback_parts.append("❌ Missing dateutil import")
            
        except SyntaxError as e:
            feedback_parts.append(f"❌ Syntax error in repro.py: {str(e)}")
        except Exception as e:
            feedback_parts.append(f"⚠️ Could not parse imports: {str(e)}")
        
        # Check 7: File is syntactically valid
        try:
            compile(repro_content, 'repro.py', 'exec')
            criteria_passed += 1
            feedback_parts.append("✅ Valid Python syntax")
        except SyntaxError as e:
            feedback_parts.append(f"❌ Syntax error: {str(e)}")
        
        # Check 8: Verify README.md content
        readme_path = os.path.join(temp_dir, "README.md")
        if os.path.exists(readme_path):
            readme_content = read_file_content(readme_path).lower()
            
            required_sections = [
                "steps to reproduce",
                "expected behavior",
                "actual behavior"
            ]
            
            missing_sections = [s for s in required_sections if s not in readme_content]
            
            if not missing_sections:
                criteria_passed += 1
                feedback_parts.append("✅ README has all required sections")
            else:
                feedback_parts.append(f"❌ README missing sections: {missing_sections}")
        else:
            feedback_parts.append("❌ README.md not accessible")
        
        # Check 9: Verify requirements.txt
        req_path = os.path.join(temp_dir, "requirements.txt")
        if os.path.exists(req_path):
            req_content = read_file_content(req_path).strip()
            
            # Remove comments and empty lines
            req_lines = [
                line.strip() for line in req_content.split('\n')
                if line.strip() and not line.strip().startswith('#')
            ]
            
            # Should have exactly 1 dependency
            if len(req_lines) == 1:
                req_line = req_lines[0].lower()
                
                # Check it's dateutil with pinned version
                has_dateutil = 'dateutil' in req_line or 'python-dateutil' in req_line
                has_version = '==' in req_line
                
                if has_dateutil and has_version:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Clean requirements.txt: {req_lines[0]}")
                elif not has_dateutil:
                    feedback_parts.append(f"❌ requirements.txt doesn't contain python-dateutil")
                elif not has_version:
                    feedback_parts.append(f"❌ Dependency version not pinned (missing ==)")
            elif len(req_lines) > 1:
                feedback_parts.append(f"❌ Too many dependencies ({len(req_lines)}), expected 1")
            else:
                feedback_parts.append("❌ requirements.txt is empty")
        else:
            feedback_parts.append("❌ requirements.txt not accessible")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score == 100  # All criteria must pass for this task
        
        feedback = " | ".join(feedback_parts)
        feedback = f"Criteria passed: {criteria_passed}/{total_criteria} | " + feedback
        
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
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
