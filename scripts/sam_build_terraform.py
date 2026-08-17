#!/usr/bin/env python3
"""Run the native SAM Terraform hook in an isolated, build-only workspace."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

GENERATED_DIRECTORIES = (".aws-sam", ".aws-sam-iacs")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a Terraform-defined SAM application without using its configured "
            "remote backend or AWS credentials."
        )
    )
    parser.add_argument("--terraform-project-root", required=True, type=Path)
    parser.add_argument("--sam-command", default="sam")
    return parser.parse_args()


def create_terraform_shim(
    shim_path: Path, terraform_executable: str, terraform_data: Path
) -> None:
    shim_path.write_text(
        "#!/usr/bin/env python3\n"
        "import hashlib\n"
        "import os\n"
        "import subprocess\n"
        "import sys\n"
        "from pathlib import Path\n"
        f"terraform_data = Path({str(terraform_data)!r})\n"
        "working_directory = os.getcwd().encode('utf-8')\n"
        "data_directory = terraform_data / hashlib.sha256(working_directory).hexdigest()\n"
        "os.environ['TF_DATA_DIR'] = str(data_directory)\n"
        "arguments = sys.argv[1:]\n"
        "command = arguments[0] if arguments else ''\n"
        "allowed_commands = {'init', 'plan', 'show', 'version'}\n"
        "if command == 'apply':\n"
        "    targets = [value.split('=', 1)[1] for value in arguments if value.startswith('-target=')]\n"
        "    for index, value in enumerate(arguments[:-1]):\n"
        "        if value == '-target':\n"
        "            targets.append(arguments[index + 1])\n"
        "    if len(targets) != 1 or not targets[0].startswith('null_resource.sam_metadata_'):\n"
        "        print('Blocked non-metadata Terraform apply during SAM build', file=sys.stderr)\n"
        "        raise SystemExit(2)\n"
        "elif command not in allowed_commands:\n"
        "    print(f'Blocked unexpected Terraform command during SAM build: {command}', file=sys.stderr)\n"
        "    raise SystemExit(2)\n"
        "executable_arguments = [" + repr(terraform_executable) + ", *arguments]\n"
        "raise SystemExit(subprocess.call(executable_arguments))\n",
        encoding="utf-8",
    )
    shim_path.chmod(0o755)


def copy_generated_directories(workspace: Path, project_root: Path) -> None:
    for directory_name in GENERATED_DIRECTORIES:
        source = workspace / directory_name
        if not source.is_dir():
            raise FileNotFoundError(f"SAM did not generate expected directory: {source}")
        destination = project_root / directory_name
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(source, destination)


def build(terraform_project_root: Path, sam_command: str) -> None:
    project_root = terraform_project_root.resolve()
    if not project_root.is_dir():
        raise NotADirectoryError(f"Terraform project root does not exist: {project_root}")

    terraform_executable = shutil.which("terraform")
    if terraform_executable is None:
        raise FileNotFoundError("The SAM Terraform hook requires Terraform")

    with tempfile.TemporaryDirectory(prefix="sam-terraform-") as temporary_directory:
        temporary_path = Path(temporary_directory)
        workspace = temporary_path / "project"
        shutil.copytree(
            project_root,
            workspace,
            ignore=shutil.ignore_patterns(
                ".terraform",
                ".aws-sam",
                ".aws-sam-iacs",
                "*.tfstate",
                "*.tfstate.*",
                "*_override.tf",
                "*_override.tf.json",
            ),
        )

        backend_state = temporary_path / "prepare.tfstate"
        (workspace / "z_samcli_backend_override.tf").write_text(
            "terraform {\n"
            '  backend "local" {\n'
            f'    path = "{backend_state.as_posix()}"\n'
            "  }\n"
            "}\n",
            encoding="utf-8",
        )

        shim_directory = temporary_path / "bin"
        shim_directory.mkdir()
        create_terraform_shim(
            shim_directory / "terraform",
            terraform_executable,
            temporary_path / "terraform-data",
        )

        environment = os.environ.copy()
        for variable in (
            "AWS_PROFILE",
            "AWS_SESSION_TOKEN",
            "TF_CLI_ARGS",
            "TF_CLI_ARGS_plan",
            "TF_CLI_ARGS_apply",
            "TF_CLI_ARGS_init",
            "TF_DATA_DIR",
        ):
            environment.pop(variable, None)
        environment.update(
            {
                "AWS_ACCESS_KEY_ID": "sam-build",
                "AWS_SECRET_ACCESS_KEY": "sam-build",
                "AWS_EC2_METADATA_DISABLED": "true",
                "PATH": f"{shim_directory}{os.pathsep}{environment['PATH']}",
                "TF_CLI_ARGS_init": "-reconfigure -input=false",
                "TF_IN_AUTOMATION": "1",
            }
        )

        subprocess.run(
            [sam_command, "build", "--hook-name", "terraform"],
            cwd=workspace,
            env=environment,
            check=True,
        )
        copy_generated_directories(workspace, project_root)


if __name__ == "__main__":
    arguments = parse_args()
    build(
        arguments.terraform_project_root,
        arguments.sam_command,
    )
