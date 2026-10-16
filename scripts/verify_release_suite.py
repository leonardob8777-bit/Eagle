#!/usr/bin/env python3
"""Run self-contained Python regression gates; log explicit manual/artifact exclusions.

No app publication or physical-device access. Simulator-owning gates run serially.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/release-95-checks'
EXCLUDED = {
    'verify_release_suite.py': 'This runner.',
    'verify_eagle_visual_base.py': 'Projection helper, exercised by integration gates.',
    'verify_eagle_aura_test_ipa.py': 'Run separately against the newly built candidate.',
    'verify_eagle_interface_preview_artifacts.py': 'Requires a dedicated interface-preview artifact directory.',
    'verify_island_live.py': 'Requires explicit gallery asset directory.',
    'verify_island_live_animation.py': 'Requires explicit simulator and animation frames.',
    'verify_island_pulse.py': 'Requires explicit simulator.',
    'verify_dock_aura.py': 'Requires explicit simulator.',
}

def check(path):
    log = OUT / (path.stem + '.log')
    with log.open('w') as stream:
        try:
            result = subprocess.run([sys.executable, str(path)], cwd=ROOT,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=360)
            status = 'passed' if result.returncode == 0 else 'failed'
        except subprocess.TimeoutExpired:
            status = 'timeout'
    print(f'{status.upper()}: {path.name}', flush=True)
    return {'script': path.name, 'status': status, 'log': str(log)}

def main():
    global OUT
    retry = '--retry-failed' in sys.argv
    failed_names = None
    if retry:
        previous = json.loads((OUT / 'results.json').read_text())
        failed_names = {r['script'] for r in previous['results'] if r['status'] != 'passed'}
        OUT = ROOT / 'build/release-95-rechecks'
    OUT.mkdir(parents=True, exist_ok=True)
    paths = sorted(p for p in (ROOT / 'scripts').glob('verify_*.py') if p.name not in EXCLUDED)
    if failed_names is not None:
        paths = [p for p in paths if p.name in failed_names]
    simulator = [p for p in paths if '"simctl"' in p.read_text() or "'simctl'" in p.read_text()]
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(check, [p for p in paths if p not in simulator]))
    results += [check(p) for p in simulator]
    report = {'results': results, 'excluded': EXCLUDED}
    (OUT / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    failures = [r for r in results if r['status'] != 'passed']
    print(f"SUMMARY: {len(results) - len(failures)}/{len(results)} passed; {len(EXCLUDED)} exclusions", flush=True)
    return bool(failures)

if __name__ == '__main__':
    sys.exit(main())
