#!/usr/bin/env python3
"""Portable checks only; no Apple model execution or speech-quality claims."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import analyze_combined_trial as analysis
import analyze_combined_live as live
import combined_runtime_patch as runtime
import combined_trial as assets
from prepare_pal6_decoder_trial import REFERENCE_PIN, CANDIDATE_PIN

HERE = Path(__file__).parent


def digest(value): return hashlib.sha256(value.encode()).hexdigest()


def synthetic(root, label, enc="fp8", dec="pal8", native=False, policy="always"):
    root.mkdir()
    names = ["001.wav"]*2 if native else analysis.old.EXPECTED
    rows, preps, events = [], [], []
    pin = analysis.ENCODERS[enc]
    for i, name in enumerate(names, 1):
        rows.append({"turn": i, "file": name, "sampleCount": 16000,
            "audioSHA256": digest(name), "melSHA256": [digest(name+"mel")],
            "encoderHiddenSHA256": [digest(name+enc)],
            "rawTranscript": "Yesterday I went to the supermarket.", "normalizedTranscript": "yesterday i went to the supermarket",
            "generatedTokens": [[1, 2, 3]], "detectedLanguages": ["vi"], "termination": "endToken", "error": None,
            "thermalBefore": 0, "thermalAfter": 0,
            "timings": {"totalSeconds": 1, "decoderSeconds": .9}})
        preps.append({"index": i, "whisperKitLoadSeconds": .2, "whisperKitPrewarmSeconds": .1})
        stages = [("encoder-load-complete", {"function": pin["entrypoint"], "cacheHit": True, "specializationSeconds": 0,
                    "functionLoadSeconds": .2, "cacheLookupSeconds": .01}),
            ("encoder-response-verified", {"format": enc, "packetElements": 1920000+pin["width"],
                "challengeSeed": i & 31, "nativeSeconds": .5, "validationCopySeconds": .01}),
            ("encoder-run-end", {"hiddenElements": 1920000}),
            ("encoder-post-release-footprint", {}),
            ("whisperkit-load-complete", {"phase": "models"}),
            ("decoder-run-end", {"phase": "text"}),
            ("staged-asr-full-complete", {"file": name, "seconds": 2,
                "scope": "after-audio-read-through-encoder-prepare-decoder-not-UI-send"})]
        for j, (stage, fields) in enumerate(stages):
            events.append({"runID": label, "sessionID": label, "turn": i, "stage": stage, "uptime": i*10+j,
                "thermalState": 0, "memory": {"footprintBytes": 1000, "processRSSPeakBytes": 1500}, **fields})
    report = {"runID": label, "mode": "staged-gpu", "status": "complete", "terminal": True, "stateAtEnd": "idle",
        "errors": [], "cancellation": None, "corpusRequested": not native, "requestedTurns": 2 if native else 1,
        "lifecycle": "recreate", "architecture": "h18p", "turns": rows, "preparations": preps,
        "modelPrecision": f"v3 packed {enc} encoder, FP16 activations/handoff",
        "encoderArtifactSHA256": pin["aot_fingerprint"], "expectedEncoderArtifactSHA256": pin["aot_fingerprint"],
        "supportManifestSHA256": analysis.SUPPORT_PINS[dec],
        "tokenizer": "PhoWhisperTokenizer", "melBoundary": "fixed", "decodingOptions": {"task": "transcribe"}}
    context = {"source_commit": assets.START, "app_executable_sha256": "c"*64, "device_model": "synthetic",
        "os_build": "synthetic", "cache_condition": "retained-cache-new-process", "measurement_protocol": "synthetic-v1",
        "process_session_id": label, "prewarm_policy": policy,
        "launch_arguments": ["--coreai-product-mode=staged-gpu", "--coreai-w8-v3-encoder="+enc,
            "--coreai-w8-v3-decoder="+dec, "--coreai-w8-v3-prewarm="+policy,
            "--coreai-product-turns=2" if native else "--coreai-product-corpus"]}
    if (enc, dec) in analysis.COMBINED_FLAGS:
        context["launch_arguments"].append(analysis.COMBINED_FLAGS[(enc, dec)])
    (root/"report.json").write_text(json.dumps({"runID": label, "productGate": report, "memoryWarnings": 0, "error": None}))
    (root/"events.jsonl").write_text(''.join(json.dumps(e)+"\n" for e in events))
    (root/"trial-context.json").write_text(json.dumps(context))


def modify(root, filename, fn):
    p = root/filename
    if filename.endswith("jsonl"):
        obj = [json.loads(x) for x in p.read_text().splitlines()]; fn(obj)
        p.write_text(''.join(json.dumps(x)+"\n" for x in obj))
    else:
        obj = json.loads(p.read_text()); fn(obj); p.write_text(json.dumps(obj))


class RunTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory(); self.addCleanup(t.cleanup); self.root = Path(t.name)
        self.a, self.b = self.root/'a', self.root/'b'
        synthetic(self.a, 'a'); synthetic(self.b, 'b', 'pal6', 'pal6')

    def test_combined_contrast_retains_scopes(self):
        r = analysis.compare(analysis.read_run(self.a), analysis.read_run(self.b), 'combined')
        self.assertEqual(r['normalized_agreement']['matches'], 21)
        self.assertEqual(r['candidate']['scored']['encoder_response_footprint_bytes']['count'], 21)
        self.assertEqual(r['candidate']['warm_scored']['encoder_post_release_footprint_bytes']['count'], 20)
        self.assertIn('diagnostic_017', r['candidate'])
        self.assertEqual(r['process_lifetime_rss_peak_bytes']['candidate'], 1500)

    def test_intermediate_contrast_allows_encoder_hidden_changes(self):
        c = self.root/'c'; synthetic(c, 'c', 'fp8', 'pal6')
        self.assertEqual(analysis.compare(analysis.read_run(c), analysis.read_run(self.b), 'encoder-at-pal6')['normalized_agreement']['matches'], 21)

    def test_pal4_contrasts_are_pinned_and_pairable(self):
        b = self.root/'pal4-b'; c = self.root/'pal4-c'
        synthetic(b, 'pal4-b', 'fp8', 'pal4')
        synthetic(c, 'pal4-c', 'pal4', 'pal4')
        self.assertEqual(analysis.compare(analysis.read_run(self.a), analysis.read_run(c), 'combined-pal4')['normalized_agreement']['matches'], 21)
        self.assertEqual(analysis.compare(analysis.read_run(b), analysis.read_run(c), 'encoder-at-pal4')['normalized_agreement']['matches'], 21)

    def test_fixed_encoder_hidden_mismatch_is_rejected(self):
        c = self.root/'c'; synthetic(c, 'c', 'pal6', 'pal8')
        modify(c, 'report.json', lambda x: x['productGate']['turns'][1].update(encoderHiddenSHA256=['f'*64]))
        with self.assertRaises(ValueError): analysis.compare(analysis.read_run(c), analysis.read_run(self.b), 'decoder-at-pal6')

    def test_corpus_difference_is_not_hidden(self):
        modify(self.b, 'report.json', lambda x: x['productGate']['turns'][6].update(rawTranscript='New regression', normalizedTranscript='new regression'))
        r = analysis.compare(analysis.read_run(self.a), analysis.read_run(self.b), 'combined')
        self.assertEqual(r['normalized_agreement']['matches'], 20)
        self.assertEqual(r['differences'][0]['file'], '007.wav')

    def test_diagnostic_does_not_count_as_scored(self):
        modify(self.b, 'report.json', lambda x: x['productGate']['turns'][16].update(rawTranscript='Diagnostic changed'))
        r = analysis.compare(analysis.read_run(self.a), analysis.read_run(self.b), 'combined')
        self.assertEqual(r['normalized_agreement']['matches'], 21)
        self.assertFalse(r['differences'][0]['scored'])

    def test_nonterminal_rejected(self):
        modify(self.b, 'report.json', lambda x: x['productGate'].update(terminal=False))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_not_drained_rejected(self):
        modify(self.b, 'report.json', lambda x: x['productGate'].update(stateAtEnd='transcribing'))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_warning_rejected(self):
        modify(self.b, 'report.json', lambda x: x.update(memoryWarnings=1))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_unpinned_aot_rejected_even_when_expected_matches(self):
        modify(self.b, 'report.json', lambda x: x['productGate'].update(encoderArtifactSHA256='f'*64, expectedEncoderArtifactSHA256='f'*64))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_packet_width_rejected(self):
        modify(self.b, 'events.jsonl', lambda xs: next(x for x in xs if x['stage']=='encoder-response-verified').update(packetElements=1920040))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_main_fallback_rejected(self):
        modify(self.b, 'events.jsonl', lambda xs: next(x for x in xs if x['stage']=='encoder-load-complete').update(function='main'))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_specialization_not_inference(self):
        modify(self.b, 'events.jsonl', lambda xs: next(x for x in xs if x['stage']=='encoder-load-complete').update(specializationSeconds=2))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_missing_phase_memory_rejected(self):
        modify(self.b, 'events.jsonl', lambda xs: next(x for x in xs if x['stage']=='encoder-post-release-footprint')['memory'].pop('footprintBytes'))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_missing_combined_flag_rejected(self):
        modify(self.b, 'trial-context.json', lambda x: x['launch_arguments'].remove(assets.COMBINED))
        with self.assertRaises(ValueError): analysis.read_run(self.b)

    def test_mismatched_app_rejected(self):
        modify(self.b, 'trial-context.json', lambda x: x.update(app_executable_sha256='f'*64))
        with self.assertRaises(ValueError): analysis.compare(analysis.read_run(self.a), analysis.read_run(self.b), 'combined')

    def test_changed_policy_not_precision_result(self):
        modify(self.b, 'trial-context.json', lambda x: (x.update(prewarm_policy='once'), x['launch_arguments'].__setitem__(3, '--coreai-w8-v3-prewarm=once')))
        with self.assertRaises(ValueError): analysis.compare(analysis.read_run(self.a), analysis.read_run(self.b), 'combined')

    def test_native_two_turns_and_repeatability(self):
        a,b = self.root/'na', self.root/'nb'
        synthetic(a,'na', native=True); synthetic(b,'nb','pal6','pal6',native=True)
        r = analysis.compare(analysis.read_run(a, True), analysis.read_run(b, True), 'combined')
        self.assertEqual(r['normalized_agreement']['denominator'], 2)
        modify(b, 'report.json', lambda x: x['productGate']['turns'][1].update(encoderHiddenSHA256=['d'*64]))
        with self.assertRaises(ValueError): analysis.read_run(b, True)

    def test_native_quality_gate_rejects_wrong_text(self):
        n=self.root/'n'; synthetic(n,'n','pal6','pal6',native=True)
        modify(n, 'report.json', lambda x: [t.update(rawTranscript='wrong') for t in x['productGate']['turns']])
        with self.assertRaises(ValueError): analysis.read_run(n, True)

    def test_once_comparison_holds_both_models(self):
        c=self.root/'c'; synthetic(c,'c','pal6','pal6',policy='once')
        r = analysis.compare(analysis.read_run(self.b), analysis.read_run(c), 'prewarm')
        self.assertEqual(r['normalized_agreement']['matches'], 21)
        with self.assertRaises(ValueError): analysis.compare(analysis.read_run(self.a), analysis.read_run(c), 'prewarm')


class PolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(); p=Path(cls.tmp.name); cls.binary=p/'policy'
        (p/'main.swift').write_text('''import Foundation
let args = Array(CommandLine.arguments.dropFirst())
do {
    let once = try DecoderTrialPolicy.once(args)
    let e = args.first { $0.hasPrefix("--coreai-w8-v3-encoder=") }?.split(separator: "=").last.map(String.init)
    let d = args.first { $0.hasPrefix("--coreai-w8-v3-decoder=") }?.split(separator: "=").last.map(String.init)
    if let e, let d { try DecoderTrialPolicy.validatePair(encoder: e, decoder: d, arguments: args) }
    print(once ? "once" : "always")
} catch { exit(2) }
''')
        subprocess.run(['swiftc',str(HERE/'DecoderTrialPolicy.swift'),str(p/'main.swift'),'-o',str(cls.binary)],check=True,timeout=40)
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def check(self, args, valid=True, policy='always'):
        r=subprocess.run([str(self.binary),*args],text=True,capture_output=True,timeout=5)
        self.assertEqual(r.returncode, 0 if valid else 2, args)
        if valid: self.assertEqual(r.stdout.strip(),policy)
    def pair(self,e,d): return ['--coreai-w8-v3-encoder='+e,'--coreai-w8-v3-decoder='+d]
    def test_defaults_and_safe_pair_unchanged(self):
        self.check([]); self.check(self.pair('fp8','pal8')); self.check(self.pair('fp8','pal6')); self.check(self.pair('fp8','pal4'))
    def test_joint_requires_extra_opt_in(self):
        self.check(self.pair('pal6','pal6'),False)
        self.check(self.pair('pal6','pal6')+[assets.COMBINED])
        self.check(self.pair('pal4','pal4'),False)
        self.check(self.pair('pal4','pal4')+[analysis.COMBINED4])
    def test_combined_native_and_corpus(self):
        for args in (['--coreai-product-mode=staged-gpu','--coreai-product-turns=2'],['--coreai-product-mode=staged-gpu','--coreai-product-corpus']):
            self.check(self.pair('pal6','pal6')+[assets.COMBINED,'--coreai-w8-v3-prewarm=always']+args)
            self.check(self.pair('pal4','pal4')+[analysis.COMBINED4,'--coreai-w8-v3-prewarm=always']+args)
    def test_no_concurrent_or_legacy_mode(self):
        for flag in ('--coreai-product-mode=hybrid','--coreai-product-coexistence','--coreai-compressed-encoder=fp8'):
            self.check(self.pair('pal6','pal6')+[assets.COMBINED,flag],False)
    def test_duplicate_malformed_and_stray_flags(self):
        for tail in ([assets.COMBINED]*2,['--coreai-w8-v3-combined'],['--coreai-w8-v3-combined=anything']):
            self.check(self.pair('pal6','pal6')+tail,False)
        self.check(self.pair('fp8','pal8')+[assets.COMBINED],False)
    def test_historical_encoder_control_explicit_always(self):
        self.check(self.pair('pal6','pal8')+['--coreai-w8-v3-prewarm=always'])
        self.check(self.pair('pal6','pal8')+['--coreai-w8-v3-prewarm=once'],False)
        self.check(self.pair('pal4','pal8')+['--coreai-w8-v3-prewarm=always'])
        self.check(self.pair('pal4','pal8')+['--coreai-w8-v3-prewarm=once'],False)
    def test_joint_policy_is_opt_in_not_default(self):
        self.check(self.pair('pal6','pal6')+[assets.COMBINED,'--coreai-w8-v3-prewarm=once'],policy='once')
        self.check(self.pair('pal6','pal6')+[assets.COMBINED])


class PatchTests(unittest.TestCase):
    def source(self):
        old=HERE/'combined-policy-baseline.txt'
        if runtime.blob(old.read_text()) != "2d488bfd3d30987d19bf442c8724769d3a98703f":
            raise ValueError("Original policy fixture drift")
        baseline=old.read_text().replace('import Foundation\n','',1).lstrip()
        return {'App/LocalConversationEngine.swift': ('    private var generation = UUID()\n'
            'x = $0.hasPrefix("--coreai-w8-v3-encoder=") || $0.hasPrefix("--coreai-w8-v3-decoder=") || $0.hasPrefix("--coreai-w8-v3-prewarm") }\n'+runtime.OLD_GUARDS+'\n'
            '                self.logger.notice("local_audio_started send_to_audio_seconds=\\(gap, privacy: .public)")\n'
            'try await native.value\ntry identity.unpack(packet)\n\n'+baseline),
            'App/MuralApp.swift': runtime.OLD_RECOVERY+'\n}\nawait productTeardown(next: .idle)\n'}
    def test_both_policy_copies_and_drains(self):
        source=self.source(); p=(HERE/'DecoderTrialPolicy.swift').read_text(); out=runtime.patch_sources(source,p)
        self.assertIn(p.replace('import Foundation\n','',1).lstrip(),out['App/LocalConversationEngine.swift'])
        self.assertIn('try await native.value',out['App/LocalConversationEngine.swift'])
        self.assertIn('try identity.unpack(packet)',out['App/LocalConversationEngine.swift'])
        self.assertIn('requireRecovery = !config.corpus',out['App/MuralApp.swift'])
        self.assertIn('asr_trial_audio id=',out['App/LocalConversationEngine.swift'])
        self.assertIn('selection.supportIdentity != "phowhisper-cs-pal6-g16-v1"',out['App/MuralApp.swift'])
    def test_double_apply_and_drift_rejected(self):
        p=(HERE/'DecoderTrialPolicy.swift').read_text(); out=runtime.patch_sources(self.source(),p)
        with self.assertRaises(ValueError): runtime.patch_sources(out,p)
        s=self.source(); s['App/MuralApp.swift']='unrelated'
        with self.assertRaises(ValueError): runtime.patch_sources(s,p)
    def test_whole_file_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); (root/'App').mkdir()
            for n,s in self.source().items(): (root/n).write_text(s)
            with self.assertRaises(ValueError): runtime.patch_repository(root,(HERE/'DecoderTrialPolicy.swift').read_text())


class LiveTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory(); self.addCleanup(self.t.cleanup); self.p=Path(self.t.name)/'log'
        self.id='11111111-1111-1111-1111-111111111111'
        self.text=f'asr_trial_capture id={self.id} uptime=10\nasr_trial_send id={self.id} uptime=15\nasr_trial_final id={self.id} uptime=17 send_to_final_seconds=2 captured_seconds=5\nasr_trial_audio id={self.id} uptime=19 send_to_audio_seconds=4\n'
        self.p.write_text(self.text)
    def test_correlated_audio_does_not_use_browser_clock(self):
        self.p.write_text('browser reply uptime=90000\n'+self.text)
        r=live.analyze(self.p); self.assertEqual(r['turns'][0]['send_to_first_tutor_audio_seconds'],4)
        self.assertEqual(r['turns'][0]['post_asr_to_audio_seconds_not_pure_tutor_time'],2)
    def test_missing_or_duplicate_audio_rejected(self):
        self.p.write_text('\n'.join(x for x in self.text.splitlines() if 'asr_trial_audio' not in x))
        with self.assertRaises(ValueError): live.analyze(self.p)
        self.p.write_text(self.text+self.text.splitlines()[-1]+'\n')
        with self.assertRaises(ValueError): live.analyze(self.p)
    def test_audio_before_final_rejected(self):
        self.p.write_text(self.text.replace('uptime=19 send_to_audio_seconds=4','uptime=16 send_to_audio_seconds=1'))
        with self.assertRaises(ValueError): live.analyze(self.p)


class ArithmeticTests(unittest.TestCase):
    def test_real_sanitized_storage_arithmetic(self):
        r=assets.storage({'aot':{'bytes':640483375}},{'aot':{'bytes':1273967904}}, {'decoder_bytes':991764466},{'decoder_bytes':769115313})
        self.assertEqual(r['combined_minus_safe_bytes'],410835376)
        self.assertAlmostEqual(r['combined_minus_safe_percent'],25.16991388687)
        self.assertEqual(r['combined_minus_fp8_pal6_bytes'],633484529)
    def test_pins_are_different_and_no_encoder_pal8(self):
        self.assertEqual(set(assets.ENCODERS),{'fp8','pal6'})
        self.assertNotEqual(assets.ENCODERS['fp8']['manifest'],assets.ENCODERS['pal6']['manifest'])



class AdmissionTests(unittest.TestCase):
    def inputs(self):
        control = {k: "fixed" for k in ("source_weights", "source_configuration", "kind", "transport", "architecture", "compute", "min_deployment")}
        def encoder(tag, size):
            return {"control": copy.deepcopy(control), "source": {"native_hashes": [{"native_bytes_hex": tag+"1"}]},
                    "aot": {"bytes": size, "native_hashes": [{"native_bytes_hex": tag+"2"}]}}
        common = {"generation_config.json": {"bytes": 1, "sha256": digest("g")},
                  "tokenizer.json": {"bytes": 1, "sha256": digest("t")},
                  "MelSpectrogram.mlmodelc/data": {"bytes": 1, "sha256": digest("m")}}
        def support(tag, size):
            return {"files": {**copy.deepcopy(common), "TextDecoder.mlmodelc/data": {"bytes": size, "sha256": digest(tag)}},
                    "decoder_inventory_sha256": digest(tag), "decoder_bytes": size}
        return [encoder("a", 640483375), encoder("b", 1273967904), support("8", 991764466), support("6", 769115313)]

    def test_admission_is_not_a_device_pass(self):
        r = assets.admit(*self.inputs())
        self.assertEqual(r["status"], "static-only-not-device-qualified")
        self.assertEqual(r["native_current_os_abi_cache_quality"], "NOT TESTED")
        self.assertEqual(r["storage"]["combined_minus_safe_bytes"], 410835376)

    def test_mismatched_frozen_controls_rejected(self):
        args = self.inputs(); args[1]["control"]["source_configuration"] = "changed"
        with self.assertRaises(ValueError): assets.admit(*args)

    def test_cross_encoder_native_identity_collision_rejected(self):
        args = self.inputs(); args[1]["aot"]["native_hashes"] = args[0]["source"]["native_hashes"]
        with self.assertRaises(ValueError): assets.admit(*args)

    def test_manifest_rejected_before_any_model_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"manifest.json"; path.write_text("{}")
            with self.assertRaisesRegex(ValueError, "Not the historical"):
                assets.verify_encoder(path, "pal6")

if __name__=='__main__': unittest.main()
