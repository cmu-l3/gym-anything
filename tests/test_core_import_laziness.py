"""Importing core must not load party implementation modules.

The Windows-host blocker found by a downstream consumer: runner modules
carry platform-specific imports (fcntl on Unix), so eagerly importing them
from the package __init__ breaks `import gym_anything` on other hosts.
The property under test is the root cause, checked in a fresh interpreter:
core import loads the contract (base) and the door (registry) only.
"""

from __future__ import annotations

import subprocess
import sys
import unittest


class CoreImportLazinessTest(unittest.TestCase):
    def test_import_gym_anything_loads_no_party_modules(self):
        code = (
            "import sys, gym_anything\n"
            "loaded = [m for m in sys.modules"
            " if m.startswith('gym_anything.runtime.runners.')"
            " and not m.endswith(('.base', '.registry'))]\n"
            "assert not loaded, f'party modules loaded by core import: {loaded}'\n"
            "print('lazy-ok')\n"
        )
        result = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=120
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertIn("lazy-ok", result.stdout)


if __name__ == "__main__":
    unittest.main()
