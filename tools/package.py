"""Builds the release zip of the addon (everbuff-wow-addon #3; CONVENTIONS "Lua addon"): `EverbuffJournal-<version>.zip`
holding the `EverbuffJournal/` folder with the TOC, only the files the TOC loads, and `media/`. The version comes
from the TOC only. With `--tag v<version>` it also checks that the tag and the TOC agree.

    python tools/package.py                      # -> dist/EverbuffJournal-<version>.zip
    python tools/package.py --tag v0.9.3 --out dist
"""
import argparse
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Everbuff")
TOC = "EverbuffJournal.toc"
FOLDER = "EverbuffJournal"


def toc_files_and_version():
    files, version = [], None
    with open(os.path.join(SRC, TOC), encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("## Version:"):
                version = line.split(":", 1)[1].strip()
            elif line and not line.startswith("#"):
                files.append(line.replace("\\", "/"))
    if not version:
        sys.exit(f"{TOC} has no ## Version line")
    missing = [f for f in files if not os.path.isfile(os.path.join(SRC, f))]
    if missing:
        sys.exit(f"{TOC} loads files that do not exist: {missing}")
    return files, version


def build(out_dir, tag=None):
    files, version = toc_files_and_version()
    if tag is not None and tag != f"v{version}":
        sys.exit(f"tag {tag} does not match the TOC version v{version}")
    entries = [TOC] + files
    media = os.path.join(SRC, "media")
    for d, _, names in os.walk(media):
        for n in sorted(names):
            entries.append(os.path.relpath(os.path.join(d, n), SRC).replace("\\", "/"))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{FOLDER}-{version}.zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for e in sorted(set(entries)):
            with open(os.path.join(SRC, e), "rb") as f:
                data = f.read()
            if e.lower().endswith((".lua", ".toc", ".txt", ".xml")):
                data = data.replace(b"\r\n", b"\n")  # LF on every OS, so a local build equals the CI build
            z.writestr(f"{FOLDER}/{e}", data)
    return path, version, sorted(set(entries))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--tag", help="the release tag, checked against the TOC version")
    a = ap.parse_args()
    path, version, entries = build(a.out, a.tag)
    print(f"{path}: {len(entries)} files, version {version}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
            f.write(f"zip={path}\nversion={version}\n")


if __name__ == "__main__":
    main()
