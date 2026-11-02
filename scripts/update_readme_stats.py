#!/usr/bin/env python3
"""Refresh the README stats card and download button from the live GitHub API.

Writes docs/badges/stats-{dark,light}.svg and docs/badges/download.svg, then
rewrites the README block between the eagle-stats markers. Nothing is written
when the release, download and star counts are unchanged, so the scheduled
workflow only commits real changes.

Set GITHUB_TOKEN to avoid the anonymous API rate limit.
"""
from datetime import datetime, timezone
from html import escape
from pathlib import Path
import argparse
import json
import os
import re
import sys
import urllib.request

REPO = os.environ.get('EAGLE_REPO', 'leonardob8777-bit/Eagle')
API = f'https://api.github.com/repos/{REPO}'
WEB = f'https://github.com/{REPO}'
ROOT = Path(__file__).resolve().parents[1]
BADGES = ROOT / 'docs/badges'
README = ROOT / 'README.md'
STATE = BADGES / 'stats.json'
START = '<!-- eagle-stats:start -->'
END = '<!-- eagle-stats:end -->'

FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Helvetica, Arial, sans-serif"
# Matches EagleSpectrumStyle.colors in lara/views/new/EagleRainbowLoadingView.swift.
SPECTRUM = ['#22d3ee', '#3b82f6', '#8b5cf6', '#ec4899', '#ef4444', '#f97316', '#eab308', '#22c55e', '#22d3ee']

THEMES = {
    'dark': {
        'bg': '#0b0c14', 'border': '#ffffff1f', 'tile': '#ffffff0a', 'tile_border': '#ffffff14',
        'text': '#f5f6fa', 'muted': '#9aa0b4',
        'accents': {'release': '#a78bfa', 'downloads': '#22d3ee', 'stars': '#fbbf24', 'license': '#4ade80'},
    },
    'light': {
        'bg': '#ffffff', 'border': '#0b0c1424', 'tile': '#f4f5fa', 'tile_border': '#0b0c1414',
        'text': '#0b0c14', 'muted': '#5b6072',
        'accents': {'release': '#7c3aed', 'downloads': '#0891b2', 'stars': '#d97706', 'license': '#16a34a'},
    },
}

# 24x24 stroke icons.
ICONS = {
    'release': '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8z"/><circle cx="7" cy="7" r="1.2"/>',
    'downloads': '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    'stars': '<path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8-6.2-3.2-6.2 3.2L7 14.2 2 9.3l6.9-1z"/>',
    'license': '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
}


def get(url):
    request = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'eagle-readme-stats',
    })
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        request.add_header('Authorization', f'Bearer {token}')
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def fetch_stats():
    repo = get(API)
    latest = get(f'{API}/releases/latest')
    downloads = 0
    page = 1
    while True:
        releases = get(f'{API}/releases?per_page=100&page={page}')
        for release in releases:
            downloads += sum(a['download_count'] for a in release['assets'] if a['name'].lower().endswith('.ipa'))
        if len(releases) < 100:
            break
        page += 1
    ipa = next((a for a in latest['assets'] if a['name'].lower().endswith('.ipa')), None)
    version = latest['tag_name'].lstrip('v')
    build = re.search(r'-(\d+)\.ipa$', ipa['name']) if ipa else None
    return {
        'tag': latest['tag_name'],
        'version': version,
        'build': build.group(1) if build else None,
        'ipa_url': ipa['browser_download_url'] if ipa else f'{WEB}/releases/latest',
        'downloads': downloads,
        'stars': repo['stargazers_count'],
        'license': (repo.get('license') or {}).get('spdx_id') or 'AGPL-3.0',
    }


def spectrum_gradient(gradient_id, x2='100%', y2='0%'):
    step = 100 / (len(SPECTRUM) - 1)
    stops = ''.join(f'<stop offset="{i * step:.1f}%" stop-color="{c}"/>' for i, c in enumerate(SPECTRUM))
    return f'<linearGradient id="{gradient_id}" x1="0%" y1="0%" x2="{x2}" y2="{y2}">{stops}</linearGradient>'


