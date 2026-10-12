import unittest
from unittest.mock import Mock
import backend as b

def client(address='0xabc', workspace=b.SCRATCH, pid=42):
    return dict(address=address, mapped=True, pid=pid, initialClass='test', initialTitle='demo',
                title='Demo', **{'class': 'test'}, workspace={'name': workspace})

class Tests(unittest.TestCase):
    def test_only_existing_scratchpad(self):
        self.assertEqual(len(b.cards([client(), client('0xdef','special:other'), client('0x123','1')], {})),1)

    def test_borrowed_window_remains_visible(self):
        c = client(workspace='1')
        self.assertFalse(b.cards([c],{'0xabc':b.identity(c)})[0]['parked'])

    def test_reused_address_not_owned(self):
        old = client(workspace='1')
        self.assertEqual(b.cards([client(workspace='1',pid=99)], {'0xabc':b.identity(old)}), [])

    def test_bring_only_explicit_address(self):
        dispatch = Mock()
        leases = b.action('bring','0xabc',[client()],{},2,dispatch)
        self.assertIn('0xabc',leases)
        self.assertIn('window = "address:0xabc"', dispatch.call_args.args[1])
        self.assertIn('workspace = "2"', dispatch.call_args.args[1])

    def test_return_uses_same_scratchpad(self):
        c = client(workspace='1'); dispatch = Mock()
        self.assertEqual(b.action('return','0xabc',[c],{'0xabc':b.identity(c)},1,dispatch),{})
        self.assertIn('special:scratchpad',dispatch.call_args.args[1])

    def test_arbitrary_window_refused(self):
        with self.assertRaises(ValueError):
            b.action('return','0xabc',[client(workspace='1')],{},1,Mock())

    def test_injection_refused(self):
        for address in ['0xabc;exit', '"})', 'all', '', 'address:0xabc']:
            with self.assertRaises(ValueError):
                b.action('bring',address,[client()],{},1,Mock())

    def test_non_normal_destination_refused(self):
        with self.assertRaises(ValueError):
            b.action('bring','0xabc',[client()],{},-99,Mock())

    def test_closed_window_refused(self):
        with self.assertRaises(ValueError):
            b.action('bring','0xabc',[],{},1,Mock())

    def test_failed_move_does_not_claim_window(self):
        leases = {}
        with self.assertRaises(RuntimeError):
            b.action('bring','0xabc',[client()],leases,1,Mock(side_effect=RuntimeError('fail')))
        self.assertEqual(leases,{})

    def test_portrait_defaults_and_bounds(self):
        default = b.geometry({})
        self.assertLess(default['width'],default['height'])
        self.assertEqual(b.geometry({'width':-1,'height':99999})['width'],200)
        self.assertEqual(b.geometry({'height':99999})['height'],1400)
        self.assertEqual(b.geometry({'width':'invalid'})['width'],360)

    def test_no_title_in_saved_identity(self):
        self.assertNotIn('demo',b.identity(client()))

    def test_dismiss_does_not_dispatch_or_remove_other_cards(self):
        c = client(workspace='1'); other = client('0xdef', workspace='2')
        leases = {'0xabc': b.identity(c), '0xdef': b.identity(other)}
        dispatch = Mock()
        result = b.action('dismiss', '0xabc', [c, other], leases, None, dispatch)
        self.assertEqual(result, {'0xdef': b.identity(other)})
        self.assertEqual([x['address'] for x in b.cards([c,other],result)], ['0xdef'])
        self.assertEqual(c['workspace']['name'], '1')
        dispatch.assert_not_called()

    def test_dismissed_card_reappears_when_parked_again(self):
        c = client(workspace='1'); dispatch = Mock()
        leases = b.action('dismiss', '0xabc', [c], {'0xabc':b.identity(c)}, None, dispatch)
        self.assertEqual(b.cards([c],leases), [])
        c['workspace']['name'] = b.SCRATCH
        self.assertTrue(b.cards([c], leases)[0]['parked'])
        dispatch.assert_not_called()

    def test_parked_card_cannot_be_dismissed(self):
        c = client(); leases = {'0xabc': b.identity(c)}; dispatch = Mock()
        with self.assertRaises(ValueError):
            b.action('dismiss', '0xabc', [c], leases, None, dispatch)
        self.assertIn('0xabc', leases)
        dispatch.assert_not_called()

    def test_unmanaged_or_reused_card_cannot_be_dismissed(self):
        c = client(workspace='1'); dispatch = Mock()
        for leases in ({}, {'0xabc': b.identity(client(pid=99))}):
            with self.assertRaises(ValueError):
                b.action('dismiss', '0xabc', [c], leases, None, dispatch)
        dispatch.assert_not_called()

    def test_dismiss_command_persists_without_window_commands(self):
        import contextlib
        import io
        import json
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        c = client(workspace='1')
        with tempfile.TemporaryDirectory() as folder:
            runtime = Path(folder) / 'runtime'
            ledger = runtime / (b.SESSION + '.json')
            b.write_json(ledger, {'0xabc': b.identity(c)})
            def only_clients(*args, **kwargs):
                self.assertEqual(args, ('clients', '-j'))
                return [c]
            output = io.StringIO()
            with patch.object(b, 'RUNTIME', runtime), patch.object(b, 'STATE', Path(folder) / 'state'), \
                 patch.object(b, 'hypr', side_effect=only_clients), patch.object(b, 'theme', return_value={}), \
                 patch.object(b.sys, 'argv', ['backend.py', 'dismiss', '0xabc']), \
                 patch.object(b.os, 'umask'), contextlib.redirect_stdout(output):
                b.main()
            self.assertEqual(b.read_json(ledger, None), {})
            result = json.loads(output.getvalue())
            self.assertTrue(result['ok'])
            self.assertEqual(result['cards'], [])

    def test_display_modes(self):
        self.assertEqual(b.settings({})['displayMode'], 'preview')
        self.assertEqual(b.settings({'displayMode':'compact'})['displayMode'], 'compact')
        self.assertEqual(b.settings({'displayMode':'wrong'})['displayMode'], 'preview')
        self.assertEqual(b.settings(None)['displayMode'], 'preview')

    def test_view_mode_defaults_and_validation(self):
        self.assertEqual(b.settings({})['viewMode'], 'panel')
        self.assertEqual(b.settings({'viewMode':'bar'})['viewMode'], 'bar')
        self.assertEqual(b.settings({'viewMode':'bad'})['viewMode'], 'panel')

    def test_parking_requires_current_picker_identity(self):
        c = client(workspace='1'); c['workspace']['id'] = 1
        dispatch = Mock()
        for token in (None, 'old-identity'):
            with self.assertRaises(ValueError):
                b.action('park','0xabc',[c],{},None,dispatch,token)
        dispatch.assert_not_called()
        b.action('park','0xabc',[c],{},None,dispatch,b.identity(c))
        self.assertIn('special:scratchpad',dispatch.call_args.args[1])
        self.assertIn('address:0xabc',dispatch.call_args.args[1])

    def test_picker_excludes_special_and_unmapped(self):
        normal = client(workspace='2'); normal['workspace']['id'] = 2
        hidden = client('0xdef'); hidden['workspace']['id'] = -99
        unmapped = dict(normal, address='0x123', mapped=False)
        self.assertEqual([c['address'] for c in b.candidates([normal,hidden,unmapped])], ['0xabc'])

    def test_other_special_workspace_cannot_be_parked(self):
        c = client(workspace='special:other'); c['workspace']['id'] = -98
        dispatch = Mock()
        with self.assertRaises(ValueError):
            b.action('park','0xabc',[c],{},None,dispatch,b.identity(c))
        dispatch.assert_not_called()

    def test_focus_never_moves_on_desktop_card(self):
        c = client(workspace='2'); dispatch = Mock()
        b.action('focus','0xabc',[c],{'0xabc':b.identity(c)},None,dispatch)
        self.assertIn('hl.dsp.focus',dispatch.call_args.args[1])
        self.assertNotIn('move',dispatch.call_args.args[1])

    def test_card_order_does_not_follow_park_state(self):
        a = client(); z = client('0xdef',workspace='2')
        leases = {c['address']: b.identity(c) for c in [a,z]}
        before = [c['address'] for c in b.cards([a,z],leases)]
        a['workspace']['name'] = '1'; z['workspace']['name'] = b.SCRATCH
        self.assertEqual(before, [c['address'] for c in b.cards([a,z],leases)])

    def test_undo_expiry_closed_reused_and_parked_guards(self):
        c = client(workspace='1')
        record = {'address':'0xabc','identity':b.identity(c),'until':100}
        self.assertIs(b.undo_card(record,[c],90),c)
        self.assertIsNone(b.undo_card(record,[c],101))
        self.assertIsNone(b.undo_card(record,[],90))
        self.assertIsNone(b.undo_card(record,[client(workspace='1',pid=99)],90))
        self.assertIsNone(b.undo_card(record,[client()],90))

    def test_partial_settings_keep_other_choice(self):
        import contextlib, io, tempfile
        from pathlib import Path
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder)
            b.write_json(state/'settings.json', {'displayMode':'compact','viewMode':'panel'})
            with patch.object(b,'STATE',state), patch.object(b.sys,'argv',['backend.py','settings','{"viewMode":"bar"}']), \
                 patch.object(b.os,'umask'), contextlib.redirect_stdout(io.StringIO()):
                b.main()
            self.assertEqual(b.read_json(state/'settings.json',{}), {'displayMode':'compact','viewMode':'bar'})

    def test_dismiss_and_undo_roundtrip_never_moves_window(self):
        import contextlib, io, json, tempfile
        from pathlib import Path
        from unittest.mock import patch
        c = client(workspace='1')
        with tempfile.TemporaryDirectory() as folder:
            runtime = Path(folder)/'runtime'
            ledger = runtime/(b.SESSION+'.json')
            b.write_json(ledger, {'0xabc':b.identity(c)})
            def only_clients(*args, **kwargs):
                self.assertEqual(args, ('clients','-j'))
                return [c]
            for verb, expected_count in [('dismiss',0),('undo',1)]:
                output = io.StringIO()
                with patch.object(b,'RUNTIME',runtime), patch.object(b,'STATE',Path(folder)/'state'), \
                     patch.object(b,'hypr',side_effect=only_clients), patch.object(b,'theme',return_value={}), \
                     patch.object(b.sys,'argv',['backend.py',verb,'0xabc']), patch.object(b.os,'umask'), \
                     contextlib.redirect_stdout(output):
                    b.main()
                result = json.loads(output.getvalue())
                self.assertEqual(len(result['cards']), expected_count)
                self.assertEqual(result['undoAvailable'], verb == 'dismiss')
            self.assertEqual(b.read_json(ledger,{}), {'0xabc':b.identity(c)})

    def test_settings_persist_separately_from_geometry(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            b.write_json(path / 'geometry.json', b.geometry({'width': 210}))
            b.write_json(path / 'settings.json', b.settings({'displayMode':'compact'}))
            self.assertEqual(b.read_json(path / 'settings.json', {})['displayMode'], 'compact')
            self.assertEqual(b.read_json(path / 'geometry.json', {})['width'], 210)

if __name__ == '__main__':
    unittest.main()
