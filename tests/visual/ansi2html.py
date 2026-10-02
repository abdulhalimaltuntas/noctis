#!/usr/bin/env python3
"""tmux `capture-pane -e -p` çıktısını (SGR renk kodlarıyla) HTML'e çevirir.
Ekran görüntüleri gerçek terminal içeriğinden üretilir; tasarlanmış mockup değildir.
Kullanım: ansi2html.py girdi.ansi çıktı.html "Başlık"
"""
import html
import re
import sys

BASE16 = [
    "#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
    "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff",
]


def xterm256(n: int) -> str:
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        levels = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (levels[n // 36], levels[(n // 6) % 6], levels[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


SGR = re.compile(r"\x1b\[([0-9;:]*)m")


def convert(text: str, default_fg: str, default_bg: str) -> str:
    out_lines = []
    state = {"fg": None, "bg": None, "bold": False, "italic": False, "ul": False, "rev": False, "dim": False, "strike": False}
    for line in text.split("\n"):
        pos = 0
        spans = []
        for m in SGR.finditer(line):
            if m.start() > pos:
                spans.append((dict(state), line[pos:m.start()]))
            params = m.group(1).replace(":", ";").split(";") if m.group(1) else ["0"]
            i = 0
            while i < len(params):
                p = int(params[i]) if params[i] else 0
                if p == 0:
                    state.update(fg=None, bg=None, bold=False, italic=False, ul=False, rev=False, dim=False, strike=False)
                elif p == 1:
                    state["bold"] = True
                elif p == 2:
                    state["dim"] = True
                elif p == 3:
                    state["italic"] = True
                elif p == 4:
                    state["ul"] = True
                    if i + 1 < len(params) and m.group(1).find(":") >= 0:
                        i += 1
                elif p == 7:
                    state["rev"] = True
                elif p == 9:
                    state["strike"] = True
                elif p == 22:
                    state["bold"] = state["dim"] = False
                elif p == 23:
                    state["italic"] = False
                elif p == 24:
                    state["ul"] = False
                elif p == 27:
                    state["rev"] = False
                elif p == 29:
                    state["strike"] = False
                elif 30 <= p <= 37:
                    state["fg"] = BASE16[p - 30]
                elif 90 <= p <= 97:
                    state["fg"] = BASE16[p - 90 + 8]
                elif 40 <= p <= 47:
                    state["bg"] = BASE16[p - 40]
                elif 100 <= p <= 107:
                    state["bg"] = BASE16[p - 100 + 8]
                elif p in (38, 48, 58):
                    key = {38: "fg", 48: "bg", 58: None}[p]
                    if i + 1 < len(params) and params[i + 1] == "5":
                        if key:
                            state[key] = xterm256(int(params[i + 2]))
                        i += 2
                    elif i + 1 < len(params) and params[i + 1] == "2":
                        if key:
                            r, g, b = (int(x) for x in params[i + 2:i + 5])
                            state[key] = "#%02x%02x%02x" % (r, g, b)
                        i += 4
                elif p == 39:
                    state["fg"] = None
                elif p == 49:
                    state["bg"] = None
                i += 1
            pos = m.end()
        if pos < len(line):
            spans.append((dict(state), line[pos:]))
        parts = []
        for st, txt in spans:
            fg = st["fg"] or default_fg
            bg = st["bg"] or default_bg
            if st["rev"]:
                fg, bg = bg, fg
            css = [f"color:{fg}", f"background:{bg}"]
            if st["bold"]:
                css.append("font-weight:700")
            if st["italic"]:
                css.append("font-style:italic")
            if st["dim"]:
                css.append("opacity:.7")
            deco = []
            if st["ul"]:
                deco.append("underline")
            if st["strike"]:
                deco.append("line-through")
            if deco:
                css.append("text-decoration:" + " ".join(deco))
            parts.append(f'<span style="{";".join(css)}">{html.escape(txt)}</span>')
        out_lines.append("<div>" + "".join(parts) + "</div>")
    # white-space:pre içinde div'ler arası "\n" fazladan satır üretir
    return "".join(out_lines)


def main() -> None:
    src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "NOCTIS"
    default_bg = sys.argv[4] if len(sys.argv) > 4 else "#0b1020"
    default_fg = sys.argv[5] if len(sys.argv) > 5 else "#dce5f5"
    fonts = sys.argv[6] if len(sys.argv) > 6 else ""
    with open(src, encoding="utf-8", errors="replace") as f:
        text = f.read().rstrip("\n")
    body = convert(text, default_fg, default_bg)
    page = f"""<!doctype html><html><head><meta charset="utf-8"><title>{html.escape(title)}</title>
<style>
@font-face {{ font-family: 'NerdSym'; src: url('file://{fonts}/SymbolsNerdFontMono-Regular.ttf'); }}
html, body {{ margin:0; background:{default_bg}; }}
#term {{ display:inline-block; padding:0; font-family:'DejaVu Sans Mono','NerdSym',monospace;
  font-size:14px; line-height:17px; white-space:pre; background:{default_bg}; color:{default_fg};
  font-variant-ligatures:none; }}
#term div {{ height:17px; }}
#term span {{ display:inline-block; height:17px; vertical-align:top; }}
</style></head><body><div id="term">{body}</div></body></html>"""
    with open(dst, "w", encoding="utf-8") as f:
        f.write(page)


if __name__ == "__main__":
    main()
