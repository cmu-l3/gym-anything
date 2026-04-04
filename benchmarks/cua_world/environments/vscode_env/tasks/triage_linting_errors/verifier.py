#!/usr/bin/env python3
"""
Verifier for Triage Linting Errors task
Checks that linting errors were systematically resolved
"""

import sys
import os
import logging
import tempfile
import shutil
import re
import subprocess

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_triage_errors(traj, env_info, task_info):
    """
    Verify that the agent successfully triaged and fixed linting errors
    
    Returns:
        dict with "passed", "score", "feedback" keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='triage_verify_')
    
    try:
        feedback_parts = []
        points = 0.0
        max_points = 10.0
        
        # Copy exported files
        exported_src = os.path.join(temp_dir, "src")
        exported_tests = os.path.join(temp_dir, "tests")
        os.makedirs(exported_src, exist_ok=True)
        os.makedirs(exported_tests, exist_ok=True)
        
        expected_files = [
            ("src/models.py", "models.py"),
            ("src/database.py", "database.py"),
            ("src/api_client.py", "api_client.py"),
            ("src/validators.py", "validators.py"),
            ("src/utils.py", "utils.py"),
            ("tests/test_models.py", "test_models.py")
        ]
        
        copied_files = {}
        for rel_path, filename in expected_files:
            container_path = f"/tmp/customer_portal_export/{rel_path}"
            local_path = os.path.join(temp_dir, rel_path)
            
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    copied_files[filename] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
        
        if len(copied_files) < 4:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access workspace files. Only {len(copied_files)} files found."
            }
        
        # Criterion 1: Check that files were modified (2 points)
        modified_files = 0
        for filename, filepath in copied_files.items():
            content = read_file_content(filepath)
            # Check if file has been modified (contains type hints or suppressions)
            if (": str" in content or ": int" in content or ": bool" in content or 
                "-> " in content or "# type: ignore" in content or "# pylint: disable" in content):
                modified_files += 1
        
        if modified_files >= 5:
            points += 2.0
            feedback_parts.append(f"✅ Modified {modified_files}/6 files")
        elif modified_files >= 3:
            points += 1.0
            feedback_parts.append(f"△ Modified {modified_files}/6 files (need 5+ for full credit)")
        else:
            feedback_parts.append(f"❌ Only {modified_files} files modified (need 5+)")
        
        # Criterion 2: Check for type hints additions (2.5 points)
        type_hints_count = 0
        for filename, filepath in copied_files.items():
            content = read_file_content(filepath)
            # Count type annotations (parameters and return types)
            type_hints_count += len(re.findall(r':\s*(str|int|bool|dict|list|Optional|None|Any)', content))
            type_hints_count += len(re.findall(r'->\s*(str|int|bool|dict|list|None|Any)', content))
        
        if type_hints_count >= 15:
            points += 2.5
            feedback_parts.append(f"✅ Added {type_hints_count} type hints")
        elif type_hints_count >= 10:
            points += 1.5
            feedback_parts.append(f"△ Added {type_hints_count} type hints (good progress)")
        elif type_hints_count >= 5:
            points += 0.5
            feedback_parts.append(f"△ Added {type_hints_count} type hints (need 15+ for full credit)")
        else:
            feedback_parts.append(f"❌ Only {type_hints_count} type hints added")
        
        # Criterion 3: Check for suppression comments (1.5 points)
        suppression_count = 0
        for filename, filepath in copied_files.items():
            content = read_file_content(filepath)
            suppression_count += content.count("# type: ignore")
            suppression_count += content.count("# pylint: disable")
            suppression_count += content.count("# noqa")
        
        if suppression_count >= 1:
            points += 1.5
            feedback_parts.append(f"✅ Added {suppression_count} suppression comment(s)")
        else:
            feedback_parts.append("❌ No suppression comments found")
        
        # Criterion 4: Check critical errors are fixed (3 points)
        critical_fixes = 0
        max_critical = 4
        
        # Check 4.1: models.py should have type hints in __init__
        if "models.py" in copied_files:
            content = read_file_content(copied_files["models.py"])
            if "def __init__(self, name: str, email: str, age: int)" in content:
                critical_fixes += 1
            elif (": str" in content or ": int" in content) and "def __init__" in content:
                critical_fixes += 0.5
        
        # Check 4.2: database.py should fix undefined_count error
        if "database.py" in copied_files:
            content = read_file_content(copied_files["database.py"])
            if "undefined_count" not in content or "# type: ignore" in content:
                critical_fixes += 1
            elif "undefined_count = " in content:
                critical_fixes += 1
        
        # Check 4.3: test_models.py should fix import error
        if "test_models.py" in copied_files:
            content = read_file_content(copied_files["test_models.py"])
            if "from src.models import" in content:
                critical_fixes += 1
            elif "# type: ignore" in content or "# noqa" in content:
                critical_fixes += 0.5
        
        # Check 4.4: api_client.py should initialize total variable
        if "api_client.py" in copied_files:
            content = read_file_content(copied_files["api_client.py"])
            if "total = 0" in content or "total: int = 0" in content:
                critical_fixes += 1
            elif "# type: ignore" in content or "total +=" not in content:
                critical_fixes += 0.5
        
        critical_score = (critical_fixes / max_critical) * 3.0
        points += critical_score
        
        if critical_fixes >= 3:
            feedback_parts.append(f"✅ Fixed {critical_fixes}/{max_critical} critical errors")
        elif critical_fixes >= 2:
            feedback_parts.append(f"△ Fixed {critical_fixes}/{max_critical} critical errors")
        else:
            feedback_parts.append(f"❌ Only fixed {critical_fixes}/{max_critical} critical errors")
        
        # Criterion 5: Check syntax validity (1 point)
        syntax_valid = True
        syntax_errors = []
        for filename, filepath in copied_files.items():
            try:
                result = subprocess.run(
                    ["python3", "-m", "py_compile", filepath],
                    capture_output=True,
                    timeout=5,
                    text=True
                )
                if result.returncode != 0:
                    syntax_valid = False
                    syntax_errors.append(filename)
            except Exception as e:
                logger.warning(f"Syntax check failed for {filename}: {e}")
                syntax_valid = False
                syntax_errors.append(filename)
        
        if syntax_valid:
            points += 1.0
            feedback_parts.append("✅ All files syntactically valid")
        else:
            feedback_parts.append(f"❌ Syntax errors in: {', '.join(syntax_errors)}")
        
        # Calculate final score
        score = int((points / max_points) * 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\nScore: {points:.1f}/{max_points} ({score}%)"
        
        if passed:
            feedback += "\n✅ Task completed successfully"
        else:
            feedback += "\n❌ Task incomplete - need 70% to pass"
        
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
