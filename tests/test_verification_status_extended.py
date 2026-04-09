from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from gym_anything.verification.reports import (
    VerificationIssue,
    VerificationRecord,
    VerificationSummary,
)
from gym_anything.verification.status import (
    build_missing_hook_reference_manifest,
    build_task_status_manifest,
    build_verified_task_split,
    write_json_report,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ROOT = "benchmarks/cua_world/environments"


def _ok_task(env: str, task: str, spec_id: str | None = None) -> VerificationRecord:
    return VerificationRecord(
        kind="task",
        path=f"{ROOT}/{env}/tasks/{task}/task.json",
        spec_id=spec_id or f"{task}@1",
    )


def _fail_task(
    env: str,
    task: str,
    code: str = "missing_hook_reference",
    message: str = "error",
    spec_id: str | None = None,
) -> VerificationRecord:
    return VerificationRecord(
        kind="task",
        path=f"{ROOT}/{env}/tasks/{task}/task.json",
        spec_id=spec_id or f"{task}@1",
        issues=[VerificationIssue(code=code, message=message, severity="error")],
    )


def _warn_task(env: str, task: str) -> VerificationRecord:
    return VerificationRecord(
        kind="task",
        path=f"{ROOT}/{env}/tasks/{task}/task.json",
        issues=[VerificationIssue(code="w", message="warn", severity="warning")],
    )


def _env_record(env: str) -> VerificationRecord:
    return VerificationRecord(
        kind="env",
        path=f"{ROOT}/{env}/env.json",
        spec_id=f"{env}@1",
    )


# ---------------------------------------------------------------------------
# build_task_status_manifest — extended coverage
# ---------------------------------------------------------------------------


class TestBuildTaskStatusManifest(unittest.TestCase):
    def test_empty_summary_returns_zero_counts(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_task_status_manifest(s)
        self.assertEqual(m["total_task_records"], 0)
        self.assertEqual(m["verified_task_count"], 0)
        self.assertEqual(m["failed_task_count"], 0)
        self.assertEqual(m["issue_counts"], {})
        self.assertEqual(m["verified_tasks"], [])
        self.assertEqual(m["failed_tasks"], [])
        self.assertEqual(m["by_environment"], {})

    def test_schema_version_is_1(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_task_status_manifest(s)
        self.assertEqual(m["schema_version"], 1)

    def test_generated_at_present(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_task_status_manifest(s)
        self.assertIn("generated_at", m)
        self.assertIsInstance(m["generated_at"], str)

    def test_env_records_excluded_from_task_counts(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_env_record("env_a"), _ok_task("env_a", "task_1")],
        )
        m = build_task_status_manifest(s)
        self.assertEqual(m["total_task_records"], 1)
        self.assertEqual(m["verified_task_count"], 1)

    def test_verified_task_entry_fields(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_ok_task("env_a", "task_1", spec_id="task_1@2")],
        )
        m = build_task_status_manifest(s)
        entry = m["verified_tasks"][0]
        self.assertEqual(entry["status"], "verified")
        self.assertEqual(entry["spec_id"], "task_1@2")
        self.assertEqual(entry["environment"], "env_a")
        self.assertEqual(entry["task_id"], "task_1")
        self.assertEqual(entry["task_ref"], "env_a/task_1")

    def test_failed_task_entry_fields(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_fail_task("env_b", "task_bad", code="invalid_verifier", message="bad program")],
        )
        m = build_task_status_manifest(s)
        entry = m["failed_tasks"][0]
        self.assertEqual(entry["status"], "failed")
        self.assertEqual(entry["environment"], "env_b")
        self.assertIn("issues", entry)
        self.assertEqual(entry["issues"][0]["code"], "invalid_verifier")

    def test_issue_counts_aggregated(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _fail_task("env_a", "t1", code="code_x"),
                _fail_task("env_b", "t2", code="code_x"),
                _fail_task("env_c", "t3", code="code_y"),
            ],
        )
        m = build_task_status_manifest(s)
        self.assertEqual(m["issue_counts"]["code_x"], 2)
        self.assertEqual(m["issue_counts"]["code_y"], 1)

    def test_by_environment_verified_tasks_sorted(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_a", "z_task"),
                _ok_task("env_a", "a_task"),
            ],
        )
        m = build_task_status_manifest(s)
        self.assertEqual(m["by_environment"]["env_a"]["verified_tasks"], ["a_task", "z_task"])

    def test_by_environment_failed_tasks_sorted(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _fail_task("env_a", "z_fail"),
                _fail_task("env_a", "a_fail"),
            ],
        )
        m = build_task_status_manifest(s)
        self.assertEqual(m["by_environment"]["env_a"]["failed_tasks"], ["a_fail", "z_fail"])

    def test_by_environment_multiple_envs(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_alpha", "t1"),
                _ok_task("env_beta", "t2"),
                _fail_task("env_beta", "t3"),
            ],
        )
        m = build_task_status_manifest(s)
        self.assertIn("env_alpha", m["by_environment"])
        self.assertIn("env_beta", m["by_environment"])
        self.assertEqual(len(m["by_environment"]["env_alpha"]["verified_tasks"]), 1)
        self.assertEqual(len(m["by_environment"]["env_beta"]["failed_tasks"]), 1)

    def test_warning_only_task_counted_as_verified(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_warn_task("env_a", "t1")],
        )
        m = build_task_status_manifest(s)
        self.assertEqual(m["verified_task_count"], 1)
        self.assertEqual(m["failed_task_count"], 0)

    def test_root_preserved_in_manifest(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_task_status_manifest(s)
        self.assertEqual(m["root"], ROOT)

    def test_by_environment_issue_counts_per_env(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _fail_task("env_a", "t1", code="bad_hook"),
                _fail_task("env_a", "t2", code="bad_hook"),
                _fail_task("env_b", "t3", code="bad_hook"),
            ],
        )
        m = build_task_status_manifest(s)
        self.assertEqual(m["by_environment"]["env_a"]["issue_counts"]["bad_hook"], 2)
        self.assertEqual(m["by_environment"]["env_b"]["issue_counts"]["bad_hook"], 1)

    def test_no_issues_key_on_ok_task(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_ok_task("env_a", "t1")],
        )
        m = build_task_status_manifest(s)
        entry = m["verified_tasks"][0]
        self.assertNotIn("issues", entry)


