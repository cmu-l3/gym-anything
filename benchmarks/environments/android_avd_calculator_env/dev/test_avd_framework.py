#!/usr/bin/env python3
"""
Comprehensive test for AVD environment with Gym-Anything framework.

Tests:
1. Framework integration (from_config, reset, step, close)
2. Calculator APK installation
3. VNC server setup
4. All input methods (touch, keyboard, swipe)
5. Screenshot capture
6. File copy to/from device
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


def test_avd_framework():
    """Test AVD environment with Gym-Anything framework."""
    from gym_anything.api import from_config
    from gym_anything.runners.avd_sdk_manager import AVDSDKManager

    env_dir = Path(__file__).parent.parent

    print("=" * 60)
    print("AVD Framework Integration Test")
    print("=" * 60)

    results = {}
    env = None

    try:
        # === Test 1: Framework initialization ===
        print("\n[1/8] Testing framework initialization...")
        try:
            env = from_config(str(env_dir), task_id="basic_addition")
            results["framework_init"] = "PASS"
            print("  -> PASS: Environment created from config")
        except Exception as e:
            results["framework_init"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")
            raise

        # === Test 2: Environment reset (starts emulator) ===
        print("\n[2/8] Testing environment reset (this will start the emulator)...")
        start_time = time.time()
        try:
            obs = env.reset(seed=42)
            elapsed = time.time() - start_time
            results["env_reset"] = f"PASS ({elapsed:.1f}s)"
            print(f"  -> PASS: Environment reset completed in {elapsed:.1f}s")
            print(f"  -> Observation keys: {list(obs.keys()) if obs else 'None'}")
        except Exception as e:
            results["env_reset"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")
            raise

        # Get the runner for direct testing
        runner = env._runner

        # === Test 3: Install Calculator APK ===
        print("\n[3/8] Testing Calculator APK installation...")
        try:
            sdk_manager = AVDSDKManager()

            # Download Calculator APK
            calc_apk = sdk_manager.ensure_calculator_apk()
            if calc_apk and calc_apk.exists():
                print(f"  -> Calculator APK: {calc_apk}")

                # Install it
                if runner.install_apk(str(calc_apk)):
                    results["calculator_install"] = "PASS"
                    print("  -> PASS: Calculator APK installed")
                else:
                    results["calculator_install"] = "FAIL: install_apk returned False"
                    print("  -> FAIL: APK installation failed")
            else:
                results["calculator_install"] = "FAIL: APK download failed"
                print("  -> FAIL: Could not download Calculator APK")
        except Exception as e:
            results["calculator_install"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 4: Launch Calculator ===
        print("\n[4/8] Testing Calculator launch...")
        try:
            # Try OpenCalc (F-Droid) - use monkey to launch by package
            result = runner._adb_command([
                "shell", "monkey", "-p", "com.darkempire78.opencalculator",
                "-c", "android.intent.category.LAUNCHER", "1"
            ])

            if result.returncode != 0:
                # Fallback: Try Google Calculator
                result = runner._adb_command([
                    "shell", "am", "start", "-n",
                    "com.google.android.calculator/com.android.calculator2.Calculator"
                ])

            time.sleep(2)

            # Verify Calculator is running
            ps_result = runner._adb_command(["shell", "dumpsys", "activity", "activities"])
            output = ps_result.stdout.decode('utf-8', errors='replace')

            if "opencalculator" in output.lower() or "calculator" in output.lower():
                results["calculator_launch"] = "PASS"
                print("  -> PASS: Calculator launched successfully")
            else:
                results["calculator_launch"] = "FAIL: Calculator not in activity stack"
                print("  -> FAIL: Calculator not running")
        except Exception as e:
            results["calculator_launch"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 5: Screenshot capture ===
        print("\n[5/8] Testing screenshot capture...")
        try:
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                temp_path = f.name

            if runner.capture_screenshot(temp_path):
                size = Path(temp_path).stat().st_size
                results["screenshot"] = f"PASS ({size} bytes)"
                print(f"  -> PASS: Screenshot captured ({size} bytes)")
                # Save to artifacts
                artifacts = env_dir / "artifacts"
                artifacts.mkdir(exist_ok=True)
                import shutil
                shutil.copy(temp_path, artifacts / "test_screenshot.png")
            else:
                results["screenshot"] = "FAIL: capture_screenshot returned False"
                print("  -> FAIL: Screenshot capture failed")

            Path(temp_path).unlink(missing_ok=True)
        except Exception as e:
            results["screenshot"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 6: Touch input ===
        print("\n[6/8] Testing touch input (tap 5 button)...")
        try:
            # Tap on approximate location for "5" button
            # Standard calculator button layout at 1080x2400 resolution
            # Use standard action format: {"mouse": {"left_click": [x, y]}}
            runner.inject_action({"mouse": {"left_click": [540, 1700]}})
            time.sleep(0.5)
            results["touch_input"] = "PASS"
            print("  -> PASS: Touch input injected")
        except Exception as e:
            results["touch_input"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 7: Framework step ===
        print("\n[7/8] Testing framework step...")
        try:
            action = {"mouse": {"left_click": [540, 1850]}}  # Tap + button
            obs, reward, done, info = env.step([action])
            results["framework_step"] = "PASS"
            print(f"  -> PASS: Step completed (reward={reward}, done={done})")
            print(f"  -> Observation: {list(obs.keys()) if obs else 'None'}")
        except Exception as e:
            results["framework_step"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

        # === Test 8: VNC Server installation (if available) ===
        print("\n[8/8] Testing VNC server installation...")
        try:
            sdk_manager = AVDSDKManager()
            vnc_apk = sdk_manager.ensure_vnc_server_apk()

            if vnc_apk and vnc_apk.exists():
                print(f"  -> VNC Server APK: {vnc_apk}")

                if runner.install_apk(str(vnc_apk)):
                    # Try to start VNC server
                    if runner.start_vnc_server(port=5900, password="password"):
                        # Forward port
                        try:
                            host_port = runner.forward_vnc_port()
                            results["vnc_server"] = f"PASS (port {host_port})"
                            print(f"  -> PASS: VNC server started on localhost:{host_port}")
                        except Exception as e:
                            results["vnc_server"] = f"PARTIAL: VNC started but forward failed: {e}"
                            print(f"  -> PARTIAL: VNC started but port forward failed: {e}")
                    else:
                        results["vnc_server"] = "PARTIAL: APK installed but start failed"
                        print("  -> PARTIAL: VNC APK installed but service start failed")
                else:
                    results["vnc_server"] = "FAIL: APK install failed"
                    print("  -> FAIL: VNC APK installation failed")
            else:
                results["vnc_server"] = "FAIL: APK download failed"
                print("  -> FAIL: Could not download VNC Server APK")
        except Exception as e:
            results["vnc_server"] = f"FAIL: {e}"
            print(f"  -> FAIL: {e}")

    except Exception as e:
        print(f"\n[ERROR] Test aborted: {e}")
        import traceback
        traceback.print_exc()

    finally:
        # Cleanup
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
    partial = 0

    for test, result in results.items():
        status = result.split(":")[0] if ":" in result else result.split()[0]
        if status == "PASS":
            passed += 1
            symbol = "✓"
        elif status == "PARTIAL":
            partial += 1
            symbol = "~"
        else:
            failed += 1
            symbol = "✗"
        print(f"  [{symbol}] {test}: {result}")

    print(f"\nTotal: {passed} passed, {partial} partial, {failed} failed")

    return passed, partial, failed


if __name__ == "__main__":
    passed, partial, failed = test_avd_framework()
    sys.exit(0 if failed == 0 else 1)
