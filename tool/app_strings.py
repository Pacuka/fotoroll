#!/usr/bin/env python3
"""Adds/updates app-only strings in assets/i18n_app/{en,hu}.json.
Usage: python3 tool/app_strings.py key "English" "Magyar" [key en hu ...]"""
import json, sys, os
root = os.path.join(os.path.dirname(__file__), '..', 'assets', 'i18n_app')
files = {lang: os.path.join(root, f'{lang}.json') for lang in ('en', 'hu')}
data = {}
for lang, f in files.items():
    data[lang] = json.load(open(f)) if os.path.exists(f) else {}
args = sys.argv[1:]
assert len(args) % 3 == 0, 'need key/en/hu triples'
for i in range(0, len(args), 3):
    k, en, hu = args[i:i + 3]
    data['en'][k] = en
    data['hu'][k] = hu
for lang, f in files.items():
    with open(f, 'w') as fh:
        json.dump(dict(sorted(data[lang].items())), fh, ensure_ascii=False, indent=2)
        fh.write('\n')
