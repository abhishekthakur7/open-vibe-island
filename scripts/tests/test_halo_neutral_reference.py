from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HTML = ROOT / "Validation/HaloParity/calibration/v1/reference/neutral-v1.html"
SUITE = ROOT / "Validation/HaloParity/calibration/v1/suite.json"


class HaloNeutralReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = HTML.read_text(encoding="utf-8")
        cls.suite = json.loads(SUITE.read_text(encoding="utf-8"))

    def test_all_frozen_primitive_ids_are_present(self) -> None:
        expected = {item["id"] for item in self.suite["primitives"]}
        actual = set(re.findall(r'data-primitive-id="([^"]+)"', self.source))
        self.assertEqual(expected, actual)

    def test_profiles_and_modes_are_closed_and_versioned(self) -> None:
        self.assertIn('"notch-v1": Object.freeze({ width: 540', self.source)
        self.assertIn('"top-bar-v1": Object.freeze({ width: 520', self.source)
        self.assertIn('["static", "manual", "normal", "reduced"]', self.source)
        self.assertIn("unknown neutral profile", self.source)
        self.assertIn("unknown neutral mode", self.source)
        self.assertIn("timeMs is valid only in manual mode", self.source)

    def test_frozen_neutral_values_are_literal(self) -> None:
        for value in ("#000", "#202020", "#808080", "#fff"):
            self.assertIn(value, self.source)
        for width in ("height: 1px", "height: 1.5px", "height: 2px"):
            self.assertIn(width, self.source)
        for radius in ("border-radius: 8px", "border-radius: 19px", "border-radius: 28px"):
            self.assertIn(radius, self.source)
        for alpha in ("opacity: .08", "opacity: .16", "opacity: .5", "opacity: 1"):
            self.assertIn(alpha, self.source)
        self.assertIn("1000ms linear infinite", self.source)
        self.assertIn("translateX(120px)", self.source)

    def test_source_is_self_contained_and_has_no_remote_inputs(self) -> None:
        self.assertNotRegex(self.source, r'https?://')
        self.assertNotIn("<link", self.source.lower())
        self.assertNotRegex(self.source, r'<script[^>]+src=')
        lowered = self.source.lower()
        for forbidden in ("halo reference", "halo candidate", "known halo defect"):
            self.assertNotIn(forbidden, lowered)

    def test_machine_readable_mapping_metadata_is_present(self) -> None:
        for key in (
            "neutralMappedUnitCssPx",
            "neutralExpectedScale",
            "neutralViewportWidth",
            "neutralViewportHeight",
            "neutralObservedDpr",
            "neutralCanvasX",
            "neutralCanvasY",
            "neutralCanvasWidth",
            "neutralCanvasHeight",
        ):
            self.assertIn(key, self.source)

    def test_canvas_is_exact_profile_geometry_without_page_padding(self) -> None:
        self.assertRegex(self.source, r"#neutral-suite\s*\{[^}]*height:\s*320px")
        self.assertRegex(self.source, r"body\s*\{[^}]*place-items:\s*start center")
        body_rule = re.search(r"body\s*\{([^}]*)\}", self.source)
        self.assertIsNotNone(body_rule)
        self.assertNotIn("padding", body_rule.group(1))
        self.assertIn("neutral canvas geometry mismatch", self.source)


if __name__ == "__main__":
    unittest.main()
