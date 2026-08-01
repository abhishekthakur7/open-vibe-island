import copy
import re
import unittest
from unittest.mock import patch

from tools.poured_parity.core import ROOT, ParityError, VALIDATION, load, verify_manifests


def _swift_source_texts():
    return [path.read_text(encoding="utf-8", errors="replace") for path in sorted((ROOT / "Sources").rglob("*.swift"))]


def _resolves_in_swift_sources(symbol, texts):
    """True when `symbol` names a Swift type (bare) or one of its members present in Sources/**.

    Mirrors `core._verify_native_symbol`'s regex approach rather than importing
    it, because ledger `source_symbols` are a looser vocabulary than scenario
    `native.mapping`: a bare type name (`PouredSessionListScaffold`) is a valid
    evidence location, and `verify_manifests` never checks these at all — so an
    item can quietly cite a symbol the sources deleted.
    """
    type_name, _, member = symbol.partition(".")
    declaration = re.compile(rf"\b(?:enum|struct|class|actor|protocol)\s+{re.escape(type_name)}\b")
    extension = re.compile(rf"\bextension\s+{re.escape(type_name)}\b")
    candidates = [text for text in texts if declaration.search(text)]
    if not candidates:
        return False
    if not member:
        return True
    candidates += [text for text in texts if extension.search(text)]
    member_declaration = re.compile(rf"\b(?:case|func|var|let)\s+{re.escape(member)}\b")
    return any(member_declaration.search(text) for text in candidates)

class PouredManifestTests(unittest.TestCase):
    def test_committed_manifests_validate_and_remain_pending(self):
        result=verify_manifests(); self.assertTrue(result["approval_pending"]); self.assertEqual(result["scenario_count"],39)
    def test_required_scenario_contracts(self):
        rows={x["id"]:x for x in load(VALIDATION/"scenarios-v1.json")["scenarios"]}
        self.assertEqual(rows["F1-question"]["class"],"derived-validation")
        self.assertEqual(rows["C4-stress-40"]["native"]["status"],"not-located")
        self.assertEqual(rows["H1-completed"]["native"]["mapping"],"IslandDebugScenario.completionCard")
        for key in ("D1-detail","E1-command-permission","E2-diff-permission","E3-jump-codex"): self.assertIn(key,rows)
    def test_unknown_class_duplicate_and_false_direct_claim_rejected(self):
        original=load(VALIDATION/"scenarios-v1.json")
        for mutation, message in (
            (lambda x:x["scenarios"][0].__setitem__("class","fiction"),"unknown class"),
            (lambda x:x["scenarios"][1].__setitem__("id",x["scenarios"][0]["id"]),"duplicate"),
            (lambda x:x["scenarios"][7].__setitem__("direct_reference",True),"claims a direct")):
            value=copy.deepcopy(original); mutation(value)
            real_load=load
            with patch("tools.poured_parity.core.load",side_effect=lambda p,v=value: v if p.name=="scenarios-v1.json" else real_load(p)):
                with self.assertRaisesRegex(ParityError,message): verify_manifests()
    def test_mapping_and_f1_regressions_rejected(self):
        original=load(VALIDATION/"scenarios-v1.json"); real_load=load
        for scenario,field,value in (("F1-question","class","rendered-canonical"),("A2-working-one","mapping","IslandDebugScenario.working"),("C4-stress-40","mapping","IslandDebugScenario.large")):
            altered=copy.deepcopy(original); row=next(x for x in altered["scenarios"] if x["id"]==scenario)
            (row["native"] if field=="mapping" else row)[field]=value
            with patch("tools.poured_parity.core.load",side_effect=lambda p,v=altered: v if p.name=="scenarios-v1.json" else real_load(p)):
                with self.assertRaises(ParityError): verify_manifests()
    def test_native_mappings_name_only_symbols_present_in_swift_sources(self):
        rows={x["id"]:x for x in load(VALIDATION/"scenarios-v1.json")["scenarios"]}
        self.assertIsNone(rows["A1-idle"]["native"]["mapping"])
        self.assertEqual(rows["E1-command-permission"]["native"]["mapping"],"IslandDebugScenario.approvalCard")
        original=load(VALIDATION/"scenarios-v1.json"); real_load=load
        for scenario,mapping,message in (
            ("E1-command-permission","IslandDebugScenario.permission","member absent from Swift sources"),
            ("A1-idle","PouredParityScenario.idle","member absent from Swift sources"),
            ("A2-working-one","InventedType.closed","undeclared Swift type"),
            ("A2m-working-many","notASwiftSymbol","not a <Type>.<member> Swift symbol")):
            altered=copy.deepcopy(original); next(x for x in altered["scenarios"] if x["id"]==scenario)["native"]["mapping"]=mapping
            with patch("tools.poured_parity.core.load",side_effect=lambda p,v=altered: v if p.name=="scenarios-v1.json" else real_load(p)):
                with self.assertRaisesRegex(ParityError,message): verify_manifests()

    def test_conflicts_cannot_pass_without_authority(self):
        ledger=load(VALIDATION/"ledger-v1.json"); next(x for x in ledger["items"] if x["id"]=="PI-REF-001")["status"]="passed"; real_load=load
        with patch("tools.poured_parity.core.load",side_effect=lambda p: ledger if p.name=="ledger-v1.json" else real_load(p)):
            with self.assertRaisesRegex(ParityError,"allowed product/design-owner disposition"): verify_manifests()
    def test_arbitrary_conflict_strings_and_self_authority_are_rejected(self):
        ledger=load(VALIDATION/"ledger-v1.json"); next(x for x in ledger["items"] if x["id"]=="PI-REF-001")["status"]="passed"
        conflicts=load(VALIDATION/"conflicts-v1.json"); conflict=next(x for x in conflicts["conflicts"] if x["id"]=="PI-REF-001"); conflict.update(status="resolved",ruling="anything",authority="self")
        real_load=load
        with patch("tools.poured_parity.core.load",side_effect=lambda p: ledger if p.name=="ledger-v1.json" else conflicts if p.name=="conflicts-v1.json" else real_load(p)):
            with self.assertRaisesRegex(ParityError,"allowed product/design-owner disposition"): verify_manifests()

