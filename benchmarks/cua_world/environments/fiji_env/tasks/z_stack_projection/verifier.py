#!/usr/bin/env python3
"""Verifier for Z-Stack Projection task.

This is a stub verifier. Actual verification is done externally via VLM evaluators.
"""

def verify_z_projection(traj, env_info, task_info):
    """
    Stub verifier for z_stack_projection task.

    Real verification is done via external VLM evaluation.

    Expected outputs:
    - ~/Fiji_Data/results/max_projection.png (256x256 image)
    - ~/Fiji_Data/results/projection_stats.csv (measurement results)
    """
    import os
    from pathlib import Path

    results = {
        "passed": False,
        "score": 0,
        "feedback": "Stub verifier - VLM evaluation is external",
        "details": {}
    }

    # Check if output files exist
    home = Path("/home/ga")
    max_proj = home / "Fiji_Data" / "results" / "max_projection.png"
    stats_csv = home / "Fiji_Data" / "results" / "projection_stats.csv"

    results["details"]["max_projection_exists"] = max_proj.exists()
    results["details"]["stats_csv_exists"] = stats_csv.exists()

    # Basic validation - both files should exist
    if max_proj.exists() and stats_csv.exists():
        # Check file sizes
        results["details"]["max_projection_size"] = max_proj.stat().st_size
        results["details"]["stats_csv_size"] = stats_csv.stat().st_size

        # If both files exist and have content, consider it likely passed
        if max_proj.stat().st_size > 1000 and stats_csv.stat().st_size > 10:
            results["passed"] = True
            results["score"] = 100
            results["feedback"] = "Output files found - VLM verification pending"
    else:
        results["feedback"] = f"Missing files: projection={max_proj.exists()}, stats={stats_csv.exists()}"

    return results
