from __future__ import annotations

import unittest

from gym_anything.runtime.runners.qemu_apptainer import _get_env_hash
from gym_anything.specs import EnvSpec


def _spec(env_id: str) -> EnvSpec:
    return EnvSpec.from_dict({
        "id": env_id,
        "base": "ubuntu-gnome-systemd_highres",
        "hooks": {"pre_start": "/workspace/scripts/install_odoo.sh",
                  "post_start": "/workspace/scripts/setup_odoo.sh"},
    })


class QemuCheckpointKeyTests(unittest.TestCase):
    def test_envs_sharing_hook_paths_get_their_own_checkpoint(self) -> None:
        # The odoo_*_env family shares hook command paths but installs
        # different data; a shared checkpoint booted the wrong env.
        self.assertNotEqual(_get_env_hash(_spec("odoo_quality_env@0.1")),
                            _get_env_hash(_spec("odoo_scheduling_env@0.1")))
        self.assertEqual(_get_env_hash(_spec("odoo_quality_env@0.1")),
                         _get_env_hash(_spec("odoo_quality_env@0.1")))


if __name__ == "__main__":
    unittest.main()
