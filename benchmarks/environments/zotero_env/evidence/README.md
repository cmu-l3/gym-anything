# Zotero Environment Evidence Documentation

This directory contains evidence that the Zotero environment has been properly set up and tested.

## Required Evidence

The following screenshots and logs must be captured during interactive testing:

### Environment Boot Evidence

1. **env_boot_no_task.png**: Screenshot showing Zotero running after environment boots (no task loaded)
   - Should show: Zotero window maximized, empty library, main interface visible

### Task Setup Evidence

For each task, capture:

2. **task_import_bibtex_library_setup.png**: Screenshot after `import_bibtex_library` task setup
   - Should show: Zotero open, BibTeX file present in `/home/ga/Documents/`
   - Verify file exists: `ls -la /home/ga/Documents/classic_papers.bib`

3. **task_create_collection_organize_setup.png**: Screenshot after `create_collection_organize` task setup
   - Should show: Zotero open, RIS file present in `/home/ga/Documents/`
   - Verify file exists: `ls -la /home/ga/Documents/machine_learning_papers.ris`

4. **task_add_tags_to_items_setup.png**: Screenshot after `add_tags_to_items` task setup
   - Should show: Zotero open with some items in library

### Verification Evidence

For each task, include:

5. **Verification outputs**: Copy of actual verification results from running tasks
   - Sample of `/tmp/task_result.json` content
   - Verifier output showing scores and feedback

### Log Snippets

Include relevant snippets from:

- `/home/ga/env_setup_pre_start.log` (installation log)
- `/home/ga/env_setup_post_start.log` (setup log)
- Task hook logs

## How to Capture Evidence

During interactive testing:

```python
from gym_anything.api import from_config
import paramiko

# Start environment
env = from_config("benchmarks/environments/zotero_env", task_id="import_bibtex_library")
obs = env.reset(seed=42, use_cache=False)

# Connect via SSH
ssh_port = env._runner.ssh_port
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=ssh_port, username='ga', password='password123')

# Take screenshot
ssh.exec_command('DISPLAY=:1 import -window root /tmp/screenshot.png')

# Download screenshot
sftp = ssh.open_sftp()
sftp.get('/tmp/screenshot.png', 'evidence/task_import_bibtex_library_setup.png')

# Get logs
sftp.get('/home/ga/env_setup_post_start.log', 'evidence/env_setup_post_start.log')

sftp.close()
ssh.close()
```

## Verification Checklist

- [ ] Environment boots successfully
- [ ] Zotero 7.x is installed and launches
- [ ] Window maximizes properly
- [ ] Database is created at `/home/ga/Zotero/zotero.sqlite`
- [ ] Profile configuration disables first-run dialogs
- [ ] Sample BibTeX file is accessible
- [ ] Sample RIS file is accessible
- [ ] Database queries return expected results
- [ ] Verification scripts execute without errors
- [ ] All three tasks can be completed interactively
