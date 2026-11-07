#!/usr/bin/env python3
"""Collects the notices for everything bundled into the Windows exe: the .NET runtime pack,
every NuGet package in the published app (Avalonia, SkiaSharp, NAudio…), the Lucide icons,
the Noto Serif SC font and NSIS."""
from pathlib import Path
import json
import re
import shutil
import sys

root = Path(__file__).resolve().parent.parent
rid = sys.argv[1] if len(sys.argv) > 1 else "win-x64"
project = root / "Windows/Crumple.Desktop"
assets = json.loads((project / "obj/project.assets.json").read_text())
packages = [Path(p) for p in assets["packageFolders"]]
output = root / "build/releases/windows"
output.mkdir(parents=True, exist_ok=True)
notices = ["Crumple for Windows — bundled component notices\n"]


def package_folder(name, version):
    relative = name.lower() + "/" + version
    return next((base / relative for base in packages if (base / relative).is_dir()), None)


def section(title, url, text):
    notices.append("\n" + "=" * 72 + "\n" + title + ("\n" + url if url else "") + "\n\n" + text.strip() + "\n")


# The .NET runtime that is published inside the exe.
runtime = f"Microsoft.NETCore.App.Runtime.{rid}"
dependency = next(d for framework in assets["project"]["frameworks"].values()
                  for d in framework.get("downloadDependencies", []) if d["name"].lower() == runtime.lower())
version = dependency["version"].strip("[]").split(",")[0].strip()
folder = package_folder(runtime, version)
for candidate in ["LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT"]:
    if folder and (folder / candidate).exists():
        section(f"{runtime} {version} — {candidate}", "https://github.com/dotnet", (folder / candidate).read_text(encoding="utf-8-sig"))

# Every package that ends up in the app for this runtime.
target = next(v for k, v in assets["targets"].items() if k.endswith("/" + rid))
for key, info in sorted(target.items()):
    if info.get("type") != "package":
        continue
    name, version = key.split("/")
    folder = package_folder(name, version)
    if folder is None:
        continue
    nuspec = next(folder.glob("*.nuspec"), None)
    meta = nuspec.read_text(encoding="utf-8-sig") if nuspec else ""
    licence = re.search(r'<license type="expression">([^<]+)</license>', meta)
    url = re.search(r"<projectUrl>([^<]+)</projectUrl>", meta)
    files = [p for p in folder.iterdir() if p.is_file() and re.match(r"(?i)(license|licence|copying)(\.(txt|md))?$", p.name)]
    text = files[0].read_text(encoding="utf-8-sig", errors="replace") if files else f"Licensed under {licence.group(1) if licence else 'its stated licence'}."
    section(f"{name} {version}" + (f" — {licence.group(1)}" if licence else ""), url.group(1) if url else "", text)

for name, title, url in [("Lucide-ISC.txt", "Lucide icons", "https://lucide.dev"),
                         ("NotoSerifSC-OFL.txt", "Noto Serif SC", "https://github.com/notofonts/noto-cjk")]:
    section(title, url, (project / "Assets/Licenses" / name).read_text(encoding="utf-8"))
nsis_notice = root / "build/windows-tools/nsis-3.13/COPYING"
if nsis_notice.exists():
    section("NSIS 3.13 (installer)", "https://nsis.sourceforge.io", nsis_notice.read_text(encoding="utf-8-sig"))
(output / "THIRD-PARTY-NOTICES.txt").write_text("\n".join(notices), encoding="utf-8")
shutil.copyfile(root / "Windows/installer/README.txt", output / "README.txt")
print(f"Packaged notices for {len(notices) - 1} components and the bilingual instructions.")
