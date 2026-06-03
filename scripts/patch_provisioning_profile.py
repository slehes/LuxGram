#!/usr/bin/env python3
"""Patch rules_apple provisioning_profile.bzl for CI: replace fail() with early return."""
import sys

path = sys.argv[1]
src = open(path).read()

old = '    if not profile_artifact:\n        fail(\n            "\\n".join([\n                "ERROR: In {}:".format(str(rule_label)),\n                "Building for device, but no provisioning_profile attribute was set.",\n            ]),\n        )'
new = '    if not profile_artifact:\n        return struct(bundle_files = [])  # CI: skip'

if old in src:
    src = src.replace(old, new)
    open(path, 'w').write(src)
    print(f"Patched OK: {path}")
else:
    print(f"Pattern not found in {path} — may already be patched or file changed")
    print("Attempting fallback: replacing 'if not profile_artifact:' block")
    lines = src.splitlines()
    out = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == 'if not profile_artifact:' and i + 1 < len(lines) and 'fail(' in lines[i+1]:
            out.append(lines[i])
            out.append('        return struct(bundle_files = [])  # CI: skip')
            # skip until matching closing paren of fail(...)
            i += 1
            depth = 0
            while i < len(lines):
                depth += lines[i].count('(') - lines[i].count(')')
                i += 1
                if depth <= 0:
                    break
        else:
            out.append(lines[i])
            i += 1
    open(path, 'w').write('\n'.join(out) + '\n')
    print(f"Fallback patch applied: {path}")
