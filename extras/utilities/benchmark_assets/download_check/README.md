# Benchmark Asset Download Check

Scans CUA-World setup scripts for external asset URLs and optionally checks
or downloads them.

This method is adapted from the script shared by Tianbao Xie
(`@Timothyxxx`) in
<https://github.com/cmu-l3/gym-anything/issues/2>.

## Usage

```bash
gym-anything-extras utilities benchmark_assets download_check
```

By default this only parses scripts and writes:

```text
gym_anything_asset_audit/asset_download_check.json
```

To probe link health without downloading full assets:

```bash
gym-anything-extras utilities benchmark_assets download_check --check-links --jobs 16
```

To reproduce the heavier download-style audit:

```bash
gym-anything-extras utilities benchmark_assets download_check --download --jobs 4
```

Use `--all-domains` to include URLs outside the known asset-domain allowlist.
Use `--fail-on-dead` when running in automation.

