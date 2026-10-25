"""Package this fork's addon folders as the rolling Latest release ZIP.

Each --addon names a folder of the checkout, its TOC and the folder name inside
WoW's Interface/AddOns. Files the TOC or its XML loads are always kept; other
files stay unless they are known development material (repository metadata,
tests, docs and tooling), because addons may load Lua, textures and fonts
dynamically. Every folder gets SOURCE_REVISION.txt with the packaged commit.
The selection matches mod-playerbots-portable's cmake/AddonRuntime.py.
"""
from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile


DEVELOPMENT_METADATA = {".git", ".github", ".vscode", ".idea"}
DEVELOPMENT_DIRECTORIES = {"docs", "tests"}
DEVELOPMENT_FILES = {".portable-source", ".editorconfig", ".gitignore", ".gitattributes", ".luacheckrc",
                     ".coderabbit.yaml", "stylua.toml", "build-addon.sh", "agents.md", "contributing.md",
                     "code_of_conduct.md", "todo.md", "changelog.md"}
FIXED_TIME = (2026, 1, 1, 0, 0, 0)


def development_path(relative: str) -> bool:
    path = PurePosixPath(relative)
    return (any(part.casefold() in DEVELOPMENT_METADATA for part in path.parts)
            or path.parts[0].casefold() in DEVELOPMENT_DIRECTORIES
            or path.name.casefold() in DEVELOPMENT_FILES
            or re.fullmatch(r"test_.*\.lua", path.name, re.IGNORECASE) is not None)


def safe_relative(value: str) -> str:
    value = value.replace("\\", "/")
    if (not value or value.startswith("/") or ":" in value
            or any(part in ("", ".", "..") for part in value.split("/"))):
        raise ValueError(f"Unsafe addon asset path: {value!r}")
    return value


def tracked_files(checkout: Path, folder: str) -> dict[str, Path]:
    """Committed files below folder; untracked build output never reaches the ZIP."""
    listed = subprocess.run(["git", "-C", str(checkout), "ls-files", "-z", "--", folder],
                            check=True, capture_output=True).stdout.decode("utf-8").split("\0")
    base = PurePosixPath(folder) if folder != "." else PurePosixPath()
    files, folded = {}, set()
    for name in filter(None, listed):
        path = checkout / name
        if path.is_symlink():
            raise ValueError(f"Symbolic link in addon: {name}")
        relative = safe_relative(PurePosixPath(name).relative_to(base).as_posix())
        if relative.casefold() in folded:
            raise ValueError(f"Case-colliding addon asset: {relative}")
        folded.add(relative.casefold())
        files[relative] = path
    return files


def runtime_paths(files: dict[str, Path], toc: str) -> list[str]:
    toc = safe_relative(toc)
    if toc not in files:
        raise ValueError(f"Missing addon TOC: {toc}")
    text = files[toc].read_text(encoding="utf-8-sig")
    interfaces = re.findall(r"(?m)^##[ \t]*Interface[ \t]*:[ \t]*(\d+)[ \t]*\r?$", text)
    if interfaces != ["30300"]:
        raise ValueError(f"{toc} must declare the WoW 3.3.5a interface 30300 exactly once")
    protected, pending = {toc}, []
    for line in text.splitlines():
        value = line.strip()
        if not value or value.startswith("#"):
            continue
        relative = safe_relative(value)
        if relative not in files:
            raise ValueError(f"Missing addon TOC asset: {relative}")
        protected.add(relative)
        if relative.lower().endswith(".xml"):
            pending.append(relative)
    visited = set()
    while pending:
        relative = pending.pop()
        if relative in visited:
            continue
        visited.add(relative)
        try:
            document = ET.fromstring(files[relative].read_bytes())
        except ET.ParseError as error:
            raise ValueError(f"Invalid addon XML: {relative}: {error}") from None
        for node in document.iter():
            if node.tag.rsplit("}", 1)[-1] not in ("Script", "Include") or "file" not in node.attrib:
                continue
            value = node.attrib["file"].replace("\\", "/")
            if value.startswith("/") or ":" in value:
                raise ValueError(f"Unsafe addon XML include: {relative}: {value}")
            if value.startswith("Interface/"):
                prefix = f"Interface/AddOns/{PurePosixPath(toc).stem}/"
                if not value.startswith(prefix):
                    continue  # Shared Blizzard or other-addon includes are not local assets.
                candidate = value[len(prefix):]
            else:
                parts = list(PurePosixPath(relative).parent.parts)
                for part in value.split("/"):
                    if part == "..":
                        if not parts:
                            raise ValueError(f"Escaping addon XML include: {relative}: {value}")
                        parts.pop()
                    elif part not in ("", "."):
                        parts.append(part)
                candidate = "/".join(parts)
            candidate = safe_relative(candidate)
            if candidate not in files:
                raise ValueError(f"Missing addon XML asset: {relative}: {candidate}")
            protected.add(candidate)
            if candidate.lower().endswith(".xml"):
                pending.append(candidate)
    return [relative for relative in files if relative in protected or not development_path(relative)]


def package(checkout: Path, addons: list[tuple[str, str, str]], extras: list[tuple[str, str]], output: Path) -> None:
    revision = subprocess.run(["git", "-C", str(checkout), "rev-parse", "HEAD"], check=True,
                              capture_output=True, text=True).stdout.strip()
    entries: dict[str, bytes] = {}
    for folder, toc, name in addons:
        files = tracked_files(checkout, folder)
        for relative in runtime_paths(files, toc):
            entries[f"{name}/{relative}"] = files[relative].read_bytes()
        entries[f"{name}/SOURCE_REVISION.txt"] = (revision + "\n").encode("ascii")
    for source, target in extras:
        entries[safe_relative(target)] = (checkout / safe_relative(source)).read_bytes()
    temporary = output.with_suffix(".zip.tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in sorted(entries.items()):
            entry = zipfile.ZipInfo(name, FIXED_TIME)
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, content)
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None or sorted(archive.namelist()) != sorted(entries):
            raise ValueError("The packaged ZIP differs from its inputs")
    temporary.replace(output)
    print(f"Packaged {output.name}: {len(entries)} files from {revision}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, default=Path("."))
    parser.add_argument("--addon", action="append", required=True, metavar="FOLDER:TOC:NAME",
                        help="addon folder in the checkout, its TOC and the installed folder name")
    parser.add_argument("--extra", action="append", default=[], metavar="SOURCE:TARGET",
                        help="additional committed file and its path in the ZIP, such as a license")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    addons = [tuple(value.split(":", 2)) for value in args.addon]
    extras = [tuple(value.split(":", 1)) for value in args.extra]
    if any(len(value) != 3 for value in addons) or any(len(value) != 2 for value in extras):
        parser.error("--addon takes FOLDER:TOC:NAME and --extra takes SOURCE:TARGET")
    package(args.checkout.resolve(), addons, extras, args.output.resolve())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Packaging failed: {error}") from None
