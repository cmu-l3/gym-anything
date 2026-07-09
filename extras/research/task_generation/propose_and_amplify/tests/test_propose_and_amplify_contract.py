"""Contract tests for the propose_and_amplify driver.

Verify the parser, path resolution, prefix construction, and stage
plumbing without invoking real LLM APIs or agent CLIs.
"""

from __future__ import annotations

import json
import os
import pickle
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "src"))

from extras.research.task_generation.propose_and_amplify import method as pa  # noqa: E402
from extras.research.task_generation.propose_and_amplify import pipeline  # noqa: E402
from extras.research.task_generation.propose_and_amplify.pipeline import propose_cc  # noqa: E402


class PathResolutionTests(unittest.TestCase):
    def test_default_workspace_finds_repo(self):
        ws = pa._default_workspace()
        self.assertTrue((ws / "src" / "gym_anything").is_dir())

    def test_packaged_task_creation_notes_exists(self):
        notes = REPO_ROOT / (
            "extras/research/task_generation/propose_and_amplify/"
            "memory/task_creation_notes"
        )
        self.assertTrue(notes.is_dir(), notes)
        self.assertTrue((notes / "00_getting_started.md").is_file())

    def test_pipeline_constants_resolve_to_repo(self):
        self.assertEqual(
            Path(pipeline.get_examples_dir()),
            REPO_ROOT / "benchmarks" / "cua_world" / "environments",
        )
        self.assertEqual(Path(pipeline.get_project_root()), REPO_ROOT)

    def test_resolve_env_folder_from_short_name(self):
        ws = REPO_ROOT
        # moodle_env exists in the corpus
        resolved = pa._resolve_env_folder("moodle_env", ws)
        self.assertEqual(
            resolved,
            ws / "benchmarks" / "cua_world" / "environments" / "moodle_env",
        )

    def test_resolve_env_folder_rejects_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                pa._resolve_env_folder("does_not_exist_env", Path(tmp))


class ParserTests(unittest.TestCase):
    def test_required_args(self):
        with self.assertRaises(SystemExit):
            pa.build_parser().parse_args([])

    def test_defaults(self):
        args = pa.build_parser().parse_args(
            ["--software", "Demo", "--env-dir", "demo_env"]
        )
        self.assertEqual(args.software, "Demo")
        self.assertEqual(args.env_dir, "demo_env")
        self.assertEqual(args.stage, "all")
        self.assertEqual(args.amplifier_model, pa.DEFAULT_AMPLIFIER_MODEL)
        self.assertEqual(args.proposer_model, pa.DEFAULT_PROPOSER_MODEL)
        self.assertEqual(args.amplify_count, pa.DEFAULT_AMPLIFY_COUNT)

    def test_stage_choices(self):
        for stage in ("propose", "amplify", "extract", "all"):
            args = pa.build_parser().parse_args(
                ["--software", "Demo", "--env-dir", "demo_env",
                 "--stage", stage]
            )
            self.assertEqual(args.stage, stage)

    def test_stage_rejects_unknown(self):
        with self.assertRaises(SystemExit):
            pa.build_parser().parse_args(
                ["--software", "Demo", "--env-dir", "demo_env",
                 "--stage", "merge"]  # used to exist; now removed
            )

    def test_no_databricks_flag(self):
        # The flag was removed; argparse should reject it.
        with self.assertRaises(SystemExit):
            pa.build_parser().parse_args(
                ["--software", "Demo", "--env-dir", "demo_env",
                 "--use-databricks", "true"]
            )


class PrefixTests(unittest.TestCase):
    def test_readme_prefix_uses_amplifier_model(self):
        self.assertEqual(
            pa._readme_prefix("gemini-3-pro-preview", "Apache OpenOffice"),
            "enhanced_gemini-3-pro-preview_Apache_OpenOffice",
        )

    def test_files_prefix_uses_amplifier_model(self):
        self.assertEqual(
            pa._files_prefix("gemini-3-pro-preview", "Apache OpenOffice"),
            "enhanced_files_gemini-3-pro-preview_Apache_OpenOffice",
        )

    def test_model_slug_replaces_slashes(self):
        self.assertEqual(pa._model_slug("anthropic/claude-opus"),
                         "anthropic-claude-opus")


