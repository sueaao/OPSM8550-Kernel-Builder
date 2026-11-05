#!/usr/bin/env python3
"""Exercise six-job metadata and release staging with identical source commits."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

scripts = Path(__file__).resolve().parents[1]
roots = ("SukiSU-Ultra-with-susfs-nomount-KPM", "BakaSU-with-susfs-nomount", "KernelSU-Next-with-susfs-nomount")


def read_env(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines())


def checksums(package):
    files = [*package.glob("*.zip"), *package.glob("Image-*"), package / "build-info.json"]
    (package / "SHA256SUMS").write_text("".join(
        f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n" for file in files))


with tempfile.TemporaryDirectory() as temporary:
    fixture = Path(temporary)
    packages = fixture / "packages"
    packages.mkdir()
    env = dict(os.environ, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1", RUNNER_OS="Linux",
               SOC="sm8650", SOURCE_SLUG="crdroid", PROFILE_ID="sm8650-oneplus12-crdroid",
               ROM_GKI_MODULE_COMPAT="0", ANDROID_BATCH_BUILD="1")
    names, diagnostics, caches = set(), set(), set()
    for root in roots:
        for android in ("16", "17"):
            metadata = fixture / "env"
            output = fixture / "output"
            metadata.unlink(missing_ok=True)
            output.unlink(missing_ok=True)
            env.update(KSU_TYPE=root, KERNEL_BRANCH=f"{android}.0", SUPPORTED_ANDROID_VERSIONS=android,
                       CLANG_VERSION="clang-r563880c" if android == "16" else "clang-r584948",
                       GITHUB_ENV=str(metadata), GITHUB_OUTPUT=str(output))
            subprocess.run(["bash", str(scripts / "set-build-metadata.sh")], env=env, check=True)
            values = read_env(metadata)
            name = values["ARTIFACT_NAME"]
            assert name.endswith(f"-{root}-A{android}")
            assert read_env(output)["artifact_name"] == name
            names.add(name)
            diagnostics.add(values["DIAGNOSTICS_NAME"])
            caches.add(values["CCACHE_KEY_PREFIX"])
            package = packages / name
            package.mkdir()
            # A16/A17 can have identical kernel commits and timestamps. The
            # Android label must still preserve both ZIPs, Images and manifests.
            stem = f"profile_{root}_111111111111_20261105_000000_A{android}"
            info = {"supported_android_versions": android, "root_solution": root,
                    "kernel_commit": "1" * 40, "android_batch_build": True}
            (package / "build-info.json").write_text(json.dumps(info))
            (package / f"Image-{stem}").write_bytes(b"same kernel source commit")
            with zipfile.ZipFile(package / f"{stem}.zip", "w") as archive:
                archive.write(package / "build-info.json", "build-info.json")
            (package / "release-notes.md").write_text(f"## Build profile\n\nAndroid target: {android}\n")
            checksums(package)
    assert len(names) == len(diagnostics) == len(caches) == 6

    # Non-batch callers keep their previous artifact names. Invalid batch
    # versions fail before exporting metadata to another workflow step.
    metadata.unlink()
    env.update(ANDROID_BATCH_BUILD="0")
    subprocess.run(["bash", str(scripts / "set-build-metadata.sh")], env=env, check=True)
    assert read_env(metadata)["ARTIFACT_NAME"] == f"kernel-package-123-1-{roots[-1]}"
    metadata.unlink()
    env.update(ANDROID_BATCH_BUILD="1", SUPPORTED_ANDROID_VERSIONS="15")
    invalid = subprocess.run(["bash", str(scripts / "set-build-metadata.sh")], env=env, capture_output=True)
    assert invalid.returncode != 0 and not metadata.exists()

    assets = fixture / "assets"
    subprocess.run(["bash", str(scripts / "stage-release-assets.sh"), str(packages), str(assets)],
                   env=env, check=True, stdout=subprocess.DEVNULL)
    assert len(list(assets.glob("*.zip"))) == len(list(assets.glob("Image-*"))) == 6
    assert len(list(assets.glob("build-info-*.json"))) == len(list(assets.glob("SHA256SUMS-*"))) == 6
    for name in names:
        variant = name.removeprefix("kernel-package-123-1-")
        info = json.loads((assets / f"build-info-{variant}.json").read_text())
        assert variant.endswith(f'-A{info["supported_android_versions"]}')
        assert f"## {variant}\n" in (assets / "release-notes.md").read_text()
        subprocess.run(["sha256sum", "--check", f"SHA256SUMS-{variant}"], cwd=assets,
                       check=True, stdout=subprocess.DEVNULL)

    corrupt = fixture / "corrupt"
    shutil.copytree(packages, corrupt)
    next(corrupt.glob("*/Image-*")).write_bytes(b"corrupted Image")
    result = subprocess.run(["bash", str(scripts / "stage-release-assets.sh"), str(corrupt), str(fixture / "bad-assets")],
                            env=env, capture_output=True)
    assert result.returncode != 0

    collisions = fixture / "collisions"
    for package in list(packages.iterdir())[:2]:
        target = collisions / package.name
        shutil.copytree(package, target)
        next(target.glob("*.zip")).rename(target / "duplicate.zip")
        checksums(target)
    result = subprocess.run(["bash", str(scripts / "stage-release-assets.sh"), str(collisions), str(fixture / "collision-assets")],
                            env=env, capture_output=True)
    assert result.returncode != 0 and b"name collision" in result.stdout

print("PASS: A16/A17 metadata, six-variant release staging, integrity checks, and collision rejection")
