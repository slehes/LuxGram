#!/usr/bin/env python3
"""Patch rules_apple provisioning_profile.bzl for CI: replace fail() with early return."""
import re
import sys

path = sys.argv[1]
src = open(path).read()
src = re.sub(
    r'if not profile_artifact:\n        fail\(.*?\)',
    'if not profile_artifact:\n        return struct(bundle_files = [])  # CI: skip',
    src,
    flags=re.DOTALL,
)
open(path, 'w').write(src)
print(f"Patched: {path}")
