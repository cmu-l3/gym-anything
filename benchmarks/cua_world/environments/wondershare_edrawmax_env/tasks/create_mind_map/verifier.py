#!/usr/bin/env python3
"""Verifier for create_mind_map task.
Checks that linux_kernel_mindmap.eddx contains a real Linux kernel mind map.
"""
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_mind_map(traj, env_info, task_info):
    """
    Verify that linux_kernel_mindmap.eddx was saved and contains a real mind map.

    Checks:
    1. File exists at /home/ga/linux_kernel_mindmap.eddx
    2. File is substantially sized (> 12KB) — a 17-node mind map with labels
       is much larger than the bundled flowchart template
    3. File is a valid ZIP archive (eddx format)
    4. Diagram XML contains key Linux kernel mind map labels:
       - "Linux" or "Kernel" (central node) AND
       - at least one of: "Scheduler", "Driver", "ARM", "Torvalds", "Memory", "Network"
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    container_path = "/home/ga/linux_kernel_mindmap.eddx"
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

    # Criterion 2: substantially sized (17-node labeled mind map >> 12KB)
    size = os.path.getsize(tmp_path)
    if size > 12000:
        criteria_passed += 1
        feedback_parts.append(f"File size adequate ({size} bytes, > 12KB)")
    else:
        feedback_parts.append(
            f"File too small ({size} bytes) — a 17-node labeled mind map should be > 12KB; "
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

            # Criterion 4: key label strings from Linux kernel mind map
            has_linux = "Linux" in all_xml or "Kernel" in all_xml or "kernel" in all_xml
            has_subtopic = any(t in all_xml for t in [
                "Scheduler", "scheduler",
                "Driver", "driver",
                "ARM", "Torvalds",
                "Memory", "Network", "network",
                "x86", "RISC"
            ])
            if has_linux and has_subtopic:
                criteria_passed += 1
                feedback_parts.append(
                    "Diagram contains expected Linux kernel mind map labels (Linux/Kernel + subsystem names)"
                )
            elif has_linux:
                feedback_parts.append(
                    "Found 'Linux/Kernel' but missing subsystem names (Scheduler/Driver/ARM/Torvalds/etc)"
                )
            else:
                feedback_parts.append(
                    "Diagram XML does not contain expected labels ('Linux', 'Kernel', subsystem names) — "
                    "the required Linux kernel mind map was not created"
                )
    except zipfile.BadZipFile:
        feedback_parts.append("Not a valid eddx/ZIP archive")
    except Exception as e:
        feedback_parts.append(f"Archive check error: {e}")

    os.unlink(tmp_path)

    score = int((criteria_passed / 4) * 100)
    passed = criteria_passed >= 3
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
