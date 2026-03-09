#!/usr/bin/env python3
"""
Genuine test that creates Flask project FROM SCRATCH using PyCharm GUI.
This test MUST NOT have any pre-existing files.
"""

import sys
import os
import time
import json

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from ask_cua import AskCUA


def run_genuine_creation_test():
    """Run a genuine test that creates files from scratch."""

    print("=" * 60)
    print("GENUINE FLASK PROJECT CREATION TEST")
    print("=" * 60)
    print("\nThis test creates a Flask project FROM SCRATCH.")
    print("No pre-existing files allowed.\n")

    # Initialize environment
    cua = AskCUA(
        env_name="pycharm_env",
        task_name="create_flask_app"
    )

    try:
        # Start the environment
        print("Starting environment...")
        obs = cua.start()

        # Record episode start time
        episode_start = time.time()
        print(f"Episode started at: {episode_start}")

        # Take initial screenshot to verify clean state
        cua.save_screenshot("evidence/genuine_01_initial_clean.png")
        print("Initial screenshot saved - should show PyCharm Welcome screen")

        # Wait for PyCharm to be ready
        time.sleep(3)

        # Verify no hello_flask directory exists
        result = cua.execute_command("ls -la /home/ga/PycharmProjects/")
        print(f"PycharmProjects contents:\n{result}")

        if "hello_flask" in str(result):
            print("ERROR: hello_flask directory already exists! Test invalid.")
            return False

        print("\n" + "=" * 40)
        print("STEP 1: Create New Project")
        print("=" * 40)

        # Click on "New Project" button
        # First, let's position and click on the New Project button
        # Based on PyCharm Welcome screen layout: New Project is typically around (747, 270)
        cua.action({"type": "click", "x": 747, "y": 270})
        time.sleep(2)
        cua.save_screenshot("evidence/genuine_02_new_project_dialog.png")

        # Type the project location
        # Clear the existing location and type new one
        cua.action({"type": "key", "key": "ctrl+a"})
        time.sleep(0.3)
        cua.action({"type": "type", "text": "/home/ga/PycharmProjects/hello_flask"})
        time.sleep(1)
        cua.save_screenshot("evidence/genuine_03_project_location.png")

        # Click Create button (usually at bottom of dialog)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(5)  # Wait for project creation
        cua.save_screenshot("evidence/genuine_04_project_created.png")

        print("\n" + "=" * 40)
        print("STEP 2: Create app.py")
        print("=" * 40)

        # Use Alt+Insert to create new file
        cua.action({"type": "key", "key": "alt+Insert"})
        time.sleep(1)
        cua.save_screenshot("evidence/genuine_05_new_menu.png")

        # Type "Python" to select Python File
        cua.action({"type": "type", "text": "Python"})
        time.sleep(0.5)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(1)

        # Type the filename
        cua.action({"type": "type", "text": "app"})
        time.sleep(0.3)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(2)
        cua.save_screenshot("evidence/genuine_06_app_file_created.png")

        # Type the Flask app code
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

        cua.action({"type": "type", "text": app_code})
        time.sleep(1)

        # Save the file
        cua.action({"type": "key", "key": "ctrl+s"})
        time.sleep(1)
        cua.save_screenshot("evidence/genuine_07_app_code_typed.png")

        print("\n" + "=" * 40)
        print("STEP 3: Create test_app.py")
        print("=" * 40)

        # Create another new file
        cua.action({"type": "key", "key": "alt+Insert"})
        time.sleep(1)
        cua.action({"type": "type", "text": "Python"})
        time.sleep(0.5)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(1)

        # Type the filename
        cua.action({"type": "type", "text": "test_app"})
        time.sleep(0.3)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(2)

        # Type the test code
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

        cua.action({"type": "type", "text": test_code})
        time.sleep(1)

        # Save the file
        cua.action({"type": "key", "key": "ctrl+s"})
        time.sleep(1)
        cua.save_screenshot("evidence/genuine_08_test_code_typed.png")

        print("\n" + "=" * 40)
        print("STEP 4: Create requirements.txt")
        print("=" * 40)

        # Create requirements.txt
        cua.action({"type": "key", "key": "alt+Insert"})
        time.sleep(1)
        cua.action({"type": "type", "text": "File"})
        time.sleep(0.5)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(1)

        # Type the filename
        cua.action({"type": "type", "text": "requirements.txt"})
        time.sleep(0.3)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(2)

        # Type requirements
        cua.action({"type": "type", "text": "Flask>=2.0.0\npytest>=7.0.0"})
        time.sleep(0.5)
        cua.action({"type": "key", "key": "ctrl+s"})
        time.sleep(1)
        cua.save_screenshot("evidence/genuine_09_requirements_typed.png")

        print("\n" + "=" * 40)
        print("STEP 5: Run Tests")
        print("=" * 40)

        # Open test_app.py and run tests
        cua.action({"type": "key", "key": "ctrl+shift+n"})
        time.sleep(1)
        cua.action({"type": "type", "text": "test_app.py"})
        time.sleep(0.5)
        cua.action({"type": "key", "key": "Return"})
        time.sleep(2)

        # Run tests with Ctrl+Shift+F10
        cua.action({"type": "key", "key": "ctrl+shift+F10"})
        time.sleep(10)  # Wait for tests to run
        cua.save_screenshot("evidence/genuine_10_tests_running.png")

        print("\n" + "=" * 40)
        print("VERIFICATION")
        print("=" * 40)

        # Verify files were created
        result = cua.execute_command("ls -la /home/ga/PycharmProjects/hello_flask/")
        print(f"Project contents:\n{result}")

        # Verify .idea folder exists
        result = cua.execute_command("ls -la /home/ga/PycharmProjects/hello_flask/.idea/")
        print(f".idea folder contents:\n{result}")

        # Run pytest via command line to verify
        result = cua.execute_command(
            "cd /home/ga/PycharmProjects/hello_flask && python3 -m pytest test_app.py -v"
        )
        print(f"Pytest output:\n{result}")

        # Get trajectory
        trajectory = cua.get_trajectory()

        # Count actions
        total_clicks = sum(1 for step in trajectory.get('steps', [])
                         if any(a.get('type') == 'click' for a in step.get('action', [])))
        total_types = sum(1 for step in trajectory.get('steps', [])
                        if any(a.get('type') == 'type' for a in step.get('action', [])))
        total_typed_chars = sum(len(a.get('text', ''))
                               for step in trajectory.get('steps', [])
                               for a in step.get('action', [])
                               if a.get('type') == 'type')

        print(f"\nTrajectory Summary:")
        print(f"  Total clicks: {total_clicks}")
        print(f"  Total type actions: {total_types}")
        print(f"  Total chars typed: {total_typed_chars}")

        # Save trajectory
        with open("evidence/genuine_trajectory.json", "w") as f:
            json.dump(trajectory, f, indent=2)

        # Final screenshot
        cua.save_screenshot("evidence/genuine_11_final_state.png")

        print("\n" + "=" * 60)
        print("TEST COMPLETE")
        print("=" * 60)

        return True

    except Exception as e:
        print(f"Error during test: {e}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        cua.stop()


if __name__ == "__main__":
    success = run_genuine_creation_test()
    sys.exit(0 if success else 1)
