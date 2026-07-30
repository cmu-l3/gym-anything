"""fast_io zeroes the between-action gap.

A composite gesture (modifier-held click, composed drag, click-then-type) is
several action dicts in one step. The 200 ms default gap between them made a
three-action gesture 96% sleep on the fast path, which exists precisely to
remove per-action latency. fast_io already zeroes the post-action settle and
the step cycle; this is the third of the three.
"""

from __future__ import annotations

import unittest
from unittest import mock

from gym_anything.env import GymAnythingEnv


class ActionGapTests(unittest.TestCase):
    def _env(self, fast_io: bool) -> GymAnythingEnv:
        env = GymAnythingEnv.__new__(GymAnythingEnv)
        env.fast_io = fast_io
        return env

    def test_fast_io_drops_the_gap(self) -> None:
        self.assertEqual(self._env(True)._action_gap_seconds(0.2), 0.0)

    def test_non_fast_io_keeps_what_the_caller_asked_for(self) -> None:
        self.assertEqual(self._env(False)._action_gap_seconds(0.2), 0.2)
        self.assertEqual(self._env(False)._action_gap_seconds(0.0), 0.0)

    def test_fast_io_gap_is_tunable_like_the_other_two_settles(self) -> None:
        with mock.patch.dict("os.environ",
                             {"GYM_ANYTHING_FAST_IO_ACTION_GAP_MS": "25"}):
            self.assertAlmostEqual(self._env(True)._action_gap_seconds(0.2), 0.025)

    def test_a_bad_override_falls_back_to_zero_rather_than_raising(self) -> None:
        with mock.patch.dict("os.environ",
                             {"GYM_ANYTHING_FAST_IO_ACTION_GAP_MS": "nonsense"}):
            self.assertEqual(self._env(True)._action_gap_seconds(0.2), 0.0)


if __name__ == "__main__":
    unittest.main()
