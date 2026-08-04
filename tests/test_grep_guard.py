"""The grep guard: core orchestration names no party in control flow (L1).

Scans CODE tokens only (comments and strings are prose, not control flow),
so docstrings may mention runners freely while an import, dict, or branch
keyed on a specific runner class, benchmark, or agent module fails here —
mechanically, before any reviewer has to notice it. The string literal
"cua_world" is additionally guarded because the old benchmark binding was
string-keyed; it is allowed only at its sanctioned configuration sites.
"""

from __future__ import annotations

import io
import re
import tokenize
import unittest
from collections import defaultdict
from pathlib import Path

import gym_anything

CORE = Path(gym_anything.__file__).resolve().parent

# Party implementations and their sanctioned table live here — allowed.
ALLOWED_DIRS = {"runtime/runners", "presets"}

# Sanctioned exceptions: file -> substrings allowed there, each a recorded
# design decision (configuration values and bundled-party surfaces).
# Adding an entry to this table is a design decision, not a fix.
SANCTIONED = {
    # The one L1-sanctioned configuration value: the default benchmark.
    "cli.py": {
        '"cua_world"': "DEFAULT_BENCHMARK configuration value",
        "agents . agents": "bundled-agent listing (cmd_agents)",
    },
    # Hub adapters bind bundled parties for external training hubs;
    # cua_world appears only as their documented default parameter, and the
    # reference-agent registry is the surface they expose to hubs.
    "integrations/prime_rl/hub.py": {'"cua_world"': "default parameter value"},
    "integrations/prime_rl/__init__.py": {'"cua_world"': "docstring example (string guard cannot tell prose strings from code strings)"},
    "integrations/harbor/compile.py": {'"cua_world"': "default parameter value"},
    "integrations/prime_rl/verifiers.py": {"agents . agents": "hub rollouts drive bundled reference agents"},
    "integrations/harbor/agent.py": {"agents . agents": "hub rollouts drive bundled reference agents"},
}

_RUNNER_CLASS_NAMES = [
    "DockerRunner", "QemuApptainerRunner", "QemuNativeRunner",
    "AVDApptainerRunner", "AVDNativeRunner", "AVFRunner",
    "ApptainerDirectRunner", "LocalRunner", "UseComputerRunner",
    "ModalRunner", "ModalNativeRunner",
]

# Patterns over the token stream (dotted names appear as "a . b").
FORBIDDEN = [re.compile(rf"\b{name}\b") for name in _RUNNER_CLASS_NAMES] + [
    re.compile(r"\bbenchmarks\s*\.\s*cua_world\b"),
    re.compile(r"\bfrom\s+benchmarks\b"),
    re.compile(r"\bagents\s*\.\s*agents\b"),
    re.compile(r'"cua_world"'),
]

_PROSE_TOKENS = {tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT}


def _code_lines(path: Path):
    """Per-line joined code tokens; strings kept only for the config guard."""
    lines = defaultdict(list)
    source = path.read_text()
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except tokenize.TokenizeError:
        return {}
    for tok in tokens:
        if tok.type in _PROSE_TOKENS:
            continue
        if tok.type == tokenize.STRING:
            # Strings are prose except the guarded literal.
            if "cua_world" not in tok.string:
                continue
            text = '"cua_world"'
        else:
            text = tok.string
        lines[tok.start[0]].append(text)
    return {lineno: " ".join(parts) for lineno, parts in lines.items()}


def _violations():
    found = []
    for path in sorted(CORE.rglob("*.py")):
        rel = path.relative_to(CORE).as_posix()
        if any(rel.startswith(prefix + "/") or rel == prefix for prefix in ALLOWED_DIRS):
            continue
        sanctioned = SANCTIONED.get(rel, {})
        for lineno, code in sorted(_code_lines(path).items()):
            for pattern in FORBIDDEN:
                if not pattern.search(code):
                    continue
                if any(token in code for token in sanctioned):
                    continue
                found.append(f"{rel}:{lineno}: {code}  [{pattern.pattern}]")
    return found


class GrepGuardTest(unittest.TestCase):
    def test_core_orchestration_names_no_party_in_control_flow(self):
        violations = _violations()
        self.assertEqual(
            violations, [],
            msg="L1 violations (party names in core control flow):\n" + "\n".join(violations),
        )


if __name__ == "__main__":
    unittest.main()
