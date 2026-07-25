from __future__ import annotations

import io
import struct
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.specs import EnvSpec
from gym_anything.env import GymAnythingEnv
from gym_anything.config.validators import validate_env_spec
from gym_anything.runtime.runners.modal_native import ModalNativeRunner, VNC_PORT
from gym_anything.runtime.runners import modal_native_fast_io as fast_io
from gym_anything.runtime.runners.modal_native_fast_io import (
    FAST_IO_PORT,
    ModalNativeFastIOClient,
    events_for_action,
)
from gym_anything.runtime.runners.modal_native_image import MODAL_NATIVE_IMAGE_FINGERPRINT
from gym_anything.runtime.runners.vnc_utils import VNCConnection


class _FakeStream:
    def __init__(self, value=""):
        self.value = value

    def read(self):
        return self.value


class _FakeStdin:
    def __init__(self):
        self.data = bytearray()
        self.eof = False

    def write(self, data):
        self.data.extend(data.encode() if isinstance(data, str) else data)

    def drain(self):
        return None

    def write_eof(self):
        self.eof = True


class _FakeProcess:
    def __init__(self, code=0, stdout="", stderr=""):
        self.code = code
        self.stdout = _FakeStream(stdout)
        self.stderr = _FakeStream(stderr)
        self.stdin = _FakeStdin()

    def wait(self):
        return self.code


class _FakeRemoteFile:
    def __init__(self, sandbox, path, mode):
        self.sandbox = sandbox
        self.path = path
        self.mode = mode
        self.buffer = io.BytesIO(sandbox.files.get(path, b"") if "r" in mode else b"")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        if exc_type is None and "w" in self.mode:
            self.sandbox.files[self.path] = self.buffer.getvalue()

    def read(self, size=None):
        return self.buffer.read(-1 if size is None else size)

    def write(self, data):
        return self.buffer.write(data)

    def flush(self):
        return None


class _FakeDict:
    def __init__(self):
        self.data = {}

    def get(self, key, default=None):
        return self.data.get(key, default)

    def put(self, key, value, skip_if_exists=False):
        if skip_if_exists and key in self.data:
            return False
        self.data[key] = value
        return True

    def pop(self, key, default=None):
        return self.data.pop(key, default)


class _FakeImage:
    from_id_calls = []

    def __init__(self, object_id="im-base"):
        self.object_id = object_id

    @classmethod
    def from_id(cls, image_id):
        cls.from_id_calls.append(image_id)
        return cls(image_id)


class _FakeTunnel:
    tcp_socket = ("modal-vnc.example", 43210)


class _FakeFastIOTunnel:
    tls_socket = ("modal-fast-io.example", 443)


class _FakeSandbox:
    create_calls = []

    def __init__(self):
        self.object_id = "sb-test"
        self.exec_calls = []
        self.terminated = False
        self.snapshot_calls = []
        self.next_process = None
        self.files = {}
        self.directories = set()

    @classmethod
    def create(cls, *args, **kwargs):
        sandbox = cls()
        cls.create_calls.append((args, kwargs, sandbox))
        return sandbox

    def tunnels(self):
        return {
            VNC_PORT: _FakeTunnel(),
            FAST_IO_PORT: _FakeFastIOTunnel(),
        }

    def exec(self, *args, **kwargs):
        self.exec_calls.append((args, kwargs))
        if self.next_process is not None:
            process, self.next_process = self.next_process, None
            return process
        return _FakeProcess()

    def terminate(self):
        self.terminated = True

    def snapshot_filesystem(self, **kwargs):
        self.snapshot_calls.append(kwargs)
        return _FakeImage("im-snapshot")

    def mkdir(self, path, parents=False):
        self.directories.add((path, parents))

    @property
    def filesystem(self):
        return self

    def make_directory(self, path, create_parents=True):
        self.directories.add((path, create_parents))

    def copy_from_local(self, local_path, remote_path):
        self.files[remote_path] = Path(local_path).read_bytes()

    def copy_to_local(self, remote_path, local_path):
        Path(local_path).write_bytes(self.files[remote_path])

    def remove(self, path, recursive=False):
        self.files.pop(path, None)

    def open(self, path, mode="r"):
        return _FakeRemoteFile(self, path, mode)

    def rm(self, path, recursive=False):
        self.files.pop(path, None)


