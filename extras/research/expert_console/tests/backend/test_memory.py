"""Tests for the memory + memory_diff services."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.services.memory import (
    FeedbackTarget,
    MemoryError,
    MemoryService,
    MemoryTier,
)
from extras.research.expert_console.server.services.memory_diff import (
    EnvDiffService,
    MemoryDiffError,
    MemoryDiffService,
    _parse_unified_diff,
)


# ----------------------------------------------------------------------
# MemoryService — listing
# ----------------------------------------------------------------------


def test_list_memory_includes_both_pipelines(test_settings: Settings) -> None:
    svc = MemoryService(test_settings)
    listing = svc.list_memory()
    pipelines = {m.pipeline for m in listing.general}
    assert pipelines == {"creation_audit", "propose_and_amplify"}
    # The new expert_feedback files are in there.
    names = {m.name for m in listing.general}
    assert "expert_feedback.md" in names
    assert "audit_expert_feedback.md" in names


def test_list_memory_marks_expert_feedback(test_settings: Settings) -> None:
    svc = MemoryService(test_settings)
    listing = svc.list_memory()
    for m in listing.general:
        if m.name in ("expert_feedback.md", "audit_expert_feedback.md"):
            assert m.is_expert_feedback


def test_list_memory_env_filter(test_settings: Settings) -> None:
    """openemr_notes.md is recognized as env-specific to openemr_env."""
    svc = MemoryService(test_settings)
    listing = svc.list_memory("openemr_env")
    assert listing.specific, (
        "expected at least one openemr-scoped memory file"
    )
    for m in listing.specific:
        assert m.env_dir == "openemr_env"


def test_list_memory_picks_up_specific_env_notes_subdir(
    test_settings: Settings,
) -> None:
    """Files under .../specific_env_notes/<env_dir>/ must be classified
    as env-specific for that env, even though their file *name* (e.g.
    notes.md) doesn't include the env name. Previously the matcher
    only inspected file names and missed these entirely.
    """
    svc = MemoryService(test_settings)
    listing = svc.list_memory("odoo_hr_env")
    rel_paths = [m.rel_path for m in listing.specific]
    assert any(
        "specific_env_notes/odoo_hr_env" in p for p in rel_paths
    ), f"expected odoo_hr_env-scoped shard in {rel_paths}"


def test_read_file_within_memory(test_settings: Settings) -> None:
    svc = MemoryService(test_settings)
    text = svc.read_file(
        "extras/research/software_as_env/creation_audit/memory/audit_prompt.md"
    )
    assert "checklist" in text.lower()


def test_read_file_path_traversal_blocked(test_settings: Settings) -> None:
    svc = MemoryService(test_settings)
    with pytest.raises(MemoryError):
        svc.read_file("../../etc/passwd")


def test_read_file_outside_memory_roots(test_settings: Settings) -> None:
    """Files inside the repo but outside memory roots are rejected."""
    svc = MemoryService(test_settings)
    with pytest.raises(MemoryError):
        svc.read_file("README.md")


# ----------------------------------------------------------------------
# MemoryService — append
# ----------------------------------------------------------------------


def _isolated_settings(test_settings: Settings, tmp_path: Path) -> Settings:
    """Copy the memory tree to a tmp dir so append tests don't mutate
    the real repo files.
    """
    import shutil

    # Mirror just the memory dirs we care about so config validators pass.
    repo_root = test_settings.repo_root
    sandbox = tmp_path / "repo"
    sandbox.mkdir()
    (sandbox / "src" / "gym_anything").mkdir(parents=True)
    (sandbox / "src" / "gym_anything" / "__init__.py").write_text("")
    (sandbox / "benchmarks" / "cua_world" / "environments").mkdir(parents=True)
    shutil.copytree(
        repo_root / "extras" / "research" / "software_as_env",
        sandbox / "extras" / "research" / "software_as_env",
    )
    shutil.copytree(
        repo_root / "extras" / "research" / "task_generation",
        sandbox / "extras" / "research" / "task_generation",
    )
    state_dir = tmp_path / "isolated-state"
    state_dir.mkdir(parents=True, exist_ok=True)
    return Settings(
        repo_root=sandbox,
        state_dir=state_dir,
        db_path=state_dir / "test.sqlite3",
        artifacts_dir=state_dir / "runs",
        claude_bin=test_settings.claude_bin,
    )


def test_append_creator_global_header(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    svc = MemoryService(sandboxed)
    record = svc.append_expert_entry(
        target=FeedbackTarget.CREATOR,
        memory_tier=MemoryTier.GENERAL,
        env_dir=None,
        task_id=None,
        body="Always pull real public data — synthetic seeded inline is FAIL.",
        suggest_checklist_change=False,
    )
    assert record.rel_path.endswith("env_creation_notes/expert_feedback.md")
    text = sandboxed.expert_feedback_creation_path.read_text(encoding="utf-8")
    # New header format: no env picked -> "GLOBAL".
    assert "— GLOBAL\n" in text
    # Task name is NEVER auto-injected.
    assert "— None" not in text
    assert "FAIL" in text


def test_append_specific_header_shows_env(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    svc = MemoryService(sandboxed)
    svc.append_expert_entry(
        target=FeedbackTarget.AUDIT,
        memory_tier=MemoryTier.SPECIFIC,
        env_dir="odoo_hr_env",
        task_id=None,
        body="If `install.sh` calls `--load=demo` for the HR module, FAIL.",
        suggest_checklist_change=True,
    )
    text = sandboxed.expert_feedback_audit_path.read_text(encoding="utf-8")
    assert "— odoo_hr_env\n" in text
    assert "global" not in text.split("## ")[-1].split("\n")[0]
    assert "Proposed checklist change" in text


def test_append_general_with_env_marks_global(test_settings, tmp_path) -> None:
    """Env picked but scope=general: header shows env + 'global' marker."""
    sandboxed = _isolated_settings(test_settings, tmp_path)
    svc = MemoryService(sandboxed)
    svc.append_expert_entry(
        target=FeedbackTarget.PROPOSER,
        memory_tier=MemoryTier.GENERAL,
        env_dir="moodle_env",
        task_id="enroll_student",
        body="Replace one-student enrollment with bulk CSV upload.",
        suggest_checklist_change=False,
    )
    text = sandboxed.expert_feedback_propose_path.read_text(encoding="utf-8")
    # Env name IS in the header even when scope is general.
    assert "— moodle_env — global" in text
    # Task name is NOT in the header (it's in the message body or nowhere).
    last_header = text.strip().split("\n## ")[-1].split("\n")[0]
    assert "enroll_student" not in last_header
    assert "bulk CSV upload" in text


def test_append_specific_requires_env_dir(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    svc = MemoryService(sandboxed)
    with pytest.raises(MemoryError):
        svc.append_expert_entry(
            target=FeedbackTarget.CREATOR,
            memory_tier=MemoryTier.SPECIFIC,
            env_dir=None,
            task_id=None,
            body="y",
            suggest_checklist_change=False,
        )


def test_append_rejects_empty_body(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    svc = MemoryService(sandboxed)
    with pytest.raises(MemoryError):
        svc.append_expert_entry(
            target=FeedbackTarget.CREATOR,
            memory_tier=MemoryTier.GENERAL,
            env_dir=None,
            task_id=None,
            body="",
            suggest_checklist_change=False,
        )


# ----------------------------------------------------------------------
# Unified diff parser
# ----------------------------------------------------------------------


def test_parse_unified_diff_simple() -> None:
    text = (
        "diff --git a/extras/foo.md b/extras/foo.md\n"
        "index abc..def 100644\n"
        "--- a/extras/foo.md\n"
        "+++ b/extras/foo.md\n"
        "@@ -1,3 +1,4 @@\n"
        " line one\n"
        "+new line\n"
        " line two\n"
        "-line three\n"
        " line four\n"
    )
    files = _parse_unified_diff(text)
    assert len(files) == 1
    f = files[0]
    assert f.rel_path == "extras/foo.md"
    assert f.additions == 1
    assert f.deletions == 1
    assert len(f.hunks) == 1
    assert f.hunks[0].header.startswith("@@")


# ----------------------------------------------------------------------
# MemoryDiffService — run against a real git repo
# ----------------------------------------------------------------------


def _init_git_repo(root: Path) -> None:
    """Create a minimal repo inside `root` so git diff works."""
    subprocess.run(["git", "init", "-q"], cwd=str(root), check=True)
    subprocess.run(
        ["git", "config", "user.email", "test@example.com"],
        cwd=str(root),
        check=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Test"], cwd=str(root), check=True
    )
    subprocess.run(["git", "add", "-A"], cwd=str(root), check=True)
    subprocess.run(
        ["git", "commit", "-q", "-m", "init"], cwd=str(root), check=True
    )


def test_memory_diff_sees_appended_entry(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git_repo(sandboxed.repo_root)
    mem = MemoryService(sandboxed)
    mem.append_expert_entry(
        target=FeedbackTarget.CREATOR,
        memory_tier=MemoryTier.GENERAL,
        env_dir=None,
        task_id=None,
        body="Always pull real public data.",
        suggest_checklist_change=False,
    )
    diff = MemoryDiffService(sandboxed).get_diff()
    assert diff.total_additions > 0
    paths = [f.rel_path for f in diff.files]
    assert any("expert_feedback.md" in p for p in paths)


def test_memory_diff_filters_by_env(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git_repo(sandboxed.repo_root)
    mem = MemoryService(sandboxed)
    mem.append_expert_entry(
        target=FeedbackTarget.AUDIT,
        memory_tier=MemoryTier.SPECIFIC,
        env_dir="odoo_hr_env",
        task_id=None,
        body="FAIL on --load=demo",
        suggest_checklist_change=True,
    )
    diff = MemoryDiffService(sandboxed).get_diff("odoo_hr_env")
    assert diff.files, "expected at least one diff entry"


def test_memory_diff_handles_untracked_files(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git_repo(sandboxed.repo_root)
    new_path = (
        sandboxed.creation_audit_memory_dir
        / "specific_env_notes"
        / "newenv_env.md"
    )
    new_path.parent.mkdir(parents=True, exist_ok=True)
    new_path.write_text("# notes about newenv_env\n\nrealistic data required.\n")
    diff = MemoryDiffService(sandboxed).get_diff()
    rel_paths = [f.rel_path for f in diff.files]
    assert any("newenv_env" in p for p in rel_paths)


# ----------------------------------------------------------------------
# EnvDiffService — scoped to one env folder + its audit report
# ----------------------------------------------------------------------


def _seed_env_in_sandbox(sandboxed: Settings, env_name: str) -> Path:
    """Create a fake env folder with a few files so EnvDiffService has
    something tracked to diff against.
    """
    env_root = sandboxed.environments_dir / env_name
    env_root.mkdir(parents=True, exist_ok=True)
    (env_root / "env.json").write_text(
        '{"id": "' + env_name + '@0.1", "version": "0.1"}\n',
        encoding="utf-8",
    )
    (env_root / "tasks").mkdir(exist_ok=True)
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text(
        "#!/bin/bash\necho install\n", encoding="utf-8"
    )
    return env_root


def test_env_diff_sees_modified_task_files(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    env_root = _seed_env_in_sandbox(sandboxed, "moodle_env")
    _init_git_repo(sandboxed.repo_root)
    # Modify a script after the initial commit.
    (env_root / "scripts" / "install.sh").write_text(
        "#!/bin/bash\necho install MODIFIED\n", encoding="utf-8"
    )
    # And add a new task folder.
    new_task = env_root / "tasks" / "import_real_employees"
    new_task.mkdir()
    (new_task / "task.json").write_text(
        '{"id":"import_real_employees@1","description":"Use real data"}\n',
        encoding="utf-8",
    )
    diff = EnvDiffService(sandboxed).get_diff("moodle_env")
    rel_paths = [f.rel_path for f in diff.files]
    assert any("install.sh" in p for p in rel_paths)
    assert any("import_real_employees" in p for p in rel_paths)
    assert diff.total_additions > 0


def test_env_diff_includes_audit_report(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _seed_env_in_sandbox(sandboxed, "moodle_env")
    sandboxed.audits_dir.mkdir(parents=True, exist_ok=True)
    _init_git_repo(sandboxed.repo_root)
    audit_file = sandboxed.audits_dir / "audit_moodle_env.md"
    audit_file.write_text("# Audit moodle_env\n\nFAIL: demo data.\n", encoding="utf-8")
    diff = EnvDiffService(sandboxed).get_diff("moodle_env")
    rel_paths = [f.rel_path for f in diff.files]
    assert any("audit_moodle_env.md" in p for p in rel_paths)


def test_env_diff_rejects_unknown_env(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git_repo(sandboxed.repo_root)
    with pytest.raises(MemoryDiffError):
        EnvDiffService(sandboxed).get_diff("nonexistent_env")


def test_env_diff_rejects_empty(test_settings, tmp_path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    with pytest.raises(MemoryDiffError):
        EnvDiffService(sandboxed).get_diff("")


# ----------------------------------------------------------------------
# API
# ----------------------------------------------------------------------


def test_api_list_memory(app_client) -> None:
    response = app_client.get("/api/memory")
    assert response.status_code == 200, response.text
    data = response.json()
    assert "general" in data and isinstance(data["general"], list)
    assert any(m["name"] == "expert_feedback.md" for m in data["general"])


def test_api_read_memory_file(app_client) -> None:
    response = app_client.get(
        "/api/memory/file",
        params={
            "rel_path": "extras/research/software_as_env/creation_audit/memory/audit_prompt.md"
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "checklist" in data["text"].lower()


def test_api_diff_runs(app_client) -> None:
    response = app_client.get("/api/memory/diff")
    # In the live repo we may or may not have memory diffs pending —
    # the endpoint must succeed either way.
    assert response.status_code == 200, response.text
    data = response.json()
    assert "files" in data and isinstance(data["files"], list)


def test_api_env_diff_runs(app_client) -> None:
    response = app_client.get(
        "/api/memory/diff/env",
        params={"env_dir": "moodle_env"},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "files" in data and isinstance(data["files"], list)


def test_api_env_diff_unknown_env_404(app_client) -> None:
    response = app_client.get(
        "/api/memory/diff/env",
        params={"env_dir": "definitely_not_an_env"},
    )
    assert response.status_code == 404
