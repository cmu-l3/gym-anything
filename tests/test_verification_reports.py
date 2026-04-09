from __future__ import annotations

import unittest

from gym_anything.verification.reports import (
    TaskPipelineVerificationResult,
    VerificationIssue,
    VerificationRecord,
    VerificationSummary,
    render_summary_text,
    render_task_pipeline_result_text,
)


# ---------------------------------------------------------------------------
# VerificationIssue
# ---------------------------------------------------------------------------


class TestVerificationIssue(unittest.TestCase):
    def test_default_severity_is_error(self):
        issue = VerificationIssue(code="bad_spec", message="Field missing")
        self.assertEqual(issue.severity, "error")

    def test_default_path_is_none(self):
        issue = VerificationIssue(code="bad_spec", message="Field missing")
        self.assertIsNone(issue.path)

    def test_explicit_severity_warning(self):
        issue = VerificationIssue(code="w001", message="Consider using X", severity="warning")
        self.assertEqual(issue.severity, "warning")

    def test_explicit_severity_info(self):
        issue = VerificationIssue(code="i001", message="FYI", severity="info")
        self.assertEqual(issue.severity, "info")

    def test_path_stored(self):
        issue = VerificationIssue(code="c001", message="msg", path="/some/file.py")
        self.assertEqual(issue.path, "/some/file.py")

    def test_code_and_message_stored(self):
        issue = VerificationIssue(code="MY_CODE", message="My message")
        self.assertEqual(issue.code, "MY_CODE")
        self.assertEqual(issue.message, "My message")

    def test_equality(self):
        a = VerificationIssue(code="x", message="y", severity="warning", path="/p")
        b = VerificationIssue(code="x", message="y", severity="warning", path="/p")
        self.assertEqual(a, b)

    def test_inequality_different_code(self):
        a = VerificationIssue(code="x", message="y")
        b = VerificationIssue(code="z", message="y")
        self.assertNotEqual(a, b)


# ---------------------------------------------------------------------------
# VerificationRecord
# ---------------------------------------------------------------------------


class TestVerificationRecord(unittest.TestCase):
    def test_default_issues_empty(self):
        record = VerificationRecord(kind="task", path="/some/task.json")
        self.assertEqual(record.issues, [])

    def test_default_spec_id_none(self):
        record = VerificationRecord(kind="env", path="/env.json")
        self.assertIsNone(record.spec_id)

    def test_ok_when_no_issues(self):
        record = VerificationRecord(kind="task", path="/t.json")
        self.assertTrue(record.ok)

    def test_ok_when_only_warnings(self):
        record = VerificationRecord(
            kind="task",
            path="/t.json",
            issues=[VerificationIssue(code="w", message="warn", severity="warning")],
        )
        self.assertTrue(record.ok)

    def test_ok_when_only_info(self):
        record = VerificationRecord(
            kind="task",
            path="/t.json",
            issues=[VerificationIssue(code="i", message="info", severity="info")],
        )
        self.assertTrue(record.ok)

    def test_not_ok_when_error_present(self):
        record = VerificationRecord(
            kind="task",
            path="/t.json",
            issues=[VerificationIssue(code="e", message="error", severity="error")],
        )
        self.assertFalse(record.ok)

    def test_not_ok_with_mixed_severities(self):
        record = VerificationRecord(
            kind="task",
            path="/t.json",
            issues=[
                VerificationIssue(code="w", message="warn", severity="warning"),
                VerificationIssue(code="e", message="err", severity="error"),
            ],
        )
        self.assertFalse(record.ok)

    def test_spec_id_stored(self):
        record = VerificationRecord(kind="task", path="/t.json", spec_id="demo@1")
        self.assertEqual(record.spec_id, "demo@1")

    def test_kind_env(self):
        record = VerificationRecord(kind="env", path="/env.json")
        self.assertEqual(record.kind, "env")

    def test_multiple_error_issues_still_not_ok(self):
        record = VerificationRecord(
            kind="task",
            path="/t.json",
            issues=[
                VerificationIssue(code="e1", message="err1", severity="error"),
                VerificationIssue(code="e2", message="err2", severity="error"),
            ],
        )
        self.assertFalse(record.ok)

    def test_issues_list_is_independent_per_instance(self):
        r1 = VerificationRecord(kind="task", path="/t1.json")
        r2 = VerificationRecord(kind="task", path="/t2.json")
        r1.issues.append(VerificationIssue(code="x", message="x"))
        self.assertEqual(r2.issues, [])


