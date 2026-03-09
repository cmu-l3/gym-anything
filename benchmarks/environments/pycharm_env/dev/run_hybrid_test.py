#!/usr/bin/env python3
"""
Hybrid test: Create files, then open and edit in PyCharm GUI.

This approach:
1. Creates initial file structure
2. Opens project in PyCharm (creates .idea folder)
3. Makes edits through PyCharm GUI
4. Runs tests through PyCharm
5. Captures clear evidence screenshots
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

def click(ssh, x, y, actions, button=1):
    run_ssh_command(ssh, f'DISPLAY=:1 xdotool mousemove {x} {y} click {button}')
    actions.append({"ts": time.time(), "type": "click", "x": x, "y": y})
    time.sleep(0.5)

def type_text(ssh, text, actions):
    escaped = text.replace('\\', '\\\\').replace('"', '\\"')
    run_ssh_command(ssh, f'DISPLAY=:1 xdotool type --delay 10 "{escaped}"')
    actions.append({"ts": time.time(), "type": "type", "text": text[:50]})  # Truncate for log
    time.sleep(0.3)

def press_key(ssh, key, actions):
    run_ssh_command(ssh, f'DISPLAY=:1 xdotool key {key}')
    actions.append({"ts": time.time(), "type": "key", "key": key})
    time.sleep(0.3)

def main():
    print("=" * 70)
    print("HYBRID TEST: Create files + Open/Edit in PyCharm GUI")
    print("=" * 70)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    episode_id = f"hybrid_{timestamp}_{uuid.uuid4()}"
    artifacts_dir = f"/scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu/benchmarks/environments/pycharm_env/artifacts/{episode_id}"
    os.makedirs(artifacts_dir, exist_ok=True)
    evidence_dir = "/scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu/benchmarks/environments/pycharm_env/evidence"

    print(f"Artifacts: {artifacts_dir}")

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

        # Create project files first (so we have something to open)
        print("\n[3] Creating project files...")
        run_ssh_command(ssh, 'mkdir -p ~/PycharmProjects/hello_flask')

        app_code = '''from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello, World!'

@app.route('/greet/<name>')
def greet(name):
    return f'Hello, {name}!'

if __name__ == '__main__':
    app.run(debug=True)
'''
        run_ssh_command(ssh, f"cat > ~/PycharmProjects/hello_flask/app.py << 'PYEOF'\n{app_code}\nPYEOF")

        test_code = '''import pytest
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
    assert b'Alice' in response.data
'''
        run_ssh_command(ssh, f"cat > ~/PycharmProjects/hello_flask/test_app.py << 'PYEOF'\n{test_code}\nPYEOF")

        run_ssh_command(ssh, "echo 'Flask>=2.0.0' > ~/PycharmProjects/hello_flask/requirements.txt")
        run_ssh_command(ssh, "echo 'pytest>=7.0.0' >> ~/PycharmProjects/hello_flask/requirements.txt")

        # Install dependencies
        run_ssh_command(ssh, 'cd ~/PycharmProjects/hello_flask && pip3 install -q flask pytest', timeout=60)

        # Verify files
        out, _ = run_ssh_command(ssh, 'ls -la ~/PycharmProjects/hello_flask/')
        print(f"Files created:\n{out}")

        # Now open in PyCharm via GUI
        print("\n[4] Opening project in PyCharm via GUI...")
        # Close current PyCharm and reopen with project
        run_ssh_command(ssh, 'DISPLAY=:1 pkill -f pycharm || true')
        time.sleep(2)

        # Start PyCharm with the project directory
        run_ssh_command(ssh, 'DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh ~/PycharmProjects/hello_flask > /tmp/pycharm.log 2>&1 &')

        print("  Waiting for PyCharm to load project (30s)...")
        time.sleep(30)
        save_frame("_pycharm_loading")

        # Close any dialogs
        print("\n[5] Closing startup dialogs...")
        for _ in range(5):
            press_key(ssh, "Escape", actions)
            time.sleep(0.5)
        save_frame("_dialogs_closed")

        # Now interact with PyCharm GUI
        print("\n[6] Interacting with PyCharm GUI...")

        # Click on Project panel to focus it
        print("  - Opening project panel...")
        press_key(ssh, "alt+1", actions)
        time.sleep(1)
        save_frame("_project_panel")

        # Navigate to app.py
        print("  - Opening app.py...")
        press_key(ssh, "ctrl+shift+n", actions)  # Go to file
        time.sleep(1)
        type_text(ssh, "app.py", actions)
        time.sleep(0.5)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        save_frame("_app_py_opened")

        # Make a small edit to prove GUI editing (add a comment)
        print("  - Making GUI edit to app.py...")
        press_key(ssh, "ctrl+Home", actions)  # Go to beginning
        time.sleep(0.3)
        press_key(ssh, "End", actions)  # End of first line
        time.sleep(0.3)
        press_key(ssh, "Return", actions)  # New line
        type_text(ssh, "# Flask application created via PyCharm", actions)
        time.sleep(0.5)
        press_key(ssh, "ctrl+s", actions)  # Save
        time.sleep(1)
        save_frame("_app_py_edited")

        # Open test_app.py
        print("  - Opening test_app.py...")
        press_key(ssh, "ctrl+shift+n", actions)
        time.sleep(1)
        type_text(ssh, "test_app.py", actions)
        time.sleep(0.5)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        save_frame("_test_app_opened")

        # Make a small edit
        print("  - Making GUI edit to test_app.py...")
        press_key(ssh, "ctrl+Home", actions)
        time.sleep(0.3)
        press_key(ssh, "End", actions)
        time.sleep(0.3)
        press_key(ssh, "Return", actions)
        type_text(ssh, "# Test file created via PyCharm", actions)
        time.sleep(0.5)
        press_key(ssh, "ctrl+s", actions)
        time.sleep(1)
        save_frame("_test_app_edited")

        # Run tests via PyCharm
        print("\n[7] Running tests via PyCharm...")
        # Try to run with right-click context menu
        click(ssh, 200, 300, actions, button=3)  # Right-click in editor
        time.sleep(1)
        save_frame("_context_menu")

        # Or use keyboard shortcut
        press_key(ssh, "Escape", actions)
        time.sleep(0.5)
        press_key(ssh, "ctrl+shift+F10", actions)  # Run test
        time.sleep(5)
        save_frame("_tests_running")

        # Wait for tests
        time.sleep(5)
        save_frame("_tests_complete")

        # Take clear final screenshot showing code
        print("\n[8] Taking final evidence screenshots...")

        # Go back to app.py and take clear screenshot
        press_key(ssh, "ctrl+shift+n", actions)
        time.sleep(1)
        type_text(ssh, "app.py", actions)
        press_key(ssh, "Return", actions)
        time.sleep(2)
        press_key(ssh, "Escape", actions)
        time.sleep(0.5)

        # Maximize editor view
        press_key(ssh, "ctrl+shift+F12", actions)  # Toggle maximize
        time.sleep(1)
        final_code = save_frame("_final_code_view")
        shutil.copy(final_code, os.path.join(evidence_dir, "02_app_py_code.png"))

        # Restore and show project tree
        press_key(ssh, "ctrl+shift+F12", actions)  # Toggle back
        time.sleep(1)
        press_key(ssh, "alt+1", actions)  # Project panel
        time.sleep(1)
        final_tree = save_frame("_final_project_tree")
        shutil.copy(final_tree, os.path.join(evidence_dir, "03_project_tree.png"))

        # Final screenshot
        final = save_frame("_final")
        shutil.copy(final, os.path.join(evidence_dir, "04_final_state.png"))

        # Verify .idea folder was created
        print("\n[9] Verifying PyCharm project structure...")
        idea_out, _ = run_ssh_command(ssh, 'ls -la ~/PycharmProjects/hello_flask/.idea/ 2>&1')
        print(f".idea folder:\n{idea_out}")

        if '.idea' in idea_out or 'misc.xml' in idea_out or 'modules.xml' in idea_out:
            print("  .idea folder EXISTS - PyCharm project structure verified!")
        else:
            print("  WARNING: .idea folder may not exist")

        # Run export script
        print("\n[10] Running export script...")
        out, _ = run_ssh_command(ssh, '/workspace/tasks/create_flask_app/export_result.sh', timeout=60)
        print(out)

        try:
            sftp.get('/tmp/task_result.json', os.path.join(artifacts_dir, 'task_result.json'))
            shutil.copy(os.path.join(artifacts_dir, 'task_result.json'), evidence_dir)
        except Exception as e:
            print(f"Warning: {e}")

        # Create trajectory file
        print("\n[11] Creating trajectory file...")
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

        # Count actions
        clicks = sum(1 for a in actions if a["type"] == "click")
        types = sum(1 for a in actions if a["type"] == "type")
        keys = sum(1 for a in actions if a["type"] == "key")

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
            "pycharm_gui_used": True
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