# ---------------------------------------------------------------------------
# build_verified_task_split — extended coverage
# ---------------------------------------------------------------------------


class TestBuildVerifiedTaskSplit(unittest.TestCase):
    def test_empty_summary(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        split = build_verified_task_split(s)
        self.assertEqual(split["task_count"], 0)
        self.assertEqual(split["tasks"], [])
        self.assertEqual(split["by_environment"], {})

    def test_schema_version_is_1(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        split = build_verified_task_split(s)
        self.assertEqual(split["schema_version"], 1)

    def test_excludes_failed_tasks(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_a", "t_ok"),
                _fail_task("env_a", "t_fail"),
            ],
        )
        split = build_verified_task_split(s)
        self.assertEqual(split["task_count"], 1)
        self.assertEqual(split["tasks"], ["env_a/t_ok"])

    def test_excludes_env_records(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_env_record("env_a"), _ok_task("env_a", "t1")],
        )
        split = build_verified_task_split(s)
        self.assertEqual(split["task_count"], 1)

    def test_tasks_sorted(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_b", "z"),
                _ok_task("env_a", "a"),
            ],
        )
        split = build_verified_task_split(s)
        self.assertEqual(split["tasks"], ["env_a/a", "env_b/z"])

    def test_by_environment_sorted(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_b", "t1"),
                _ok_task("env_a", "t2"),
            ],
        )
        split = build_verified_task_split(s)
        self.assertEqual(list(split["by_environment"].keys()), ["env_a", "env_b"])

    def test_by_environment_tasks_sorted(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_a", "z_task"),
                _ok_task("env_a", "a_task"),
            ],
        )
        split = build_verified_task_split(s)
        self.assertEqual(split["by_environment"]["env_a"], ["a_task", "z_task"])

    def test_multi_env_grouping(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[
                _ok_task("env_a", "t1"),
                _ok_task("env_b", "t2"),
                _ok_task("env_b", "t3"),
            ],
        )
        split = build_verified_task_split(s)
        self.assertEqual(len(split["by_environment"]["env_a"]), 1)
        self.assertEqual(len(split["by_environment"]["env_b"]), 2)

    def test_root_preserved(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        split = build_verified_task_split(s)
        self.assertEqual(split["root"], ROOT)

    def test_generated_at_present(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        split = build_verified_task_split(s)
        self.assertIn("generated_at", split)

    def test_warning_task_included_as_verified(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_warn_task("env_a", "t1")],
        )
        split = build_verified_task_split(s)
        self.assertEqual(split["task_count"], 1)
        self.assertIn("env_a/t1", split["tasks"])


# ---------------------------------------------------------------------------
# build_missing_hook_reference_manifest — extended coverage
# ---------------------------------------------------------------------------


class TestBuildMissingHookReferenceManifest(unittest.TestCase):
    def test_empty_summary(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["task_count"], 0)
        self.assertEqual(m["environment_count"], 0)
        self.assertEqual(m["tasks"], [])
        self.assertEqual(m["by_environment"], {})

    def test_schema_version_is_1(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["schema_version"], 1)

    def test_no_missing_hook_issues_returns_empty(self):
        s = VerificationSummary(
            scope="corpus",
            root=ROOT,
            records=[_fail_task("env_a", "t1", code="invalid_verifier", message="bad")],
        )
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["task_count"], 0)

    def test_single_missing_hook_asset(self):
        record = VerificationRecord(
            kind="task",
            path=f"{ROOT}/env_a/tasks/t1/task.json",
            issues=[
                VerificationIssue(
                    code="missing_hook_reference",
                    message="pre_task references missing script(s): /workspace/tasks/t1/setup.sh",
                    severity="error",
                )
            ],
        )
        s = VerificationSummary(scope="corpus", root=ROOT, records=[record])
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["task_count"], 1)
        assets = m["tasks"][0]["missing_hook_assets"]
        self.assertEqual(len(assets), 1)
        self.assertEqual(assets[0]["hook"], "pre_task")
        self.assertEqual(assets[0]["asset"], "/workspace/tasks/t1/setup.sh")

    def test_multiple_assets_in_one_message(self):
        record = VerificationRecord(
            kind="task",
            path=f"{ROOT}/env_a/tasks/t1/task.json",
            issues=[
                VerificationIssue(
                    code="missing_hook_reference",
                    message="pre_task references missing script(s): /a/setup.sh, /b/install.sh",
                    severity="error",
                )
            ],
        )
        s = VerificationSummary(scope="corpus", root=ROOT, records=[record])
        m = build_missing_hook_reference_manifest(s)
        assets = m["tasks"][0]["missing_hook_assets"]
        self.assertEqual(len(assets), 2)
        self.assertEqual(assets[0]["asset"], "/a/setup.sh")
        self.assertEqual(assets[1]["asset"], "/b/install.sh")

    def test_multiple_hook_issues_per_task(self):
        record = VerificationRecord(
            kind="task",
            path=f"{ROOT}/env_a/tasks/t1/task.json",
            issues=[
                VerificationIssue(
                    code="missing_hook_reference",
                    message="pre_task references missing script(s): /setup.sh",
                    severity="error",
                ),
                VerificationIssue(
                    code="missing_hook_reference",
                    message="post_task references missing script(s): /cleanup.sh",
                    severity="error",
                ),
            ],
        )
        s = VerificationSummary(scope="corpus", root=ROOT, records=[record])
        m = build_missing_hook_reference_manifest(s)
        assets = m["tasks"][0]["missing_hook_assets"]
        self.assertEqual(len(assets), 2)
        hook_names = {a["hook"] for a in assets}
        self.assertIn("pre_task", hook_names)
        self.assertIn("post_task", hook_names)

    def test_env_records_excluded(self):
        env_record = VerificationRecord(
            kind="env",
            path=f"{ROOT}/env_a/env.json",
            issues=[
                VerificationIssue(
                    code="missing_hook_reference",
                    message="pre_task references missing script(s): /x.sh",
                    severity="error",
                )
            ],
        )
        s = VerificationSummary(scope="corpus", root=ROOT, records=[env_record])
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["task_count"], 0)

    def test_by_environment_counts(self):
        records = [
            VerificationRecord(
                kind="task",
                path=f"{ROOT}/env_a/tasks/t{i}/task.json",
                issues=[
                    VerificationIssue(
                        code="missing_hook_reference",
                        message=f"pre_task references missing script(s): /s{i}.sh",
                        severity="error",
                    )
                ],
            )
            for i in range(3)
        ]
        s = VerificationSummary(scope="corpus", root=ROOT, records=records)
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["environment_count"], 1)
        env_data = m["by_environment"]["env_a"]
        self.assertEqual(env_data["task_count"], 3)
        self.assertEqual(env_data["missing_hook_asset_count"], 3)

    def test_unmatched_message_format_hook_unknown(self):
        record = VerificationRecord(
            kind="task",
            path=f"{ROOT}/env_a/tasks/t1/task.json",
            issues=[
                VerificationIssue(
                    code="missing_hook_reference",
                    message="some unexpected message format",
                    severity="error",
                )
            ],
        )
        s = VerificationSummary(scope="corpus", root=ROOT, records=[record])
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["task_count"], 1)
        assets = m["tasks"][0]["missing_hook_assets"]
        self.assertEqual(assets[0]["hook"], "unknown")

    def test_mixed_issue_codes_only_hook_issues_in_assets(self):
        record = VerificationRecord(
            kind="task",
            path=f"{ROOT}/env_a/tasks/t1/task.json",
            issues=[
                VerificationIssue(
                    code="missing_hook_reference",
                    message="pre_task references missing script(s): /setup.sh",
                    severity="error",
                ),
                VerificationIssue(code="invalid_verifier", message="bad verifier", severity="error"),
            ],
        )
        s = VerificationSummary(scope="corpus", root=ROOT, records=[record])
        m = build_missing_hook_reference_manifest(s)
        task = m["tasks"][0]
        # Only missing_hook_reference issues should appear in "issues" list of the task entry
        for issue in task["issues"]:
            self.assertEqual(issue["code"], "missing_hook_reference")

    def test_root_preserved(self):
        s = VerificationSummary(scope="corpus", root=ROOT)
        m = build_missing_hook_reference_manifest(s)
        self.assertEqual(m["root"], ROOT)


# ---------------------------------------------------------------------------
# write_json_report — extended coverage
# ---------------------------------------------------------------------------


class TestWriteJsonReport(unittest.TestCase):
    def test_creates_parent_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "a" / "b" / "report.json"
            write_json_report({"x": 1}, out)
            self.assertTrue(out.exists())

    def test_writes_valid_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "report.json"
            write_json_report({"hello": "world", "n": 42}, out)
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data["hello"], "world")
            self.assertEqual(data["n"], 42)

    def test_file_ends_with_newline(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "report.json"
            write_json_report({}, out)
            raw = out.read_text(encoding="utf-8")
            self.assertTrue(raw.endswith("\n"))

    def test_overwrites_existing_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "report.json"
            write_json_report({"v": 1}, out)
            write_json_report({"v": 2}, out)
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data["v"], 2)

    def test_empty_dict(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "report.json"
            write_json_report({}, out)
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data, {})

    def test_accepts_path_string(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "report.json"
            write_json_report({"ok": True}, str(out))
            self.assertTrue(out.exists())


if __name__ == "__main__":
    unittest.main()
