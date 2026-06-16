#!/usr/bin/env python3
"""cc-status full — 3-line boxed dashboard (proper ANSI width handling)."""
import os, sys, json, subprocess
from datetime import datetime

CC_KIT = os.environ.get("CC_KIT_DIR") or "__CC_KIT_DIR__"
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

# Context window from stdin
ctx_pct = ""
try:
    raw = sys.stdin.read()
    if raw:
        data = json.loads(raw)
        ctx_pct = str(int(float(data.get("remaining_percentage", 0))))
except: pass

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

# ── Build lines (no ANSI inside the content width calculation) ──────
now = datetime.now().strftime("%H:%M")

# Line 1: Provider + model | cost + balance | time
l1_left  = f"◆ {label}  {D}{model}{R}"
l1_right = f"{YL}{cur}{cost_s} session{R}  {bal_c}{cur}{bal if bal else '—'} balance{R}  {D}{now}{R}"
# Calculate visible width of right side (strip ANSI for measurement)
import re
def vis(s): return len(re.sub(r'\033\[[0-9;]*m', '', s))
l1_r_vis = vis(l1_right)
l1_l_vis = vis(l1_left)
pad1 = max(1, 76 - l1_l_vis - l1_r_vis)
l1 = f"{GY}│{R}  {l1_left}{' ' * pad1}{l1_right}  {GY}│{R}"

# Line 2: context bar + token stats
l2_left = f"context  {ctx_bar}" if ctx_bar else "context"
l2_right = f"{BL}⬇{fmt(in_tok)} input{R}  {GR}⬆{fmt(out_tok)} output{R}  {B}{fmt(total)} total{R}"
l2_r_vis = vis(l2_right)
l2_l_vis = vis(l2_left)
pad2 = max(1, 76 - l2_l_vis - l2_r_vis)
l2 = f"{GY}│{R}  {l2_left}{' ' * pad2}{l2_right}  {GY}│{R}"

# Line 3: cache hit + cost detail
l3_left  = f"cache    {MG}↯{hit_s}% hit{R}  {YL}{cur}{cost_s} session{R}  {YL}{cur}{cost_g} tracked{R}"
l3_right = f"{D}pricing: ¥2/M in · ¥0.2/M hit · ¥8/M out{R}"
l3_r_vis = vis(l3_right)
l3_l_vis = vis(l3_left)
pad3 = max(1, 76 - l3_l_vis - l3_r_vis)
l3 = f"{GY}│{R}  {l3_left}{' ' * pad3}{l3_right}  {GY}│{R}"

# Box lines
hline = "─" * 78
top = f"{GY}╭{hline}╮{R}"
sep = f"{GY}├{hline}┤{R}"
bot = f"{GY}╰{hline}╯{R}"

print(f"{top}\n{l1}\n{sep}\n{l2}\n{sep}\n{l3}\n{bot}")
