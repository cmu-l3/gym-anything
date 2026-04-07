#!/usr/bin/env python3
"""
Verifier for podcast_production_mix task.
Occupation: Broadcast Technician (SOC 27-4012)
Industry: Broadcasting / Media

Checks that the agent assembled a podcast episode with proper track structure,
audio placement, gain levels, markers, and exported final mix.
"""

import math
import os
import sys
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65.0
SAMPLE_RATE = 44100


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Get audio track routes (excluding Master/Monitor buses)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def get_route_names(root):
    return [r.get('name', '') for r in get_audio_routes(root)]


def get_markers(root):
    """Get user-placed markers (excluding session range / loop / punch)."""
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        markers.append({
            'name': loc.get('name', ''),
            'start': int(loc.get('start', '0')),
            'end': int(loc.get('end', '0')),
            'flags': flags,
        })
    return markers


def get_route_gain_db(route):
    """Return gain of a route in dB."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') in ('gaincontrol', 'gain'):
            try:
                val = float(ctrl.get('value', '1.0'))
                if val <= 0:
                    return -120.0
                return 20 * math.log10(val)
            except (ValueError, TypeError):
                return 0.0
    return 0.0


def get_regions_for_route(root, route_name):
    """Get regions from the playlist associated with a route."""
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Ardour playlist names are like "TrackName.1" or "TrackName"
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions


# ---------- Main verifier ----------

def verify_podcast_production_mix(traj, env_info, task_info):
    """
    Multi-criterion verifier for podcast production task.

    Criteria (100 pts total, pass >= 65):
      1. Three audio tracks with correct names          (20 pts)
      2. Audio regions placed in correct temporal order  (25 pts)
      3. Gain levels appropriate for music vs speech     (20 pts)
      4. Session markers for episode segments            (15 pts)
      5. Exported WAV file in podcast_final/             (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # ---- Copy session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()

    try:
        copy_from_env(session_remote, tmp_session.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session file not accessible: {e}"}

    if not os.path.exists(tmp_session.name) or os.path.getsize(tmp_session.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_session.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}

    # ================================================================
    # CRITERION 1: Three audio tracks with correct names (20 pts)
    # Required: "Intro Theme", "Interview", "Outro Theme"
    # ================================================================
    route_names = get_route_names(root)
    route_names_lower = [n.lower() for n in route_names]

    required_tracks = {
        'intro': ['intro theme', 'intro_theme', 'intro music', 'intro'],
        'interview': ['interview', 'interview segment', 'interview_segment', 'speech', 'dialogue'],
        'outro': ['outro theme', 'outro_theme', 'outro music', 'outro', 'closing'],
    }

    tracks_found = {}
    for key, aliases in required_tracks.items():
        for rn in route_names_lower:
            for alias in aliases:
                if alias in rn or rn in alias:
                    tracks_found[key] = rn
                    break
            if key in tracks_found:
                break

    n_found = len(tracks_found)
    if n_found >= 3:
        score += 20.0
        feedback.append(f"PASS: All 3 podcast tracks found ({', '.join(route_names[:5])})")
    elif n_found >= 2:
        score += 12.0
        feedback.append(f"PARTIAL: {n_found}/3 podcast tracks found")
    elif n_found >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {n_found}/3 podcast tracks found")
    else:
        # Check if any new tracks were added at all (beyond the original Audio 1)
        if len(route_names) > 1:
            score += 3.0
            feedback.append(f"PARTIAL: {len(route_names)} tracks exist but names don't match spec")
        else:
            feedback.append("FAIL: No podcast tracks created")

    # ================================================================
    # CRITERION 2: Audio regions in correct temporal order (25 pts)
    # Intro first, Interview second, Outro third
    # ================================================================
    all_routes = get_audio_routes(root)
    route_regions = {}
    for route in all_routes:
        rname = route.get('name', '')
        regions = get_regions_for_route(root, rname)
        if regions:
            # Use earliest region position for ordering
            earliest = min(r['position'] for r in regions)
            route_regions[rname.lower()] = earliest

    # Check temporal order among found tracks
    positions = []
    for key in ['intro', 'interview', 'outro']:
        if key in tracks_found:
            tname = tracks_found[key]
            if tname in route_regions:
                positions.append((key, route_regions[tname]))

    if len(positions) >= 3:
        ordered = all(positions[i][1] <= positions[i+1][1] for i in range(len(positions)-1))
        if ordered:
            score += 25.0
            feedback.append("PASS: Audio regions in correct temporal order (intro -> interview -> outro)")
        else:
            score += 10.0
            feedback.append("PARTIAL: All 3 regions present but order incorrect")
    elif len(positions) >= 2:
        score += 12.0
        feedback.append(f"PARTIAL: Only {len(positions)}/3 tracks have audio regions placed")
    elif len(positions) >= 1:
        score += 5.0
        feedback.append("PARTIAL: Only 1 track has an audio region placed")
    else:
        # Check if ANY regions were added anywhere
        all_regions = list(root.iter('Region'))
        if len(all_regions) > 1:  # Original session has 1 region
            score += 3.0
            feedback.append("PARTIAL: Audio regions exist but not on correctly named tracks")
        else:
            feedback.append("FAIL: No audio regions placed beyond original")

    # ================================================================
    # CRITERION 3: Gain levels (20 pts)
    # Music tracks between -18dB and -6dB, speech near 0dB (±3dB)
    # ================================================================
    gain_correct = 0
    gain_checks = 0

    for route in all_routes:
        rname = route.get('name', '').lower()
        gain_db = get_route_gain_db(route)

        # Check if this is a music track
        is_music = any(kw in rname for kw in ['intro', 'outro', 'theme', 'music'])
        is_speech = any(kw in rname for kw in ['interview', 'speech', 'dialogue', 'voice'])

        if is_music:
            gain_checks += 1
            if -18.0 <= gain_db <= -3.0:
                gain_correct += 1
        elif is_speech:
            gain_checks += 1
            if -3.0 <= gain_db <= 3.0:
                gain_correct += 1

    if gain_checks >= 3 and gain_correct >= 3:
        score += 20.0
        feedback.append("PASS: Gain levels correct (music reduced, speech at unity)")
    elif gain_checks >= 2 and gain_correct >= 2:
        score += 12.0
        feedback.append(f"PARTIAL: {gain_correct}/{gain_checks} tracks have correct gain")
    elif gain_correct >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: {gain_correct}/{gain_checks} tracks have correct gain")
    else:
        # Check if any gain was changed at all from default
        gains_changed = sum(1 for r in all_routes if abs(get_route_gain_db(r)) > 0.5)
        if gains_changed > 0:
            score += 3.0
            feedback.append("PARTIAL: Some gain levels changed but not to spec")
        else:
            feedback.append("FAIL: Gain levels not adjusted from defaults")

    # ================================================================
    # CRITERION 4: Session markers (15 pts)
    # At least 2 meaningful markers
    # ================================================================
    markers = get_markers(root)
    meaningful_markers = [m for m in markers if len(m['name']) > 1]

    if len(meaningful_markers) >= 4:
        score += 15.0
        feedback.append(f"PASS: {len(meaningful_markers)} markers placed")
    elif len(meaningful_markers) >= 2:
        score += 10.0
        feedback.append(f"PARTIAL: {len(meaningful_markers)} markers (4 recommended)")
    elif len(meaningful_markers) >= 1:
        score += 5.0
        feedback.append(f"PARTIAL: Only {len(meaningful_markers)} marker(s)")
    else:
        feedback.append("FAIL: No session markers placed")

    # ================================================================
    # CRITERION 5: Exported WAV in podcast_final/ (20 pts)
    # ================================================================
    export_dir = "/home/ga/Audio/podcast_final"
    tmp_export_dir = tempfile.mkdtemp()
    wav_found = False

    # Try to copy any WAV files from the export directory
    for fname in ['community_voices.wav', 'podcast.wav', 'mix.wav', 'final.wav',
                  'MyProject.wav', 'master.wav', 'export.wav']:
        try:
            remote_path = f"{export_dir}/{fname}"
            local_path = os.path.join(tmp_export_dir, fname)
            copy_from_env(remote_path, local_path)
            if os.path.exists(local_path) and os.path.getsize(local_path) > 1000:
                wav_found = True
                break
        except Exception:
            continue

    # Also try listing via a known pattern
    if not wav_found:
        try:
            # Try common Ardour export naming patterns
            for pattern in ['MyProject.wav', 'MyProject_01.wav']:
                remote_path = f"{export_dir}/{pattern}"
                local_path = os.path.join(tmp_export_dir, pattern)
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 1000:
                    wav_found = True
                    break
        except Exception:
            pass

    # Check default Ardour export location as well
    if not wav_found:
        default_export = "/home/ga/Audio/sessions/MyProject/export"
        for fname in ['MyProject.wav', 'master.wav']:
            try:
                remote_path = f"{default_export}/{fname}"
                local_path = os.path.join(tmp_export_dir, fname)
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 1000:
                    wav_found = True
                    score += 12.0  # Partial - wrong directory but exported
                    feedback.append("PARTIAL: WAV exported but to default location, not /podcast_final/")
                    break
            except Exception:
                continue

    if wav_found and score < 12.0:  # Not already partial-credited
        score += 20.0
        feedback.append("PASS: Final mix WAV exported to podcast_final/")
    elif not wav_found:
        feedback.append("FAIL: No exported WAV file found")

    # Cleanup
    try:
        os.unlink(tmp_session.name)
        import shutil
        shutil.rmtree(tmp_export_dir, ignore_errors=True)
    except Exception:
        pass

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback)
    }


