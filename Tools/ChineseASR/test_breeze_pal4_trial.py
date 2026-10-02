"""Synthetic host contracts only: no real weights, Apple frameworks, or phone results."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import types
import unittest
from unittest.mock import patch
import breeze_pal4_trial as t
import breeze_ab_report as report


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.base=self.root/'base'; self.snap=self.root/'snapshot'
        self.base.mkdir(); self.snap.mkdir()
        for n in t.SUPPORT:
            t.write(self.base/n, t.TOPOLOGY if n=='config.json' else {})
        for root, precision in ((self.base,8),(self.snap,4)):
            for bundle in t.BUNDLES:
                b=root/bundle; (b/'weights').mkdir(parents=True)
                (b/'coremldata.bin').write_bytes(b'SYNTHETIC')
                (b/'weights/weight.bin').write_bytes(b'NOT A MODEL')
                (b/'model.mil').write_text('constexpr_lut_to_dense')
                tensor={'name':'test','shape':'[1, 2]','dataType':'Float16','type':'MultiArray'}
                t.write(b/'metadata.json',[{'storagePrecision':f'Mixed (Float16, Palettized ({precision} bits))',
                         'inputSchema':[tensor], 'outputSchema':[tensor]}])
        files={p.relative_to(self.base).as_posix():t.entry(p) for p in self.base.rglob('*') if p.is_file()}
        t.write(self.base/'manifest.json',{'revision':t.BASE_REVISION,'precision':'pal8','files':files})
        self.pin=patch.object(t,'BASE_MANIFEST', t.sha(self.base/'manifest.json')); self.pin.start(); self.addCleanup(self.pin.stop)
        self.lock=self.root/'lock.json'; self.refresh_lock()
        self.out=self.root/'package'

    def refresh_lock(self):
        data={'schema':'mural.breeze-hf-lock.v1','repo':t.REPO,'revision':'a'*40,'lineage':'SYNTHETIC TEST',
              'files':{p.relative_to(self.snap).as_posix():t.entry(p) for p in self.snap.rglob('*') if p.is_file()}}
        self.lock.write_text(json.dumps(data))

    def package(self): return t.inspect_package(self.base,self.snap,self.lock,self.out)

    def review(self):
        a=self.package(); ev=self.root/'mac-evidence.txt'; ev.write_text('SYNTHETIC UNIT TEST; NOT NATIVE EVIDENCE')
        self.review_path=self.root/'review.json'
        r={'schema':'mural.breeze-pal4-review.v1','audit_sha256':t.sha(self.out/'audit.json'),
           'reviewer':'synthetic-test','native_evidence_file':ev.name,'native_evidence_sha256':t.sha(ev),
           **{k:True for k in ('approved_for_device_trial','io_and_cache_contract_reviewed','pal4_bitpacking_reviewed',
                              'license_and_lineage_caveat_reviewed','native_mac_load_and_transcribe_passed')}}
        t.write(self.review_path,r); return a,r

    def test_full_synthetic_package_and_pin(self):
        a,_=self.review(); pin=self.root/'pin.swift'; t.arm(self.out,self.review_path,pin)
        self.assertIn(a['manifest_sha256'],pin.read_text()); self.assertEqual(a['file_count'],17)
        self.assertIsNone(a['phone_results']); self.assertIsNone(a['runtime_ram_bytes'])
        for n in t.SUPPORT: self.assertEqual((self.base/n).read_bytes(),(self.out/n).read_bytes())

    def test_baseline_pin_mismatch(self):
        (self.base/'manifest.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'independently pinned'): self.package()

    def test_baseline_support_tamper(self):
        (self.base/'tokenizer.json').write_text('tampered')
        with self.assertRaisesRegex(ValueError,'mismatch'): self.package()

    def test_candidate_hash_mismatch(self):
        (self.snap/'TextDecoder.mlmodelc/weights/weight.bin').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError,'Source drift'): self.package()

    def test_symlink_rejected(self):
        p=self.snap/'TextDecoder.mlmodelc/weights/weight.bin'; saved=p.read_bytes(); p.unlink()
        target=self.root/'target'; target.write_bytes(saved); p.symlink_to(target)
        with self.assertRaisesRegex(ValueError,'Symlinks'): self.package()

    def test_shape_drift(self):
        p=self.snap/'AudioEncoder.mlmodelc/metadata.json'; m=t.read(p); m[0]['outputSchema'][0]['shape']='[1, 3]'; p.write_text(json.dumps(m)); self.refresh_lock()
        with self.assertRaisesRegex(ValueError,'Tensor/cache'): self.package()

    def test_not_really_declared_pal4(self):
        p=self.snap/'AudioEncoder.mlmodelc/metadata.json'; p.write_text(p.read_text().replace('4 bits','8 bits')); self.refresh_lock()
        with self.assertRaisesRegex(ValueError,'No PAL4'): self.package()

    def test_lut_evidence_missing(self):
        (self.snap/'AudioEncoder.mlmodelc/model.mil').write_text('not a LUT'); self.refresh_lock()
        with self.assertRaisesRegex(ValueError,'LUT'): self.package()

    def test_v3_config_refused(self):
        t.write(self.snap/'config.json',dict(t.TOPOLOGY,num_mel_bins=128)); self.refresh_lock()
        with self.assertRaisesRegex(ValueError,'incompatible'): self.package()

    def test_existing_package_preserved(self):
        self.package(); before=t.sha(self.out/'manifest.json')
        with self.assertRaisesRegex(ValueError,'exists'): self.package()
        self.assertEqual(before,t.sha(self.out/'manifest.json'))

    def test_incomplete_review_refused(self):
        _,r=self.review(); r['native_mac_load_and_transcribe_passed']=False; self.review_path.write_text(json.dumps(r))
        with self.assertRaisesRegex(ValueError,'incomplete'): t.arm(self.out,self.review_path,self.root/'pin.swift')

    def test_review_must_bind_audit(self):
        _,r=self.review(); r['audit_sha256']='0'*64; self.review_path.write_text(json.dumps(r))
        with self.assertRaisesRegex(ValueError,'bind'): t.arm(self.out,self.review_path,self.root/'pin.swift')

    def test_native_evidence_required(self):
        self.review(); (self.root/'mac-evidence.txt').unlink()
        with self.assertRaisesRegex(ValueError,'Missing file'): t.arm(self.out,self.review_path,self.root/'pin.swift')

    def test_package_tamper_after_review(self):
        self.review(); (self.out/'tokenizer.json').write_text('tampered')
        with self.assertRaisesRegex(ValueError,'mismatch'): t.arm(self.out,self.review_path,self.root/'pin.swift')

    def test_pin_no_overwrite(self):
        self.review(); p=self.root/'pin.swift'; p.write_text('preserve')
        with self.assertRaisesRegex(ValueError,'exists'): t.arm(self.out,self.review_path,p)
        self.assertEqual(p.read_text(),'preserve')

    def test_path_rejections(self):
        for s in ('../bad','/bad','a//b','a/./b','a\\b',''):
            with self.subTest(s=s): self.assertFalse(t.valid_path(s))

    def test_lock_moving_revision_refused(self):
        data=t.read(self.lock); data['revision']='main'
        with self.assertRaisesRegex(ValueError,'Immutable'): t.check_lock(data)

    def test_lock_missing_bundle_refused(self):
        data=t.read(self.lock); del data['files']['TextDecoder.mlmodelc/model.mil']
        with self.assertRaisesRegex(ValueError,'Incomplete'): t.check_lock(data)

    def test_duplicate_json_refused(self):
        p=self.root/'duplicate.json'; p.write_text('{"key":1,"key":2}')
        with self.assertRaisesRegex(ValueError,'Duplicate'): t.read(p)


    def test_resolve_pins_remote_revision_and_blob_hashes(self):
        lock=t.read(self.lock)
        siblings=[SimpleNamespace(rfilename=n, size=e['bytes'], lfs=None,
                     blob_id=t.sha(self.snap/n, 'sha1', git_blob=True)) for n,e in lock['files'].items()]
        calls=[]
        class API:
            def __init__(self, token): self.token=token
            def model_info(inner, repo, revision, files_metadata):
                calls.append((repo, revision, files_metadata, inner.token))
                return SimpleNamespace(sha='a'*40, siblings=siblings)
        fake=types.ModuleType('huggingface_hub'); fake.HfApi=API
        with patch.dict('sys.modules', {'huggingface_hub':fake}):
            result=t.resolve('main', self.root/'resolved.json')
        self.assertEqual(calls, [(t.REPO,'main',True,False),(t.REPO,'a'*40,True,False)])
        self.assertEqual(result['revision'],'a'*40)
        self.assertTrue(all('git_blob_sha1' in e for e in t.read(self.root/'resolved.json')['files'].values()))

    def test_fetch_is_pinned_and_unknown_wire_bytes(self):
        calls=[]
        fake=types.ModuleType('huggingface_hub')
        def download(**kwargs):
            calls.append(kwargs); return str(self.snap/kwargs['filename'])
        fake.hf_hub_download=download
        output=self.root/'fetched'
        with patch.dict('sys.modules', {'huggingface_hub':fake}):
            result=t.fetch(self.lock,t.sha(self.lock),output)
        self.assertIsNone(result['network_bytes'])
        self.assertTrue(all(c['repo_id']==t.REPO and c['revision']=='a'*40 and c['token'] is False for c in calls))
        self.assertEqual((output/'TextDecoder.mlmodelc/weights/weight.bin').read_bytes(),b'NOT A MODEL')

    def test_failed_download_is_not_published(self):
        bad=self.root/'bad'; bad.write_bytes(b'bad')
        fake=types.ModuleType('huggingface_hub'); fake.hf_hub_download=lambda **kw: str(bad)
        output=self.root/'fetched'
        with patch.dict('sys.modules', {'huggingface_hub':fake}):
            with self.assertRaisesRegex(ValueError,'mismatch'): t.fetch(self.lock,t.sha(self.lock),output)
        self.assertFalse(output.exists())


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup); self.root=Path(self.tmp.name)
        self.corpus=self.root/'corpus.json'
        rows=[{'id':'mix','group':'zh-en','locale':'zh-CN','speaker':'s1','wav':'mix.wav','reference':'明天用 Core ML','entities':['Core ML']},
              {'id':'quiet','group':'silence','locale':'zh-CN','speaker':'control','wav':'quiet.wav','reference':''}]
        t.write(self.corpus,{'schema':'mural.chinese-asr.corpus.v1','clips':rows})
        b={k:'fixed' for k in report.COMMON}
        b.update({k:'1'*64 for k in report.HASHES})
        b.update(model_manifest_sha256=report.BASE_MANIFEST, schema='mural.breeze-ab.run.v1',arm='pal8',physical_device=True,hardware='iPhone18,3',
                 cleanup_passed=True,safety_stop=False,corpus_sha256=t.sha(self.corpus),process_id=123,
                 run_id='a',process_start_utc='2026-10-01T00:00:00Z',evidence_path='PRIVATE-SYNTHETIC-FIXTURE',
                 input_mode='file-replay',measurement_scope='whole-process',cache_regime='unchanged-install-warm',
                 peak_physical_footprint_bytes=2000,payload_bytes=1600,
                 preparations=[{'regime':'unchanged-install-warm','seconds':5}])
        self.a={'schema':'mural.chinese-asr.predictions.v1','complete':True,'benchmark':b,'predictions':[
            {'id':'mix','text':'明天用 Core ML','vad_rejected':False,'first_since_prepare':True,'audio_seconds':3.0,'decode_seconds':1.,'send_to_final_seconds':1.1,'asr_including_vad_seconds':1.05},
            {'id':'quiet','text':'','vad_rejected':True,'first_since_prepare':False,'audio_seconds':1.,'send_to_final_seconds':.05,'asr_including_vad_seconds':.04}]}
        self.b=copy.deepcopy(self.a); self.b['benchmark'].update(arm='pal4',model_manifest_sha256='2'*64,process_id=124,run_id='b',process_start_utc='2026-10-01T00:02:00Z',peak_physical_footprint_bytes=1500,payload_bytes=900)

    def compare(self): return report.compare(self.corpus,self.a,self.b)

    def test_report_metrics_and_no_promotion(self):
        r=self.compare(); self.assertFalse(r['automatically_promoted'])
        self.assertEqual(r['resources']['peak_physical_footprint_bytes']['reduction_percent'],25)
        self.assertIsNone(r['resources']['wire_bytes']['reduction_percent'])
        self.assertEqual(r['accuracy']['delta_mer_percentage_points'],0)
        self.assertEqual(r['accuracy']['candidate_entities']['hits'],1)
        self.assertIn('inference/first',r['timing']); self.assertIn('duration/under-2s',r['timing'])

    def test_cold_not_pooled_with_warm(self):
        self.b['benchmark']['preparations'].append({'regime':'first-artifact-load','seconds':170})
        r=self.compare(); self.assertEqual(r['preparation']['unchanged-install-warm']['candidate']['p50'],5)
        self.assertIsNone(r['preparation']['first-artifact-load']['p50_reduction_percent'])

    def test_missing_prediction_refused(self):
        self.b['predictions'].pop()
        with self.assertRaisesRegex(ValueError,'ID mismatch'): self.compare()

    def test_incomplete_refused(self):
        self.b['complete']=False
        with self.assertRaisesRegex(ValueError,'Complete'): self.compare()

    def test_mismatched_context_refused(self):
        for key in report.COMMON+('cache_regime',):
            old=self.b['benchmark'][key]; self.b['benchmark'][key]='changed'
            with self.subTest(key=key),self.assertRaises(ValueError): self.compare()
            self.b['benchmark'][key]=old

    def test_same_model_refused(self):
        self.b['benchmark']['model_manifest_sha256']=self.a['benchmark']['model_manifest_sha256']
        with self.assertRaisesRegex(ValueError,'Same model'): self.compare()

    def test_same_process_refused(self):
        self.b['benchmark']['process_start_utc']=self.a['benchmark']['process_start_utc']
        with self.assertRaisesRegex(ValueError,'Separate native'): self.compare()

    def test_failed_cleanup_refused(self):
        self.b['benchmark']['cleanup_passed']=False
        with self.assertRaisesRegex(ValueError,'Unclean'): self.compare()

    def test_partial_timing_refused(self):
        del self.b['predictions'][0]['send_to_final_seconds']
        with self.assertRaisesRegex(ValueError,'Unmatched'): self.compare()

    def test_silence_punctuation_still_fails(self):
        self.b['predictions'][1].update(text='.',vad_rejected=False)
        r=self.compare(); self.assertEqual(r['accuracy']['new_nonempty_silence_ids'],['quiet'])

    def test_raw_script_errors_not_hidden(self):
        self.a['predictions'][0]['text']='明天用 Core ML'
        self.b['predictions'][0]['text']='明天用錯 Core ML'
        self.assertGreater(self.compare()['accuracy']['delta_mer_percentage_points'],0)

    def test_first_position_must_match(self):
        self.b['predictions'][0]['first_since_prepare']=False
        with self.assertRaisesRegex(ValueError,'positions'): self.compare()

    def test_unknown_preparation_regime_refused(self):
        self.b['benchmark']['preparations']=[{'regime':'unspecified','seconds':1}]
        with self.assertRaisesRegex(ValueError,'Unknown preparation'): self.compare()

    def test_nan_refused(self):
        self.b['benchmark']['peak_physical_footprint_bytes']=float('nan')
        with self.assertRaisesRegex(ValueError,'measurement'): self.compare()


class SwiftSelectionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc') and Path('/private/var').is_dir(), 'Apple path alias required')
    def test_actual_inventory_under_apple_var_alias(self):
        root = Path(__file__).resolve().parents[2]
        code = r'''import Foundation
@main struct Check {
 static func main() throws {
  let folder = URL(fileURLWithPath: "/var/tmp").appending(path: "breeze-inventory-\(UUID())", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try Data().write(to: folder.appending(path: "manifest.json"))
  try BreezeTrialSelection.verifyInventory(at: folder, allowed: ["manifest.json"])
  try Data().write(to: folder.appending(path: "extra"))
  do { try BreezeTrialSelection.verifyInventory(at: folder, allowed: ["manifest.json"]); fatalError("extra file accepted") } catch {}
  try FileManager.default.removeItem(at: folder.appending(path: "extra"))
  try FileManager.default.createSymbolicLink(at: folder.appending(path: "link"), withDestinationURL: folder.appending(path: "manifest.json"))
  do { try BreezeTrialSelection.verifyInventory(at: folder, allowed: ["manifest.json", "link"]); fatalError("symlink accepted") } catch {}
 }
}'''
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / 'Check.swift'; main.write_text(code)
            exe = Path(tmp) / 'check'
            subprocess.run(['swiftc', str(root / 'App/BreezeTrialSelection.swift'), str(main), '-o', str(exe)], check=True, capture_output=True, timeout=40)
            subprocess.run([str(exe)], check=True, capture_output=True, timeout=10)

    @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler unavailable')
    def test_actual_swift_parser_both_build_modes(self):
        root=Path(__file__).resolve().parents[2]
        selection=root/'App/BreezeTrialSelection.swift'
        code='''import Foundation
@main struct Check {
    static func main() throws {
        assert(try BreezeTrialSelection.parse([], enabled: false) == .pal8)
        assert(try BreezeTrialSelection.parse(["--breeze-trial=pal4"], enabled: true) == .pal4)
        assert(try BreezeTrialSelection.parse(["--breeze-trial=pal8"], enabled: true) == .pal8)
        for args in [["--breeze-trial=oops"], ["--breeze-trial"], ["--breeze-trial=pal4", "--breeze-trial=pal8"]] {
            do { _ = try BreezeTrialSelection.parse(args, enabled: true); fatalError("accepted invalid selection") } catch {}
        }
        do { _ = try BreezeTrialSelection.parse(["--breeze-trial=pal4"], enabled: false); fatalError("production trial allowed") } catch {}
        #if MURAL_BREEZE_PAL4_TRIAL
        assert(BreezeTrialSelection.enabled)
        #else
        assert(!BreezeTrialSelection.enabled)
        #endif
    }
}'''
        # Swift assert takes a non-throwing autoclosure; evaluate the parser first.
        code=code.replace('assert(try BreezeTrialSelection.parse([], enabled: false) == .pal8)','let a = try BreezeTrialSelection.parse([], enabled: false); assert(a == .pal8)').replace('assert(try BreezeTrialSelection.parse(["--breeze-trial=pal4"], enabled: true) == .pal4)','let b = try BreezeTrialSelection.parse(["--breeze-trial=pal4"], enabled: true); assert(b == .pal4)').replace('assert(try BreezeTrialSelection.parse(["--breeze-trial=pal8"], enabled: true) == .pal8)','let c = try BreezeTrialSelection.parse(["--breeze-trial=pal8"], enabled: true); assert(c == .pal8)')
        with tempfile.TemporaryDirectory() as td:
            main=Path(td)/'Check.swift'; main.write_text(code)
            for flags in ([],['-D','MURAL_BREEZE_PAL4_TRIAL']):
                exe=Path(td)/'check'
                subprocess.run(['swiftc',*flags,str(selection),str(main),'-o',str(exe)],check=True,capture_output=True,timeout=40)
                subprocess.run([str(exe)],check=True,capture_output=True,timeout=10)

if __name__=='__main__': unittest.main()
