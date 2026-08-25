import json

d = json.load(open('run-now.json', encoding='utf-8'))
print(d['status'], d['conclusion'])
