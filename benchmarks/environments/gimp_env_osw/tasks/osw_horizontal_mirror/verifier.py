#!/usr/bin/env python3
"""OSWorld verifier: ensure image has been mirrored horizontally."""

import os
import sys
import logging

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from osworld_all_verifs import check_image_mirror

logging.basicConfig(level=logging.DEBUG)


def check_horizontal_mirror(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    possible_results = [
        "/home/ga/Desktop/osw_horizontal_mirror.png",
        "/home/ga/Desktop/berry_mirror.png",
        "/home/ga/Desktop/horizontal_mirror.png"
    ]

    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/berry.png",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": file_info.get("error", "Setup failed")}

    try:
        src_path = file_info["original_path"]
        tgt_path = file_info["result_path"]
        score = check_image_mirror(src_path, tgt_path)
        passed = bool(score >= 1.0)
        feedback = "Image mirrored horizontally" if passed else "Mirroring verification failed"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
    except Exception as e:
        breakpoint()
        logging.exception("Mirror verification error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {e}"}
    finally:
        cleanup_verification_environment(file_info.get("temp_dir", ""))
