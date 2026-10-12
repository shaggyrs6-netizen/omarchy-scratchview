#!/usr/bin/env python3
"""ScratchView: local IPC, explicit window moves and no shell evaluation."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
import time

SCRATCH = 'special:scratchpad'
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'omarchy-scratchview'
SESSION = hashlib.sha256(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '').encode()).hexdigest()[:16]
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))) / 'omarchy-scratchview'

def read_json(path, fallback):
    try:
        if path.stat().st_size > 65536:
            return fallback
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback

def write_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.scratchview-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as file:
            json.dump(value, file)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

def hypr(*args, json_output=False):
    result = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=4, check=True)
    if json_output:
        return json.loads(result.stdout)
    if result.stdout.strip() != 'ok':
        raise RuntimeError(result.stdout.strip()[:180] or 'Window action failed')

def identity(client):
    value = [client.get('pid'), client.get('initialClass'), client.get('initialTitle')]
    return hashlib.sha256(json.dumps(value).encode()).hexdigest()

def cards(clients, leases):
    result = []
    for client in clients:
        address = client.get('address', '')
        if not re.fullmatch(r'0x[0-9a-fA-F]+', address) or not client.get('mapped', False):
            continue
        parked = client.get('workspace', {}).get('name') == SCRATCH
        borrowed = leases.get(address) == identity(client)
        if parked or borrowed:
            result.append({'address': address, 'title': client.get('title', '')[:250],
                           'app': client.get('class', '')[:100], 'parked': parked,
                           'identity': identity(client)})
    # Moving a window must not reshuffle its card.
    return sorted(result, key=lambda c: (c['app'], c['address']))

def candidates(clients):
    return [{'address': c['address'], 'identity': identity(c),
             'title': c.get('title', '')[:250], 'app': c.get('class', '')[:100],
             'workspace': c['workspace'].get('name', '')}
            for c in clients if c.get('mapped') and c.get('workspace', {}).get('id', 0) > 0
            and re.fullmatch(r'0x[0-9a-fA-F]+', c.get('address', ''))]

def action(verb, address, clients, leases, workspace, dispatch, expected=None):
    if verb not in ('bring', 'return', 'dismiss', 'park', 'focus') or not re.fullmatch(r'0x[0-9a-fA-F]+', address):
        raise ValueError('Invalid action or window address')
    client = next((c for c in clients if c.get('address') == address and c.get('mapped')), None)
    if not client:
        raise ValueError('That window has closed')
    if expected is not None and expected != identity(client):
        raise ValueError('That window has changed; choose it again')
    parked = client.get('workspace', {}).get('name') == SCRATCH
    if verb == 'park':
        if expected is None or client.get('workspace', {}).get('id', 0) <= 0:
            raise ValueError('Choose a normal desktop window from the parking list')
        dispatch('dispatch', f'hl.dsp.window.move({{ window = "address:{address}", workspace = "{SCRATCH}", follow = false }})')
        leases.pop(address, None)
        return leases
    if not parked and leases.get(address) != identity(client):
        raise ValueError('Window is not managed by ScratchView')
    if verb == 'focus':
        if parked:
            raise ValueError('That window is parked; use Bring here')
        dispatch('dispatch', f'hl.dsp.focus({{ window = "address:{address}" }})')
    elif verb == 'dismiss':
        if parked:
            raise ValueError('Parked windows cannot be dismissed; retrieve the window first')
        leases.pop(address, None)
    elif verb == 'return':
        if not parked:
            dispatch('dispatch', f'hl.dsp.window.move({{ window = "address:{address}", workspace = "{SCRATCH}", follow = false }})')
        leases.pop(address, None)
    else:
        if not isinstance(workspace, int) or workspace <= 0:
            raise ValueError('Select a normal workspace first')
        dispatch('dispatch', f'hl.dsp.window.move({{ window = "address:{address}", workspace = "{workspace}", follow = false }})')
        leases[address] = identity(client)
        # The move is recorded by the caller even if focus fails.
    return leases

def geometry(value):
    if not isinstance(value, dict):
        value = {}
    def number(key, default, low, high):
        try:
            return max(low, min(high, int(value.get(key, default))))
        except (ValueError, TypeError, OverflowError):
            return default
    return {'x': number('x', 40, 0, 16000), 'y': number('y', 90, 0, 16000),
            'width': number('width', 360, 200, 1000), 'height': number('height', 660, 240, 1400)}

def settings(value):
    mode = value.get('displayMode') if isinstance(value, dict) else None
    view = value.get('viewMode') if isinstance(value, dict) else None
    return {'displayMode': mode if mode in ('preview', 'compact') else 'preview',
            'viewMode': view if view in ('panel', 'bar') else 'panel'}

def undo_card(record, clients, now=None):
    if not isinstance(record, dict) or not isinstance(record.get('until'), (int, float)):
        return None
    if record['until'] < (time.time() if now is None else now):
        return None
    return next((c for c in clients if c.get('mapped') and c.get('address') == record.get('address')
                 and identity(c) == record.get('identity') and c.get('workspace', {}).get('name') != SCRATCH), None)

def theme():
    palette = {}
    try:
        palette = tomllib.loads((Path.home() / '.local/state/omarchy/current/theme/colors.toml').read_text())
    except (OSError, ValueError):
        pass
    defaults = {'background': '#171723', 'foreground': '#f3f0e9', 'accent': '#2dd4bf', 'muted': '#a8a8b8'}
    return {key: palette.get(key) if re.fullmatch(r'#[0-9a-fA-F]{6}', str(palette.get(key, ''))) else default
            for key, default in defaults.items()}

def main():
    os.umask(0o077)
    verb = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if verb == 'settings':
        value = json.loads(sys.argv[2])
        allowed = {'displayMode': ('preview', 'compact'), 'viewMode': ('panel', 'bar')}
        if not isinstance(value, dict) or not value or any(k not in allowed or v not in allowed[k] for k,v in value.items()):
            raise ValueError('Unknown display setting')
        STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (STATE / 'settings.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            merged = settings(read_json(STATE / 'settings.json', {}))
            merged.update(value)
            write_json(STATE / 'settings.json', merged)
        print(json.dumps({'ok': True}))
        return
    if verb == 'geometry':
        write_json(STATE / 'geometry.json', geometry(json.loads(sys.argv[2])))
        print(json.dumps({'ok': True}))
        return
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    with (RUNTIME / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = RUNTIME / (SESSION + '.json')
        leases = read_json(path, {})
        if not isinstance(leases, dict):
            leases = {}
        clients = hypr('clients', '-j', json_output=True)
        undo_path = RUNTIME / (SESSION + '-undo.json')
        undo_record = read_json(undo_path, {})
        previous = leases
        leases = {c['address']: leases[c['address']] for c in clients
                  if c.get('address') in leases and leases[c['address']] == identity(c)}
        if previous != leases:
            write_json(path, leases)
        if verb == 'undo':
            restored = undo_card(undo_record, clients)
            if not restored:
                raise ValueError('Undo is no longer available')
            leases[restored['address']] = identity(restored)
            write_json(path, leases)
            write_json(undo_path, {})
            undo_record = {}
        elif verb in ('bring', 'return', 'dismiss', 'park', 'focus'):
            workspace = hypr('activeworkspace', '-j', json_output=True).get('id') if verb == 'bring' else None
            expected = sys.argv[3] if len(sys.argv) > 3 else None
            leases = action(verb, sys.argv[2], clients, leases, workspace, hypr, expected)
            write_json(path, leases)
            if verb == 'dismiss':
                dismissed = next(c for c in clients if c['address'] == sys.argv[2])
                undo_record = {'address': dismissed['address'], 'identity': identity(dismissed), 'until': time.time() + 20}
                write_json(undo_path, undo_record)
            if verb == 'bring':
                hypr('dispatch', f'hl.dsp.focus({{ window = "address:{sys.argv[2]}" }})')
            clients = hypr('clients', '-j', json_output=True)
        elif verb not in ('status', 'picker'):
            raise ValueError('Unknown command')
        result = {'ok': True, 'cards': cards(clients, leases), 'theme': theme(),
                          'geometry': geometry(read_json(STATE / 'geometry.json', {})),
                          'settings': settings(read_json(STATE / 'settings.json', {})),
                          'undoAvailable': undo_card(undo_record, clients) is not None}
        if verb == 'picker':
            result['candidates'] = candidates(clients)
        print(json.dumps(result))

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'ok': False, 'error': str(exc)[:240]}))
        sys.exit(1)
