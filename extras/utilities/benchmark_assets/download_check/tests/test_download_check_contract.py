"""Contract tests for the benchmark asset download_check utility."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "src"))

from extras.utilities.benchmark_assets.download_check import method as dc  # noqa: E402


class ScanAssetsTests(unittest.TestCase):
    def test_extract_urls_from_wget_curl_python_and_assignment(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "setup_task.sh"
            script.write_text(
                "\n".join(
                    [
                        "wget -q https://imagej.net/images/leaf.jpg -O leaf.jpg",
                        "curl -L https://github.com/example/release.zip -o release.zip",
                        "urllib.request.urlretrieve('https://upload.wikimedia.org/a.png', 'a.png')",
                        "DATA_URL='https://raw.githubusercontent.com/org/repo/main/data.csv'",
                    ]
                )
            )
            urls = [url for url, _, _ in dc.extract_urls_from_file(script)]
        self.assertEqual(len(urls), 4)
        self.assertIn("https://imagej.net/images/leaf.jpg", urls)

    def test_scan_assets_deduplicates_and_records_usage(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task_a = root / "demo_env" / "tasks" / "task_a"
            task_b = root / "demo_env" / "tasks" / "task_b"
            scripts = root / "demo_env" / "scripts"
            task_a.mkdir(parents=True)
            task_b.mkdir(parents=True)
            scripts.mkdir(parents=True)
            url = "https://imagej.net/images/leaf.jpg"
            (task_a / "setup_task.sh").write_text(f"wget -q {url} -O leaf.jpg\n")
            (task_b / "setup_task.sh").write_text(f"curl -L {url} -o leaf.jpg\n")
            (scripts / "install.sh").write_text(
                "wget -q https://raw.githubusercontent.com/org/repo/main/file.txt\n"
            )

            entries, filtered = dc.scan_assets(root)

        self.assertEqual(filtered, [])
        self.assertEqual(len(entries), 2)
        leaf = next(entry for entry in entries if entry.url == url)
        self.assertEqual(leaf.used_by, ["demo_env/task_a", "demo_env/task_b"])
        self.assertEqual(len(leaf.sources), 2)

    def test_scan_assets_filters_unknown_domains_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            task = Path(tmp) / "demo_env" / "tasks" / "task_a"
            task.mkdir(parents=True)
            (task / "setup_task.sh").write_text(
                "wget -q https://unknown.invalid/file.dat -O file.dat\n"
            )

            entries, filtered = dc.scan_assets(Path(tmp))

        self.assertEqual(entries, [])
        self.assertEqual(filtered[0]["domain"], "unknown.invalid")


class StatusTests(unittest.TestCase):
    def test_check_one_url_records_failed_status(self):
        entry = dc.AssetEntry(
            url="https://imagej.nih.gov/ij/images/missing.tif",
            domain="imagej.nih.gov",
            filename="missing.tif",
        )
        completed = mock.Mock()
        completed.stdout = "404"
        completed.stderr = ""
        completed.returncode = 0
        with mock.patch.object(dc.subprocess, "run", return_value=completed):
            result = dc.check_one_url(entry, connect_timeout=1, max_time=1)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.http_code, 404)

    def test_summarize_counts_failed_tasks_and_env_scripts(self):
        failed = dc.AssetEntry(
            url="https://imagej.nih.gov/ij/images/missing.tif",
            domain="imagej.nih.gov",
            filename="missing.tif",
            used_by=["fiji_env/task_a", "fiji_env/_env_scripts"],
            status="failed",
            http_code=404,
        )
        ok = dc.AssetEntry(
            url="https://imagej.net/images/leaf.jpg",
            domain="imagej.net",
            filename="leaf.jpg",
            used_by=["fiji_env/task_b"],
            status="ok",
            http_code=200,
        )
        summary = dc.summarize([failed, ok], [])
        self.assertEqual(summary["failed_urls"], 1)
        self.assertEqual(summary["affected_tasks"], 1)
        self.assertEqual(summary["affected_env_scripts"], 1)
        self.assertEqual(summary["failed_status_counts"], {"404": 1})


class ParserTests(unittest.TestCase):
    def test_parser_defaults_to_parse_only(self):
        args = dc.build_parser().parse_args([])
        self.assertFalse(args.check_links)
        self.assertFalse(args.download)
        self.assertFalse(args.all_domains)

    def test_run_writes_report_without_network_when_parse_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            root = tmp_path / "benchmarks"
            task = root / "demo_env" / "tasks" / "task_a"
            task.mkdir(parents=True)
            (task / "setup_task.sh").write_text(
                "wget -q https://imagej.net/images/leaf.jpg -O leaf.jpg\n"
            )
            output = tmp_path / "out"

            rc = dc.run(
                [
                    "--benchmarks-root",
                    str(root),
                    "--output-dir",
                    str(output),
                    "--json",
                ]
            )

            report = json.loads((output / "asset_download_check.json").read_text())
        self.assertEqual(rc, 0)
        self.assertEqual(report["summary"]["downloadable_urls"], 1)
        self.assertEqual(report["summary"]["checked_or_downloaded_urls"], 0)


if __name__ == "__main__":
    unittest.main()

