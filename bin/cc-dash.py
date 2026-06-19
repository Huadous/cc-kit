#!/usr/bin/env python3
"""cc-dash — Standalone real-time dashboard for cc-kit token usage.
Run in a separate terminal: cc-dash
Uses the Blessed library for professional terminal rendering.
"""

import os
import sys
import time
from datetime import datetime

try:
    from blessed import Terminal
except ImportError:
    print("Please install blessed: pip install blessed")
    sys.exit(1)

# Self-locate: this script lives at <root>/bin/, so the install root is the parent.
# Falls back to $CC_KIT_DIR env var if set so the user's dev override still works.
_HERE = os.path.dirname(os.path.abspath(__file__))
CC_KIT_DIR = os.environ.get("CC_KIT_DIR") or os.path.dirname(_HERE)
DATA_DIR = os.path.join(CC_KIT_DIR, "data")
USAGE_FILE = os.path.join(DATA_DIR, "usage.db")

term = Terminal()


def get_provider_label():
    """Get current provider short label."""
    provider_env = os.path.join(DATA_DIR, "provider.env")
    if not os.path.exists(provider_env):
        return "AN"
    with open(provider_env) as f:
        content = f.read()
    if "deepseek" in content:
        if "flash" in content:
            return "DS-flash"
        return "DS-pro"
    if "minimax" in content:
        if "M3" in content:
            return "MM-m3"
        if "highspeed" in content:
            return "MM-hs"
        return "MM"
    if "bigmodel" in content or "z.ai" in content:
        if "glm-5.1" in content:
            return "GLM-5.1"
        if "glm-4.7-flash" in content:
            return "GLM-flash"
        if "glm-4.7" in content:
            return "GLM-4.7"
        return "GLM"
    return "AN"


def fmt_num(n):
    """Format number: 12345 -> 12.3k"""
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1000:
        return f"{n/1000:.1f}k"
    return str(n)


def read_usage():
    """Parse usage.db and return summary dict."""
    if not os.path.exists(USAGE_FILE):
        return {}
    summary = {}
    with open(USAGE_FILE) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 7:
                continue
            provider = parts[1]
            inp = int(parts[3])
            out = int(parts[4])
            cr = int(parts[6])
            if provider not in summary:
                summary[provider] = {"input": 0, "output": 0, "cache": 0, "sessions": 0}
            summary[provider]["input"] += inp
            summary[provider]["output"] += out
            summary[provider]["cache"] += cr
            summary[provider]["sessions"] += 1
    return summary


def get_current_tokens():
    """Get current session token counts from JSONL."""
    try:
        cwd = os.getcwd()
        project_dir = os.path.expanduser(
            f"~/.claude/projects/{cwd.replace('/', '-')}"
        )
        if not os.path.isdir(project_dir):
            return 0, 0, 0
        files = sorted(
            [f for f in os.listdir(project_dir) if f.endswith(".jsonl")],
            key=lambda x: os.path.getmtime(os.path.join(project_dir, x)),
            reverse=True,
        )
        if not files:
            return 0, 0, 0
        latest = os.path.join(project_dir, files[0])
        inp = out = cr = 0
        import re
        with open(latest) as f:
            for line in f:
                for m in re.finditer(r'"input_tokens":(\d+)', line):
                    inp += int(m.group(1))
                for m in re.finditer(r'"output_tokens":(\d+)', line):
                    out += int(m.group(1))
                for m in re.finditer(r'"cache_read_input_tokens":(\d+)', line):
                    cr += int(m.group(1))
        return inp, out, cr
    except Exception:
        return 0, 0, 0


def draw_dashboard():
    """Render the dashboard."""
    label = get_provider_label()
    inp, out, cr = get_current_tokens()
    history = read_usage()

    # Layout
    print(term.home + term.clear)

    # Header
    with term.location(0, 0):
        print(term.cyan + term.bold + "  ◈  CC-KIT DASHBOARD" + term.normal)
        print(term.dim + "─" * term.width + term.normal)

    y = 3

    # Current session
    with term.location(2, y):
        print(term.bold + "Current Session" + term.normal)
    y += 2
    with term.location(4, y):
        print(f"{term.dim}Provider:{term.normal} {term.bold}{label}{term.normal}")
    y += 1

    # Token bars
    max_val = max(inp, out, cr, 1)
    bar_width = 30

    def draw_bar(y, name, value, color):
        filled = int(value * bar_width / max_val)
        bar = "█" * filled + "░" * (bar_width - filled)
        with term.location(4, y):
            print(f"{name:<8} {color}{bar}{term.normal} {fmt_num(value):>8}")

    draw_bar(y, "Input", inp, term.blue)
    y += 1
    draw_bar(y, "Output", out, term.green)
    y += 1
    draw_bar(y, "Cache", cr, term.yellow)
    y += 2

    with term.location(4, y):
        print(f"{term.dim}Total:{term.normal} {term.bold}{fmt_num(inp + out)}{term.normal}")
    y += 2

    # History
    if history:
        print(term.move(y, 0) + term.dim + "─" * term.width + term.normal)
        y += 1
        with term.location(2, y):
            print(term.bold + "History" + term.normal)
        y += 1
        with term.location(4, y):
            print(f"{term.dim}{'Provider':<12} {'Sessions':>8} {'Input':>10} {'Output':>10}{term.normal}")
        y += 1
        for provider in ["deepseek", "minimax", "glm", "anthropic"]:
            if provider in history:
                h = history[provider]
                with term.location(4, y):
                    print(
                        f"{provider:<12} {h['sessions']:>8} "
                        f"{fmt_num(h['input']):>10} {fmt_num(h['output']):>10}"
                    )
                y += 1

    # Footer
    with term.location(0, term.height - 1):
        print(term.dim + "─" * term.width + term.normal)
    with term.location(2, term.height - 1):
        print(f"{term.dim}Ctrl+C to exit │ Updated: {datetime.now().strftime('%H:%M:%S')}{term.normal}")


def main():
    with term.fullscreen(), term.cbreak(), term.hidden_cursor():
        try:
            while True:
                draw_dashboard()
                time.sleep(3)
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