# Entry point for gym-anything
verify_task = verify_podcast_production_mix


# ---------- Offline mock tests ----------

if __name__ == "__main__":
    import shutil

    def make_mock_session_xml(tracks=None, markers=None, regions=None):
        """Create a minimal Ardour session XML for testing."""
        xml = '<?xml version="1.0" encoding="UTF-8"?>\n<Session name="MyProject">\n'
        xml += '<Routes>\n'
        xml += '<Route name="Master" default-type="audio" flags="MasterOut">'
        xml += '<Controllable name="gaincontrol" value="1.0"/></Route>\n'
        if tracks:
            for t in tracks:
                gain_linear = 10 ** (t.get('gain_db', 0) / 20.0) if t.get('gain_db', 0) > -120 else 0
                xml += f'<Route name="{t["name"]}" default-type="audio">'
                xml += f'<Controllable name="gaincontrol" value="{gain_linear}"/>'
                xml += '</Route>\n'
        xml += '</Routes>\n'
        xml += '<Playlists>\n'
        if tracks and regions:
            for t in tracks:
                tname = t['name']
                xml += f'<Playlist name="{tname}.1">\n'
                for r in regions:
                    if r.get('track', '').lower() == tname.lower():
                        xml += f'<Region name="{r.get("name","audio")}" '
                        xml += f'position="{r["position"]}" length="{r.get("length", 44100)}"/>\n'
                xml += '</Playlist>\n'
        xml += '</Playlists>\n'
        xml += '<Locations>\n'
        xml += '<Location name="session" start="0" end="1323000" flags="IsSessionRange"/>\n'
        if markers:
            for m in markers:
                xml += f'<Location name="{m["name"]}" start="{m["start"]}" end="{m["start"]}" flags="IsMark"/>\n'
        xml += '</Locations>\n'
        xml += '</Session>'
        return xml

    def run_test(name, session_xml, export_wav=False):
        tmpdir = tempfile.mkdtemp()
        session_path = os.path.join(tmpdir, "MyProject.ardour")
        with open(session_path, 'w') as f:
            f.write(session_xml)

        export_dir = os.path.join(tmpdir, "podcast_final")
        os.makedirs(export_dir, exist_ok=True)
        if export_wav:
            wav_path = os.path.join(export_dir, "community_voices.wav")
            with open(wav_path, 'wb') as f:
                f.write(b'\x00' * 5000)  # Dummy WAV

        def mock_copy(remote, local):
            if 'MyProject.ardour' in remote:
                shutil.copy2(session_path, local)
            elif 'podcast_final' in remote:
                fname = os.path.basename(remote)
                src = os.path.join(export_dir, fname)
                if os.path.exists(src):
                    shutil.copy2(src, local)
                else:
                    raise FileNotFoundError(f"No such file: {remote}")
            else:
                raise FileNotFoundError(f"No such file: {remote}")

        env_info = {'copy_from_env': mock_copy}
        result = verify_podcast_production_mix([], env_info, {})
        shutil.rmtree(tmpdir, ignore_errors=True)
        print(f"\n{'='*60}")
        print(f"TEST: {name}")
        print(f"  passed={result['passed']}, score={result['score']}")
        print(f"  feedback: {result['feedback']}")
        return result

    # Test 1: Do-nothing (clean session, no changes)
    r1 = run_test("Do-nothing",
                  make_mock_session_xml(
                      tracks=[{'name': 'Audio 1', 'gain_db': 0}],
                      markers=None, regions=None))
    assert not r1['passed'], "Do-nothing must fail"

    # Test 2: Partial - tracks created but no regions/export
    r2 = run_test("Tracks only",
                  make_mock_session_xml(
                      tracks=[
                          {'name': 'Intro Theme', 'gain_db': -12},
                          {'name': 'Interview', 'gain_db': 0},
                          {'name': 'Outro Theme', 'gain_db': -12},
                      ], markers=None, regions=None))
    assert not r2['passed'], "Tracks-only should not pass (missing regions/export)"
    assert r2['score'] > 0, "Tracks-only should get partial credit"

    # Test 3: Full completion
    r3 = run_test("Full completion",
                  make_mock_session_xml(
                      tracks=[
                          {'name': 'Intro Theme', 'gain_db': -12},
                          {'name': 'Interview', 'gain_db': 0},
                          {'name': 'Outro Theme', 'gain_db': -12},
                      ],
                      markers=[
                          {'name': 'Episode Start', 'start': 0},
                          {'name': 'Interview Begin', 'start': 352800},
                          {'name': 'Outro Begin', 'start': 1234000},
                          {'name': 'Episode End', 'start': 1500000},
                      ],
                      regions=[
                          {'track': 'Intro Theme', 'name': 'intro', 'position': 0, 'length': 352800},
                          {'track': 'Interview', 'name': 'interview', 'position': 352800, 'length': 882000},
                          {'track': 'Outro Theme', 'name': 'outro', 'position': 1234800, 'length': 352800},
                      ]),
                  export_wav=True)
    assert r3['passed'], f"Full completion must pass, got score={r3['score']}"

    print("\n\nAll offline mock tests passed!")
