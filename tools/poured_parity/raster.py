from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import binary_erosion, distance_transform_edt

from .trust import TrustError, contained_path, digest, iso_timestamp, read_json


RENDERERS = {"css", "swiftui"}
FIDUCIALS = {"nw", "ne", "sw", "se"}
CALIBRATION_LIMITS = {"mapping_residual_max","declared_scale_residual_max","landmark_repeatability_max","cross_renderer_residual_max","pixel_noise_mean_max","color_variance_mean_max","timing_jitter_max","duplicates_max","drops_max"}


def _number(value: Any, label: str, minimum: float | None = None) -> float:
    if type(value) not in {int,float} or not math.isfinite(value) or (minimum is not None and value<minimum):
        raise TrustError(f"{label} must be a finite numeric value")
    return float(value)


def _image(path: Path, mode: str = "RGBA") -> np.ndarray:
    try:
        with Image.open(path) as source:
            source.load()
            return np.asarray(source.convert(mode))
    except Exception as exc:
        raise TrustError(f"cannot decode raster {path}: {exc}") from exc


def _asset(base: Path, record: dict[str, Any], expected_size: tuple[int, int] | None = None) -> tuple[Path, np.ndarray]:
    path = contained_path(base, record.get("path", ""), require_file=True)
    if digest(path) != record.get("sha256"):
        raise TrustError(f"asset hash mismatch: {record.get('path')}")
    raster = _image(path)
    size = (raster.shape[1], raster.shape[0])
    if record.get("dimensions") != list(size) or (expected_size and size != expected_size):
        raise TrustError(f"asset dimensions mismatch: {record.get('path')}")
    return path, raster


def _fiducials(value: Any) -> dict[str, list[float]]:
    if not isinstance(value, dict) or set(value) != FIDUCIALS:
        raise TrustError("exactly four named fiducials nw/ne/sw/se are required")
    for point in value.values():
        if not isinstance(point, list) or len(point) != 2 or not all(type(v) in {int,float} and math.isfinite(v) for v in point):
            raise TrustError("fiducial coordinates must be numeric pairs")
    return value


def _validate_corner_geometry(value: dict[str,list[float]],label: str) -> None:
    nw,ne,sw,se=(value[x] for x in ("nw","ne","sw","se"))
    if not (nw[0]<ne[0] and sw[0]<se[0] and nw[1]<sw[1] and ne[1]<se[1]): raise TrustError(f"{label} fiducial geometry is degenerate or reflected")


def _validate_frames(base: Path, frames: list[dict[str, Any]], expected_size: tuple[int, int] | None = None) -> tuple[list[np.ndarray], list[float], int, int, float]:
    if len(frames) < 2:
        raise TrustError("motion run requires at least two decoded frames")
    arrays: list[np.ndarray] = []
    pts: list[float] = []
    size = expected_size
    for frame in frames:
        _, array = _asset(base, frame, size)
        if size is None:
            size = (array.shape[1], array.shape[0])
        arrays.append(array)
        point = frame.get("pts")
        if type(point) not in {int,float} or not math.isfinite(point) or point < 0:
            raise TrustError("frame PTS must be nonnegative numeric values")
        pts.append(float(point))
    intervals = np.diff(pts)
    if np.any(intervals <= 0):
        raise TrustError("frame PTS must be strictly monotonic")
    tolerance = 0.002
    if float(np.median(intervals)) > 1 / 60 + tolerance:
        raise TrustError("motion cadence is below 60 fps")
    hashes = [frame["sha256"] for frame in frames]
    duplicates = sum(a == b for a, b in zip(hashes, hashes[1:]))
    expected = float(np.median(intervals))
    drops = int(sum(max(0, round(value / expected) - 1) for value in intervals))
    jitter = float(np.max(np.abs(intervals - expected)))
    return arrays, pts, duplicates, drops, jitter


def _json_digest(value: Any) -> str:
    return __import__("hashlib").sha256(json.dumps(value,sort_keys=True,separators=(",",":")).encode()).hexdigest()