class PouredLedgerSourceSymbolTests(unittest.TestCase):
    """PI-V-001: every ledger evidence symbol must still exist in the sources.

    `verify_manifests` source-verifies scenario `native.mapping` only. Ledger
    items carry their own `source_symbols`, and nothing checked them — a rename
    or deletion would leave the ledger pointing at code that no longer exists
    while the tooling stayed green.
    """

    def test_every_ledger_source_symbol_resolves_in_swift_sources(self):
        texts = _swift_source_texts()
        unresolved = []
        for item in load(VALIDATION / "ledger-v1.json")["items"]:
            symbols = item.get("source_symbols")
            self.assertIsInstance(symbols, list, f"{item['id']} source_symbols must be a list")
            for symbol in symbols:
                self.assertIsInstance(symbol, str)
                self.assertTrue(symbol.strip(), f"{item['id']} carries an empty source symbol")
                if not _resolves_in_swift_sources(symbol, texts):
                    unresolved.append(f"{item['id']}:{symbol}")
        self.assertEqual(unresolved, [], f"ledger source symbols missing from Sources/**: {unresolved}")

    def test_guard_rejects_a_renamed_or_invented_symbol(self):
        texts = _swift_source_texts()
        # Positive controls: a bare type, and a real type.member.
        self.assertTrue(_resolves_in_swift_sources("PouredSessionListScaffold", texts))
        self.assertTrue(_resolves_in_swift_sources("AgentSession.spotlightDisplayName", texts))
        # Negative controls: undeclared type, and a member the type does not have.
        self.assertFalse(_resolves_in_swift_sources("InventedScaffold", texts))
        self.assertFalse(_resolves_in_swift_sources("AgentSession.spotlightDisplayNameV2", texts))

    def test_c1_now_carries_a_deterministic_native_fixture(self):
        row = {x["id"]: x for x in load(VALIDATION / "scenarios-v1.json")["scenarios"]}["C1-grouped-six"]
        self.assertEqual(row["native"]["mapping"], "IslandDebugScenario.pouredGroupedSix")
        self.assertEqual(row["native"]["status"], "partial")
        self.assertTrue(row["deterministic"])
        self.assertTrue(row["reproducible"])
        # A deterministic fixture is evidence, not capture authority — the row
        # must still say why it is blocked.
        self.assertTrue(row["blocked_reason"])

if __name__=="__main__": unittest.main()
