from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from .core import (ParityError, ROOT, analyze_calibration, artifact_run_for, compare_static, fingerprint,
    freeze_calibration, generate_masks, index_run, init_run, load, native_plan, reference_plan,
    review_packet, validate_motion, verify_freshness, verify_gate, verify_manifests,
    verify_masks, verify_reference_dom, write)

def emit(value): print(json.dumps(value, indent=2, sort_keys=True))
def evidence_output(path,role,source=None):
    output=Path(path); root,resolved=artifact_run_for(output)
    relative=resolved.relative_to(root)
    if not relative.parts or relative.parts[0]!=role: raise ParityError(f"output must use canonical run role {role}")
    if source is not None and artifact_run_for(Path(source),True)[0]!=root: raise ParityError("input and output must share one canonical run")
    return resolved
def swift_test(filter_expression: str) -> int:
    """Compile and run the Poured Swift seam with its conditional flag defined.

    The seam lives entirely inside `#if POURED_PARITY_TESTING`; without
    `-Xswiftc -DPOURED_PARITY_TESTING` those regions are not even type-checked,
    so this is the only command that proves the seam builds.
    """
    command=["swift","test","-Xswiftc","-DPOURED_PARITY_TESTING","--filter",filter_expression]
    completed=subprocess.run(command,cwd=str(ROOT),check=False)
    return completed.returncode
def parser():
    p=argparse.ArgumentParser(prog="poured",description="Fail-closed Poured parity validation")
    s=p.add_subparsers(dest="command",required=True)
    d=s.add_parser("doctor"); d.add_argument("--bindings")
    fp=s.add_parser("fingerprint"); fp.add_argument("--bindings")
    s.add_parser("reference-verify")
    v=s.add_parser("verify-manifests"); v.add_argument("--require-ready",action="store_true")
    i=s.add_parser("init-run"); i.add_argument("--run-id",required=True); i.add_argument("--bindings")
    for name in ("reference-plan","native-plan"):
        q=s.add_parser(name); q.add_argument("--output")
    a=s.add_parser("calibrate-analyze"); a.add_argument("manifest"); a.add_argument("--output")
    f=s.add_parser("calibrate-freeze"); f.add_argument("analysis"); f.add_argument("output"); f.add_argument("--masks",required=True); f.add_argument("--aa-band",required=True,type=int); f.add_argument("--thresholds",required=True); f.add_argument("--approval",required=True)
    mg=s.add_parser("masks-generate"); mg.add_argument("annotations"); mg.add_argument("output")
    mv=s.add_parser("masks-verify"); mv.add_argument("manifest")
    c=s.add_parser("compare-static"); c.add_argument("output"); c.add_argument("--spec",required=True)
    m=s.add_parser("compare-motion"); m.add_argument("manifest"); m.add_argument("output")
    rp=s.add_parser("review-packet"); rp.add_argument("run"); rp.add_argument("--approval")
    fr=s.add_parser("freshness"); fr.add_argument("run")
    ei=s.add_parser("evidence-index"); ei.add_argument("run")
    g=s.add_parser("verify"); g.add_argument("--gate",choices=["0A","0B","0C"],required=True); g.add_argument("--run")
    st=s.add_parser("swift-test"); st.add_argument("--filter",default="PouredParityTests",dest="filter_expression")
    return p
def main(argv=None):
    args=parser().parse_args(argv)
    try:
        if args.command=="doctor": emit({"manifests":verify_manifests(),"fingerprint":fingerprint(Path(args.bindings) if args.bindings else None),"status":"blocked-unvalidated"})
        elif args.command=="fingerprint": emit(fingerprint(Path(args.bindings) if args.bindings else None))
        elif args.command=="reference-verify": emit(verify_reference_dom())
        elif args.command=="verify-manifests": emit(verify_manifests(args.require_ready))
        elif args.command=="init-run": emit({"run":str(init_run(args.run_id,Path(args.bindings) if args.bindings else None))})
        elif args.command in {"reference-plan","native-plan"}:
            value=reference_plan() if args.command=="reference-plan" else native_plan()
            if args.output: write(evidence_output(args.output,"reference" if args.command=="reference-plan" else "native-baseline"),value)
            emit(value)
        elif args.command=="calibrate-analyze":
            target=evidence_output(args.output,"metrics",args.manifest) if args.output else None; value=analyze_calibration(Path(args.manifest)); write(target,value) if target else None; emit(value)
        elif args.command=="calibrate-freeze": emit(freeze_calibration(Path(args.analysis),Path(args.output),Path(args.masks),args.aa_band,Path(args.thresholds),Path(args.approval)))
        elif args.command=="masks-generate": emit(generate_masks(Path(args.annotations),Path(args.output)))
        elif args.command=="masks-verify": emit(verify_masks(Path(args.manifest)))
        elif args.command=="compare-static": emit(compare_static(Path(args.output),Path(args.spec)))
        elif args.command=="compare-motion": emit(validate_motion(Path(args.manifest),Path(args.output)))
        elif args.command=="review-packet": emit(review_packet(Path(args.run).absolute(),Path(args.approval) if args.approval else None))
        elif args.command=="freshness": emit(verify_freshness(Path(args.run).absolute()))
        elif args.command=="evidence-index": emit(index_run(Path(args.run).absolute()))
        elif args.command=="verify": emit(verify_gate(args.gate,Path(args.run).absolute() if args.run else None))
        elif args.command=="swift-test": return swift_test(args.filter_expression)
        return 0
    except (ParityError,KeyError,ValueError,TypeError,IndexError,OSError,json.JSONDecodeError) as exc:
        print(f"blocked-unvalidated: {exc}",file=sys.stderr); return 2
if __name__=="__main__": raise SystemExit(main())
