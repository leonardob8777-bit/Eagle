#!/usr/bin/env python3
"""Track GitHub release download counts for Eagle over time.

The GitHub API only exposes a running total per asset, so a single reading
cannot tell you whether a release is still being picked up or whether that
number is a week-old plateau. This script appends timestamped readings to a
CSV and reports rates and equal-age comparisons from that history.

Usage:
    scripts/release_downloads.py snapshot        # append current counts to the CSV
    scripts/release_downloads.py report          # totals, per-day rate, delta since last reading
    scripts/release_downloads.py report --age 7  # compare every release at 7 days old

Set GITHUB_TOKEN to raise the API rate limit (60/hour unauthenticated).
Counting note: downloads are requests, not people. A single user who
re-downloads, or a mirror that pulls the IPA, is counted each time.
"""

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO = "leonardob8777-bit/Eagle"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CSV = PROJECT_ROOT / "metrics" / "release_downloads.csv"
FIELDNAMES = [
    "snapshot_utc",
    "tag",
    "release_name",
    "published_at",
    "prerelease",
    "asset_name",
    "download_count",
    "size_bytes",
]


def parse_ts(value):
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def fetch_releases(repo):
    """Return every release, newest published first."""
    releases = []
    page = 1
    while True:
        url = f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}"
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "eagle-release-downloads",
            },
        )
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                batch = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code in (403, 429):
                sys.exit(
                    f"GitHub rate limit or access error ({error.code}). "
                    "Set GITHUB_TOKEN and retry."
                )
            raise
        if not batch:
            break
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1

    releases = [release for release in releases if not release["draft"]]
    releases.sort(key=lambda release: release["published_at"], reverse=True)
    return releases


def asset_rows(releases, snapshot_utc, ipa_only=True):
    for release in releases:
        for asset in release["assets"]:
            if ipa_only and not asset["name"].endswith(".ipa"):
                continue
            yield {
                "snapshot_utc": snapshot_utc,
                "tag": release["tag_name"],
                "release_name": release["name"] or release["tag_name"],
                "published_at": release["published_at"],
                "prerelease": str(release["prerelease"]).lower(),
                "asset_name": asset["name"],
                "download_count": asset["download_count"],
                "size_bytes": asset["size"],
            }


def read_history(csv_path):
    if not csv_path.exists():
        return []
    with csv_path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_snapshot(csv_path, rows):
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    is_new = not csv_path.exists()
    with csv_path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        if is_new:
            writer.writeheader()
        writer.writerows(rows)


def totals_by_tag(rows):
    """Sum download counts per tag, keeping the release metadata."""
    totals = {}
    for row in rows:
        entry = totals.setdefault(
            row["tag"],
            {
                "tag": row["tag"],
                "release_name": row["release_name"],
                "published_at": row["published_at"],
                "prerelease": row["prerelease"] == "true",
                "downloads": 0,
            },
        )
        entry["downloads"] += int(row["download_count"])
    return totals


def previous_snapshot_totals(history, current_snapshot):
    """Totals from the most recent reading taken before this one."""
    earlier = [row for row in history if row["snapshot_utc"] < current_snapshot]
    if not earlier:
        return None, None
    last = max(row["snapshot_utc"] for row in earlier)
    return totals_by_tag([row for row in earlier if row["snapshot_utc"] == last]), last


def cmd_snapshot(args):
    csv_path = Path(args.csv)
    snapshot_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    releases = fetch_releases(args.repo)
    rows = list(asset_rows(releases, snapshot_utc, ipa_only=not args.all_assets))
    if not rows:
        sys.exit("No matching release assets found.")
    write_snapshot(csv_path, rows)

    history = read_history(csv_path)
    current = totals_by_tag(rows)
    previous, previous_at = previous_snapshot_totals(history, snapshot_utc)

    print(f"Snapshot {snapshot_utc} -> {csv_path}")
    print(f"{len(rows)} asset rows across {len(current)} releases\n")
    for tag, entry in sorted(
        current.items(), key=lambda item: item[1]["published_at"], reverse=True
    ):
        line = f"  {tag:<18} {entry['downloads']:>7}"
        if previous and tag in previous:
            delta = entry["downloads"] - previous[tag]["downloads"]
            line += f"  ({delta:+d} since {previous_at})"
        elif previous:
            line += "  (new since last snapshot)"
        print(line)


