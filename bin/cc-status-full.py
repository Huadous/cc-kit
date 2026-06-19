#!/usr/bin/env python3
"""cc-status full — 3-line boxed dashboard (proper ANSI width handling)."""
import os, sys, json, subprocess
from datetime import datetime

# Self-locate: this script lives at <root>/bin/, so the install root is the parent.
# Falls back to $CC_KIT_DIR env var if set so the user's dev override still works.
_HERE = os.path.dirname(os.path.abspath(__file__))
CC_KIT = os.environ.get("CC_KIT_DIR") or os.path.dirname(_HERE)
MONITOR = os.path.join(CC_KIT, "modules/monitor.sh")

def run_monitor(fn):
    """Call a monitor function and return its stdout."""
    try:
        out = subprocess.check_output(
            ["bash", "-c", f"source {MONITOR} 2>/dev/null; {fn}"],
            stderr=subprocess.DEVNULL, text=True, timeout=5
        ).strip()
        return out
    except Exception:
        return ""

def fmt(n):
    try: n = int(n)
    except: return str(n)
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1000: return f"{n/1000:.1f}k"
    return str(n)

# ── Gather data ─────────────────────────────────────────────────────
label  = run_monitor("monitor_provider_label") or "CC"
model  = os.getenv("ANTHROPIC_MODEL", "unknown")
stats  = run_monitor("monitor_stats_line") or "0 0 0 0 0"
parts  = stats.split()
in_tok = int(parts[0]) if len(parts) > 0 else 0
out_tok= int(parts[1]) if len(parts) > 1 else 0
cr_tok = int(parts[2]) if len(parts) > 2 else 0
total  = in_tok + out_tok

hit_s  = run_monitor("monitor_hit_rate") or ""
hit_g  = run_monitor("monitor_global_hit_rate") or ""
cost_s = run_monitor("monitor_session_cost") or "0.00"
cost_g = run_monitor("monitor_global_cost") or "0.00"
cur    = run_monitor("monitor_currency") or "$"

bal = ""
bal_file = os.path.join(CC_KIT, "data", ".balance_cache")
if os.path.exists(bal_file):
    try:
        with open(bal_file) as f: bal = f.read().strip().split()[0]
    except: pass

# Context window from stdin. Claude Code's statusLine payload nests the
# context info under a `context_window` key (with `total_tokens`,
# `used_percentage`, `remaining_percentage`). Older payloads (or the
# user's manual test scripts) may pass it at the top level — try both
# locations before defaulting to 0.
ctx_pct = ""
try:
    raw = sys.stdin.read()
    if raw:
        data = json.loads(raw)
        cw = data.get("context_window") or {}
        # Try nested first (Claude Code actual format), then top-level (legacy).
        remaining = cw.get("remaining_percentage")
        if remaining is None:
            remaining = data.get("remaining_percentage")
        if remaining is not None:
            ctx_pct = str(int(float(remaining)))
except Exception:
    pass

# ── ANSI ────────────────────────────────────────────────────────────
R  = "\033[0m"; B = "\033[1m"; D = "\033[2m"
BL = "\033[34m"; GR = "\033[32m"; CY = "\033[36m"
MG = "\033[35m"; YL = "\033[33m"; RD = "\033[31m"; GY = "\033[90m"

