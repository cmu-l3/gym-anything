#!/usr/bin/env python3
"""Verifier for change_to_imperial task.

Checks that Subsurface.conf has imperial units set (unit_system=1 or length=1).
"""

import os
import tempfile


def verify_change_to_imperial(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    tmp.close()
    try:
        try:
            copy_from_env('/home/ga/.config/Subsurface/Subsurface.conf', tmp.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read Subsurface.conf: {e}"}

        with open(tmp.name) as f:
            conf = f.read()

        # Check for imperial unit settings
        # unit_system=1 means imperial (set by Subsurface when Imperial radio clicked)
        # OR legacy: length=1 means feet
        has_unit_system_imperial = 'unit_system=1' in conf
        has_length_imperial = 'length=1' in conf

        if has_unit_system_imperial or has_length_imperial:
            indicator = 'unit_system=1' if has_unit_system_imperial else 'length=1'
            return {
                "passed": True,
                "score": 100,
                "feedback": f"Imperial units confirmed in config ({indicator})"
            }
        else:
            # Check what unit_system is set to
            import re
            m = re.search(r'unit_system=(\d+)', conf)
            current = m.group(1) if m else 'not set'
            m2 = re.search(r'length=(\d+)', conf)
            current_len = m2.group(1) if m2 else 'not set'
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Units still metric. unit_system={current}, length={current_len}"
            }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
