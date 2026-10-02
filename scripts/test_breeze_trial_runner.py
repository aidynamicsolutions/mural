"""Model-free trial integration checks. Synthetic logs, never phone evidence."""
import json
import tempfile
import sys
from pathlib import Path
import unittest
from verify_device import breeze_trial_contract, breeze_trial_launch, compiler_proof, APP_EXECUTABLE, export_breeze_trial


class TrialRunnerTests(unittest.TestCase):
    def test_candidate_must_be_pinned(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'App').mkdir()
            (root / 'App/BreezePAL4TrialPin.swift').write_text('static let identity = "unconfigured"')
            with self.assertRaises(ValueError): breeze_trial_contract('pal4', root)
            self.assertEqual(breeze_trial_contract('pal8', root)['model'], 'breeze-asr25-pal8-v1')
            with self.assertRaises(ValueError): breeze_trial_contract('wrong', root)

    def test_exact_compiled_arm_pin_executable_and_pid(self):
        contract = breeze_trial_contract('pal8')
        marker = (f'Mural[123:4] breeze_trial_launch arm=pal8 model={contract["model"]} '
                  f'manifest={contract["manifest"]} executable_sha256={"a" * 64}\n')
        backend = 'Mural[123:4] local_talk_asr_backend backend=Core AI GPU-preferred encoder + Core ML decoder (staged)\n'
        log = backend + marker
        self.assertEqual(breeze_trial_launch(log, contract, 'a' * 64), '123')
        self.assertEqual(breeze_trial_launch(log + marker, contract, 'a' * 64), '123')
        for bad in ('', backend, log + marker.replace('arm=pal8', 'arm=pal4'), log.replace('arm=pal8', 'arm=pal4'),
                    log.replace(contract['manifest'], 'b' * 64), log.replace('a' * 64, 'b' * 64),
                    backend + marker.replace('[123:4]', '[124:4]')):
            with self.subTest(log=bad), self.assertRaises(ValueError):
                breeze_trial_launch(bad, contract, 'a' * 64)

    def test_export_requires_real_turn_scoped_metrics_and_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); contract = breeze_trial_contract('pal8')
            def save(name, value): (root / name).write_text(json.dumps(value))
            save('session.json', dict(breeze_trial=contract, udid='test-device', pair='breeze-zh-CN-en', breeze_cache_regime='unchanged-install-warm'))
            save('cleanup.json', {'cleanup': 'PASS'})
            save('result.json', {'turns': [{'raw': 'synthetic test'}]})
            save('prepared.json', {'identity': {'artifacts': {APP_EXECUTABLE: 'a' * 64}}})
            save('prepared-source.json', {'receipt': str(root / 'prepared.json')})
            save('breeze-fixtures.json', [dict(id='F00A-switch', category='Mandarin-English-Mandarin', file='/synthetic/SYNTHETIC.wav', reference='synthetic test', sha256='b' * 64, manifest_sha256='c' * 64, duration_seconds=2.0)])
            save('devices.json', {'result': {'devices': [{'properties': {'hardware': {'udid': 'test-device', 'productType': 'iPhone18,3'}, 'software': {'osBuildVersions': {'buildVersion': {'name': 'synthetic-os'}}}}}]}})
            save('trial-install.json', {'first_install_run': 'synthetic-install'})
            save('capture-process.json', {'started_at': '2026-10-01T00:00:00Z'})
            turn = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
            events = ['local_talk_asr_backend backend=Core AI GPU-preferred encoder + Core ML decoder (staged)',
                f'breeze_trial_launch arm=pal8 model={contract["model"]} manifest={contract["manifest"]} executable_sha256={"a" * 64}',
                f'breeze_trial_prepare model={contract["model"]} success=true seconds=5.0',
                'capture_started', f'asr_trial_capture id={turn}', f'asr_trial_send id={turn}',
                'asr_input converted_frames=32000', 'breeze_inference_begin turn=1 first_since_prepare=true',
                'breeze_decode scope=whisperkit-transcribe-not-ui-send seconds=1.0',
                f'breeze_trial_transcribe model={contract["model"]} outcome=completed samples=32000 seconds=1.1 scope=asr-including-vad-not-ui-send',
                f'asr_trial_final id={turn} uptime=20.0 send_to_final_seconds=1.2 captured_seconds=2.0']
            log = '\n'.join('Mural[123:4] ' + event for event in events)
            (root / 'mural-device.log').write_text(log)
            export_breeze_trial(root)
            result = json.loads((root / 'benchmark-run.json').read_text())
            sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Tools/ChineseASR'))
            from evaluate import corpus
            rows = corpus(root / 'benchmark-corpus.json')
            self.assertEqual(rows[0]['group'], 'multi-switch')
            self.assertEqual(rows[0]['source_category'], 'Mandarin-English-Mandarin')
            self.assertEqual(rows[0]['wav'], 'SYNTHETIC.wav')
            self.assertTrue(result['complete'])
            self.assertIsNone(result['benchmark']['peak_physical_footprint_bytes'])
            self.assertEqual(result['predictions'][0]['send_to_final_seconds'], 1.2)
            (root / 'mural-device.log').write_text(log.replace('seconds=1.1', 'seconds=unknown'))
            with self.assertRaises(ValueError): export_breeze_trial(root)
            (root / 'mural-device.log').write_text(log)
            save('cleanup.json', {'cleanup': 'FAIL'})
            with self.assertRaises(ValueError): export_breeze_trial(root)

    def test_compiler_requires_trial_flag_for_identical_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'build.log'
            identity = {'artifacts': {APP_EXECUTABLE: 'a' * 64}}
            log.write_text('swiftc -module-name Mural -D MURAL_COREAI_TALK\n')
            with self.assertRaises(ValueError): compiler_proof(log, identity, [], trial=True)
            log.write_text('swiftc -module-name Mural -D MURAL_COREAI_TALK -D MURAL_BREEZE_PAL4_TRIAL\n')
            self.assertEqual(compiler_proof(log, identity, [], trial=True)['app_sha256'], 'a' * 64)
            with self.assertRaises(ValueError): compiler_proof(log, identity, [])


if __name__ == '__main__': unittest.main()