# ── Context bar (30-seg gradient) ───────────────────────────────────
ctx_bar = ""
if ctx_pct and ctx_pct != "100":
    used = 100 - int(ctx_pct)
    blocks = " ▁▂▃▄▅▆▇█"
    bar = ""
    for i in range(30):
        seg_s = i * 100 // 30
        seg_e = (i + 1) * 100 // 30
        if used >= seg_e: lv = 8
        elif used <= seg_s: lv = 0
        else: lv = max(1, (used - seg_s) * 8 * 30 // 100 + 1)
        bar += blocks[min(lv, 8)]
    if used > 75: c = RD
    elif used > 50: c = YL
    else: c = GR
    ctx_bar = f"{c}{bar}{R} {ctx_pct}%"

# ── Balance color ───────────────────────────────────────────────────
bal_c = GR
if bal:
    try:
        n = float(bal)
        if n < 10: bal_c = RD
        elif n < 30: bal_c = YL
    except: pass

# Check if the current provider has an API key (affects balance fallback text).
def _has_api_key():
    """Return True if the current provider's API key is set."""
    provider_env = os.path.join(CC_KIT, "data", "provider.env")
    secrets_env = os.path.join(CC_KIT, "data", "secrets.env")
    base_url = os.getenv("ANTHROPIC_BASE_URL", "")
    # ANTHROPIC_AUTH_TOKEN set directly in env
    if os.getenv("ANTHROPIC_AUTH_TOKEN", ""):
        return True
    # Read secrets.env for per-provider keys
    try:
        with open(secrets_env) as f:
            content = f.read()
        if "deepseek" in base_url:
            if 'DEEPSEEK_API_KEY="' in content and 'DEEPSEEK_API_KEY=""' not in content:
                return True
        elif "minimax" in base_url:
            if 'MINIMAX_API_KEY="' in content and 'MINIMAX_API_KEY=""' not in content:
                return True
        elif "bigmodel" in base_url or "z.ai" in base_url:
            if 'ZHIPU_API_KEY="' in content and 'ZHIPU_API_KEY=""' not in content:
                return True
    except Exception:
        pass
    return False

# ── Build lines (no ANSI inside the content width calculation) ──────
now = datetime.now().strftime("%H:%M")

# Box geometry: outer width = 92 visible chars (so 90 dashes between
# corners). Inner content area = 90 - 4 (margins) = 86 chars between
# the `│` borders. Earlier versions used 78/74 which was too narrow for
# the verbose pricing + tracked-cost line; everything overflowed.
INNER_W = 86

# Width helper: visible width = total bytes minus ANSI escape codes.
import re
def vis(s): return len(re.sub(r'\033\[[0-9;]*m', '', s))

# If a side still overflows after composing, truncate the right side
# (visually) so the line never breaks the box. Ellipsize with "…".
def fit_right(right_str, max_w):
    if vis(right_str) <= max_w:
        return right_str
    # Walk characters, dropping ANSI codes from the count and stopping
    # when we run out of room. Append an ellipsis if we cut anything.
    out, used = [], 0
    i = 0
    while i < len(right_str):
        m = re.match(r'\033\[[0-9;]*m', right_str[i:])
        if m:
            out.append(m.group(0))
            i += len(m.group(0))
            continue
        if used + 1 > max_w - 1:   # reserve 1 char for ellipsis
            out.append('…')
            used += 1
            break
        out.append(right_str[i])
        used += 1
        i += 1
    return ''.join(out) + R  # ensure reset code at end

def make_line(left, right):
    """Compose a left|right line, padded to INNER_W, with right truncated
    if needed. Returns a string ready to print."""
    l_vis, r_vis = vis(left), vis(right)
    avail_r = INNER_W - l_vis - 1   # at least 1 space between L and R
    if r_vis > avail_r:
        right = fit_right(right, avail_r)
        r_vis = vis(right)
    pad = max(1, INNER_W - l_vis - r_vis)
    return f"{GY}│{R}  {left}{' ' * pad}{right}  {GY}│{R}"

# Line 1: Provider + model | cost + balance | time
l1_left  = f"◆ {label}  {D}{model}{R}"
bal_fb = bal if bal else ('—' if _has_api_key() else 'no key')
l1_right = f"{YL}{cur}{cost_s} session{R}  {bal_c}{cur}{bal_fb} balance{R}  {D}{now}{R}"
l1 = make_line(l1_left, l1_right)

# Line 2: context bar + token stats. Shrink ctx bar to 20 chars if it
# would otherwise push past INNER_W.
l2_left = f"context  {ctx_bar}" if ctx_bar else "context"
l2_right = f"{BL}⬇{fmt(in_tok)} input{R}  {GR}⬆{fmt(out_tok)} output{R}  {B}{fmt(total)} total{R}"
if vis(l2_left) + vis(l2_right) + 1 > INNER_W:
    # Rebuild ctx_bar with 20 segments instead of 30 (preserves color).
    ctx_bar_short = ""
    if ctx_pct and ctx_pct != "100":
        used = 100 - int(ctx_pct)
        blocks = " ▁▂▃▄▅▆▇█"
        bar = ""
        for i in range(20):
            seg_s = i * 100 // 20
            seg_e = (i + 1) * 100 // 20
            if used >= seg_e: lv = 8
            elif used <= seg_s: lv = 0
            else: lv = max(1, (used - seg_s) * 8 * 20 // 100 + 1)
            bar += blocks[min(lv, 8)]
        if used > 75: c = RD
        elif used > 50: c = YL
        else: c = GR
        ctx_bar_short = f"{c}{bar}{R} {ctx_pct}%"
    l2_left = f"context  {ctx_bar_short}" if ctx_bar_short else "context"
l2 = make_line(l2_left, l2_right)

# Line 3: cache hit + cost detail. Concise pricing string fits cleanly.
l3_left  = f"cache    {MG}↯{hit_s}% hit{R}  {YL}{cur}{cost_s} session{R}  {YL}{cur}{cost_g} tracked{R}"
l3_right = f"{D}¥2/M in · ¥0.2/M hit · ¥8/M out{R}"
l3 = make_line(l3_left, l3_right)

# Box borders (92 visible chars wide: ╭ + 90 dashes + ╮)
hline = "─" * (INNER_W + 4)
top = f"{GY}╭{hline}╮{R}"
sep = f"{GY}├{hline}┤{R}"
bot = f"{GY}╰{hline}╯{R}"

print(f"{top}\n{l1}\n{sep}\n{l2}\n{sep}\n{l3}\n{bot}")
