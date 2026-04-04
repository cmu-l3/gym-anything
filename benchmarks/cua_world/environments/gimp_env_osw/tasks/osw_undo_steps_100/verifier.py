#!/usr/bin/env python3
"""
OSWorld verifier: check undo-levels is set to 100 in GIMP gimprc.
"""

import os
import logging
import sys

# Import our env6 verification utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment, copy_file_from_container

# Import OSWorld verifier function
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from osworld_all_verifs import check_config_status

logging.basicConfig(level=logging.DEBUG)


def check_undo_steps_100(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy gimprc from container; OSWorld expects gimprc as result
    # Common locations for GIMP 2.10 on Linux
    possible_cfg_paths = [
        "/home/ga/.config/GIMP/2.10/gimprc",
        "/home/ga/.gimp-2.10/gimprc",
        "/root/.config/GIMP/2.10/gimprc",
    ]

    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory() as tmpd:
        host_cfg = Path(tmpd) / "gimprc"
        found = False
        for p in possible_cfg_paths:
            ok, err = copy_file_from_container(p, str(host_cfg), copy_from_env)
            if ok:
                logging.debug(f"Copied gimprc from: {p}")
                found = True
                break
        if not found:
            return {"passed": False, "score": 0, "feedback": f"Could not locate gimprc in {possible_cfg_paths}"}

        # OSWorld rule format
        rule = {"type": "key-value", "key": "undo-levels", "value": "100"}
        try:
            score = check_config_status(str(host_cfg), rule)
            passed = bool(score >= 1.0)
            feedback = "Undo steps correctly set to 100" if passed else "Undo steps not set to 100"
            return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
        except Exception as e:
            logging.exception("Verification failed")
            return {"passed": False, "score": 0, "feedback": f"Verifier error: {e}"}
