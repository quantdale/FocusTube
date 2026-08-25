import io, re, sys

h = io.open(sys.argv[1], encoding="utf-8", errors="ignore").read()
pat = r'aria-label="(completed successfully|completed unsuccessfully|failed|in_progress|in progress)[^"]*"'
for m in list(re.finditer(pat, h, re.I))[:12]:
    print(repr(m.group(0)[:200]))
print("---run-ids---")
for m in list(re.finditer(r"/actions/runs/(\d+)", h))[:10]:
    print(m.group(1))
