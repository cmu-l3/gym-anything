#!/usr/bin/env python3
"""OSWorld verifier: ensure layer resized to height 512 while structure maintained."""

import os
import sys
import logging

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../..")))
from osworld_all_verifs import check_image_size, check_structure_sim_resized

logging.basicConfig(level=logging.DEBUG)


def check_resize_layer_512(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    possible_results = [
        "/home/ga/Desktop/osw_resized_layer.png",
        "/home/ga/Desktop/resized.png",
        "/home/ga/Desktop/dog_resized.png"
    ]

    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/dog_with_background.png",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": file_info.get("error", "Setup failed")}

    try:
        src_path = file_info["original_path"]
        tgt_path = file_info["result_path"]

        size_rule = {"height": 512, "ignore_transparent": True}
        size_ok = bool(check_image_size(tgt_path, size_rule) >= 1.0)
        structure_ok = bool(check_structure_sim_resized(src_path, tgt_path) >= 1.0)

        passed = size_ok and structure_ok
        feedback = "Layer resized to 512px height" if passed else "Resize verification failed"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
    except Exception as e:
        logging.exception("Resize verification error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {e}"}
    finally:
        cleanup_verification_environment(file_info.get("temp_dir", ""))
