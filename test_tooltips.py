"""Regression: real Qt tooltip with HTML image title must make zero requests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import threading
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent

class TooltipTests(unittest.TestCase):
    def test_all_variable_tooltip_sinks_are_owned_plain_text(self):
        panel = (ROOT / 'shell.qml').read_text()
        bar = (ROOT / 'BarWidget.qml').read_text()
        tooltip = (ROOT / 'PlainToolTip.qml').read_text()
        self.assertIn('textFormat: Text.PlainText', tooltip)
        self.assertIn('text: tip.text', tooltip)
        self.assertIn('PlainToolTip {', panel)
        self.assertIn('PlainToolTip {', bar)
        for line in panel.splitlines():
            if 'ToolTip.text:' in line:
                self.assertNotIn('card.', line)
                self.assertNotIn('modelData', line)
        for line in bar.splitlines():
            if 'tooltipText:' in line:
                expression = line.split('tooltipText:', 1)[1].split(';', 1)[0]
                self.assertNotIn('modelData', expression)
                self.assertNotIn('root.launchError ||', expression)

    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell required for Qt rendering test')
    def test_html_title_no_fetch_with_positive_control(self):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(204)
                self.end_headers()
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for unsafe in ('1', '0'):
                requests.clear()
                env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           QT_QUICK_CONTROLS_STYLE='Basic', SCRATCHVIEW_UNSAFE_CONTROL=unsafe,
                           SCRATCHVIEW_TEST_URL=f'http://127.0.0.1:{server.server_port}/tooltip-probe')
                with tempfile.TemporaryDirectory(prefix='scratchview-tooltip-test-') as directory:
                    shutil.copy2(ROOT / 'PlainToolTip.qml', directory)
                    shutil.copy2(ROOT / 'tests/TooltipProbe.qml', Path(directory) / 'shell.qml')
                    result = subprocess.run(['quickshell', '-p', directory],
                                            env=env, capture_output=True, text=True, timeout=12)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn('PLAIN_TEXT_OK', output)
                if unsafe == '1':
                    self.assertIn('/tooltip-probe', requests, 'Unsafe control did not exercise image loading')
                else:
                    self.assertEqual(requests, [], 'Plain tooltip unexpectedly fetched an image')
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
