import copy
import unittest
from unittest.mock import patch

from tools.poured_parity.core import ParityError, VALIDATION, load, verify_manifests

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

if __name__=="__main__": unittest.main()