def analyze_calibration(path: Path, authority: dict[str,Any], runtime: dict[str,Any], run_manifest: dict[str,Any]) -> dict[str, Any]:
    value=read_json(path); base=path.parent
    required_input={"schema_version","run_artifact_root","environment_sha256","bindings_sha256","capture_session_id","capture_metadata","content_role","source_role","poured_source_hashes","required_renderers","logical_size","logical_fiducials","captured_scale","color_profile","target_id","stills","motion_runs"}
    if not isinstance(value,dict) or set(value)!=required_input or value.get("schema_version")!=1: raise TrustError("calibration input schema mismatch")
    metadata=value.get("capture_metadata"); expected_metadata={"captured_at":metadata.get("captured_at") if isinstance(metadata,dict) else None,"target_executable_sha256":run_manifest.get("environment",{}).get("target",{}).get("executable_sha256"),"capture_helper_sha256":run_manifest.get("environment",{}).get("capture",{}).get("helper_sha256"),"display_identity":run_manifest.get("environment",{}).get("display",{}).get("stable_identity")}
    if value.get("run_artifact_root")!=run_manifest.get("artifact_root") or value.get("environment_sha256")!=_json_digest(run_manifest.get("environment")) or value.get("bindings_sha256")!=_json_digest(run_manifest.get("bindings")) or not isinstance(value.get("capture_session_id"),str) or not value["capture_session_id"] or not isinstance(metadata,dict) or set(metadata)!={"captured_at","target_executable_sha256","capture_helper_sha256","display_identity"} or not iso_timestamp(metadata.get("captured_at")) or metadata!=expected_metadata: raise TrustError("calibration input does not bind its canonical run/capture identity")
    if value.get("content_role")!="neutral-calibration" or value.get("source_role")!="neutral-primitives" or value.get("poured_source_hashes"): raise TrustError("calibration input must be neutral-only")
    if set(value.get("required_renderers",[]))!=RENDERERS: raise TrustError("calibration requires css and swiftui renderers")
    logical=value.get("logical_size"); declared_scale=_number(value.get("captured_scale"),"captured scale",1); profile=value.get("color_profile"); target=value.get("target_id"); logical_fiducials=_fiducials(value.get("logical_fiducials")); _validate_corner_geometry(logical_fiducials,"logical")
    configured=isinstance(authority,dict) and authority.get("status")=="approved" and authority.get("target_id") is not None and authority.get("color_profile") is not None and authority.get("aa_band") is not None and isinstance(authority.get("limits"),dict) and set(authority["limits"])==CALIBRATION_LIMITS and all(type(x) in {int,float} and math.isfinite(x) for x in authority["limits"].values())
    limits=authority.get("limits") if configured else None
    if configured and (target!=authority["target_id"] or profile!=authority["color_profile"]): raise TrustError("calibration target/profile differs from committed authority")
    if not (isinstance(logical,list) and len(logical)==2 and all(type(x) is int and x>0 for x in logical) and isinstance(profile,str) and profile and isinstance(target,str) and target): raise TrustError("calibration logical size/profile/target are invalid")
    expected_size=(round(logical[0]*declared_scale),round(logical[1]*declared_scale)); logical_points=np.asarray([logical_fiducials[name] for name in sorted(FIDUCIALS)],dtype=float)
    groups={renderer:[] for renderer in RENDERERS}; repetitions={renderer:set() for renderer in RENDERERS}; points={renderer:[] for renderer in RENDERERS}; fits={renderer:[] for renderer in RENDERERS}; assets=[]; sample_ids=set(); capture_ids=set(); asset_paths=set(); asset_hashes=set()
    def fit(renderer,captured,identity):
        device=np.asarray([captured[name] for name in sorted(FIDUCIALS)],dtype=float); lc=logical_points-logical_points.mean(axis=0); dc=device-device.mean(axis=0); denominator=float(np.sum(lc*lc))
        if denominator<=0: raise TrustError("logical fiducial geometry is degenerate")
        _validate_corner_geometry(captured,"captured"); measured=float(np.sum(lc*dc)/denominator)
        if measured<=0: raise TrustError("fitted calibration scale must be positive")
        translation=device.mean(axis=0)-measured*logical_points.mean(axis=0); residual=np.linalg.norm(logical_points*measured+translation-device,axis=1)
        fits[renderer].append({"identity":identity,"measured_scale":measured,"translation":translation.tolist(),"residuals":{name:float(residual[i]) for i,name in enumerate(sorted(FIDUCIALS))},"residual_max":float(residual.max())})
    for sample in value.get("stills",[]):
        renderer=sample.get("renderer"); sample_id=sample.get("sample_id"); capture_id=sample.get("capture_id"); repetition=sample.get("repetition"); asset_path=sample.get("path")
        if renderer not in RENDERERS or sample.get("target_id")!=target or sample.get("profile")!=profile or sample.get("scale")!=declared_scale or not isinstance(sample_id,str) or not sample_id or sample_id in sample_ids or not isinstance(capture_id,str) or not capture_id or capture_id in capture_ids or not isinstance(asset_path,str) or asset_path in asset_paths or sample.get("sha256") in asset_hashes or type(repetition) is not int or repetition<0 or repetition in repetitions[renderer]: raise TrustError("still/capture/path/content SHA-256 identity or renderer/target/profile/scale is invalid or duplicated")
        sample_ids.add(sample_id); capture_ids.add(capture_id); asset_paths.add(asset_path); asset_hashes.add(sample["sha256"]); repetitions[renderer].add(repetition); fiducials=_fiducials(sample.get("fiducials")); _,raster=_asset(base,sample,expected_size)
        if any(not (0<=point[0]<expected_size[0] and 0<=point[1]<expected_size[1]) for point in fiducials.values()): raise TrustError("captured fiducial lies outside image bounds")
        fit(renderer,fiducials,sample_id); groups[renderer].append(raster.astype(float)); points[renderer].append([fiducials[name] for name in sorted(FIDUCIALS)]); assets.append({"path":asset_path,"sha256":sample["sha256"],"capture_id":capture_id})
    for renderer in RENDERERS:
        if len(groups[renderer])<5: raise TrustError(f"renderer {renderer} requires at least five neutral stills")
    motions={renderer:[] for renderer in RENDERERS}; motion_ids=set()
    for run in value.get("motion_runs",[]):
        renderer=run.get("renderer"); run_id=run.get("run_id"); run_capture=run.get("capture_id")
        if renderer not in RENDERERS or run.get("target_id")!=target or run.get("profile")!=profile or run.get("scale")!=declared_scale or not isinstance(run_id,str) or not run_id or run_id in motion_ids or not isinstance(run_capture,str) or not run_capture or run_capture in capture_ids: raise TrustError("motion/capture identity or renderer/target/profile/scale is invalid or duplicated")
        motion_ids.add(run_id); capture_ids.add(run_capture); fiducials=_fiducials(run.get("fiducials"));
        if any(not (0<=point[0]<expected_size[0] and 0<=point[1]<expected_size[1]) for point in fiducials.values()): raise TrustError("captured fiducial lies outside image bounds")
        frames=run.get("frames",[])
        for frame in frames:
            capture_id=frame.get("capture_id"); asset_path=frame.get("path")
            if not isinstance(capture_id,str) or not capture_id or capture_id in capture_ids or not isinstance(asset_path,str) or asset_path in asset_paths or frame.get("sha256") in asset_hashes: raise TrustError("motion frame capture/path/content SHA-256 identity is missing or reused")
            capture_ids.add(capture_id); asset_paths.add(asset_path); asset_hashes.add(frame["sha256"])
        fit(renderer,fiducials,run_id); _,pts,duplicates,drops,jitter=_validate_frames(base,frames,expected_size); motions[renderer].append({"run_id":run_id,"capture_id":run_capture,"pts_intervals":np.diff(pts).tolist(),"duplicates":duplicates,"drops":drops,"timing_jitter":jitter}); assets.extend({"path":frame["path"],"sha256":frame["sha256"],"capture_id":frame["capture_id"]} for frame in frames)
    if any(len(motions[renderer])<3 for renderer in RENDERERS): raise TrustError("each renderer requires at least three unique neutral motion runs")
    reports={}
    for renderer in sorted(RENDERERS):
        stack=np.stack(groups[renderer]); point_array=np.asarray(points[renderer]); scales=np.asarray([x["measured_scale"] for x in fits[renderer]]); translations=np.asarray([x["translation"] for x in fits[renderer]])
        repeatability={name:{"x_std":float(np.std(point_array[:,i,0])),"y_std":float(np.std(point_array[:,i,1])),"radial_std":float(np.linalg.norm(np.std(point_array[:,i,:],axis=0)))} for i,name in enumerate(sorted(FIDUCIALS))}
        reports[renderer]={"still_count":len(stack),"pixel_noise_mean":float(np.mean(np.std(stack,axis=0))),"color_variance_mean":float(np.mean(np.var(stack[...,:3],axis=0))),"landmark_repeatability":repeatability,"landmark_repeatability_max":max(x["radial_std"] for x in repeatability.values()),"mapping_fits":fits[renderer],"scale_distribution":{"mean":float(np.mean(scales)),"std":float(np.std(scales)),"min":float(np.min(scales)),"max":float(np.max(scales))},"translation_distribution":{"mean":np.mean(translations,axis=0).tolist(),"std":np.std(translations,axis=0).tolist()},"declared_scale_residual_max":float(np.max(np.abs(scales-declared_scale))),"mapping_residual_max":float(max(x["residual_max"] for x in fits[renderer])),"motion_runs":motions[renderer]}
    predicted={renderer:logical_points*reports[renderer]["scale_distribution"]["mean"]+np.asarray(reports[renderer]["translation_distribution"]["mean"]) for renderer in RENDERERS}; cross_by_landmark={name:float(np.linalg.norm(predicted["css"][i]-predicted["swiftui"][i])) for i,name in enumerate(sorted(FIDUCIALS))}; cross=max(cross_by_landmark.values()); checks=[]
    if configured:
        checks=[cross<=limits["cross_renderer_residual_max"]]
        for item in reports.values():
            checks += [item["mapping_residual_max"]<=limits["mapping_residual_max"],item["declared_scale_residual_max"]<=limits["declared_scale_residual_max"],item["landmark_repeatability_max"]<=limits["landmark_repeatability_max"],item["pixel_noise_mean"]<=limits["pixel_noise_mean_max"],item["color_variance_mean"]<=limits["color_variance_mean_max"]]
            for run in item["motion_runs"]: checks += [run["duplicates"]<=limits["duplicates_max"],run["drops"]<=limits["drops_max"],run["timing_jitter"]<=limits["timing_jitter_max"]]
    capture_independent=bool(run_manifest.get("canonical_ready")) and all(metadata.get(key) is not None for key in ("target_executable_sha256","capture_helper_sha256","display_identity"))
    ready=configured and capture_independent and all(checks)
    return {"schema_version":1,"input_manifest":path.name,"input_sha256":digest(path),"run_artifact_root":value["run_artifact_root"],"environment_sha256":value["environment_sha256"],"bindings_sha256":value["bindings_sha256"],"capture_session_id":value["capture_session_id"],"capture_metadata":metadata,"capture_independence_attested":capture_independent,"neutral_only":True,"target_id":target,"logical_size":logical,"declared_scale":declared_scale,"captured_dimensions":list(expected_size),"color_profile":profile,"logical_fiducials":logical_fiducials,"renderers":reports,"cross_renderer_landmark_residuals":cross_by_landmark,"cross_renderer_residual":cross,"limits":limits,"authority_sha256":digest(Path(authority["_path"])) if authority.get("_path") else None,"runtime":runtime,"asset_bindings":sorted(assets,key=lambda x:x["path"]),"status":"ready" if ready else "diagnostic","ready":ready}


