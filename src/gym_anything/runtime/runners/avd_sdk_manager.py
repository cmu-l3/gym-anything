"""
Android SDK Manager for AVD Emulation.

Downloads and manages Android SDK components needed for running AVD emulators:
- cmdline-tools (sdkmanager, avdmanager)
- emulator
- platform-tools (adb)
- system-images

All components are cached in ~/.cache/gym-anything/android-sdk/
"""

from __future__ import annotations

import os
import shutil
import subprocess
import zipfile
from pathlib import Path
from typing import List, Optional, Tuple
import urllib.request
import sys
import tempfile


# SDK component URLs and versions
# Command-line tools: https://developer.android.com/studio#command-tools
CMDLINE_TOOLS_VERSION = "11076708"  # Latest as of 2024
_CMDLINE_TOOLS_PLATFORM = "mac" if sys.platform == "darwin" else "linux"
CMDLINE_TOOLS_URL = f"https://dl.google.com/android/repository/commandlinetools-{_CMDLINE_TOOLS_PLATFORM}-{CMDLINE_TOOLS_VERSION}_latest.zip"

# Default cache directory
DEFAULT_CACHE_DIR = Path.home() / ".cache" / "gym-anything"

# Available system image configurations
SYSTEM_IMAGE_VARIANTS = {
    "default": "default",
    "google_apis": "google_apis",
    "google_apis_playstore": "google_apis_playstore",
}

# API level to Android version mapping
API_VERSIONS = {
    35: "Android 15",
    34: "Android 14",
    33: "Android 13",
    32: "Android 12L",
    31: "Android 12",
    30: "Android 11",
    29: "Android 10",
    28: "Android 9",
}


