#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOP_LEVEL_TOC_GLOB = "*/*.toc"
XML_REF_RE = re.compile(r"<\\s*(?:Script|Include)\\b[^>]*\\bfile\\s*=\\s*([\\"'])(.*?)\\1", re.IGNORECASE)
PLACEHOLDER_RE = re.compile(
    r"(?<!%)%(?!%)(?:\\d+\\$)?[-+ #0]*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?([cdeEfgGiouqsxX])"
)
CONFLICT_RE = re.compile(r"^(?:<<<<<<< |>>>>>>> |=======\\s*$)", re.MULTILINE)


class ValidationError(Exception):
    pass


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="strict")


def resolve_reference(owner: Path, raw_reference: str) -> Path:
    normalized = raw_reference.strip().replace("\\\\", "/")
    return (owner.parent / normalized).resolve()


def parse_toc_references(path: Path) -> list[str]:
    refs: list[str] = []
    for raw_line in read_text(path).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        refs.append(line)
    return refs


def parse_xml_references(path: Path) -> list[str]:
    return [match.group(2) for match in XML_REF_RE.finditer(read_text(path))]


def validate_reference(owner: Path, raw_reference: str) -> Path:
    target = resolve_reference(owner, raw_reference)
    try:
        target.relative_to(ROOT)
    except ValueError as exc:
        raise ValidationError(
            f"{rel(owner)} references a path outside the repository: {raw_reference}"
        ) from exc
    if not target.is_file():
        raise ValidationError(f"{rel(owner)} references missing file: {raw_reference}")
    return target


def collect_runtime_files() -> tuple[set[Path], set[Path]]:
    top_level_tocs = sorted(ROOT.glob(TOP_LEVEL_TOC_GLOB))
    if not top_level_tocs:
        raise ValidationError("No top-level addon .toc files found")

    visited_xml: set[Path] = set()
    runtime_files: set[Path] = set()
    loaded_lua: set[Path] = set()

    def visit(path: Path) -> None:
        path = path.resolve()
        runtime_files.add(path)
        suffix = path.suffix.lower()
        if suffix == ".lua":
            loaded_lua.add(path)
            return
        if suffix != ".xml" or path in visited_xml:
            return
        visited_xml.add(path)
        for reference in parse_xml_references(path):
            visit(validate_reference(path, reference))

    for toc in top_level_tocs:
        runtime_files.add(toc.resolve())
        for reference in parse_toc_references(toc):
            visit(validate_reference(toc, reference))

    return runtime_files, loaded_lua


def check_interface_versions() -> None:
    errors: list[str] = []
    for toc in sorted(ROOT.glob(TOP_LEVEL_TOC_GLOB)):
        interface = None
        for line in read_text(toc).splitlines():
            match = re.match(r"^\\s*##\\s*Interface\\s*:\\s*(\\d+)\\s*$", line)
            if match:
                interface = match.group(1)
                break
        if interface != "30300":
            errors.append(f"{rel(toc)} has Interface={interface!r}, expected '30300'")
    if errors:
        raise ValidationError("\n".join(errors))


def scan_all_manifest_references() -> None:
    errors: list[str] = []
    manifests = sorted(ROOT.rglob("*.toc")) + sorted(ROOT.rglob("*.xml"))
    for manifest in manifests:
        if ".git" in manifest.parts:
            continue
        references = (
            parse_toc_references(manifest)
            if manifest.suffix.lower() == ".toc"
            else parse_xml_references(manifest)
        )
        for reference in references:
            try:
                validate_reference(manifest, reference)
            except ValidationError as exc:
                errors.append(str(exc))
    if errors:
        raise ValidationError("\n".join(errors))


def parse_lua_string(text: str, start: int) -> tuple[str, int] | None:
    if start >= len(text) or text[start] not in {"\\\"", "'"}:
        return None
    quote = text[start]
    i = start + 1
    chars: list[str] = []
    while i < len(text):
        char = text[i]
        if char == "\\\\":
            if i + 1 >= len(text):
                return None
            chars.append(text[i : i + 2])
            i += 2
            continue
        if char == quote:
            return "".join(chars), i + 1
        chars.append(char)
        i += 1
    return None


