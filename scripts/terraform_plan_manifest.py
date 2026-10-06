#!/usr/bin/env python3
"""Create or verify the artifact manifest for a saved production plan."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

from check_lambda_package import verify_package


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_to_repo(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root).as_posix()
    except ValueError as error:
        raise ValueError(f"Artifact is outside the repository: {path}") from error


def safe_repo_path(repo_root: Path, relative_path: str) -> Path:
    candidate = (repo_root / relative_path).resolve()
    try:
        candidate.relative_to(repo_root)
    except ValueError as error:
        raise ValueError(
            f"Manifest path escapes the repository: {relative_path}"
        ) from error
    return candidate


def plan_manifest_path(plan_path: Path) -> Path:
    return plan_path.with_suffix(f"{plan_path.suffix}.manifest.json")


def package_record(repo_root: Path, package_manifest_path: Path) -> dict[str, str]:
    package_manifest_path = package_manifest_path.resolve()
    if not package_manifest_path.is_file():
        raise FileNotFoundError(f"Missing package manifest: {package_manifest_path}")

    package_manifest = json.loads(package_manifest_path.read_text(encoding="utf-8"))
    package_path = safe_repo_path(
        repo_root, package_manifest.get("package", {}).get("path", "")
    )
    fresh, reason, verified_manifest = verify_package(
        repo_root, package_path, package_manifest_path
    )
    if not fresh or verified_manifest is None:
        raise ValueError(f"Package is not ready for planning: {reason}")

    return {
        "manifest_path": relative_to_repo(package_manifest_path, repo_root),
        "manifest_sha256": sha256(package_manifest_path),
        "package_path": relative_to_repo(package_path, repo_root),
        "package_sha256": sha256(package_path),
        "source_fingerprint": verified_manifest["source_fingerprint"],
    }


def create_manifest(
    repo_root: Path,
    terraform_root: Path,
    plan_path: Path,
    package_manifests: list[Path],
) -> None:
    if not plan_path.is_file():
        raise FileNotFoundError(f"Saved production plan does not exist: {plan_path}")

    manifest = {
        "version": 1,
        "stage": "prod",
        "terraform_root": relative_to_repo(terraform_root, repo_root),
        "plan": {
            "path": relative_to_repo(plan_path, repo_root),
            "sha256": sha256(plan_path),
        },
        "packages": sorted(
            [package_record(repo_root, path) for path in package_manifests],
            key=lambda item: item["manifest_path"],
        ),
    }

    output = plan_manifest_path(plan_path)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=output.parent,
        prefix=f".{output.name}.",
        suffix=".tmp",
        delete=False,
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)
        json.dump(manifest, temporary_file, indent=2, sort_keys=True)
        temporary_file.write("\n")

    try:
        temporary_path.replace(output)
    finally:
        temporary_path.unlink(missing_ok=True)


def verify_manifest(
    repo_root: Path,
    terraform_root: Path,
    plan_path: Path,
    package_manifests: list[Path],
) -> None:
    manifest_path = plan_manifest_path(plan_path)
    if not manifest_path.is_file():
        raise FileNotFoundError(
            f"Saved production plan manifest does not exist: {manifest_path}"
        )

    manifest: dict[str, Any] = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("version") != 1 or manifest.get("stage") != "prod":
        raise ValueError("Saved production plan manifest has an unsupported format")
    if manifest.get("terraform_root") != relative_to_repo(terraform_root, repo_root):
        raise ValueError("Saved production plan belongs to a different Terraform root")

    recorded_plan = manifest.get("plan", {})
    if safe_repo_path(repo_root, recorded_plan.get("path", "")) != plan_path:
        raise ValueError("Saved production plan path differs from its manifest")
    if not plan_path.is_file() or sha256(plan_path) != recorded_plan.get("sha256"):
        raise ValueError("Saved production plan content differs from its manifest")

    expected_manifest_paths = sorted(
        relative_to_repo(path, repo_root) for path in package_manifests
    )
    recorded_packages = manifest.get("packages", [])
    recorded_manifest_paths = sorted(
        package.get("manifest_path", "") for package in recorded_packages
    )
    if expected_manifest_paths != recorded_manifest_paths:
        raise ValueError("Saved production plan package set differs from its manifest")

    for package in recorded_packages:
        package_manifest_path = safe_repo_path(
            repo_root, package.get("manifest_path", "")
        )
        package_path = safe_repo_path(repo_root, package.get("package_path", ""))
        if sha256(package_manifest_path) != package.get("manifest_sha256"):
            raise ValueError(
                f"Package manifest changed after planning: {package_manifest_path}"
            )
        if sha256(package_path) != package.get("package_sha256"):
            raise ValueError(f"Package changed after planning: {package_path}")

        fresh, reason, package_manifest = verify_package(
            repo_root, package_path, package_manifest_path
        )
        if not fresh or package_manifest is None:
            raise ValueError(f"Package source inputs changed after planning: {reason}")
        if package_manifest.get("source_fingerprint") != package.get(
            "source_fingerprint"
        ):
            raise ValueError(
                f"Package source fingerprint changed after planning: {package_path}"
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("create", "verify"))
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--terraform-root", required=True, type=Path)
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--package-manifest", action="append", default=[], type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    terraform_root = args.terraform_root.resolve()
    plan_path = args.plan.resolve()
    package_manifests = [path.resolve() for path in args.package_manifest]

    try:
        if args.action == "create":
            create_manifest(repo_root, terraform_root, plan_path, package_manifests)
        else:
            verify_manifest(repo_root, terraform_root, plan_path, package_manifests)
    except (
        FileNotFoundError,
        KeyError,
        TypeError,
        ValueError,
        json.JSONDecodeError,
    ) as error:
        print(f"Production plan validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