# ---------------------------------------------------------------------------
# VerificationSummary
# ---------------------------------------------------------------------------


class TestVerificationSummary(unittest.TestCase):
    def _make_ok_record(self, path: str) -> VerificationRecord:
        return VerificationRecord(kind="task", path=path)

    def _make_fail_record(self, path: str) -> VerificationRecord:
        return VerificationRecord(
            kind="task",
            path=path,
            issues=[VerificationIssue(code="err", message="bad", severity="error")],
        )

    def _make_warn_record(self, path: str) -> VerificationRecord:
        return VerificationRecord(
            kind="task",
            path=path,
            issues=[VerificationIssue(code="w", message="warn", severity="warning")],
        )

    def test_empty_summary(self):
        s = VerificationSummary(scope="corpus", root="/root")
        self.assertEqual(s.total_records, 0)
        self.assertEqual(s.error_count, 0)
        self.assertEqual(s.warning_count, 0)
        self.assertEqual(s.failed_records, 0)
        self.assertTrue(s.ok)

    def test_total_records(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[self._make_ok_record("/a"), self._make_ok_record("/b")],
        )
        self.assertEqual(s.total_records, 2)

    def test_error_count(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                self._make_fail_record("/a"),
                self._make_fail_record("/b"),
                self._make_ok_record("/c"),
            ],
        )
        self.assertEqual(s.error_count, 2)

    def test_warning_count(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                self._make_warn_record("/a"),
                self._make_ok_record("/b"),
            ],
        )
        self.assertEqual(s.warning_count, 1)

    def test_failed_records(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                self._make_fail_record("/a"),
                self._make_ok_record("/b"),
            ],
        )
        self.assertEqual(s.failed_records, 1)

    def test_ok_false_when_any_error(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[self._make_fail_record("/a")],
        )
        self.assertFalse(s.ok)

    def test_ok_true_when_only_warnings(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[self._make_warn_record("/a")],
        )
        self.assertTrue(s.ok)

    def test_multiple_issues_per_record_counted(self):
        record = VerificationRecord(
            kind="task",
            path="/t.json",
            issues=[
                VerificationIssue(code="e1", message="err1", severity="error"),
                VerificationIssue(code="e2", message="err2", severity="error"),
                VerificationIssue(code="w1", message="warn1", severity="warning"),
            ],
        )
        s = VerificationSummary(scope="corpus", root="/root", records=[record])
        self.assertEqual(s.error_count, 2)
        self.assertEqual(s.warning_count, 1)

    def test_to_dict_returns_dict(self):
        s = VerificationSummary(scope="corpus", root="/root")
        d = s.to_dict()
        self.assertIsInstance(d, dict)
        self.assertEqual(d["scope"], "corpus")
        self.assertEqual(d["root"], "/root")
        self.assertEqual(d["records"], [])

    def test_to_dict_includes_records(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[self._make_ok_record("/a")],
        )
        d = s.to_dict()
        self.assertEqual(len(d["records"]), 1)

    def test_default_records_empty(self):
        s = VerificationSummary(scope="test", root="/r")
        self.assertEqual(s.records, [])

    def test_records_list_is_independent_per_instance(self):
        s1 = VerificationSummary(scope="a", root="/r1")
        s2 = VerificationSummary(scope="b", root="/r2")
        s1.records.append(self._make_ok_record("/x"))
        self.assertEqual(s2.records, [])


# ---------------------------------------------------------------------------
# TaskPipelineVerificationResult
# ---------------------------------------------------------------------------