def parse_locale_assignments(path: Path) -> dict[str, str]:
    text = read_text(path)
    result: dict[str, str] = {}
    pos = 0
    while True:
        start = text.find("L[", pos)
        if start < 0:
            break
        i = start + 2
        while i < len(text) and text[i].isspace():
            i += 1
        parsed_key = parse_lua_string(text, i)
        if not parsed_key:
            pos = start + 2
            continue
        key, i = parsed_key
        while i < len(text) and text[i].isspace():
            i += 1
        if i >= len(text) or text[i] != "]":
            pos = start + 2
            continue
        i += 1
        while i < len(text) and text[i].isspace():
            i += 1
        if i >= len(text) or text[i] != "=":
            pos = start + 2
            continue
        i += 1
        while i < len(text) and text[i].isspace():
            i += 1
        parsed_value = parse_lua_string(text, i)
        if not parsed_value:
            pos = start + 2
            continue
        value, end = parsed_value
        if key in result:
            raise ValidationError(f"{rel(path)} defines locale key twice: {key}")
        result[key] = value
        pos = end
    return result


def placeholders(value: str) -> tuple[str, ...]:
    return tuple(match.group(1) for match in PLACEHOLDER_RE.finditer(value))


def check_locale_placeholders() -> None:
    locale_dir = ROOT / "TradeSkillMaster" / "Locale"
    en_path = locale_dir / "enUS.lua"
    if not en_path.is_file():
        raise ValidationError("Missing TradeSkillMaster/Locale/enUS.lua")
    english = parse_locale_assignments(en_path)
    if not english:
        raise ValidationError("No locale assignments parsed from enUS.lua")

    errors: list[str] = []
    for path in sorted(locale_dir.glob("*.lua")):
        if path.name in {"Core.lua", "enUS.lua"}:
            continue
        values = parse_locale_assignments(path)
        for key, value in values.items():
            if key not in english:
                errors.append(f"{rel(path)} contains unknown locale key: {key}")
                continue
            expected = placeholders(english[key])
            actual = placeholders(value)
            if actual != expected:
                errors.append(
                    f"{rel(path)} placeholder mismatch for {key!r}: "
                    f"expected {expected}, got {actual}"
                )
    if errors:
        raise ValidationError("\n".join(errors))


def check_conflict_markers(runtime_files: set[Path]) -> None:
    errors: list[str] = []
    for path in sorted(runtime_files):
        if path.suffix.lower() not in {".lua", ".xml", ".toc"}:
            continue
        if CONFLICT_RE.search(read_text(path)):
            errors.append(f"{rel(path)} contains an unresolved merge-conflict marker")
    if errors:
        raise ValidationError("\n".join(errors))


def check_lua_syntax(loaded_lua: set[Path], luac: str) -> None:
    errors: list[str] = []
    for path in sorted(loaded_lua):
        proc = subprocess.run(
            [luac, "-p", str(path)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip()
            errors.append(f"{rel(path)}: {detail}")
    if errors:
        raise ValidationError("\n".join(errors))


def run_checks(luac: str) -> None:
    scan_all_manifest_references()
    runtime_files, loaded_lua = collect_runtime_files()
    check_interface_versions()
    check_locale_placeholders()
    check_conflict_markers(runtime_files)
    check_lua_syntax(loaded_lua, luac)

    print(f"OK: {len(runtime_files)} runtime files referenced by top-level addons")
    print(f"OK: {len(loaded_lua)} Lua files parse as Lua 5.1")
    print("OK: all TOC/XML references exist")
    print("OK: all top-level addon TOCs target Interface 30300")
    print("OK: locale format placeholders match enUS")
    print("OK: no merge-conflict markers in runtime files")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the TSM WotLK repository")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser("check", help="run all repository checks")
    check_parser.add_argument("--luac", required=True, help="path to a Lua 5.1 compiler")

    subparsers.add_parser("list-lua", help="print runtime-loaded Lua files")
    args = parser.parse_args()

    try:
        runtime_files, loaded_lua = collect_runtime_files()
        if args.command == "list-lua":
            for path in sorted(loaded_lua):
                print(rel(path))
            return 0
        run_checks(args.luac)
        return 0
    except (OSError, UnicodeError, ValidationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
