#!/usr/bin/env python3
"""
Verifier for fix_broken_particle_sim task.

Scoring breakdown (100 points total, pass threshold 60):
  5 pts  - Output scene exists and > 10KB
  20 pts - Gravity fixed (negative Y force between -15 and -5)
  20 pts - Emission rate fixed (birth rate > 0)
  20 pts - Collision SOP path fixed (points to valid geometry)
  15 pts - Substeps fixed (value >= 1)
  10 pts - Particles actually simulated (particle count > 0 at frame 24+)
  10 pts - At least 48 frames cached/simulated

Do-nothing state: scene exists (pre-built) but all errors remain.
  - output_exists would be false (fixed scene not saved) => 0 pts
  - Or if they just re-saved without fixing: scene exists ~5 pts, all else 0 => 5 pts total
  => passed = False
"""

import json
import os
import tempfile


def verify_fix_broken_particle_sim(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    result_vm_path = "/tmp/task_result.json"

    # ----------------------------------------------------------------
    # Pull the result JSON that export_result.sh wrote inside the VM
    # ----------------------------------------------------------------
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    result_data = None
    try:
        copy_from_env(result_vm_path, tmp.name)
        with open(tmp.name, "r", errors="replace") as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result JSON from VM: {e}",
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if result_data is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result JSON was empty or unparseable",
        }

    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # CHECK 1: Output scene exists and > 10KB (5 points)
    # ================================================================
    output_exists = result_data.get("output_exists", False)
    output_size = result_data.get("output_size_bytes", 0)
    details["output_exists"] = output_exists
    details["output_size_bytes"] = output_size

    if output_exists and output_size > 10240:
        score += 5
        feedback_parts.append(
            f"Output scene exists ({output_size} bytes) [5/5 pts]"
        )
    elif output_exists:
        score += 2
        feedback_parts.append(
            f"Output scene exists but small ({output_size} bytes) [2/5 pts]"
        )
    else:
        feedback_parts.append("Output scene not found [0/5 pts]")

    # ================================================================
    # CHECK 2: Gravity fixed - negative Y between -15 and -5 (20 points)
    # ================================================================
    gravity_y = result_data.get("gravity_forcey", 9.81)
    details["gravity_forcey"] = gravity_y

    try:
        gravity_y = float(gravity_y)
    except (ValueError, TypeError):
        gravity_y = 9.81

    if -15.0 <= gravity_y <= -5.0:
        score += 20
        feedback_parts.append(
            f"Gravity fixed: forcey={gravity_y:.2f} (valid range) [20/20 pts]"
        )
    elif gravity_y < 0:
        # Negative but outside ideal range - partial credit
        score += 10
        feedback_parts.append(
            f"Gravity partially fixed: forcey={gravity_y:.2f} (negative but outside -15..-5) [10/20 pts]"
        )
    else:
        feedback_parts.append(
            f"Gravity NOT fixed: forcey={gravity_y:.2f} (still positive or zero) [0/20 pts]"
        )

    # ================================================================
    # CHECK 3: Emission rate fixed - birth rate > 0 (20 points)
    # ================================================================
    birth_rate = result_data.get("birth_rate", 0)
    details["birth_rate"] = birth_rate

    try:
        birth_rate = float(birth_rate)
    except (ValueError, TypeError):
        birth_rate = 0

    if birth_rate > 0:
        score += 20
        feedback_parts.append(
            f"Emission rate fixed: birth_rate={birth_rate:.1f} [20/20 pts]"
        )
    else:
        feedback_parts.append(
            f"Emission rate NOT fixed: birth_rate={birth_rate} (still 0) [0/20 pts]"
        )

    # ================================================================
    # CHECK 4: Collision SOP path fixed (20 points)
    # ================================================================
    collision_path = result_data.get("collision_soppath", "")
    collision_valid = result_data.get("collision_path_valid", False)
    details["collision_soppath"] = collision_path
    details["collision_path_valid"] = collision_valid

    if collision_valid:
        score += 20
        feedback_parts.append(
            f"Collision path fixed: '{collision_path}' is valid [20/20 pts]"
        )
    elif collision_path != "/obj/collision_geo/OUT":
        # Path was changed but still doesn't resolve - partial credit
        score += 5
        feedback_parts.append(
            f"Collision path changed to '{collision_path}' but not valid [5/20 pts]"
        )
    else:
        feedback_parts.append(
            f"Collision path NOT fixed: still '{collision_path}' [0/20 pts]"
        )

    # ================================================================
    # CHECK 5: Substeps fixed - value >= 1 (15 points)
    # ================================================================
    substeps = result_data.get("substeps", 0)
    details["substeps"] = substeps

    try:
        substeps = int(float(substeps))
    except (ValueError, TypeError):
        substeps = 0

    if substeps >= 1:
        score += 15
        feedback_parts.append(
            f"Substeps fixed: {substeps} (>= 1) [15/15 pts]"
        )
    else:
        feedback_parts.append(
            f"Substeps NOT fixed: {substeps} (still 0 or invalid) [0/15 pts]"
        )

    # ================================================================
    # CHECK 6: Particles actually simulated (10 points)
    # ================================================================
    particle_count_24 = result_data.get("particle_count_frame24", 0)
    particle_count_48 = result_data.get("particle_count_frame48", 0)
    details["particle_count_frame24"] = particle_count_24
    details["particle_count_frame48"] = particle_count_48

    try:
        particle_count_24 = int(particle_count_24)
        particle_count_48 = int(particle_count_48)
    except (ValueError, TypeError):
        particle_count_24 = 0
        particle_count_48 = 0

    max_particles = max(particle_count_24, particle_count_48)
    if max_particles > 0:
        score += 10
        feedback_parts.append(
            f"Particles simulated: {max_particles} particles found [10/10 pts]"
        )
    else:
        sim_error = result_data.get("sim_error", "none")
        feedback_parts.append(
            f"No particles generated (sim_error: {sim_error}) [0/10 pts]"
        )

    # ================================================================
    # CHECK 7: At least 48 frames cached (10 points)
    # ================================================================
    cached_frames = result_data.get("cached_frames", 0)
    details["cached_frames"] = cached_frames

    try:
        cached_frames = int(cached_frames)
    except (ValueError, TypeError):
        cached_frames = 0

    if cached_frames >= 48:
        score += 10
        feedback_parts.append(
            f"Cache complete: {cached_frames} frames (>= 48) [10/10 pts]"
        )
    elif cached_frames >= 24:
        score += 5
        feedback_parts.append(
            f"Partial cache: {cached_frames} frames (< 48 but >= 24) [5/10 pts]"
        )
    elif cached_frames > 0:
        score += 2
        feedback_parts.append(
            f"Minimal cache: {cached_frames} frames [2/10 pts]"
        )
    else:
        feedback_parts.append(
            f"No cached frames found [0/10 pts]"
        )

    # ================================================================
    # FINAL RESULT
    # ================================================================
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
