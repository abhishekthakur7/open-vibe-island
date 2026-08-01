from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from .trust import TrustError, digest


CHROME_CANDIDATES = (
    Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
)


def _chrome() -> Path:
    for candidate in CHROME_CANDIDATES:
        if candidate.is_file():
            return candidate
    discovered = shutil.which("google-chrome") or shutil.which("chromium")
    if discovered:
        return Path(discovered)
    raise TrustError("browser execution unavailable: Chrome/Chromium was not found")


def _receive(ws: Any, command_id: int) -> dict[str, Any]:
    while True:
        message = json.loads(ws.recv())
        if message.get("id") == command_id:
            if "error" in message:
                raise TrustError(f"browser protocol error: {message['error']}")
            return message["result"]


def verify_reference_dom(html: Path, expected_sha256: str, scenarios: list[dict[str, Any]]) -> dict[str, Any]:
    if digest(html) != expected_sha256:
        raise TrustError("reference source hash mismatch before browser execution")
    try:
        from websockets.sync.client import connect
    except ImportError as exc:
        raise TrustError("browser execution unavailable: Python websockets support is missing") from exc
    direct = [row for row in scenarios if row["class"] in {"rendered-canonical", "rendered-motion-exemplar"}]
    query = [{"scenario": row["id"], "selector": row["anchor"]["selector"], "identity": row["anchor"].get("identity")} for row in direct]
    if any(not item["identity"] for item in query):
        raise TrustError("every direct reference selector requires an identity contract")
    browser_path=_chrome()
    flags=["--headless=new","--no-first-run","--disable-gpu","--remote-debugging-port=0","--remote-allow-origins=*"]
    with tempfile.TemporaryDirectory(prefix="poured-dom-") as profile:
        process = subprocess.Popen(
            [str(browser_path), *flags, f"--user-data-dir={profile}", "about:blank"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            endpoint = None
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                line = process.stderr.readline() if process.stderr else ""
                match = re.search(r"DevTools listening on (ws://\S+)", line)
                if match:
                    endpoint = match.group(1)
                    break
                if process.poll() is not None:
                    break
            if endpoint is None:
                raise TrustError("browser execution unavailable: debugging endpoint did not start")
            with connect(endpoint, open_timeout=5) as ws:
                command_id = 1
                ws.send(json.dumps({"id":command_id,"method":"Browser.getVersion"}))
                product=_receive(ws,command_id)
                command_id += 1
                ws.send(json.dumps({"id": command_id, "method": "Target.createTarget", "params": {"url": "about:blank"}}))
                target = _receive(ws, command_id)["targetId"]
                command_id += 1
                ws.send(json.dumps({"id": command_id, "method": "Target.attachToTarget", "params": {"targetId": target, "flatten": True}}))
                session = _receive(ws, command_id)["sessionId"]
                command_id += 1; ws.send(json.dumps({"id":command_id,"sessionId":session,"method":"Page.enable"})); _receive(ws,command_id)
                intended=html.resolve().as_uri(); command_id += 1; ws.send(json.dumps({"id":command_id,"sessionId":session,"method":"Page.navigate","params":{"url":intended}})); _receive(ws,command_id)
                ready_deadline=time.monotonic()+10; ready=False
                while time.monotonic()<ready_deadline:
                    command_id += 1; ws.send(json.dumps({"id":command_id,"sessionId":session,"method":"Runtime.evaluate","params":{"expression":"({ready:document.readyState,url:location.href})","returnByValue":True}})); state=_receive(ws,command_id).get("result",{}).get("value",{})
                    if state.get("url")!=intended: raise TrustError("browser navigated to an unintended reference URL")
                    if state.get("ready")=="complete": ready=True; break
                if not ready: raise TrustError("browser reference document did not reach readyState complete before deadline")
                expression = """
                (() => {
                  const queries = %s;
                  return queries.map(q => {
                    const nodes = [...document.querySelectorAll(q.selector)];
                    return {scenario:q.scenario, selector:q.selector, count:nodes.length,
                      nodes:nodes.map(n => ({tag:n.tagName.toLowerCase(), classes:[...n.classList].sort(),
                        text:n.innerText.replace(/\\s+/g,' ').trim()}))};
                  });
                })()
                """ % json.dumps(query)
                command_id += 1
                ws.send(json.dumps({"id": command_id, "sessionId": session, "method": "Runtime.evaluate", "params": {"expression": expression, "returnByValue": True, "awaitPromise": True}}))
                result = _receive(ws, command_id)["result"]["value"]
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
            if process.stderr is not None:
                process.stderr.close()
    by_id = {item["scenario"]: item for item in result}
    records = []
    for item in query:
        actual = by_id.get(item["scenario"], {})
        if actual.get("count") != 1:
            raise TrustError(f"reference selector cardinality for {item['scenario']} is {actual.get('count')}, expected 1")
        node = actual["nodes"][0]
        identity = item["identity"]
        if node["tag"] != identity["tag"] or not set(identity["classes"]) <= set(node["classes"]):
            raise TrustError(f"reference selector identity mismatch for {item['scenario']}")
        for text in identity.get("text_contains", []):
            if text not in node["text"]:
                raise TrustError(f"reference selector text identity mismatch for {item['scenario']}: {text!r}")
        records.append({**actual, "identity": identity})
    return {"schema_version": 1, "engine": "chrome-cdp", "browser":{"path":str(browser_path),"sha256":digest(browser_path),"product":product.get("product"),"revision":product.get("revision"),"protocol_version":product.get("protocolVersion"),"user_agent":product.get("userAgent"),"js_version":product.get("jsVersion"),"flags":flags}, "source_sha256": expected_sha256, "records": records, "passed": True}
