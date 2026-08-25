import io, re, sys, time, urllib.request

target = sys.argv[1]  # run id to watch for
url = "https://github.com/quantdale/FocusTube/actions/workflows/ios-ci.yml?query=is%3Acompleted"
deadline = time.time() + 28 * 60
while time.time() < deadline:
    req = urllib.request.Request(url, headers={"User-Agent": "ci-watch"})
    h = urllib.request.urlopen(req).read().decode("utf-8", "ignore")
    ids = re.findall(r"/actions/runs/(\d+)", h)
    labels = re.findall(r'aria-label="(completed successfully|failed)[^"]*Run (\d+) of iOS CI[^"]*"', h)
    if target in ids:
        for status, num in labels:
            print("RESULT", status, "run", num, flush=True)
        break
    print("pending...", flush=True)
    time.sleep(120)
else:
    print("WATCH_TIMEOUT", flush=True)
