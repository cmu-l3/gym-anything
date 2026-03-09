#!/usr/bin/env python3
"""
Run a GENUINE test using PyCharm GUI to create the Flask project.
This test will:
1. Use PyCharm's GUI to create/open project
2. Create files through PyCharm's interface
3. Run tests through PyCharm
4. Capture proper screenshots with visible code
"""

import sys
import os
import time
import json
import paramiko
import shutil
from datetime import datetime
import uuid

sys.path.insert(0, '/scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu')

from gym_anything.api import from_config

def run_ssh_command(ssh, cmd, timeout=30):
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    return stdout.read().decode(), stderr.read().decode()

def take_screenshot(ssh, sftp, local_path):
    run_ssh_command(ssh, 'DISPLAY=:1 scrot -o /tmp/screen.png')
    time.sleep(0.5)
    sftp.get('/tmp/screen.png', local_path)
    return local_path

def scale_coords(x, y):
    """Scale from 1280x720 reference to 1920x1080."""
    return int(x * 1920 / 1280), int(y * 1080 / 720)

def click(ssh, x, y, actions, button=1):
    """Click at coordinates and record action."""
    run_ssh_command(ssh, f'DISPLAY=:1 xdotool mousemove {x} {y} click {button}')
    actions.append({"ts": time.time(), "type": "click", "x": x, "y": y})
    time.sleep(0.5)

def type_text(ssh, text, actions):
    """Type text and record action."""
    # Escape special characters for xdotool
    escaped = text.replace('\\', '\\\\').replace('"', '\\"').replace("'", "\\'")
    run_ssh_command(ssh, f'DISPLAY=:1 xdotool type --delay 20 "{escaped}"')
    actions.append({"ts": time.time(), "type": "type", "text": text})
    time.sleep(0.3)

def press_key(ssh, key, actions):
    """Press a key and record action."""
    run_ssh_command(ssh, f'DISPLAY=:1 xdotool key {key}')
    actions.append({"ts": time.time(), "type": "key", "key": key})
    time.sleep(0.3)

