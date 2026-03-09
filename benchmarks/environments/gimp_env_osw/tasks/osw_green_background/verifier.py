#!/usr/bin/env python3
"""OSWorld verifier: ensure background filled with green while object preserved."""

import os
import sys
import logging

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from osworld_all_verifs import check_green_background

logging.basicConfig(level=logging.DEBUG)


def check_green_background_fill(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    possible_results = [
        "/home/ga/Desktop/osw_green_background.png",
        "/home/ga/Desktop/green_background_with_object.png",
        "/home/ga/Desktop/green_background.png"
    ]

    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/white_background_with_object.png",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": file_info.get("error", "Setup failed")}

    try:
        src_path = file_info["original_path"]
        tgt_path = file_info["result_path"]
        score = check_green_background(src_path, tgt_path)
        passed = bool(score >= 1.0)
        feedback = "Background successfully filled with green" if passed else "Green background verification failed"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
    except Exception as e:
        logging.exception("Green background verification error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {e}"}
    finally:
        cleanup_verification_environment(file_info.get("temp_dir", ""))
