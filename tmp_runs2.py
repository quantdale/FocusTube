import json

d = json.load(open('runs-new.json', encoding='utf-8'))
for r in d.get('workflow_runs', []):
    print(r['id'], r['name'], r['status'], r['conclusion'], r['head_sha'][:7])
print('n=', d.get('total_count'))
