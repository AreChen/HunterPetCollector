"""Extract NPC translations for this addon's IDs from a QuestieDB baked TOC.

Usage: python scripts/extract_questiedb_locales.py path/to/QuestieDB_Forever.toc
Requires cbor2. QuestieDB and contributors: https://github.com/Questie/QuestieDB
"""
import base64
import re
import sys
import zlib
from pathlib import Path
import cbor2

root = Path(__file__).resolve().parents[1]
npc_ids = set()
for dataset in root.glob('Data/Data_*.lua'):
    npc_ids.update(int(n) for n in re.findall(r'\{(\d+),"[^"\n]+",\d+,\d+,\d+,"', dataset.read_text(encoding='utf-8-sig')))
keys = ('X-Npc-IDS', 'X-l10n-zhCN-Npc', 'X-l10n-zhTW-Npc')
values = {}
with Path(sys.argv[1]).open(encoding='utf-8-sig') as toc:
    for line in toc:
        if not line.startswith('## X-'):
            continue
        key, sep, value = line[3:].rstrip('\r\n').partition(': ')
        if sep and any(key == k or key.startswith(k + '-') for k in keys):
            values[key] = value

def decode(key):
    data = values[key]
    if data.startswith('~'):
        data = ''.join(values[f'{key}-{i}'] for i in range(1, int(data.strip('~')) + 1))
    return cbor2.loads(zlib.decompress(base64.b64decode(data)))

ids = decode(keys[0])
for locale in ('zhCN', 'zhTW'):
    names = decode('X-l10n-' + locale + '-Npc')[0]
    rows = []
    for npc, name in zip(ids, names):
        if npc in npc_ids and name:
            if isinstance(name, bytes): name = name.decode('utf-8')
            name = name.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ')
            rows.append(f'    [{npc}] = "{name}",')
    output = '-- NPC names extracted from QuestieDB; see README for attribution.\nlocal _, ns = ...\n'
    output += f'if GetLocale() ~= "{locale}" then return end\nns.NPCNames = {{\n' + '\n'.join(rows) + '\n}\n'
    (root / f'Locale/NPC_{locale}.lua').write_text(output, encoding='utf-8')
    print(f'{locale}: {len(rows)} translated NPCs of {len(npc_ids)} IDs in addon datasets')
