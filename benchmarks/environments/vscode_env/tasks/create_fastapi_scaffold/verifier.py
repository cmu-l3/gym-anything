#!/usr/bin/env python3
"""
Verifier for Create FastAPI Scaffold task
"""

import sys
import os
import logging
import tempfile
import shutil
import ast

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_toml_file(filepath):
    """Parse TOML file with fallback for missing library"""
    try:
        import tomli
        with open(filepath, 'rb') as f:
            return tomli.load(f)
    except ImportError:
        try:
            import toml
            with open(filepath, 'r') as f:
                return toml.load(f)
        except ImportError:
            # Fallback: basic manual parsing for simple TOML
            logger.warning("No TOML library available, using basic parsing")
            config = {}
            with open(filepath, 'r') as f:
                content = f.read()
                # Very basic check
                if '[project]' in content or '[tool.poetry]' in content:
                    config['_has_project_section'] = True
                if 'fastapi' in content.lower():
                    config['_has_fastapi'] = True
            return config


def verify_fastapi_scaffold(traj, env_info, task_info):
    """
    Verify that FastAPI project scaffold was created correctly.
    
    Checks 8 criteria:
    1. All required files exist
    2. Directory structure correct
    3. src/main.py has valid Python syntax
    4. FastAPI app instance created
    5. Health check endpoint exists
    6. pyproject.toml is valid TOML with metadata
    7. .gitignore contains Python exclusions
    8. Dockerfile has essential instructions
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace_base = "/home/ga/workspace/notification_service"
    
    # Required files to check
    required_files = [
        "src/__init__.py",
        "src/main.py",
        "tests/__init__.py",
        "tests/test_main.py",
        "pyproject.toml",
        ".gitignore",
        "Dockerfile",
        "README.md"
    ]
    
    required_dirs = ["src", "tests", "docs"]
    
    temp_dir = tempfile.mkdtemp(prefix='fastapi_scaffold_verify_')
    
    try:
        criteria_results = {
            "all_files_exist": False,
            "directory_structure": False,
            "main_syntax_valid": False,
            "fastapi_app_created": False,
            "health_endpoint_exists": False,
            "pyproject_valid": False,
            "gitignore_valid": False,
            "dockerfile_valid": False
        }
        
        feedback_parts = []
        
        # Create local directory structure
        os.makedirs(os.path.join(temp_dir, "src"), exist_ok=True)
        os.makedirs(os.path.join(temp_dir, "tests"), exist_ok=True)
        os.makedirs(os.path.join(temp_dir, "docs"), exist_ok=True)
        
        # Copy all required files
        files_copied = 0
        missing_files = []
        
        for file_path in required_files:
            container_path = os.path.join(workspace_base, file_path)
            local_path = os.path.join(temp_dir, file_path)
            
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) >= 0:
                    files_copied += 1
                else:
                    missing_files.append(file_path)
            except Exception as e:
                logger.warning(f"Failed to copy {file_path}: {e}")
                missing_files.append(file_path)
        
        # Criterion 1: All required files exist
        if files_copied >= 7:  # Allow for 1 optional file
            criteria_results["all_files_exist"] = True
            feedback_parts.append(f"✅ Found {files_copied}/8 required files")
        else:
            feedback_parts.append(f"❌ Only {files_copied}/8 files exist. Missing: {', '.join(missing_files[:3])}")
        
        # Criterion 2: Check directory structure (check if directories exist in container)
        dirs_exist = 0
        for dir_name in required_dirs:
            dir_path = os.path.join(workspace_base, dir_name)
            # Try to copy a marker to see if directory exists
            try:
                # Check by trying to list directory or checking if __init__.py exists in src/tests
                if dir_name == "src":
                    test_file = os.path.join(workspace_base, "src/__init__.py")
                elif dir_name == "tests":
                    test_file = os.path.join(workspace_base, "tests/__init__.py")
                else:
                    test_file = os.path.join(workspace_base, "docs/README.md")
                
                # If we can copy a file from that directory, it exists
                if dir_name == "src" and os.path.exists(os.path.join(temp_dir, "src/__init__.py")):
                    dirs_exist += 1
                elif dir_name == "tests" and os.path.exists(os.path.join(temp_dir, "tests/__init__.py")):
                    dirs_exist += 1
                elif dir_name == "docs":
                    # Try to copy docs/README.md
                    docs_readme_local = os.path.join(temp_dir, "docs/README.md")
                    try:
                        copy_from_env(os.path.join(workspace_base, "docs/README.md"), docs_readme_local)
                        if os.path.exists(docs_readme_local):
                            dirs_exist += 1
                    except:
                        pass
            except:
                pass
        
        if dirs_exist >= 2:  # At least src/ and tests/ should exist
            criteria_results["directory_structure"] = True
            feedback_parts.append(f"✅ Directory structure correct ({dirs_exist}/3 dirs)")
        else:
            feedback_parts.append(f"❌ Directory structure incomplete ({dirs_exist}/3 dirs)")
        
        # Criterion 3, 4, 5: Validate src/main.py
        main_py_path = os.path.join(temp_dir, "src/main.py")
        if os.path.exists(main_py_path) and os.path.getsize(main_py_path) > 0:
            try:
                content = read_file_content(main_py_path)
                
                # Check syntax with AST
                try:
                    ast.parse(content)
                    criteria_results["main_syntax_valid"] = True
                    feedback_parts.append("✅ src/main.py has valid Python syntax")
                except SyntaxError as e:
                    feedback_parts.append(f"❌ src/main.py has syntax errors: {str(e)[:50]}")
                
                # Check for FastAPI app creation
                content_normalized = content.replace(" ", "").replace("\n", " ")
                has_fastapi_import = "FastAPI" in content or "fastapi" in content.lower()
                has_app_creation = "app=FastAPI()" in content_normalized or "app =FastAPI()" in content_normalized or ("app=" in content and "FastAPI" in content)
                
                if has_fastapi_import and has_app_creation:
                    criteria_results["fastapi_app_created"] = True
                    feedback_parts.append("✅ FastAPI app instance created")
                else:
                    feedback_parts.append(f"❌ FastAPI app not properly initialized (import={has_fastapi_import}, app={has_app_creation})")
                
                # Check for health endpoint
                has_decorator = "@app.get" in content or "@app.route" in content or "@app.api_route" in content
                has_health = "health" in content.lower() and ("/health" in content or '"/health"' in content or "'/health'" in content)
                has_status_return = '"status"' in content or "'status'" in content
                
                if has_decorator and has_health:
                    criteria_results["health_endpoint_exists"] = True
                    feedback_parts.append("✅ Health check endpoint defined")
                else:
                    feedback_parts.append(f"❌ Health endpoint missing (decorator={has_decorator}, health={has_health})")
                    
            except Exception as e:
                feedback_parts.append(f"❌ Error reading src/main.py: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ src/main.py not found or empty")
        
        # Criterion 6: Validate pyproject.toml
        pyproject_path = os.path.join(temp_dir, "pyproject.toml")
        if os.path.exists(pyproject_path) and os.path.getsize(pyproject_path) > 0:
            try:
                config = parse_toml_file(pyproject_path)
                
                has_project = ("project" in config or "tool" in config or 
                             config.get("_has_project_section", False))
                content_lower = read_file_content(pyproject_path).lower()
                has_fastapi = "fastapi" in content_lower
                
                if has_project and has_fastapi:
                    criteria_results["pyproject_valid"] = True
                    feedback_parts.append("✅ pyproject.toml valid with fastapi dependency")
                else:
                    feedback_parts.append(f"❌ pyproject.toml incomplete (project_section={has_project}, fastapi={has_fastapi})")
            except Exception as e:
                feedback_parts.append(f"❌ pyproject.toml parse error: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ pyproject.toml not found or empty")
        
        # Criterion 7: Validate .gitignore
        gitignore_path = os.path.join(temp_dir, ".gitignore")
        if os.path.exists(gitignore_path) and os.path.getsize(gitignore_path) > 0:
            content = read_file_content(gitignore_path).lower()
            
            python_patterns = ["__pycache__", ".pyc", ".venv", ".pytest_cache", ".env", "*.pyc", "venv/"]
            matches = sum(1 for pattern in python_patterns if pattern in content)
            
            if matches >= 3:
                criteria_results["gitignore_valid"] = True
                feedback_parts.append(f"✅ .gitignore has {matches} Python exclusions")
            else:
                feedback_parts.append(f"❌ .gitignore has only {matches}/3+ Python patterns")
        else:
            feedback_parts.append("❌ .gitignore not found or empty")
        
        # Criterion 8: Validate Dockerfile
        dockerfile_path = os.path.join(temp_dir, "Dockerfile")
        if os.path.exists(dockerfile_path) and os.path.getsize(dockerfile_path) > 0:
            content = read_file_content(dockerfile_path)
            lines = [l.strip() for l in content.split('\n') if l.strip() and not l.strip().startswith('#')]
            
            has_from = any(line.upper().startswith("FROM") and "python" in line.lower() for line in lines)
            has_cmd = any(line.upper().startswith(("CMD", "ENTRYPOINT")) for line in lines)
            enough_lines = len(lines) >= 3  # At least FROM, WORKDIR/COPY, CMD
            
            if has_from and has_cmd and enough_lines:
                criteria_results["dockerfile_valid"] = True
                feedback_parts.append(f"✅ Dockerfile valid ({len(lines)} instructions)")
            else:
                feedback_parts.append(f"❌ Dockerfile incomplete (FROM={has_from}, CMD={has_cmd}, lines={len(lines)})")
        else:
            feedback_parts.append("❌ Dockerfile not found or empty")
        
        # Calculate score
        passed_criteria = sum(criteria_results.values())
        total_criteria = len(criteria_results)
        score = int((passed_criteria / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria
        
        # Generate final feedback
        summary = f"Passed {passed_criteria}/{total_criteria} criteria"
        
        if passed:
            final_feedback = f"✅ {summary} - Project scaffold successfully created!\n" + "\n".join(feedback_parts)
        else:
            final_feedback = f"❌ {summary} - Scaffold incomplete or incorrect\n" + "\n".join(feedback_parts)
        
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
