#!/usr/bin/env python3
"""
Test script for Flight Crew View (FLICA) Android AVD environment.

Tests:
1. Framework integration (from_config, reset, step, close)
2. Flight Crew View APK installation check
3. Screenshot capture
4. VNC server setup
5. Touch input
6. Framework step
7. UI dump for verification

Usage:
    python benchmarks/environments/flica_env/dev/test_flica.py
    python benchmarks/environments/flica_env/dev/test_flica.py --interactive
"""

import os
import sys
import time
import tempfile
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

os.environ["ADB_MDNS"] = "0"  # Disable mDNS for InfiniBand compatibility


def test_flica_env():
    """Test Flight Crew View environment with Gym-Anything framework."""
    from gym_anything.api import from_config

    env_dir = Path(__file__).parent.parent

    print("=" * 60)
    print("Flight Crew View (FLICA) Environment Test")
    print("=" * 60)

    results = {}
    env = None

    try:
        # === Test 1: Framework initialization ===
        print("\n[1/7] Testing framework initialization...")
        try:
            env = from_config(str(env_dir), task_id="create_account")
            results["framework_init"] = "PASS"
            print("  -> PASS: Environment created from config")
        except Exception as e:
            results["framework_init"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")
            raise

        # === Test 2: Environment reset (starts emulator) ===
        print("\n[2/7] Testing environment reset (this will start the emulator)...")
        print("  Note: This may take 2-5 minutes on first run...")
        start_time = time.time()
        try:
            obs = env.reset(seed=42)
            elapsed = time.time() - start_time
            results["env_reset"] = f"PASS ({elapsed:.1f}s)"
            print(f"  -> PASS: Environment reset completed in {elapsed:.1f}s")
        except Exception as e:
            results["env_reset"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")
            raise

        runner = env._runner

        # === Test 3: Check Flight Crew View installation ===
        print("\n[3/7] Checking Flight Crew View installation...")
        try:
            result = runner._adb_command(["shell", "pm", "list", "packages", "com.robert.fcView"])
            output = result.stdout.decode('utf-8', errors='replace')

            if "com.robert.fcView" in output:
                results["app_installed"] = "PASS"
                print("  -> PASS: Flight Crew View is installed")
            else:
                results["app_installed"] = "FAIL: Not installed"
                print("  -> FAIL: Flight Crew View is NOT installed")
        except Exception as e:
            results["app_installed"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 4: Screenshot capture ===
        print("\n[4/7] Testing screenshot capture...")
        try:
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                temp_path = f.name

            if runner.capture_screenshot(temp_path):
                size = Path(temp_path).stat().st_size
                results["screenshot"] = f"PASS ({size} bytes)"
                print(f"  -> PASS: Screenshot captured ({size} bytes)")

                artifacts = env_dir / "artifacts"
                artifacts.mkdir(exist_ok=True)
                import shutil
                shutil.copy(temp_path, artifacts / "test_screenshot.png")
                print(f"  -> Saved to: {artifacts / 'test_screenshot.png'}")
            else:
                results["screenshot"] = "FAIL: capture_screenshot returned False"
                print("  -> FAIL: Screenshot capture failed")

            Path(temp_path).unlink(missing_ok=True)
        except Exception as e:
            results["screenshot"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 5: VNC Server check ===
        print("\n[5/7] Checking VNC server...")
        try:
            if runner.vnc_port:
                results["vnc_server"] = f"PASS (localhost:{runner.vnc_port})"
                print(f"  -> PASS: VNC available at localhost:{runner.vnc_port}")
                print(f"  -> Password: password")
            else:
                results["vnc_server"] = "SKIP: VNC not configured"
                print("  -> SKIP: VNC server not configured")
        except Exception as e:
            results["vnc_server"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 6: Framework step ===
        print("\n[6/7] Testing framework step...")
        try:
            action = {"mouse": {"left_click": [540, 1200]}}
            obs, reward, done, info = env.step([action])
            results["framework_step"] = "PASS"
            print(f"  -> PASS: Step completed (reward={reward}, done={done})")
        except Exception as e:
            results["framework_step"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 7: UI Dump ===
        print("\n[7/7] Testing UI dump for verification...")
        try:
            result = runner._adb_command(["shell", "uiautomator", "dump", "/sdcard/ui_dump.xml"])
            time.sleep(1)

            result = runner._adb_command(["shell", "ls", "-la", "/sdcard/ui_dump.xml"])
            output = result.stdout.decode('utf-8', errors='replace')

            if "ui_dump.xml" in output:
                results["ui_dump"] = "PASS"
                print("  -> PASS: UI dump created successfully")

                result = runner._adb_command(["shell", "head", "-c", "500", "/sdcard/ui_dump.xml"])
                preview = result.stdout.decode('utf-8', errors='replace')
                print(f"  -> Preview: {preview[:200]}...")
            else:
                results["ui_dump"] = "FAIL: UI dump not created"
                print("  -> FAIL: UI dump not created")
        except Exception as e:
            results["ui_dump"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

    except Exception as e:
        print(f"\n[ERROR] Test aborted: {e}")
        import traceback
        traceback.print_exc()

    finally:
        print("\n" + "=" * 60)
        print("Cleaning up...")
        if env:
            try:
                env.close()
                print("Environment closed successfully")
            except Exception as e:
                print(f"Warning: Error during cleanup: {e}")

    # Print summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)

    passed = 0
    failed = 0
    skipped = 0

    for test, result in results.items():
        status = result.split(":")[0] if ":" in result else result.split()[0]
        if status.startswith("PASS"):
            passed += 1
            symbol = "+"
        elif status.startswith("SKIP"):
            skipped += 1
            symbol = "-"
        else:
            failed += 1
            symbol = "x"
        print(f"  [{symbol}] {test}: {result}")

    print(f"\nTotal: {passed} passed, {failed} failed, {skipped} skipped")
    return passed, 0, failed


def interactive_test():
    """Interactive test mode - starts environment and keeps it running."""
    from gym_anything.api import from_config

    env_dir = Path(__file__).parent.parent

    print("=" * 60)
    print("Flight Crew View Interactive Test Mode")
    print("=" * 60)

    env = None

    try:
        print("\nStarting environment (this may take a few minutes)...")
        env = from_config(str(env_dir), task_id="create_account")
        obs = env.reset(seed=42)

        runner = env._runner
        print(f"\nEnvironment ready!")
        print(f"  ADB device: emulator-{runner.console_port}")
        print(f"  VNC port: {runner.vnc_port}")
        print("\nConnect via VNC to interact with the emulator.")
        print("Press Ctrl+C to stop the environment.\n")

        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\n\nStopping environment...")
    finally:
        if env:
            env.close()
            print("Environment closed.")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Test Flight Crew View environment")
    parser.add_argument("--interactive", "-i", action="store_true",
                        help="Run in interactive mode (keeps emulator running)")
    args = parser.parse_args()

    if args.interactive:
        interactive_test()
    else:
        passed, partial, failed = test_flica_env()
        sys.exit(0 if failed == 0 else 1)