def freeze_calibration(analysis_path: Path, output: Path, mask_manifest: Path, aa_band: int, thresholds: Path, provenance: dict[str, Any], authority: dict[str,Any], runtime: dict[str,Any], run_manifest: dict[str,Any]) -> dict[str, Any]:
    analysis = read_json(analysis_path)
    source = analysis_path.parent / analysis.get("input_manifest", "")
    recomputed = analyze_calibration(source,authority,runtime,run_manifest)
    if analysis != recomputed or not recomputed.get("ready"):
        raise TrustError("calibration analysis is stale, forged, or not ready")
    if aa_band < 0 or not mask_manifest.is_file() or not thresholds.is_file():
        raise TrustError("mask bundle, nonnegative AA band, and thresholds are required")
    frozen = {**recomputed, "calibration_version": 1, "analysis_path":analysis_path.name, "analysis_sha256": digest(analysis_path), "mask_manifest_sha256": digest(mask_manifest), "thresholds_sha256": digest(thresholds), "aa_band_device_px": aa_band, "approval": provenance, "status": "approved"}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(frozen, indent=2, sort_keys=True) + "\n")
    return frozen


def _rect(draw: ImageDraw.ImageDraw, rect: list[int]) -> None:
    if not isinstance(rect, list) or len(rect) != 4 or not all(isinstance(v, int) for v in rect):
        raise TrustError("mask rectangles must be four integers")
    draw.rectangle((rect[0], rect[1], rect[2] - 1, rect[3] - 1), fill=255)


def _scope_key(value: dict[str, Any]) -> tuple[str, str, str, str]:
    result=(value.get("scenario"),value.get("profile"),value.get("variant"),value.get("capture_role"))
    if not all(isinstance(item,str) and item for item in result) or result[3] not in {"reference","native","shared"}: raise TrustError("mask scope requires scenario, profile, variant, and capture role")
    return result


def _draw_mask(size: tuple[int,int], rects: Any) -> np.ndarray:
    if not isinstance(rects,list): raise TrustError("mask rectangle collection must be an array")
    image=Image.new("L",size,0); draw=ImageDraw.Draw(image)
    for rect in rects:
        if not isinstance(rect,list) or len(rect)!=4 or not all(type(x) is int for x in rect) or not (0<=rect[0]<rect[2]<=size[0] and 0<=rect[1]<rect[3]<=size[1]): raise TrustError("mask rectangle is empty or outside annotation dimensions")
        _rect(draw,rect)
    return np.asarray(image)


