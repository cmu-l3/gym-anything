#!/usr/bin/env python3
"""
Verifier for investigate_coordinated_intrusion task.

Stub verifier — VLM checklist evaluation is the primary scoring mechanism.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_investigate_coordinated_intrusion(traj, env_info, task_info):
    """Stub verifier — VLM evaluation is external."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
