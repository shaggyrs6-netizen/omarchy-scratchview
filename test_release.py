import importlib.util
import json
from pathlib import Path
import tempfile
import shutil
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parent

class ReleaseTests(unittest.TestCase):
    def test_manifest_and_portable_paths(self):
        manifest = json.loads((ROOT / 'manifest.json').read_text())
        self.assertEqual(manifest['id'], 'shaggyrs6.scratchview')
        self.assertEqual(manifest['name'], 'Omarchy ScratchView')
        self.assertTrue((ROOT / manifest['entryPoints']['barWidget']).is_file())
        source = (ROOT / 'BarWidget.qml').read_text()
        self.assertIn("Qt.resolvedUrl('.')", source)
        for name in ('BarWidget.qml', 'shell.qml', 'control.py', 'backend.py'):
            self.assertNotIn('/home/shaggyrs6', (ROOT / name).read_text())

    def test_controller_relocates_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix='scratchview release ') as directory:
            target = Path(directory) / 'control.py'
            shutil.copy2(ROOT / 'control.py', target)
            spec = importlib.util.spec_from_file_location('relocated_control', target)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            with patch.object(module.subprocess, 'run', return_value=Mock(returncode=0)) as run:
                module.restore('settings')
                self.assertEqual(run.call_args.args[0], ['quickshell', 'ipc', '-p', directory, 'call', 'scratchview', 'settings'])

    def test_controller_launch_is_scoped(self):
        import control
        with patch.object(control.subprocess, 'run', side_effect=[Mock(returncode=1), Mock(returncode=0), Mock(returncode=0)]) as run:
            control.restore()
            self.assertEqual(run.call_args_list[1].args[0], ['quickshell', '-p', str(ROOT), '-n', '-d'])
            self.assertEqual(run.call_args_list[1].kwargs['env']['SCRATCHVIEW_RESTORE'], '1')

    def test_invalid_controller_action_refused(self):
        import control
        with patch.object(control.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                control.restore('quit-all')
            run.assert_not_called()
