# Zotero Environment for Gym-Anything

A complete environment for benchmarking AI agents on Zotero reference management tasks.

## Overview

This environment provides a fully functional Zotero 7.0.11 installation on Ubuntu 22.04 with GNOME desktop, configured for AI agent interaction through the Gym-Anything framework.

## Environment Details

- **Application**: Zotero 7.0.11 (reference management software)
- **Base Image**: ubuntu-gnome-systemd_highres (1920x1080)
- **Resources**: 4 CPU cores, 4GB RAM
- **Database**: SQLite at `/home/ga/Zotero/zotero.sqlite`
- **Data Directory**: `/home/ga/Zotero/`
- **User**: ga (password: password123, sudo enabled)
- **License**: AGPL-3.0

## Environment Setup

- **Base Image**: `ubuntu-gnome-systemd_highres` (Ubuntu 22.04 with GNOME desktop, 1920x1080)
- **Installation Method**: Official tarball from zotero.org
- **Resources**: 4 CPU cores, 4GB RAM
- **Display**: GNOME desktop at 1920x1080 resolution

## Tasks

### 1. Import BibTeX Library (`import_bibtex_library`)

Import a BibTeX bibliography file containing classic computer science and physics papers into Zotero.

**Objective**: Import the file `classic_papers.bib` (located at `/home/ga/Documents/classic_papers.bib`) containing 10 papers by authors like Einstein, Turing, Knuth, and Shannon using File > Import.

**Verification**: Checks that 9-11 items were added and expected authors appear in the database.

**Data Source**: Classic papers in computer science and physics (Einstein's relativity, Turing's computability, Shannon's information theory, etc.)

### 2. Create Collection and Organize (`create_collection_organize`)

Create a new collection and import papers into it.

**Objective**: Create a collection named "Machine Learning Papers" and import the RIS file `machine_learning_papers.ris` (located at `/home/ga/Documents/machine_learning_papers.ris`) containing 8 foundational ML papers into this collection.

**Verification**: Checks that the collection was created and contains 7-9 items.

**Data Source**: Foundational machine learning papers (Deep Learning by LeCun, ImageNet by Krizhevsky, Attention is All You Need, AlphaGo, GPT-3, BERT, ResNet, GANs)

### 3. Add Tags to Items (`add_tags_to_items`)

Organize library items by adding relevant tags.

**Objective**: Add at least 3 different tags to items in your library. Tags should be relevant to the research topics (e.g., 'deep-learning', 'neural-networks', 'computer-vision', 'NLP').

**Verification**: Checks that tags were added and items were tagged appropriately.

## Data Files

All bibliographic data files are located in `assets/sample_data/`:

- **classic_papers.bib**: BibTeX file with 10 classic papers in CS/physics
- **machine_learning_papers.ris**: RIS file with 8 foundational ML papers

These files contain real academic papers from published literature, providing authentic bibliographic metadata.

## Zotero Database Structure

Zotero uses SQLite database (`/home/ga/Zotero/zotero.sqlite`) with key tables:

- **items**: Main items table (itemTypeID: 1=note, 14=attachment, others=bibliographic items)
- **collections**: User-created collections
- **collectionItems**: Junction table linking items to collections
- **creators**: Author/creator information
- **tags**: Tag definitions
- **itemTags**: Junction table linking items to tags
- **itemData**: Field values for items
- **itemDataValues**: Actual values for fields

## Usage

Start the environment:

```python
from gym_anything.api import from_config

# Load environment with a specific task
env = from_config("examples/zotero_env", task_id="import_bibtex_library")
obs = env.reset(seed=42)

# Get SSH connection info
ssh_port = env._runner.ssh_port
print(f"SSH port: {ssh_port}")
```

Connect to Zotero via SSH for interactive testing:

```python
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=ssh_port, username='ga', password='password123')

# Take screenshot
ssh.exec_command('DISPLAY=:1 import -window root /tmp/screenshot.png')

# Copy screenshot
sftp = ssh.open_sftp()
sftp.get('/tmp/screenshot.png', 'local_screenshot.png')
sftp.close()
```

## Verification Pattern

All tasks follow the standard two-part verification:

1. **Export script** (`export_result.sh`): Queries Zotero SQLite database, exports data to `/tmp/task_result.json`
2. **Verifier** (`verifier.py`): Uses `copy_from_env()` to read JSON, evaluates criteria, returns score

## Notes

- Zotero profile is created at first launch with random suffix (e.g., `abc123.default`)
- Configuration in `prefs.js` disables first-run dialogs and sets data directory to `/home/ga/Zotero`
- Window maximization ensures better agent interaction
- Database queries exclude notes (itemTypeID=1) and attachments (itemTypeID=14) from item counts

## Testing Status

✅ **Environment Setup: COMPLETE** (Post-Audit)
- Zotero 7.0.11 installs successfully
- Application launches and stays running without blocking popups
- Database created and accessible
- All task files properly configured
- Firefox interference eliminated

✅ **Infrastructure: VERIFIED & HARDENED**
- Export scripts produce valid JSON with robust error handling
- Verifiers use strict matching (exact collection names, word-boundary tags)
- Timestamp-based import verification prevents gaming
- SSH access working
- Screenshot capture functional

✅ **Task Quality: IMPROVED**
- Clear completion criteria in all descriptions
- Removed biasing examples from task 3
- Emphasized exact collection name requirement
- Visual verification hints added

✅ **READY FOR PRODUCTION USE**

## Audit & Fixes

**Two Independent Audits Completed:** 2026-02-11

### First Audit Results:
- **Initial Score:** 5.61/10 (NOT READY FOR USE)
- **Post-Fix Score:** 8.5/10 (READY FOR USE)
- **Critical Issues:** Firefox popups, verifier logic, ambiguous task descriptions

### Second Audit Results:
- **Initial Score:** 5.9/10 (NOT READY FOR USE)
- **Post-Fix Score:** 8.8/10 (PRODUCTION READY)
- **Critical Issues:** Window visibility, task start state failures

### All Critical Issues Fixed:
1. ✅ Firefox popup interference eliminated
2. ✅ Window activation/visibility - Zotero now properly raised and focused
3. ✅ Robust window detection with automatic restart fallback
4. ✅ Verifier logic strengthened (exact matches, domain-agnostic tags)
5. ✅ Task descriptions clarified with explicit completion criteria
6. ✅ Screenshot verification at setup and task start
7. ✅ All typos fixed (reinforcement pattern)

See documentation:
- `evidence_docs/AUDIT_FIXES.md` - First audit response
- `evidence_docs/SECOND_AUDIT_FIXES.md` - Second audit response (window visibility fixes)

## Evidence

See `evidence_docs/` directory for:
- `AUDIT_FIXES.md`: Complete audit response with all fixes documented
- `ENVIRONMENT_STATUS.md`: Detailed technical status report
- `env_boot_with_task.png`: Screenshot showing Zotero running cleanly (no popups)
- `step*.png`: Manual testing screenshots
- `env_setup_*.log`: Installation and setup logs

## Critical Implementation Notes

**Setup Script Pattern** (important for similar desktop apps):
```bash
# Do NOT use set -e - causes premature exit
# Do NOT use heredocs with su - causes hanging
# Correct pattern:
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > log 2>&1 &'
```

**Registration in constants.py**:
```python
try:
    zotero_tasks = [f for f in os.listdir('examples/zotero_env/tasks') if '.' not in f]
except FileNotFoundError:
    zotero_tasks = []

ENV_TASK_SPLITS['zotero_env'] = zotero_tasks
```
