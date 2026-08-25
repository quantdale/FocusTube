import io, json, sys, time

mode = sys.argv[1]
if mode == "rate":
    d = json.load(io.open("rl.json", encoding="utf-8"))
    c = d["resources"]["core"]
    now = int(time.time())
    print("remaining", c["remaining"], "reset_in_s", c["reset"] - now)
