# Zotero Environment - Testing Status

## Completed Steps

### Phase 1-5: Environment Creation ✅
- [x] Framework understanding
- [x] Application research (Zotero 7.x)
- [x] Realistic data sourcing (classic CS/physics papers, ML papers)
- [x] Directory structure created
- [x] env.json configured
- [x] Installation script (install_zotero.sh)
- [x] Setup script (setup_zotero.sh)
- [x] Task utilities (task_utils.sh)
- [x] All 3 tasks created with task.json, setup_task.sh, export_result.sh, verifier.py
- [x] Environment registered in constants.py
- [x] All scripts made executable (chmod +x)
- [x] Documentation created (README.md, TASKS_SUMMARY.md, IMPLEMENTATION_NOTES.md)

### Tasks Implemented
1. **import_bibtex_library**: Import 10 classic papers from BibTeX file
2. **create_collection_organize**: Create collection + import 8 ML papers from RIS
3. **add_tags_to_items**: Add relevant tags to library items

### Data Files
- `assets/sample_data/classic_papers.bib`: 10 real CS/physics papers (102 lines)
- `assets/sample_data/machine_learning_papers.ris`: 8 real ML papers (115 lines)

## Phase 6: Interactive Testing 🔄 IN PROGRESS

### Test Script Created
- `test_zotero_interactive.py`: Automated environment startup and verification

### Running Tests
Currently running: `python test_zotero_interactive.py import_bibtex_library`

This test will:
1. Start the Zotero environment
2. Connect via SSH
3. Verify Zotero is running
4. Take screenshots
5. Check logs
6. Verify task setup files
7. Query Zotero database

### Expected Output
- Screenshot at `benchmarks/environments/zotero_env/evidence/task_import_bibtex_library_setup.png`
- Environment logs verification
- Database existence confirmation

## Phase 7: Final Verification ⏳ PENDING

Once interactive testing completes, need to verify:

### Verification Checklist
- [ ] Installation script completes without errors
- [ ] Setup script completes without errors
- [ ] Zotero 7.x is visible in screenshot
- [ ] Zotero window is maximized
- [ ] Database exists at `/home/ga/Zotero/zotero.sqlite`
- [ ] Profile configuration is applied
- [ ] Task setup files are accessible
- [ ] BibTeX file exists for import task
- [ ] RIS file exists for collection task
- [ ] Export scripts produce valid JSON
- [ ] Verifiers can read and process results

### Evidence Documentation Needed
For `evidence/` folder:
1. **env_boot_no_task.png**: Zotero running without task
2. **task_import_bibtex_library_setup.png**: After task 1 setup
3. **task_create_collection_organize_setup.png**: After task 2 setup
4. **task_add_tags_to_items_setup.png**: After task 3 setup
5. **Log snippets**: From env_setup_pre_start.log and env_setup_post_start.log
6. **Verification samples**: Sample JSON outputs from export scripts

### Manual Testing Steps (After Automated Test)
Once environment is confirmed running:

1. **Test Task 1 (Import BibTeX)**:
   ```bash
   python ask_cua.py --question "Where is the File menu in Zotero?" --screenshot_path /path/to/screenshot.png
   # Use xdotool to click File > Import
   # Select /home/ga/Documents/classic_papers.bib
   # Verify items appear in library
   ```

2. **Test Task 2 (Create Collection)**:
   ```bash
   # Right-click on "My Library"
   # Create new collection "Machine Learning Papers"
   # Import RIS file into collection
   ```

3. **Test Task 3 (Add Tags)**:
   ```bash
   # Select items
   # Add tags in right panel
   # Verify tags appear
   ```

### Interactive Testing Commands

```python
# In Python shell after test starts
from gym_anything.api import from_config
import paramiko

env = from_config("benchmarks/environments/zotero_env", task_id="import_bibtex_library")
obs = env.reset(seed=42)

# SSH connection
ssh_port = env._runner.ssh_port
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=ssh_port, username='ga', password='password123')

# Take screenshot
ssh.exec_command('DISPLAY=:1 import -window root /tmp/screen.png')

# Download
sftp = ssh.open_sftp()
sftp.get('/tmp/screen.png', 'local_screen.png')

# Use ask_cua.py
# python ask_cua.py --question "Where should I click?" --screenshot_path local_screen.png

# Perform action
ssh.exec_command('DISPLAY=:1 xdotool mousemove X Y click 1')

# Cleanup
sftp.close()
ssh.close()
env.close()
```

## Known Issues to Watch For

Based on similar environments:
1. **Profile Creation**: Zotero creates profile with random suffix on first launch
2. **First-run Dialogs**: Must be disabled via prefs.js
3. **Database Timing**: Database created after app initializes
4. **Window Management**: Use wmctrl for maximize/focus
5. **SQLite Permissions**: Export scripts need sudo fallbacks

## Next Actions

1. **Wait for test completion** (~5-10 minutes for VM boot + Zotero start)
2. **Review test output** for errors
3. **Examine screenshot** to verify Zotero is visible
4. **Complete manual interaction** using ask_cua.py + xdotool
5. **Run verification** to confirm export/verifier work
6. **Capture evidence** screenshots and logs
7. **Document learnings** in implementation notes

## Success Criteria

Environment is ready when:
- ✅ All scripts run without errors
- ✅ Zotero launches and is visible
- ✅ Database is created and queryable
- ✅ Task files are accessible
- ✅ At least one task can be completed manually
- ✅ Verification scripts work correctly
- ✅ Evidence documentation is complete

## Test Results

*Results will be added here after testing completes...*
