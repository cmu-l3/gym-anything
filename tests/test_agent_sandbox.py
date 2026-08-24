"""Offline tests for the agent sandbox abstraction: backend selection and
image-recipe rendering. No docker/apptainer daemon required.
"""
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from agents.shared import agent_sandbox
from agents.shared.agent_sandbox import (
    ApptainerSandbox,
    DockerSandbox,
    SandboxSpec,
    select_sandbox,
)


def _spec():
    return SandboxSpec(
        name="claude",
        base_image="node:22-slim",
        install="npm install -g @anthropic-ai/claude-code",
        act_script="#!/usr/bin/env python3\n",
    )


class SelectionTests(unittest.TestCase):
    def test_explicit_override_apptainer(self):
        with mock.patch.dict("os.environ", {"GYM_ANYTHING_AGENT_SANDBOX": "apptainer"}):
            sb = select_sandbox(_spec(), Path("/tmp/x"))
        self.assertIsInstance(sb, ApptainerSandbox)

    def test_explicit_override_docker(self):
        with mock.patch.dict("os.environ", {"GYM_ANYTHING_AGENT_SANDBOX": "docker"}):
            sb = select_sandbox(_spec(), Path("/tmp/x"))
        self.assertIsInstance(sb, DockerSandbox)

    def test_unknown_override_raises(self):
        with mock.patch.dict("os.environ", {"GYM_ANYTHING_AGENT_SANDBOX": "podman"}):
            with self.assertRaises(ValueError):
                select_sandbox(_spec(), Path("/tmp/x"))

    def test_autodetect_prefers_apptainer(self):
        with mock.patch.dict("os.environ", {}, clear=False) as _env, \
             mock.patch.object(agent_sandbox, "_apptainer_available", return_value=True), \
             mock.patch.object(agent_sandbox, "_docker_available", return_value=True):
            import os
            os.environ.pop("GYM_ANYTHING_AGENT_SANDBOX", None)
            sb = select_sandbox(_spec(), Path("/tmp/x"))
        self.assertIsInstance(sb, ApptainerSandbox)

    def test_autodetect_falls_to_docker(self):
        with mock.patch.object(agent_sandbox, "_apptainer_available", return_value=False), \
             mock.patch.object(agent_sandbox, "_docker_available", return_value=True):
            import os
            os.environ.pop("GYM_ANYTHING_AGENT_SANDBOX", None)
            sb = select_sandbox(_spec(), Path("/tmp/x"))
        self.assertIsInstance(sb, DockerSandbox)

    def test_no_backend_refuses_rather_than_no_isolation(self):
        with mock.patch.object(agent_sandbox, "_apptainer_available", return_value=False), \
             mock.patch.object(agent_sandbox, "_docker_available", return_value=False):
            import os
            os.environ.pop("GYM_ANYTHING_AGENT_SANDBOX", None)
            with self.assertRaises(RuntimeError):
                select_sandbox(_spec(), Path("/tmp/x"))


class RenderingTests(unittest.TestCase):
    def test_dockerfile_layers_common_then_cli(self):
        df = DockerSandbox(_spec(), Path("/tmp/x")).dockerfile()
        self.assertIn("FROM node:22-slim", df)
        self.assertIn("apt-get install", df)
        self.assertIn("npm install -g @anthropic-ai/claude-code", df)
        self.assertIn("COPY act /usr/local/bin/act", df)
        self.assertIn("chmod 1777 /gym-agent-private", df)
        # common install must precede the CLI install
        self.assertLess(df.index("apt-get install"), df.index("npm install"))

    def test_apptainer_def_bootstraps_from_docker(self):
        d = ApptainerSandbox(_spec(), Path("/tmp/x")).definition()
        self.assertIn("Bootstrap: docker", d)
        self.assertIn("From: node:22-slim", d)
        self.assertIn("%post", d)
        self.assertIn("npm install -g @anthropic-ai/claude-code", d)
        self.assertIn("act /usr/local/bin/act", d)
        self.assertIn("chmod 1777 /gym-agent-private", d)

    def test_gateway_url_and_bind_differ_by_backend(self):
        apptainer = ApptainerSandbox(_spec(), Path("/tmp/x"))
        docker = DockerSandbox(_spec(), Path("/tmp/x"))
        self.assertEqual(apptainer.gateway_bind_host, "127.0.0.1")
        self.assertEqual(docker.gateway_bind_host, "0.0.0.0")
        self.assertIn("127.0.0.1:8000", apptainer.gateway_url(8000))
        self.assertIn("host.docker.internal:8000", docker.gateway_url(8000))

    def test_spec_digest_stable_and_sensitive(self):
        s1 = _spec()
        s2 = SandboxSpec("claude", "node:22-slim", "npm install -g @anthropic-ai/claude-code", "#!/usr/bin/env python3\n")
        self.assertEqual(s1.digest(), s2.digest())
        s3 = SandboxSpec("claude", "node:22-slim", "npm install -g @openai/codex", "#!/usr/bin/env python3\n")
        self.assertNotEqual(s1.digest(), s3.digest())


