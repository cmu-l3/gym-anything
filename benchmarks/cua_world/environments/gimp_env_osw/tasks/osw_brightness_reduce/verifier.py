#!/usr/bin/env python3
"""OSWorld verifier: check brightness decreased while structure similar."""

import os
import sys
import logging

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from osworld_all_verifs import check_brightness_decrease_and_structure_sim

logging.basicConfig(level=logging.DEBUG)


def check_brightness_reduction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    possible_results = [
        "/home/ga/Desktop/osw_brightness_reduced.png",
        "/home/ga/Desktop/edited_darker.png",
        "/home/ga/Desktop/brightness_reduced.png"
    ]
    # breakpoint()

    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/woman_sitting_by_the_tree.png",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": file_info.get("error", "Setup failed")}

    try:
        src_path = file_info["original_path"]
        tgt_path = file_info["result_path"]
        score = check_brightness_decrease_and_structure_sim(src_path, tgt_path)
        passed = bool(score >= 1.0)
        feedback = "Brightness reduced with structure preserved" if passed else "Brightness reduction verification failed"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
    except Exception as e:
        logging.exception("Brightness verification error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {e}"}
    finally:
        cleanup_verification_environment(file_info.get("temp_dir", ""))
