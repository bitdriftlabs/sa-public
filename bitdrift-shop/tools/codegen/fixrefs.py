#!/usr/bin/env python3
"""Re-points stale `source:` file:line citations in spec/*.yaml after code edits shift lines.

Runs `spec/validate.py --strict`, and for every "not found near <file>:<line>" warning moves the
citation to the nearest line that mentions the token (or its generated-constant spelling).
Run from the bitdrift-shop root with the codegen venv:

    tools/codegen/.venv/bin/python tools/codegen/fixrefs.py

Citations whose token appears nowhere in the file are reported as NOFIX and need a hand edit.
"""
import glob
import re
import subprocess
import sys

sys.path.insert(0, 'tools/codegen')
import codegen as cg  # noqa: E402

out = subprocess.run(['tools/codegen/.venv/bin/python', 'spec/validate.py', '--strict'],
                     capture_output=True, text=True).stdout
roots = {'A': 'android/app/src/main/java/ai/bitdrift/shop', 'I': 'ios/BitdriftShop',
         'R': 'reactnative', 'F': 'flutter/lib'}
fix = {}
for l in out.splitlines():
    m = re.match(r"WARN\s+(\S+): (.+?) not found near (\S+):(\d+)", l)
    if not m:
        continue
    where, tok, path, line = m.group(1), m.group(2).strip("\"'"), m.group(3), int(m.group(4))
    variants = {tok, cg.const_name(tok), cg.camel(tok).strip('`'), tok[:1].lower() + tok[1:]}
    p = where.split('.')
    if p[0] == 'screens':
        variants.add(cg.camel(p[1]).strip('`'))
    hits = [i for i, t in enumerate(open(path).read().splitlines(), 1)
            if any(re.search(r'(?<![A-Za-z0-9_])' + re.escape(v) + r'(?![A-Za-z0-9_])', t) for v in variants)]
    if not hits:
        print('NOFIX', where, tok)
        continue
    for r, b in roots.items():
        if path.startswith(b + '/'):
            fix[f'{r}:{path[len(b) + 1:]}:{line}'] = f'{r}:{path[len(b) + 1:]}:{min(hits, key=lambda h: abs(h - line))}'
for f in glob.glob('spec/*.yaml'):
    s = open(f).read()
    o = s
    for a, b in fix.items():
        s = s.replace('"' + a + '"', '"' + b + '"')
    if s != o:
        open(f, 'w').write(s)
print(len(fix), 'refs updated')
