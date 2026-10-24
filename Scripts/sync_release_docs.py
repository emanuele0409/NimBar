#!/usr/bin/env python3
"""Synchronize public release documentation from GitHub Releases metadata."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


OWNER = "emanuele0409"
REPOSITORY = "NimBar"
API_URL = f"https://api.github.com/repos/{OWNER}/{REPOSITORY}/releases"
TAG_PATTERN = re.compile(
    r"^v?(?P<version>\d+(?:\.\d+){2,3})(?:-(?P<channel>alpha|beta)\.(?P<build>\d+))?$",
    re.IGNORECASE,
)
BUILD_PATTERN = re.compile(r"\bbuild\s*#?\s*(\d+)\b", re.IGNORECASE)
@dataclass(frozen=True)
class Release:
    tag: str
    version: str
    channel: str
    build: int | None
    url: str
    title: str
    body: str
    published_at: str

    @property
    def sort_key(self) -> tuple[Any, ...]:
        parts = tuple(int(part) for part in self.version.split("."))
        padded_version = parts + (0,) * (4 - len(parts))
        channel_rank = {"alpha": 0, "beta": 1, "stable": 2}[self.channel]
        return (*padded_version, channel_rank, self.build or 0, self.published_at, self.tag)

    @property
    def display(self) -> str:
        label = self.version if self.channel == "stable" else f"{self.version} {self.channel}"
        if self.build is not None:
            label += f" (build {self.build})"
        return label


def parse_release(raw: dict[str, Any]) -> Release | None:
    if raw.get("draft") is True:
        return None

    tag = str(raw.get("tag_name", ""))
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        return None

    version = match.group("version")
    channel = (match.group("channel") or "stable").lower()
    is_prerelease = raw.get("prerelease") is True
    if is_prerelease != (channel != "stable"):
        return None

    suffix_build = match.group("build")
    title = str(raw.get("name") or tag)
    body = str(raw.get("body") or "")
    build = int(suffix_build) if suffix_build else None
    if build is None:
        build_match = BUILD_PATTERN.search(title) or BUILD_PATTERN.search(body)
        if build_match:
            build = int(build_match.group(1))

    url = str(raw.get("html_url") or f"https://github.com/{OWNER}/{REPOSITORY}/releases/tag/{tag}")
    return Release(
        tag=tag,
        version=version,
        channel=channel,
        build=build,
        url=url,
        title=title,
        body=body.replace("\r\n", "\n").strip(),
        published_at=str(raw.get("published_at") or ""),
    )


def select_current_release(raw_releases: list[dict[str, Any]]) -> Release:
    candidates = [release for item in raw_releases if (release := parse_release(item)) is not None]
    if not candidates:
        raise ValueError("GitHub returned no published release with a supported NimBar tag.")
    return max(candidates, key=lambda release: release.sort_key)


def fetch_releases() -> list[dict[str, Any]]:
    token = os.environ.get("GITHUB_TOKEN")
    releases: list[dict[str, Any]] = []
    page = 1
    while True:
        request = urllib.request.Request(
            f"{API_URL}?per_page=100&page={page}",
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "NimBar-release-documentation-sync",
                **({"Authorization": f"Bearer {token}"} if token else {}),
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                page_items = json.load(response)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            raise RuntimeError(f"Could not read the GitHub Releases API: {error}") from error
        if not isinstance(page_items, list):
            raise RuntimeError("GitHub Releases API returned an unexpected response.")
        releases.extend(item for item in page_items if isinstance(item, dict))
        if len(page_items) < 100:
            return releases
        page += 1


def extract_highlights(body: str) -> list[str]:
    lines = body.splitlines()
    heading = re.compile(r"^#{1,4}\s+(highlights|what(?:'|’)s changed|release notes?)\s*$", re.IGNORECASE)
    stop_heading = re.compile(r"^#{1,4}\s+(downloads?|checksums?|requirements?(?: and signing)?|assets?)\b", re.IGNORECASE)
    start = next((index for index, line in enumerate(lines) if heading.match(line.strip())), None)
    if start is not None:
        selected: list[str] = []
        for line in lines[start + 1 :]:
            stripped = line.strip()
            if stop_heading.match(stripped) or re.match(r"^#{1,4}\s+", stripped):
                break
            if stripped:
                selected.append(stripped)
        return selected

    selected = []
    for line in lines:
        stripped = line.strip()
        if stop_heading.match(stripped) or re.match(r"^#{1,4}\s+(downloads?|checksums?|requirements?)\b", stripped, re.IGNORECASE):
            break
        if stripped:
            selected.append(stripped)
    return selected


def changelog_heading(release: Release) -> str:
    channel = "" if release.channel == "stable" else f" {release.channel}"
    build = f" — build {release.build}" if release.build is not None else ""
    return f"## {release.version}{channel}{build}"


def changelog_block(release: Release) -> str:
    highlights = extract_highlights(release.body)
    lines = [
        "<!-- nimbar-release-sync:changelog:start -->",
        f"<!-- release-tag: {release.tag} -->",
        changelog_heading(release),
        f"[Release notes and downloads]({release.url})",
    ]
    if highlights:
        lines.extend(["", "### Highlights", "", *highlights])
    lines.append("<!-- nimbar-release-sync:changelog:end -->")
    return "\n".join(lines)


def replace_or_insert_marked_block(
    text: str,
    name: str,
    content: str,
    fallback_pattern: str,
    required: bool = True,
) -> str:
    marker = re.compile(
        rf"<!-- nimbar-release-sync:{re.escape(name)}:start -->.*?"
        rf"<!-- nimbar-release-sync:{re.escape(name)}:end -->",
        re.DOTALL,
    )
    matches = list(marker.finditer(text))
    if len(matches) > 1:
        raise ValueError(f"Expected at most one managed {name} block.")
    if matches:
        return text[: matches[0].start()] + content + text[matches[0].end() :]

    if fallback_pattern:
        fallback = re.search(fallback_pattern, text, re.MULTILINE)
        if fallback:
            return text[: fallback.start()] + content + text[fallback.end() :]
    if required:
        raise ValueError(f"Could not find the insertion point for the {name} release block.")
    return text


def sync_changelog(text: str, release: Release) -> str:
    block = changelog_block(release)
    matches = list(
        re.finditer(
            r"<!-- nimbar-release-sync:changelog:start -->.*?<!-- nimbar-release-sync:changelog:end -->",
            text,
            re.DOTALL,
        )
    )
    if len(matches) > 1:
        raise ValueError("Expected at most one managed changelog block.")
    if matches:
        old_block = matches[0].group(0)
        old_tag_match = re.search(r"<!-- release-tag: ([^ ]+) -->", old_block)
        old_tag = old_tag_match.group(1) if old_tag_match else None
        if old_tag == release.tag:
            replacement = block
        else:
            historical = old_block.replace("<!-- nimbar-release-sync:changelog:start -->\n", "", 1)
            historical = historical.replace("<!-- nimbar-release-sync:changelog:end -->", "").strip()
            replacement = block + "\n\n" + historical
        return text[: matches[0].start()] + replacement + text[matches[0].end() :]

    # Migrate the current hand-maintained release entry into the managed block.
    header = re.compile(r"^##\s+(\d+(?:\.\d+){2,3})(?:\s+(alpha|beta))?.*$", re.MULTILINE)
    sections = list(header.finditer(text))
    target = None
    for index, section in enumerate(sections):
        version = section.group(1)
        channel = (section.group(2) or "stable").lower()
        next_start = sections[index + 1].start() if index + 1 < len(sections) else len(text)
        section_text = text[section.start() : next_start]
        build_match = BUILD_PATTERN.search(section.group(0))
        section_build = int(build_match.group(1)) if build_match else None
        if (version, channel, section_build) == (release.version, release.channel, release.build):
            target = (section.start(), next_start)
            break

    if target:
        return text[: target[0]] + block + "\n\n" + text[target[1] :].lstrip("\n")

    first_section = sections[0].start() if sections else len(text)
    prefix = text[:first_section].rstrip()
    suffix = text[first_section:].lstrip("\n")
    return prefix + "\n\n" + block + ("\n\n" + suffix if suffix else "\n")


def release_line(release: Release, prefix: str = "Current public release") -> str:
    return f"{prefix}: **{release.display}** ([release notes and downloads]({release.url}))"


def sync_docs(root: Path, release: Release) -> list[Path]:
    changed: list[Path] = []

    readme_path = root / "README.md"
    readme = readme_path.read_text(encoding="utf-8")
    readme_blocks = {
        "latest": (
            f"> **Latest public release: {release.display}.** [Release notes and downloads]({release.url}).",
            r"^> \*\*Latest beta:.*$",
        ),
        "download": (
            f"The current public release is **{release.display}**. Download the DMG or ZIP from the [release page]({release.url}).",
            r"^The latest beta is \*\*.*$",
        ),
        "installation": (
            f"Download NimBar **{release.display}** from the official [GitHub release page]({release.url}). Choose the DMG for guided installation or the ZIP for manual installation. See [Installation](docs/INSTALLATION.md) for the steps.",
            r"^Download the current beta from \[GitHub Releases\].*$",
        ),
        "updates": (
            f"The current public release is **{release.display}** ([release page]({release.url})). See [Update Design](docs/UPDATES.md) for the release tag format and signing requirements.",
            r"^The current public beta is \[.*$",
        ),
    }
    for name, (line, fallback) in readme_blocks.items():
        readme = replace_or_insert_marked_block(
            readme,
            f"readme-{name}",
            f"<!-- nimbar-release-sync:readme-{name}:start -->\n{line}\n<!-- nimbar-release-sync:readme-{name}:end -->",
            fallback,
        )
    if readme != readme_path.read_text(encoding="utf-8"):
        readme_path.write_text(readme, encoding="utf-8")
        changed.append(readme_path)

    changelog_path = root / "CHANGELOG.md"
    changelog_before = changelog_path.read_text(encoding="utf-8")
    changelog = sync_changelog(changelog_before, release)
    if changelog != changelog_before:
        changelog_path.write_text(changelog, encoding="utf-8")
        changed.append(changelog_path)

    installation_path = root / "docs" / "INSTALLATION.md"
    installation = installation_path.read_text(encoding="utf-8")
    installation_line = (
        f"Download NimBar **{release.display}** only from the official "
        f"[GitHub release page]({release.url}). No Xcode installation is required for end users."
    )
    installation = replace_or_insert_marked_block(
        installation,
        "installation-current",
        f"<!-- nimbar-release-sync:installation-current:start -->\n{installation_line}\n<!-- nimbar-release-sync:installation-current:end -->",
        r"^Download NimBar only from the official \[GitHub Releases page\].*$",
    )
    installation = installation.replace("The current development build is not notarized", "The current public release is not notarized")
    installation = installation.replace("#opening-a-future-download", "#opening-a-release-download")
    if installation != installation_path.read_text(encoding="utf-8"):
        installation_path.write_text(installation, encoding="utf-8")
        changed.append(installation_path)

    updates_path = root / "docs" / "UPDATES.md"
    updates_before = updates_path.read_text(encoding="utf-8")
    updates = re.sub(r"^- The Xcode project declares version .*?bundle identifier `com\.nimbar\.NimBar`\.\n", "", updates_before, count=1, flags=re.MULTILINE)
    update_release = (
        f"- {release_line(release, 'Latest published release')}. Its tag is `{release.tag}` and its channel is **{release.channel}**."
    )
    updates = replace_or_insert_marked_block(
        updates,
        "verified-release",
        f"<!-- nimbar-release-sync:verified-release:start -->\n{update_release}\n<!-- nimbar-release-sync:verified-release:end -->",
        r"^## Verified repository state\s*$",
        required=False,
    ) if "<!-- nimbar-release-sync:verified-release:start -->" in updates else insert_after_heading(
        updates,
        "Verified repository state",
        f"<!-- nimbar-release-sync:verified-release:start -->\n{update_release}\n<!-- nimbar-release-sync:verified-release:end -->",
    )
    updates = re.sub(
        r"## Local alpha development\s*\n\s*The current release is .*?(?=\n\n|\Z)",
        "## Channel selection and release order\n\nRelease tags follow the app's supported version and channel format. Beta clients can select beta or stable releases; stable clients select stable releases. For the same base version, stable sorts after beta, and beta sorts after alpha. Alpha revisions remain separate from beta build tags.",
        updates,
        count=1,
        flags=re.DOTALL,
    )
    if "## Public release documentation sync" not in updates:
        updates += (
            "\n\n## Public release documentation sync\n\n"
            "`.github/workflows/sync-release-docs.yml` runs when a release is published or edited and can be started manually with `workflow_dispatch`. "
            "It selects releases by their supported numeric version, channel precedence, and build suffix rather than by the last modification timestamp. "
            "The workflow also provides the initial synchronization for the existing build 62 release; run it once manually after enabling Actions. "
            "The workflow commits only when generated documentation changes. GitHub does not start another workflow for most events caused by `GITHUB_TOKEN`; this sync therefore completes the documentation update in the same run, and `workflow_dispatch` remains available for recovery or a manual refresh. "
            "Each run asks for a manual review of `SECURITY.md` and `PRIVACY.md`, because signing, notarization, permissions, or data behavior may change independently of release metadata."
        )
    if updates != updates_before:
        updates_path.write_text(updates, encoding="utf-8")
        changed.append(updates_path)

    return changed


def insert_after_heading(text: str, heading: str, content: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}\s*$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"Could not find the {heading!r} section in docs/UPDATES.md.")
    insertion = match.end()
    return text[:insertion] + "\n\n" + content + "\n\n" + text[insertion:].lstrip("\n")


def load_fixture(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict):
        payload = [payload]
    if not isinstance(payload, list) or not all(isinstance(item, dict) for item in payload):
        raise ValueError("Release fixture must be a GitHub release object or a list of release objects.")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--releases-json", type=Path, help="Use a saved GitHub Releases response instead of the network.")
    args = parser.parse_args(argv)

    try:
        raw_releases = load_fixture(args.releases_json) if args.releases_json else fetch_releases()
        release = select_current_release(raw_releases)
        changed = sync_docs(args.repo_root.resolve(), release)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"Release documentation sync failed: {error}", file=sys.stderr)
        return 1

    print(f"Selected {release.display} ({release.tag}) from {release.url}")
    if changed:
        print("Updated: " + ", ".join(str(path.relative_to(args.repo_root.resolve())) for path in changed))
    else:
        print("No documentation changes were needed.")
    print("Manual review required: check PRIVACY.md and SECURITY.md for release-specific changes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
