#!/usr/bin/env python3
"""Verification utilities for Blender 3D environment tasks."""

import json
import os
import tempfile
from pathlib import Path
from typing import Any, Callable, Dict, Optional, Tuple


def setup_verification_environment(
    copy_from_env: Callable[[str, str], None],
    files_to_copy: Dict[str, str]
) -> Dict[str, Any]:
    """
    Copy files from the environment to local temp directory for verification.

    Args:
        copy_from_env: Function to copy files from container
        files_to_copy: Dict mapping container paths to file type hints
                       e.g., {"/tmp/result.json": "json", "/home/ga/render.png": "image"}

    Returns:
        Dict with local paths to copied files and any parse errors
    """
    result = {
        "files": {},
        "errors": []
    }

    for container_path, file_type in files_to_copy.items():
        try:
            suffix = Path(container_path).suffix or f".{file_type}"
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
            temp_path = temp_file.name
            temp_file.close()

            copy_from_env(container_path, temp_path)

            result["files"][container_path] = {
                "local_path": temp_path,
                "file_type": file_type,
                "exists": os.path.exists(temp_path),
                "size": os.path.getsize(temp_path) if os.path.exists(temp_path) else 0
            }

            # Parse JSON files automatically
            if file_type == "json" and os.path.exists(temp_path):
                try:
                    with open(temp_path, 'r') as f:
                        result["files"][container_path]["data"] = json.load(f)
                except json.JSONDecodeError as e:
                    result["errors"].append(f"JSON parse error for {container_path}: {e}")

        except Exception as e:
            result["errors"].append(f"Failed to copy {container_path}: {e}")
            result["files"][container_path] = {
                "local_path": None,
                "file_type": file_type,
                "exists": False,
                "error": str(e)
            }

    return result


def verify_render_output(
    image_path: str,
    expected_width: int = 1920,
    expected_height: int = 1080,
    min_size_kb: int = 50,
    expected_format: str = "PNG"
) -> Dict[str, Any]:
    """
    Verify a rendered image output from Blender.

    Args:
        image_path: Local path to the rendered image
        expected_width: Expected width in pixels
        expected_height: Expected height in pixels
        min_size_kb: Minimum file size in KB
        expected_format: Expected image format (PNG, JPEG, etc.)

    Returns:
        Dict with verification results
    """
    result = {
        "valid": False,
        "exists": False,
        "size_kb": 0,
        "width": 0,
        "height": 0,
        "format": None,
        "checks": {
            "file_exists": False,
            "size_ok": False,
            "width_ok": False,
            "height_ok": False,
            "format_ok": False
        },
        "errors": []
    }

    if not os.path.exists(image_path):
        result["errors"].append("Image file does not exist")
        return result

    result["exists"] = True
    result["checks"]["file_exists"] = True
    result["size_kb"] = os.path.getsize(image_path) / 1024

    try:
        from PIL import Image
        img = Image.open(image_path)

        result["width"] = img.width
        result["height"] = img.height
        result["format"] = img.format

        # Check dimensions
        result["checks"]["width_ok"] = abs(img.width - expected_width) <= 10
        result["checks"]["height_ok"] = abs(img.height - expected_height) <= 10

        # Check format
        result["checks"]["format_ok"] = img.format == expected_format

        # Check size
        result["checks"]["size_ok"] = result["size_kb"] >= min_size_kb

        # Overall validity
        result["valid"] = all([
            result["checks"]["file_exists"],
            result["checks"]["size_ok"],
            result["checks"]["width_ok"],
            result["checks"]["height_ok"]
        ])

    except ImportError:
        result["errors"].append("PIL not available for image verification")
    except Exception as e:
        result["errors"].append(f"Image verification error: {e}")

    return result


def verify_blend_file(
    blend_path: str,
    expected_objects: Optional[list] = None,
    min_object_count: int = 1
) -> Dict[str, Any]:
    """
    Verify a Blender file meets certain criteria.

    This function checks the blend file's metadata without running Blender.
    For detailed scene analysis, use get_scene_metadata with Blender.

    Args:
        blend_path: Path to the .blend file
        expected_objects: List of expected object names (optional)
        min_object_count: Minimum number of objects expected

    Returns:
        Dict with verification results
    """
    result = {
        "valid": False,
        "exists": False,
        "size_kb": 0,
        "errors": []
    }

    if not os.path.exists(blend_path):
        result["errors"].append("Blend file does not exist")
        return result

    result["exists"] = True
    result["size_kb"] = os.path.getsize(blend_path) / 1024

    # Check if it's a valid Blender file by checking magic bytes
    try:
        with open(blend_path, 'rb') as f:
            magic = f.read(7)
            if magic == b'BLENDER':
                result["valid"] = True
            else:
                result["errors"].append("File is not a valid Blender file")
    except Exception as e:
        result["errors"].append(f"Error reading blend file: {e}")

    return result


