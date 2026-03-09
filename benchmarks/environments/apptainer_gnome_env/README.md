# Apptainer GNOME Demo

This example packages a full GNOME desktop for the `ApptainerRunner`. It is designed for rootless clusters (e.g., Slurm) where Docker is unavailable but Apptainer/Singularity is allowed.

## Layout

``` 
benchmarks/environments/apptainer_gnome_env/
├── env.yaml                     # EnvSpec referencing the GNOME SIF and startup script
├── config/
│   └── gnome-desktop.def        # Apptainer definition used to build the SIF
├── scripts/
│   └── start_gnome.sh           # Entry script that boots GNOME + gnome-text-editor
└── gnome-desktop.sif            # (generated) Apptainer image; build before running
```

## Build the SIF (rootless)

```bash
cd /path/to/scaling_cua2
apptainer build --fakeroot benchmarks/environments/apptainer_gnome_env/gnome-desktop.sif \
  benchmarks/environments/apptainer_gnome_env/config/gnome-desktop.def
```

The build installs `ubuntu-desktop-minimal`, GNOME Flashback, PulseAudio, VNC tooling, and a default `ga` user.

> **Note:** If your site does not permit `--fakeroot`, drop that flag—just ensure you have write permissions to the destination path.

## Start the environment

```bash
python -m gym_anything.cli run benchmarks/environments/apptainer_gnome_env --steps 40
```

During startup the runner prints the chosen VNC port (default host port 5951). Connect with any viewer, e.g. `open vnc://localhost:5951`, to see the GNOME desktop with `gnome-text-editor` already open. Episode artifacts (recording, screenshots, logs) are written under `./artifacts/` relative to the working directory.

## Customisation

- Edit `scripts/start_gnome.sh` to launch additional GUI apps or tweak session behaviour.
- Add more bind mounts via `mounts` (EnvSpec) or `apptainer.binds` (ApptainerSpec) to expose datasets or host directories.
- Increase `resources.mem_gb` / `cpu` as needed for heavier workloads.

Enjoy running GNOME inside rootless Apptainer with full parity to the Docker runner.
