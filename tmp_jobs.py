import json
import sys

d = json.load(open('ci-jobs-now.json', encoding='utf-8'))
j = d['jobs'][0]
print('job', j['id'], j['conclusion'])
for s in j['steps']:
    if s['conclusion'] not in ('success', 'skipped', None):
        print('STEP-FAIL:', s['name'], s['conclusion'])