class TestTaskPipelineVerificationResult(unittest.TestCase):
    def test_minimal_construction(self):
        r = TaskPipelineVerificationResult(
            env_dir="/envs/my_env",
            task_id="task_01",
            ok=True,
            stage="verify",
        )
        self.assertEqual(r.env_dir, "/envs/my_env")
        self.assertEqual(r.task_id, "task_01")
        self.assertTrue(r.ok)
        self.assertEqual(r.stage, "verify")
        self.assertIsNone(r.episode_dir)
        self.assertIsNone(r.verifier)
        self.assertIsNone(r.error)

    def test_failed_result(self):
        r = TaskPipelineVerificationResult(
            env_dir="/envs/e",
            task_id="t",
            ok=False,
            stage="setup",
            error="Setup crashed",
        )
        self.assertFalse(r.ok)
        self.assertEqual(r.error, "Setup crashed")

    def test_full_construction(self):
        r = TaskPipelineVerificationResult(
            env_dir="/envs/e",
            task_id="t",
            ok=True,
            stage="verify",
            episode_dir="/episodes/ep1",
            verifier={"type": "program", "result": True},
            error=None,
        )
        self.assertEqual(r.episode_dir, "/episodes/ep1")
        self.assertEqual(r.verifier, {"type": "program", "result": True})

    def test_to_dict_ok_result(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e", task_id="t", ok=True, stage="verify"
        )
        d = r.to_dict()
        self.assertIsInstance(d, dict)
        self.assertTrue(d["ok"])
        self.assertEqual(d["env_dir"], "/e")
        self.assertEqual(d["task_id"], "t")
        self.assertEqual(d["stage"], "verify")
        self.assertIsNone(d["episode_dir"])
        self.assertIsNone(d["verifier"])
        self.assertIsNone(d["error"])

    def test_to_dict_failed_result(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e", task_id="t", ok=False, stage="setup", error="boom"
        )
        d = r.to_dict()
        self.assertFalse(d["ok"])
        self.assertEqual(d["error"], "boom")

    def test_to_dict_with_verifier(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e",
            task_id="t",
            ok=True,
            stage="verify",
            verifier={"success": True, "score": 1.0},
        )
        d = r.to_dict()
        self.assertEqual(d["verifier"], {"success": True, "score": 1.0})


# ---------------------------------------------------------------------------
# render_summary_text
# ---------------------------------------------------------------------------


class TestRenderSummaryText(unittest.TestCase):
    def test_empty_summary_contains_headers(self):
        s = VerificationSummary(scope="corpus", root="/root")
        text = render_summary_text(s)
        self.assertIn("Scope: corpus", text)
        self.assertIn("Root: /root", text)
        self.assertIn("Records: 0", text)
        self.assertIn("Failed records: 0", text)
        self.assertIn("Errors: 0", text)
        self.assertIn("Warnings: 0", text)

    def test_ok_record_shows_ok_status(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(kind="task", path="/root/t.json", spec_id="demo@1"),
            ],
        )
        text = render_summary_text(s)
        self.assertIn("[OK]", text)
        self.assertIn("demo@1", text)
        self.assertIn("task", text)

    def test_failed_record_shows_fail_status(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(
                    kind="task",
                    path="/root/t.json",
                    spec_id="demo@1",
                    issues=[VerificationIssue(code="bad", message="broken", severity="error")],
                ),
            ],
        )
        text = render_summary_text(s)
        self.assertIn("[FAIL]", text)

    def test_issue_details_in_output(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(
                    kind="task",
                    path="/root/t.json",
                    issues=[
                        VerificationIssue(
                            code="MY_CODE",
                            message="Something broke",
                            severity="error",
                            path="/hook.sh",
                        )
                    ],
                ),
            ],
        )
        text = render_summary_text(s)
        self.assertIn("MY_CODE", text)
        self.assertIn("Something broke", text)
        self.assertIn("/hook.sh", text)

    def test_issue_without_path_no_extra_parentheses(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(
                    kind="task",
                    path="/root/t.json",
                    issues=[VerificationIssue(code="c", message="msg")],
                ),
            ],
        )
        text = render_summary_text(s)
        lines = text.split("\n")
        issue_line = next(l for l in lines if "msg" in l)
        self.assertNotIn("()", issue_line)

    def test_uses_path_when_spec_id_none(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(kind="env", path="/env.json"),
            ],
        )
        text = render_summary_text(s)
        self.assertIn("/env.json", text)

    def test_summary_counts_in_output(self):
        issue = VerificationIssue(code="e", message="err", severity="error")
        warn = VerificationIssue(code="w", message="warn", severity="warning")
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(kind="task", path="/a.json", issues=[issue, warn]),
            ],
        )
        text = render_summary_text(s)
        self.assertIn("Errors: 1", text)
        self.assertIn("Warnings: 1", text)
        self.assertIn("Failed records: 1", text)

    def test_returns_string(self):
        s = VerificationSummary(scope="s", root="/r")
        self.assertIsInstance(render_summary_text(s), str)

    def test_multiple_records_all_in_output(self):
        s = VerificationSummary(
            scope="corpus",
            root="/root",
            records=[
                VerificationRecord(kind="task", path="/a.json", spec_id="a@1"),
                VerificationRecord(kind="task", path="/b.json", spec_id="b@1"),
            ],
        )
        text = render_summary_text(s)
        self.assertIn("a@1", text)
        self.assertIn("b@1", text)