def _mask_capture(scope: dict[str,Any],run_root: Path,run_manifest: dict[str,Any],dimensions: list[int]) -> dict[str,Any]:
    record=scope.get("capture_sidecar")
    if not isinstance(record,dict) or set(record)!={"path","sha256"}: raise TrustError("mask scope lacks exact capture sidecar provenance")
    sidecar_path=contained_path(run_root,record["path"],require_file=True)
    if digest(sidecar_path)!=record["sha256"]: raise TrustError("mask capture sidecar hash mismatch")
    sidecar=read_json(sidecar_path); required={"schema_version","scenario","profile","variant","capture_role","capture_id","captured_at","environment_sha256","bindings_sha256","artifact"}
    if not isinstance(sidecar,dict) or set(sidecar)!=required or sidecar.get("schema_version")!=1 or any(sidecar.get(key)!=scope.get(key) for key in ("scenario","profile","variant","capture_role")) or not isinstance(sidecar.get("capture_id"),str) or not sidecar["capture_id"] or not iso_timestamp(sidecar.get("captured_at")) or sidecar.get("environment_sha256")!=_json_digest(run_manifest.get("environment")) or sidecar.get("bindings_sha256")!=_json_digest(run_manifest.get("bindings")): raise TrustError("mask capture sidecar context/run identity mismatch")
    artifact=sidecar.get("artifact")
    if not isinstance(artifact,dict) or set(artifact)!={"path","sha256","dimensions"} or artifact.get("dimensions")!=dimensions: raise TrustError("mask capture artifact schema/dimensions mismatch")
    artifact_path=contained_path(run_root,artifact["path"],require_file=True)
    if digest(artifact_path)!=artifact["sha256"]: raise TrustError("mask capture artifact hash mismatch")
    return record


def generate_masks(annotation_path: Path, output: Path, required_families: set[str], empty_families: set[str], run_root: Path, run_manifest: dict[str,Any]) -> dict[str, Any]:
    value = read_json(annotation_path)
    width, height = value.get("dimensions", [None, None])
    if not all(isinstance(v, int) and v > 0 for v in (width, height)):
        raise TrustError("mask annotation dimensions are invalid")
    output.mkdir(parents=True, exist_ok=True)
    if not isinstance(value,dict) or set(value)!={"schema_version","dimensions","scopes"} or value.get("schema_version")!=1 or not isinstance(value.get("scopes"),list) or not value["scopes"]:
        raise TrustError("mask annotation schema is invalid or empty")
    records = []; seen=set()
    for scope in value["scopes"]:
        if not isinstance(scope,dict) or set(scope)!={"scenario","profile","variant","capture_role","capture_sidecar","families","owned_text_rects","owned_content_rects","os_external_rects"}: raise TrustError("mask annotation scope schema mismatch")
        scenario, profile, variant, capture_role = _scope_key(scope)
        if (scenario,profile,variant,capture_role) in seen: raise TrustError("duplicate mask annotation scope")
        seen.add((scenario,profile,variant,capture_role))
        _mask_capture(scope,run_root,run_manifest,[width,height]); annotations = scope.get("families", {})
        if set(annotations) != required_families:
            raise TrustError(f"mask families incomplete for {scenario}/{profile}")
        for family in sorted(required_families):
            array=_draw_mask((width,height),annotations[family])
            if not np.any(array) and family not in empty_families: raise TrustError(f"mask family is empty for {scenario}/{profile}/{variant}/{capture_role}/{family}")
            image=Image.fromarray(array,mode="L")
            name = f"{scenario}--{profile}--{variant}--{capture_role}--{family.replace('/', '_')}.png"
            path = output / name
            image.save(path, format="PNG", optimize=False)
            records.append({"scenario": scenario, "profile": profile, "variant":variant,"capture_role":capture_role, "family": family, "dimensions": [width, height], "path": name, "sha256": digest(path), "coverage_pixels": int(np.count_nonzero(array))})
    relative=str(annotation_path.relative_to(run_root)) if annotation_path.is_relative_to(run_root) else None
    if relative is None: raise TrustError("mask reconstruction input must share the output artifact run")
    manifest = {"schema_version": 1, "reconstruction_input": relative, "reconstruction_sha256": digest(annotation_path), "dimensions": [width, height], "scopes": [{key:x[key] for key in ("scenario","profile","variant","capture_role","capture_sidecar","owned_text_rects","owned_content_rects","os_external_rects")} for x in value["scopes"]], "masks": records}
    manifest_path = output / "masks.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def _rect_mask(size: tuple[int, int], rects: list[list[int]]) -> np.ndarray:
    image = Image.new("1", size, 0)
    draw = ImageDraw.Draw(image)
    for rect in rects:
        _rect(draw, rect)
    return np.asarray(image, dtype=bool)