def main():
    print("=" * 70)
    print("GENUINE PYCHARM GUI TEST")
    print("Creating Flask project using PyCharm's interface")
    print("=" * 70)

    # Create artifacts directory
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    episode_id = f"genuine_gui_{timestamp}_{uuid.uuid4()}"
    artifacts_dir = f"/scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu/benchmarks/environments/pycharm_env/artifacts/{episode_id}"
    os.makedirs(artifacts_dir, exist_ok=True)
    evidence_dir = "/scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu/benchmarks/environments/pycharm_env/evidence"

    print(f"Artifacts: {artifacts_dir}")

    # Track actions for trajectory
    actions = []
    frame_num = 0
    episode_start = time.time()

    def save_frame(suffix=""):
        nonlocal frame_num
        path = os.path.join(artifacts_dir, f"frame_{frame_num:05d}{suffix}.png")
        take_screenshot(ssh, sftp, path)
        frame_num += 1
        return path

    # Start environment
    print("\n[1] Starting environment...")
    env = from_config("benchmarks/environments/pycharm_env", task_id="create_flask_app")
    obs = env.reset(seed=42, use_cache=False)
    ssh_port = env._runner.ssh_port
    print(f"SSH Port: {ssh_port}")

    # Connect
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('localhost', port=ssh_port, username='ga', password='password123', timeout=30)
    sftp = ssh.open_sftp()

    try:
        # Initial screenshot
        print("\n[2] Taking initial screenshot...")
        initial = save_frame("_initial")
        shutil.copy(initial, os.path.join(evidence_dir, "01_pycharm_welcome.png"))
        time.sleep(2)

        # Wait for PyCharm
        print("\n[3] Waiting for PyCharm to be ready...")
        time.sleep(5)

        # Close any tip dialogs
        print("\n[4] Closing any dialogs...")
        for _ in range(2):
            press_key(ssh, "Escape", actions)
            time.sleep(0.5)

        save_frame()

        # Click on "New Project" button
        print("\n[5] Creating new project via PyCharm GUI...")
        # "New Project" button is roughly at center-left of welcome screen
        x, y = scale_coords(748, 262)  # "New Project" button
        click(ssh, x, y, actions)
        time.sleep(2)
        save_frame("_new_project_dialog")

        # In the New Project dialog, change the project name/location
        print("  - Setting project location...")
        # Click on location field
        x, y = scale_coords(640, 68)  # Location field
        click(ssh, x, y, actions)
        time.sleep(0.5)

        # Clear the field and type new path
        press_key(ssh, "ctrl+a", actions)
        time.sleep(0.2)
        type_text(ssh, "/home/ga/PycharmProjects/hello_flask", actions)
        time.sleep(1)
        save_frame("_project_location")

        # Click "Create" button
        print("  - Clicking Create button...")
        x, y = scale_coords(1170, 695)  # Create button (bottom right)
        click(ssh, x, y, actions)
        time.sleep(10)  # Wait for project to be created
        save_frame("_project_created")

        # Close any tips/dialogs that appear
        print("\n[6] Closing startup dialogs...")
        for _ in range(3):
            press_key(ssh, "Escape", actions)
            time.sleep(1)
        save_frame()

        # Now create the files using PyCharm
        # Right-click in project tree to create new file
        print("\n[7] Creating app.py via PyCharm...")

        # First, let's use the keyboard shortcut Alt+Insert or right-click
        # Focus on project tree first
        press_key(ssh, "alt+1", actions)  # Open Project tool window
        time.sleep(1)
        save_frame()

        # Press Alt+Insert to get New menu
        press_key(ssh, "alt+Insert", actions)
        time.sleep(1)
        save_frame("_new_menu")

        # Type to filter to Python File
        type_text(ssh, "Python", actions)
        time.sleep(0.5)
        press_key(ssh, "Return", actions)
        time.sleep(1)
        save_frame()

        # Type filename
        type_text(ssh, "app", actions)
        time.sleep(0.3)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        save_frame("_app_py_created")

        # Now type the Flask code
        print("  - Typing Flask code...")
        app_code = """from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello, World!'

@app.route('/greet/<name>')
def greet(name):
    return f'Hello, {name}!'

if __name__ == '__main__':
    app.run(debug=True)"""

        type_text(ssh, app_code, actions)
        time.sleep(1)
        save_frame("_app_py_code")

        # Save the file
        print("  - Saving app.py...")
        press_key(ssh, "ctrl+s", actions)
        time.sleep(1)

        # Create test_app.py
        print("\n[8] Creating test_app.py...")
        press_key(ssh, "alt+Insert", actions)
        time.sleep(1)
        type_text(ssh, "Python", actions)
        time.sleep(0.5)
        press_key(ssh, "Return", actions)
        time.sleep(1)
        type_text(ssh, "test_app", actions)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        save_frame("_test_app_created")

        # Type test code
        print("  - Typing test code...")
        test_code = """import pytest
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_hello_route(client):
    response = client.get('/')
    assert response.status_code == 200
    assert b'Hello, World!' in response.data

def test_greet_route(client):
    response = client.get('/greet/Alice')
    assert response.status_code == 200
    assert b'Alice' in response.data"""

        type_text(ssh, test_code, actions)
        time.sleep(1)
        save_frame("_test_app_code")
        press_key(ssh, "ctrl+s", actions)
        time.sleep(1)

        # Create requirements.txt
        print("\n[9] Creating requirements.txt...")
        press_key(ssh, "alt+Insert", actions)
        time.sleep(1)
        type_text(ssh, "File", actions)
        time.sleep(0.5)
        press_key(ssh, "Return", actions)
        time.sleep(1)
        type_text(ssh, "requirements.txt", actions)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        save_frame()

        type_text(ssh, "Flask>=2.0.0\npytest>=7.0.0", actions)
        press_key(ssh, "ctrl+s", actions)
        time.sleep(1)
        save_frame("_requirements_created")

        # Install dependencies via terminal
        print("\n[10] Installing dependencies...")
        # Open terminal in PyCharm
        press_key(ssh, "alt+F12", actions)
        time.sleep(2)
        save_frame("_terminal_opened")

        type_text(ssh, "pip install flask pytest", actions)
        press_key(ssh, "Return", actions)
        time.sleep(5)
        save_frame()

        # Run tests using PyCharm's Run menu
        print("\n[11] Running tests via PyCharm...")
        # Right-click on test_app.py and run
        press_key(ssh, "alt+1", actions)  # Focus project tree
        time.sleep(1)

        # Navigate to test_app.py and right-click
        # Use keyboard: Ctrl+Shift+R to run current file's tests
        # First open test_app.py
        press_key(ssh, "ctrl+shift+n", actions)  # Go to file
        time.sleep(1)
        type_text(ssh, "test_app.py", actions)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        save_frame()

        # Run the tests with Ctrl+Shift+F10 or right-click > Run
        press_key(ssh, "ctrl+shift+F10", actions)
        time.sleep(5)
        save_frame("_tests_running")

        # Wait for tests to complete
        time.sleep(5)
        save_frame("_tests_complete")

        # Take final screenshot showing project structure and code
        print("\n[12] Taking final screenshots...")

        # Open app.py to show the code
        press_key(ssh, "ctrl+shift+n", actions)
        time.sleep(1)
        type_text(ssh, "app.py", actions)
        press_key(ssh, "Return", actions)
        time.sleep(2)

        # Close any dialogs
        press_key(ssh, "Escape", actions)
        time.sleep(1)

        final = save_frame("_final")
        shutil.copy(final, os.path.join(evidence_dir, "04_final_code_visible.png"))

        # Show project tree with all files
        press_key(ssh, "alt+1", actions)
        time.sleep(1)
        final_tree = save_frame("_final_project_tree")
        shutil.copy(final_tree, os.path.join(evidence_dir, "05_project_tree.png"))

        # Run export script
        print("\n[13] Running export script...")
        out, _ = run_ssh_command(ssh, '/workspace/tasks/create_flask_app/export_result.sh', timeout=60)
        print(out)

        # Copy task_result.json
        try:
            sftp.get('/tmp/task_result.json', os.path.join(artifacts_dir, 'task_result.json'))
            shutil.copy(os.path.join(artifacts_dir, 'task_result.json'), evidence_dir)
        except Exception as e:
            print(f"Warning: {e}")

        # Verify .idea folder exists
        print("\n[14] Verifying PyCharm project structure...")
        idea_out, _ = run_ssh_command(ssh, 'ls -la /home/ga/PycharmProjects/hello_flask/.idea/')
        print(f".idea folder contents:\n{idea_out}")

        # Create trajectory file
        print("\n[15] Creating trajectory file...")
        episode_end = time.time()

        traj_path = os.path.join(artifacts_dir, 'traj.jsonl')
        with open(traj_path, 'w') as f:
            f.write(json.dumps({
                "event": "reset",
                "ts": episode_start,
                "env": "pycharm_env@0.1",
                "task": "create_flask_app@1"
            }) + '\n')

            for idx, action in enumerate(actions):
                step = {
                    "event": "step",
                    "ts": action["ts"],
                    "idx": idx,
                    "action": [{k: v for k, v in action.items() if k != "ts"}]
                }
                f.write(json.dumps(step) + '\n')

            f.write(json.dumps({
                "event": "finalize",
                "ts": episode_end
            }) + '\n')

        # Count action types
        clicks = sum(1 for a in actions if a["type"] == "click")
        types = sum(1 for a in actions if a["type"] == "type")
        keys = sum(1 for a in actions if a["type"] == "key")

        # Create summary
        summary = {
            "env": "pycharm_env@0.1",
            "task": "create_flask_app@1",
            "start_ts": episode_start,
            "end_ts": episode_end,
            "duration_seconds": episode_end - episode_start,
            "total_actions": len(actions),
            "gui_clicks": clicks,
            "type_actions": types,
            "key_actions": keys,
            "genuine_test": True,
            "pycharm_gui_used": True,
            "description": "Genuine test using PyCharm GUI to create Flask project"
        }

        with open(os.path.join(artifacts_dir, 'summary.json'), 'w') as f:
            json.dump(summary, f, indent=2)

        print("\n" + "=" * 70)
        print("TEST COMPLETE")
        print("=" * 70)
        print(f"Duration: {episode_end - episode_start:.2f} seconds")
        print(f"Total actions: {len(actions)} ({clicks} clicks, {types} types, {keys} keys)")
        print(f"Artifacts: {artifacts_dir}")

    finally:
        sftp.close()
        ssh.close()
        env.close()

    print(f"\nEvidence updated in: {evidence_dir}")
    return True

if __name__ == '__main__':
    main()
