#!/usr/bin/env python3
"""Verify a Lambda package against its package-time build-input manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


def result(fresh: bool, reason: str) -> dict[str, str]:
    return {"fresh": str(fresh).lower(), "reason": reason}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_repo_path(repo_root: Path, relative_path: str) -> Path:
    candidate = (repo_root / relative_path).resolve()
    try:
        candidate.relative_to(repo_root)
    except ValueError as error:
        raise ValueError(
            f"manifest path escapes the repository: {relative_path}"
        ) from error
    return candidate


def enumerate_selection(
    repo_root: Path, selection: dict[str, Any]
) -> list[dict[str, str]]:
    excluded = set(selection.get("excluded_components", []))
    sources: dict[str, str] = {}

    for root in selection.get("roots", []):
        relative_path = root.get("path", "")
        path = safe_repo_path(repo_root, relative_path)
        kind = root.get("kind")
        if kind == "file":
            if not path.is_file():
                raise FileNotFoundError(f"missing build input: {relative_path}")
            candidates = [path]
        elif kind == "tree":
            if not path.is_dir():
                raise FileNotFoundError(f"missing build input tree: {relative_path}")
            candidates = sorted(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file()
                and not excluded.intersection(candidate.relative_to(path).parts)
            )
        else:
            raise ValueError(f"unsupported build input kind: {kind!r}")

        for candidate in candidates:
            source_path = candidate.relative_to(repo_root).as_posix()
            sources[source_path] = sha256(candidate)

    return [
        {"path": path, "sha256": digest} for path, digest in sorted(sources.items())
    ]


def source_fingerprint(sources: list[dict[str, str]]) -> str:
    return hashlib.sha256(
        json.dumps(sources, separators=(",", ":"), sort_keys=True).encode("utf-8")
    ).hexdigest()


def verify_package(
    repo_root: Path, package_path: Path, manifest_path: Path
) -> tuple[bool, str, dict[str, Any] | None]:
    repo_root = repo_root.resolve()
    package_path = package_path.resolve()
    manifest_path = manifest_path.resolve()

    if not package_path.is_file():
        return False, f"missing package: {package_path}", None
    if not manifest_path.is_file():
        return False, f"missing package manifest: {manifest_path}", None

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("version") != 1:
            return False, "unsupported package manifest version", manifest

        recorded_package = manifest.get("package", {})
        expected_package_path = safe_repo_path(
            repo_root, recorded_package.get("path", "")
        )
        if expected_package_path != package_path:
            return False, "package path does not match the package manifest", manifest
        if sha256(package_path) != recorded_package.get("sha256"):
            return False, "package content differs from the package manifest", manifest

        recorded_sources = manifest.get("sources")
        if not isinstance(recorded_sources, list) or not recorded_sources:
            return False, "package manifest contains no build inputs", manifest
        current_sources = enumerate_selection(repo_root, manifest.get("selection", {}))
        if current_sources != recorded_sources:
            recorded_paths = {entry.get("path") for entry in recorded_sources}
            current_paths = {entry.get("path") for entry in current_sources}
            added = sorted(current_paths - recorded_paths)
            deleted = sorted(recorded_paths - current_paths)
            if added:
                return False, f"build input added after packaging: {added[0]}", manifest
            if deleted:
                return (
                    False,
                    f"build input deleted after packaging: {deleted[0]}",
                    manifest,
                )
            changed = next(
                current["path"]
                for current, recorded in zip(
                    current_sources, recorded_sources, strict=True
                )
                if current != recorded
            )
            return False, f"build input changed after packaging: {changed}", manifest

        package_mtime_ns = package_path.stat().st_mtime_ns
        newer_source = next(
            (
                entry["path"]
                for entry in current_sources
                if safe_repo_path(repo_root, entry["path"]).stat().st_mtime_ns
                > package_mtime_ns
            ),
            None,
        )
        if newer_source is not None:
            return (
                False,
                f"build input is newer than the package: {newer_source}",
                manifest,
            )

        fingerprint = source_fingerprint(current_sources)
        if fingerprint != manifest.get("source_fingerprint"):
            return (
                False,
                "build-input fingerprint differs from the package manifest",
                manifest,
            )
    except (
        FileNotFoundError,
        KeyError,
        TypeError,
        ValueError,
        json.JSONDecodeError,
    ) as error:
        return False, str(error), None

    return True, "fresh", manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path)
    parser.add_argument("--package-path", type=Path)
    parser.add_argument("--manifest-path", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cli_mode = any((args.repo_root, args.package_path, args.manifest_path))

    if cli_mode:
        if not all((args.repo_root, args.package_path, args.manifest_path)):
            print(
                "--repo-root, --package-path, and --manifest-path are required together",
                file=sys.stderr,
            )
            return 2
        fresh, reason, _ = verify_package(
            args.repo_root, args.package_path, args.manifest_path
        )
        if not fresh:
            print(f"Package validation failed: {reason}", file=sys.stderr)
            return 1
        return 0

    query = json.load(sys.stdin)
    fresh, reason, _ = verify_package(
        Path(query["repo_root"]),
        Path(query["package_path"]),
        Path(query["manifest_path"]),
    )
    json.dump(result(fresh, reason), sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
