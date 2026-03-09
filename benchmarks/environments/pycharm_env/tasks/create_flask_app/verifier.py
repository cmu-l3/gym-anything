#!/usr/bin/env python3
"""Verifier for create_flask_app task.

This verifier includes safeguards against pre-baked solutions:
1. Trajectory validation - requires file CREATION actions (not just navigation)
2. File timestamp validation - files must be created during episode
3. Content validation - proper Flask app structure
4. PyCharm project structure validation - .idea folder must exist
5. Code content validation - rejects trivial modifications to pre-existing code
"""

import json
import tempfile
import os
import re
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Minimum number of meaningful steps required for this task
# Creating a Flask project via PyCharm GUI realistically requires 20+ actions:
# - Navigate PyCharm menus to create/open project (3-5 clicks)
# - Create files via File > New or Alt+Insert (2-3 actions per file x 3 files)
# - Type code content in editor (multiple type actions for 3 files)
# - Save files (Ctrl+S actions)
# - Run tests via Run menu or right-click (2-3 actions)
MIN_MEANINGFUL_STEPS = 20

# Minimum number of GUI clicks required
# Creating a proper Flask project via GUI requires multiple clicks:
# - New Project or Open button
# - File > New for each file (or Alt+Insert)
# - Run tests
MIN_GUI_CLICKS = 5

# Minimum characters typed - creating Flask app from scratch requires typing code
# app.py (~200 chars) + test_app.py (~300 chars) + requirements.txt (~30 chars) = ~530 chars
MIN_TYPED_CHARACTERS = 300


