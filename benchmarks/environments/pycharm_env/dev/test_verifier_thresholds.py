#!/usr/bin/env python3
"""
Test the verifier thresholds with various trajectory patterns.
This tests that the verifier correctly rejects:
1. Trajectories with only navigation (no file creation)
2. Trajectories with insufficient clicks
3. Trajectories with insufficient typed characters
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

# Import the verifier
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tasks', 'create_flask_app'))
from verifier import verify_create_flask_app


def test_navigation_only_trajectory():
    """Test that navigation-only trajectory is rejected."""
    print("\n" + "=" * 60)
    print("TEST 1: Navigation-only trajectory (should FAIL)")
    print("=" * 60)

    # Trajectory that only navigates to existing files
    navigation_traj = {
        "steps": [
            {"event": "step", "ts": 1000, "idx": 0, "action": [{"type": "key", "key": "Escape"}]},
            {"event": "step", "ts": 1001, "idx": 1, "action": [{"type": "key", "key": "Escape"}]},
            {"event": "step", "ts": 1002, "idx": 2, "action": [{"type": "key", "key": "alt+1"}]},  # Open project panel
            {"event": "step", "ts": 1003, "idx": 3, "action": [{"type": "key", "key": "ctrl+shift+n"}]},  # Go to file
            {"event": "step", "ts": 1004, "idx": 4, "action": [{"type": "type", "text": "app.py"}]},  # Search
            {"event": "step", "ts": 1005, "idx": 5, "action": [{"type": "key", "key": "Return"}]},
            {"event": "step", "ts": 1006, "idx": 6, "action": [{"type": "type", "text": "# comment"}]},  # Trivial edit
            {"event": "step", "ts": 1007, "idx": 7, "action": [{"type": "key", "key": "ctrl+s"}]},  # Save
        ] * 3  # Repeat to meet step count
    }

    # Mock env_info
    env_info = {
        "episode_start_ts": 999,
        "copy_from_env": lambda src, dst: None  # Will cause file not found
    }
    task_info = {"metadata": {"project_dir": "/nonexistent"}}

    result = verify_create_flask_app(navigation_traj, env_info, task_info)
    print(f"Result: passed={result['passed']}, score={result['score']}")
    print(f"Feedback: {result['feedback']}")

    assert not result['passed'], "Navigation-only trajectory should fail!"
    print("TEST 1 PASSED: Navigation-only trajectory correctly rejected")


def test_insufficient_clicks_trajectory():
    """Test that trajectory with too few clicks is rejected."""
    print("\n" + "=" * 60)
    print("TEST 2: Insufficient clicks trajectory (should FAIL)")
    print("=" * 60)

    # Trajectory with only keyboard actions, no clicks
    keyboard_only_traj = {
        "steps": [
            {"event": "step", "ts": 1000, "idx": i, "action": [{"type": "key", "key": "a"}]}
            for i in range(25)  # 25 key presses
        ] + [
            {"event": "step", "ts": 1025, "idx": 25, "action": [{"type": "click", "x": 100, "y": 100}]},  # Only 1 click
        ] + [
            {"event": "step", "ts": 1030 + i, "idx": 26 + i, "action": [{"type": "type", "text": "x" * 50}]}
            for i in range(10)  # Type 500 chars total
        ]
    }

    env_info = {
        "episode_start_ts": 999,
        "copy_from_env": lambda src, dst: None
    }
    task_info = {"metadata": {"project_dir": "/nonexistent"}}

    result = verify_create_flask_app(keyboard_only_traj, env_info, task_info)
    print(f"Result: passed={result['passed']}, score={result['score']}")
    print(f"Feedback: {result['feedback']}")

    assert not result['passed'], "Insufficient clicks trajectory should fail!"
    assert "clicks" in result['feedback'].lower() or "gui" in result['feedback'].lower()
    print("TEST 2 PASSED: Insufficient clicks trajectory correctly rejected")


def test_insufficient_typing_trajectory():
    """Test that trajectory with too little code typed is rejected."""
    print("\n" + "=" * 60)
    print("TEST 3: Insufficient typing trajectory (should FAIL)")
    print("=" * 60)

    # Trajectory with clicks but very little typing
    minimal_typing_traj = {
        "steps": [
            {"event": "step", "ts": 1000 + i, "idx": i, "action": [{"type": "click", "x": 100, "y": 100}]}
            for i in range(10)  # 10 clicks
        ] + [
            {"event": "step", "ts": 1010 + i, "idx": 10 + i, "action": [{"type": "key", "key": "a"}]}
            for i in range(15)  # 15 key presses
        ] + [
            {"event": "step", "ts": 1025, "idx": 25, "action": [{"type": "type", "text": "# comment"}]},  # Only 9 chars
        ]
    }

    env_info = {
        "episode_start_ts": 999,
        "copy_from_env": lambda src, dst: None
    }
    task_info = {"metadata": {"project_dir": "/nonexistent"}}

    result = verify_create_flask_app(minimal_typing_traj, env_info, task_info)
    print(f"Result: passed={result['passed']}, score={result['score']}")
    print(f"Feedback: {result['feedback']}")

    assert not result['passed'], "Insufficient typing trajectory should fail!"
    assert "typed" in result['feedback'].lower() or "char" in result['feedback'].lower()
    print("TEST 3 PASSED: Insufficient typing trajectory correctly rejected")


def test_valid_trajectory_pattern():
    """Test that a trajectory with valid patterns passes initial checks."""
    print("\n" + "=" * 60)
    print("TEST 4: Valid trajectory pattern (should pass trajectory checks)")
    print("=" * 60)

    # Trajectory with file creation patterns
    valid_pattern_traj = {
        "steps": [
            # Initial actions
            {"event": "step", "ts": 1000, "idx": 0, "action": [{"type": "click", "x": 747, "y": 270}]},  # New Project
            {"event": "step", "ts": 1001, "idx": 1, "action": [{"type": "type", "text": "/home/ga/PycharmProjects/hello_flask"}]},
            {"event": "step", "ts": 1002, "idx": 2, "action": [{"type": "click", "x": 500, "y": 500}]},  # Create
            {"event": "step", "ts": 1003, "idx": 3, "action": [{"type": "key", "key": "alt+Insert"}]},  # New file
            {"event": "step", "ts": 1004, "idx": 4, "action": [{"type": "click", "x": 300, "y": 300}]},  # Select Python
            {"event": "step", "ts": 1005, "idx": 5, "action": [{"type": "type", "text": "app"}]},
            {"event": "step", "ts": 1006, "idx": 6, "action": [{"type": "click", "x": 400, "y": 400}]},  # OK
        ] + [
            # Type Flask code (~200 chars)
            {"event": "step", "ts": 1010, "idx": 7, "action": [{"type": "type", "text": "from flask import Flask\n\napp = Flask(__name__)\n\n@app.route('/')\ndef hello():\n    return 'Hello, World!'\n\n@app.route('/greet/<name>')\ndef greet(name):\n    return f'Hello, {name}!'\n"}]},
        ] + [
            {"event": "step", "ts": 1011, "idx": 8, "action": [{"type": "key", "key": "ctrl+s"}]},
            {"event": "step", "ts": 1012, "idx": 9, "action": [{"type": "key", "key": "alt+Insert"}]},  # New file
            {"event": "step", "ts": 1013, "idx": 10, "action": [{"type": "click", "x": 300, "y": 300}]},
            {"event": "step", "ts": 1014, "idx": 11, "action": [{"type": "type", "text": "test_app"}]},
            {"event": "step", "ts": 1015, "idx": 12, "action": [{"type": "click", "x": 400, "y": 400}]},
        ] + [
            # Type test code (~200 chars)
            {"event": "step", "ts": 1020, "idx": 13, "action": [{"type": "type", "text": "import pytest\nfrom app import app\n\n@pytest.fixture\ndef client():\n    app.config['TESTING'] = True\n    with app.test_client() as client:\n        yield client\n\ndef test_hello_route(client):\n    response = client.get('/')\n    assert response.status_code == 200\n"}]},
        ] + [
            {"event": "step", "ts": 1021 + i, "idx": 14 + i, "action": [{"type": "key", "key": "a"}]}
            for i in range(10)  # More actions
        ]
    }

    env_info = {
        "episode_start_ts": 999,
        "copy_from_env": lambda src, dst: None  # Will still fail file checks
    }
    task_info = {"metadata": {"project_dir": "/nonexistent"}}

    result = verify_create_flask_app(valid_pattern_traj, env_info, task_info)
    print(f"Result: passed={result['passed']}, score={result['score']}")
    print(f"Feedback: {result['feedback']}")

    # This should fail on file checks, not trajectory checks
    assert "Trajectory OK" in result['feedback'], f"Valid pattern should pass trajectory checks! Got: {result['feedback']}"
    print("TEST 4 PASSED: Valid trajectory pattern passes trajectory validation")


if __name__ == "__main__":
    print("=" * 60)
    print("VERIFIER THRESHOLD TESTS")
    print("=" * 60)

    try:
        test_navigation_only_trajectory()
        test_insufficient_clicks_trajectory()
        test_insufficient_typing_trajectory()
        test_valid_trajectory_pattern()

        print("\n" + "=" * 60)
        print("ALL TESTS PASSED!")
        print("=" * 60)

    except AssertionError as e:
        print(f"\nTEST FAILED: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
