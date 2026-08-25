import json

d = json.load(open('ci-ann-now.json', encoding='utf-8'))
out = open('ann-now.txt', 'w', encoding='utf-8')
for a in d:
    out.write('=' * 14 + ' ' + a['annotation_level'] + ' line ' + str(a['start_line']) + ' ' + '=' * 14 + '\n')
    out.write(a['message'][:2800] + '\n\n')
out.close()
print('written', len(d))
