#!/usr/bin/env python3
"""Publish a .NET Lambda project and create a deterministic deployment zip."""

from __future__ import annotations

import argparse
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Publish a .NET Lambda project and package its output."
    )
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runtime", default="linux-x64")
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
            for source in sorted(path for path in build_dir.rglob("*") if path.is_file()):
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


if __name__ == "__main__":
    arguments = parse_args()
    publish(
        arguments.project.resolve(), arguments.build_dir.resolve(), arguments.runtime
    )
    package(arguments.build_dir.resolve(), arguments.output.resolve())
