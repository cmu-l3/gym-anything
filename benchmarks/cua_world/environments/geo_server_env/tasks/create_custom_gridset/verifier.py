#!/usr/bin/env python3
"""Verifier for create_custom_gridset task."""

import json
import tempfile
import os
import math

def verify_create_custom_gridset(traj, env_info, task_info):
    """Verify that the custom gridset was created and assigned to the layer correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_gridset_name', 'EPSG3035_Europe')
    expected_crs = metadata.get('expected_crs', 'EPSG:3035')
    expected_bounds = metadata.get('expected_bounds', {})
    expected_tile_size = metadata.get('expected_tile_size', 256)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_custom_gridset_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Gridset Exists (20 points)
    if result.get('gridset_exists'):
        score += 20
        feedback_parts.append(f"Gridset '{expected_name}' created")
    else:
        return {"passed": False, "score": 0, "feedback": f"Gridset '{expected_name}' NOT found"}

    # 2. Correct SRS (15 points)
    # Allow EPSG:3035 or just 3035
    gridset_srs = result.get('gridset_srs', '')
    if '3035' in gridset_srs:
        score += 15
        feedback_parts.append(f"Correct CRS ({gridset_srs})")
    else:
        feedback_parts.append(f"Incorrect CRS: found '{gridset_srs}' (expected {expected_crs})")

    # 3. Correct Tile Size (10 points)
    width = int(result.get('tile_width', 0))
    height = int(result.get('tile_height', 0))
    if width == expected_tile_size and height == expected_tile_size:
        score += 10
        feedback_parts.append(f"Correct tile size ({width}x{height})")
    else:
        feedback_parts.append(f"Incorrect tile size: {width}x{height}")

    # 4. Correct Bounds (15 points)
    # Check within tolerance (e.g., 10%)
    res_bounds = result.get('bounds', {})
    
    def parse_float(val):
        try:
            return float(val)
        except (ValueError, TypeError):
            return None

    minx = parse_float(res_bounds.get('minx'))
    miny = parse_float(res_bounds.get('miny'))
    maxx = parse_float(res_bounds.get('maxx'))
    maxy = parse_float(res_bounds.get('maxy'))
    
    exp_minx = expected_bounds.get('minx')
    exp_miny = expected_bounds.get('miny')
    exp_maxx = expected_bounds.get('maxx')
    exp_maxy = expected_bounds.get('maxy')

    bounds_ok = True
    if None in [minx, miny, maxx, maxy]:
        bounds_ok = False
        feedback_parts.append("Bounds not defined correctly")
    else:
        # Check tolerance (allow small epsilon for float differences)
        epsilon = 1.0 # 1 meter tolerance
        if (abs(minx - exp_minx) > epsilon or abs(miny - exp_miny) > epsilon or
            abs(maxx - exp_maxx) > epsilon or abs(maxy - exp_maxy) > epsilon):
            bounds_ok = False
            feedback_parts.append(f"Bounds mismatch. Found: [{minx}, {miny}, {maxx}, {maxy}]")
        else:
            score += 15
            feedback_parts.append("Bounds match expected European extent")

    # 5. Sufficient Zoom Levels (10 points)
    zoom_levels = int(result.get('zoom_levels', 0))
    if zoom_levels >= 4:
        score += 10
        feedback_parts.append(f"Zoom levels defined: {zoom_levels}")
    else:
        feedback_parts.append(f"Insufficient zoom levels: {zoom_levels} (expected >= 4)")

    # 6. Layer Assignment (25 points)
    if result.get('layer_configured'):
        score += 25
        feedback_parts.append("Gridset correctly assigned to layer 'ne:ne_countries'")
    else:
        feedback_parts.append("Gridset NOT assigned to layer 'ne:ne_countries'")

    # 7. Anti-gaming / VLM (5 points)
    # Verify GUI interaction was detected (programmatic API bypass check)
    if result.get('gui_interaction_detected'):
        score += 5
        feedback_parts.append("GUI interaction confirmed")
    else:
        feedback_parts.append("No GUI interaction detected (possible API script used)")

    # VLM Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, num_samples=3)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt=(
                        "These images show a user working in GeoServer. "
                        "Do you see the user configuring 'Gridsets' or 'Tile Caching' settings? "
                        "Look for forms with fields like 'Grid Set Name', 'Coordinate Reference System', or 'Tile Dimensions'. "
                        "Return JSON: {\"gridset_config_visible\": bool}"
                    )
                )
                if isinstance(vlm_result, dict) and vlm_result.get('success'):
                    if not vlm_result.get('parsed', {}).get('gridset_config_visible', False):
                        # If VLM strongly says NO config happened, penalize slightly but don't fail if programmatic checks passed
                        pass 
        except Exception as e:
            print(f"VLM check failed: {e}")

    # Final logic
    # Pass if Gridset Exists AND Layer is Configured
    passed = result.get('gridset_exists') and result.get('layer_configured') and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }