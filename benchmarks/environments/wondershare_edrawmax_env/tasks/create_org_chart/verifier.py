#!/usr/bin/env python3
"""Verifier for create_org_chart task.
Checks that apache_org_chart.eddx contains a real Apache Foundation org chart.
"""
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_org_chart(traj, env_info, task_info):
    """
    Verify that apache_org_chart.eddx was saved and contains a real org chart.

    Checks:
    1. File exists at /home/ga/apache_org_chart.eddx
    2. File is substantially sized (> 8KB) — a 7-node labeled org chart with
       hierarchy lines is much larger than the bundled template
    3. File is a valid ZIP archive (eddx format)
    4. Diagram XML contains key Apache Foundation org chart labels:
       - "Board" or "Director" (Board of Directors) AND
       - at least one of: "President", "Secretary", "Infrastructure", "Legal", "Marketing"
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    container_path = "/home/ga/apache_org_chart.eddx"
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

    # Criterion 2: substantially sized (7-node org chart with labels >> 8KB)
    size = os.path.getsize(tmp_path)
    if size > 8000:
        criteria_passed += 1
        feedback_parts.append(f"File size adequate ({size} bytes, > 8KB)")
    else:
        feedback_parts.append(
            f"File too small ({size} bytes) — a 7-node labeled org chart should be > 8KB; "
            "this may be a blank canvas or trivially saved file"
        )

    # Criterion 3: valid ZIP + content checks
    try:
        with zipfile.ZipFile(tmp_path, "r") as zf:
            names = zf.namelist()
            if names:
                criteria_passed += 1
                feedback_parts.append(f"Valid eddx archive ({len(names)} entries)")

            # Collect all XML text
            all_xml = ""
            for name in names:
                if name.endswith(".xml"):
                    try:
                        all_xml += zf.read(name).decode("utf-8", errors="ignore")
                    except Exception:
                        pass

            # Criterion 4: key label strings from Apache Foundation org chart
            has_board = "Board" in all_xml or "Director" in all_xml
            has_role = any(t in all_xml for t in [
                "President", "president",
                "Secretary", "secretary",
                "Infrastructure", "infrastructure",
                "Legal", "Marketing"
            ])
            if has_board and has_role:
                criteria_passed += 1
                feedback_parts.append(
                    "Diagram contains expected Apache org chart labels (Board/Director + role names)"
                )
            elif has_board:
                feedback_parts.append(
                    "Found 'Board/Director' but missing role names (President/Secretary/Infrastructure/Legal/Marketing)"
                )
            else:
                feedback_parts.append(
                    "Diagram XML does not contain expected labels ('Board of Directors', role names) — "
                    "the required Apache org chart was not created"
                )
    except zipfile.BadZipFile:
        feedback_parts.append("Not a valid eddx/ZIP archive")
    except Exception as e:
        feedback_parts.append(f"Archive check error: {e}")

    os.unlink(tmp_path)

    score = int((criteria_passed / 4) * 100)
    passed = criteria_passed >= 3
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
