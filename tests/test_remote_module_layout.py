from __future__ import annotations

import importlib
import unittest


class RemoteModuleLayoutTests(unittest.TestCase):
    def test_core_remote_modules_import(self) -> None:
        worker = importlib.import_module("gym_anything.remote.worker")
        master = importlib.import_module("gym_anything.remote.master")
        dashboard = importlib.import_module("gym_anything.remote.dashboard_app")
        monitoring = importlib.import_module("gym_anything.remote.monitoring")

        self.assertTrue(callable(getattr(worker, "main", None)))
        self.assertTrue(callable(getattr(master, "main", None)))
        self.assertTrue(callable(getattr(dashboard, "main", None)))
        self.assertTrue(callable(getattr(monitoring, "get_metrics_collector", None)))


if __name__ == "__main__":
    unittest.main()
