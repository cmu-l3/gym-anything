"""HTTP shim that runs inside a Modal VM Sandbox and drives a QemuNativeRunner.

Started by ModalRunner via `python -m gym_anything.runtime.runners.modal_shim`.
Exposes the BaseRunner surface over HTTP so the client-side ModalRunner can
proxy calls from env.py without any changes to the QEMU runner itself.

Long-running calls (start, exec of hooks, checkpoint creation) go through a
submit/poll job queue so no HTTP request has to stay open across the tunnel.
Jobs run on a single worker thread, matching env.py's sequential runner usage.
"""

from __future__ import annotations

import argparse
import base64
import dataclasses
import json
import queue
import tempfile
import threading
import traceback
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

_runner = None
_jobs: dict = {}
_job_queue: "queue.Queue" = queue.Queue()


def _init_runner(spec_dict: dict) -> None:
    global _runner
    from ...presets import is_avd_preset
    from ...specs import EnvSpec

    spec = EnvSpec.from_dict(spec_dict)
    base = spec_dict.get("base") or ""
    runner_name = spec_dict.get("runner") or ""
    if runner_name in ("avd", "avd_native") or is_avd_preset(base):
        from .avd_native import AVDNativeRunner

        _runner = AVDNativeRunner(spec)
    else:
        from .qemu_native import QemuNativeRunner

        _runner = QemuNativeRunner(spec)


def _encode_result(result):
    if isinstance(result, bytes):
        return {"__bytes_b64__": base64.b64encode(result).decode()}
    if dataclasses.is_dataclass(result) and not isinstance(result, type):
        return {"__dataclass__": dataclasses.asdict(result)}
    return result


def _worker_loop() -> None:
    while True:
        job_id, method, args, kwargs = _job_queue.get()
        job = _jobs[job_id]
        job["status"] = "running"
        try:
            fn = getattr(_runner, method)
            result = fn(*args, **kwargs)
            job["result"] = _encode_result(result)
            job["status"] = "done"
        except Exception as e:
            job["error"] = f"{e}\n{traceback.format_exc()}"
            job["status"] = "error"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quiet request logging
        pass

    def _send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, data: bytes, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if not length:
            return {}
        return json.loads(self.rfile.read(length))

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json({"ok": True, "initialized": _runner is not None})
            return
        if parsed.path == "/result":
            job_id = parse_qs(parsed.query).get("id", [""])[0]
            job = _jobs.get(job_id)
            if job is None:
                self._send_json({"status": "unknown"}, code=404)
                return
            self._send_json(job)
            return
        if parsed.path == "/screenshot":
            try:
                tmp = Path(tempfile.mkdtemp()) / "screen.png"
                ok = _runner.capture_screenshot(tmp)
                if ok and tmp.exists():
                    self._send_bytes(tmp.read_bytes())
                else:
                    self._send_json({"error": "capture failed"}, code=500)
            except Exception as e:
                self._send_json({"error": f"{e}\n{traceback.format_exc()}"}, code=500)
            return
        self._send_json({"error": "not found"}, code=404)

    def do_POST(self):
        parsed = urlparse(self.path)
        try:
            if parsed.path == "/init":
                body = self._read_body()
                _init_runner(body["spec"])
                self._send_json({"ok": True})
                return
            if parsed.path == "/submit":
                body = self._read_body()
                # Client may supply the id so retried submits are idempotent.
                job_id = body.get("id") or uuid.uuid4().hex
                if job_id not in _jobs:
                    _jobs[job_id] = {"status": "pending", "result": None, "error": None}
                    _job_queue.put(
                        (job_id, body["method"], body.get("args", []), body.get("kwargs", {}))
                    )
                self._send_json({"id": job_id})
                return
            if parsed.path == "/put_file":
                body = self._read_body()
                tmp = Path(tempfile.mkdtemp()) / body["name"]
                tmp.write_bytes(base64.b64decode(body["data_b64"]))
                self._send_json({"path": _runner.put_file(str(tmp))})
                return
            if parsed.path == "/copy_to":
                body = self._read_body()
                tmp = Path(tempfile.mkdtemp()) / body["name"]
                tmp.write_bytes(base64.b64decode(body["data_b64"]))
                _runner.copy_to(str(tmp), body["dst"])
                self._send_json({"ok": True})
                return
            if parsed.path == "/copy_from":
                body = self._read_body()
                tmp_dir = Path(tempfile.mkdtemp())
                dst = tmp_dir / "out"
                _runner.copy_from(body["src"], str(dst))
                if dst.is_dir():
                    import io
                    import tarfile

                    buf = io.BytesIO()
                    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
                        tar.add(str(dst), arcname=".")
                    self._send_json(
                        {"is_dir": True, "data_b64": base64.b64encode(buf.getvalue()).decode()}
                    )
                elif dst.exists():
                    self._send_json(
                        {"is_dir": False, "data_b64": base64.b64encode(dst.read_bytes()).decode()}
                    )
                else:
                    self._send_json({"error": "copy_from produced no output"}, code=500)
                return
            self._send_json({"error": "not found"}, code=404)
        except Exception as e:
            self._send_json({"error": f"{e}\n{traceback.format_exc()}"}, code=500)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8377)
    args = parser.parse_args()

    threading.Thread(target=_worker_loop, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"[modal-shim] listening on :{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
