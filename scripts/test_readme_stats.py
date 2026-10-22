#!/usr/bin/env python3
"""Counter behavior: pagination, failures, decreases, stable writes and cache keys."""
import tempfile
import unittest
from pathlib import Path

from update_readme_stats import collect_stats, update


class ReadmeStatsTests(unittest.TestCase):
    def test_all_pages_ipa_only_no_drafts(self):
        pages = [
            [{"draft": False, "assets": [{"name": "a.ipa", "download_count": 5},
                                          {"name": "SHA256SUMS.txt", "download_count": 99}]}],
            [{"draft": False, "assets": [{"name": "b.IPA", "download_count": 8}]},
             {"draft": True, "assets": [{"name": "private.ipa", "download_count": 100}]}],
        ]
        self.assertEqual(collect_stats({"stargazers_count": 64}, pages),
                         {"ipa_downloads": 13, "stars": 64})

    def test_invalid_api_response_rejected(self):
        for value in (None, -1, True, "64"):
            with self.assertRaises(ValueError):
                collect_stats({"stargazers_count": value}, [[]])
        with self.assertRaises(KeyError):
            collect_stats({"message": "API rate limit exceeded"}, [[]])
        with self.assertRaises(ValueError):
            collect_stats({"stargazers_count": 64}, [])

    def test_updates_decreases_no_churn_and_failure_preserves_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "docs/badges").mkdir(parents=True)
            (root / "README.md").write_text(
                '![Downloads](docs/badges/downloads.svg)\n![Stars](docs/badges/stars.svg)\n'
                '  <sub>Counts checked old date.</sub>\n')
            self.assertTrue(update(root, {"ipa_downloads": 2154, "stars": 64}, "first"))
            before = {p: p.read_bytes() for p in root.rglob('*') if p.is_file()}
            self.assertFalse(update(root, {"ipa_downloads": 2154, "stars": 64}, "later"))
            self.assertEqual(before, {p: p.read_bytes() for p in before})
            with self.assertRaises(ValueError):
                update(root, {"ipa_downloads": -1, "stars": 0}, "failure")
            self.assertEqual(before, {p: p.read_bytes() for p in before})
            self.assertTrue(update(root, {"ipa_downloads": 2155, "stars": 63}, "next"))
            readme = (root / "README.md").read_text()
            self.assertIn('downloads.svg?v=2155', readme)
            self.assertIn('stars.svg?v=63', readme)
            self.assertIn('Last change: next.', readme)
            self.assertIn('STARS: 63', (root / "docs/badges/stars.svg").read_text())


if __name__ == '__main__':
    unittest.main()
