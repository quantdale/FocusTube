import io, re, sys

h = io.open(sys.argv[1], encoding="utf-8", errors="ignore").read()
print("len", len(h))
# GitHub commit pages embed check status in titles/aria-labels like
# 'iOS CI: Success' / 'iOS CI: Failure' and summary text 'All checks passed' etc.
for p in [r"iOS CI[^<]{0,40}", r"All checks \w+", r"checks? (passed|failed)", r"aria-label=\"[^\"]*check[^\"]*\"",
          r"title=\"[^\"]*(Success|Failure|Pending)[^\"]*\""]:
    for m in list(re.finditer(p, h, re.I))[:6]:
        print(repr(m.group(0)[:120]))
