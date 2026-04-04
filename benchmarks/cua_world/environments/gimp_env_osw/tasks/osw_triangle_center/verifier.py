#!/usr/bin/env python3
"""OSWorld verifier: ensure triangle placed near center."""

import os
import sys
import logging

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from osworld_all_verifs import check_triangle_position

logging.basicConfig(level=logging.DEBUG)


def check_triangle_center(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    possible_results = [
        "/home/ga/Desktop/osw_triangle_center.png",
        "/home/ga/Desktop/Triangle_In_The_Middle.png",
        "/home/ga/Desktop/triangle_center.png"
    ]

    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/Triangle_On_The_Side.png",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": file_info.get("error", "Setup failed")}

    try:
        result_path = file_info["result_path"]
        score = check_triangle_position(result_path)
        passed = bool(score >= 1.0)
        feedback = "Triangle positioned near center" if passed else "Triangle position verification failed"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
    except Exception as e:
        logging.exception("Triangle position verification error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {e}"}
    finally:
        cleanup_verification_environment(file_info.get("temp_dir", ""))
