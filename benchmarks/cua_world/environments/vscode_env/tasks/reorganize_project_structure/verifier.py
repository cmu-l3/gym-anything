#!/usr/bin/env python3
"""
Verifier for Reorganize Project Structure task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_project_reorganization(traj, env_info, task_info):
    """
    Verify that project was reorganized correctly.
    
    Checks:
    1. Correct directory structure exists (src/, utils/, tests/, config/)
    2. Files are in correct locations
    3. Old root files are removed (not duplicated)
    4. Import statements are updated correctly
    5. __init__.py files exist where needed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_reorg_')
    
    try:
        base_path = "/home/ga/workspace/messy_project"
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # ===== Criterion 1: Verify directory structure exists =====
        required_dirs = ["src", "utils", "tests", "config"]
        all_dirs_exist = True
        missing_dirs = []
        
        for dir_name in required_dirs:
            dir_path = f"{base_path}/{dir_name}"
            temp_check = tempfile.NamedTemporaryFile(delete=False)
            try:
                # Try to copy a marker file or list directory
                # We'll use a workaround: try to copy __init__.py or check if directory listing works
                copy_from_env(f"{dir_path}/", temp_check.name)
            except:
                # If directory doesn't exist, this will fail
                pass
            
            # Better approach: check if files exist in that directory
            # We'll verify this by checking if the expected files in those directories exist
            finally:
                if os.path.exists(temp_check.name):
                    os.unlink(temp_check.name)
        
        # We'll verify directory structure by checking if files exist in correct locations
        # This implicitly verifies directories exist
        
        # ===== Criterion 2: Verify files are in correct locations =====
        expected_files = {
            f"{base_path}/src/app.py": "Main app file",
            f"{base_path}/utils/helpers.py": "Helpers file",
            f"{base_path}/tests/test_app.py": "Test file",
            f"{base_path}/config/settings.ini": "Config file",
        }
        
        files_in_correct_location = True
        missing_files = []
        
        for filepath, description in expected_files.items():
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.basename(filepath))
            try:
                copy_from_env(filepath, temp_file.name)
                if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
                    files_in_correct_location = False
                    missing_files.append(description)
            except Exception as e:
                files_in_correct_location = False
                missing_files.append(description)
                logger.debug(f"Failed to copy {filepath}: {e}")
            finally:
                if os.path.exists(temp_file.name):
                    os.unlink(temp_file.name)
        
        if files_in_correct_location:
            criteria_passed += 1
            feedback_parts.append("✅ All files in correct locations (src/, utils/, tests/, config/)")
        else:
            feedback_parts.append(f"❌ Missing files in new locations: {', '.join(missing_files)}")
        
        # ===== Criterion 3: Verify old root files are removed =====
        old_files = [
            f"{base_path}/app.py",
            f"{base_path}/helpers.py",
            f"{base_path}/test_app.py",
            f"{base_path}/settings.ini"
        ]
        
        old_files_removed = True
        remaining_files = []
        
        for old_file in old_files:
            temp_file = tempfile.NamedTemporaryFile(delete=False)
            try:
                copy_from_env(old_file, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    old_files_removed = False
                    remaining_files.append(os.path.basename(old_file))
            except:
                # File doesn't exist (good!)
                pass
            finally:
                if os.path.exists(temp_file.name):
                    os.unlink(temp_file.name)
        
        if old_files_removed:
            criteria_passed += 1
            feedback_parts.append("✅ Old files removed from root directory")
        else:
            feedback_parts.append(f"❌ Old files still in root: {', '.join(remaining_files)}")
        
        # ===== Criterion 4: Verify import statements updated correctly =====
        # Check src/app.py imports
        app_import_correct = False
        temp_app = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env(f"{base_path}/src/app.py", temp_app.name)
            if os.path.exists(temp_app.name):
                app_content = read_file_content(temp_app.name)
                # Check for updated import: should be "from utils.helpers import" or "from utils import helpers"
                if ("from utils.helpers import" in app_content or 
                    "from utils import helpers" in app_content or
                    "import utils.helpers" in app_content):
                    app_import_correct = True
                    # Also verify old import is NOT present
                    if "from helpers import" in app_content and "from utils.helpers import" not in app_content:
                        app_import_correct = False
        except Exception as e:
            logger.debug(f"Failed to verify app.py imports: {e}")
        finally:
            if os.path.exists(temp_app.name):
                os.unlink(temp_app.name)
        
        # Check tests/test_app.py imports
        test_import_correct = False
        temp_test = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env(f"{base_path}/tests/test_app.py", temp_test.name)
            if os.path.exists(temp_test.name):
                test_content = read_file_content(temp_test.name)
                # Check for updated import: should be "from src.app import" or "from src import app"
                if ("from src.app import" in test_content or 
                    "from src import app" in test_content or
                    "import src.app" in test_content):
                    test_import_correct = True
                    # Also verify old import is NOT present
                    if "from app import" in test_content and "from src.app import" not in test_content:
                        test_import_correct = False
        except Exception as e:
            logger.debug(f"Failed to verify test_app.py imports: {e}")
        finally:
            if os.path.exists(temp_test.name):
                os.unlink(temp_test.name)
        
        if app_import_correct and test_import_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Import statements updated correctly in both files")
        else:
            issues = []
            if not app_import_correct:
                issues.append("src/app.py")
            if not test_import_correct:
                issues.append("tests/test_app.py")
            feedback_parts.append(f"❌ Imports not updated correctly in: {', '.join(issues)}")
        
        # ===== Criterion 5: Verify __init__.py files exist =====
        init_files = {
            f"{base_path}/src/__init__.py": "src package",
            f"{base_path}/utils/__init__.py": "utils package",
            f"{base_path}/tests/__init__.py": "tests package"
        }
        
        all_inits_exist = True
        missing_inits = []
        
        for init_path, description in init_files.items():
            temp_init = tempfile.NamedTemporaryFile(delete=False)
            try:
                copy_from_env(init_path, temp_init.name)
                if not os.path.exists(temp_init.name):
                    all_inits_exist = False
                    missing_inits.append(description)
            except:
                all_inits_exist = False
                missing_inits.append(description)
            finally:
                if os.path.exists(temp_init.name):
                    os.unlink(temp_init.name)
        
        if all_inits_exist:
            criteria_passed += 1
            feedback_parts.append("✅ __init__.py files present in all package directories")
        else:
            feedback_parts.append(f"❌ Missing __init__.py in: {', '.join(missing_inits)}")
        
        # ===== Calculate final score =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria  # All criteria must pass
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification result: {criteria_passed}/{total_criteria} criteria passed")
        
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
