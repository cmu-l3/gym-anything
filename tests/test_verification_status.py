from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from gym_anything.verification.reports import VerificationIssue, VerificationRecord, VerificationSummary
from gym_anything.verification.status import (
    build_missing_hook_reference_manifest,
    build_task_status_manifest,
    build_verified_task_split,
    write_json_report,
)


class VerificationStatusTests(unittest.TestCase):
    def test_build_verified_task_split_only_includes_ok_tasks(self):
        summary = VerificationSummary(
            scope="corpus",
            root="benchmarks/cua_world/environments",
            records=[
                VerificationRecord(
                    kind="task",
                    path="benchmarks/cua_world/environments/env_a/tasks/task_ok/task.json",
                    spec_id="task_ok@1",
                ),
                VerificationRecord(
                    kind="task",
                    path="benchmarks/cua_world/environments/env_a/tasks/task_bad/task.json",
                    spec_id="task_bad@1",
                    issues=[VerificationIssue(code="missing_hook_reference", message="missing", severity="error")],
                ),
            ],
        )

        split = build_verified_task_split(summary)
        self.assertEqual(split["task_count"], 1)
        self.assertEqual(split["tasks"], ["env_a/task_ok"])
        self.assertEqual(split["by_environment"], {"env_a": ["task_ok"]})

    def test_status_manifest_counts_issue_codes(self):
        summary = VerificationSummary(
            scope="corpus",
            root="benchmarks/cua_world/environments",
            records=[
                VerificationRecord(
                    kind="task",
                    path="benchmarks/cua_world/environments/env_a/tasks/task_ok/task.json",
                    spec_id="task_ok@1",
                ),
                VerificationRecord(
                    kind="task",
                    path="benchmarks/cua_world/environments/env_b/tasks/task_bad/task.json",
                    spec_id="task_bad@1",
                    issues=[VerificationIssue(code="invalid_program_verifier", message="bad", severity="error")],
                ),
            ],
        )

        manifest = build_task_status_manifest(summary)
        self.assertEqual(manifest["verified_task_count"], 1)
        self.assertEqual(manifest["failed_task_count"], 1)
        self.assertEqual(manifest["issue_counts"], {"invalid_program_verifier": 1})
        self.assertEqual(manifest["by_environment"]["env_b"]["failed_tasks"], ["task_bad"])

    def test_write_json_report_creates_parent_directory(self):
        data = {"hello": "world"}
        with tempfile.TemporaryDirectory() as tmpdir:
            out_path = Path(tmpdir) / "nested" / "report.json"
            write_json_report(data, out_path)
            self.assertEqual(json.loads(out_path.read_text(encoding="utf-8")), data)

    def test_missing_hook_reference_manifest_includes_task_dirs_and_assets(self):
        summary = VerificationSummary(
            scope="corpus",
            root="benchmarks/cua_world/environments",
            records=[
                VerificationRecord(
                    kind="task",
                    path="benchmarks/cua_world/environments/env_a/tasks/task_bad/task.json",
                    spec_id="task_bad@1",
                    issues=[
                        VerificationIssue(
                            code="missing_hook_reference",
                            message="pre_task references missing script(s): /workspace/tasks/task_bad/setup_task.sh",
                            severity="error",
                        ),
                        VerificationIssue(
                            code="missing_hook_reference",
                            message="post_task references missing script(s): /workspace/tasks/task_bad/export_result.sh",
                            severity="error",
                        ),
                    ],
                ),
            ],
        )

        manifest = build_missing_hook_reference_manifest(summary)

        self.assertEqual(manifest["task_count"], 1)
        self.assertEqual(manifest["environment_count"], 1)
        self.assertEqual(
            manifest["tasks"][0]["task_dir"],
            "benchmarks/cua_world/environments/env_a/tasks/task_bad",
        )
        self.assertEqual(
            manifest["tasks"][0]["missing_hook_assets"],
            [
                {"hook": "pre_task", "asset": "/workspace/tasks/task_bad/setup_task.sh"},
                {"hook": "post_task", "asset": "/workspace/tasks/task_bad/export_result.sh"},
            ],
        )


if __name__ == "__main__":
    unittest.main()
