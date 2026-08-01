#!/usr/bin/env python3
# Injects the custom/capslock module into any waybar config + stylesheet,
# so the caps lock pill works across every theme (current and future).
# Usage: capslock.py <config.jsonc> [style.css]
# Prints two lines: patched-config-path, patched-style-path.

import json
import os
import sys

MODULE = "custom/capslock"

MODULE_DEF = {
    "exec": "~/.config/waybar/scripts/capslock.sh",
    "return-type": "json",
    "interval": 0.3,
    "tooltip": False,
}

CSS_RULE = """
#custom-capslock {
    padding: 1px 12px 0;
    margin: 6px 4px;
    border-radius: 18px;
    background: rgba(240, 120, 120, 0.22);
    color: #f38ba8;
    font-weight: 700;
    transition: background-color 0.1s ease, color 0.1s ease;
}
#custom-capslock.off {
    padding: 0;
    margin: 0;
    background: transparent;
    color: transparent;
}
"""


def strip_comments(text):
    out = []
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(nxt)
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif c == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and nxt == "*":
            i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                i += 1
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def load_jsonc(path):
    text = strip_comments(open(path, encoding="utf-8").read())
    text = text.lstrip("\ufeff").replace("\x00", "")
    text = __import__("re").sub(r",\s*([}\]])", r"\1", text)
    obj, _ = json.JSONDecoder().raw_decode(text)
    return obj


def main():
    if len(sys.argv) < 2:
        sys.exit(2)
    cfg_path = os.path.expanduser(sys.argv[1])
    style_path = sys.argv[2]
    if style_path:
        style_path = os.path.expanduser(style_path)
    base = os.path.splitext(os.path.basename(cfg_path))[0]
    rundir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")

    try:
        data = load_jsonc(cfg_path)
    except Exception as e:
        print(f"capslock.py: could not parse {cfg_path}: {e}", file=sys.stderr)
        print(cfg_path)
        print(style_path or "")
        sys.exit(0)

    if MODULE not in data:
        data[MODULE] = MODULE_DEF

    placed = False
    for key in ("modules-right", "modules-left", "modules-center"):
        if isinstance(data.get(key), list):
            if MODULE not in data[key]:
                data[key].insert(0, MODULE)
            placed = True
            break
    if not placed:
        data["modules-right"] = [MODULE]

    out_cfg = os.path.join(rundir, f"{base}.capslock.json")
    with open(out_cfg, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    out_style = style_path or ""
    if style_path and os.path.isfile(style_path):
        src = open(style_path, encoding="utf-8").read()
        if "#custom-capslock" not in src:
            out_style = os.path.join(
                os.path.dirname(style_path),
                ".capslock-" + os.path.basename(style_path),
            )
            with open(out_style, "w", encoding="utf-8") as f:
                f.write(src)
                if not src.endswith("\n"):
                    f.write("\n")
                f.write(CSS_RULE)

    print(out_cfg)
    print(out_style)


if __name__ == "__main__":
    main()
