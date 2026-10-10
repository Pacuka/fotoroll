#!/usr/bin/env python3
"""Builds assets/admin/system_settings.json from an Immich checkout: the web's
system-settings forms (section order, groups, field labels as i18n keys, bound
config paths) plus enum values from the OpenAPI spec.
Usage: python3 -I tool/gen_system_settings.py ../immich-upstream"""
import json, os, re, sys

src = sys.argv[1]
web = os.path.join(src, 'web/src')
page = open(os.path.join(web, 'routes/admin/system-settings/+page.svelte')).read()

imports = dict(re.findall(r"import (\w+) from '([^']+)';", page))
sections = re.findall(
    r"component: (\w+),\s*title: \$t\('([^']+)'\),\s*subtitle: \$t\('([^']+)'\),\s*key: '([^']+)'", page)

spec = json.load(open(os.path.join(src, 'open-api/immich-openapi-specs.json')))
schemas = spec['components']['schemas']

def resolve(s):
    while '$ref' in s:
        s = schemas[s['$ref'].split('/')[-1]]
    if 'allOf' in s and len(s['allOf']) == 1:
        return resolve(s['allOf'][0])
    return s

def schema_at(path):
    s = resolve(schemas['SystemConfigDto'])
    for part in path.split('.'):
        if re.fullmatch(r'\d+|\[\w+\]', part):
            s = resolve(s.get('items', {}))
            continue
        s = resolve(s.get('properties', {}).get(part, {}))
    return s

tag_re = re.compile(r'<(Setting(?:Switch|InputField|Select|Textarea|Checkboxes|Combobox|Accordion))\b(.*?)(/?)>', re.S)
key_re = lambda attr: re.compile(attr + r"=\{[^}]*?\$t\('([^']+)'")
literal_re = re.compile(r'\blabel="([^"]+)"')

out = []
for comp, title, subtitle, key in sections:
    path = imports.get(comp, '')
    path = path.replace('$lib', web + '/lib') if path.startswith('$lib') else os.path.normpath(os.path.join(web, 'routes/admin/system-settings', path))
    text = open(path).read()
    items = []
    for m in tag_re.finditer(text):
        tag, body = m.group(1), m.group(2)
        t = (key_re('title').search(body) or key_re('label').search(body))
        d = (key_re('subtitle').search(body) or key_re('description').search(body))
        if tag == 'SettingAccordion':
            if t:
                items.append({'group': t.group(1), 'desc': d.group(1) if d else None})
            continue
        b = re.search(r'bind:(?:checked|value)=\{configToEdit\.([\w.\[\]]+)\}', body) \
            or re.search(r'bind:value=\{configToEdit\.([\w.]+)\}', body)
        if not b:
            continue
        p = b.group(1)
        if re.search(r'\[i\]$', p):  # list rendered item by item (e.g. ML urls)
            p = p[:-3]
        s = schema_at(p)
        kind = {'Switch': 'bool', 'Select': 'enum', 'Checkboxes': 'list', 'Textarea': 'text'}.get(tag[7:], None)
        if kind is None:
            kind = {'boolean': 'bool', 'integer': 'int', 'number': 'num', 'array': 'list'}.get(s.get('type'), 'string')
        if s.get('enum'):
            kind = 'list' if kind == 'list' else 'enum'
        lit = literal_re.search(body)
        field = {'path': p, 'kind': kind, 'title': t.group(1) if t else None, 'desc': d.group(1) if d else None}
        if not t and lit:
            field['label'] = lit.group(1)  # untranslated technical label, as on the web
        enum = s.get('enum') or resolve(s.get('items', {})).get('enum')
        if enum:
            field['options'] = enum
        elif kind == 'enum':
            # Options listed in the Svelte source: { value: 1080, text: '1080p' } / text: $t('key')
            opts = []
            block = re.search(r'options=\{\[(.*?)\]\}', body, re.S)
            for v, txt in re.findall(r"\{\s*value:\s*([^,]+?),\s*text:\s*(.+?)\s*,?\s*\}", block.group(1) if block else '', re.S):
                v = v.strip()
                value = int(v) if re.fullmatch(r'-?\d+', v) else v.strip("'\"")
                tk = re.match(r"\$t\('([^']+)'", txt)
                opts.append({'value': value, 'textKey': tk.group(1)} if tk else {'value': value, 'text': txt.strip().strip("'\"")})
            if opts:
                field['options'] = opts
            else:
                field['kind'] = {'integer': 'int', 'number': 'num'}.get(s.get('type'), 'string')
        if not any(i.get('path') == p for i in items):
            items.append(field)
    out.append({'key': key, 'title': title, 'subtitle': subtitle, 'items': items})

json.dump({'version': open(os.path.join(src, 'server/package.json')).read().split('"version": "')[1].split('"')[0],
           'sections': out}, open(sys.stdout.fileno(), 'w'), indent=1, ensure_ascii=False)
