import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync_release_docs as sync  # noqa: E402


def github_release(tag, *, name=None, prerelease=False, draft=False, body="", published_at="2026-10-24T12:00:00Z"):
    return {
        "tag_name": tag,
        "name": name or tag,
        "prerelease": prerelease,
        "draft": draft,
        "body": body,
        "html_url": f"https://github.com/emanuele0409/NimBar/releases/tag/{tag}",
        "published_at": published_at,
    }


class ReleaseSelectionTests(unittest.TestCase):
    def test_selects_highest_version_and_channel_precedence(self):
        releases = [
            github_release("v0.3.0-beta.62", prerelease=True),
            github_release("v0.3.1-beta.3", prerelease=True),
            github_release("v0.3.1", prerelease=False),
        ]
        self.assertEqual(sync.select_current_release(releases).tag, "v0.3.1")

    def test_recognizes_alpha_beta_and_stable_tags(self):
        self.assertEqual(sync.parse_release(github_release("v0.4.0.1-alpha.7", prerelease=True)).channel, "alpha")
        self.assertEqual(sync.parse_release(github_release("v0.4.0-beta.8", prerelease=True)).build, 8)
        self.assertEqual(sync.parse_release(github_release("v0.4.0")).channel, "stable")

    def test_skips_drafts_and_inconsistent_prerelease_flags(self):
        releases = [
            github_release("v9.0.0-beta.1", prerelease=True, draft=True),
            github_release("v8.0.0-beta.1", prerelease=False),
            github_release("v0.3.0-beta.62", prerelease=True),
        ]
        self.assertEqual(sync.select_current_release(releases).tag, "v0.3.0-beta.62")


class DocumentationSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "docs").mkdir()
        (self.root / "README.md").write_text(
            "> **Latest beta: 0.3.0.** Download it from the [NimBar Releases page](https://github.com/emanuele0409/NimBar/releases).\n\n"
            "## Screenshots\n\nKEEP THESE SCREENSHOTS EXACTLY\n\n"
            "## Download\n\nThe latest beta is **0.3.0**. Download the DMG or ZIP from the [NimBar Releases page](https://github.com/emanuele0409/NimBar/releases).\n\n"
            "## Installation\n\nDownload the current beta from [GitHub Releases](https://github.com/emanuele0409/NimBar/releases/tag/v0.2.1-beta.46). Choose the DMG for guided installation or the ZIP for manual installation. See [Installation](docs/INSTALLATION.md) for the steps.\n\n"
            "## Updates\n\nThe current public beta is [0.2.1 beta, build 46](https://github.com/emanuele0409/NimBar/releases/tag/v0.2.1-beta.46). See [Update Design](docs/UPDATES.md) for the release tag format and signing requirements.\n",
            encoding="utf-8",
        )
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n\nIntro.\n\n## 0.3.0 beta — build 62\n\nOld notes.\n\n## 0.3.0 beta — build 49\n\nHistorical notes.\n",
            encoding="utf-8",
        )
        (self.root / "SECURITY.md").write_text("MANUAL SECURITY REVIEW\n", encoding="utf-8")
        (self.root / "PRIVACY.md").write_text("MANUAL PRIVACY REVIEW\n", encoding="utf-8")
        (self.root / "docs" / "INSTALLATION.md").write_text(
            "# Installation\n\nDownload NimBar only from the official [GitHub Releases page](https://github.com/emanuele0409/NimBar/releases/tag/v0.2.1-beta.46). No Xcode installation is required for end users.\n\n"
            "The current development build is not notarized by Apple. Read [Security](../SECURITY.md#opening-a-future-download).\n",
            encoding="utf-8",
        )
        (self.root / "docs" / "UPDATES.md").write_text(
            "# NimBar Updates\n\n## Verified repository state\n\n"
            "- The Xcode project declares version `0.3.0`, build `49`, beta release channel, macOS deployment target `27.0`, and bundle identifier `com.nimbar.NimBar`.\n\n"
            "## Local alpha development\n\nThe current release is 0.3.0 beta, build 49, tagged `v0.3.0-beta.49`. Beta clients select beta or stable releases.\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def test_initial_sync_is_idempotent_and_preserves_screenshots_and_manual_docs(self):
        release = sync.parse_release(
            github_release(
                "v0.3.0-beta.62",
                name="0.3.0 beta (build 62)",
                prerelease=True,
                body="## NimBar 0.3.0 beta (build 62)\n\n### Highlights\n- Restored Notification Center clock clicks.\n- Adapted the Layout strip.\n\n### Downloads\n- DMG",
            )
        )
        screenshots = self.readme_screenshots()
        security_before = (self.root / "SECURITY.md").read_bytes()
        privacy_before = (self.root / "PRIVACY.md").read_bytes()

        changed = sync.sync_docs(self.root, release)
        self.assertIn(self.root / "README.md", changed)
        self.assertIn(self.root / "docs" / "UPDATES.md", changed)
        self.assertIn("Restored Notification Center clock clicks.", (self.root / "CHANGELOG.md").read_text())
        self.assertIn("v0.3.0-beta.62", (self.root / "docs" / "INSTALLATION.md").read_text())
        self.assertEqual(screenshots, self.readme_screenshots())
        self.assertEqual(security_before, (self.root / "SECURITY.md").read_bytes())
        self.assertEqual(privacy_before, (self.root / "PRIVACY.md").read_bytes())

        snapshots = {path: path.read_bytes() for path in self.root.rglob("*.md")}
        self.assertEqual(sync.sync_docs(self.root, release), [])
        self.assertEqual(snapshots, {path: path.read_bytes() for path in self.root.rglob("*.md")})

    def test_new_release_moves_previous_managed_entry_into_history_once(self):
        first = sync.parse_release(github_release("v0.3.0-beta.62", prerelease=True, body="### Highlights\n- Old release"))
        second = sync.parse_release(github_release("v0.3.1-beta.1", prerelease=True, body="### Highlights\n- New release"))
        sync.sync_docs(self.root, first)
        sync.sync_docs(self.root, second)
        changelog = (self.root / "CHANGELOG.md").read_text()
        self.assertEqual(changelog.count("<!-- release-tag: v0.3.0-beta.62 -->"), 1)
        self.assertEqual(changelog.count("## 0.3.0 beta — build 62"), 1)
        self.assertIn("## 0.3.1 beta — build 1", changelog)
        self.assertIn("## 0.3.0 beta — build 49", changelog)
        before = changelog
        sync.sync_docs(self.root, second)
        self.assertEqual(before, (self.root / "CHANGELOG.md").read_text())

    def readme_screenshots(self):
        readme = (self.root / "README.md").read_text(encoding="utf-8")
        start = readme.index("## Screenshots")
        end = readme.index("## Download", start)
        return readme[start:end]


if __name__ == "__main__":
    unittest.main()
