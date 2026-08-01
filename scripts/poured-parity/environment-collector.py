#!/usr/bin/env python3
"""Versioned capture seam for Poured environment attestations.

This collector intentionally emits only locally measurable runtime facts. Native
capture code must add display, preference, window, signing, and capture facts and
an authorized attestor identity before the sidecar can become canonical.
"""
import json, platform, sys

print(json.dumps({"schema_version":1,"measured":{"macos":platform.mac_ver()[0],"hardware":platform.machine(),"python":platform.python_version(),"executable":sys.executable},"canonical_ready":False},sort_keys=True))
