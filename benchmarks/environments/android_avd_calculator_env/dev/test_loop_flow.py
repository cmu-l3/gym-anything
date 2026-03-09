#!/usr/bin/env python3
"""
Test the full loop.py flow with AVD environment.

This script simulates what loop.py does:
1. Load environment from config
2. Reset environment
3. Run a few steps with actions
4. Verify the verifier runs at the end
"""

import os
import sys
import time
import json
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

os.environ["ADB_MDNS"] = "0"  # Disable mDNS for InfiniBand compatibility


def test_loop_flow():
    """Test the full loop.py flow."""
    from gym_anything.api import from_config

    env_dir = Path(__file__).parent.parent
    task_id = "basic_addition"

    print("=" * 60)
    print("AVD Loop.py Flow Test")
    print("=" * 60)

    env = None
    try:
        # === Step 1: Load environment (like loop.py line 30) ===
        print("\n[Step 1] Loading environment from config...")
        env = from_config(str(env_dir), task_id=task_id)
        print(f"  -> Environment: {env.env_spec.id}")
        print(f"  -> Task: {env.task_spec.id}")

        # === Step 2: Reset environment (like loop.py line 35) ===
        print("\n[Step 2] Resetting environment (starting emulator)...")
        start_time = time.time()
        obs = env.reset(seed=42)
        elapsed = time.time() - start_time
        print(f"  -> Reset completed in {elapsed:.1f}s")
        print(f"  -> Episode directory: {env._episode_dir}")

        # Note: Calculator installation and launch is handled by the
        # post_start hook (setup_calculator.sh) which runs during env.reset()

        # === Step 3: Capture initial observation (like loop.py line 60) ===
        print("\n[Step 3] Capturing initial observation...")
        obs = env._capture_observation()
        print(f"  -> Observation keys: {list(obs.keys())}")
        if 'screen' in obs:
            print(f"  -> Screenshot: {obs['screen'].get('path', 'N/A')}")

        # === Step 4: Load task description (like loop.py line 50) ===
        print("\n[Step 4] Loading task description...")
        task_json_path = env_dir / "tasks" / task_id / "task.json"
        task_data = json.loads(task_json_path.read_text())
        task_description = task_data['description']
        print(f"  -> Task: {task_description}")

        # === Step 5: Simulate agent actions (calculator: 25 + 17 = 42) ===
        print("\n[Step 5] Simulating agent actions...")

        # Define button positions for OpenCalc (approximate positions for 1080x2400 screen)
        # OpenCalc has a standard calculator layout:
        # Row 1: AC, (), %, ÷
        # Row 2: 7, 8, 9, ×
        # Row 3: 4, 5, 6, -
        # Row 4: 1, 2, 3, +
        # Row 5: 0, ., DEL, =
        buttons = {
            '0': (270, 2000),
            '1': (130, 1800),
            '2': (400, 1800),
            '3': (670, 1800),
            '4': (130, 1600),
            '5': (400, 1600),
            '6': (670, 1600),
            '7': (130, 1400),
            '8': (400, 1400),
            '9': (670, 1400),
            '+': (940, 1800),
            '-': (940, 1600),
            '*': (940, 1400),
            '/': (940, 1200),
            '=': (940, 2000),
            'C': (130, 1200),
        }

        # Tap sequence: 2, 5, +, 1, 7, = (for 25 + 17 = 42)
        actions_sequence = ['2', '5', '+', '1', '7', '=']

        for i, key in enumerate(actions_sequence):
            x, y = buttons[key]
            action = {"mouse": {"left_click": [x, y]}}
            print(f"  -> Step {i+1}: Tapping '{key}' at ({x}, {y})")

            obs, reward, done, info = env.step([action])
            time.sleep(0.5)

            print(f"     Reward: {reward}, Done: {done}")

        # === Step 6: Capture final screenshot ===
        print("\n[Step 6] Capturing final observation...")
        obs = env._capture_observation()
        if 'screen' in obs:
            final_path = obs['screen'].get('path', 'N/A')
            print(f"  -> Final screenshot: {final_path}")

        # === Step 7: Mark done and trigger verifier ===
        print("\n[Step 7] Marking episode as done (triggers verifier)...")
        obs, reward, done, info = env.step([{"mouse": {"left_click": [0, 0]}}], mark_done=True)
        print(f"  -> Done: {done}")
        print(f"  -> Reward: {reward}")
        print(f"  -> Info: {info}")

        # Check verifier result
        if 'verifier' in info:
            verifier_result = info['verifier']
            if verifier_result:
                print(f"\n[Verifier Result]")
                print(f"  -> Passed: {verifier_result.get('passed', 'N/A')}")
                print(f"  -> Score: {verifier_result.get('score', 'N/A')}")
            else:
                print("\n[Verifier] No result (verifier may have failed)")

        print("\n" + "=" * 60)
        print("TEST COMPLETED SUCCESSFULLY!")
        print("=" * 60)
        print(f"\nEpisode artifacts saved to: {env._episode_dir}")

        return True

    except Exception as e:
        print(f"\n[ERROR] Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        # Cleanup
        print("\nCleaning up...")
        if env:
            try:
                env.close()
                print("Environment closed successfully")
            except Exception as e:
                print(f"Warning: Error during cleanup: {e}")


if __name__ == "__main__":
    success = test_loop_flow()
    sys.exit(0 if success else 1)
