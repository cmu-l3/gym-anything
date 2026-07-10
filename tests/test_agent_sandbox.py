"""Offline tests for the agent sandbox abstraction: backend selection and
image-recipe rendering. No docker/apptainer daemon required.
"""
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
        # common install must precede the CLI install
        self.assertLess(df.index("apt-get install"), df.index("npm install"))

    def test_apptainer_def_bootstraps_from_docker(self):
        d = ApptainerSandbox(_spec(), Path("/tmp/x")).definition()
        self.assertIn("Bootstrap: docker", d)
        self.assertIn("From: node:22-slim", d)
        self.assertIn("%post", d)
        self.assertIn("npm install -g @anthropic-ai/claude-code", d)
        self.assertIn("act /usr/local/bin/act", d)

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


if __name__ == "__main__":
    unittest.main()
