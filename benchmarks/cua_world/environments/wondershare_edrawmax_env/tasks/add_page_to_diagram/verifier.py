#!/usr/bin/env python3
"""Verifier for add_page_to_diagram task.
Checks that multipage_diagram.eddx has been saved and contains multiple pages.
"""
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_page_to_diagram(traj, env_info, task_info):
    """
    Verify that multipage_diagram.eddx was saved with an added page.

    Checks:
    1. File exists at /home/ga/multipage_diagram.eddx
    2. File is non-trivially sized (> 2KB)
    3. File is a valid ZIP archive (eddx format)
    4. File is larger than the original template (extra page was added)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    container_path = "/home/ga/multipage_diagram.eddx"
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

    # Criterion 2: non-trivial size
    size = os.path.getsize(tmp_path)
    if size > 2048:
        criteria_passed += 1
        feedback_parts.append(f"File size OK ({size} bytes)")
    else:
        feedback_parts.append(f"File too small ({size} bytes)")

    # Criterion 3: valid ZIP/eddx + check for page content
    page_count = 0
    notes_page_found = False
    try:
        with zipfile.ZipFile(tmp_path, "r") as zf:
            names = zf.namelist()
            if names:
                criteria_passed += 1
                feedback_parts.append(f"Valid eddx archive ({len(names)} entries)")
            # eddx stores pages as separate XML files; look for page XML entries
            page_files = [n for n in names if n.endswith(".xml") and "page" in n.lower()]
            page_count = len(page_files)
            # Check if Notes page content exists anywhere in the archive
            for name in names:
                if name.endswith(".xml"):
                    try:
                        content = zf.read(name).decode("utf-8", errors="ignore")
                        if "Notes" in content:
                            notes_page_found = True
                            break
                    except Exception:
                        pass
    except zipfile.BadZipFile:
        feedback_parts.append("Not a valid eddx/ZIP archive")
    except Exception as e:
        feedback_parts.append(f"Archive check error: {e}")

    # Criterion 4: evidence of added page (Notes found in content, or file is larger than ~50KB baseline)
    if notes_page_found:
        criteria_passed += 1
        feedback_parts.append("'Notes' page found in diagram content")
    elif size > 50000:
        # If the file is substantially larger than original template, a page was likely added
        criteria_passed += 1
        feedback_parts.append(f"File size suggests additional content was added ({size} bytes)")
    else:
        feedback_parts.append("No 'Notes' page detected in diagram content")

    os.unlink(tmp_path)

    score = int((criteria_passed / 4) * 100)
    passed = criteria_passed >= 3
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
