from __future__ import annotations

import hashlib
from pathlib import Path


MODAL_NATIVE_IMAGE_SCHEMA = "ubuntu-22.04-v4"

_APT_PACKAGES = [
    "build-essential",
    "ca-certificates",
    "curl",
    "dbus",
    "dbus-x11",
    "dconf-cli",
    "dcraw",
    "docker-compose",
    "docker.io",
    "exiftool",
    "ffmpeg",
    "fonts-dejavu-extra",
    "fonts-firacode",
    "fonts-hack",
    "fonts-liberation",
    "fonts-noto",
    "git",
    "gimp",
    "gimp-data-extras",
    "gimp-gmic",
    "gimp-help-common",
    "gimp-help-en",
    "gimp-plugin-registry",
    "gnome-tweaks",
    "graphicsmagick",
    "imagemagick",
    "inkscape",
    "libgimp2.0-dev",
    "libx11-dev",
    "libxdamage-dev",
    "libxext-dev",
    "libxtst-dev",
    "locales",
    "net-tools",
    "novnc",
    "openssh-server",
    "procps",
    "python3-dev",
    "python3-numpy",
    "python3-pil",
    "python3-pip",
    "python3-scipy",
    "python3-tk",
    "snapd",
    "squashfs-tools",
    "sudo",
    "systemd",
    "systemd-sysv",
    "tigervnc-common",
    "tigervnc-scraping-server",
    "tigervnc-standalone-server",
    "tigervnc-viewer",
    "tigervnc-xorg-extension",
    "ubuntu-desktop",
    "unzip",
    "util-linux",
    "wget",
    "wmctrl",
    "x11-apps",
    "x11-utils",
    "xdotool",
    "xterm",
    "xvfb",
]


def _assets_dir() -> Path:
    return Path(__file__).with_name("modal_native_assets")


def _image_fingerprint() -> str:
    digest = hashlib.sha256()
    digest.update(MODAL_NATIVE_IMAGE_SCHEMA.encode())
    digest.update(Path(__file__).read_bytes())
    for package in _APT_PACKAGES:
        digest.update(package.encode())
        digest.update(b"\0")
    for path in sorted(_assets_dir().iterdir(), key=lambda item: item.name):
        if path.is_file():
            digest.update(path.name.encode())
            digest.update(b"\0")
            digest.update(path.read_bytes())
    return f"{MODAL_NATIVE_IMAGE_SCHEMA}-{digest.hexdigest()[:16]}"


MODAL_NATIVE_IMAGE_FINGERPRINT = _image_fingerprint()


def build_modal_native_image(modal):
    """Build the stable Linux guest image used by ModalNativeRunner."""
    assets = _assets_dir()
    image = (
        modal.Image.from_registry("ubuntu:22.04")
        .env(
            {
                "DEBIAN_FRONTEND": "noninteractive",
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
                "container": "modal",
            }
        )
        .apt_install(*_APT_PACKAGES)
        .add_local_file(
            assets / "bootstrap.sh",
            "/usr/local/sbin/ga-modal-native-bootstrap",
            copy=True,
        )
        .add_local_file(
            assets / "namespace_exec.sh",
            "/usr/local/sbin/ga-nsenter",
            copy=True,
        )
        .add_local_file(
            assets / "systemd_init.sh",
            "/usr/local/sbin/ga-systemd-init",
            copy=True,
        )
        .add_local_file(
            assets / "snap_transitions.sh",
            "/usr/local/sbin/ga-snap-transitions",
            copy=True,
        )
        .add_local_file(
            assets / "snap_mounts.sh",
            "/usr/local/sbin/ga-snap-mounts",
            copy=True,
        )
        .add_local_file(
            assets / "snap_wrapper.sh",
            "/usr/local/sbin/ga-snap-wrapper",
            copy=True,
        )
        .add_local_file(
            assets / "xstartup",
            "/etc/gym-anything/xstartup",
            copy=True,
        )
        .add_local_file(
            assets / "ga-vnc.service",
            "/etc/systemd/system/ga-vnc.service",
            copy=True,
        )
        .add_local_file(
            assets / "ga-fast-io.service",
            "/etc/systemd/system/ga-fast-io.service",
            copy=True,
        )
        .add_local_file(
            assets / "fast_io_server.c",
            "/tmp/ga-modal-native-fast-io.c",
            copy=True,
        )
        .add_local_file(
            assets / "ga-snap-transitions.service",
            "/etc/systemd/system/ga-snap-transitions.service",
            copy=True,
        )
        .run_commands(
            "apt-get purge -y gnome-initial-setup || true; "
            "apt-get remove -y update-notifier || true",
            "gcc -O3 -flto -fopenmp -DNDEBUG -std=c11 -Wall -Wextra -Werror -pthread "
            "/tmp/ga-modal-native-fast-io.c -o /usr/local/bin/ga-modal-native-fast-io "
            "-lX11 -lXext -lXdamage -lXtst; rm /tmp/ga-modal-native-fast-io.c",
            "chmod 0755 /usr/local/sbin/ga-modal-native-bootstrap "
            "/usr/local/sbin/ga-nsenter /usr/local/sbin/ga-systemd-init "
            "/usr/local/sbin/ga-snap-transitions /usr/local/sbin/ga-snap-mounts "
            "/usr/local/sbin/ga-snap-wrapper "
            "/etc/gym-anything/xstartup",
            "ln -sfn /usr/local/sbin/ga-snap-wrapper /usr/local/bin/snap",
            "/usr/local/sbin/ga-snap-transitions prepare",
            "userdel -r ubuntu >/dev/null 2>&1 || true; "
            "id -u ga >/dev/null 2>&1 || useradd ga -u 1000 -U -d /home/ga -m -s /bin/bash",
            "echo 'ga:password123' | chpasswd; "
            "echo 'ga ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ga; "
            "chmod 0440 /etc/sudoers.d/ga; "
            "usermod -aG docker,audio,video ga",
            "install -d -o ga -g ga -m 0700 /home/ga/.vnc; "
            "install -o ga -g ga -m 0755 /etc/gym-anything/xstartup /home/ga/.vnc/xstartup; "
            "install -d -o ga -g ga /home/ga/.config; "
            "touch /home/ga/.config/gnome-initial-setup-done; "
            "chown ga:ga /home/ga/.config/gnome-initial-setup-done",
            "install -d /etc/dconf/db/local.d /etc/dconf/profile; "
            "printf 'user-db:user\\nsystem-db:local\\n' > /etc/dconf/profile/user; "
            "printf '[org/gnome/desktop/screensaver]\\nlock-enabled=false\\nubuntu-lock-on-suspend=false\\n\\n"
            "[org/gnome/desktop/session]\\nidle-delay=uint32 0\\n' "
            "> /etc/dconf/db/local.d/01-disable-lock; dconf update",
            "python3 -m pip install --no-cache-dir pyautogui",
            "systemctl enable docker.service containerd.service ssh.service snapd.socket "
            "ga-snap-transitions.service ga-vnc.service",
            "systemctl disable apport.service whoopsie.service >/dev/null 2>&1 || true",
            "ln -sfn /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html; "
            "mkdir -p /workspace /run/gym-anything; "
            "rm -f /etc/machine-id; touch /etc/machine-id; "
            "rm -rf /var/lib/apt/lists/*",
        )
    )
    return image


__all__ = [
    "MODAL_NATIVE_IMAGE_FINGERPRINT",
    "MODAL_NATIVE_IMAGE_SCHEMA",
    "build_modal_native_image",
]
