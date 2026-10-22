#!/usr/bin/env python3
"""Refresh first-party README counters from GitHub; retain valid data on API failure."""
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = "leonardob8777-bit/Eagle"


def api(path, *, paginate=False):
    args = ["gh", "api"]
    if paginate:
        args += ["--paginate", "--slurp"]
    result = subprocess.run(args + [path], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def count(value):
    if type(value) is not int or value < 0:
        raise ValueError("GitHub returned an invalid counter; existing badges retained")
    return value


def collect_stats(repository, release_pages):
    stars = count(repository["stargazers_count"])
    if not isinstance(release_pages, list) or not release_pages:
        raise ValueError("Missing release pages; existing badges retained")
    downloads = 0
    for page in release_pages:
        if not isinstance(page, list):
            raise ValueError("Invalid release page; existing badges retained")
        for release in page:
            if release["draft"]:
                continue
            for asset in release["assets"]:
                if asset["name"].lower().endswith(".ipa"):
                    downloads += count(asset["download_count"])
    return {"ipa_downloads": downloads, "stars": stars}


def badge(label, number, color, left):
    value = f"{number:,}"
    right = max(45, len(value) * 9 + 24)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{left + right}" height="28" role="img" aria-label="{label}: {value}">
  <title>{label}: {value}</title>
  <rect width="{left}" height="28" fill="#444"/>
  <rect x="{left}" width="{right}" height="28" fill="{color}"/>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,DejaVu Sans,sans-serif" font-size="10" letter-spacing="1">
    <text x="{left / 2:g}" y="18">{label}</text>
    <text x="{left + right / 2:g}" y="18" font-weight="bold">{value}</text>
  </g>
</svg>
'''


def render_readme(readme, stats, checked_at):
    for name, key in (("downloads", "ipa_downloads"), ("stars", "stars")):
        pattern = rf"docs/badges/{name}\.svg(?:\?v=[0-9]+)?"
        readme, matches = re.subn(pattern, f"docs/badges/{name}.svg?v={stats[key]}", readme)
        if matches != 1:
            raise ValueError(f"Expected one {name} badge in README")
    note = (f"  <sub>IPA downloads and stars refresh automatically about every 15 minutes. "
            f"Last change: {checked_at}. Counts include IPA files only.</sub>")
    readme, matches = re.subn(
        r"^  <sub>(?:Counts checked |IPA downloads and stars refresh automatically )[^\n]*</sub>$",
        note, readme, flags=re.MULTILINE,
    )
    if matches != 1:
        raise ValueError("Expected one counter status note in README")
    return readme


def update(root, stats, now):
    stats = {key: count(stats[key]) for key in ("ipa_downloads", "stars")}
    folder = root / "docs/badges"
    stats_path = folder / "stats.json"
    previous = json.loads(stats_path.read_text()) if stats_path.exists() else {}
    unchanged = all(previous.get(key) == value for key, value in stats.items())
    checked_at = previous["updated_at"] if unchanged else now
    # Construct every output before writing, so API/format failures cannot replace counts.
    outputs = {
        folder / "downloads.svg": badge("IPA DOWNLOADS", stats["ipa_downloads"], "#0891b2", 138),
        folder / "stars.svg": badge("STARS", stats["stars"], "#d97706", 68),
        stats_path: json.dumps({**stats, "updated_at": checked_at}, indent=2) + "\n",
        root / "README.md": render_readme((root / "README.md").read_text(), stats, checked_at),
    }
    for path, content in outputs.items():
        if not path.exists() or path.read_text() != content:
            path.write_text(content)
    return not unchanged


def main():
    # Fetch both complete responses before touching any file. No token is stored in output.
    repository = api(f"repos/{REPO}")
    pages = api(f"repos/{REPO}/releases?per_page=100", paginate=True)
    stats = collect_stats(repository, pages)
    changed = update(ROOT, stats, datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
    print(f"IPA downloads: {stats['ipa_downloads']}; stars: {stats['stars']}; changed: {changed}")


if __name__ == "__main__":
    main()
