"""Compatibility package for ``gym_anything.recording.*`` imports."""

from importlib import import_module
import sys

from ..runtime.recording import *  # noqa: F401,F403
from ..runtime.recording import __all__  # noqa: F401

sys.modules[f"{__name__}.ffmpeg"] = import_module("gym_anything.runtime.recording.ffmpeg")
