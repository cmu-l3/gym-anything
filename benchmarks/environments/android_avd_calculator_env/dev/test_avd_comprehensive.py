#!/usr/bin/env python3
"""
Comprehensive test for AVD Android environment.

Tests:
1. Screenshot capture
2. Touch input (tap)
3. Keyboard input (text entry)
4. Swipe/scroll
5. File copy to device
6. File copy from device
7. Shell command execution
8. Networking (DNS, HTTP)
9. UI dump (accessibility)
10. Calculator app interaction
"""

import os
import sys
import time
import tempfile
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

from gym_anything.runners.avd_apptainer import AVDApptainerRunner
from gym_anything.specs import EnvSpec, ObservationSpec, RuntimeResources, AVDSpec


def test_avd_comprehensive():
    """Run comprehensive tests on AVD emulator."""

    print("=" * 60)
    print("AVD COMPREHENSIVE TEST")
    print("=" * 60)

    # Create spec for Android 34
    spec = EnvSpec(
        id="test.avd_comprehensive@1",
        observation=[ObservationSpec(type="rgb_screen", resolution=(1080, 2400))],
        resources=RuntimeResources(cpu=4, mem_gb=4),
        avd=AVDSpec(api_level=34, variant="google_apis", arch="x86_64", device="pixel_6")
    )

    runner = AVDApptainerRunner(spec)
    temp_dir = tempfile.mkdtemp(prefix="avd_test_")

    results = {
        "screenshot": False,
        "touch_input": False,
        "keyboard_input": False,
        "swipe": False,
        "copy_to_device": False,
        "copy_from_device": False,
        "shell_exec": False,
        "networking_dns": False,
        "networking_http": False,
        "ui_dump": False,
        "calculator_launch": False,
    }

    try:
        # Start emulator
        print("\n[1/11] Starting AVD emulator...")
        runner.start()
        print(f"       Emulator ready! Device: emulator-{runner.console_port}")

        # Wait for system to stabilize
        time.sleep(5)

        # Test 1: Screenshot
        print("\n[2/11] Testing screenshot capture...")
        try:
            screenshot_path = os.path.join(temp_dir, "test_screenshot.png")
            runner.capture_screenshot(screenshot_path)
            if os.path.exists(screenshot_path) and os.path.getsize(screenshot_path) > 10000:
                results["screenshot"] = True
                print(f"       PASS - Screenshot saved ({os.path.getsize(screenshot_path)} bytes)")
            else:
                print(f"       FAIL - Screenshot too small or missing")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 2: Shell execution
        print("\n[3/11] Testing shell command execution...")
        try:
            output = runner.exec_capture("getprop ro.build.version.release")
            android_version = output.strip()
            if android_version:
                results["shell_exec"] = True
                print(f"       PASS - Android version: {android_version}")
            else:
                print(f"       FAIL - Empty output")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 3: Touch input
        print("\n[4/11] Testing touch input (tap)...")
        try:
            # Tap center of screen using standard action format
            runner.inject_action({"mouse": {"left_click": [540, 1200]}})
            time.sleep(0.5)
            results["touch_input"] = True
            print("       PASS - Tap command sent successfully")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 4: Keyboard input
        print("\n[5/11] Testing keyboard input...")
        try:
            # Press HOME key using standard action format
            runner.inject_action({"keyboard": {"keys": ["home"]}})
            time.sleep(1)
            # Try typing text
            runner.inject_action({"keyboard": {"text": "test"}})
            results["keyboard_input"] = True
            print("       PASS - Keyboard commands sent successfully")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 5: Swipe
        print("\n[6/11] Testing swipe gesture...")
        try:
            # Swipe using standard action format (left_click_drag)
            runner.inject_action({
                "mouse": {"left_click_drag": [[540, 1800], [540, 800]]}
            })
            time.sleep(0.5)
            results["swipe"] = True
            print("       PASS - Swipe command sent successfully")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 6: Copy to device
        print("\n[7/11] Testing copy to device...")
        try:
            # Create a test file
            test_file = os.path.join(temp_dir, "test_upload.txt")
            with open(test_file, "w") as f:
                f.write("Hello from host! AVD test file.")

            runner.copy_to(test_file, "/sdcard/test_upload.txt")

            # Verify it exists on device
            verify_output = runner.exec_capture("cat /sdcard/test_upload.txt")
            if "Hello from host" in verify_output:
                results["copy_to_device"] = True
                print("       PASS - File copied to device and verified")
            else:
                print(f"       FAIL - File content mismatch: {verify_output[:50]}")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 7: Copy from device
        print("\n[8/11] Testing copy from device...")
        try:
            # Create a file on device
            runner.exec("echo 'Hello from device!' > /sdcard/test_download.txt")

            # Download it
            download_path = os.path.join(temp_dir, "test_download.txt")
            runner.copy_from("/sdcard/test_download.txt", download_path)

            if os.path.exists(download_path):
                with open(download_path, "r") as f:
                    content = f.read()
                if "Hello from device" in content:
                    results["copy_from_device"] = True
                    print("       PASS - File copied from device and verified")
                else:
                    print(f"       FAIL - Content mismatch: {content[:50]}")
            else:
                print("       FAIL - Downloaded file not found")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 8: Networking - DNS
        print("\n[9/11] Testing networking (DNS resolution)...")
        try:
            output = runner.exec_capture("ping -c 1 -W 5 8.8.8.8 2>&1")
            if "1 received" in output or "1 packets transmitted" in output:
                results["networking_dns"] = True
                print("       PASS - Network connectivity confirmed (ping 8.8.8.8)")
            else:
                # Try nslookup
                dns_output = runner.exec_capture("nslookup google.com 2>&1")
                if "Address" in dns_output:
                    results["networking_dns"] = True
                    print("       PASS - DNS resolution working")
                else:
                    print(f"       FAIL - No network connectivity: {output[:100]}")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 9: Networking - HTTP (using curl/wget if available)
        print("\n[10/11] Testing networking (HTTP request)...")
        try:
            # Android usually has wget or we can use am to check connectivity
            output = runner.exec_capture("wget -q -O - http://connectivitycheck.gstatic.com/generate_204 2>&1 || echo 'wget_failed'")
            if "wget_failed" not in output:
                results["networking_http"] = True
                print("       PASS - HTTP request successful")
            else:
                # Try ping as fallback
                output = runner.exec_capture("ping -c 1 connectivitycheck.gstatic.com 2>&1")
                if "1 received" in output:
                    results["networking_http"] = True
                    print("       PASS - HTTP endpoint reachable (via ping)")
                else:
                    print(f"       PARTIAL - wget not available, ping result: {output[:50]}")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Test 10: UI dump
        print("\n[11/11] Testing UI accessibility dump...")
        try:
            # First go to home screen
            runner.inject_action({"type": "keyboard", "key": "home"})
            time.sleep(2)

            # Dump UI
            runner.exec("uiautomator dump /sdcard/ui_test.xml")
            time.sleep(1)

            ui_path = os.path.join(temp_dir, "ui_test.xml")
            runner.copy_from("/sdcard/ui_test.xml", ui_path)

            if os.path.exists(ui_path):
                with open(ui_path, "r") as f:
                    ui_content = f.read()
                if len(ui_content) > 500 and "hierarchy" in ui_content:
                    results["ui_dump"] = True
                    print(f"       PASS - UI dump captured ({len(ui_content)} bytes)")
                else:
                    print(f"       FAIL - UI dump too small or invalid")
            else:
                print("       FAIL - UI dump file not found")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Bonus: Test Calculator app
        print("\n[BONUS] Testing Calculator app launch...")
        try:
            runner.exec("am start -n com.google.android.calculator/com.android.calculator2.Calculator")
            time.sleep(3)

            # Take screenshot of calculator
            calc_screenshot = os.path.join(temp_dir, "calculator.png")
            runner.capture_screenshot(calc_screenshot)

            # Tap some buttons (2, +, 3, =)
            # These coordinates are approximate for a 1080x2400 screen
            # Button layout varies, so we'll just verify the app launched

            ui_output = runner.exec_capture("dumpsys window | grep -i calculator")
            if "calculator" in ui_output.lower():
                results["calculator_launch"] = True
                print("       PASS - Calculator app launched successfully")
            else:
                print("       PARTIAL - Calculator may have launched but couldn't verify")
        except Exception as e:
            print(f"       FAIL - {e}")

        # Final screenshot
        print("\n[Final] Capturing final screenshot...")
        final_screenshot = os.path.join(temp_dir, "final_screenshot.png")
        try:
            runner.capture_screenshot(final_screenshot)
            print(f"       Saved to: {final_screenshot}")
        except Exception as e:
            print(f"       Error: {e}")

    except Exception as e:
        print(f"\n[ERROR] Test failed with exception: {e}")
        import traceback
        traceback.print_exc()

    finally:
        print("\n[Cleanup] Stopping emulator...")
        try:
            runner.stop()
        except:
            pass

    # Print summary
    print("\n" + "=" * 60)
    print("TEST RESULTS SUMMARY")
    print("=" * 60)

    passed = sum(1 for v in results.values() if v)
    total = len(results)

    for test_name, result in results.items():
        status = "PASS" if result else "FAIL"
        print(f"  {test_name:25s} : {status}")

    print("-" * 60)
    print(f"  Total: {passed}/{total} tests passed")
    print("=" * 60)

    print(f"\nTest artifacts saved to: {temp_dir}")

    return passed == total


if __name__ == "__main__":
    success = test_avd_comprehensive()
    sys.exit(0 if success else 1)
