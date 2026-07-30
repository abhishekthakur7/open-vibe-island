from __future__ import annotations

import json
import math
import os
import tempfile
from fractions import Fraction
from itertools import combinations
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw

from .core import ParityError, canonical_json_bytes, sha256_bytes, sha256_file


SCHEMA_VERSION = "1.0.0"
MASK_SET_VERSION = "halo-reference-masks-v1"
MASK_FAMILIES = (
    "silhouette-body",
    "edge-core",
    "emissive-bloom",
    "non-text-content",
    "text-layout-boxes",
    "os-external",
)
AGGREGATE_FAMILIES = MASK_FAMILIES[:4]
FAMILY_PURPOSES = {
    "silhouette-body": "owned black surface bounds, corners, continuity, and topology",
    "edge-core": "nominal living stroke width, centerline, stops, and opacity",
    "emissive-bloom": "falloff area, centroid, intensity, and localization",
    "non-text-content": "owned glyph, dot, rail, meter, divider, and icon pixels",
    "text-layout-boxes": "string boxes, baselines, wrapping, and truncation geometry",
    "os-external": "narrowly scoped non-Halo OS or capture content only",
}
PROFILE_LOGICAL_DIMENSIONS = {
    "notch-v1": (540, 320),
    "top-bar-v1": (520, 320),
}
RASTERIZER = {
    "id": "halo-mask-rasterizer-v1",
    "fillRule": "nonzero",
    "boundsRule": "half-open-after-nearest-half-up-device-pixel-quantization",
    "binaryValues": [0, 255],
    "textRule": "text-layout-boxes-subtracted-from-all-aggregate-families",
    "overlapRule": (
        "aggregate-family-overlap-allowed; text/aggregate and "
        "os-external/Halo-owned overlap-forbidden"
    ),
}
_SHAPE_KEYS = {
    "rect": {"type", "x", "y", "width", "height"},
    "rounded-rect": {"type", "x", "y", "width", "height", "radius"},
    "ellipse": {"type", "x", "y", "width", "height"},
    "polygon": {"type", "points"},
    "stroke-rounded-rect": {
        "type",
        "x",
        "y",
        "width",
        "height",
        "radius",
        "strokeWidth",
    },
}


def _require_exact_keys(
    value: Any, expected: set[str], label: str
) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        actual = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise ParityError(
            f"{label} fields must be exactly {sorted(expected)}; got {actual}"
        )
    return value


def _hash(value: Any) -> str:
    return sha256_bytes(canonical_json_bytes(value))


