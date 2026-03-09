#!/usr/bin/env python3
"""Utility functions for PyCharm task verification."""

import json
import logging
import os
import tempfile
from typing import Any, Dict, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def copy_and_read(copy_from_env, remote_path: str) -> Optional[str]:
    """Copy a file from the environment and read its contents.

    Args:
        copy_from_env: The copy function from env_info
        remote_path: Path to the file in the container

    Returns:
        File contents as string, or None if file doesn't exist/can't be read
    """
    tmp = None
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
        tmp.close()
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, 'r') as f:
            content = f.read()
        return content
    except Exception as e:
        logger.debug(f"Failed to read {remote_path}: {e}")
        return None
    finally:
        if tmp and os.path.exists(tmp.name):
            os.unlink(tmp.name)


def copy_and_read_binary(copy_from_env, remote_path: str) -> Optional[bytes]:
    """Copy a binary file from the environment and read its contents.

    Args:
        copy_from_env: The copy function from env_info
        remote_path: Path to the file in the container

    Returns:
        File contents as bytes, or None if file doesn't exist/can't be read
    """
    tmp = None
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
        tmp.close()
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, 'rb') as f:
            content = f.read()
        return content
    except Exception as e:
        logger.debug(f"Failed to read binary {remote_path}: {e}")
        return None
    finally:
        if tmp and os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_python_syntax(code: str) -> bool:
    """Check if Python code has valid syntax.

    Args:
        code: Python source code

    Returns:
        True if syntax is valid, False otherwise
    """
    try:
        compile(code, '<string>', 'exec')
        return True
    except SyntaxError:
        return False


def check_python_imports(code: str, required_imports: List[str]) -> Dict[str, bool]:
    """Check which required imports are present in Python code.

    Args:
        code: Python source code
        required_imports: List of module names to check for

    Returns:
        Dict mapping import names to whether they're present
    """
    import re
    results = {}
    for imp in required_imports:
        # Check for 'import X' or 'from X import' patterns
        pattern = rf'(?:^|\s)(?:import\s+{re.escape(imp)}|from\s+{re.escape(imp)}\s+import)'
        results[imp] = bool(re.search(pattern, code, re.MULTILINE))
    return results


def check_function_exists(code: str, function_name: str) -> bool:
    """Check if a function definition exists in Python code.

    Args:
        code: Python source code
        function_name: Name of the function to look for

    Returns:
        True if function is defined, False otherwise
    """
    import re
    pattern = rf'^\s*def\s+{re.escape(function_name)}\s*\('
    return bool(re.search(pattern, code, re.MULTILINE))


def check_class_exists(code: str, class_name: str) -> bool:
    """Check if a class definition exists in Python code.

    Args:
        code: Python source code
        class_name: Name of the class to look for

    Returns:
        True if class is defined, False otherwise
    """
    import re
    pattern = rf'^\s*class\s+{re.escape(class_name)}\s*[:\(]'
    return bool(re.search(pattern, code, re.MULTILINE))


def parse_pytest_output(output: str) -> Dict[str, Any]:
    """Parse pytest output to extract test results.

    Args:
        output: Raw pytest output string

    Returns:
        Dict with passed, failed, error counts and test details
    """
    import re

    result = {
        'passed': 0,
        'failed': 0,
        'errors': 0,
        'skipped': 0,
        'total': 0,
        'success': False,
        'test_details': []
    }

    # Parse summary line like "5 passed, 2 failed, 1 error in 1.23s"
    summary_match = re.search(
        r'(?:(\d+)\s+passed)?[,\s]*(?:(\d+)\s+failed)?[,\s]*(?:(\d+)\s+error)?[,\s]*(?:(\d+)\s+skipped)?',
        output
    )

    if summary_match:
        result['passed'] = int(summary_match.group(1) or 0)
        result['failed'] = int(summary_match.group(2) or 0)
        result['errors'] = int(summary_match.group(3) or 0)
        result['skipped'] = int(summary_match.group(4) or 0)
        result['total'] = result['passed'] + result['failed'] + result['errors']
        result['success'] = result['failed'] == 0 and result['errors'] == 0 and result['passed'] > 0

    # Parse individual test results
    test_pattern = r'(test_\w+)\s+(PASSED|FAILED|ERROR|SKIPPED)'
    for match in re.finditer(test_pattern, output):
        result['test_details'].append({
            'name': match.group(1),
            'status': match.group(2)
        })

    return result


def parse_requirements_txt(content: str) -> List[Dict[str, str]]:
    """Parse requirements.txt content into a list of package specs.

    Args:
        content: requirements.txt file content

    Returns:
        List of dicts with 'name' and 'version' keys
    """
    import re
    packages = []

    for line in content.strip().split('\n'):
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('-'):
            continue

        # Parse package==version or package>=version etc.
        match = re.match(r'^([a-zA-Z0-9_-]+)(?:([<>=!]+)(.+))?$', line)
        if match:
            packages.append({
                'name': match.group(1),
                'operator': match.group(2) or '',
                'version': match.group(3) or ''
            })

    return packages


def vlm_verify_pycharm_task(
    traj: Any,
    env_info: Dict[str, Any],
    task_description: str,
    checklist_items: List[str]
) -> Optional[Dict[str, Any]]:
    """Use VLM to verify PyCharm task completion based on screenshots.

    This is a placeholder that can be connected to an actual VLM API.

    Args:
        traj: Trajectory object (may contain screenshots)
        env_info: Environment info dict
        task_description: Description of what the task should accomplish
        checklist_items: List of visual indicators to check for

    Returns:
        Dict with vlm_passed, vlm_score, vlm_feedback, or None if VLM not available
    """
    # This is a stub - actual VLM integration would go here
    # For now, return None to indicate VLM verification is not performed
    try:
        # Try to import VLM verification if available
        from gym_anything.verification.vlm import query_vlm

        # Get final screenshot from trajectory if available
        if hasattr(traj, 'final_screenshot'):
            screenshot_path = traj.final_screenshot
        else:
            # Look in episode directory
            episode_dir = env_info.get('episode_dir', '')
            screenshot_path = os.path.join(episode_dir, 'final.png')
            if not os.path.exists(screenshot_path):
                return None

        prompt = f"""Analyze this PyCharm screenshot and evaluate task completion.

Task: {task_description}

Checklist to verify:
{chr(10).join(f"- {item}" for item in checklist_items)}

For each checklist item, indicate if it appears to be satisfied (YES/NO/UNCLEAR).
Then provide an overall assessment: PASS if most items are satisfied, FAIL otherwise.
"""

        response = query_vlm(screenshot_path, prompt)

        # Parse VLM response
        passed = 'PASS' in response.upper() and 'FAIL' not in response.upper()

        # Count satisfied items
        yes_count = response.upper().count('YES')
        total_items = len(checklist_items)
        score = int((yes_count / total_items) * 100) if total_items > 0 else 0

        return {
            'vlm_passed': passed,
            'vlm_score': score,
            'vlm_feedback': f"VLM: {yes_count}/{total_items} checklist items verified"
        }

    except Exception as e:
        logger.debug(f"VLM verification not available: {e}")
        return None