class PrivateFileCopyTests(unittest.TestCase):
    def test_docker_copies_file_into_running_container(self):
        sandbox = DockerSandbox(_spec(), Path("/tmp/x"))
        result = mock.Mock(returncode=0, stderr="")
        with tempfile.NamedTemporaryFile() as source, \
             mock.patch.object(agent_sandbox, "_run", return_value=result) as run:
            sandbox.copy_file(Path(source.name), "/tmp/private/auth.json")

        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(
            ["docker", "cp", source.name, f"{sandbox.container_name}:/tmp/private/auth.json"],
            commands,
        )
        self.assertIn(
            ["docker", "exec", sandbox.container_name, "chmod", "600", "/tmp/private/auth.json"],
            commands,
        )

    def test_apptainer_streams_contents_without_host_bind(self):
        sandbox = ApptainerSandbox(_spec(), Path("/tmp/x"))
        completed = mock.Mock(returncode=0, stderr=b"")
        with tempfile.NamedTemporaryFile() as source:
            source.write(b"secret login bytes")
            source.flush()
            with mock.patch.object(agent_sandbox.subprocess, "run", return_value=completed) as run:
                sandbox.copy_file(Path(source.name), "/tmp/private/auth.json")

        args = run.call_args.args[0]
        self.assertEqual(run.call_args.kwargs["input"], b"secret login bytes")
        self.assertIn(f"instance://{sandbox.instance_name}", args)
        self.assertNotIn(source.name, args)
        self.assertIn("chmod 600", args[-1])


class PrivateScratchTests(unittest.TestCase):
    def test_docker_mounts_private_scratch_and_removes_it_on_stop(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = DockerSandbox(_spec(), Path(tmp) / "logs")
            completed = mock.Mock(returncode=0, stderr="")
            with mock.patch.object(agent_sandbox, "_run", return_value=completed) as run:
                sandbox.start(8000, "token", {})
                private_dir = sandbox._private_dir
                self.assertIsNotNone(private_dir)
                self.assertEqual(private_dir.stat().st_mode & 0o777, 0o700)
                start_args = run.call_args_list[-1].args[0]
                self.assertIn(f"{private_dir}:/gym-agent-private", start_args)
                self.assertNotEqual(private_dir, sandbox.logs_dir)
                sandbox.stop()

            self.assertFalse(private_dir.exists())

    def test_apptainer_mounts_private_scratch_and_removes_it_on_stop(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = ApptainerSandbox(_spec(), Path(tmp) / "logs")
            completed = mock.Mock(returncode=0, stderr="")
            with mock.patch.object(agent_sandbox, "_run", return_value=completed) as run:
                sandbox.start(8000, "token", {})
                private_dir = sandbox._private_dir
                self.assertIsNotNone(private_dir)
                self.assertEqual(private_dir.stat().st_mode & 0o777, 0o700)
                start_args = run.call_args_list[-1].args[0]
                self.assertIn(f"{private_dir}:/gym-agent-private", start_args)
                self.assertNotEqual(private_dir, sandbox.logs_dir)
                sandbox.stop()

            self.assertFalse(private_dir.exists())


class ArtifactCopyTests(unittest.TestCase):
    def test_docker_copies_container_directory_to_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / "sessions"
            sandbox = DockerSandbox(_spec(), Path(tmp))
            completed = mock.Mock(returncode=0, stderr="")
            with mock.patch.object(agent_sandbox, "_run", return_value=completed) as run:
                sandbox.copy_directory_from("/private/sessions", destination)

        run.assert_called_once_with(
            [
                "docker", "cp",
                f"{sandbox.container_name}:/private/sessions/.",
                str(destination),
            ],
            timeout=60,
        )

    def test_apptainer_copies_only_to_bound_logs_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs_dir = Path(tmp)
            destination = logs_dir / "codex_home" / "sessions"
            sandbox = ApptainerSandbox(_spec(), logs_dir)
            completed = mock.Mock(returncode=0, stderr="")
            with mock.patch.object(agent_sandbox, "_run", return_value=completed) as run:
                sandbox.copy_directory_from("/private/sessions", destination)

        args = run.call_args.args[0]
        self.assertIn(f"instance://{sandbox.instance_name}", args)
        self.assertIn("/private/sessions/.", args[-1])
        self.assertIn("/logs/codex_home/sessions/", args[-1])

    def test_apptainer_rejects_destination_outside_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = ApptainerSandbox(_spec(), Path(tmp))
            with self.assertRaisesRegex(ValueError, "under the logs directory"):
                sandbox.copy_directory_from("/private/sessions", Path(tmp).parent / "elsewhere")


if __name__ == "__main__":
    unittest.main()
