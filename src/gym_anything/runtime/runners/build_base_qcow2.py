#!/usr/bin/env python3
"""
Build base QCOW2 image from Docker image.

Run this script on a machine WITH Docker to create the base QCOW2 image,
then copy the result to your HPC/SLURM cluster.

Usage:
    python -m gym_anything.runners.build_base_qcow2 [options]
    
    # Build from default preset
    python -m gym_anything.runners.build_base_qcow2
    
    # Build from specific Docker image
    python -m gym_anything.runners.build_base_qcow2 --image myimage:latest
    
    # Specify output path
    python -m gym_anything.runners.build_base_qcow2 --output ~/my_base.qcow2

After building, copy the QCOW2 to your HPC cluster:
    scp base_ubuntu_gnome.qcow2 user@hpc:~/.cache/gym-anything/qemu/
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def check_docker():
    """Check if Docker is available."""
    try:
        result = subprocess.run(["docker", "info"], capture_output=True, timeout=10)
        return result.returncode == 0
    except:
        return False


def check_virt_make_fs():
    """Check if virt-make-fs is available."""
    try:
        result = subprocess.run(["virt-make-fs", "--version"], capture_output=True)
        return result.returncode == 0
    except:
        return False


def check_qemu_img():
    """Check if qemu-img is available."""
    try:
        result = subprocess.run(["qemu-img", "--version"], capture_output=True)
        return result.returncode == 0
    except:
        return False


def build_docker_image(preset_name: str = "ubuntu-gnome-systemd_highres_gimp") -> str:
    """Build Docker image from preset and return the tag."""
    from gym_anything.config.presets import load_preset_env_dict
    
    preset = load_preset_env_dict(preset_name)
    dockerfile = preset.get("dockerfile")
    
    if not dockerfile:
        raise RuntimeError(f"Preset {preset_name} has no dockerfile")
    
    dockerfile_path = Path(dockerfile)
    if not dockerfile_path.exists():
        raise RuntimeError(f"Dockerfile not found: {dockerfile_path}")
    
    tag = f"ga/{preset_name}:latest"
    
    print(f"[build] Building Docker image: {tag}")
    print(f"[build] Dockerfile: {dockerfile_path}")
    
    result = subprocess.run(
        ["docker", "build", "-t", tag, "-f", str(dockerfile_path), str(dockerfile_path.parent)],
        capture_output=False
    )
    
    if result.returncode != 0:
        raise RuntimeError("Docker build failed")
    
    return tag


def export_docker_to_qcow2(image: str, output_path: Path, size: str = "50G"):
    """Export Docker image filesystem to QCOW2."""
    print(f"[build] Exporting Docker image to QCOW2...")
    
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)
        tarball = tmpdir / "rootfs.tar"
        
        # Create container
        print(f"[build] Creating container from {image}...")
        result = subprocess.run(
            ["docker", "create", "--name", "ga_export_tmp", image],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"Failed to create container: {result.stderr}")
        
        try:
            # Export filesystem
            print(f"[build] Exporting filesystem...")
            subprocess.run(
                ["docker", "export", "-o", str(tarball), "ga_export_tmp"],
                check=True
            )
            
            # Convert to QCOW2
            print(f"[build] Converting to QCOW2 ({size})...")
            
            if check_virt_make_fs():
                # Use virt-make-fs (best option)
                subprocess.run([
                    "virt-make-fs",
                    "--format=qcow2",
                    f"--size={size}",
                    "--type=ext4",
                    str(tarball),
                    str(output_path)
                ], check=True)
            else:
                # Fallback: manual conversion
                print("[build] Warning: virt-make-fs not found, using manual conversion")
                raw_img = tmpdir / "disk.raw"
                
                # Create raw image
                subprocess.run([
                    "qemu-img", "create", "-f", "raw", str(raw_img), size
                ], check=True)
                
                # Create filesystem
                subprocess.run(["mkfs.ext4", "-F", str(raw_img)], check=True)
                
                # Mount and extract (needs root)
                mount_point = tmpdir / "mnt"
                mount_point.mkdir()
                
                subprocess.run(["sudo", "mount", "-o", "loop", str(raw_img), str(mount_point)], check=True)
                try:
                    subprocess.run(["sudo", "tar", "-xf", str(tarball), "-C", str(mount_point)], check=True)
                finally:
                    subprocess.run(["sudo", "umount", str(mount_point)], check=True)
                
                # Convert to QCOW2
                subprocess.run([
                    "qemu-img", "convert", "-f", "raw", "-O", "qcow2",
                    str(raw_img), str(output_path)
                ], check=True)
            
            print(f"[build] QCOW2 created: {output_path}")
            
        finally:
            # Cleanup container
            subprocess.run(["docker", "rm", "-f", "ga_export_tmp"], capture_output=True)


def make_bootable(qcow2_path: Path):
    """Add bootloader to QCOW2 (optional, for direct VM boot)."""
    print(f"[build] Note: For direct QEMU boot, you may need to install a bootloader")
    print(f"[build] The gym-anything runner uses cloud images with kernel args, so this is optional")


def main():
    parser = argparse.ArgumentParser(description="Build base QCOW2 from Docker image")
    parser.add_argument("--image", help="Docker image to export (default: build from preset)")
    parser.add_argument("--preset", default="ubuntu-gnome-systemd_highres_gimp", 
                       help="Preset name to build (default: ubuntu-gnome-systemd_highres_gimp)")
    parser.add_argument("--output", "-o", 
                       default=str(Path.home() / ".cache/gym-anything/qemu/base_ubuntu_gnome.qcow2"),
                       help="Output QCOW2 path")
    parser.add_argument("--size", default="50G", help="Disk size (default: 50G)")
    
    args = parser.parse_args()
    
    # Check prerequisites
    print("[build] Checking prerequisites...")
    
    if not check_docker():
        print("ERROR: Docker is not available. This script must be run on a machine with Docker.")
        sys.exit(1)
    print("[build] ✓ Docker available")
    
    if not check_qemu_img():
        print("WARNING: qemu-img not found. Install: apt install qemu-utils")
    
    if check_virt_make_fs():
        print("[build] ✓ virt-make-fs available (will use for conversion)")
    else:
        print("[build] ⚠ virt-make-fs not found (will use manual conversion, needs sudo)")
    
    # Get Docker image
    if args.image:
        docker_image = args.image
    else:
        docker_image = build_docker_image(args.preset)
    
    # Create output directory
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Export to QCOW2
    export_docker_to_qcow2(docker_image, output_path, args.size)
    
    print(f"\n{'='*60}")
    print(f"SUCCESS! Base QCOW2 created: {output_path}")
    print(f"{'='*60}")
    print(f"\nNext steps:")
    print(f"1. Copy to your HPC cluster:")
    print(f"   scp {output_path} user@hpc:~/.cache/gym-anything/qemu/")
    print(f"\n2. Run your experiments with:")
    print(f"   export GYM_ANYTHING_RUNNER=qemu")
    print(f"   python -m agents.evaluation.run_single ...")


if __name__ == "__main__":
    main()
