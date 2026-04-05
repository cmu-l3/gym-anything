from __future__ import annotations

import importlib
import unittest


class AgentsModuleLayoutTests(unittest.TestCase):
    def test_new_agents_packages_import_cleanly(self) -> None:
        agents_pkg = importlib.import_module("agents")
        agents_pkg_inner = importlib.import_module("agents.agents")
        shared_pkg = importlib.import_module("agents.shared")
        evaluation_pkg = importlib.import_module("agents.evaluation")

        self.assertIsNotNone(agents_pkg)
        self.assertTrue(hasattr(agents_pkg_inner, "ClaudeAgent"))
        self.assertIsNotNone(shared_pkg)
        self.assertIsNotNone(evaluation_pkg)

    def test_evaluation_modules_are_import_safe(self) -> None:
        run_single = importlib.import_module("agents.evaluation.run_single")
        run_batch = importlib.import_module("agents.evaluation.run_batch")

        self.assertTrue(callable(run_single.build_parser))
        self.assertTrue(callable(run_single.main))
        self.assertTrue(callable(run_batch.build_parser))
        self.assertTrue(callable(run_batch.main))

if __name__ == "__main__":
    unittest.main()
