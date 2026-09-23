"""Prompts must render on every host OS.

A downstream Windows reviewer hit ValueError from strftime('%-d') — a
glibc-only modifier — at agents.shared.prompts IMPORT time, killing the
benchmark harness before it started. Pins two things: the portable date
matches the old glibc rendering (checked on hosts where %-d works), and no
platform-dependent %-modifiers creep back into non-corpus source.
"""

from __future__ import annotations

import re
import unittest
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


class PromptPortabilityTests(unittest.TestCase):
    def test_current_date_matches_glibc_rendering(self):
        from agents.shared import prompts

        self.assertIn(f"The current date is {prompts._CURRENT_DATE}.", prompts.CLAUDE_SYSTEM_PROMPT)
        try:
            glibc = prompts._TODAY.strftime("%A, %B %-d, %Y")
        except ValueError:
            self.skipTest("host strftime rejects %-d; nothing to compare against")
        self.assertEqual(prompts._CURRENT_DATE, glibc)

    def test_no_glibc_only_strftime_modifiers_in_source(self):
        pattern = re.compile(r"strftime\([^)]*%-")
        offenders = []
        for root in ("agents", "src"):
            for path in (REPO / root).rglob("*.py"):
                if pattern.search(path.read_text(errors="replace")):
                    offenders.append(str(path.relative_to(REPO)))
        self.assertEqual(offenders, [], msg=f"glibc-only strftime modifiers in: {offenders}")


if __name__ == "__main__":
    unittest.main()