def verify_create_flask_app(traj, env_info, task_info):
    """Verify that a Flask application was created with correct structure.

    Criteria:
    1. app.py exists with Flask app, '/' route, and '/greet/<name>' route (35 pts)
    2. test_app.py exists with at least 2 pytest tests (25 pts)
    3. requirements.txt exists with Flask dependency (10 pts)
    4. All tests pass when run with pytest (30 pts)

    Anti-cheat validation:
    - Trajectory must show file CREATION (not just navigation to existing files)
    - Must have minimum GUI clicks (file creation requires clicks)
    - Must type substantial code content
    - Files must have been modified during the episode (timestamp check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/PycharmProjects/hello_flask')

    # Get episode start time from env_info or task_info
    episode_start_ts = env_info.get('episode_start_ts', 0)
    if not episode_start_ts:
        # Try to get from trajectory
        if traj and len(traj) > 0:
            first_event = traj[0] if isinstance(traj, list) else None
            if first_event and isinstance(first_event, dict):
                episode_start_ts = first_event.get('ts', 0)

    score = 0
    feedback_parts = []

    # === ANTI-CHEAT: Trajectory Validation ===
    step_count = 0
    meaningful_actions = 0
    gui_clicks = 0  # Track GUI clicks specifically
    type_actions = 0  # Track typing actions
    total_typed_chars = 0  # Track total characters typed

    # Track specific action patterns for file creation detection
    file_creation_indicators = 0  # Actions that indicate new file creation
    file_navigation_only = 0  # Actions that only navigate to existing files

    # Key combinations that indicate file creation in PyCharm
    FILE_CREATION_KEYS = [
        'alt+insert',  # New... menu
        'alt+shift+insert',  # New file
    ]

    # Key combinations that only navigate (suspicious if no creation)
    NAVIGATION_ONLY_KEYS = [
        'ctrl+shift+n',  # Go to File (searches existing files)
        'ctrl+n',  # Go to Class
        'ctrl+e',  # Recent files
        'alt+1',  # Project panel (view existing structure)
    ]

    # The trajectory is passed as a dict with "steps" key containing events
    traj_steps = []
    if isinstance(traj, dict):
        traj_steps = traj.get('steps', [])
    elif isinstance(traj, list):
        traj_steps = traj

    for event in traj_steps:
        if isinstance(event, dict) and event.get('event') == 'step':
            step_count += 1
            action = event.get('action', [])
            # Count meaningful actions (not just Escape or empty)
            if action:
                for a in (action if isinstance(action, list) else [action]):
                    if isinstance(a, dict):
                        action_type = a.get('type', '')
                        # Filter out trivial actions
                        if action_type == 'key':
                            key = a.get('key', '').lower()
                            if key not in ['escape', 'esc', '']:
                                meaningful_actions += 1
                                # Check for file creation vs navigation patterns
                                if key in FILE_CREATION_KEYS:
                                    file_creation_indicators += 1
                                elif key in NAVIGATION_ONLY_KEYS:
                                    file_navigation_only += 1
                        elif action_type == 'click':
                            meaningful_actions += 1
                            gui_clicks += 1
                        elif action_type == 'type':
                            meaningful_actions += 1
                            type_actions += 1
                            text = a.get('text', '')
                            total_typed_chars += len(text)
                        elif action_type in ['scroll', 'drag']:
                            meaningful_actions += 1
                            gui_clicks += 1

    logger.info(f"Trajectory validation: {step_count} steps, {meaningful_actions} meaningful actions, "
                f"{gui_clicks} GUI clicks, {total_typed_chars} chars typed")
    logger.info(f"File creation indicators: {file_creation_indicators}, Navigation-only: {file_navigation_only}")

    # === ANTI-CHEAT: Reject trajectories that only navigate without creating ===
    if file_navigation_only > 0 and file_creation_indicators == 0 and gui_clicks < 3:
        feedback_parts.append(f"FAILED: Trajectory shows file NAVIGATION (ctrl+shift+n) without file CREATION. "
                             f"Files must be created via PyCharm's File > New menu or Alt+Insert, not by navigating to pre-existing files.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    if meaningful_actions < MIN_MEANINGFUL_STEPS:
        feedback_parts.append(f"FAILED: Insufficient agent actions ({meaningful_actions} < {MIN_MEANINGFUL_STEPS} required)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Check for minimum GUI clicks - file creation requires clicks
    if gui_clicks < MIN_GUI_CLICKS:
        feedback_parts.append(f"FAILED: Insufficient GUI clicks ({gui_clicks} < {MIN_GUI_CLICKS} required). "
                             f"Creating files via PyCharm GUI requires clicking on menus/dialogs.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Check for minimum typed characters - creating code from scratch requires typing
    if total_typed_chars < MIN_TYPED_CHARACTERS:
        feedback_parts.append(f"FAILED: Insufficient code typed ({total_typed_chars} < {MIN_TYPED_CHARACTERS} chars required). "
                             f"Creating Flask app from scratch requires typing substantial code.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    feedback_parts.append(f"Trajectory OK: {meaningful_actions} actions, {gui_clicks} clicks, {total_typed_chars} chars typed")

    def copy_and_read(remote_path):
        """Copy a file from the environment and read its contents."""
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            try:
                if os.path.exists(tmp.name):
                    os.unlink(tmp.name)
            except:
                pass
            return None

    def file_exists(remote_path):
        """Check if a file exists in the environment."""
        content = copy_and_read(remote_path)
        return content is not None

    # === ANTI-CHEAT: PyCharm Project Structure Validation ===
    # Check that .idea folder exists (created when PyCharm opens a project)
    idea_misc = copy_and_read(f"{project_dir}/.idea/misc.xml")
    idea_modules = copy_and_read(f"{project_dir}/.idea/modules.xml")
    idea_iml = copy_and_read(f"{project_dir}/.idea/hello_flask.iml") or copy_and_read(f"{project_dir}/hello_flask.iml")

    pycharm_project_valid = idea_misc is not None or idea_modules is not None or idea_iml is not None

    if not pycharm_project_valid:
        # Also check if project was opened (workspace.xml created)
        idea_workspace = copy_and_read(f"{project_dir}/.idea/workspace.xml")
        pycharm_project_valid = idea_workspace is not None

    if not pycharm_project_valid:
        feedback_parts.append("FAILED: No PyCharm project structure found (.idea folder missing). Project must be opened/created in PyCharm GUI.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    feedback_parts.append("PyCharm project structure verified (.idea folder exists)")

    def get_file_mtime(remote_path):
        """Get modification time of a file in the environment."""
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            mtime = os.path.getmtime(tmp.name)
            os.unlink(tmp.name)
            return mtime
        except Exception as e:
            logger.debug(f"Failed to get mtime for {remote_path}: {e}")
            return None

    # First try to read the exported result JSON
    result_json = copy_and_read("/tmp/task_result.json")
    if result_json:
        try:
            result = json.loads(result_json)
        except json.JSONDecodeError:
            result = {}
    else:
        result = {}

    # === ANTI-CHEAT: File Timestamp Validation ===
    # Check if files were created/modified during this episode
    if episode_start_ts > 0:
        files_to_check = [
            f"{project_dir}/app.py",
            f"{project_dir}/test_app.py",
            f"{project_dir}/requirements.txt"
        ]

        files_created_during_episode = 0
        for filepath in files_to_check:
            mtime = get_file_mtime(filepath)
            if mtime and mtime >= episode_start_ts - 5:  # Allow only 5s tolerance to prevent pre-baked solutions
                files_created_during_episode += 1
                logger.info(f"File {filepath} created during episode (mtime={mtime}, start={episode_start_ts})")
            elif mtime:
                logger.warning(f"File {filepath} existed BEFORE episode (mtime={mtime}, start={episode_start_ts})")

        if files_created_during_episode == 0:
            feedback_parts.append("FAILED: No files created during this episode (pre-existing solution detected)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        feedback_parts.append(f"Timestamp OK: {files_created_during_episode}/3 files created during episode")

    # Track validation state with boolean flags (not string matching)
    has_valid_app = False
    has_valid_tests = False
    tests_actually_passed = False

    # --- Criterion 1: app.py (35 points) ---
    app_content = copy_and_read(f"{project_dir}/app.py")
    if app_content:
        app_score = 0

        # === ANTI-CHEAT: Reject trivial code that's just comments ===
        # Strip comments and whitespace to check actual code content
        code_lines = [line for line in app_content.split('\n')
                     if line.strip() and not line.strip().startswith('#')]
        actual_code_chars = sum(len(line) for line in code_lines)

        if actual_code_chars < 100:  # Minimum actual code (not comments)
            feedback_parts.append(f"FAILED: app.py contains insufficient code ({actual_code_chars} chars). "
                                 f"Appears to be mostly comments or trivial modifications.")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Check for Flask import
        if re.search(r'from\s+flask\s+import\s+Flask|import\s+flask', app_content, re.IGNORECASE):
            app_score += 5
            feedback_parts.append("Flask import found")

        # Check for Flask app creation
        if re.search(r'Flask\s*\(\s*__name__\s*\)|Flask\s*\(\s*["\']', app_content):
            app_score += 5
            feedback_parts.append("Flask app created")

        # Check for '/' route
        if re.search(r'@\w+\.route\s*\(\s*["\']\/["\']\s*\)', app_content):
            app_score += 10
            # Check if it returns Hello World
            if re.search(r'["\']Hello,?\s*World!?["\']', app_content, re.IGNORECASE):
                app_score += 5
                feedback_parts.append("'/' route returns Hello World")
            else:
                feedback_parts.append("'/' route exists but may not return Hello World")
        else:
            feedback_parts.append("'/' route not found")

        # Check for '/greet/<name>' route
        if re.search(r'@\w+\.route\s*\(\s*["\']\/greet\/<\w+>["\']', app_content):
            app_score += 10
            feedback_parts.append("'/greet/<name>' route found")
        elif re.search(r'@\w+\.route\s*\(\s*["\']\/greet', app_content):
            app_score += 5
            feedback_parts.append("'/greet' route found (may not have parameter)")
        else:
            feedback_parts.append("'/greet/<name>' route not found")

        score += app_score
        feedback_parts.append(f"app.py: {app_score}/35 pts")
        # Mark as valid if we got at least 25 points (has routes)
        if app_score >= 25:
            has_valid_app = True
    else:
        feedback_parts.append("app.py not found")

    # --- Criterion 2: test_app.py (25 points) ---
    test_content = copy_and_read(f"{project_dir}/test_app.py")
    if test_content:
        test_score = 0

        # === ANTI-CHEAT: Reject trivial test code ===
        code_lines = [line for line in test_content.split('\n')
                     if line.strip() and not line.strip().startswith('#')]
        actual_code_chars = sum(len(line) for line in code_lines)

        if actual_code_chars < 150:  # Minimum actual test code
            feedback_parts.append(f"FAILED: test_app.py contains insufficient code ({actual_code_chars} chars).")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Check for pytest import or test functions
        has_pytest_import = bool(re.search(r'import\s+pytest|from\s+pytest', test_content))
        if has_pytest_import:
            test_score += 5

        # Count test functions
        test_functions = re.findall(r'def\s+(test_\w+)\s*\(', test_content)
        num_tests = len(test_functions)

        if num_tests >= 2:
            test_score += 15
            feedback_parts.append(f"Found {num_tests} test functions")
        elif num_tests == 1:
            test_score += 8
            feedback_parts.append(f"Found only 1 test function (need at least 2)")
        else:
            feedback_parts.append("No test functions found")

        # Check for Flask test client usage
        if re.search(r'\.test_client\(\)|client\.get|client\.post', test_content):
            test_score += 5
            feedback_parts.append("Flask test client used")

        score += test_score
        feedback_parts.append(f"test_app.py: {test_score}/25 pts")
        # Mark as valid if we got at least 15 points (has 2+ test functions)
        if test_score >= 15:
            has_valid_tests = True
    else:
        feedback_parts.append("test_app.py not found")

    # --- Criterion 3: requirements.txt (10 points) ---
    req_content = copy_and_read(f"{project_dir}/requirements.txt")
    if req_content:
        req_score = 0

        # Check for Flask dependency
        if re.search(r'^flask', req_content, re.MULTILINE | re.IGNORECASE):
            req_score += 10
            feedback_parts.append("Flask in requirements.txt")
        else:
            req_score += 5  # Partial credit for having requirements.txt
            feedback_parts.append("requirements.txt exists but Flask not found")

        score += req_score
    else:
        feedback_parts.append("requirements.txt not found")

    # --- Criterion 4: Tests pass (30 points) ---
    # Use the result from export script if available
    tests_pass = result.get('tests_pass', False)
    pytest_output = result.get('pytest_output', '')

    if tests_pass:
        score += 30
        feedback_parts.append("All tests pass")
        tests_actually_passed = True
    elif pytest_output:
        # Parse pytest output to see if any tests passed
        passed_match = re.search(r'(\d+)\s+passed', pytest_output)
        failed_match = re.search(r'(\d+)\s+failed', pytest_output)

        if passed_match:
            passed_count = int(passed_match.group(1))
            failed_count = int(failed_match.group(1)) if failed_match else 0

            if passed_count > 0 and failed_count == 0:
                score += 30
                feedback_parts.append(f"All {passed_count} tests pass")
                tests_actually_passed = True
            elif passed_count > 0:
                # Partial credit for some passing tests
                partial = int(15 * passed_count / (passed_count + failed_count))
                score += partial
                feedback_parts.append(f"{passed_count} passed, {failed_count} failed")
            else:
                feedback_parts.append("Tests failed to pass")
        else:
            feedback_parts.append("Could not parse pytest output")
    else:
        feedback_parts.append("Tests not run or failed")

    # --- VLM Verification (bonus) ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from pycharm_verification_utils import vlm_verify_pycharm_task

        vlm_result = vlm_verify_pycharm_task(
            traj, env_info,
            task_description="Create a Flask web application (hello_flask) in PyCharm with app.py, "
                           "test_app.py, and requirements.txt. Run tests with pytest.",
            checklist_items=[
                "PyCharm is open and visible",
                "A Python project structure is visible in the project explorer",
                "An app.py or main Python file is open or visible",
                "A test file is visible in the project",
                "No errors are visible in the IDE",
            ]
        )
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                score = min(score + 10, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Determine pass/fail using boolean flags (not fragile string matching)
    # Must have valid app.py with routes AND valid tests AND tests must pass
    passed = score >= 70 and has_valid_app and has_valid_tests and tests_actually_passed

    if not tests_actually_passed and score >= 50:
        feedback_parts.append("NOTE: Task incomplete without passing tests")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
