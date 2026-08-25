import json

d = json.load(open('ci-new.json', encoding='utf-8'))
for r in d.get('check_runs', []):
    print(r['id'], r['name'], r['status'], r['conclusion'])
print('total', d.get('total_count'))
