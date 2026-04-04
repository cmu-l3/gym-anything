#!/usr/bin/env python3
"""OSWorld verifier: ensure Vignette filter was opened (action-history entry)."""

import os
import sys
import logging

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import copy_file_from_container

logging.basicConfig(level=logging.DEBUG)

ACTION_FILES = [
    "/home/ga/.config/GIMP/2.10/action-history",
    "/home/ga/.gimp-2.10/action-history",
    "/root/.config/GIMP/2.10/action-history",
]

TARGET_TOKEN = "filters-vignette"


def check_vignette_open(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory() as tmpd:
        host_action = Path(tmpd) / "action-history"
        found = False
        for p in ACTION_FILES:
            ok, err = copy_file_from_container(p, str(host_action), copy_from_env)
            if ok:
                logging.debug(f"Copied action history from {p}")
                found = True
                break
        if not found:
            return {"passed": False, "score": 0, "feedback": f"Could not locate action-history in {ACTION_FILES}"}

        try:
            content = host_action.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            logging.exception("Failed to read action history")
            return {"passed": False, "score": 0, "feedback": f"Could not read action history: {e}"}

        passed = TARGET_TOKEN in content
        feedback = "Vignette filter recorded" if passed else "Vignette filter not observed in action history"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
