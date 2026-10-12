#!/usr/bin/env python3
"""Restore this installed ScratchView panel; never restart the desktop shell."""
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent

def restore(target='restore'):
    if target not in ('restore', 'parkPicker', 'settings'):
        raise ValueError('Unknown panel action')
    command = ['quickshell', 'ipc', '-p', str(ROOT), 'call', 'scratchview', target]
    result = subprocess.run(command, capture_output=True, timeout=3)
    if result.returncode == 0:
        return
    env = dict(os.environ, SCRATCHVIEW_RESTORE='1')
    subprocess.run(['quickshell', '-p', str(ROOT), '-n', '-d'], env=env,
                   capture_output=True, timeout=8, check=True)
    for _ in range(20):
        result = subprocess.run(command, capture_output=True, timeout=3)
        if result.returncode == 0:
            return
        time.sleep(0.1)
    raise RuntimeError('ScratchView did not become ready')

if __name__ == '__main__':
    try:
        restore(sys.argv[1] if len(sys.argv) > 1 else 'restore')
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
