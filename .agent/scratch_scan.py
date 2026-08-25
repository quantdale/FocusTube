import io, sys

path = sys.argv[1] if len(sys.argv) > 1 else "runpage.html"
h = io.open(path, encoding="utf-8", errors="ignore").read()
print("len", len(h))
pats = ['"conclusion"', '"failure"', '"success"', "Failure", "Success",
        "cancelled", "Timed out", "unit.exit", "ui.exit", "Gate", "Annotations"]
for p in pats:
    i = h.find(p)
    print(p, "->", i)
    if i > 0:
        print("   ", repr(h[max(0, i - 100):i + 160]))
