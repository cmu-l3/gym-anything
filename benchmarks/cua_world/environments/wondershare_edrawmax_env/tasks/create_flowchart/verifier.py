#!/usr/bin/env python3
"""Verifier for create_flowchart task.
Checks that git_pr_flowchart.eddx contains a real Git PR workflow diagram.
"""
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_flowchart(traj, env_info, task_info):
    """
    Verify that git_pr_flowchart.eddx was saved and contains a real flowchart.

    Checks:
    1. File exists at /home/ga/git_pr_flowchart.eddx
    2. File is substantially sized (> 12KB) — a 12-node labeled flowchart is much
       larger than a blank canvas or the 8KB bundled template
    3. File is a valid ZIP archive (eddx format)
    4. Diagram XML contains key label text from the Git PR workflow description:
       - "Start" (the starting oval) AND
       - at least one of: "Pull Request", "Feature Branch", "Merge"
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    container_path = "/home/ga/git_pr_flowchart.eddx"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".eddx")
    tmp_path = tmp.name
    tmp.close()

    try:
        copy_from_env(container_path, tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"File not found at {container_path}: {e}"}

    if not os.path.exists(tmp_path):
        return {"passed": False, "score": 0, "feedback": f"Output file {container_path} does not exist"}

    criteria_passed = 0
    feedback_parts = []

    # Criterion 1: file exists
    criteria_passed += 1
    feedback_parts.append(f"File {container_path} exists")

    # Criterion 2: substantially sized (a 12-node flowchart with labels >> 12KB)
    size = os.path.getsize(tmp_path)
    if size > 12000:
        criteria_passed += 1
        feedback_parts.append(f"File size adequate ({size} bytes, > 12KB)")
    else:
        feedback_parts.append(
            f"File too small ({size} bytes) — a 12-node labeled flowchart should be > 12KB; "
            "this may be a blank canvas or trivially saved file"
        )

    # Criterion 3: valid ZIP + content checks
    content_ok = False
    try:
        with zipfile.ZipFile(tmp_path, "r") as zf:
            names = zf.namelist()
            if names:
                criteria_passed += 1
                feedback_parts.append(f"Valid eddx archive ({len(names)} entries)")

            # Collect all XML text to search for required labels
            all_xml = ""
            for name in names:
                if name.endswith(".xml"):
                    try:
                        all_xml += zf.read(name).decode("utf-8", errors="ignore")
                    except Exception:
                        pass

            # Criterion 4: key label strings from the Git PR workflow
            has_start = "Start" in all_xml or "start" in all_xml
            has_pr_term = any(t in all_xml for t in [
                "Pull Request", "pull request",
                "Feature Branch", "feature branch",
                "Merge", "merge"
            ])
            if has_start and has_pr_term:
                content_ok = True
                criteria_passed += 1
                feedback_parts.append("Diagram contains expected Git PR workflow labels (Start + PR/Branch/Merge terms)")
            elif has_start:
                feedback_parts.append(
                    "Found 'Start' label but missing Git PR terms (Pull Request/Feature Branch/Merge) — "
                    "diagram may not depict the required workflow"
                )
            else:
                feedback_parts.append(
                    "Diagram XML does not contain expected labels ('Start', 'Pull Request'/'Feature Branch'/'Merge') — "
                    "the required Git PR flowchart was not created"
                )
    except zipfile.BadZipFile:
        feedback_parts.append("Not a valid eddx/ZIP archive")
    except Exception as e:
        feedback_parts.append(f"Archive check error: {e}")

    os.unlink(tmp_path)

    score = int((criteria_passed / 4) * 100)
    passed = criteria_passed >= 3
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
