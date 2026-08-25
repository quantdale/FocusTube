import io, json, sys

d = json.load(io.open(sys.argv[1], encoding="utf-8"))
for a in d:
    lvl = a.get("annotation_level")
    msg = a.get("message", "")
    print("=====", lvl)
    print(msg[:2500])
