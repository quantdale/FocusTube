import json

d = json.load(open('ci-ann-now.json', encoding='utf-8'))
out = open('ann-full.txt', 'w', encoding='utf-8')
for a in d:
    msg = a['message']
    if 'testCancelFreesSlot' in msg or 'NSCocoaErrorDomain' in msg:
        out.write('FULL MESSAGE:\n')
        out.write(msg + '\n\nRAW:\n')
        out.write(json.dumps(a, indent=1)[:6000] + '\n\n')
out.close()
print('done')