def verify_masks(manifest_path: Path, required_families: set[str], empty_families: set[str], allowed_scopes: set[tuple[str,str,str,str]], run_root: Path, run_manifest: dict[str,Any]) -> dict[str, Any]:
    value = read_json(manifest_path)
    base = manifest_path.parent
    reconstruction = contained_path(run_root,value.get("reconstruction_input", ""),require_file=True)
    if not reconstruction.is_file() or digest(reconstruction) != value.get("reconstruction_sha256"):
        raise TrustError("mask reconstruction input is missing or stale")
    if not isinstance(value,dict) or set(value)!={"schema_version","reconstruction_input","reconstruction_sha256","dimensions","scopes","masks"} or value.get("schema_version")!=1: raise TrustError("mask manifest schema mismatch")
    annotation=read_json(reconstruction)
    if annotation.get("dimensions")!=value.get("dimensions"): raise TrustError("mask annotation dimension drift")
    records = value.get("masks", [])
    if not isinstance(records,list) or not records: raise TrustError("mask records are empty")
    by_scope: dict[tuple[str, str, str, str], dict[str, np.ndarray]] = {}; seen_records=set()
    for record in records:
        if not isinstance(record,dict) or set(record)!={"scenario","profile","variant","capture_role","family","dimensions","path","sha256","coverage_pixels"}: raise TrustError("mask record schema mismatch")
        key=_scope_key(record); identity=(*key,record.get("family"))
        if identity in seen_records: raise TrustError("duplicate mask record")
        seen_records.add(identity)
        if key not in allowed_scopes: raise TrustError(f"mask scope is not applicable: {key}")
        if record.get("family") not in required_families or record.get("dimensions")!=value["dimensions"] or type(record.get("coverage_pixels")) is not int or record["coverage_pixels"]<0 or record["coverage_pixels"]>value["dimensions"][0]*value["dimensions"][1] or (record["coverage_pixels"]==0 and record["family"] not in empty_families): raise TrustError("mask record identity, dimensions, or coverage is invalid")
        path, raster = _asset(base, record)
        if raster.shape[2] != 4:
            raise TrustError(f"mask is not decodable RGBA: {path}")
        gray = np.asarray(Image.open(path).convert("L"))
        if not set(np.unique(gray)) <= {0, 255}:
            raise TrustError(f"mask is not binary: {path}")
        if int(np.count_nonzero(gray))!=record["coverage_pixels"]: raise TrustError("mask coverage count mismatch")
        by_scope.setdefault(key, {})[record["family"]] = gray > 0
    source_scopes=annotation.get("scopes",[])
    if not isinstance(source_scopes,list) or any(not isinstance(x,dict) for x in source_scopes): raise TrustError("mask annotation scopes are invalid")
    source_keys=[_scope_key(x) for x in source_scopes]
    if len(source_keys)!=len(set(source_keys)): raise TrustError("duplicate mask annotation scope")
    annotation_scopes={_scope_key(x):x for x in source_scopes}
    scopes=value.get("scopes",[])
    if not isinstance(scopes,list) or len(scopes)!=len(annotation_scopes) or len(scopes)!=len(by_scope): raise TrustError("mask scope coverage is missing, extra, or duplicated")
    seen_scopes=set()
    for scope in scopes:
        if not isinstance(scope,dict) or set(scope)!={"scenario","profile","variant","capture_role","capture_sidecar","owned_text_rects","owned_content_rects","os_external_rects"}: raise TrustError("mask scope schema mismatch")
        key = _scope_key(scope)
        if key in seen_scopes or key not in annotation_scopes or key not in allowed_scopes: raise TrustError("mask scope is duplicated, stale, or not applicable")
        seen_scopes.add(key)
        _mask_capture(annotation_scopes[key],run_root,run_manifest,value["dimensions"])
        projection={name:annotation_scopes[key][name] for name in ("scenario","profile","variant","capture_role","capture_sidecar","owned_text_rects","owned_content_rects","os_external_rects")}
        if scope!=projection: raise TrustError("mask manifest scope metadata differs from annotation projection")
        families = by_scope.get(key, {})
        if set(families) != required_families:
            raise TrustError(f"mask family coverage is incomplete for {key}")
        size = (value["dimensions"][0], value["dimensions"][1])
        text = _rect_mask(size, scope.get("owned_text_rects", []))
        if np.any(text & ~families["text-layout"]):
            raise TrustError("owned text is excluded from owned comparison coverage")
        owned = _rect_mask(size, scope.get("owned_content_rects", []))
        external = _rect_mask(size, scope.get("os_external_rects", []))
        if not np.array_equal(external,families["os-external"]): raise TrustError("os-external mask differs from declared external rectangles")
        if np.any(owned & external) or np.any(families["os-external"] & owned):
            raise TrustError("os-external mask overlaps owned content")
        source=annotation_scopes[key]
        for family in required_families:
            reconstructed=_draw_mask(size,source["families"][family])>0
            if not np.array_equal(reconstructed,families[family]): raise TrustError("mask raster differs from its reconstruction annotation")
    if set(by_scope)!=allowed_scopes: raise TrustError("mask scopes do not exactly equal complete applicability")
    return {"valid": True, "scopes": len(by_scope), "masks": len(records), "manifest_sha256": digest(manifest_path)}


def _delta_e_2000(lab1: np.ndarray, lab2: np.ndarray) -> np.ndarray:
    # Sharma et al. CIEDE2000, vectorized.
    l1, a1, b1 = np.moveaxis(lab1, -1, 0); l2, a2, b2 = np.moveaxis(lab2, -1, 0)
    c1 = np.hypot(a1, b1); c2 = np.hypot(a2, b2); cbar = (c1 + c2) / 2
    g = .5 * (1 - np.sqrt(cbar**7 / (cbar**7 + 25**7 + 1e-12)))
    ap1, ap2 = (1 + g) * a1, (1 + g) * a2
    cp1, cp2 = np.hypot(ap1, b1), np.hypot(ap2, b2)
    hp1 = np.mod(np.degrees(np.arctan2(b1, ap1)), 360); hp2 = np.mod(np.degrees(np.arctan2(b2, ap2)), 360)
    dl, dc = l2 - l1, cp2 - cp1
    dh = hp2 - hp1; dh = np.where(dh > 180, dh - 360, np.where(dh < -180, dh + 360, dh)); dh = np.where((cp1 * cp2) == 0, 0, dh)
    dH = 2 * np.sqrt(cp1 * cp2) * np.sin(np.radians(dh / 2))
    lbar, cpbar = (l1 + l2) / 2, (cp1 + cp2) / 2
    hpbar = np.where((cp1 * cp2) == 0, hp1 + hp2, np.where(np.abs(hp1 - hp2) <= 180, (hp1 + hp2) / 2, np.where(hp1 + hp2 < 360, (hp1 + hp2 + 360) / 2, (hp1 + hp2 - 360) / 2)))
    t = 1 - .17*np.cos(np.radians(hpbar-30)) + .24*np.cos(np.radians(2*hpbar)) + .32*np.cos(np.radians(3*hpbar+6)) - .20*np.cos(np.radians(4*hpbar-63))
    sl = 1 + .015*(lbar-50)**2/np.sqrt(20+(lbar-50)**2); sc = 1 + .045*cpbar; sh = 1 + .015*cpbar*t
    rt = -2*np.sqrt(cpbar**7/(cpbar**7+25**7+1e-12))*np.sin(np.radians(60*np.exp(-((hpbar-275)/25)**2)))
    return np.sqrt((dl/sl)**2 + (dc/sc)**2 + (dH/sh)**2 + rt*(dc/sc)*(dH/sh))