class _FakeApp:
    lookup_calls = []

    @classmethod
    def lookup(cls, name, create_if_missing=False):
        cls.lookup_calls.append((name, create_if_missing))
        return object()


class _FakeDictType:
    instance = _FakeDict()

    @classmethod
    def from_name(cls, name, create_if_missing=False):
        return cls.instance


def _fake_modal(version="1.5.2"):
    return types.SimpleNamespace(
        __version__=version,
        App=_FakeApp,
        Dict=_FakeDictType,
        Image=_FakeImage,
        Sandbox=_FakeSandbox,
    )


def _spec(**overrides) -> EnvSpec:
    data = {
        "id": "tests.modal-native@1",
        "runner": "modal_native",
        "os_type": "linux",
        "resources": {"cpu": 2, "mem_gb": 4, "gpu": 0, "net": True},
        "observation": [
            {"type": "rgb_screen", "fps": 2, "resolution": [1280, 720]}
        ],
        "action": [{"type": "mouse"}, {"type": "keyboard"}],
        "vnc": {"enable": True, "password": "secret"},
    }
    data.update(overrides)
    spec = EnvSpec.from_dict(data)
    spec.security.resolved_env = {"FROM_SPEC": "yes"}
    return spec


class ModalNativeRunnerTests(unittest.TestCase):
    def test_config_validator_accepts_modal_native_runner(self):
        validate_env_spec(_spec())

    def setUp(self):
        _FakeSandbox.create_calls = []
        _FakeImage.from_id_calls = []
        _FakeApp.lookup_calls = []
        _FakeDictType.instance = _FakeDict()
        self.modal = _fake_modal()
        self.modal_patch = mock.patch.dict(sys.modules, {"modal": self.modal})
        self.modal_patch.start()

    def tearDown(self):
        self.modal_patch.stop()

    def test_rejects_non_linux_and_gpu_specs_before_creating_resources(self):
        with self.assertRaisesRegex(ValueError, "Linux environments only"):
            ModalNativeRunner(_spec(os_type="windows"))
        with self.assertRaisesRegex(ValueError, "does not support GPU"):
            ModalNativeRunner(
                _spec(resources={"cpu": 2, "mem_gb": 4, "gpu": 1, "net": True})
            )
        self.assertEqual(_FakeApp.lookup_calls, [])

    def test_requires_filesystem_capable_modal_sdk(self):
        with mock.patch.dict(sys.modules, {"modal": _fake_modal("1.3.9")}):
            with self.assertRaisesRegex(RuntimeError, "modal>=1.4"):
                ModalNativeRunner(_spec())

    def test_core_runner_dispatch_uses_modal_native_key(self):
        env = GymAnythingEnv.__new__(GymAnythingEnv)
        sentinel = object()
        with mock.patch(
            "gym_anything.runtime.runners.modal_native.ModalNativeRunner",
            return_value=sentinel,
        ) as runner_class:
            selected = env._runner_for_key("modal_native", _spec())
        self.assertIs(selected, sentinel)
        runner_class.assert_called_once()

    def test_start_maps_resources_network_resolution_and_runtime_info(self):
        spec = _spec(resources={"cpu": 3, "mem_gb": 6, "gpu": 0, "net": False})
        runner = ModalNativeRunner(spec)
        with mock.patch(
            "gym_anything.runtime.runners.modal_native.build_modal_native_image",
            return_value=_FakeImage(),
        ), mock.patch.object(runner, "_wait_for_desktop"), mock.patch.object(
            runner, "_setup_mounts"
        ), mock.patch.object(runner, "_connect_vnc"):
            runner.start(seed=7)

        args, kwargs, sandbox = _FakeSandbox.create_calls[-1]
        self.assertEqual(args, ("/usr/local/sbin/ga-modal-native-bootstrap",))
        self.assertEqual(kwargs["cpu"], (3.0, 3.0))
        self.assertEqual(kwargs["memory"], (6144, 6144))
        self.assertEqual(kwargs["unencrypted_ports"], [5901])
        self.assertEqual(kwargs["experimental_options"], {"vm_runtime": True})
        self.assertEqual(kwargs["outbound_cidr_allowlist"], [])
        self.assertEqual(kwargs["outbound_domain_allowlist"], [])
        self.assertEqual(kwargs["env"]["GYM_ANYTHING_VNC_GEOMETRY"], "1280x720")

        info = runner.get_runtime_info()
        self.assertEqual(info.platform_family, "linux")
        self.assertEqual(info.instance_name, "sb-test")
        self.assertEqual(info.vnc_port, 43210)
        self.assertEqual(info.vnc_url, "vnc://modal-vnc.example:43210")
        runner.stop()
        self.assertTrue(sandbox.terminated)

    def test_fast_start_exposes_tls_service_and_connects_native_client(self):
        runner = ModalNativeRunner(_spec())
        runner.set_fast_io(True)
        client = mock.Mock()
        with mock.patch(
            "gym_anything.runtime.runners.modal_native.build_modal_native_image",
            return_value=_FakeImage(),
        ), mock.patch.object(runner, "_wait_for_desktop"), mock.patch.object(
            runner, "_setup_mounts"
        ), mock.patch.object(runner, "_connect_vnc"), mock.patch(
            "gym_anything.runtime.runners.modal_native.ModalNativeFastIOClient",
            return_value=client,
        ) as client_class:
            runner.start()

        _, kwargs, sandbox = _FakeSandbox.create_calls[-1]
        self.assertEqual(kwargs["cpu"], (4.0, 4.0))
        self.assertEqual(kwargs["encrypted_ports"], [FAST_IO_PORT])
        self.assertEqual(
            kwargs["env"]["GYM_ANYTHING_FAST_IO_TOKEN"], runner._fast_io_token
        )
        client_class.assert_called_once_with(
            "modal-fast-io.example",
            443,
            runner._fast_io_token,
            (1280, 720),
            timeout=30.0,
        )
        client.connect.assert_called_once_with(retry_count=30, retry_delay=1.0)
        service_command = sandbox.exec_calls[-1][0][-1]
        self.assertEqual(service_command, "systemctl restart ga-fast-io.service")
        runner.stop()
        client.close.assert_called_once()

    def test_start_cleans_up_sandbox_when_interrupted(self):
        runner = ModalNativeRunner(_spec())
        with mock.patch(
            "gym_anything.runtime.runners.modal_native.build_modal_native_image",
            return_value=_FakeImage(),
        ), mock.patch.object(
            runner, "_wait_for_desktop", side_effect=KeyboardInterrupt
        ):
            with self.assertRaises(KeyboardInterrupt):
                runner.start()
        self.assertTrue(_FakeSandbox.create_calls[-1][2].terminated)

    def test_desktop_probe_has_an_in_guest_timeout(self):
        runner = ModalNativeRunner(_spec())
        runner._sandbox = _FakeSandbox()
        runner._sandbox.next_process = _FakeProcess(stdout="active\n")
        runner._wait_for_desktop()
        args, kwargs = runner._sandbox.exec_calls[-1]
        self.assertIn("timeout --signal=TERM --kill-after=1s 5s", args[-1])
        self.assertEqual(kwargs["timeout"], 10)

    def test_systemd_init_masks_acpid_activation_loop(self):
        asset = (
            Path(__file__).parents[1]
            / "src/gym_anything/runtime/runners/modal_native_assets/systemd_init.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("/etc/systemd/system/acpid.path", asset)
        self.assertIn("/etc/systemd/system/acpid.service", asset)
        self.assertIn("/etc/systemd/system/acpid.socket", asset)
        self.assertIn("mount -t tmpfs", asset)
        self.assertIn("tmpfs /run", asset)

    def test_desktop_allows_local_guest_applications_to_use_x11(self):
        asset = (
            Path(__file__).parents[1]
            / "src/gym_anything/runtime/runners/modal_native_assets/xstartup"
        ).read_text(encoding="utf-8")
        self.assertIn("xhost +local:", asset)

    def test_base_completes_snap_transitions_without_application_installers(self):
        assets = Path(__file__).parents[1] / (
            "src/gym_anything/runtime/runners/modal_native_assets"
        )
        transition = (
            assets / "snap_transitions.sh"
        ).read_text(encoding="utf-8")
        mounts = (assets / "snap_mounts.sh").read_text(encoding="utf-8")
        wrapper = (assets / "snap_wrapper.sh").read_text(encoding="utf-8")
        service = (
            assets / "ga-snap-transitions.service"
        ).read_text(encoding="utf-8")
        vnc_service = (
            assets / "ga-vnc.service"
        ).read_text(encoding="utf-8")
        image_builder = (
            Path(__file__).parents[1]
            / "src/gym_anything/runtime/runners/modal_native_image.py"
        ).read_text(encoding="utf-8")
        self.assertIn("transitional package", transition)
        self.assertIn("apt-get download", transition)
        self.assertIn("dpkg --unpack", transition)
        self.assertIn("pgrep -x snapfuse", mounts)
        self.assertIn("unsquashfs", mounts)
        self.assertIn('mount --bind "$destination" "$target"', mounts)
        self.assertIn("systemctl stop snapd.socket snapd.service", mounts)
        self.assertIn("/usr/bin/snap", wrapper)
        self.assertIn("/usr/local/sbin/ga-snap-mounts", wrapper)
        self.assertIn("After=network-online.target snapd.socket", service)
        self.assertIn("Requires=ga-snap-transitions.service", vnc_service)
        self.assertIn('"snapd"', image_builder)
        self.assertIn("/usr/local/bin/snap", image_builder)
        self.assertNotIn("dpkg-divert", image_builder)
        self.assertNotIn(
            "firefox", transition + mounts + wrapper + service + image_builder
        )
        self.assertIn("ga-fast-io.service", image_builder)
        self.assertIn("libxdamage-dev", image_builder)
        fast_service = (assets / "ga-fast-io.service").read_text(encoding="utf-8")
        fast_server = (assets / "fast_io_server.c").read_text(encoding="utf-8")
        self.assertIn("Requires=ga-vnc.service", fast_service)
        self.assertIn("XShmGetImage", fast_server)
        self.assertIn("XDamageCreate", fast_server)
        self.assertNotIn("XCheckTypedEvent", fast_server)
        self.assertIn("XTestFakeKeyEvent", fast_server)
        self.assertIn("convert_xrgb_ssse3", fast_server)
        self.assertIn("#pragma omp parallel", fast_server)
        self.assertIn("LOCAL_FRAME_PATH", fast_server)
        self.assertIn("frame_cache.next_slot", fast_server)

    def test_exec_enters_systemd_namespace_and_merges_environment(self):
        runner = ModalNativeRunner(_spec())
        runner._sandbox = _FakeSandbox()
        code = runner.exec(
            "printf ok",
            env={"EXTRA": "value"},
            user="ga",
            use_pty=False,
            timeout=17,
        )
        self.assertEqual(code, 0)
        args, kwargs = runner._sandbox.exec_calls[-1]
        self.assertEqual(args[:2], ("/usr/local/sbin/ga-nsenter", "runuser"))
        self.assertIn("ga", args)
        self.assertEqual(args[-3:], ("bash", "-lc", "printf ok"))
        self.assertFalse(kwargs["pty"])
        self.assertEqual(kwargs["timeout"], 17)
        self.assertEqual(kwargs["env"]["FROM_SPEC"], "yes")
        self.assertEqual(kwargs["env"]["EXTRA"], "value")
        self.assertEqual(kwargs["env"]["DISPLAY"], ":1")

    def test_action_mapping_uses_vnc_and_preserves_scroll_convention(self):
        runner = ModalNativeRunner(_spec())
        connection = mock.Mock()
        connection.pointer_position = (40, 50)
        with mock.patch.object(runner, "_vnc_connection", return_value=connection):
            runner.inject_action(
                {
                    "mouse": {
                        "double_click": [1, 2],
                        "triple_click": [7, 8],
                        "right_click_drag": [[3, 4], [5, 6]],
                        "buttons": {"left_down": True, "left_up": True},
                        "scroll": 3,
                    },
                    "keyboard": {
                        "text": "Hi",
                        "keys": ["ctrl", "a"],
                        "keys_down": "shift",
                        "keys_up": "shift",
                    },
                }
            )
        self.assertEqual(
            connection.send_mouse_click.call_args_list,
            [
                mock.call(1, 2, button=1, double=True),
                mock.call(7, 8, button=1),
                mock.call(7, 8, button=1),
                mock.call(7, 8, button=1),
            ],
        )
        connection.send_mouse_drag.assert_called_once_with(3, 4, 5, 6, button=3)
        self.assertEqual(connection.send_mouse_button.call_count, 2)
        connection.send_scroll.assert_called_once_with(40, 50, -3)
        connection.type_text.assert_called_once_with("Hi")
        connection.send_key_combo.assert_called_once_with(["ctrl", "a"])
        self.assertEqual(connection.send_key.call_count, 2)

    def test_fast_action_and_screenshot_bypass_vnc(self):
        from PIL import Image

        runner = ModalNativeRunner(_spec())
        runner.set_fast_io(True)
        client = mock.Mock()
        client.capture_image.return_value = Image.new("RGB", (1280, 720), "red")
        runner._fast_io_client = client
        action = {"keyboard": {"text": "native"}}
        with mock.patch.object(
            runner, "_vnc_connection", side_effect=AssertionError("VNC hot path")
        ):
            runner.inject_action(action)
            image = runner.capture_screenshot_image()
        client.inject_action.assert_called_once_with(action)
        self.assertEqual(image.mode, "RGB")
        self.assertEqual(image.getpixel((0, 0)), (255, 0, 0))

    def test_mount_copy_replaces_target_and_keeps_environment_source_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "scripts"
            source.mkdir()
            (source / "setup.sh").write_text("#!/bin/bash\n", encoding="utf-8")
            spec = _spec(
                mounts=[
                    {"source": str(source), "target": "/workspace/scripts", "mode": "ro"}
                ]
            )
            runner = ModalNativeRunner(spec)
            with mock.patch.object(runner, "exec", return_value=0) as execute, mock.patch.object(
                runner, "copy_to"
            ) as copy_to:
                runner._setup_mounts()
            execute.assert_called_once()
            self.assertIn("rm -rf -- /workspace/scripts", execute.call_args.args[0])
            copy_to.assert_called_once_with(str(source), "/workspace/scripts")
            self.assertEqual(spec.mounts[0].source, str(source))

    def test_file_copy_round_trip_uses_sandbox_filesystem_api(self):
        runner = ModalNativeRunner(_spec())
        runner._sandbox = _FakeSandbox()
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "input.bin"
            source.write_bytes(b"modal-native-data")
            with mock.patch.object(runner, "exec", return_value=0) as execute:
                runner.copy_to(str(source), "/workspace/input.bin")
            self.assertEqual(
                runner._sandbox.files["/workspace/input.bin"], b"modal-native-data"
            )
            self.assertIn("chmod", execute.call_args.args[0])

            destination = Path(tmp) / "output.bin"
            with mock.patch.object(runner, "exec_capture", return_value="file"):
                runner.copy_from("/workspace/input.bin", str(destination))
            self.assertEqual(destination.read_bytes(), b"modal-native-data")

    def test_checkpoint_snapshot_is_published_and_runner_restarts_from_it(self):
        runner = ModalNativeRunner(_spec())
        sandbox = _FakeSandbox()
        runner._sandbox = sandbox
        runner._running = True
        runner._app = object()
        runner._checkpoint_dict = _FakeDictType.instance
        runner.set_checkpoint_key("post_start")
        with mock.patch.object(runner, "exec", return_value=0), mock.patch.object(
            runner, "_restart_from_image"
        ) as restart:
            self.assertTrue(runner.create_checkpoint())

        self.assertEqual(
            sandbox.snapshot_calls,
            [{"timeout": runner.snapshot_timeout, "ttl": None}],
        )
        restart.assert_called_once()
        self.assertEqual(restart.call_args.args[0].object_id, "im-snapshot")
        record = runner._checkpoint_dict.get(runner._checkpoint_key())
        self.assertEqual(record["image_id"], "im-snapshot")
        self.assertEqual(record["cache_level"], "post_start")

    def test_checkpoint_lookup_does_not_create_a_sandbox(self):
        runner = ModalNativeRunner(_spec())
        runner.set_checkpoint_key("pre_start")
        self.assertFalse(runner.checkpoint_exists())
        self.assertEqual(_FakeSandbox.create_calls, [])

        runner._checkpoint_dict.put(
            runner._checkpoint_key(),
            {
                "image_id": "im-existing",
                "image_schema": MODAL_NATIVE_IMAGE_FINGERPRINT,
            },
        )
        with mock.patch.object(runner, "_start_with_image") as start:
            self.assertTrue(runner.start_from_checkpoint(seed=9))
        self.assertEqual(_FakeImage.from_id_calls, ["im-existing"])
        self.assertEqual(start.call_args.kwargs["seed"], 9)

    def test_savevm_is_rejected(self):
        runner = ModalNativeRunner(_spec())
        self.assertFalse(runner.supports_savevm())
        with self.assertRaisesRegex(ValueError, "not use_savevm"):
            runner.set_checkpoint_key("pre_start", use_savevm=True)


class _FragmentedSocket:
    def __init__(self, chunks=None):
        self.chunks = list(chunks or [])
        self.sent = []
        self.closed = False

    def recv(self, size):
        if not self.chunks:
            return b""
        value = self.chunks.pop(0)
        if len(value) > size:
            self.chunks.insert(0, value[size:])
            return value[:size]
        return value

    def recv_into(self, buffer):
        value = self.recv(len(buffer))
        buffer[: len(value)] = value
        return len(value)

    def sendall(self, data):
        self.sent.append(data)

    def settimeout(self, timeout):
        return None

    def connect(self, address):
        return None

    def close(self):
        self.closed = True


class ModalNativeFastIOTests(unittest.TestCase):
    @staticmethod
    def _response(opcode, payload=b"", status=0):
        return (
            fast_io._RESPONSE_HEADER.pack(
                fast_io._MAGIC,
                fast_io._VERSION,
                opcode,
                status,
                len(payload),
            )
            + payload
        )

    def test_action_translation_batches_mouse_text_and_hotkey(self):
        events = events_for_action(
            {
                "mouse": {"left_click": [10, 20], "scroll": 1},
                "keyboard": {"text": "A", "keys": ["ctrl", "a"]},
            }
        )
        self.assertEqual(
            events,
            [
                (1, 0, 0, 10, 20),
                (2, 1, 1, 0, 0),
                (2, 0, 1, 0, 0),
                (2, 1, 5, 0, 0),
                (2, 0, 5, 0, 0),
                (3, 1, 0xFFE1, 0, 0),
                (3, 1, ord("a"), 0, 0),
                (3, 0, ord("a"), 0, 0),
                (3, 0, 0xFFE1, 0, 0),
                (3, 1, 0xFFE3, 0, 0),
                (3, 1, ord("a"), 0, 0),
                (3, 0, ord("a"), 0, 0),
                (3, 0, 0xFFE3, 0, 0),
            ],
        )
        f24_events = events_for_action({"keyboard": {"keys": "f24"}})
        self.assertEqual([event[2] for event in f24_events], [0xFFD5, 0xFFD5])

    def test_screenshot_protocol_reuses_unchanged_cached_frame(self):
        pixels = bytes((255, 0, 0, 0, 255, 0))
        first_metadata = fast_io._SCREENSHOT_META.pack(
            2, 1, 6, 1, 7, 123456, 142_000
        )
        second_metadata = fast_io._SCREENSHOT_META.pack(
            2, 1, 6, 0, 7, 123456, 142_000
        )
        first_response = self._response(
            fast_io._OP_SCREENSHOT, first_metadata + pixels
        )
        second_response = self._response(fast_io._OP_SCREENSHOT, second_metadata)
        sock = _FragmentedSocket(
            [
                first_response[:3],
                first_response[3:19],
                first_response[19:],
                second_response,
            ]
        )
        client = ModalNativeFastIOClient(
            "host", 443, "token", (2, 1), use_tls=False
        )
        client._socket = sock

        first = client.capture_image()
        first.putpixel((0, 0), (0, 0, 0))
        second = client.capture_image()

        self.assertEqual(first.mode, "RGB")
        self.assertEqual(first.getpixel((1, 0)), (0, 255, 0))
        self.assertEqual(second.getpixel((0, 0)), (255, 0, 0))
        self.assertEqual(second.getpixel((1, 0)), (0, 255, 0))
        self.assertEqual(client.last_frame_captured_ns, 123456)
        self.assertEqual(client.last_server_capture_ns, 142_000)
        requested_frame_ids = [
            fast_io._SCREENSHOT_REQUEST.unpack(message[-8:])[0]
            for message in sock.sent
        ]
        self.assertEqual(requested_frame_ids, [0, 7])

    def test_action_acknowledgement_reports_in_vm_elapsed_time(self):
        payload = fast_io._ACTION_RESPONSE.pack(16_000)
        sock = _FragmentedSocket(
            [self._response(fast_io._OP_ACTION, payload)]
        )
        client = ModalNativeFastIOClient(
            "host", 443, "token", (2, 1), use_tls=False
        )
        client._socket = sock
        client.inject_action({"keyboard": {"text": "x"}})
        self.assertEqual(client.last_server_action_ns, 16_000)
        _, _, opcode, request_size = fast_io._REQUEST_HEADER.unpack(
            sock.sent[0][: fast_io._REQUEST_HEADER.size]
        )
        self.assertEqual(opcode, fast_io._OP_ACTION)
        self.assertGreater(request_size, 4)

    def test_local_shared_frame_returns_stable_rgb_image_without_socket_transfer(self):
        frame_size = 2 * 1 * 3
        mapping_size = fast_io._LOCAL_HEADER_SIZE + frame_size * 3
        with tempfile.TemporaryFile() as backing:
            backing.truncate(mapping_size)
            import mmap

            mapping = mmap.mmap(backing.fileno(), mapping_size)
            fast_io._LOCAL_PREFIX.pack_into(
                mapping, 0, b"GAFS", fast_io._VERSION, 2, 1, 6, 3
            )
            fast_io._LOCAL_U64.pack_into(mapping, 24, 0)
            fast_io._LOCAL_SLOT_META.pack_into(
                mapping, 32, 2, 9, 123_000, 140_000
            )
            mapping[fast_io._LOCAL_HEADER_SIZE : fast_io._LOCAL_HEADER_SIZE + 6] = (
                bytes((1, 2, 3, 4, 5, 6))
            )
            client = ModalNativeFastIOClient(
                "127.0.0.1", 5902, "token", (2, 1), use_tls=False
            )
            client._local_frame_map = mapping
            client._last_local_ping_ns = fast_io.time.monotonic_ns()
            image = client.capture_image()
            image.putpixel((0, 0), (0, 0, 0))
            second = client.capture_image()
            self.assertEqual(list(second.getdata()), [(1, 2, 3), (4, 5, 6)])
            self.assertEqual(client._frame_id, 9)
            self.assertEqual(client.last_server_capture_ns, 140_000)
            client.close()


class VNCTransportTests(unittest.TestCase):
    def test_recv_exact_handles_fragmented_remote_frames(self):
        connection = VNCConnection("host", 5901)
        connection._socket = _FragmentedSocket([b"a", b"bc", b"def"])
        self.assertEqual(connection._recv_exact(6), b"abcdef")

    def test_connect_failure_closes_without_reentrant_lock_deadlock(self):
        sock = _FragmentedSocket([b"NOT AN RFB!!"])
        with mock.patch("gym_anything.runtime.runners.vnc_utils.socket.socket", return_value=sock):
            connection = VNCConnection("host", 5901)
            self.assertFalse(connection.connect(timeout=0.01))
        self.assertTrue(sock.closed)

    def test_pointer_button_state_is_preserved_across_moves(self):
        sock = _FragmentedSocket()
        connection = VNCConnection("host", 5901)
        connection._socket = sock
        connection._width = 100
        connection._height = 100

        connection.send_mouse_button(1, True, x=10, y=20)
        connection.send_mouse_move(30, 40)
        connection.send_mouse_button(1, False)

        messages = [struct.unpack("!BBHH", value) for value in sock.sent]
        self.assertEqual(messages, [(5, 1, 10, 20), (5, 1, 30, 40), (5, 0, 30, 40)])
        self.assertEqual(connection.pointer_position, (30, 40))


if __name__ == "__main__":
    unittest.main()
