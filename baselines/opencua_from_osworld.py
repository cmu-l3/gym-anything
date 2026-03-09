"""Fallback prompt definitions for the OpenCUA baseline.

The upstream OpenCUA prompt source is not vendored in this checkout. These
definitions provide a stable local fallback so baseline imports remain quiet
and deterministic.
"""

AGNET_SYS_PROMPT_L1 = (
    "You are a GUI agent. You are given a task and a screenshot of the screen. "
    "You need to perform a series of pyautogui actions to complete the task."
)

AGNET_SYS_PROMPT_L2 = AGNET_SYS_PROMPT_L1
AGNET_SYS_PROMPT_L3 = AGNET_SYS_PROMPT_L1

