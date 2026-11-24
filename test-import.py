import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent

class ImportTests(unittest.TestCase):
    def run_helper(self, picker=0, nmcli=0, path='/tmp/profile with spaces.ovpn'):
        with tempfile.TemporaryDirectory() as temp:
            d = Path(temp)
            (d / 'omarchy').write_text('#!/bin/bash\nprintf "%s" "$PICKED_PATH"\nexit "$PICKER_STATUS"\n')
            (d / 'nmcli').write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$CALL_LOG"\nif (( NMCLI_STATUS )); then echo "missing OpenVPN support" >&2; fi\nexit "$NMCLI_STATUS"\n')
            for p in d.iterdir(): p.chmod(0o755)
            env = dict(os.environ, PATH=f'{temp}:'+os.environ['PATH'], PICKED_PATH=path,
                       PICKER_STATUS=str(picker), NMCLI_STATUS=str(nmcli), CALL_LOG=str(d/'calls'))
            r = subprocess.run(['bash', str(ROOT/'import-profile')], env=env, capture_output=True, text=True)
            calls = (d/'calls').read_text().splitlines() if (d/'calls').exists() else None
            return r, calls

    def test_import_preserves_path(self):
        r, calls = self.run_helper()
        self.assertEqual(r.returncode, 0)
        self.assertEqual(calls, ['connection', 'import', 'type', 'openvpn', 'file', '/tmp/profile with spaces.ovpn'])

    def test_cancel_is_quiet(self):
        r, calls = self.run_helper(picker=1, path='')
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr, '')
        self.assertIsNone(calls)

    def test_chooser_failure(self):
        r, calls = self.run_helper(picker=2)
        self.assertEqual(r.returncode, 2)
        self.assertIn('picker', r.stderr)
        self.assertIsNone(calls)

    def test_empty_selection_is_error(self):
        r, calls = self.run_helper(path='')
        self.assertEqual(r.returncode, 2)
        self.assertIsNone(calls)

    def test_nmcli_failure_is_not_cancel(self):
        r, _ = self.run_helper(nmcli=1)
        self.assertEqual(r.returncode, 2)
        self.assertIn('missing OpenVPN support', r.stderr)

    def test_error_lifecycle(self):
        source = (ROOT/'OpenVpnService.qml').read_text()
        def function(name):
            start = source.index('  function '+name+'(')
            end = source.index('\n  }', start)+4
            return source[start:end]
        script = '\n'.join(function(n) for n in ['boundedText', 'setError', 'finalizeImport', 'finalizeList'])
        script += '''
const assert = require('node:assert/strict');
let lastError='', errorSource='', importExitCode=null, importStreamFinished=false, importOutput='missing OpenVPN support';
let refreshDelay={restart(){}}, listExitCode=0, listStreamFinished=true, nmcliAvailable=false, profiles=[], listOutput='';
function parseProfiles(){return []} function refreshDetails(){}
for (const exitFirst of [true, false]) {
  setError(''); importExitCode=null; importStreamFinished=false;
  if(exitFirst) importExitCode=2; else importStreamFinished=true;
  finalizeImport(); assert.equal(lastError, '');
  importExitCode=2; importStreamFinished=true; finalizeImport();
  assert.equal(lastError, 'missing OpenVPN support');
  finalizeList(); assert.equal(lastError, 'missing OpenVPN support');
}
importOutput=''; importExitCode=2; finalizeImport(); assert.match(lastError,/Could not import/);
for(const code of [0,1]) {importExitCode=code; finalizeImport(); assert.equal(lastError,'');}
setError('inventory failed','inventory'); finalizeList(); assert.equal(lastError,'');
'''
        subprocess.run(['node', '-e', script], check=True)

if __name__ == '__main__': unittest.main()