def get_scene_metadata(
    blend_path: str,
    blender_path: str = "/opt/blender/blender"
) -> Dict[str, Any]:
    """
    Get metadata from a Blender scene file using Blender's Python API.

    Args:
        blend_path: Path to the .blend file
        blender_path: Path to Blender executable

    Returns:
        Dict with scene metadata
    """
    import subprocess
    import tempfile

    script = '''
import bpy
import json
import sys

# The blend file is passed as the last argument before --
blend_file = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else None
if blend_file:
    bpy.ops.wm.open_mainfile(filepath=blend_file)

scene = bpy.context.scene
info = {
    "scene_name": scene.name,
    "frame_start": scene.frame_start,
    "frame_end": scene.frame_end,
    "frame_current": scene.frame_current,
    "render_engine": scene.render.engine,
    "resolution_x": scene.render.resolution_x,
    "resolution_y": scene.render.resolution_y,
    "object_count": len(bpy.data.objects),
    "mesh_count": len(bpy.data.meshes),
    "material_count": len(bpy.data.materials),
    "camera_count": len([o for o in bpy.data.objects if o.type == "CAMERA"]),
    "light_count": len([o for o in bpy.data.objects if o.type == "LIGHT"]),
    "objects": [{"name": o.name, "type": o.type} for o in bpy.data.objects]
}

# Output as JSON on a single line
print("SCENE_JSON:" + json.dumps(info))
'''

    try:
        # Write script to temp file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(script)
            script_path = f.name

        # Run Blender with the script
        cmd = [blender_path, "--background", "--python", script_path, "--", blend_path]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

        # Parse output
        for line in result.stdout.split('\n'):
            if line.startswith('SCENE_JSON:'):
                return json.loads(line[11:])

        return {"error": "Could not parse Blender output"}

    except subprocess.TimeoutExpired:
        return {"error": "Blender timed out"}
    except Exception as e:
        return {"error": str(e)}
    finally:
        if 'script_path' in locals():
            try:
                os.unlink(script_path)
            except:
                pass


def compare_images(
    image1_path: str,
    image2_path: str,
    threshold: float = 0.95
) -> Dict[str, Any]:
    """
    Compare two images for similarity.

    Args:
        image1_path: Path to first image
        image2_path: Path to second image
        threshold: Similarity threshold (0-1) for passing

    Returns:
        Dict with comparison results
    """
    result = {
        "similar": False,
        "similarity": 0.0,
        "errors": []
    }

    try:
        from PIL import Image
        import numpy as np

        img1 = Image.open(image1_path).convert('RGB')
        img2 = Image.open(image2_path).convert('RGB')

        # Resize to same dimensions if needed
        if img1.size != img2.size:
            img2 = img2.resize(img1.size)

        # Convert to numpy arrays
        arr1 = np.array(img1, dtype=np.float32)
        arr2 = np.array(img2, dtype=np.float32)

        # Calculate normalized cross-correlation
        diff = np.abs(arr1 - arr2)
        max_diff = 255.0 * 3 * arr1.shape[0] * arr1.shape[1]  # Max possible difference
        actual_diff = np.sum(diff)

        similarity = 1.0 - (actual_diff / max_diff)
        result["similarity"] = float(similarity)
        result["similar"] = similarity >= threshold

    except ImportError:
        result["errors"].append("PIL/numpy not available for image comparison")
    except Exception as e:
        result["errors"].append(f"Image comparison error: {e}")

    return result


def cleanup_temp_files(verification_result: Dict[str, Any]) -> None:
    """
    Clean up temporary files created during verification.

    Args:
        verification_result: Result from setup_verification_environment
    """
    if "files" not in verification_result:
        return

    for file_info in verification_result["files"].values():
        local_path = file_info.get("local_path")
        if local_path and os.path.exists(local_path):
            try:
                os.unlink(local_path)
            except:
                pass
