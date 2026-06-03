#!/usr/bin/env python3
"""Patch rules_apple for CI: remove provisioning_profile device-build requirements."""
import sys
import os

rules_apple_dir = sys.argv[1]

patches = [
    # provisioning_profile.bzl: replace fail() with early return
    (
        os.path.join(rules_apple_dir, "apple/internal/partials/provisioning_profile.bzl"),
        '    if not profile_artifact:\n        fail(\n            "\\n".join([\n                "ERROR: In {}:".format(str(rule_label)),\n                "Building for device, but no provisioning_profile attribute was set.",\n            ]),\n        )',
        '    if not profile_artifact:\n        return struct(bundle_files = [])  # CI: skip',
    ),
    # codesigning_support.bzl: neutralize the validate_provisioning_profile check
    (
        os.path.join(rules_apple_dir, "apple/internal/codesigning_support.bzl"),
        '    if (platform_prerequisites.platform.is_device and\n        rule_descriptor.requires_signing_for_device and\n        not provisioning_profile):\n        fail("The provisioning_profile attribute must be set for device " +\n             "builds on this platform (%s)." %\n             platform_prerequisites.platform_type)',
        '    if False:  # CI: skip provisioning profile validation\n        pass',
    ),
]

for path, old, new in patches:
    if not os.path.exists(path):
        print(f"SKIP (not found): {path}")
        continue
    src = open(path).read()
    if old in src:
        open(path, 'w').write(src.replace(old, new))
        print(f"Patched OK: {path}")
    elif new in src:
        print(f"Already patched: {path}")
    else:
        print(f"WARNING: pattern not found in {path}")