def compare_static(reference: Path, native: Path, output: Path, spec_path: Path) -> dict[str, Any]:
    spec = read_json(spec_path); base = spec_path.parent
    permitted = spec.get("registration", {}).get("permitted_translation_device_px")
    anchors = spec.get("registration", {}).get("anchors",{})
    if not isinstance(anchors,dict) or set(anchors)!={"reference","native"} or set(anchors["reference"])!=set(anchors["native"]) or len(anchors["reference"])<2: raise TrustError("named reference/native registration anchors are required")
    offsets=[]
    for name,point in anchors["reference"].items():
        native_point=anchors["native"].get(name)
        if not isinstance(point,list) or not isinstance(native_point,list) or len(point)!=2 or len(native_point)!=2 or not all(type(x) is int for x in point+native_point): raise TrustError("registration anchors must be integer coordinate pairs")
        offsets.append((point[0]-native_point[0],point[1]-native_point[1]))
    if len(set(offsets))!=1: raise TrustError("registration anchors do not imply one exact integer translation")
    dx,dy=offsets[0]
    if type(permitted) is not int or permitted<0 or abs(dx) > permitted or abs(dy) > permitted:
        raise TrustError("named registration anchors and calibrated translation bounds are required")
    ref = Image.open(reference).convert("RGBA"); cand = Image.open(native).convert("RGBA")
    if ref.size != cand.size:
        raise TrustError("scale/warp forbidden: source image sizes must match")
    registered = Image.new("RGBA", ref.size); registered.alpha_composite(cand, (dx, dy))
    output.mkdir(parents=True, exist_ok=True)
    ref.save(output/"registered-reference.png"); registered.save(output/"registered-native.png")
    side=Image.new("RGBA",(ref.width*2,ref.height)); side.paste(ref,(0,0)); side.paste(registered,(ref.width,0)); side.save(output/"side-by-side.png")
    Image.blend(ref,registered,.5).save(output/"overlay.png"); ImageChops.difference(ref,registered).save(output/"absolute-diff.png")
    signed=np.asarray(registered,dtype=np.int16)-np.asarray(ref,dtype=np.int16); np.save(output/"signed-diff.npy",signed)
    Image.fromarray(np.clip(signed[...,:3]+128,0,255).astype(np.uint8)).save(output/"signed-diff-visual.png")
    Image.fromarray(np.clip(np.max(np.abs(signed[...,:3]),axis=2)*4,0,255).astype(np.uint8)).save(output/"heatmap.png")
    ref.save(output/"blink.gif",save_all=True,append_images=[registered],duration=400,loop=0)
    def shift(array: np.ndarray) -> np.ndarray:
        shifted=np.zeros_like(array); x0=max(0,dx); x1=min(array.shape[1],array.shape[1]+dx); y0=max(0,dy); y1=min(array.shape[0],array.shape[0]+dy)
        shifted[y0:y1,x0:x1]=array[y0-dy:y1-dy,x0-dx:x1-dx]; return shifted
    def mask(name: str) -> np.ndarray:
        record=spec.get("masks",{}).get(name)
        if not isinstance(record,dict): raise TrustError(f"required static mask is missing: {name}")
        _, array=_asset(base,record,ref.size); result=np.asarray(Image.fromarray(array).convert("L"))>0
        if not np.any(result): raise TrustError(f"required static mask is empty: {name}")
        return shift(result) if name.startswith("native_") else result
    rs, ns, opaque, nontext, rc, nc = (mask(x) for x in ("reference_silhouette","native_silhouette","stable_opaque","stable_non_text","reference_chrome","native_chrome"))
    union=np.count_nonzero(rs|ns); iou=np.count_nonzero(rs&ns)/union if union else 1.0
    re=rs^binary_erosion(rs); ne=ns^binary_erosion(ns); aa=int(spec.get("aa_band_device_px",-1)); scale=float(spec.get("logical_to_device_scale",0))
    if aa<0 or scale<=0: raise TrustError("AA band and logical/device scale are required")
    distances=np.concatenate([distance_transform_edt(~ne)[re],distance_transform_edt(~re)[ne]])/scale
    distances=distances[distances>aa/scale]
    p95=float(np.percentile(distances,95)) if distances.size else 0.; maximum=float(np.max(distances)) if distances.size else 0.
    rrgb=np.asarray(ref)[...,:3]; nrgb=np.asarray(registered)[...,:3]
    lab1=cv2.cvtColor(rrgb,cv2.COLOR_RGB2LAB).astype(float); lab2=cv2.cvtColor(nrgb,cv2.COLOR_RGB2LAB).astype(float); lab1[...,0]*=100/255; lab2[...,0]*=100/255; lab1[...,1:]-=128; lab2[...,1:]-=128
    if not np.any(opaque) or not np.any(nontext): raise TrustError("static comparison domains must be nonempty")
    de=_delta_e_2000(lab1[opaque],lab2[opaque]); de_med=float(np.median(de)); de95=float(np.percentile(de,95))
    gray1=cv2.cvtColor(rrgb,cv2.COLOR_RGB2GRAY).astype(float); gray2=cv2.cvtColor(nrgb,cv2.COLOR_RGB2GRAY).astype(float)
    mu1=cv2.GaussianBlur(gray1,(3,3),1); mu2=cv2.GaussianBlur(gray2,(3,3),1); s1=cv2.GaussianBlur(gray1*gray1,(3,3),1)-mu1*mu1; s2=cv2.GaussianBlur(gray2*gray2,(3,3),1)-mu2*mu2; s12=cv2.GaussianBlur(gray1*gray2,(3,3),1)-mu1*mu2
    ssim_map=((2*mu1*mu2+6.5025)*(2*s12+58.5225))/((mu1*mu1+mu2*mu2+6.5025)*(s1+s2+58.5225)); ssim=float(np.mean(ssim_map[nontext]))
    chrome_ref=np.count_nonzero(rc); chrome_native=np.count_nonzero(nc); chrome=abs(chrome_native-chrome_ref)/chrome_ref if chrome_ref else (0 if chrome_native==0 else math.inf)
    threshold=spec.get("thresholds",{}); text=spec.get("text",{}); landmarks=spec.get("landmarks",{})
    text_ok=isinstance(text.get("reference"),list) and bool(text["reference"]) and text.get("reference")==text.get("native")
    landmark_d=[]
    for name, rp in landmarks.get("reference",{}).items():
        npnt=landmarks.get("native",{}).get(name)
        if npnt is None: raise TrustError(f"native landmark missing: {name}")
        if not isinstance(rp,list) or not isinstance(npnt,list) or len(rp)!=2 or len(npnt)!=2 or not all(type(x) in {int,float} and math.isfinite(x) for x in rp+npnt): raise TrustError("static landmarks must be finite coordinate pairs")
        landmark_d.append(math.dist(rp,[npnt[0]+dx,npnt[1]+dy])/scale)
    if not landmark_d: raise TrustError("static landmark domain is empty")
    values={"silhouette_iou":iou,"edge_p95":p95,"edge_max":maximum,"delta_e_median":de_med,"delta_e_p95":de95,"ssim":ssim,"chrome_ratio":chrome,"text_geometry":text_ok,"landmark_max":max(landmark_d)}
    if any(type(v) is float and not math.isfinite(v) for v in values.values()): raise TrustError("static metric is non-finite")
    limits={"silhouette_iou":lambda v:v>=threshold["silhouette_iou_min"],"edge_p95":lambda v:v<=threshold["edge_distance_p95_logical_px_max"],"edge_max":lambda v:v<=threshold["edge_distance_max_logical_px_max"],"delta_e_median":lambda v:v<=threshold["delta_e_2000_median_max"],"delta_e_p95":lambda v:v<=threshold["delta_e_2000_p95_max"],"ssim":lambda v:v>=threshold["non_text_ssim_min"],"chrome_ratio":lambda v:v<=threshold["chrome_area_ratio_relative_max"],"text_geometry":bool,"landmark_max":lambda v:v<=threshold["landmark_logical_px_max"]}
    metrics={name:{"status":"passed" if limits[name](value) else "failed","value":value} for name,value in values.items()}
    context=spec.get("context"); bindings=spec.get("bindings")
    if not isinstance(context,dict) or set(context)!={"scenario","profile","variant","authority_class"} or not all(isinstance(x,str) and x for x in context.values()): raise TrustError("static context binding schema mismatch")
    required_bindings={"calibration","mask_manifest","thresholds","reference_sidecar","native_sidecar","evidence_index"}
    if not isinstance(bindings,dict) or set(bindings)!=required_bindings or not all(isinstance(x,dict) and set(x)=={"path","sha256"} and isinstance(x["path"],str) and isinstance(x["sha256"],str) and len(x["sha256"])==64 for x in bindings.values()): raise TrustError("static evidence bindings are incomplete")
    report={"schema_version":1,"screening_only":True,"context":context,"bindings":{key:value["sha256"] for key,value in bindings.items()},"inputs":{"reference_sha256":digest(reference),"native_sha256":digest(native),"spec_sha256":digest(spec_path)},"registration":{"dx":dx,"dy":dy,"scale":1,"warp":False,"anchors":sorted(anchors["reference"])},"metrics":metrics,"overall_screening_status":"passed" if all(x["status"]=="passed" for x in metrics.values()) else "failed"}
    (output/"metrics.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n"); return report