def cmd_report(args):
    csv_path = Path(args.csv)
    history = read_history(csv_path)

    if args.live or not history:
        snapshot_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        releases = fetch_releases(args.repo)
        rows = list(asset_rows(releases, snapshot_utc, ipa_only=not args.all_assets))
        source = "live API"
    else:
        snapshot_utc = max(row["snapshot_utc"] for row in history)
        rows = [row for row in history if row["snapshot_utc"] == snapshot_utc]
        source = f"{csv_path.name}"

    if not rows:
        sys.exit("No data to report on. Run 'snapshot' first.")

    if args.age is not None:
        report_at_age(history, args.age, args.stable_only)
        return

    current = totals_by_tag(rows)
    previous, previous_at = previous_snapshot_totals(history, snapshot_utc)
    now = parse_ts(snapshot_utc)

    entries = sorted(
        current.values(), key=lambda entry: entry["published_at"], reverse=True
    )
    if args.stable_only:
        entries = [entry for entry in entries if not entry["prerelease"]]
    if args.limit:
        entries = entries[: args.limit]

    print(f"Eagle release downloads  ({source}, read {snapshot_utc})\n")
    print(f"{'Version':<18}{'Published':<12}{'Age':>7}{'Downloads':>11}{'Per day':>9}{'Delta':>9}")
    print("-" * 66)
    total = 0
    for entry in entries:
        published = parse_ts(entry["published_at"])
        age_days = max((now - published).total_seconds() / 86400, 0.0)
        per_day = entry["downloads"] / age_days if age_days >= 0.5 else float("nan")
        delta = ""
        if previous and entry["tag"] in previous:
            delta = f"{entry['downloads'] - previous[entry['tag']]['downloads']:+d}"
        per_day_text = f"{per_day:.1f}" if per_day == per_day else "--"
        print(
            f"{entry['tag']:<18}"
            f"{entry['published_at'][:10]:<12}"
            f"{age_days:>6.1f}d"
            f"{entry['downloads']:>11}"
            f"{per_day_text:>9}"
            f"{delta:>9}"
        )
        total += entry["downloads"]
    print("-" * 66)
    print(f"{'Total':<18}{'':<12}{'':>7}{total:>11}")

    if previous:
        print(f"\nDelta measured against the snapshot taken {previous_at}.")
    else:
        print("\nNo earlier snapshot yet — run 'snapshot' regularly to get deltas.")
    if len(history) == 0:
        print("Tip: 'snapshot' writes the history that 'report --age' needs.")


def report_at_age(history, age_days, stable_only):
    """Compare releases at the same number of days after publication.

    Raw totals favor whichever release has been public longest. This lines
    every release up at the same age so the comparison means something.
    """
    if not history:
        sys.exit("Equal-age comparison needs snapshot history. Run 'snapshot' first.")

    by_tag = {}
    for row in history:
        by_tag.setdefault(row["tag"], []).append(row)

    print(f"Eagle downloads at {age_days} days after publication\n")
    print(f"{'Version':<18}{'Published':<12}{'At age':>9}{'Reading':>10}{'Downloads':>11}")
    print("-" * 60)

    rows_out = []
    for tag, tag_rows in by_tag.items():
        published = parse_ts(tag_rows[0]["published_at"])
        if stable_only and tag_rows[0]["prerelease"] == "true":
            continue
        # Latest reading at or before the target age; totals only ever grow,
        # so an earlier reading undercounts rather than inventing downloads.
        eligible = {}
        for row in tag_rows:
            taken = parse_ts(row["snapshot_utc"])
            row_age = (taken - published).total_seconds() / 86400
            if row_age <= age_days:
                eligible.setdefault(row["snapshot_utc"], []).append((row_age, row))
        if not eligible:
            rows_out.append((published, tag, None, None, None))
            continue
        best_snapshot = max(eligible)
        actual_age = eligible[best_snapshot][0][0]
        downloads = sum(int(row["download_count"]) for _, row in eligible[best_snapshot])
        rows_out.append((published, tag, actual_age, best_snapshot, downloads))

    for published, tag, actual_age, snapshot, downloads in sorted(
        rows_out, key=lambda item: item[0], reverse=True
    ):
        if downloads is None:
            print(
                f"{tag:<18}{published.strftime('%Y-%m-%d'):<12}"
                f"{'no reading yet':>30}"
            )
            continue
        print(
            f"{tag:<18}"
            f"{published.strftime('%Y-%m-%d'):<12}"
            f"{actual_age:>8.1f}d"
            f"{snapshot[5:10]:>10}"
            f"{downloads:>11}"
        )
    print("-" * 60)
    print(
        "\n'At age' is the real age of the reading used — always at or below the\n"
        "target, since a release has no data before its first snapshot."
    )


def main():
    parser = argparse.ArgumentParser(
        description="Track Eagle release download counts over time.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:", 1)[1],
    )
    parser.add_argument("--repo", default=REPO, help=f"owner/name (default: {REPO})")
    parser.add_argument("--csv", default=str(DEFAULT_CSV), help="history CSV path")
    parser.add_argument(
        "--all-assets",
        action="store_true",
        help="include non-IPA assets such as .sha256 checksums",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser("snapshot", help="append current counts to the CSV")
    snapshot.set_defaults(func=cmd_snapshot)

    report = subparsers.add_parser("report", help="summarize downloads and rates")
    report.add_argument(
        "--live",
        action="store_true",
        help="read fresh counts from the API instead of the newest CSV rows",
    )
    report.add_argument(
        "--age",
        type=float,
        metavar="DAYS",
        help="compare every release at the same age instead of raw totals",
    )
    report.add_argument(
        "--stable-only", action="store_true", help="skip prereleases"
    )
    report.add_argument("--limit", type=int, help="show only the newest N releases")
    report.set_defaults(func=cmd_report)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # Piping into head or less closes stdout early. Point the remaining
        # output at devnull so interpreter shutdown does not flush into the
        # dead pipe and report the same failure a second time.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