class StagePlanningTests(unittest.TestCase):
    """Drive run_pipeline with stubs that record which stage runs."""

    def _setup_workspace(self, tmp: str):
        workspace = Path(tmp)
        (workspace / "src" / "gym_anything").mkdir(parents=True)
        env_folder = (workspace / "benchmarks" / "cua_world" /
                      "environments" / "demo_env")
        env_folder.mkdir(parents=True)
        return workspace, env_folder

    def test_stage_all_runs_propose_amplify_extract_in_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, _ = self._setup_workspace(tmp)
            args = pa.build_parser().parse_args([
                "--software", "Demo", "--env-dir", "demo_env",
                "--workspace", str(workspace),
            ])
            calls: list[str] = []

            with mock.patch.object(pa, "_stage_propose",
                                   side_effect=lambda *a, **k: calls.append("propose") or 0), \
                 mock.patch.object(pa, "_stage_amplify",
                                   side_effect=lambda *a, **k: calls.append("amplify") or 0), \
                 mock.patch.object(pa, "_stage_extract",
                                   side_effect=lambda *a, **k: calls.append("extract") or 0):
                rc = pa.run_pipeline(args)

            self.assertEqual(rc, 0)
            self.assertEqual(calls, ["propose", "amplify", "extract"])

    def test_stage_single_runs_only_that_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, _ = self._setup_workspace(tmp)
            args = pa.build_parser().parse_args([
                "--software", "Demo", "--env-dir", "demo_env",
                "--workspace", str(workspace),
                "--stage", "extract",
            ])
            calls: list[str] = []

            with mock.patch.object(pa, "_stage_propose",
                                   side_effect=lambda *a, **k: calls.append("propose") or 0), \
                 mock.patch.object(pa, "_stage_amplify",
                                   side_effect=lambda *a, **k: calls.append("amplify") or 0), \
                 mock.patch.object(pa, "_stage_extract",
                                   side_effect=lambda *a, **k: calls.append("extract") or 0):
                rc = pa.run_pipeline(args)

            self.assertEqual(rc, 0)
            self.assertEqual(calls, ["extract"])

    def test_failed_stage_stops_the_pipeline(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, _ = self._setup_workspace(tmp)
            args = pa.build_parser().parse_args([
                "--software", "Demo", "--env-dir", "demo_env",
                "--workspace", str(workspace),
            ])
            calls: list[str] = []

            with mock.patch.object(pa, "_stage_propose",
                                   side_effect=lambda *a, **k: calls.append("propose") or 0), \
                 mock.patch.object(pa, "_stage_amplify",
                                   side_effect=lambda *a, **k: calls.append("amplify") or 9), \
                 mock.patch.object(pa, "_stage_extract",
                                   side_effect=lambda *a, **k: calls.append("extract") or 0):
                rc = pa.run_pipeline(args)

            self.assertEqual(rc, 9)
            self.assertEqual(calls, ["propose", "amplify"])


class ProposeCcPromptIntegrityTests(unittest.TestCase):
    """The proposer prompts must remain byte-identical to the original
    driver (only `task_creation_notes/` references resolved to the
    real packaged path)."""

    def _capture_prompts(self) -> list[str]:
        captured: list[str] = []

        def fake_run_claude(binary, args, *, cwd, timeout):
            # The "-p PROMPT" is always the second pair of args in the
            # invocations the proposer makes.
            for i, token in enumerate(args):
                if token == "-p" and i + 1 < len(args):
                    captured.append(args[i + 1])
                    break

        with mock.patch.object(propose_cc, "run_claude", side_effect=fake_run_claude), \
             mock.patch.object(propose_cc, "_resolve_bin",
                               return_value=Path("/fake/claude")):
            with tempfile.TemporaryDirectory() as tmp:
                propose_cc.run(
                    target_env_dir="moodle_env",
                    workspace=Path(tmp),
                    logs_dir=Path(tmp) / "logs",
                )
        return captured

    def test_four_prompts_emitted(self):
        prompts = self._capture_prompts()
        self.assertEqual(len(prompts), 4)

    def test_step1_prompt_text(self):
        prompts = self._capture_prompts()
        # Step 1: the step text after the @-reference must match the source.
        self.assertIn(
            ". Read ALL files in ", prompts[0]
        )
        self.assertIn(
            "Do not enter plan mode or ask me for any input at any time.",
            prompts[0],
        )

    def test_step2_prompt_text_byte_identical_after_env_name(self):
        prompts = self._capture_prompts()
        # Step 2 prompt is verbatim from the source driver; only
        # target_env_dir is interpolated.
        expected = (
            "now go through the starter tasks of moodle_env. those are a.) very easy, "
            "and b.) not really realistic. we have to create \"extremely hard\" and "
            "\"realistic\" 5 new tasks, following the criteria mentioned in "
            "task_creation_notes. please follow it, and complete the job. Do not enter "
            "plan mode or ask me for any input at any time. Remember realistic tasks, "
            "diverse environments (based on occupation and industry), and extremely "
            "difficult tasks. Also note you are not compelled to use existing data and "
            "can download new ones per task as well. (Unrelated Context: remember to "
            "use the visual_grounding MCP tool to interact with the running environment)"
        )
        self.assertEqual(prompts[1], expected)

    def test_step3_blind_nudge_prompt_byte_identical(self):
        prompts = self._capture_prompts()
        expected = (
            "please read task_creation_notes again. you have not completed the task. "
            "(Unrelated Context: remember to use the visual_grounding MCP tool to "
            "interact with the running environment). Also make sure for live runs you "
            "verify the screenshots to ensure that the task is setup correctly."
        )
        self.assertEqual(prompts[2], expected)

    def test_step1_references_packaged_notes(self):
        prompts = self._capture_prompts()
        # Real path of packaged notes
        notes_dir = (
            REPO_ROOT
            / "extras/research/task_generation/propose_and_amplify/memory/task_creation_notes"
        )
        getting_started = notes_dir / "00_getting_started.md"
        self.assertIn(f"@{getting_started.as_posix()}", prompts[0])
        self.assertIn(notes_dir.as_posix(), prompts[0])

    def test_step4_writes_seed_tasks_json_at_correct_path(self):
        prompts = self._capture_prompts()
        # Step 4 must instruct the agent to put seed_tasks.json at the
        # canonical location and use the bare-name JSON list format.
        step4 = prompts[3]
        self.assertIn(
            "benchmarks/cua_world/environments/moodle_env/tasks/seed_tasks.json",
            step4,
        )
        self.assertIn("JSON array", step4)
        self.assertIn("no @version suffix", step4)
        self.assertIn("new tasks you just created", step4)

    def test_step4_skipped_when_start_idx_advances_past_it(self):
        from extras.research.task_generation.propose_and_amplify.pipeline import propose_cc
        captured: list[str] = []

        def fake_run_claude(binary, args, *, cwd, timeout):
            for i, token in enumerate(args):
                if token == "-p" and i + 1 < len(args):
                    captured.append(args[i + 1])
                    break

        with mock.patch.object(propose_cc, "run_claude", side_effect=fake_run_claude), \
             mock.patch.object(propose_cc, "_resolve_bin",
                               return_value=Path("/fake/claude")):
            with tempfile.TemporaryDirectory() as tmp:
                propose_cc.run(
                    target_env_dir="moodle_env",
                    workspace=Path(tmp),
                    logs_dir=Path(tmp) / "logs",
                    start_idx=4,  # past every step including the new one
                )
        self.assertEqual(captured, [])


class SeedTasksJsonTests(unittest.TestCase):
    """The amplify step's third pass writes the generated task names into
    <env>/tasks/seed_tasks.json so future amplify runs see them as seeds."""

    @staticmethod
    def _make_questions_pickle(path: Path, task_names: list[str]) -> None:
        """Write a pickle that resembles main_*_enhanced output."""
        questions = []
        for name in task_names:
            # extract_task_name_from_response looks for `name@N` in the
            # first 500 chars; the original responses are full markdown
            # READMEs, but a minimal stub is enough for the test.
            questions.append(
                f"# Task `{name}@1`\n\n## Overview\n\nDemo task body."
            )
        with path.open("wb") as fh:
            pickle.dump(questions, fh)

    def test_writes_seed_tasks_json_with_extracted_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_folder = Path(tmp) / "demo_env"
            (env_folder / "tasks").mkdir(parents=True)
            pkl = env_folder / "questions.pkl"
            self._make_questions_pickle(pkl, ["task_alpha", "task_beta"])

            written = pa.write_seed_tasks_json(env_folder, pkl)

            self.assertEqual(written, env_folder / "tasks" / "seed_tasks.json")
            self.assertTrue(written.exists())
            loaded = json.loads(written.read_text())
            self.assertEqual(loaded, ["task_alpha", "task_beta"])

    def test_merges_with_existing_seed_tasks(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_folder = Path(tmp) / "demo_env"
            (env_folder / "tasks").mkdir(parents=True)
            seed_path = env_folder / "tasks" / "seed_tasks.json"
            seed_path.write_text(json.dumps(["existing_one", "task_alpha"]))

            pkl = env_folder / "questions.pkl"
            self._make_questions_pickle(pkl, ["task_alpha", "task_beta"])

            pa.write_seed_tasks_json(env_folder, pkl)

            loaded = json.loads(seed_path.read_text())
            # Existing first, then new (task_alpha skipped since already in)
            self.assertEqual(loaded, ["existing_one", "task_alpha", "task_beta"])

    def test_dedups_within_a_single_pickle(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_folder = Path(tmp) / "demo_env"
            (env_folder / "tasks").mkdir(parents=True)
            pkl = env_folder / "questions.pkl"
            self._make_questions_pickle(
                pkl, ["task_alpha", "task_alpha", "task_beta"]
            )

            pa.write_seed_tasks_json(env_folder, pkl)

            loaded = json.loads(
                (env_folder / "tasks" / "seed_tasks.json").read_text()
            )
            self.assertEqual(loaded, ["task_alpha", "task_beta"])

    def test_handles_missing_pickle_gracefully(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_folder = Path(tmp) / "demo_env"
            (env_folder / "tasks").mkdir(parents=True)
            seed_path = env_folder / "tasks" / "seed_tasks.json"

            pa.write_seed_tasks_json(env_folder, env_folder / "missing.pkl")

            # File still gets created (with whatever was already there;
            # nothing in this case → empty list).
            self.assertTrue(seed_path.exists())
            self.assertEqual(json.loads(seed_path.read_text()), [])

    def test_handles_corrupt_existing_seed_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_folder = Path(tmp) / "demo_env"
            (env_folder / "tasks").mkdir(parents=True)
            seed_path = env_folder / "tasks" / "seed_tasks.json"
            seed_path.write_text("{not valid json")

            pkl = env_folder / "questions.pkl"
            self._make_questions_pickle(pkl, ["task_alpha"])

            pa.write_seed_tasks_json(env_folder, pkl)

            self.assertEqual(json.loads(seed_path.read_text()), ["task_alpha"])

    def test_extract_task_names_returns_empty_for_missing_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(pa._extract_task_names(Path(tmp) / "no.pkl"), [])


class AmplifyStageInvokesSnapshotTests(unittest.TestCase):
    """_stage_amplify must call write_seed_tasks_json after both LLM
    passes succeed, and skip it if either pass fails."""

    def _setup(self, tmp: str):
        workspace = Path(tmp)
        (workspace / "src" / "gym_anything").mkdir(parents=True)
        env_folder = (workspace / "benchmarks" / "cua_world" /
                      "environments" / "demo_env")
        (env_folder / "tasks").mkdir(parents=True)
        return workspace, env_folder

    def _args(self, workspace: Path):
        args = pa.build_parser().parse_args([
            "--software", "Demo", "--env-dir", "demo_env",
            "--workspace", str(workspace),
        ])
        args.workspace_resolved = str(workspace)
        return args

    def test_snapshot_called_when_both_passes_succeed(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, env_folder = self._setup(tmp)
            output_dir = workspace / "task_generation_runs" / "demo_env"
            output_dir.mkdir(parents=True)
            args = self._args(workspace)

            with mock.patch.object(pa, "_run_subprocess", return_value=0), \
                 mock.patch.object(pa, "write_seed_tasks_json") as snap:
                rc = pa._stage_amplify(args, env_folder, output_dir)

            self.assertEqual(rc, 0)
            snap.assert_called_once()
            (called_env, called_pkl) = snap.call_args.args
            self.assertEqual(called_env, env_folder)

    def test_snapshot_not_called_if_readme_pass_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, env_folder = self._setup(tmp)
            output_dir = workspace / "task_generation_runs" / "demo_env"
            output_dir.mkdir(parents=True)
            args = self._args(workspace)

            with mock.patch.object(pa, "_run_subprocess", return_value=2), \
                 mock.patch.object(pa, "write_seed_tasks_json") as snap:
                rc = pa._stage_amplify(args, env_folder, output_dir)

            self.assertEqual(rc, 2)
            snap.assert_not_called()

    def test_snapshot_not_called_if_files_pass_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, env_folder = self._setup(tmp)
            output_dir = workspace / "task_generation_runs" / "demo_env"
            output_dir.mkdir(parents=True)
            args = self._args(workspace)

            # First call (README pass) → 0; second (files pass) → 5.
            with mock.patch.object(pa, "_run_subprocess",
                                   side_effect=[0, 5]) as run, \
                 mock.patch.object(pa, "write_seed_tasks_json") as snap:
                rc = pa._stage_amplify(args, env_folder, output_dir)

            self.assertEqual(rc, 5)
            self.assertEqual(run.call_count, 2)
            snap.assert_not_called()


class ResolveBinTests(unittest.TestCase):
    def test_explicit_must_exist(self):
        with self.assertRaises(RuntimeError):
            propose_cc._resolve_bin("/no/such/binary", "FAKE", "fake")

    def test_env_var_used(self):
        with tempfile.NamedTemporaryFile(prefix="claude-", delete=False) as fh:
            fake = Path(fh.name)
        try:
            with mock.patch.dict(os.environ, {"CLAUDE_BIN": str(fake)}):
                self.assertEqual(
                    propose_cc._resolve_bin(None, "CLAUDE_BIN", "claude"), fake
                )
        finally:
            fake.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
