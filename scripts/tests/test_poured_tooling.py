import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import tools.poured_parity.core as core
from tools.poured_parity.core import (ParityError, analyze_calibration, compare_static,
    fingerprint, init_run, load, native_plan, reference_plan, review_packet,
    validate_motion, verify_baseline_matrix, verify_freshness, verify_gate,
    verify_masks, verify_metric_reports, write)
from tools.poured_parity.dom import verify_reference_dom
from tools.poured_parity.raster import compare_static as compare_static_raster
from tools.poured_parity.trust import digest, validate_provenance, validate_run_root
from tools.poured_parity.cli import main as cli_main


def png(path, color, size=(8, 8), mode="RGBA"):
    Image.new(mode, size, color).save(path)
    return {"path": path.name, "sha256": digest(path), "dimensions": list(size)}


class PouredToolingTests(unittest.TestCase):
    def _valid_binding(self, root):
        initial=fingerprint(); relative=lambda path:str(path.relative_to(core.ROOT))
        files={name:root/name for name in ("executable","backdrop.png","helper","driver","fixture")}
        files["executable"].write_bytes(b"binary"); png(files["backdrop.png"],(1,2,3,255)); files["helper"].write_text("helper"); files["driver"].write_text("driver"); files["fixture"].write_text("fixture")
        environment=json.loads(json.dumps(initial["environment"])); environment["target"].update(name="OpenIslandApp",executable=relative(files["executable"]),executable_sha256=digest(files["executable"]),build_configuration="debug",macho_uuid="uuid",app_version="1",build_version="1")
        browser=core._browser_identity(); environment["system"].update(macos=initial["environment"]["system"]["macos"],hardware=initial["environment"]["system"]["hardware"],model="Mac",gpu="Apple"); environment["display"].update(stable_identity="display",logical_size=[100,100],native_size=[200,200],scale=2,profile="sRGB",refresh_hz=60); environment["preferences"].update(appearance="dark",accent="blue",reduce_motion=False,reduce_transparency=False,increase_contrast=False,text_size="medium"); environment["locale"].update(locale="en_US",timezone="UTC",hour_cycle="24"); environment["browser"].update(name=browser["name"],version=browser["version"],zoom=1,dpr=2,viewport=[100,100],flags=[]); environment["window"].update(bounds=[0,0,100,100],crop=[0,0,100,100],backdrop_path=relative(files["backdrop.png"]),backdrop_sha256=digest(files["backdrop.png"])); environment["capture"].update(format="png",encoding="RGBA8",api="CGWindow",helper_path=relative(files["helper"]),helper_sha256=digest(files["helper"])); environment["bundle"].update(identifier="dev.openisland",signing_identity="local",team_identifier="local")
        collector=core.ROOT/"scripts/poured-parity/environment-collector.py"; attestation=root/"environment.json"; write(attestation,{"schema_version":1,"collector":{"path":"scripts/poured-parity/environment-collector.py","sha256":digest(collector)},"collected_at":"2026-08-01T00:00:00Z","attestor_identity":"unapproved-attestor","implementation_identity":"executor","facts":{key:environment[key] for key in ("target","system","display","preferences","locale","browser","window","capture","bundle")}})
        binding=root/"bindings.json"; write(binding,{"schema_version":1,"native_commit":initial["native_commit"],"source_tree_hash":initial["source_tree_hash"],"implementation_identity":"executor","environment":environment,"environment_attestation":{"path":relative(attestation),"sha256":digest(attestation)},"bindings":{"driver":{"path":relative(files["driver"]),"sha256":digest(files["driver"])},"capture":{"path":relative(files["helper"]),"sha256":digest(files["helper"])},"fixtures":{"path":relative(files["fixture"]),"sha256":digest(files["fixture"])}}})
        return Path(relative(binding)),files

    def test_fingerprint_is_honestly_unresolved_and_binding_names_do_not_drift(self):
        value=fingerprint()
        self.assertFalse(value["canonical_ready"])
        self.assertIn("environment.display.stable_identity",value["unresolved_fields"])
        self.assertIn("bindings.driver",value["unresolved_fields"])
        self.assertNotIn("bindings.scenarios",value["unresolved_fields"])

    def test_binding_input_verifies_source_executable_backdrop_helper_and_fixture_hashes(self):
        core.ARTIFACTS.mkdir(parents=True,exist_ok=True)
        (core.ROOT/".build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=core.ROOT/".build",prefix="poured-binding-") as directory:
            root=Path(directory); initial=fingerprint(); relative=lambda path:str(path.relative_to(core.ROOT))
            executable=root/"OpenIslandApp"; executable.write_bytes(b"binary")
            backdrop=root/"backdrop.png"; png(backdrop,(1,2,3,255))
            helper=root/"capture"; helper.write_text("helper")
            driver=root/"driver"; driver.write_text("driver")
            fixture=root/"fixture"; fixture.write_text("fixture")
            environment=json.loads(json.dumps(initial["environment"])); environment["target"].update(name="OpenIslandApp",executable=relative(executable),executable_sha256=digest(executable),build_configuration="debug",macho_uuid="uuid",app_version="1",build_version="1")
            environment["system"].update(macos=initial["environment"]["system"]["macos"],hardware=initial["environment"]["system"]["hardware"],model="Mac",gpu="Apple")
            environment["display"].update(stable_identity="display",logical_size=[100,100],native_size=[200,200],scale=2,profile="sRGB",refresh_hz=60)
            environment["preferences"].update(appearance="dark",accent="blue",reduce_motion=False,reduce_transparency=False,increase_contrast=False,text_size="medium")
            environment["locale"].update(locale="en_US",timezone="UTC",hour_cycle="24")
            browser=core._browser_identity(); environment["browser"].update(name=browser["name"],version=browser["version"],zoom=1,dpr=2,viewport=[100,100],flags=[])
            environment["window"].update(bounds=[0,0,100,100],crop=[0,0,100,100],backdrop_path=relative(backdrop),backdrop_sha256=digest(backdrop))
            environment["capture"].update(format="png",encoding="RGBA8",api="CGWindow",helper_path=relative(helper),helper_sha256=digest(helper))
            environment["bundle"].update(identifier="dev.openisland",signing_identity="local",team_identifier="local")
            collector=core.ROOT/"scripts/poured-parity/environment-collector.py"; attestation=root/"environment.json"; write(attestation,{"schema_version":1,"collector":{"path":"scripts/poured-parity/environment-collector.py","sha256":digest(collector)},"collected_at":"2026-08-01T00:00:00Z","attestor_identity":"unapproved-attestor","implementation_identity":"executor","facts":{key:environment[key] for key in ("target","system","display","preferences","locale","browser","window","capture","bundle")}})
            binding=root/"bindings.json"; write(binding,{"schema_version":1,"native_commit":initial["native_commit"],"source_tree_hash":initial["source_tree_hash"],"implementation_identity":"executor","environment":environment,"environment_attestation":{"path":relative(attestation),"sha256":digest(attestation)},"bindings":{"driver":{"path":relative(driver),"sha256":digest(driver)},"capture":{"path":relative(helper),"sha256":digest(helper)},"fixtures":{"path":relative(fixture),"sha256":digest(fixture)}}})
            self.assertFalse(fingerprint(Path(relative(binding)))["canonical_ready"]); valid=load(binding)
            forged=json.loads(json.dumps(valid)); forged["environment"]["git"]["commit"]="0"*40; write(binding,forged)
            with self.assertRaisesRegex(ParityError,"locally measured Git"): fingerprint(Path(relative(binding)))
            invalid=json.loads(json.dumps(valid)); invalid["environment"]["browser"]["zoom"]=True; write(binding,invalid)
            with self.assertRaisesRegex(ParityError,"zoom/DPR"): fingerprint(Path(relative(binding)))
            traversal=json.loads(json.dumps(valid)); traversal["bindings"]["driver"]["path"]="../driver"; write(binding,traversal)
            with self.assertRaisesRegex(ParityError,"unsafe relative"): fingerprint(Path(relative(binding)))
            fake=json.loads(json.dumps(valid)); fake["environment"]["system"]["macos"]="15"; fake_attestation=load(attestation); fake_attestation["facts"]["system"]["macos"]="15"; write(attestation,fake_attestation); fake["environment_attestation"]["sha256"]=digest(attestation); write(binding,fake)
            with self.assertRaisesRegex(ParityError,"locally measured"): fingerprint(Path(relative(binding)))
            fake_browser=json.loads(json.dumps(valid)); fake_browser["environment"]["browser"]["version"]="Fake Browser 999"; fake_attestation=load(attestation); fake_attestation["facts"]["browser"]["version"]="Fake Browser 999"; write(attestation,fake_attestation); fake_browser["environment_attestation"]["sha256"]=digest(attestation); write(binding,fake_browser)
            with self.assertRaisesRegex(ParityError,"browser identity differs"): fingerprint(Path(relative(binding)))
            write(attestation,{"schema_version":1,"collector":{"path":"scripts/poured-parity/environment-collector.py","sha256":digest(collector)},"collected_at":"2026-08-01T00:00:00Z","attestor_identity":"unapproved-attestor","implementation_identity":"executor","facts":{key:environment[key] for key in ("target","system","display","preferences","locale","browser","window","capture","bundle")}})
            write(binding,valid)
            executable.write_bytes(b"changed")
            with self.assertRaisesRegex(ParityError,"hash mismatch"): fingerprint(Path(relative(binding)))

    def test_unmeasurable_browser_identity_is_unresolved_rather_than_trusted(self):
        (core.ROOT/".build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=core.ROOT/".build",prefix="poured-browser-") as directory:
            binding,_=self._valid_binding(Path(directory))
            measured=fingerprint(binding)
            self.assertNotIn("environment.browser.measurement",measured["unresolved_fields"])
            with patch.object(core,"_browser_identity",return_value={"name":None,"version":None,"executable":None,"sha256":None}):
                unmeasured=fingerprint(binding)
            self.assertIn("environment.browser.measurement",unmeasured["unresolved_fields"])
            self.assertIn("environment.browser.measurement",unmeasured["environment_evidence"]["unresolved"])
            self.assertFalse(unmeasured["canonical_ready"])

    def test_binding_backed_run_is_immediately_fresh_then_bound_mutation_is_stale(self):
        core.ARTIFACTS.mkdir(parents=True,exist_ok=True)
        (core.ROOT/".build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=core.ROOT/".build",prefix="poured-binding-") as directory:
            binding,files=self._valid_binding(Path(directory)); run_id=f"fresh-{Path(directory).name[-8:]}"; run=init_run(run_id,binding)
            try:
                self.assertTrue(verify_freshness(run)["fresh"])
                manifest=load(run/"manifest.json"); original_manifest=json.loads(json.dumps(manifest)); manifest["environment"]["system"]["model"]="forged"; write(run/"manifest.json",manifest)
                with patch.object(core,"ARTIFACTS",core.ARTIFACTS): core.index_run(run)
                with self.assertRaisesRegex(ParityError,"environment mismatch"): verify_freshness(run)
                write(run/"manifest.json",original_manifest); core.index_run(run)
                manifest=load(run/"manifest.json"); manifest["implementation_identity"]="forged"; write(run/"manifest.json",manifest); core.index_run(run)
                with self.assertRaisesRegex(ParityError,"implementation_identity mismatch"): verify_freshness(run)
                write(run/"manifest.json",original_manifest); core.index_run(run)
                genesis_path=run/original_manifest["binding_contract"]["genesis_path"]; original_genesis=load(genesis_path); stored=run/original_genesis["stored_binding_path"]; original_stored=load(stored); changed=json.loads(json.dumps(original_stored)); changed["implementation_identity"]="forged"; write(stored,changed); genesis=json.loads(json.dumps(original_genesis)); genesis["stored_binding_sha256"]=digest(stored); write(genesis_path,genesis); manifest=json.loads(json.dumps(original_manifest)); manifest["binding_contract"]["genesis_sha256"]=digest(genesis_path); write(run/"manifest.json",manifest)
                with self.assertRaisesRegex(ParityError,"trustworthy original"): core.index_run(run)
                write(stored,original_stored); write(genesis_path,original_genesis); write(run/"manifest.json",original_manifest); core.index_run(run)
                files["executable"].write_bytes(b"mutated")
                with self.assertRaisesRegex(ParityError,"hash mismatch"): verify_freshness(run)
            finally:
                shutil.rmtree(run)

    def test_freshness_rejects_coordinated_stored_binding_attestation_genesis_manifest_and_index_rewrite(self):
        (core.ROOT/".build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=core.ROOT/".build",prefix="poured-binding-") as directory:
            binding,_=self._valid_binding(Path(directory)); run=init_run(f"rewrite-{Path(directory).name[-8:]}",binding)
            try:
                manifest=load(run/"manifest.json"); genesis_path=run/manifest["binding_contract"]["genesis_path"]; genesis=load(genesis_path); stored=run/genesis["stored_binding_path"]; stored_attestation=run/genesis["stored_attestation_path"]
                forged_binding=load(stored); forged_binding["implementation_identity"]="coordinated-forgery"; write(stored,forged_binding)
                forged_attestation=load(stored_attestation); forged_attestation["implementation_identity"]="coordinated-forgery"; write(stored_attestation,forged_attestation)
                genesis["stored_binding_sha256"]=digest(stored); genesis["stored_attestation_sha256"]=digest(stored_attestation); write(genesis_path,genesis)
                manifest["binding_contract"]["genesis_sha256"]=digest(genesis_path); write(run/"manifest.json",manifest)
                entries=[{"path":str(path.relative_to(run)),"sha256":digest(path),"bytes":path.stat().st_size} for path in core.iter_files(run,{"evidence-index.json"})]
                write(run/"evidence-index.json",{"schema_version":1,"generated_at":"2026-08-01T00:00:00Z","sealed_for_review":False,"source_evidence_sha256":core._source_evidence_digest(entries),"evidence_set_sha256":core._evidence_set_digest(entries),"files":entries})
                with self.assertRaisesRegex(ParityError,"trustworthy original"): verify_freshness(run)
            finally:
                shutil.rmtree(run)

    def test_run_root_rejects_arbitrary_traversal_current_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts=Path(directory)/"artifacts"; artifacts.mkdir()
            for path in (Path(directory)/"outside",artifacts/"../escape",artifacts/"abc"/"current",artifacts/"abc"/"a/b"):
                with self.assertRaises(ParityError): validate_run_root(path,artifacts,False)
            real=artifacts/"deadbeef"/"run"; real.mkdir(parents=True)
            link=artifacts/"deadbeef"/"linked"; link.symlink_to(real,target_is_directory=True)
            with self.assertRaisesRegex(ParityError,"symlink"): validate_run_root(link,artifacts,False)

    def test_reference_plan_is_non_authoritative_and_live_dom_is_exact(self):
        plan=reference_plan()
        self.assertNotIn("F1-question",{x["scenario"] for x in plan["records"]})
        self.assertTrue(all(not x["authoritative"] for x in plan["records"]))
        report=core.verify_reference_dom()
        self.assertTrue(report["passed"])
        by_id={x["scenario"]:x for x in report["records"]}
        self.assertEqual(by_id["F4-compact-question"]["count"],1)
        self.assertIn("desk",by_id["G3-task-pill"]["nodes"][0]["classes"])

    def test_browser_dom_rejects_zero_duplicate_and_wrong_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            html=Path(directory)/"x.html"; html.write_text("<div class='x'>one</div><div class='x'>two</div>")
            base={"id":"S","class":"rendered-canonical","anchor":{"selector":".missing","identity":{"tag":"div","classes":["x"],"text_contains":[]}}}
            with self.assertRaisesRegex(ParityError,"cardinality"):
                verify_reference_dom(html,digest(html),[base])
            duplicate=json.loads(json.dumps(base)); duplicate["anchor"]["selector"]=".x"
            with self.assertRaisesRegex(ParityError,"cardinality"):
                verify_reference_dom(html,digest(html),[duplicate])
            wrong=json.loads(json.dumps(base)); wrong["anchor"]["selector"]=".x:first-child"; wrong["anchor"]["identity"]["tag"]="span"
            with self.assertRaisesRegex(ParityError,"identity"):
                verify_reference_dom(html,digest(html),[wrong])

    def _calibration(self, root):
        stills=[]; motions=[]; fid={"nw":[1,1],"ne":[7,1],"sw":[1,7],"se":[7,7]}
        for renderer_index,renderer in enumerate(("css","swiftui")):
            for repetition in range(5):
                path=root/f"{renderer}-still-{repetition}.png"; record=png(path,(20+repetition,30+renderer_index,40,255)); record.update(renderer=renderer,target_id="neutral",profile="srgb",scale=2,run_id=f"{renderer}-still",capture_id=f"{renderer}-still-capture-{repetition}",repetition=repetition,fiducials=fid); stills.append(record)
            for run_index in range(3):
                frames=[]
                for frame_index in range(3):
                    path=root/f"{renderer}-motion-{run_index}-{frame_index}.png"; record=png(path,(60+frame_index+run_index*3+renderer_index*12,70+renderer_index,80,255)); record["pts"]=frame_index/60; record["capture_id"]=f"{renderer}-motion-{run_index}-frame-{frame_index}"; frames.append(record)
                motions.append({"renderer":renderer,"target_id":"neutral","profile":"srgb","scale":2,"run_id":f"{renderer}-{run_index}","capture_id":f"{renderer}-motion-run-{run_index}","fiducials":fid,"frames":frames})
        manifest=root/"calibration.json"
        for row in stills: row["sample_id"]=f'{row["renderer"]}-{row["repetition"]}'
        run_manifest=load(root/"manifest.json"); metadata={"captured_at":"2026-08-01T00:00:00Z","target_executable_sha256":run_manifest["environment"].get("target",{}).get("executable_sha256"),"capture_helper_sha256":run_manifest["environment"].get("capture",{}).get("helper_sha256"),"display_identity":run_manifest["environment"].get("display",{}).get("stable_identity")}
        write(manifest,{"schema_version":1,"run_artifact_root":run_manifest["artifact_root"],"environment_sha256":core._json_digest(run_manifest["environment"]),"bindings_sha256":core._json_digest(run_manifest["bindings"]),"capture_session_id":"calibration-session-1","capture_metadata":metadata,"content_role":"neutral-calibration","source_role":"neutral-primitives","poured_source_hashes":[],"required_renderers":["css","swiftui"],"logical_size":[4,4],"logical_fiducials":{"nw":[0,0],"ne":[3,0],"sw":[0,3],"se":[3,3]},"captured_scale":2,"color_profile":"srgb","target_id":"neutral","stills":stills,"motion_runs":motions})
        return manifest

    def test_calibration_decodes_hashed_assets_and_measures_variance_mapping_and_timing(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); manifest=self._calibration(root)
            with patch.object(core,"ARTIFACTS",artifacts): report=analyze_calibration(manifest)
            self.assertFalse(report["ready"])
            self.assertEqual(report["status"],"diagnostic")
            self.assertEqual(set(report["renderers"]),{"css","swiftui"})
            self.assertIn("pixel_noise_mean",report["renderers"]["css"])
            self.assertIn("landmark_repeatability",report["renderers"]["css"])
            value=load(manifest); value["required_renderers"]=["css"]; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"css and swiftui"): analyze_calibration(manifest)

    def test_calibration_rejects_arbitrary_binary_and_hash_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); manifest=self._calibration(root); value=load(manifest)
            bad=root/"bad.bin"; bad.write_bytes(b"not an image")
            value["stills"][0].update(path=bad.name,sha256=digest(bad),dimensions=[8,8]); write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"decode raster"): analyze_calibration(manifest)

    def test_calibration_rejects_duplicate_ids_bad_geometry_and_permissive_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); manifest=self._calibration(root); original=load(manifest)
            for mutate,message in ((lambda x:x["stills"][1].update(sample_id=x["stills"][0]["sample_id"]),"duplicated"),(lambda x:x.update(logical_fiducials={"nw":[0,0],"ne":[0,0],"sw":[0,1],"se":[1,1]}),"degenerate"),(lambda x:x.update(limits={"mapping_residual_max":999}),"input schema mismatch")):
                value=json.loads(json.dumps(original)); mutate(value); write(manifest,value)
                with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,message): analyze_calibration(manifest)
            value=json.loads(json.dumps(original)); value["stills"][1]["path"]=value["stills"][0]["path"]; value["stills"][1]["sha256"]=value["stills"][0]["sha256"]; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"path/content SHA-256 identity"): analyze_calibration(manifest)

    def test_calibration_rejects_repeated_content_and_wrong_run_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); manifest=self._calibration(root); original=load(manifest)
            value=json.loads(json.dumps(original))
            for still in value["stills"]:
                path=root/still["path"]; png(path,(9,9,9,255)); still["sha256"]=digest(path)
            write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"content SHA-256"): analyze_calibration(manifest)
            manifest=self._calibration(root); original=load(manifest)
            value=json.loads(json.dumps(original))
            for run in value["motion_runs"]:
                for frame_index,frame in enumerate(run["frames"]):
                    path=root/frame["path"]; png(path,(100+frame_index,1,1,255)); frame["sha256"]=digest(path)
            write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"content SHA-256"): analyze_calibration(manifest)
            manifest=self._calibration(root); original=load(manifest)
            value=json.loads(json.dumps(original)); value["environment_sha256"]="0"*64; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"canonical run/capture identity"): analyze_calibration(manifest)

    def _mask_annotations(self, root, overlap=False, exclude_text=False):
        families=load(core.VALIDATION/"mask-policy-v1.json")["families"]
        rects={family:[[0,0,8,8]] for family in families}; rects["os-external"]=[[5,5,7,7]] if overlap else [[6,6,8,8]]
        if exclude_text: rects["text-layout"]=[[0,0,1,1]]
        annotation=root/"annotations.json"
        artifact=root/"mask-source.png"; png(artifact,(1,2,3,255)); manifest=load(root/"manifest.json"); sidecar=root/"mask-capture.json"; write(sidecar,{"schema_version":1,"scenario":"A1-idle","profile":"notch-v1","variant":"standard","capture_role":"reference","capture_id":"mask-capture-1","captured_at":"2026-08-01T00:00:00Z","environment_sha256":core._json_digest(manifest["environment"]),"bindings_sha256":core._json_digest(manifest["bindings"]),"artifact":{"path":artifact.name,"sha256":digest(artifact),"dimensions":[8,8]}})
        write(annotation,{"schema_version":1,"dimensions":[8,8],"scopes":[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","capture_role":"reference","capture_sidecar":{"path":sidecar.name,"sha256":digest(sidecar)},"families":rects,"owned_text_rects":[[1,1,3,3]],"owned_content_rects":[[0,0,6,6]],"os_external_rects":[[5,5,7,7]] if overlap else [[6,6,8,8]]}]})
        return annotation,set(families)

    def test_masks_are_real_hashed_binary_rasters_and_protect_owned_content(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); annotation,families=self._mask_annotations(root); output=root/"masks"
            applicable=[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","mask_roles":["reference"]}]
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=applicable): core.generate_masks(annotation,output); result=verify_masks(output/"masks.json")
            self.assertTrue(result["valid"]); self.assertEqual(result["masks"],len(families))
            (output/next(x["path"] for x in load(output/"masks.json")["masks"])).unlink()
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=applicable), self.assertRaises(ParityError): verify_masks(output/"masks.json")

    def test_masks_reject_external_overlap_and_owned_text_exclusion(self):
        for overlap,exclude,message in ((True,False,"overlaps"),(False,True,"owned text")):
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                artifacts,root=self._temporary_run(directory); annotation,families=self._mask_annotations(root,overlap,exclude); output=root/"masks"
                applicable=[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","mask_roles":["reference"]}]
                with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=applicable): core.generate_masks(annotation,output)
                with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=applicable), self.assertRaisesRegex(ParityError,message): verify_masks(output/"masks.json")

    def test_masks_reject_reconstruction_drift_even_with_rehashed_raster(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); annotation,_=self._mask_annotations(root); output=root/"masks"
            applicable=[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","mask_roles":["reference"]}]
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=applicable): core.generate_masks(annotation,output)
            manifest=load(output/"masks.json"); record=next(x for x in manifest["masks"] if x["family"]=="os-external"); path=output/record["path"]
            image=Image.new("L",(8,8),0); image.paste(255,(6,0,8,2)); image.save(path); record["sha256"]=digest(path); write(output/"masks.json",manifest)
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=applicable), self.assertRaisesRegex(ParityError,"external rectangles|reconstruction annotation"): verify_masks(output/"masks.json")

    def test_masks_reject_missing_roles_duplicate_scopes_metadata_and_nonbinary_pixels(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); annotation,_=self._mask_annotations(root); output=root/"masks"; one=[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","mask_roles":["reference"]}]
            missing=one+[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","mask_roles":["native"]}]
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=missing),self.assertRaisesRegex(ParityError,"exactly equal"): core.generate_masks(annotation,output)
            duplicate=load(annotation); duplicate["scopes"].append(json.loads(json.dumps(duplicate["scopes"][0]))); write(annotation,duplicate)
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=one),self.assertRaisesRegex(ParityError,"exactly equal"): core.generate_masks(annotation,output)
            duplicate["scopes"].pop(); write(annotation,duplicate)
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=one): core.generate_masks(annotation,output)
            manifest=load(output/"masks.json"); manifest["scopes"][0]["owned_text_rects"]=[[0,0,1,1]]; write(output/"masks.json",manifest)
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=one),self.assertRaisesRegex(ParityError,"metadata differs"): verify_masks(output/"masks.json")
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=one): core.generate_masks(annotation,output)
            manifest=load(output/"masks.json"); record=manifest["masks"][0]; path=output/record["path"]; Image.new("L",(8,8),128).save(path); record["sha256"]=digest(path); record["coverage_pixels"]=64; write(output/"masks.json",manifest)
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=one),self.assertRaisesRegex(ParityError,"not binary"): verify_masks(output/"masks.json")

    def test_masks_reject_mismatched_capture_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,root=self._temporary_run(directory); annotation,_=self._mask_annotations(root); value=load(annotation); sidecar_path=root/value["scopes"][0]["capture_sidecar"]["path"]; sidecar=load(sidecar_path); sidecar["scenario"]="A2-working-one"; write(sidecar_path,sidecar); value["scopes"][0]["capture_sidecar"]["sha256"]=digest(sidecar_path); write(annotation,value)
            one=[{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","mask_roles":["reference"]}]
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_expanded_applicability",return_value=one),self.assertRaisesRegex(ParityError,"capture sidecar context"): core.generate_masks(annotation,root/"masks")

    def _static_spec(self, root):
        records={}
        for name in ("reference_silhouette","native_silhouette","stable_opaque","stable_non_text","reference_chrome","native_chrome"):
            path=root/f"{name}.png"; records[name]=png(path,255,size=(16,16),mode="L")
        thresholds=load(core.VALIDATION/"measurements-v1.json")["targets"]
        run=root.parents[1]; bindings={}
        for name in ("calibration","mask_manifest","thresholds","reference_sidecar","native_sidecar","evidence_index"):
            path=run/f"{name}.binding"; path.write_text(name); bindings[name]={"path":str(path.relative_to(run)),"sha256":digest(path)}
        spec=root/"static-spec.json"; write(spec,{"context":{"scenario":"A1-idle","profile":"notch-v1","variant":"standard","authority_class":"rendered-canonical"},"bindings":bindings,"registration":{"permitted_translation_device_px":2,"anchors":{"reference":{"top-left":[0,0],"top-right":[15,0]},"native":{"top-left":[0,0],"top-right":[15,0]}}},"aa_band_device_px":1,"logical_to_device_scale":2,"masks":records,"thresholds":thresholds,"text":{"reference":[{"copy":"hello","lines":1,"bounds":[0,0,4,2],"baseline":1}],"native":[{"copy":"hello","lines":1,"bounds":[0,0,4,2],"baseline":1}]},"landmarks":{"reference":{"left":[0,0],"right":[15,0]},"native":{"left":[0,0],"right":[15,0]}}})
        return spec

    def test_static_comparison_measures_every_required_metric_and_signed_data(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); root=run/"comparisons/test"; root.mkdir(parents=True); reference=root/"ref.png"; native=root/"native.png"; png(reference,(10,20,30,255),(16,16)); png(native,(10,20,30,255),(16,16)); spec=self._static_spec(root)
            report=compare_static_raster(reference,native,root/"out",spec)
            self.assertEqual(report["overall_screening_status"],"passed")
            self.assertTrue(all(item["status"]=="passed" and item["value"] is not None for item in report["metrics"].values()))
            self.assertTrue((root/"out/signed-diff.npy").is_file())
            value=load(spec); del value["masks"]["stable_non_text"]; write(spec,value)
            with self.assertRaisesRegex(ParityError,"required static mask"): compare_static_raster(reference,native,root/"bad",spec)
            value=self._static_spec(root); broken=load(value); broken["registration"]["anchors"]["native"]["top-right"]=[14,0]; write(value,broken)
            with self.assertRaisesRegex(ParityError,"one exact integer translation"): compare_static_raster(reference,native,root/"bad-anchor",value)

    def test_capture_sidecars_reject_fake_source_arbitrary_anchors_and_text_strings(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); image=run/"reference.png"; png(image,(1,2,3,255)); context={"scenario":"A1-idle","profile":"notch-v1","variant":"standard","authority_class":"rendered-canonical"}; manifest=load(run/"manifest.json")
            sidecar=run/"reference.json"; base={"schema_version":1,**context,"capture_role":"reference","disposition":"exact","image":{"path":"reference.png","sha256":digest(image),"dimensions":[8,8]},"environment_sha256":core._json_digest(manifest["environment"]),"bindings_sha256":core._json_digest(manifest["bindings"]),"source_identity":{"source_sha256":load(core.VALIDATION/"authority.json")["reference"]["sha256"]},"anchors":{"left":[0,0],"right":[7,0]},"text":[{"name":"title","copy":"hello","line_count":1,"bounds":[0,0,4,2],"baselines":[1],"wrapping":"single-line"}],"landmarks":{"left":[0,0],"right":[7,0]}}; write(sidecar,base)
            def invoke(value):
                write(sidecar,value); record={"path":"reference.json","sha256":digest(sidecar)}; index={"reference.json":{"path":"reference.json","sha256":digest(sidecar),"bytes":sidecar.stat().st_size},"reference.png":{"path":"reference.png","sha256":digest(image),"bytes":image.stat().st_size}}
                with patch.object(core,"ARTIFACTS",artifacts): return core._capture_sidecar(run,record,"reference",context,index)
            invoke(base)
            value=json.loads(json.dumps(base)); value["text"]="not geometry"
            with self.assertRaisesRegex(ParityError,"text geometry"): invoke(value)
            value=json.loads(json.dumps(base)); value["anchors"]={"anything":[0,0]}
            with self.assertRaisesRegex(ParityError,"anchors"): invoke(value)
            value=json.loads(json.dumps(base)); value["source_identity"]={"source_sha256":"0"*64}
            with self.assertRaisesRegex(ParityError,"source identity"): invoke(value)
            spec=run/"loose-spec.json"; write(spec,{"schema_version":1,"context":context,"reference_sidecar":{},"native_sidecar":{},"mask_manifest":{},"calibration_bundle":{},"thresholds_sha256":digest(core.VALIDATION/"measurements-v1.json"),"ledger_sha256":"0"*64,"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"source_evidence_sha256":"0"*64,"thresholds":{"silhouette_iou_min":0}})
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"spec schema"): core.compare_static(run/"comparisons/out",spec)

    def _temporary_run(self, directory, name="run"):
        artifacts=Path(directory)/"artifacts"; commit="deadbeef"; root=artifacts/commit/name; root.mkdir(parents=True)
        manifest={"schema_version":1,"run_id":name,"native_commit":commit,"dirty":False,"source_tree_hash":"a"*64,"bindings":{},"environment":{},"environment_evidence":{},"runtime":{},"implementation_identity":"executor","unresolved_fields":["binding_contract.original_authority"],"artifact_root":f"artifacts/poured-parity/{commit}/{name}","created_at":"2026-08-01T00:00:00Z","canonical_ready":False,"binding_contract":None}
        write(root/"manifest.json",manifest)
        return artifacts,root

    def test_motion_requires_real_contained_60fps_repeated_frames_and_manual_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); scenario=run/"motion/KX-breath-css"; scenario.mkdir(parents=True); runs=[]; fid={"nw":[0,0],"ne":[7,0],"sw":[0,7],"se":[7,7]}
            for run_index in range(3):
                frames=[]
                for frame_index in range(7):
                    path=scenario/f"{run_index}-{frame_index}.png"; record=png(path,(frame_index,run_index,0,255)); record["path"]=str(path.relative_to(run)); record["pts"]=frame_index/60; record["capture_id"]=f"run-{run_index}-frame-{frame_index}"; frames.append(record)
                checkpoints=[{"id":name,"frame_index":index,"pts":frames[index]["pts"],"frame_path":frames[index]["path"],"frame_sha256":frames[index]["sha256"],"frame_capture_id":frames[index]["capture_id"],"landmarks":{"body":[index,0]}} for index,name in enumerate(["t0","trigger","10%","25%","50%","75%","settled"])]
                events=[{"id":"trigger","kind":"input","frame_index":1,"pts":frames[1]["pts"],"frame_path":frames[1]["path"],"frame_sha256":frames[1]["sha256"],"frame_capture_id":frames[1]["capture_id"]},{"id":"settled","kind":"settled","frame_index":6,"pts":frames[6]["pts"],"frame_path":frames[6]["path"],"frame_sha256":frames[6]["sha256"],"frame_capture_id":frames[6]["capture_id"]}]
                runs.append({"run_id":str(run_index),"capture_id":f"run-capture-{run_index}","fiducials":fid,"frames":frames,"checkpoints":checkpoints,"events":events})
            environment_hash=core._json_digest(load(run/"manifest.json")["environment"]); bindings_hash=core._json_digest(load(run/"manifest.json")["bindings"])
            run_captures=[item["capture_id"] for item in runs]; frame_captures=[frame["capture_id"] for item in runs for frame in item["frames"]]
            capture=scenario/"capture.json"; write(capture,{"schema_version":1,"scenario":"KX-breath-css","profile":"notch-v1","variant":"standard","capture_role":"native","capture_id":"motion-capture","run_capture_ids":run_captures,"frame_capture_ids":frame_captures,"environment_sha256":environment_hash,"bindings_sha256":bindings_hash,"view_identity":"PouredMotionView"})
            clock=scenario/"clock.json"; write(clock,{"schema_version":1,"scenario":"KX-breath-css","capture_id":"motion-capture","run_capture_ids":run_captures,"frame_capture_ids":frame_captures,"clock_id":"manual-v1","consumed_by_views":True,"view_identity":"PouredMotionView","environment_sha256":environment_hash,"bindings_sha256":bindings_hash})
            with patch.object(core,"ARTIFACTS",artifacts): core.index_run(run)
            bindings={"scenarios_sha256":digest(core.VALIDATION/"scenarios-v1.json"),"behavior_sha256":digest(core.VALIDATION/"behavior-v1.json"),"motion_authority_sha256":digest(core.VALIDATION/"motion-authority-v1.json"),"calibration_sha256":core.tree_hash([core.VALIDATION/"calibration-v1.json",core.VALIDATION/"calibration-bundle-authority-v1.json"]),"source_evidence_sha256":load(run/"evidence-index.json")["source_evidence_sha256"]}
            manifest=scenario/"motion.json"; write(manifest,{"schema_version":1,"scenario":"KX-breath-css","profile":"notch-v1","variant":"standard","authority_class":"rendered-motion-exemplar","canonical_disposition":"diagnostic","bindings":bindings,"capture_sidecar":{"path":str(capture.relative_to(run)),"sha256":digest(capture)},"manual_clock_attestation":{"path":str(clock.relative_to(run)),"sha256":digest(clock)},"runs":runs})
            output=scenario/"report.json"
            with patch.object(core,"ARTIFACTS",artifacts): self.assertEqual(validate_motion(manifest,output)["status"],"measured-diagnostic")
            original=load(manifest)
            value=json.loads(json.dumps(original)); value["runs"][0]["frames"][1]["pts"]=0; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"strictly monotonic"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][0]["frames"][1].update(path=value["runs"][0]["frames"][0]["path"],sha256=value["runs"][0]["frames"][0]["sha256"]); write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"reused"): validate_motion(manifest,output)
            binary=scenario/"frame.bin"; binary.write_bytes(b"not a frame"); value=json.loads(json.dumps(original)); value["runs"][0]["frames"][0].update(path=str(binary.relative_to(run)),sha256=digest(binary),dimensions=[8,8]); write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"index binding"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][1]["run_id"]=value["runs"][0]["run_id"]; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"distinct"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][0]["frames"][0]["pts"]=.01; value["runs"][0]["checkpoints"][0]["pts"]=.01; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"t=0"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][0]["checkpoints"][0]["frame_index"]=999; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"frame index"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][0]["events"].reverse(); write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"unordered"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][0]["checkpoints"][1]=json.loads(json.dumps(value["runs"][0]["checkpoints"][0])); write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"duplicated|authority order"): validate_motion(manifest,output)
            value=json.loads(json.dumps(original)); value["runs"][0]["checkpoints"][0]["frame_capture_id"]="unbound-capture"; write(manifest,value)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"exact frame/capture"): validate_motion(manifest,output)
            original_capture=load(capture); original_clock=load(clock)
            def sidecar_failure(capture_value,clock_value,message):
                write(capture,capture_value); write(clock,clock_value); write(manifest,original)
                with patch.object(core,"ARTIFACTS",artifacts): rebound=core.index_run(run)
                candidate=json.loads(json.dumps(original)); candidate["bindings"]["source_evidence_sha256"]=rebound["source_evidence_sha256"]; candidate["capture_sidecar"]["sha256"]=digest(capture); candidate["manual_clock_attestation"]["sha256"]=digest(clock); write(manifest,candidate)
                with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,message): validate_motion(manifest,output)
            fake_capture=json.loads(json.dumps(original_capture)); fake_clock=json.loads(json.dumps(original_clock)); fake_capture["environment_sha256"]="0"*64; fake_clock["environment_sha256"]="0"*64
            sidecar_failure(fake_capture,fake_clock,"canonical run")
            fake_capture=json.loads(json.dumps(original_capture)); fake_clock=json.loads(json.dumps(original_clock)); fake_capture["run_capture_ids"]=fake_capture["run_capture_ids"][:-1]; fake_clock["run_capture_ids"]=fake_clock["run_capture_ids"][:-1]
            sidecar_failure(fake_capture,fake_clock,"capture lineage")

    def test_index_freshness_rejects_hash_size_symlink_and_review_reindex(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); write(run/"ledger.json",{}); (run/"data.txt").write_text("x")
            current={"native_commit":"deadbeef","dirty":False,"source_tree_hash":"a"*64,"bindings":{},"environment":{},"environment_evidence":{},"runtime":{},"implementation_identity":"executor","unresolved_fields":["binding_contract.original_authority"],"canonical_ready":False}
            with patch.object(core,"ARTIFACTS",artifacts), patch.object(core,"fingerprint",return_value=current): core.index_run(run); self.assertTrue(verify_freshness(run)["fresh"])
            saved=load(run/"evidence-index.json"); malformed=json.loads(json.dumps(saved)); malformed["files"][0]["bytes"]="1"; write(run/"evidence-index.json",malformed)
            with patch.object(core,"ARTIFACTS",artifacts), patch.object(core,"fingerprint",return_value=current), self.assertRaisesRegex(ParityError,"row schema"): verify_freshness(run)
            write(run/"evidence-index.json",saved)
            (run/"data.txt").write_text("changed")
            with patch.object(core,"ARTIFACTS",artifacts), patch.object(core,"fingerprint",return_value=current), self.assertRaisesRegex(ParityError,"hash mismatch"): verify_freshness(run)
            (run/"data.txt").write_text("x")
            outside=Path(directory)/"outside"; outside.write_text("secret"); link=run/"link"; link.symlink_to(outside)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"symlinked"): core.index_run(run)
            link.unlink()
            source_digest=load(run/"evidence-index.json")["source_evidence_sha256"]; write(run/"baseline-matrix.json",{"source_evidence_sha256":source_digest}); (run/"metrics").mkdir(); write(run/"metrics/wrapper.json",{"source_evidence_sha256":source_digest})
            with patch.object(core,"ARTIFACTS",artifacts): rebound=core.index_run(run)
            self.assertEqual(rebound["source_evidence_sha256"],source_digest)
            with patch.object(core,"ARTIFACTS",artifacts), patch.object(core,"fingerprint",return_value=current): review_packet(run); self.assertTrue(verify_freshness(run)["fresh"])
            self.assertEqual(load(run/"evidence-index.json")["source_evidence_sha256"],source_digest)
            (run/"data.txt").write_text("mutated-after-seal")
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"fingerprint",return_value=current),self.assertRaisesRegex(ParityError,"hash mismatch"): verify_freshness(run)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"review-bound"): core.index_run(run)
            with patch.object(core,"ARTIFACTS",artifacts), self.assertRaisesRegex(ParityError,"cannot be renewed"): review_packet(run)

    def test_structured_provenance_rejects_self_approval_and_bad_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); artifact=root/"approval.txt"; artifact.write_text("approved")
            record={"status":"approved","disposition":"PASS","identity":"reviewer","role":"independent-reviewer","recorded_at":"2026-08-01T00:00:00Z","authority_artifact":"approval.txt","authority_sha256":digest(artifact),"evidence_index_sha256":"a"*64}
            self.assertEqual(validate_provenance(record,root=root,allowed_dispositions={"PASS"},required_role="independent-reviewer")["identity"],"reviewer")
            with self.assertRaisesRegex(ParityError,"self-approved"): validate_provenance(record,root=root,allowed_dispositions={"PASS"},required_role="independent-reviewer",distinct_from="reviewer")
            record["authority_sha256"]="0"*64
            with self.assertRaisesRegex(ParityError,"hash mismatch"): validate_provenance(record,root=root,allowed_dispositions={"PASS"},required_role="independent-reviewer")

    def test_native_plan_keeps_every_fixture_non_exact_and_all_gates_blocked(self):
        rows=native_plan()["records"]
        self.assertEqual(len(rows),39)
        self.assertFalse(any(row["status"]=="exact" for row in rows))
        for gate in ("0A","0B","0C"):
            with self.assertRaises(ParityError): verify_gate(gate,None)
        self.assertEqual(core._unresolved_authority(),["PI-REF-001","PI-REF-002","PI-REF-003"])

    def test_applicability_expands_nonstandard_variants_as_platform_adaptation_authority(self):
        expanded={(row["scenario"],row["variant"]):row for row in core._expanded_applicability() if row["profile"]=="notch-v1"}
        standard=expanded[("A1-idle","standard")]; self.assertEqual(standard["authority_class"],"rendered-canonical"); self.assertEqual(standard["evidence_roles"],["reference","native"])
        visual=expanded[("A1-idle","reduced-motion")]; self.assertEqual(visual["authority_class"],"platform-adaptation"); self.assertEqual(visual["evidence_roles"],["authority","native"]); self.assertEqual(visual["evidence_families"],["adaptation-authority","visual-a11y"]); self.assertIn("accessibility",visual["metric_families"])
        interaction=expanded[("A1-idle","voiceover")]; self.assertEqual(interaction["evidence_families"],["adaptation-authority","interaction-a11y"]); self.assertEqual(interaction["metric_families"],["interaction","accessibility"])

    def test_manifest_verification_rejects_malformed_calibration_bundle_authority(self):
        original=load(core.VALIDATION/"calibration-bundle-authority-v1.json")
        malformed={**original,"unexpected":True}
        real_load=core.load
        def substituted(path):
            return malformed if Path(path).name=="calibration-bundle-authority-v1.json" else real_load(path)
        with patch.object(core,"load",side_effect=substituted),self.assertRaisesRegex(ParityError,"bundle authority schema drift"):
            core.verify_manifests()

    def test_incomplete_baseline_matrix_and_null_or_unsupported_metrics_block(self):
        with self.assertRaisesRegex(ParityError,"applicability authority is pending"):
            verify_baseline_matrix({"records":[]})
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name in ("calibration","static","motion","geometry","light","text"):
                write(root/f"{name}.json",{"overall_screening_status":"passed","metrics":{"required":{"status":"unsupported","value":None}}})
            with self.assertRaisesRegex(ParityError,"canonical run and index"):
                verify_metric_reports(root)

    def test_approved_shape_baseline_and_metrics_reject_fake_evidence_and_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); shutil.copy2(core.VALIDATION/"ledger-v1.json",run/"ledger.json")
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            applicability=load(core.VALIDATION/"applicability-v1.json"); applicability["status"]="approved"; expanded=core._expanded_from_value(applicability)
            records=[]
            for row in expanded:
                records.append({"scenario":row["scenario"],"profile":row["profile"],"variant":row["variant"],"authority_class":row["authority_class"],"complete":True,"ledger_ids":row["ledger_ids"],"evidence":[],"source_evidence_sha256":index["source_evidence_sha256"]})
            records[0]["ledger_ids"]=["FAKE-LEDGER"]
            matrix={"schema_version":1,"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"ledger_sha256":digest(run/"ledger.json"),"source_evidence_sha256":index["source_evidence_sha256"],"records":records}
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"caller-supplied applicability"): core.verify_baseline_matrix(matrix,run,index,applicability)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"ledger relevance"): core._verify_baseline_candidate(matrix,run,index,applicability)
            records[0]["ledger_ids"]=expanded[0]["ledger_ids"]; records[0]["evidence"]=[{"role":"reference","path":"missing.png","sha256":"0"*64,"sidecar_path":"missing.json","sidecar_sha256":"0"*64,"disposition":"exact"}]
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"evidence count differs"): core._verify_baseline_candidate(matrix,run,index,applicability)
            records[0]["evidence"]=[{"role":role,"path":"missing.png","sha256":"0"*64,"sidecar_path":"missing.json","sidecar_sha256":"0"*64,"disposition":"exact"} for role in expanded[0]["evidence_roles"]]
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"missing evidence|absent"): core._verify_baseline_candidate(matrix,run,index,applicability)

    def test_baseline_rejects_surplus_evidence_entries_beyond_applicable_families(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); shutil.copy2(core.VALIDATION/"ledger-v1.json",run/"ledger.json")
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            applicability=load(core.VALIDATION/"applicability-v1.json"); applicability["status"]="approved"; expanded=core._expanded_from_value(applicability)
            def entry(role): return {"role":role,"path":"missing.png","sha256":"0"*64,"sidecar_path":"missing.json","sidecar_sha256":"0"*64,"disposition":"exact"}
            records=[{"scenario":row["scenario"],"profile":row["profile"],"variant":row["variant"],"authority_class":row["authority_class"],"complete":True,"ledger_ids":row["ledger_ids"],"evidence":[entry(role) for role in row["evidence_roles"]],"source_evidence_sha256":index["source_evidence_sha256"]} for row in expanded]
            # One surplus entry beyond the applicable families used to be silently
            # dropped by zip(..., strict=False): never hashed, role-checked, or
            # entered into the reuse ledgers.
            records[0]["evidence"].append(entry("native"))
            matrix={"schema_version":1,"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"ledger_sha256":digest(run/"ledger.json"),"source_evidence_sha256":index["source_evidence_sha256"],"records":records}
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"evidence count differs"): core._verify_baseline_candidate(matrix,run,index,applicability)

    def test_baseline_rejects_702_rows_reusing_six_plain_text_artifacts_and_sidecars(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); shutil.copy2(core.VALIDATION/"ledger-v1.json",run/"ledger.json")
            files=[]
            for number in range(6):
                path=run/f"reused-{number}.txt"; path.write_text(f"plain evidence {number}"); files.append(path)
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            applicability=load(core.VALIDATION/"applicability-v1.json"); applicability["status"]="approved"; expanded=core._expanded_from_value(applicability); records=[]
            for row_index,row in enumerate(expanded):
                evidence=[]
                for role_index,role in enumerate(row["evidence_roles"]):
                    artifact=files[(row_index+role_index)%3]; sidecar=files[3+(row_index+role_index)%3]
                    evidence.append({"role":role,"path":artifact.name,"sha256":digest(artifact),"sidecar_path":sidecar.name,"sidecar_sha256":digest(sidecar),"disposition":"exact"})
                records.append({"scenario":row["scenario"],"profile":row["profile"],"variant":row["variant"],"authority_class":row["authority_class"],"complete":True,"ledger_ids":row["ledger_ids"],"evidence":evidence,"source_evidence_sha256":index["source_evidence_sha256"]})
            self.assertEqual(len(records),702)
            matrix={"schema_version":1,"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"ledger_sha256":digest(run/"ledger.json"),"source_evidence_sha256":index["source_evidence_sha256"],"records":records}
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"sidecar is not valid JSON"): core._verify_baseline_candidate(matrix,run,index,applicability)

    def test_metric_wrappers_reject_plain_text_mismatched_context_and_unsupported_generators(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); shutil.copy2(core.VALIDATION/"ledger-v1.json",run/"ledger.json"); source=run/"comparisons/source.txt"; source.parent.mkdir(parents=True); source.write_text("not json"); metrics=run/"metrics"; metrics.mkdir()
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            variant_rules=load(core.VALIDATION/"applicability-v1.json")["variant_rules"]
            applicability={"profiles":["notch-v1"],"variants":["standard"],"variant_rules":variant_rules,"records":[{"scenario":"A1-idle","authority_class":"rendered-canonical","evidence_roles":["reference","native"],"mask_roles":["reference","native"],"metric_families":["static"],"ledger_ids":["PI-V-001"]}]}
            bindings={"ledger_sha256":digest(run/"ledger.json"),"source_evidence_sha256":index["source_evidence_sha256"],"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"calibration_sha256":core.tree_hash([core.VALIDATION/"calibration-v1.json",core.VALIDATION/"calibration-bundle-authority-v1.json"]),"mask_policy_sha256":digest(core.VALIDATION/"mask-policy-v1.json"),"thresholds_sha256":digest(core.VALIDATION/"measurements-v1.json")}
            static_metrics={name:{"status":"passed","value":1,"unit":"unit"} for name in load(core.VALIDATION/"metric-report-schema-v1.json")["metrics_by_family"]["static"]}
            wrapper={"schema_version":1,"family":"static","scenario":"A1-idle","profile":"notch-v1","variant":"standard","authority_class":"rendered-canonical","bindings":bindings,"source_report":{"path":"comparisons/source.txt","sha256":digest(source)},"overall_screening_status":"passed","metrics":static_metrics}; write(metrics/"wrapper.json",wrapper)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"caller-supplied applicability"): verify_metric_reports(metrics,run,index,applicability)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"not recognized JSON"): core._verify_metric_candidates(metrics,run,index,applicability)
            write(source,{"context":{"scenario":"A2-working-one","profile":"notch-v1","variant":"standard","authority_class":"rendered-canonical"},"overall_screening_status":"passed"})
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            wrapper["bindings"]["source_evidence_sha256"]=index["source_evidence_sha256"]; wrapper["source_report"]["sha256"]=digest(source); write(metrics/"wrapper.json",wrapper)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"context/status"): core._verify_metric_candidates(metrics,run,index,applicability)
            applicability["records"][0]["metric_families"]=["interaction"]; wrapper["family"]="interaction"; wrapper["metrics"]={"interaction_contract":{"status":"passed","value":True,"unit":"boolean"}}; write(metrics/"wrapper.json",wrapper)
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"generator is unsupported"): core._verify_metric_candidates(metrics,run,index,applicability)

    def test_motion_metric_wrapper_rejects_value_different_from_recomputed_generator(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); shutil.copy2(core.VALIDATION/"ledger-v1.json",run/"ledger.json"); source_manifest=run/"motion/source.json"; source_manifest.parent.mkdir(parents=True); write(source_manifest,{"placeholder":True})
            generated_path=run/"motion/generated/report.json"; generated_path.parent.mkdir(parents=True); generated={"schema_version":1,"generator":"poured-motion-v1","scenario":"KX-breath-css","profile":"notch-v1","variant":"standard","authority_class":"rendered-motion-exemplar","disposition":"exact","source_manifest":{"path":"motion/source.json","sha256":digest(source_manifest)},"runtime":{},"runs":[{"timing_jitter":0.001,"duplicates":0,"drops":0}],"capture_sidecar_sha256":"a"*64,"clock_attestation_sha256":"b"*64,"status":"measured"}; write(generated_path,generated)
            metrics=run/"metrics"; metrics.mkdir()
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            app_value=load(core.VALIDATION/"applicability-v1.json"); applicability={"profiles":["notch-v1"],"variants":["standard"],"variant_rules":app_value["variant_rules"],"records":[{"scenario":"KX-breath-css","authority_class":"rendered-motion-exemplar","evidence_roles":["reference","native"],"mask_roles":[],"metric_families":["motion"],"ledger_ids":["PI-V-001"]}]}
            bindings={"ledger_sha256":digest(run/"ledger.json"),"source_evidence_sha256":index["source_evidence_sha256"],"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"calibration_sha256":core.tree_hash([core.VALIDATION/"calibration-v1.json",core.VALIDATION/"calibration-bundle-authority-v1.json"]),"mask_policy_sha256":digest(core.VALIDATION/"mask-policy-v1.json"),"thresholds_sha256":digest(core.VALIDATION/"measurements-v1.json")}
            wrapper={"schema_version":1,"family":"motion","scenario":"KX-breath-css","profile":"notch-v1","variant":"standard","authority_class":"rendered-motion-exemplar","bindings":bindings,"source_report":{"path":"motion/generated/report.json","sha256":digest(generated_path)},"overall_screening_status":"passed","metrics":{"timing_jitter":{"status":"passed","value":999,"unit":"seconds"},"duplicates":{"status":"passed","value":0,"unit":"count"},"drops":{"status":"passed","value":0,"unit":"count"}}}; write(metrics/"wrapper.json",wrapper)
            with patch.object(core,"ARTIFACTS",artifacts),patch.object(core,"_validated_motion_report",return_value=generated),self.assertRaisesRegex(ParityError,"wrapper metric differs"): core._verify_metric_candidates(metrics,run,index,applicability)

    def test_direct_gate0b_and_stale_review_packet_fail_closed(self):
        with self.assertRaisesRegex(ParityError,"candidate run"): core._verify_gate0b_candidate(None)
        with tempfile.TemporaryDirectory() as directory:
            artifacts,run=self._temporary_run(directory); write(run/"ledger.json",load(core.VALIDATION/"ledger-v1.json")); manifest=load(run/"manifest.json")
            with patch.object(core,"ARTIFACTS",artifacts): index=core.index_run(run)
            packet={"schema_version":1,"created_at":"2026-08-01T00:00:00Z","run":manifest["artifact_root"],"bound_evidence_set_sha256":index["evidence_set_sha256"],"pre_review_index_sha256":"a"*64,"calibration_sha256":digest(core.VALIDATION/"calibration-v1.json"),"calibration_bundle_authority_sha256":digest(core.VALIDATION/"calibration-bundle-authority-v1.json"),"applicability_sha256":digest(core.VALIDATION/"applicability-v1.json"),"adaptations_sha256":digest(core.VALIDATION/"adaptations-v1.json"),"conflicts_sha256":digest(core.VALIDATION/"conflicts-v1.json"),"principals_sha256":digest(core.VALIDATION/"principals-v1.json"),"motion_authority_sha256":digest(core.VALIDATION/"motion-authority-v1.json"),"runtime_authority_sha256":digest(core.VALIDATION/"runtime-v1.json"),"scenario_class_matrix":core.verify_manifests()["class_counts"],"unresolved_authority":core._unresolved_authority(run),"mask_policy_sha256":digest(core.VALIDATION/"mask-policy-v1.json"),"thresholds_sha256":digest(core.VALIDATION/"measurements-v1.json"),"ledger_snapshot_sha256":"0"*64,"environment_sha256":core._json_digest(manifest["environment"]),"bindings_sha256":core._json_digest(manifest["bindings"]),"genesis_sha256":None,"baseline_adequacy":{},"parity_claim":False}
            with patch.object(core,"ARTIFACTS",artifacts),self.assertRaisesRegex(ParityError,"stale or forged"): core._validate_review_packet(run,packet,manifest,index)

    def test_cli_rejects_out_of_run_evidence_outputs(self):
        self.assertEqual(cli_main(["reference-plan","--output","/tmp/poured-plan.json"]),2)
        self.assertEqual(cli_main(["calibrate-analyze","/tmp/missing.json","--output","/tmp/poured-calibration.json"]),2)


if __name__=="__main__": unittest.main()
