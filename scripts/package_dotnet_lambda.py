#!/usr/bin/env python3
"""Publish a .NET Lambda project and create a deterministic deployment zip."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

EXCLUDED_SOURCE_COMPONENTS = frozenset({".aws-sam", "bin", "obj"})


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Publish a .NET Lambda project and package its output."
    )
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runtime", default="linux-x64")
    parser.add_argument(
        "--repo-root",
        type=Path,
        help="Repository root used to record portable source paths.",
    )
    parser.add_argument(
        "--source",
        action="append",
        default=[],
        type=Path,
        help="Build input file or directory to include in the package manifest.",
    )
    return parser.parse_args()


def publish(project: Path, build_dir: Path, runtime: str) -> None:
    if not project.is_file():
        raise FileNotFoundError(f"Project file does not exist: {project}")

    artifacts_dir = build_dir.parent / f".{build_dir.name}-artifacts"
    for directory in (build_dir, artifacts_dir):
        if directory.exists():
            shutil.rmtree(directory)
    build_dir.mkdir(parents=True)

    try:
        subprocess.run(
            [
                "dotnet",
                "publish",
                str(project),
                "--configuration",
                "Release",
                "--output",
                str(build_dir),
                "--runtime",
                runtime,
                "--self-contained",
                "false",
                "--property:GenerateRuntimeConfigurationFiles=true",
                "--artifacts-path",
                str(artifacts_dir),
            ],
            check=True,
        )
    finally:
        shutil.rmtree(artifacts_dir, ignore_errors=True)


def package(build_dir: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(
        dir=output.parent, prefix=f".{output.name}.", suffix=".tmp", delete=False
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)

    try:
        with zipfile.ZipFile(
            temporary_path, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for source in sorted(
                path for path in build_dir.rglob("*") if path.is_file()
            ):
                relative_path = source.relative_to(build_dir).as_posix()
                entry = zipfile.ZipInfo(relative_path, date_time=(1980, 1, 1, 0, 0, 0))
                mode = source.stat().st_mode
                permissions = 0o755 if mode & stat.S_IXUSR else 0o644
                entry.external_attr = permissions << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, source.read_bytes())

        temporary_path.replace(output)
    finally:
        temporary_path.unlink(missing_ok=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_to_repo(path: Path, repo_root: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root).as_posix()
    except ValueError as error:
        raise ValueError(f"Build input is outside the repository: {path}") from error


def source_files(source: Path) -> list[Path]:
    if source.is_file():
        return [source]
    if source.is_dir():
        return sorted(
            path
            for path in source.rglob("*")
            if path.is_file()
            and not EXCLUDED_SOURCE_COMPONENTS.intersection(
                path.relative_to(source).parts
            )
        )
    raise FileNotFoundError(f"Build input does not exist: {source}")


def write_package_manifest(output: Path, repo_root: Path, sources: list[Path]) -> None:
    repo_root = repo_root.resolve()
    selections = []
    files: dict[str, str] = {}

    for source in sources:
        resolved_source = source.resolve()
        selections.append(
            {
                "kind": "file" if resolved_source.is_file() else "tree",
                "path": relative_to_repo(resolved_source, repo_root),
            }
        )
        for path in source_files(resolved_source):
            relative_path = relative_to_repo(path, repo_root)
            files[relative_path] = sha256(path)

    source_entries = [
        {"path": path, "sha256": digest} for path, digest in sorted(files.items())
    ]
    source_fingerprint = hashlib.sha256(
        json.dumps(source_entries, separators=(",", ":"), sort_keys=True).encode(
            "utf-8"
        )
    ).hexdigest()
    manifest = {
        "version": 1,
        "package": {
            "path": relative_to_repo(output, repo_root),
            "sha256": sha256(output),
        },
        "selection": {
            "excluded_components": sorted(EXCLUDED_SOURCE_COMPONENTS),
            "roots": sorted(selections, key=lambda item: (item["path"], item["kind"])),
        },
        "source_fingerprint": source_fingerprint,
        "sources": source_entries,
    }

    manifest_path = output.with_suffix(f"{output.suffix}.manifest.json")
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=manifest_path.parent,
        prefix=f".{manifest_path.name}.",
        suffix=".tmp",
        delete=False,
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)
        json.dump(manifest, temporary_file, indent=2, sort_keys=True)
        temporary_file.write("\n")

    try:
        temporary_path.replace(manifest_path)
    finally:
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    arguments = parse_args()
    project_path = arguments.project.resolve()
    build_path = arguments.build_dir.resolve()
    output_path = arguments.output.resolve()
    publish(project_path, build_path, arguments.runtime)
    package(build_path, output_path)

    if arguments.source:
        if arguments.repo_root is None:
            raise ValueError("--repo-root is required when --source is provided")
        write_package_manifest(
            output_path,
            arguments.repo_root.resolve(),
            [source.resolve() for source in arguments.source],
        )
