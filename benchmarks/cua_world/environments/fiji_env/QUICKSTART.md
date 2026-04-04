# Fiji Environment - Quick Start Guide

## TL;DR

```python
from gym_anything.api import from_config

# Start environment
env = from_config("benchmarks/cua_world/environments/fiji_env", task_id="z_stack_projection")
obs = env.reset(seed=42)

# Environment is ready!
# Fiji is running at DISPLAY=:1
# SSH: env._runner.ssh_port
# VNC: env._runner.vnc_port
```

## Two Tasks Available

### 1. z_stack_projection (Easy)
Create max intensity projection from CT scan
- **Data**: T1 Head (Fiji built-in)
- **Steps**: Open sample → Z Project → Adjust → Save
- **Output**: max_projection.png + stats CSV

### 2. color_deconvolution (Medium)
Separate color channels in histology
- **Data**: HeLa Cells (Fiji built-in)
- **Steps**: Open sample → Color Deconvolution → Save channels
- **Output**: channel_1.png, channel_2.png + stats CSV

## File Locations

```
/opt/fiji/              # Fiji installation
/opt/fiji_samples/      # BBBC005 real data
/home/ga/Fiji_Data/     # User workspace
  ├── raw/              # Input images
  ├── processed/        # Intermediate results
  ├── results/          # Final outputs (save here!)
  └── measurements/     # Analysis data
```

## Launch Fiji

```bash
# From terminal
fiji

# Or
~/launch_fiji.sh

# Or from Desktop shortcut (double-click Fiji icon)
```

## Interactive Testing

```python
import paramiko

# Connect via SSH
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=env._runner.ssh_port,
            username='ga', password='password123')

# Take screenshot
ssh.exec_command('DISPLAY=:1 scrot /tmp/screen.png')

# Get screenshot
sftp = ssh.open_sftp()
sftp.get('/tmp/screen.png', 'local_screen.png')

# Use visual_grounding MCP tool to analyze
# Then execute actions:
ssh.exec_command('DISPLAY=:1 xdotool mousemove X Y click 1')
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| `install_fiji.sh` | Downloads Fiji + BBBC005 data |
| `setup_fiji.sh` | Configures user, creates shortcuts |
| `setup_task.sh` | Launches Fiji for specific task |
| `export_result.sh` | Copies results to /tmp |

## Verification

```bash
# Check Fiji is running
ps aux | grep fiji

# Check windows
DISPLAY=:1 wmctrl -l

# Check data
ls ~/Fiji_Data/raw/

# Check logs
tail /home/ga/env_setup_pre_start.log
```

## Resources

- **CPU**: 4 cores
- **RAM**: 6GB (4GB for Java heap)
- **Network**: Enabled
- **Resolution**: 1920x1080
- **Startup**: ~3 minutes

## Data Sources

✅ **Real data only** - No mock/synthetic data

1. **BBBC005**: https://data.broadinstitute.org/bbbc/BBBC005/
   - Real microscopy benchmark with ground truth
   - In `/opt/fiji_samples/BBBC005/`

2. **Fiji Samples**: Built-in official samples
   - Access via File > Open Samples
   - T1 Head, HeLa Cells, Blobs, etc.

## Common Commands

```bash
# Image info utility
fiji-image-info /path/to/image.tif

# List available samples
ls /opt/fiji_samples/

# Check Fiji version
/usr/local/bin/fiji --version
```

## Documentation

- `README.md` - Full documentation
- `IMPLEMENTATION_SUMMARY.md` - What was built
- `evidence/` - Testing evidence
- `env_creation_notes/specific_env_notes/fiji_env/` - Implementation details

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Fiji not visible | Check `wmctrl -l` for window list |
| Out of memory | Java heap set to 4GB (adjust in launch script) |
| Updater dialog | Click OK to dismiss (read-only warning) |
| Samples not found | Check `/opt/fiji_samples/` and `~/Fiji_Data/raw/` |

## Quick Test

```bash
# Start environment and check status
python3 << 'EOF'
from gym_anything.api import from_config
env = from_config("benchmarks/cua_world/environments/fiji_env", task_id="z_stack_projection")
obs = env.reset(seed=42, use_cache=False)
print(f"✓ Environment started")
print(f"  SSH Port: {env._runner.ssh_port}")
print(f"  VNC Port: {env._runner.vnc_port}")
env.close()
EOF
```

## Next Steps

1. **Read** `README.md` for comprehensive guide
2. **Check** `evidence/verification_checklist.md` for testing details
3. **Try** interactive testing with SSH + visual_grounding
4. **Run** one of the two tasks end-to-end

---

**Need help?** See `README.md` or `implementation_notes.md`
