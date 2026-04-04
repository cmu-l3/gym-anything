#!/usr/bin/env python3
"""
Verifier for fix_import_errors@1 task
Checks that requirements.txt was correctly updated with missing packages
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_requirements(content):
    """
    Parse requirements.txt content into a list of package names
    
    Args:
        content: String content of requirements.txt
        
    Returns:
        List of package names (lowercase, without version specifiers)
    """
    packages = []
    for line in content.split('\n'):
        line = line.strip()
        
        # Skip empty lines and comments
        if not line or line.startswith('#'):
            continue
        
        # Extract package name (before ==, >=, <=, <, >, [, etc.)
        # Handle cases like: pandas>=1.5.0, numpy==1.23, matplotlib, requests[security]
        package = re.split(r'[=<>\[\s]', line)[0].strip()
        
        if package:
            packages.append(package.lower())
    
    return packages


def verify_fix_import_errors(traj, env_info, task_info):
    """
    Verify that requirements.txt was fixed correctly
    
    Checks:
    1. Contains 'requests' package
    2. Contains 'scikit-learn' (correct name)
    3. Does NOT contain 'sklearn' (wrong name)
    4. Still contains original packages (pandas, numpy, matplotlib)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info including copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='fix_import_verify_')
    
    try:
        # Copy requirements.txt from container
        requirements_container_path = "/tmp/requirements.txt"
        local_requirements = os.path.join(temp_dir, "requirements.txt")
        
        try:
            copy_from_env(requirements_container_path, local_requirements)
        except Exception as e:
            logger.error(f"Failed to copy requirements.txt: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy requirements.txt: {e}"
            }
        
        # Check if file exists and is readable
        if not os.path.exists(local_requirements) or os.path.getsize(local_requirements) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ requirements.txt not found or is empty"
            }
        
        # Read requirements.txt content
        content = read_file_content(local_requirements)
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ requirements.txt is empty"
            }
        
        logger.info(f"Requirements content:\n{content}")
        
        # Parse package names
        packages = parse_requirements(content)
        logger.info(f"Parsed packages: {packages}")
        
        # Track criteria
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Must contain 'requests'
        has_requests = 'requests' in packages
        if has_requests:
            criteria_passed += 1
            feedback_parts.append("✅ 'requests' package present")
        else:
            feedback_parts.append("❌ Missing 'requests' package (required by script)")
        
        # Criterion 2: Must contain 'scikit-learn' (correct name)
        has_scikit_learn = 'scikit-learn' in packages
        if has_scikit_learn:
            criteria_passed += 1
            feedback_parts.append("✅ 'scikit-learn' package present (correct name)")
        else:
            feedback_parts.append("❌ Missing 'scikit-learn' package (correct package name)")
        
        # Criterion 3: Must NOT contain 'sklearn' (wrong name)
        has_sklearn_wrong = 'sklearn' in packages
        if not has_sklearn_wrong:
            criteria_passed += 1
            feedback_parts.append("✅ 'sklearn' (incorrect name) not present")
        else:
            feedback_parts.append("❌ Contains 'sklearn' but correct package name is 'scikit-learn'")
        
        # Criterion 4: Must contain 'pandas' (original package)
        has_pandas = 'pandas' in packages
        if has_pandas:
            criteria_passed += 1
            feedback_parts.append("✅ 'pandas' package preserved")
        else:
            feedback_parts.append("❌ Original 'pandas' package removed")
        
        # Criterion 5: Must contain 'numpy' (original package)
        has_numpy = 'numpy' in packages
        if has_numpy:
            criteria_passed += 1
            feedback_parts.append("✅ 'numpy' package preserved")
        else:
            feedback_parts.append("❌ Original 'numpy' package removed")
        
        # Criterion 6: Must contain 'matplotlib' (original package)
        has_matplotlib = 'matplotlib' in packages
        if has_matplotlib:
            criteria_passed += 1
            feedback_parts.append("✅ 'matplotlib' package preserved")
        else:
            feedback_parts.append("❌ Original 'matplotlib' package removed")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        
        # Task requires ALL criteria to pass (it's a simple fix task)
        passed = criteria_passed == total_criteria
        
        # Provide helpful feedback
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"✅ Perfect! All dependencies fixed correctly: {feedback}"
        else:
            feedback = f"Criteria: {criteria_passed}/{total_criteria} | {feedback}"
            
            # Add helpful hints
            if not has_requests:
                feedback += " | Hint: The script imports 'requests' - add it to requirements.txt"
            if not has_scikit_learn:
                feedback += " | Hint: The package is called 'scikit-learn' (install name), not 'sklearn' (import name)"
            if has_sklearn_wrong:
                feedback += " | Hint: Replace 'sklearn' with 'scikit-learn' - they are the same package"
        
        logger.info(f"Verification result: passed={passed}, score={score}, criteria={criteria_passed}/{total_criteria}")
        
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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
