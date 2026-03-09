#!/usr/bin/env python3
"""Verifier for apply_theme task.
Checks that themed_flowchart.eddx has the Warm color theme applied.
"""
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# The unmodified flowchart_en.eddx template uses theme Name="Novel" ID="83".
# Applying the "Warm" theme changes it to Name="Warm" ID="126".
# We verify the Warm theme was actually applied (not just that the file was saved unchanged).
ORIGINAL_THEME_NAME = "Novel"
APPLIED_THEME_NAME = "Warm"
APPLIED_THEME_ID = "126"


def verify_apply_theme(traj, env_info, task_info):
    """
    Verify that themed_flowchart.eddx was saved with the Warm color theme applied.

    Checks:
    1. File exists at /home/ga/themed_flowchart.eddx
    2. File is non-trivially sized (> 2KB)
    3. File is a valid ZIP archive (eddx format)
    4. theme.xml contains Name="Warm" or ID="126" — the specific Warm theme identifiers.
       The original unmodified template uses Name="Novel" ID="83", so "Warm" is
       unambiguous evidence that a theme was actually applied (not just resaved).
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    container_path = "/home/ga/themed_flowchart.eddx"
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

    # Criterion 3: valid ZIP + Criterion 4: Warm theme specifically applied
    warm_applied = False
    try:
        with zipfile.ZipFile(tmp_path, "r") as zf:
            names = zf.namelist()
            if names:
                criteria_passed += 1
                feedback_parts.append(f"Valid eddx archive ({len(names)} entries)")

            # Check theme.xml for the Warm theme identifiers
            # The original template has Name="Novel" ID="83"
            # After applying Warm: Name="Warm" ID="126"
            theme_xml_content = ""
            for name in names:
                if "theme" in name.lower() and name.endswith(".xml"):
                    try:
                        theme_xml_content = zf.read(name).decode("utf-8", errors="ignore")
                    except Exception:
                        pass

            # Check for Warm-specific markers (NOT present in the original "Novel" theme)
            if f'Name="{APPLIED_THEME_NAME}"' in theme_xml_content:
                warm_applied = True
                feedback_parts.append(
                    f'Warm theme confirmed: theme.xml contains Name="{APPLIED_THEME_NAME}"'
                )
            elif f'ID="{APPLIED_THEME_ID}"' in theme_xml_content:
                warm_applied = True
                feedback_parts.append(
                    f'Warm theme confirmed: theme.xml contains ID="{APPLIED_THEME_ID}" (Warm theme ID)'
                )
            elif APPLIED_THEME_NAME in theme_xml_content:
                warm_applied = True
                feedback_parts.append(
                    f'Warm theme name found in theme.xml'
                )
            else:
                # Check if original "Novel" theme is still present (unchanged file)
                if ORIGINAL_THEME_NAME in theme_xml_content:
                    feedback_parts.append(
                        f'theme.xml still has original "{ORIGINAL_THEME_NAME}" theme — '
                        f'the Warm theme was not applied (file saved without theme change)'
                    )
                else:
                    feedback_parts.append(
                        f'theme.xml does not contain Warm theme identifiers '
                        f'(Name="{APPLIED_THEME_NAME}" or ID="{APPLIED_THEME_ID}")'
                    )

    except zipfile.BadZipFile:
        feedback_parts.append("Not a valid eddx/ZIP archive")
    except Exception as e:
        feedback_parts.append(f"Archive check error: {e}")

    if warm_applied:
        criteria_passed += 1

    os.unlink(tmp_path)

    score = int((criteria_passed / 4) * 100)
    passed = criteria_passed >= 3
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
