import json, sys, time, urllib.request

run_id = sys.argv[1]
url = f"https://api.github.com/repos/quantdale/FocusTube/actions/runs/{run_id}"
deadline = time.time() + 32 * 60
while True:
    with urllib.request.urlopen(url) as r:
        d = json.load(r)
    print(d["status"], d["conclusion"], flush=True)
    if d["status"] == "completed":
        break
    if time.time() > deadline:
        print("POLL_TIMEOUT", flush=True)
        break
    time.sleep(60)
