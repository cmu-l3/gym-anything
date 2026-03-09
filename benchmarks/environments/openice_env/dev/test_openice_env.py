#!/usr/bin/env python3
"""Interactive test script for OpenICE environment.

Usage:
    python benchmarks/environments/openice_env/dev/test_openice_env.py

This script starts the OpenICE environment and allows for interactive testing.
"""

import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from gym_anything.api import from_config
import paramiko
import time


def test_openice_environment():
    """Test the OpenICE environment setup."""

    print("=" * 60)
    print("OpenICE Environment Interactive Test")
    print("=" * 60)

    # Start environment with first task
    print("\n[1] Starting OpenICE environment...")
    env = from_config("benchmarks/environments/openice_env", task_id="create_simulated_device")

    try:
        # Reset environment (this runs install and setup hooks)
        print("\n[2] Resetting environment (this may take several minutes for first run)...")
        obs = env.reset(seed=42, use_cache=False)

        print("\n[3] Environment started successfully!")

        # Get connection info
        ssh_port = env._runner.ssh_port
        vnc_port = env._runner.vnc_port

        print(f"\n[4] Connection Info:")
        print(f"    SSH Port: {ssh_port}")
        print(f"    VNC Port: {vnc_port}")
        print(f"    SSH: ssh -p {ssh_port} ga@localhost")
        print(f"    Password: password123")

        # Connect via SSH
        print("\n[5] Connecting via SSH...")
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect('localhost', port=ssh_port, username='ga', password='password123')

        # Check installation
        print("\n[6] Checking Java installation...")
        stdin, stdout, stderr = ssh.exec_command('java -version 2>&1')
        java_version = stdout.read().decode()
        print(f"    Java: {java_version[:100]}...")

        # Check OpenICE directory
        print("\n[7] Checking OpenICE installation...")
        stdin, stdout, stderr = ssh.exec_command('ls -la /opt/openice/mdpnp/')
        openice_dir = stdout.read().decode()
        print(f"    OpenICE directory exists: {'gradlew' in openice_dir}")

        # Check if OpenICE is running
        print("\n[8] Checking if OpenICE process is running...")
        stdin, stdout, stderr = ssh.exec_command('pgrep -f "java.*demo-apps" || echo "not running"')
        process_status = stdout.read().decode().strip()
        print(f"    OpenICE process: {process_status}")

        # List windows
        print("\n[9] Listing open windows...")
        stdin, stdout, stderr = ssh.exec_command('DISPLAY=:1 wmctrl -l')
        windows = stdout.read().decode()
        print(f"    Windows:\n{windows}")

        # Check setup logs
        print("\n[10] Checking setup logs...")
        stdin, stdout, stderr = ssh.exec_command('tail -20 /home/ga/env_setup_pre_start.log 2>/dev/null || echo "no pre_start log"')
        pre_start_log = stdout.read().decode()
        print(f"    Pre-start log (last 20 lines):\n{pre_start_log[:500]}...")

        stdin, stdout, stderr = ssh.exec_command('tail -20 /home/ga/env_setup_post_start.log 2>/dev/null || echo "no post_start log"')
        post_start_log = stdout.read().decode()
        print(f"    Post-start log (last 20 lines):\n{post_start_log[:500]}...")

        # Take screenshot
        print("\n[11] Taking screenshot...")
        stdin, stdout, stderr = ssh.exec_command('DISPLAY=:1 scrot /tmp/test_screenshot.png')
        time.sleep(1)

        # Download screenshot
        sftp = ssh.open_sftp()
        local_screenshot = '/tmp/openice_test_screenshot.png'
        try:
            sftp.get('/tmp/test_screenshot.png', local_screenshot)
            print(f"    Screenshot saved to: {local_screenshot}")
        except Exception as e:
            print(f"    Screenshot failed: {e}")
        sftp.close()

        ssh.close()

        print("\n[12] Interactive test complete!")
        print("=" * 60)
        print("You can now:")
        print(f"  1. Connect via VNC: localhost:{vnc_port}")
        print(f"  2. Connect via SSH: ssh -p {ssh_port} ga@localhost")
        print("  3. View screenshot: /tmp/openice_test_screenshot.png")
        print("=" * 60)

        # Keep environment running for manual inspection
        input("\nPress Enter to close the environment...")

    finally:
        print("\n[13] Closing environment...")
        env.close()
        print("Environment closed.")


if __name__ == "__main__":
    test_openice_environment()
