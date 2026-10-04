"""Read account limits through Codex's supported, authenticated local app server.

No chat is started and no reset is redeemed. Only display fields leave the helper.
"""
import json
import math
import os
import select
import shutil
import signal
import subprocess
import sys
import time


def display_snapshot(result, now=None):
    now = time.time() if now is None else now
    buckets = result.get('rateLimitsByLimitId') or {}
    bucket = buckets.get('codex') or result.get('rateLimits') or {}
    weekly = next((bucket.get(key) for key in ('primary', 'secondary')
                   if (bucket.get(key) or {}).get('windowDurationMins') == 10080), None)
    percent = weekly.get('usedPercent') if weekly else None
    if not isinstance(percent, (int, float)) or not math.isfinite(percent):
        percent = None
    resets = result.get('rateLimitResetCredits') or {}
    details = resets.get('credits')
    available = [c for c in (details or []) if c.get('status') == 'available'
                 and (c.get('expiresAt') is None or c['expiresAt'] > now)]
    return {
        'usedPercent': min(100, max(0, percent)) if percent is not None else None,
        'weeklyResetsAt': weekly.get('resetsAt') if weekly else None,
        'availableCount': resets.get('availableCount'),
        'detailsAvailable': details is not None,
        'resets': sorted([{'id': c['id'], 'expiresAt': c.get('expiresAt')}
                          for c in available], key=lambda c: c['expiresAt'] or float('inf')),
    }


def read_usage():
    executable = shutil.which('codex')
    if not executable:
        raise RuntimeError('Install Codex and sign in with ChatGPT to show your usage.')
    proc = subprocess.Popen([executable, 'app-server'], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        def send(message):
            proc.stdin.write((json.dumps(message) + '\n').encode())
            proc.stdin.flush()
        send({'method': 'initialize', 'id': 0, 'params': {
            'clientInfo': {'name': 'vaulty_usage', 'title': 'Vaulty usage', 'version': '1.0'},
            'capabilities': {'experimentalApi': True}}})
        deadline = time.monotonic() + 25
        buffer = b''
        while time.monotonic() < deadline:
            if not select.select([proc.stdout], [], [], min(1, max(0, deadline - time.monotonic())))[0]:
                continue
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError('Could not connect to Codex. Open Codex and check that you are signed in.')
            buffer += chunk
            if len(buffer) > 1024 * 1024:
                raise RuntimeError('Codex returned an unexpected response.')
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                message = json.loads(line)
                if message.get('id') == 0:
                    if 'error' in message:
                        raise RuntimeError('Your Codex version could not start the usage connection.')
                    send({'method': 'initialized', 'params': {}})
                    send({'method': 'account/rateLimits/read', 'id': 1, 'params': {}})
                elif message.get('id') == 1:
                    if 'error' in message:
                        raise RuntimeError('Could not read usage. Check your ChatGPT sign-in in Codex, then refresh.')
                    return display_snapshot(message['result'])
        raise RuntimeError('Usage refresh timed out. Check your connection and try again.')
    finally:
        if proc.poll() is None:
            proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        proc.stdin.close()
        proc.stdout.close()


if __name__ == '__main__':
    def cancelled(signum, frame):
        raise RuntimeError('Usage refresh cancelled.')
    signal.signal(signal.SIGTERM, cancelled)
    try:
        print(json.dumps(read_usage()))
    except Exception as error:
        # Do not expose raw server messages, tokens, or account identifiers.
        print(str(error) if isinstance(error, RuntimeError) else 'Could not refresh ChatGPT usage.', file=sys.stderr)
        sys.exit(1)