def _sha256(value: Any, label: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise ParityError(f"{label} must be a lowercase SHA-256")
    return value


def _safe_input_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ParityError(f"{label} must be a non-empty path")
    components = Path(value).parts
    if any(
        "candidate" in component.casefold() or "native" in component.casefold()
        for component in components
    ):
        raise ParityError(f"{label} may not identify candidate/native input: {value}")
    return value


def _fraction(value: Any, label: str, *, positive: bool = False) -> Fraction:
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ParityError(f"{label} must be a finite number")
    try:
        result = Fraction(str(value))
    except (ValueError, ZeroDivisionError) as error:
        raise ParityError(f"{label} must be a finite number") from error
    if isinstance(value, float) and not math.isfinite(value):
        raise ParityError(f"{label} must be a finite number")
    if positive and result <= 0:
        raise ParityError(f"{label} must be positive")
    return result


def _round_half_up(value: Fraction) -> int:
    return math.floor(value + Fraction(1, 2))


def _profile_dimensions(profile: dict[str, Any]) -> tuple[str, int, int, int]:
    _require_exact_keys(
        profile,
        {"id", "logicalSize", "backingScale"},
        "profile",
    )
    profile_id = profile["id"]
    if profile_id not in PROFILE_LOGICAL_DIMENSIONS:
        raise ParityError(f"unknown canonical profile: {profile_id!r}")
    logical_size = _require_exact_keys(
        profile["logicalSize"], {"width", "height"}, "profile.logicalSize"
    )
    expected_width, expected_height = PROFILE_LOGICAL_DIMENSIONS[profile_id]
    if (
        logical_size["width"] != expected_width
        or logical_size["height"] != expected_height
        or profile["backingScale"] != 2
    ):
        raise ParityError(
            f"{profile_id} must be {expected_width}x{expected_height} logical "
            "points at 2x"
        )
    return profile_id, expected_width, expected_height, 2


def _validate_transform(transform: dict[str, Any]) -> tuple[Fraction, int, int]:
    _require_exact_keys(
        transform,
        {
            "schemaVersion",
            "transformId",
            "status",
            "scale",
            "translationDevicePixels",
            "provenance",
        },
        "neutralTransform",
    )
    if transform["schemaVersion"] != SCHEMA_VERSION:
        raise ParityError("neutral transform schemaVersion must be 1.0.0")
    if transform["status"] != "frozen":
        raise ParityError("neutral transform must have status=frozen")
    if not isinstance(transform["transformId"], str) or not transform["transformId"]:
        raise ParityError("neutral transform ID must be non-empty")
    scale = _require_exact_keys(
        transform["scale"], {"numerator", "denominator"}, "neutralTransform.scale"
    )
    numerator = scale["numerator"]
    denominator = scale["denominator"]
    if (
        isinstance(numerator, bool)
        or not isinstance(numerator, int)
        or isinstance(denominator, bool)
        or not isinstance(denominator, int)
        or numerator <= 0
        or denominator <= 0
    ):
        raise ParityError("neutral transform scale must be a positive integer ratio")
    translation = _require_exact_keys(
        transform["translationDevicePixels"],
        {"x", "y"},
        "neutralTransform.translationDevicePixels",
    )
    if any(
        isinstance(translation[axis], bool)
        or not isinstance(translation[axis], int)
        for axis in ("x", "y")
    ):
        raise ParityError("neutral transform translation must use integer device pixels")
    provenance = _require_exact_keys(
        transform["provenance"],
        {"sourceRole", "sourcePath", "sha256"},
        "neutralTransform.provenance",
    )
    if provenance["sourceRole"] != "neutral-calibration":
        raise ParityError("mask transform must come from neutral-calibration")
    _safe_input_path(provenance["sourcePath"], "neutral transform sourcePath")
    _sha256(provenance["sha256"], "neutral transform provenance sha256")
    return Fraction(numerator, denominator), translation["x"], translation["y"]


def _source_bounds(shape: dict[str, Any]) -> tuple[Fraction, Fraction, Fraction, Fraction]:
    kind = shape.get("type")
    if kind not in _SHAPE_KEYS:
        raise ParityError(f"unknown mask geometry type: {kind!r}")
    _require_exact_keys(shape, _SHAPE_KEYS[kind], f"{kind} geometry")
    if kind == "polygon":
        points = shape["points"]
        if (
            not isinstance(points, list)
            or len(points) < 3
            or any(not isinstance(point, list) or len(point) != 2 for point in points)
        ):
            raise ParityError("polygon geometry requires at least three [x,y] points")
        coordinates = [
            (
                _fraction(point[0], f"polygon point {index}.x"),
                _fraction(point[1], f"polygon point {index}.y"),
            )
            for index, point in enumerate(points)
        ]
        xs = [point[0] for point in coordinates]
        ys = [point[1] for point in coordinates]
        return min(xs), min(ys), max(xs), max(ys)
    x = _fraction(shape["x"], f"{kind}.x")
    y = _fraction(shape["y"], f"{kind}.y")
    width = _fraction(shape["width"], f"{kind}.width", positive=True)
    height = _fraction(shape["height"], f"{kind}.height", positive=True)
    if kind in {"rounded-rect", "stroke-rounded-rect"}:
        radius = _fraction(shape["radius"], f"{kind}.radius")
        if radius < 0 or radius * 2 > min(width, height):
            raise ParityError(f"{kind}.radius is outside its geometry")
    if kind == "stroke-rounded-rect":
        stroke = _fraction(
            shape["strokeWidth"], "stroke-rounded-rect.strokeWidth", positive=True
        )
        if stroke * 2 > min(width, height):
            raise ParityError("stroke-rounded-rect stroke is wider than its geometry")
    return x, y, x + width, y + height


def _transform_point(
    x: Fraction, y: Fraction, scale: Fraction, tx: int, ty: int
) -> tuple[int, int]:
    return _round_half_up(x * scale + tx), _round_half_up(y * scale + ty)


def _draw_geometry(
    image: Image.Image,
    shape: dict[str, Any],
    *,
    scale: Fraction,
    tx: int,
    ty: int,
    logical_width: int,
    logical_height: int,
) -> None:
    x0, y0, x1, y1 = _source_bounds(shape)
    if x0 < 0 or y0 < 0 or x1 > logical_width or y1 > logical_height:
        raise ParityError(f"{shape['type']} geometry lies outside reference bounds")
    left, top = _transform_point(x0, y0, scale, tx, ty)
    right, bottom = _transform_point(x1, y1, scale, tx, ty)
    width, height = image.size
    if left < 0 or top < 0 or right > width or bottom > height:
        raise ParityError(f"{shape['type']} geometry lies outside device bounds")
    if right <= left or bottom <= top:
        raise ParityError(f"{shape['type']} geometry collapses after transform")
    draw = ImageDraw.Draw(image)
    kind = shape["type"]
    inclusive_box = (left, top, right - 1, bottom - 1)
    if kind == "rect":
        draw.rectangle(inclusive_box, fill=255)
    elif kind == "ellipse":
        draw.ellipse(inclusive_box, fill=255)
    elif kind == "polygon":
        points = [
            _transform_point(
                _fraction(point[0], "polygon.x"),
                _fraction(point[1], "polygon.y"),
                scale,
                tx,
                ty,
            )
            for point in shape["points"]
        ]
        if any(x < 0 or y < 0 or x >= width or y >= height for x, y in points):
            raise ParityError("polygon geometry lies outside device bounds")
        draw.polygon(points, fill=255)
    else:
        radius = _round_half_up(
            _fraction(shape["radius"], f"{kind}.radius") * scale
        )
        if kind == "rounded-rect":
            draw.rounded_rectangle(inclusive_box, radius=radius, fill=255)
        else:
            stroke = _round_half_up(
                _fraction(shape["strokeWidth"], f"{kind}.strokeWidth") * scale
            )
            if stroke < 1:
                raise ParityError("stroke-rounded-rect stroke collapses after transform")
            draw.rounded_rectangle(
                inclusive_box, radius=radius, outline=255, width=stroke
            )


def _validate_annotations(
    annotations: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    _require_exact_keys(
        annotations,
        {
            "schemaVersion",
            "coordinateSpace",
            "authority",
            "families",
        },
        "annotations",
    )
    if annotations["schemaVersion"] != SCHEMA_VERSION:
        raise ParityError("annotation schemaVersion must be 1.0.0")
    if annotations["coordinateSpace"] != "reference-logical-points":
        raise ParityError("annotations must use reference-logical-points")
    authority = _require_exact_keys(
        annotations["authority"],
        {"sourceRole", "sourcePath", "sha256"},
        "annotations.authority",
    )
    if authority["sourceRole"] != "authoritative-reference":
        raise ParityError("mask annotations must be authoritative-reference")
    _safe_input_path(authority["sourcePath"], "annotation authority sourcePath")
    _sha256(authority["sha256"], "annotation authority sha256")
    families = annotations["families"]
    if not isinstance(families, dict) or set(families) != set(MASK_FAMILIES):
        unknown = (
            sorted(set(families) - set(MASK_FAMILIES))
            if isinstance(families, dict)
            else []
        )
        missing = (
            sorted(set(MASK_FAMILIES) - set(families))
            if isinstance(families, dict)
            else list(MASK_FAMILIES)
        )
        raise ParityError(
            f"annotations require exactly six mask families; "
            f"missing={missing}, unknown={unknown}"
        )
    for family in MASK_FAMILIES:
        record = _require_exact_keys(
            families[family], {"selectors", "geometry"}, f"{family} annotations"
        )
        selectors = record["selectors"]
        geometry = record["geometry"]
        if (
            not isinstance(selectors, list)
            or not selectors
            or any(not isinstance(selector, str) or not selector for selector in selectors)
        ):
            raise ParityError(f"{family} requires authoritative source selectors")
        if not isinstance(geometry, list) or not geometry:
            raise ParityError(f"{family} requires authoritative geometry")
    return authority, families


def _overlap_pixels(left: Image.Image, right: Image.Image) -> bool:
    overlap = ImageChops.logical_and(left.convert("1"), right.convert("1"))
    return overlap.getbbox() is not None


def _atomic_save_png(image: Image.Image, path: Path) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        image.save(temporary, format="PNG", optimize=False, compress_level=9)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def _atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        temporary.write_text(
            json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def generate_masks(
    *,
    annotations: dict[str, Any],
    profile: dict[str, Any],
    neutral_transform: dict[str, Any],
    output_dir: Path,
) -> Path:
    """Freeze six reference-coordinate mask PNGs and return the manifest path."""
    profile_id, logical_width, logical_height, backing_scale = _profile_dimensions(
        profile
    )
    scale, tx, ty = _validate_transform(neutral_transform)
    authority, family_annotations = _validate_annotations(annotations)
    device_size = (logical_width * backing_scale, logical_height * backing_scale)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    raw: dict[str, Image.Image] = {}
    for family in MASK_FAMILIES:
        mask = Image.new("L", device_size, 0)
        for shape in family_annotations[family]["geometry"]:
            if not isinstance(shape, dict):
                raise ParityError(f"{family} geometry entries must be objects")
            _draw_geometry(
                mask,
                shape,
                scale=scale,
                tx=tx,
                ty=ty,
                logical_width=logical_width,
                logical_height=logical_height,
            )
        raw[family] = mask

    for halo_family in MASK_FAMILIES[:-1]:
        if _overlap_pixels(raw["os-external"], raw[halo_family]):
            raise ParityError(
                f"os-external overlaps Halo-owned {halo_family} annotations"
            )

    masks = dict(raw)
    inverse_text = ImageChops.invert(raw["text-layout-boxes"])
    for family in AGGREGATE_FAMILIES:
        masks[family] = ImageChops.multiply(raw[family], inverse_text)

    for family in AGGREGATE_FAMILIES:
        if _overlap_pixels(masks[family], masks["text-layout-boxes"]):
            raise ParityError(f"text exclusion failed for aggregate family {family}")
    for left, right in combinations(MASK_FAMILIES, 2):
        allowed = left in AGGREGATE_FAMILIES and right in AGGREGATE_FAMILIES
        if not allowed and _overlap_pixels(masks[left], masks[right]):
            raise ParityError(f"forbidden final mask overlap: {left} / {right}")

    entries: list[dict[str, Any]] = []
    for family in MASK_FAMILIES:
        filename = f"{profile_id}-{family}-v1.png"
        path = output_dir / filename
        _atomic_save_png(masks[family], path)
        entries.append(
            {
                "maskId": f"{profile_id}-{family}-v1",
                "family": family,
                "path": filename,
                "dimensions": {
                    "width": device_size[0],
                    "height": device_size[1],
                },
                "sha256": sha256_file(path),
                "selectors": family_annotations[family]["selectors"],
                "selectorsSha256": _hash(family_annotations[family]["selectors"]),
                "geometry": family_annotations[family]["geometry"],
                "geometrySha256": _hash(family_annotations[family]["geometry"]),
                "purpose": FAMILY_PURPOSES[family],
            }
        )

    manifest: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "maskSetId": f"{MASK_SET_VERSION}-{profile_id}",
        "status": "frozen",
        "profile": profile,
        "coordinateSpace": "canonical-device-pixels",
        "dimensions": {"width": device_size[0], "height": device_size[1]},
        "annotationAuthority": authority,
        "annotationsSha256": _hash(annotations),
        "neutralTransform": neutral_transform,
        "neutralTransformSha256": _hash(neutral_transform),
        "rasterizer": RASTERIZER,
        "families": entries,
    }
    manifest["manifestSha256"] = _hash(manifest)
    manifest_path = output_dir / "manifest.json"
    _atomic_write_json(manifest_path, manifest)
    verify_mask_manifest(manifest_path)
    return manifest_path


def verify_mask_manifest(manifest_path: Path) -> dict[str, Any]:
    """Verify the closed manifest, PNG hashes/dimensions/binary values, and policy."""
    manifest_path = Path(manifest_path)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise ParityError(f"unable to read mask manifest: {manifest_path}") from error
    _require_exact_keys(
        manifest,
        {
            "schemaVersion",
            "maskSetId",
            "status",
            "profile",
            "coordinateSpace",
            "dimensions",
            "annotationAuthority",
            "annotationsSha256",
            "neutralTransform",
            "neutralTransformSha256",
            "rasterizer",
            "families",
            "manifestSha256",
        },
        "mask manifest",
    )
    claimed_manifest_hash = _sha256(
        manifest["manifestSha256"], "manifestSha256"
    )
    unhashed = dict(manifest)
    del unhashed["manifestSha256"]
    if _hash(unhashed) != claimed_manifest_hash:
        raise ParityError("mask manifest hash mismatch")
    if (
        manifest["schemaVersion"] != SCHEMA_VERSION
        or manifest["status"] != "frozen"
        or manifest["coordinateSpace"] != "canonical-device-pixels"
        or manifest["rasterizer"] != RASTERIZER
    ):
        raise ParityError("mask manifest frozen contract is invalid")
    profile_id, logical_width, logical_height, backing_scale = _profile_dimensions(
        manifest["profile"]
    )
    scale, tx, ty = _validate_transform(manifest["neutralTransform"])
    if _hash(manifest["neutralTransform"]) != manifest["neutralTransformSha256"]:
        raise ParityError("neutral transform hash mismatch")
    authority = _require_exact_keys(
        manifest["annotationAuthority"],
        {"sourceRole", "sourcePath", "sha256"},
        "manifest annotationAuthority",
    )
    if authority["sourceRole"] != "authoritative-reference":
        raise ParityError("manifest annotation authority role is invalid")
    _safe_input_path(authority["sourcePath"], "manifest authority sourcePath")
    _sha256(authority["sha256"], "manifest authority sha256")
    _sha256(manifest["annotationsSha256"], "annotationsSha256")
    expected_dimensions = {
        "width": logical_width * backing_scale,
        "height": logical_height * backing_scale,
    }
    if manifest["dimensions"] != expected_dimensions:
        raise ParityError("mask manifest dimensions do not match canonical profile")
    if manifest["maskSetId"] != f"{MASK_SET_VERSION}-{profile_id}":
        raise ParityError("mask set ID does not match profile")
    entries = manifest["families"]
    if (
        not isinstance(entries, list)
        or len(entries) != len(MASK_FAMILIES)
        or [entry.get("family") for entry in entries] != list(MASK_FAMILIES)
    ):
        raise ParityError("mask manifest must list all six families in frozen order")

    images: dict[str, Image.Image] = {}
    source_families: dict[str, dict[str, Any]] = {}
    for entry in entries:
        _require_exact_keys(
            entry,
            {
                "maskId",
                "family",
                "path",
                "dimensions",
                "sha256",
                "selectors",
                "selectorsSha256",
                "geometry",
                "geometrySha256",
                "purpose",
            },
            "mask family entry",
        )
        family = entry["family"]
        expected_id = f"{profile_id}-{family}-v1"
        expected_path = f"{expected_id}.png"
        if entry["maskId"] != expected_id or entry["path"] != expected_path:
            raise ParityError(f"{family} mask ID/path is not canonical")
        if entry["dimensions"] != expected_dimensions:
            raise ParityError(f"{family} manifest dimensions are invalid")
        if (
            not isinstance(entry["selectors"], list)
            or not entry["selectors"]
            or any(
                not isinstance(selector, str) or not selector
                for selector in entry["selectors"]
            )
        ):
            raise ParityError(f"{family} source selectors are missing")
        if _hash(entry["selectors"]) != _sha256(
            entry["selectorsSha256"], f"{family} selectorsSha256"
        ):
            raise ParityError(f"{family} source selector hash mismatch")
        if not isinstance(entry["geometry"], list) or not entry["geometry"]:
            raise ParityError(f"{family} source geometry is missing")
        for shape in entry["geometry"]:
            if not isinstance(shape, dict):
                raise ParityError(f"{family} source geometry entry is invalid")
            x0, y0, x1, y1 = _source_bounds(shape)
            if (
                x0 < 0
                or y0 < 0
                or x1 > logical_width
                or y1 > logical_height
            ):
                raise ParityError(
                    f"{family} source geometry lies outside reference bounds"
                )
        if _hash(entry["geometry"]) != _sha256(
            entry["geometrySha256"], f"{family} geometrySha256"
        ):
            raise ParityError(f"{family} source geometry hash mismatch")
        if entry["purpose"] != FAMILY_PURPOSES[family]:
            raise ParityError(f"{family} purpose does not match frozen policy")
        source_families[family] = {
            "selectors": entry["selectors"],
            "geometry": entry["geometry"],
        }
        expected_file_hash = _sha256(entry["sha256"], f"{family} sha256")
        path = manifest_path.parent / entry["path"]
        if not path.is_file() or sha256_file(path) != expected_file_hash:
            raise ParityError(f"{family} PNG hash mismatch or file is missing")
        try:
            with Image.open(path) as opened:
                opened.verify()
            with Image.open(path) as opened:
                if opened.format != "PNG" or opened.mode != "L":
                    raise ParityError(f"{family} mask must be an 8-bit grayscale PNG")
                if opened.size != (
                    expected_dimensions["width"],
                    expected_dimensions["height"],
                ):
                    raise ParityError(f"{family} PNG dimensions are invalid")
                histogram = opened.histogram()
                if any(
                    count and value not in {0, 255}
                    for value, count in enumerate(histogram)
                ):
                    raise ParityError(f"{family} PNG contains non-binary pixels")
                images[family] = opened.copy()
        except (OSError, SyntaxError) as error:
            raise ParityError(f"{family} mask is not a valid lossless PNG") from error

    reconstructed_annotations = {
        "schemaVersion": SCHEMA_VERSION,
        "coordinateSpace": "reference-logical-points",
        "authority": authority,
        "families": source_families,
    }
    if _hash(reconstructed_annotations) != manifest["annotationsSha256"]:
        raise ParityError("annotation source hash does not match family records")

    expected_raw: dict[str, Image.Image] = {}
    expected_size = (expected_dimensions["width"], expected_dimensions["height"])
    for family in MASK_FAMILIES:
        expected = Image.new("L", expected_size, 0)
        for shape in source_families[family]["geometry"]:
            _draw_geometry(
                expected,
                shape,
                scale=scale,
                tx=tx,
                ty=ty,
                logical_width=logical_width,
                logical_height=logical_height,
            )
        expected_raw[family] = expected
    for family in MASK_FAMILIES[:-1]:
        if _overlap_pixels(expected_raw[family], expected_raw["os-external"]):
            raise ParityError(f"os-external source geometry overlaps {family}")
    expected_masks = dict(expected_raw)
    inverse_text = ImageChops.invert(expected_raw["text-layout-boxes"])
    for family in AGGREGATE_FAMILIES:
        expected_masks[family] = ImageChops.multiply(
            expected_raw[family], inverse_text
        )
    for family in MASK_FAMILIES:
        if ImageChops.difference(expected_masks[family], images[family]).getbbox():
            raise ParityError(f"{family} PNG does not match frozen source geometry")

    for family in AGGREGATE_FAMILIES:
        if _overlap_pixels(images[family], images["text-layout-boxes"]):
            raise ParityError(f"{family} overlaps text-layout-boxes")
    for family in MASK_FAMILIES[:-1]:
        if _overlap_pixels(images[family], images["os-external"]):
            raise ParityError(f"os-external overlaps Halo-owned {family}")
    return {
        "valid": True,
        "maskSetId": manifest["maskSetId"],
        "profileId": profile_id,
        "familyCount": len(entries),
        "dimensions": expected_dimensions,
        "manifestSha256": claimed_manifest_hash,
    }
