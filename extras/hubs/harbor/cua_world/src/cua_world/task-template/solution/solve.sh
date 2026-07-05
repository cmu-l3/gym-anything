#!/usr/bin/env bash
set -euo pipefail

# CUA-World-Long tasks are interactive GUI tasks graded by per-task verifiers
# against live application state; no scripted oracle solution is shipped.
# This follows the precedent of the OSWorld and TheAgentCompany adapters.
echo "cua-world does not ship oracle solve scripts." >&2
exit 1