def validate_motion(path: Path, output: Path | None, run_root: Path, run_manifest: dict[str,Any], scenarios_manifest: dict[str,Any], behavior_manifest: dict[str,Any], authority: dict[str,Any], calibration: dict[str,Any], capture_sidecar: dict[str,Any], clock_attestation: dict[str,Any], indexed: dict[str,Any]) -> dict[str, Any]:
    value=read_json(path)
    required_top={"schema_version","scenario","profile","variant","authority_class","canonical_disposition","bindings","capture_sidecar","manual_clock_attestation","runs"}
    if not isinstance(value,dict) or set(value)!=required_top or value.get("schema_version")!=1: raise TrustError("motion manifest schema mismatch")
    bindings=value.get("bindings")
    if not isinstance(bindings,dict) or set(bindings)!={"scenarios_sha256","behavior_sha256","motion_authority_sha256","calibration_sha256","source_evidence_sha256"} or not all(isinstance(x,str) and len(x)==64 for x in bindings.values()): raise TrustError("motion evidence bindings are incomplete")
    scenarios={row["id"]:row for row in scenarios_manifest.get("scenarios",[]) if isinstance(row,dict) and isinstance(row.get("id"),str)}; scenario=scenarios.get(value.get("scenario")); authority_class=value.get("authority_class")
    if scenario is None or (scenario.get("class")=="rendered-motion-exemplar" and authority_class!="rendered-motion-exemplar") or (scenario.get("class")=="specified-invariant" and authority_class!="approved-interactive-behavior") or scenario.get("class") not in {"rendered-motion-exemplar","specified-invariant"}: raise TrustError("motion scenario/class binding is invalid")
    if value.get("authority_class") not in {"rendered-motion-exemplar","approved-interactive-behavior"}:
        raise TrustError("motion authority class is missing or diagnostic")
    if value.get("canonical_disposition") not in {"exact","diagnostic"}: raise TrustError("motion disposition is invalid")
    if value["authority_class"]=="approved-interactive-behavior":
        timeline=next((x for x in behavior_manifest.get("timelines",[]) if isinstance(x,dict) and x.get("scenario")==value.get("scenario") and x.get("status")=="approved"),None)
        if not isinstance(timeline,dict) or not all(key in timeline for key in ("required_checkpoints","required_events","minimum_duration_seconds","start_tolerance_seconds")): raise TrustError("interactive motion lacks approved complete behavior authority")
        rendered={key:timeline[key] for key in ("required_checkpoints","required_events","minimum_duration_seconds","start_tolerance_seconds")}
    else:
        rendered=authority.get("rendered_css",{})
    required=set(rendered.get("required_checkpoints",[])); required_events=rendered.get("required_events",[])
    if not required or not required_events: raise TrustError("motion authority checkpoint/event contract is missing")
    required_clock=bool(scenario.get("deterministic")) or authority_class=="approved-interactive-behavior"
    clock_required={"schema_version","scenario","capture_id","run_capture_ids","frame_capture_ids","clock_id","consumed_by_views","view_identity","environment_sha256","bindings_sha256"}
    if not isinstance(clock_attestation,dict) or set(clock_attestation)!=clock_required or clock_attestation.get("schema_version")!=1 or clock_attestation.get("scenario")!=value.get("scenario") or (required_clock and (clock_attestation.get("consumed_by_views") is not True or not isinstance(clock_attestation.get("clock_id"),str) or not clock_attestation["clock_id"])): raise TrustError("manual clock consumption lacks a valid view attestation")
    capture_required={"schema_version","scenario","profile","variant","capture_role","capture_id","run_capture_ids","frame_capture_ids","environment_sha256","bindings_sha256","view_identity"}
    environment_sha=_json_digest(run_manifest.get("environment")); bindings_sha=_json_digest(run_manifest.get("bindings"))
    if not isinstance(capture_sidecar,dict) or set(capture_sidecar)!=capture_required or capture_sidecar.get("schema_version")!=1 or capture_sidecar.get("capture_role")!="native" or any(capture_sidecar.get(k)!=value.get(k) for k in ("scenario","profile","variant")) or capture_sidecar.get("capture_id")!=clock_attestation.get("capture_id") or capture_sidecar.get("view_identity")!=clock_attestation.get("view_identity") or capture_sidecar.get("environment_sha256")!=environment_sha or clock_attestation.get("environment_sha256")!=environment_sha or capture_sidecar.get("bindings_sha256")!=bindings_sha or clock_attestation.get("bindings_sha256")!=bindings_sha: raise TrustError("motion capture/view attestation identity differs from canonical run")
    runs=value.get("runs",[])
    if len(runs)<3: raise TrustError("motion validation requires three repeated runs")
    expected_run_captures=[run.get("capture_id") for run in runs if isinstance(run,dict)]; expected_frame_captures=[frame.get("capture_id") for run in runs if isinstance(run,dict) for frame in run.get("frames",[]) if isinstance(frame,dict)]
    if capture_sidecar.get("run_capture_ids")!=expected_run_captures or clock_attestation.get("run_capture_ids")!=expected_run_captures or capture_sidecar.get("frame_capture_ids")!=expected_frame_captures or clock_attestation.get("frame_capture_ids")!=expected_frame_captures: raise TrustError("motion capture lineage does not enumerate exact run/frame captures")
    reports=[]; run_ids=set(); run_capture_ids=set(); all_paths=set(); all_capture_ids=set(); limits=calibration.get("limits") if calibration.get("status")=="approved" else authority.get("diagnostic_limits",{})
    for run in runs:
        if not isinstance(run,dict) or set(run)!={"run_id","capture_id","fiducials","frames","checkpoints","events"}: raise TrustError("motion run schema mismatch")
        run_id=run.get("run_id")
        run_capture=run.get("capture_id")
        if not isinstance(run_id,str) or not run_id or run_id in run_ids or not isinstance(run_capture,str) or not run_capture or run_capture in run_capture_ids or run_capture==capture_sidecar.get("capture_id") or run_capture in all_capture_ids: raise TrustError("motion run/capture IDs must be distinct and nonempty")
        run_ids.add(run_id); run_capture_ids.add(run_capture)
        _fiducials(run.get("fiducials"))
        frames=run.get("frames",[])
        for frame in frames:
            if not isinstance(frame,dict) or set(frame)!={"path","sha256","dimensions","pts","capture_id"} or frame["path"] in all_paths or frame["capture_id"] in all_capture_ids or frame["capture_id"] in run_capture_ids or frame["capture_id"]==capture_sidecar.get("capture_id") or frame["path"] not in indexed or indexed[frame["path"]]["sha256"]!=frame["sha256"]: raise TrustError("motion frame schema, capture identity, path, or index binding is invalid/reused")
            all_paths.add(frame["path"]); all_capture_ids.add(frame["capture_id"])
        _,pts,duplicates,drops,jitter=_validate_frames(run_root,frames)
        if abs(pts[0])>_number(rendered.get("start_tolerance_seconds"),"motion start tolerance",0) or pts[-1]<_number(rendered.get("minimum_duration_seconds"),"motion duration",0): raise TrustError("motion run does not start at t=0 or cover required duration")
        checkpoints=run.get("checkpoints",[])
        if not isinstance(checkpoints,list) or [x.get("id") for x in checkpoints if isinstance(x,dict)]!=rendered.get("required_checkpoints"): raise TrustError("motion checkpoints are missing, duplicated, or out of authority order")
        checkpoint_indexes=[]; checkpoint_pts=[]
        for checkpoint in checkpoints:
            if not isinstance(checkpoint,dict) or set(checkpoint)!={"id","frame_index","pts","frame_path","frame_sha256","frame_capture_id","landmarks"} or type(checkpoint.get("frame_index")) is not int or not 0<=checkpoint["frame_index"]<len(frames): raise TrustError("motion checkpoint schema/frame index is invalid")
            frame=frames[checkpoint["frame_index"]]
            checkpoint_indexes.append(checkpoint["frame_index"]); checkpoint_pts.append(checkpoint["pts"])
            if checkpoint["pts"]!=frame["pts"] or checkpoint["frame_path"]!=frame["path"] or checkpoint["frame_sha256"]!=frame["sha256"] or checkpoint["frame_capture_id"]!=frame["capture_id"] or not isinstance(checkpoint["landmarks"],dict) or not checkpoint["landmarks"] or any(not isinstance(point,list) or len(point)!=2 or not all(type(x) in {int,float} and math.isfinite(x) for x in point) for point in checkpoint["landmarks"].values()): raise TrustError("motion checkpoint does not bind its exact frame/capture/landmarks")
        if checkpoint_indexes!=sorted(set(checkpoint_indexes)) or checkpoint_pts!=sorted(set(checkpoint_pts)) or checkpoint_indexes[0]!=0 or checkpoint_indexes[-1]!=len(frames)-1: raise TrustError("motion checkpoints must be strictly monotonic from first through final frame")
        events=run.get("events",[]); event_ids=[]; event_pts=[]
        for event in events:
            if not isinstance(event,dict) or set(event)!={"id","kind","frame_index","pts","frame_path","frame_sha256","frame_capture_id"} or type(event.get("frame_index")) is not int or not 0<=event["frame_index"]<len(frames): raise TrustError("motion event schema/frame index is invalid")
            frame=frames[event["frame_index"]]; event_ids.append(event["id"]); event_pts.append(event["pts"])
            if event["pts"]!=frame["pts"] or event["frame_path"]!=frame["path"] or event["frame_sha256"]!=frame["sha256"] or event["frame_capture_id"]!=frame["capture_id"]: raise TrustError("motion event does not bind its exact frame/capture")
        if event_ids!=required_events or len(event_ids)!=len(set(event_ids)) or event_pts!=sorted(set(event_pts)): raise TrustError("motion events are missing, duplicated, or unordered")
        if duplicates>limits.get("duplicates_max",0) or drops>limits.get("drops_max",0) or jitter>limits.get("timing_jitter_max",.002):
            raise TrustError("motion duplicate/drop/jitter tolerance exceeded")
        reports.append({"run_id":run_id,"capture_id":run_capture,"pts_intervals":np.diff(pts).tolist(),"duplicates":duplicates,"drops":drops,"timing_jitter":jitter,"checkpoints":checkpoints,"events":events})
    report={"schema_version":1,"generator":"poured-motion-v1","scenario":value.get("scenario"),"profile":value.get("profile"),"variant":value.get("variant"),"authority_class":value["authority_class"],"disposition":value["canonical_disposition"],"source_manifest":{"path":str(path.relative_to(run_root)),"sha256":digest(path)},"runtime":{"numpy":np.__version__,"opencv":cv2.__version__},"runs":reports,"capture_sidecar_sha256":digest(run_root/value["capture_sidecar"]["path"]),"clock_attestation_sha256":digest(run_root/value["manual_clock_attestation"]["path"]),"status":"measured-diagnostic" if value["canonical_disposition"]=="diagnostic" else "measured"}
    if output is not None: output.write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    return report