def stats_svg(stats, theme_name, updated):
    t = THEMES[theme_name]
    w, h = 560, 268
    tiles = [
        ('release', 'Latest release', f"v{stats['version']}"),
        ('downloads', 'IPA downloads', f"{stats['downloads']:,}"),
        ('stars', 'GitHub stars', f"{stats['stars']:,}"),
        ('license', 'License', stats['license']),
    ]
    body = []
    for i, (key, label, value) in enumerate(tiles):
        x = 24 + (i % 2) * 264
        y = 64 + (i // 2) * 92
        accent = t['accents'][key]
        body.append(
            f'<rect x="{x}" y="{y}" width="248" height="78" rx="18" fill="{t["tile"]}" stroke="{t["tile_border"]}"/>'
            f'<circle cx="{x + 38}" cy="{y + 39}" r="20" fill="{accent}" fill-opacity="0.16"/>'
            f'<g transform="translate({x + 29} {y + 30}) scale(0.75)" fill="none" stroke="{accent}" '
            f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">{ICONS[key]}</g>'
            f'<text x="{x + 72}" y="{y + 32}" fill="{t["muted"]}" font-size="11" font-weight="600" '
            f'letter-spacing="1.2">{escape(label.upper())}</text>'
            f'<text x="{x + 72}" y="{y + 60}" fill="{t["text"]}" font-size="25" font-weight="700">{escape(value)}</text>'
        )
    title = f"Eagle v{stats['version']} · {stats['downloads']:,} IPA downloads · {stats['stars']:,} stars · {stats['license']}"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{escape(title)}">
  <title>{escape(title)}</title>
  <defs>
    {spectrum_gradient('spectrum')}
    <clipPath id="card"><rect x="1" y="1" width="{w - 2}" height="{h - 2}" rx="26"/></clipPath>
  </defs>
  <g font-family="{FONT}">
    <rect x="1" y="1" width="{w - 2}" height="{h - 2}" rx="26" fill="{t['bg']}" stroke="{t['border']}"/>
    <rect width="{w}" height="4" fill="url(#spectrum)" clip-path="url(#card)"/>
    <text x="24" y="42" fill="url(#spectrum)" font-size="15" font-weight="800" letter-spacing="3.5">EAGLE</text>
    <text x="96" y="42" fill="{t['muted']}" font-size="12" font-weight="600" letter-spacing="1.2">LIVE STATS</text>
    <circle cx="{w - 24 - 6.5 * len(updated) - 12}" cy="38" r="4" fill="{t['accents']['license']}"/>
    <text x="{w - 24}" y="42" fill="{t['muted']}" font-size="12" text-anchor="end">{escape(updated)}</text>
    {''.join(body)}
    <text x="{w / 2:g}" y="{h - 14}" fill="{t['muted']}" font-size="11" text-anchor="middle">IPA files across every release · refreshed automatically from GitHub</text>
  </g>
</svg>
'''


def download_svg(stats):
    w, h = 340, 64
    sub = f"IPA · build {stats['build']}" if stats['build'] else 'IPA for sideloading'
    title = f"Download Eagle {stats['version']}"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{escape(title)} IPA">
  <title>{escape(title)} IPA</title>
  <defs>
    {spectrum_gradient('spectrum')}
    {spectrum_gradient('orb', '100%', '100%')}
  </defs>
  <g font-family="{FONT}">
    <rect x="1.5" y="1.5" width="{w - 3}" height="{h - 3}" rx="{(h - 3) / 2:g}" fill="#0b0c14" stroke="url(#spectrum)" stroke-width="3"/>
    <circle cx="34" cy="32" r="20" fill="url(#orb)"/>
    <g transform="translate(25 23) scale(0.75)" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">{ICONS['downloads']}</g>
    <text x="66" y="29" fill="#f5f6fa" font-size="17" font-weight="700">{escape(title)}</text>
    <text x="66" y="47" fill="#9aa0b4" font-size="12" font-weight="500" letter-spacing="0.4">{escape(sub)}</text>
    <path d="m{w - 34} 25 7 7-7 7" fill="none" stroke="#9aa0b4" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
</svg>
'''


def readme_block(stats):
    alt = f"Eagle v{stats['version']}: {stats['downloads']:,} IPA downloads, {stats['stars']:,} GitHub stars, {stats['license']} license"
    return f'''{START}
  <a href="{WEB}/releases">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/badges/stats-dark.svg">
      <img src="docs/badges/stats-light.svg" alt="{escape(alt)}" width="560">
    </picture>
  </a>

  <br><br>

  <a href="{stats['ipa_url']}">
    <img src="docs/badges/download.svg" alt="Download Eagle {stats['version']} IPA" width="340">
  </a>

  <br><br>

  [Release notes]({WEB}/releases/tag/{stats['tag']})
  · [Star Eagle]({WEB}/stargazers)
  · [Report a bug]({WEB}/issues/new?template=bug_report.md)
  · [Request a feature]({WEB}/issues/new?template=feature_request.md)
  {END}'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--force', action='store_true', help='rewrite even when the counts are unchanged')
    args = parser.parse_args()

    stats = fetch_stats()
    previous = json.loads(STATE.read_text()) if STATE.exists() else {}
    if not args.force and {k: previous.get(k) for k in stats} == stats:
        print('Stats unchanged:', json.dumps(stats))
        return

    readme = README.read_text()
    if START not in readme or END not in readme:
        sys.exit(f'README is missing the {START} / {END} markers')

    now = datetime.now(timezone.utc)
    updated = f"Updated {now:%b} {now.day}, {now:%Y} · {now:%H:%M} UTC"
    BADGES.mkdir(parents=True, exist_ok=True)
    for theme in THEMES:
        (BADGES / f'stats-{theme}.svg').write_text(stats_svg(stats, theme, updated))
    (BADGES / 'download.svg').write_text(download_svg(stats))
    STATE.write_text(json.dumps({**stats, 'updated': now.isoformat(timespec='minutes')}, indent=2) + '\n')

    head, rest = readme.split(START, 1)
    README.write_text(head + readme_block(stats) + rest.split(END, 1)[1])
    print('Stats updated:', json.dumps(stats))


if __name__ == '__main__':
    main()
