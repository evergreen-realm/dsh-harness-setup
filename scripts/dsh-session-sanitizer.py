#!/usr/bin/env python3
"""
dsh-session-sanitizer.py — Fixes the recurring SessionFormatError in DeepSeek Harness.

DSH writes system/message events mid-session during normal operation, but its own
history replay validator rejects them with:
  "SessionFormatError: system/message requires a protected first surface head"

This script replaces any mid-session system/message events with ignorable
custom/context-sync events, preserving the multi-frame zstd structure.

Usage:
  python dsh-session-sanitizer.py                    # Fix all sessions
  python dsh-session-sanitizer.py <session-id>       # Fix specific session
  python dsh-session-sanitizer.py --check             # Dry run, report only

Place in: ~/.dsh/scripts/dsh-session-sanitizer.py
"""

import json, os, sys, shutil

try:
    import zstandard
except ImportError:
    print("Installing zstandard...")
    import subprocess
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'zstandard', '-q'])
    import zstandard

import io

DSH_SESSIONS = os.path.join(os.path.expanduser('~'), '.dsh', 'sessions')
PROJCACHE = os.path.join(os.path.expanduser('~'), '.dsh', 'storages', 'session_projcache', 'sessions')
ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'


def find_all_sessions():
    """Find all session.v4.jsonl.zstd files."""
    sessions = []
    if not os.path.isdir(DSH_SESSIONS):
        return sessions
    for workspace in os.listdir(DSH_SESSIONS):
        ws_path = os.path.join(DSH_SESSIONS, workspace)
        if not os.path.isdir(ws_path):
            continue
        for session in os.listdir(ws_path):
            log = os.path.join(ws_path, session, 'session.v4.jsonl.zstd')
            if os.path.exists(log):
                sessions.append((session, log))
    return sessions


def decompress_streaming(raw):
    """Decompress multi-frame zstd data."""
    dctx = zstandard.ZstdDecompressor()
    reader = dctx.stream_reader(io.BytesIO(raw))
    chunks = []
    while True:
        chunk = reader.read(65536)
        if not chunk:
            break
        chunks.append(chunk)
    return b''.join(chunks)


def get_frame_structure(raw):
    """Map events to their original zstd frames."""
    offsets = []
    pos = 0
    while True:
        idx = raw.find(ZSTD_MAGIC, pos)
        if idx == -1:
            break
        offsets.append(idx)
        pos = idx + 1
    
    boundaries = offsets + [len(raw)]
    frame_events = []
    cumulative = 0
    
    for i in range(len(offsets)):
        chunk = raw[offsets[i]:boundaries[i + 1]]
        try:
            d = zstandard.ZstdDecompressor()
            decompressed = d.decompress(chunk, max_output_size=50 * 1024 * 1024)
            lines = decompressed.decode('utf-8', errors='replace').strip().split('\n')
            non_empty = [l for l in lines if l.strip()]
            frame_events.append((cumulative, len(non_empty)))
            cumulative += len(non_empty)
        except:
            frame_events.append((cumulative, 0))
    
    return frame_events


def check_session(log_path):
    """Check a session for system/message violations. Returns list of (line, seq)."""
    with open(log_path, 'rb') as f:
        raw = f.read()
    
    data = decompress_streaming(raw)
    lines = data.decode('utf-8', errors='replace').strip().split('\n')
    
    first_surface_seq = None
    violations = []
    
    for i, line in enumerate(lines):
        try:
            evt = json.loads(line)
            t = evt.get('type')
            seq = evt.get('seq')
            
            if t in ('user/message', 'assistant/message') and first_surface_seq is None:
                first_surface_seq = seq
            
            if t == 'system/message' and first_surface_seq is not None:
                if seq is not None and seq > first_surface_seq:
                    violations.append((i, seq))
        except:
            pass
    
    return violations


def fix_session(log_path, dry_run=False):
    """Fix system/message violations in a session file."""
    with open(log_path, 'rb') as f:
        raw = f.read()
    
    data = decompress_streaming(raw)
    lines = data.decode('utf-8', errors='replace').strip().split('\n')
    frame_structure = get_frame_structure(raw)
    
    # Find violations
    first_surface_seq = None
    fixes = []
    
    for i, line in enumerate(lines):
        try:
            evt = json.loads(line)
            t = evt.get('type')
            seq = evt.get('seq')
            
            if t in ('user/message', 'assistant/message') and first_surface_seq is None:
                first_surface_seq = seq
            
            if t == 'system/message' and first_surface_seq is not None:
                if seq is not None and seq > first_surface_seq:
                    fixes.append((i, seq, evt))
        except:
            pass
    
    if not fixes:
        return 0
    
    if dry_run:
        return len(fixes)
    
    # Apply fixes
    for line_idx, seq, orig_evt in fixes:
        replacement = {
            "type": "custom/context-sync",
            "seq": seq,
            "time": orig_evt.get("time", 0),
            "data": {},
            "ignorable": True
        }
        lines[line_idx] = json.dumps(replacement, separators=(',', ':'))
    
    # Recompress preserving frame structure
    cctx = zstandard.ZstdCompressor(level=3)
    output_frames = []
    
    for start_event, n_events in frame_structure:
        if n_events == 0:
            continue
        frame_lines = lines[start_event:start_event + n_events]
        frame_text = '\n'.join(frame_lines) + '\n'
        compressed = cctx.compress(frame_text.encode('utf-8'))
        output_frames.append(compressed)
    
    output_data = b''.join(output_frames)
    
    # Backup and write
    backup = log_path + '.pre-sanitize-bak'
    if not os.path.exists(backup):  # only keep first backup
        shutil.copy2(log_path, backup)
    
    with open(log_path, 'wb') as f:
        f.write(output_data)
    
    # Delete projcache to force rebuild
    session_id = os.path.basename(os.path.dirname(log_path))
    cache_file = os.path.join(PROJCACHE, f'{session_id}.json')
    if os.path.exists(cache_file):
        os.remove(cache_file)
    
    return len(fixes)


def main():
    dry_run = '--check' in sys.argv
    specific_id = None
    
    for arg in sys.argv[1:]:
        if not arg.startswith('--'):
            specific_id = arg
            if not specific_id.startswith('session-'):
                specific_id = f'session-{specific_id}'
    
    sessions = find_all_sessions()
    if specific_id:
        sessions = [(sid, path) for sid, path in sessions if sid == specific_id]
    
    if not sessions:
        print("No sessions found.")
        return
    
    total_fixed = 0
    for sid, path in sessions:
        violations = check_session(path)
        if violations:
            if dry_run:
                print(f"  WOULD FIX {sid}: {len(violations)} system/message violation(s) at seq {[v[1] for v in violations]}")
                total_fixed += len(violations)
            else:
                n = fix_session(path)
                if n:
                    print(f"  FIXED {sid}: {n} system/message violation(s)")
                    total_fixed += n
    
    if total_fixed == 0:
        print("All sessions clean.")
    else:
        action = "would fix" if dry_run else "fixed"
        print(f"\n{action.title()} {total_fixed} violation(s) across {len(sessions)} session(s).")
        if not dry_run:
            print("Restart DeepSeek Harness to load repaired sessions.")


if __name__ == '__main__':
    main()