class AVDSDKManager:
    """Manages Android SDK components for AVD emulation."""

    def __init__(self, cache_dir: Optional[Path] = None):
        """Initialize SDK manager.

        Args:
            cache_dir: Base cache directory. Defaults to ~/.cache/gym-anything/
        """
        self.cache_dir = cache_dir or DEFAULT_CACHE_DIR
        self.sdk_root = self.cache_dir / "android-sdk"
        self.avd_home = self.cache_dir / "avd"

        # SDK component paths
        self.cmdline_tools_dir = self.sdk_root / "cmdline-tools" / "latest"
        self.emulator_dir = self.sdk_root / "emulator"
        self.platform_tools_dir = self.sdk_root / "platform-tools"
        self.system_images_dir = self.sdk_root / "system-images"

        # Binary paths
        self.sdkmanager = self.cmdline_tools_dir / "bin" / "sdkmanager"
        self.avdmanager = self.cmdline_tools_dir / "bin" / "avdmanager"
        self.emulator_bin = self.emulator_dir / "emulator"
        self.adb = self.platform_tools_dir / "adb"

    def _run_cmd(self, cmd: List[str], env: Optional[dict] = None,
                 check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
        """Run a command with proper environment."""
        full_env = os.environ.copy()
        full_env["ANDROID_SDK_ROOT"] = str(self.sdk_root)
        full_env["ANDROID_AVD_HOME"] = str(self.avd_home)
        # EMULATOR_HOME is parent of AVD_HOME (~/.android)
        full_env["ANDROID_EMULATOR_HOME"] = str(self.avd_home.parent)
        # Accept licenses automatically
        full_env["ANDROID_SDK_ACCEPT_LICENSE"] = "y"
        if env:
            full_env.update(env)

        return subprocess.run(
            cmd,
            env=full_env,
            check=check,
            capture_output=capture,
            text=True
        )

    def _download_file(self, url: str, dest: Path, desc: str = "Downloading") -> None:
        """Download a file with progress indication."""
        print(f"[AVD SDK] {desc}: {url}")

        def progress_hook(count, block_size, total_size):
            if total_size > 0:
                percent = min(100, count * block_size * 100 // total_size)
                if count % 100 == 0:
                    print(f"[AVD SDK] Progress: {percent}%", end="\r")

        dest.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(url, dest, progress_hook)
        print(f"[AVD SDK] Downloaded: {dest}")

    def ensure_cmdline_tools(self) -> bool:
        """Download and install command-line tools if not present.

        Returns:
            True if tools are available, False on error.
        """
        if self.sdkmanager.exists() and self.avdmanager.exists():
            print("[AVD SDK] Command-line tools already installed")
            return True

        print("[AVD SDK] Installing command-line tools...")

        # Download
        zip_path = self.cache_dir / "cmdline-tools.zip"
        try:
            self._download_file(CMDLINE_TOOLS_URL, zip_path, "Downloading command-line tools")
        except Exception as e:
            print(f"[AVD SDK] Failed to download command-line tools: {e}")
            return False

        # Extract
        try:
            extract_dir = self.sdk_root / "cmdline-tools"
            extract_dir.mkdir(parents=True, exist_ok=True)

            with zipfile.ZipFile(zip_path, 'r') as zf:
                zf.extractall(extract_dir)

            # Move to 'latest' directory (SDK manager expects this structure)
            extracted = extract_dir / "cmdline-tools"
            if extracted.exists():
                if self.cmdline_tools_dir.exists():
                    shutil.rmtree(self.cmdline_tools_dir)
                extracted.rename(self.cmdline_tools_dir)

            # Make binaries executable
            for binary in ["sdkmanager", "avdmanager"]:
                bin_path = self.cmdline_tools_dir / "bin" / binary
                if bin_path.exists():
                    bin_path.chmod(0o755)

            print("[AVD SDK] Command-line tools installed")
            return True

        except Exception as e:
            print(f"[AVD SDK] Failed to extract command-line tools: {e}")
            return False
        finally:
            # Cleanup zip
            if zip_path.exists():
                zip_path.unlink()

    def accept_licenses(self) -> bool:
        """Accept all SDK licenses."""
        if not self.sdkmanager.exists():
            return False

        print("[AVD SDK] Accepting licenses...")
        try:
            # Pipe 'y' to accept all licenses
            result = subprocess.run(
                [str(self.sdkmanager), "--licenses"],
                input="y\n" * 20,  # Accept all
                env={
                    **os.environ,
                    "ANDROID_SDK_ROOT": str(self.sdk_root),
                },
                capture_output=True,
                text=True,
                timeout=60
            )
            return True
        except Exception as e:
            print(f"[AVD SDK] License acceptance error (may be ok): {e}")
            return True  # Often fails but licenses are accepted

    def ensure_emulator(self) -> bool:
        """Download and install emulator if not present.

        Returns:
            True if emulator is available, False on error.
        """
        if self.emulator_bin.exists():
            print("[AVD SDK] Emulator already installed")
            return True

        if not self.sdkmanager.exists():
            if not self.ensure_cmdline_tools():
                return False

        print("[AVD SDK] Installing emulator...")
        try:
            self._run_cmd([
                str(self.sdkmanager),
                "--install", "emulator"
            ])

            # Make emulator executable
            if self.emulator_bin.exists():
                self.emulator_bin.chmod(0o755)
                print("[AVD SDK] Emulator installed")
                return True
            else:
                print("[AVD SDK] Emulator binary not found after install")
                return False

        except subprocess.CalledProcessError as e:
            print(f"[AVD SDK] Failed to install emulator: {e}")
            return False

    def ensure_platform_tools(self) -> bool:
        """Download and install platform-tools (adb) if not present.

        Returns:
            True if platform-tools are available, False on error.
        """
        if self.adb.exists():
            print("[AVD SDK] Platform-tools already installed")
            return True

        if not self.sdkmanager.exists():
            if not self.ensure_cmdline_tools():
                return False

        print("[AVD SDK] Installing platform-tools...")
        try:
            self._run_cmd([
                str(self.sdkmanager),
                "--install", "platform-tools"
            ])

            if self.adb.exists():
                self.adb.chmod(0o755)
                print("[AVD SDK] Platform-tools installed")
                return True
            else:
                print("[AVD SDK] ADB binary not found after install")
                return False

        except subprocess.CalledProcessError as e:
            print(f"[AVD SDK] Failed to install platform-tools: {e}")
            return False

    def get_system_image_path(self, api_level: int, variant: str = "google_apis_playstore",
                               arch: str = "x86_64") -> str:
        """Get the SDK manager path string for a system image.

        Args:
            api_level: Android API level (e.g., 35 for Android 15)
            variant: Image variant (default, google_apis, google_apis_playstore)
            arch: Architecture (x86_64, x86, arm64-v8a)

        Returns:
            SDK manager package path string.
        """
        return f"system-images;android-{api_level};{variant};{arch}"

    def ensure_system_image(self, api_level: int, variant: str = "google_apis_playstore",
                            arch: str = "x86_64") -> bool:
        """Download system image if not present.

        Args:
            api_level: Android API level (e.g., 35 for Android 15)
            variant: Image variant (default, google_apis, google_apis_playstore)
            arch: Architecture (x86_64, x86, arm64-v8a)

        Returns:
            True if system image is available, False on error.
        """
        image_path = self.system_images_dir / f"android-{api_level}" / variant / arch
        if image_path.exists() and (image_path / "system.img").exists():
            print(f"[AVD SDK] System image already installed: API {api_level} ({variant}, {arch})")
            return True

        if not self.sdkmanager.exists():
            if not self.ensure_cmdline_tools():
                return False

        package = self.get_system_image_path(api_level, variant, arch)
        print(f"[AVD SDK] Installing system image: {package}")

        try:
            self._run_cmd([
                str(self.sdkmanager),
                "--install", package
            ])

            if image_path.exists():
                print(f"[AVD SDK] System image installed: {package}")
                return True
            else:
                print(f"[AVD SDK] System image directory not found after install")
                return False

        except subprocess.CalledProcessError as e:
            print(f"[AVD SDK] Failed to install system image: {e}")
            # Try alternative variant if playstore not available
            if variant == "google_apis_playstore":
                print("[AVD SDK] Trying google_apis variant instead...")
                return self.ensure_system_image(api_level, "google_apis", arch)
            return False

    def ensure_all(self, api_level: int = 35, variant: str = "google_apis_playstore",
                   arch: str = "x86_64") -> bool:
        """Ensure all SDK components are installed.

        Args:
            api_level: Android API level
            variant: System image variant
            arch: Architecture

        Returns:
            True if all components are ready, False on error.
        """
        print(f"[AVD SDK] Ensuring SDK components for API {api_level}...")

        if not self.ensure_cmdline_tools():
            return False

        self.accept_licenses()

        if not self.ensure_platform_tools():
            return False

        if not self.ensure_emulator():
            return False

        if not self.ensure_system_image(api_level, variant, arch):
            return False

        print("[AVD SDK] All components ready")
        return True

    def get_avd_path(self, name: str) -> Path:
        """Get the path to an AVD directory."""
        return self.avd_home / f"{name}.avd"

    def avd_exists(self, name: str) -> bool:
        """Check if an AVD exists."""
        avd_dir = self.get_avd_path(name)
        ini_file = self.avd_home / f"{name}.ini"
        return avd_dir.exists() and ini_file.exists()

    def create_avd(self, name: str, api_level: int = 35,
                   variant: str = "google_apis_playstore",
                   arch: str = "x86_64",
                   device: str = "pixel_6") -> bool:
        """Create an AVD configuration.

        Args:
            name: AVD name
            api_level: Android API level
            variant: System image variant
            arch: Architecture
            device: Device profile (pixel_6, pixel_7, etc.)

        Returns:
            True if AVD was created/exists, False on error.
        """
        if self.avd_exists(name):
            print(f"[AVD SDK] AVD already exists: {name}")
            return True

        if not self.avdmanager.exists():
            if not self.ensure_cmdline_tools():
                return False

        # Ensure system image is installed
        if not self.ensure_system_image(api_level, variant, arch):
            return False

        # Create AVD home directory
        self.avd_home.mkdir(parents=True, exist_ok=True)

        package = self.get_system_image_path(api_level, variant, arch)
        print(f"[AVD SDK] Creating AVD: {name} (device={device}, package={package})")

        try:
            # Create AVD (echo 'no' to decline custom hardware profile)
            result = subprocess.run(
                [
                    str(self.avdmanager),
                    "create", "avd",
                    "--name", name,
                    "--package", package,
                    "--device", device,
                    "--force"
                ],
                input="no\n",
                env={
                    **os.environ,
                    "ANDROID_SDK_ROOT": str(self.sdk_root),
                    "ANDROID_AVD_HOME": str(self.avd_home),
                },
                capture_output=True,
                text=True,
                timeout=120
            )

            if result.returncode != 0:
                print(f"[AVD SDK] avdmanager error: {result.stderr}")
                return False

            # Verify AVD was created
            if self.avd_exists(name):
                print(f"[AVD SDK] AVD created: {name}")
                # Configure AVD for better performance
                self._configure_avd(name)
                return True
            else:
                print(f"[AVD SDK] AVD directory not found after creation")
                return False

        except subprocess.CalledProcessError as e:
            print(f"[AVD SDK] Failed to create AVD: {e}")
            return False
        except subprocess.TimeoutExpired:
            print("[AVD SDK] AVD creation timed out")
            return False

    def _configure_avd(self, name: str) -> None:
        """Configure AVD for optimal headless performance."""
        config_path = self.get_avd_path(name) / "config.ini"
        if not config_path.exists():
            return

        print(f"[AVD SDK] Configuring AVD: {name}")

        # Read existing config
        with open(config_path, 'r') as f:
            config = f.read()

        # Add/update performance settings
        settings = {
            "hw.gpu.enabled": "yes",
            "hw.gpu.mode": "swiftshader_indirect",
            "hw.keyboard": "yes",
            "hw.ramSize": "4096",
            "disk.dataPartition.size": "4G",
            "vm.heapSize": "512",
            "hw.lcd.density": "440",
        }

        lines = config.strip().split('\n')
        existing_keys = set()

        # Parse existing settings
        for line in lines:
            if '=' in line:
                key = line.split('=')[0].strip()
                existing_keys.add(key)

        # Add new settings
        for key, value in settings.items():
            if key not in existing_keys:
                lines.append(f"{key}={value}")

        # Write back
        with open(config_path, 'w') as f:
            f.write('\n'.join(lines) + '\n')

    def list_avds(self) -> List[str]:
        """List available AVDs.

        Returns:
            List of AVD names.
        """
        if not self.avdmanager.exists():
            return []

        try:
            result = self._run_cmd(
                [str(self.avdmanager), "list", "avd", "-c"],
                capture=True
            )
            avds = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
            return avds
        except Exception:
            return []

    def delete_avd(self, name: str) -> bool:
        """Delete an AVD.

        Args:
            name: AVD name

        Returns:
            True if deleted, False on error.
        """
        if not self.avd_exists(name):
            return True

        try:
            self._run_cmd([
                str(self.avdmanager),
                "delete", "avd",
                "--name", name
            ])
            print(f"[AVD SDK] Deleted AVD: {name}")
            return True
        except Exception as e:
            print(f"[AVD SDK] Failed to delete AVD: {e}")
            return False

    def get_sdk_info(self) -> dict:
        """Get information about installed SDK components.

        Returns:
            Dict with component status and paths.
        """
        return {
            "sdk_root": str(self.sdk_root),
            "avd_home": str(self.avd_home),
            "cmdline_tools": {
                "installed": self.sdkmanager.exists(),
                "path": str(self.cmdline_tools_dir),
            },
            "emulator": {
                "installed": self.emulator_bin.exists(),
                "path": str(self.emulator_bin) if self.emulator_bin.exists() else None,
            },
            "platform_tools": {
                "installed": self.adb.exists(),
                "adb_path": str(self.adb) if self.adb.exists() else None,
            },
            "avds": self.list_avds(),
        }

    # ==================== APK Management ====================

    @property
    def apk_dir(self) -> Path:
        """Directory for storing APKs."""
        return self.cache_dir / "apks"

    def ensure_vnc_server_apk(self) -> Optional[Path]:
        """Download droidVNC-NG APK from F-Droid if not present.

        Returns:
            Path to APK file, or None if download failed.
        """
        # droidVNC-NG from F-Droid
        # https://f-droid.org/packages/net.christianbeier.droidvnc_ng/
        apk_name = "droidvnc_ng.apk"
        apk_path = self.apk_dir / apk_name

        if apk_path.exists():
            print(f"[AVD SDK] VNC Server APK already downloaded: {apk_path}")
            return apk_path

        # F-Droid direct download URL (version 2.18.1, build 57)
        url = "https://f-droid.org/repo/net.christianbeier.droidvnc_ng_57.apk"

        try:
            self._download_file(url, apk_path, "Downloading VNC Server APK")
            return apk_path
        except Exception as e:
            print(f"[AVD SDK] Failed to download VNC Server APK: {e}")
            return None

    def ensure_required_apks(self) -> dict:
        """Ensure all required APKs are downloaded.

        Note: Only framework-level APKs (like VNC server) are managed here.
        Task-specific APKs (like calculator) should be bundled with the
        environment and installed via setup hooks.

        Returns:
            Dict with APK paths (None if download failed).
        """
        self.apk_dir.mkdir(parents=True, exist_ok=True)

        return {
            "vnc_server": self.ensure_vnc_server_apk(),
        }


def main():
    """Test SDK manager functionality."""
    import argparse

    parser = argparse.ArgumentParser(description="Android SDK Manager for Gym-Anything")
    parser.add_argument("--install", action="store_true", help="Install all SDK components")
    parser.add_argument("--api", type=int, default=35, help="API level (default: 35)")
    parser.add_argument("--create-avd", type=str, help="Create AVD with given name")
    parser.add_argument("--list-avds", action="store_true", help="List available AVDs")
    parser.add_argument("--info", action="store_true", help="Show SDK info")

    args = parser.parse_args()

    manager = AVDSDKManager()

    if args.info:
        import json
        print(json.dumps(manager.get_sdk_info(), indent=2))
        return

    if args.list_avds:
        avds = manager.list_avds()
        print("Available AVDs:")
        for avd in avds:
            print(f"  - {avd}")
        return

    if args.install:
        success = manager.ensure_all(api_level=args.api)
        print(f"SDK installation: {'SUCCESS' if success else 'FAILED'}")
        return

    if args.create_avd:
        if not manager.ensure_all(api_level=args.api):
            print("Failed to ensure SDK components")
            return
        success = manager.create_avd(args.create_avd, api_level=args.api)
        print(f"AVD creation: {'SUCCESS' if success else 'FAILED'}")
        return

    parser.print_help()


if __name__ == "__main__":
    main()
