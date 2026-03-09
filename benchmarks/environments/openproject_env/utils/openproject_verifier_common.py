#!/usr/bin/env python3
"""Shared verifier helpers for OpenProject tasks.

These verifiers run inside the VM and validate state by querying the running
OpenProject instance inside the Docker container via a Rails runner. This avoids
depending on UI/VLM evaluation and keeps verification deterministic.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass


SEED_RESULT_FILE = os.environ.get("OPENPROJECT_SEED_RESULT_FILE", "/tmp/openproject_seed_result.json")
CONTAINER_NAME = os.environ.get("OPENPROJECT_CONTAINER_NAME", "openproject")
VERIFY_PREFIX = "__GA_VERIFY__"


class VerificationError(RuntimeError):
    pass


def _norm(s: str | None) -> str:
    if s is None:
        return ""
    return re.sub(r"\s+", " ", str(s).strip()).casefold()


def load_seed_result(path: str = SEED_RESULT_FILE) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError as e:
        raise VerificationError(f"Seed result file not found: {path}") from e
    except json.JSONDecodeError as e:
        raise VerificationError(f"Seed result file is not valid JSON: {path}") from e


def local_work_package_id_from_source(seed: dict, source_id: int | str) -> int:
    sid = str(source_id)
    for wp in seed.get("work_packages", []):
        if str(wp.get("source_id")) == sid:
            try:
                return int(wp.get("local_id"))
            except (TypeError, ValueError):
                break
    raise VerificationError(f"Could not map source_id={source_id} to local work package id from {SEED_RESULT_FILE}")


@dataclass(frozen=True)
class WorkPackageSnapshot:
    local_id: int
    subject: str
    status: str
    assignee: str
    notes: list[str]


def _run(cmd: list[str], timeout_sec: int) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_sec)
    except FileNotFoundError as e:
        raise VerificationError(f"Command not found: {cmd[0]}") from e
    except subprocess.TimeoutExpired as e:
        raise VerificationError(f"Command timed out after {timeout_sec}s: {' '.join(cmd)}") from e


def run_rails_runner(ruby_code: str, timeout_sec: int = 240) -> str:
    # Keep the Ruby snippet single-quoted in bash to reduce escaping issues.
    candidates = [
        f"cd /app && bin/rails runner -e production '{ruby_code}'",
        f"cd /app && bundle exec rails runner -e production '{ruby_code}'",
    ]

    last = None
    for cmd in candidates:
        p = _run(["docker", "exec", CONTAINER_NAME, "bash", "-lc", cmd], timeout_sec=timeout_sec)
        last = p
        if p.returncode == 0:
            return (p.stdout or "") + "\n" + (p.stderr or "")

    stdout = (last.stdout or "").strip() if last else ""
    stderr = (last.stderr or "").strip() if last else ""
    raise VerificationError(
        "Failed to run Rails runner in container.\n"
        f"Container: {CONTAINER_NAME}\n"
        f"Last stdout (tail):\n{stdout[-800:]}\n"
        f"Last stderr (tail):\n{stderr[-800:]}\n"
    )


def _extract_verify_json(output: str) -> dict:
    for line in output.splitlines():
        if VERIFY_PREFIX in line:
            payload = line.split(VERIFY_PREFIX, 1)[1].strip()
            try:
                return json.loads(payload)
            except json.JSONDecodeError as e:
                raise VerificationError(f"Verifier JSON parse failed for payload: {payload!r}") from e
    raise VerificationError(f"Did not find verifier prefix {VERIFY_PREFIX!r} in Rails output.")


def get_work_package_snapshot(local_id: int) -> WorkPackageSnapshot:
    # Avoid single-quotes inside this Ruby snippet; it is embedded in a single-quoted bash string.
    ruby = (
        'require "json"; '
        f"wp = WorkPackage.find({int(local_id)}); "
        "assignee_obj = if wp.respond_to?(:assignee) then wp.assignee elsif wp.respond_to?(:assigned_to) then wp.assigned_to else nil end; "
        "status_obj = wp.respond_to?(:status) ? wp.status : nil; "
        "journals = wp.respond_to?(:journals) ? wp.journals : []; "
        "notes = journals.map { |j| j.respond_to?(:notes) ? j.notes.to_s.strip : \"\" }.reject { |n| n.empty? }; "
        "out = {"
        "subject: (wp.respond_to?(:subject) ? wp.subject : nil), "
        "status: (status_obj && status_obj.respond_to?(:name) ? status_obj.name : nil), "
        "assignee: (assignee_obj && assignee_obj.respond_to?(:name) ? assignee_obj.name : nil), "
        "notes: notes"
        "}; "
        f'puts "{VERIFY_PREFIX}" + JSON.generate(out)'
    )

    output = run_rails_runner(ruby)
    data = _extract_verify_json(output)

    return WorkPackageSnapshot(
        local_id=int(local_id),
        subject=str(data.get("subject") or ""),
        status=str(data.get("status") or ""),
        assignee=str(data.get("assignee") or ""),
        notes=[str(x) for x in (data.get("notes") or [])],
    )


def verify_status_and_assignee(
    *,
    source_work_package_id: int | str,
    expected_subject: str,
    expected_status: str,
    expected_assignee: str,
) -> dict:
    seed = load_seed_result()
    local_id = local_work_package_id_from_source(seed, source_work_package_id)
    snap = get_work_package_snapshot(local_id)

    problems: list[str] = []

    if _norm(snap.subject) != _norm(expected_subject):
        problems.append(f"Subject mismatch: expected={expected_subject!r} actual={snap.subject!r}")

    if _norm(snap.status) != _norm(expected_status):
        problems.append(f"Status mismatch: expected={expected_status!r} actual={snap.status!r}")

    if _norm(snap.assignee) != _norm(expected_assignee):
        problems.append(f"Assignee mismatch: expected={expected_assignee!r} actual={snap.assignee!r}")

    if problems:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification failed:\n- " + "\n- ".join(problems),
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": f"Verified work package {local_id}: subject/status/assignee match expected values.",
    }


def verify_comment_present(
    *,
    source_work_package_id: int | str,
    expected_subject: str,
    expected_comment: str,
) -> dict:
    seed = load_seed_result()
    local_id = local_work_package_id_from_source(seed, source_work_package_id)
    snap = get_work_package_snapshot(local_id)

    problems: list[str] = []

    if _norm(snap.subject) != _norm(expected_subject):
        problems.append(f"Subject mismatch: expected={expected_subject!r} actual={snap.subject!r}")

    expected_norm = _norm(expected_comment)
    notes_norm = [_norm(n) for n in snap.notes]
    if expected_norm not in notes_norm:
        problems.append(
            "Expected comment not found in notes/journals.\n"
            f"Expected: {expected_comment!r}\n"
            "Actual notes (normalized, last 10):\n"
            + "\n".join(f"- {n!r}" for n in notes_norm[-10:])
        )

    if problems:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification failed:\n- " + "\n- ".join(problems),
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": f"Verified work package {local_id}: expected comment present and subject unchanged.",
    }