# ---------------------------------------------------------------------------
# render_task_pipeline_result_text
# ---------------------------------------------------------------------------


class TestRenderTaskPipelineResultText(unittest.TestCase):
    def test_ok_result_contains_basics(self):
        r = TaskPipelineVerificationResult(
            env_dir="/envs/my_env",
            task_id="task_01",
            ok=True,
            stage="verify",
        )
        text = render_task_pipeline_result_text(r)
        self.assertIn("Environment: /envs/my_env", text)
        self.assertIn("Task: task_01", text)
        self.assertIn("Stage: verify", text)
        self.assertIn("Status: OK", text)

    def test_failed_result_status(self):
        r = TaskPipelineVerificationResult(
            env_dir="/envs/e",
            task_id="t",
            ok=False,
            stage="setup",
        )
        text = render_task_pipeline_result_text(r)
        self.assertIn("Status: FAIL", text)

    def test_episode_dir_included_when_set(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e",
            task_id="t",
            ok=True,
            stage="verify",
            episode_dir="/episodes/ep42",
        )
        text = render_task_pipeline_result_text(r)
        self.assertIn("Episode dir: /episodes/ep42", text)

    def test_episode_dir_absent_when_none(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e", task_id="t", ok=True, stage="verify"
        )
        text = render_task_pipeline_result_text(r)
        self.assertNotIn("Episode dir", text)

    def test_verifier_included_when_set(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e",
            task_id="t",
            ok=True,
            stage="verify",
            verifier={"result": True},
        )
        text = render_task_pipeline_result_text(r)
        self.assertIn("Verifier:", text)

    def test_verifier_absent_when_none(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e", task_id="t", ok=True, stage="verify"
        )
        text = render_task_pipeline_result_text(r)
        self.assertNotIn("Verifier", text)

    def test_error_included_when_set(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e",
            task_id="t",
            ok=False,
            stage="setup",
            error="Container failed to start",
        )
        text = render_task_pipeline_result_text(r)
        self.assertIn("Error: Container failed to start", text)

    def test_error_absent_when_none(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e", task_id="t", ok=True, stage="verify"
        )
        text = render_task_pipeline_result_text(r)
        self.assertNotIn("Error:", text)

    def test_returns_string(self):
        r = TaskPipelineVerificationResult(
            env_dir="/e", task_id="t", ok=True, stage="verify"
        )
        self.assertIsInstance(render_task_pipeline_result_text(r), str)

    def test_full_result_all_fields(self):
        r = TaskPipelineVerificationResult(
            env_dir="/envs/e",
            task_id="task_x",
            ok=True,
            stage="verify",
            episode_dir="/ep/1",
            verifier={"type": "program"},
            error=None,
        )
        text = render_task_pipeline_result_text(r)
        self.assertIn("Environment: /envs/e", text)
        self.assertIn("Task: task_x", text)
        self.assertIn("Stage: verify", text)
        self.assertIn("Status: OK", text)
        self.assertIn("Episode dir: /ep/1", text)
        self.assertIn("Verifier:", text)
        self.assertNotIn("Error:", text)


if __name__ == "__main__":
    unittest.main()
