#!/usr/bin/env python3
from pathlib import Path

import mplib
import sapien


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        print(f"Already patched: {path}")
        return
    if old not in text:
        raise RuntimeError(f"Expected source text not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Patched: {path}")


sapien_root = Path(sapien.__file__).resolve().parent
replace_once(
    sapien_root / "wrapper" / "urdf_loader.py",
    'with open(urdf_file, "r") as f:',
    'with open(urdf_file, "r", encoding="utf-8") as f:',
)
replace_once(
    sapien_root / "wrapper" / "urdf_loader.py",
    'with open(srdf_file, "r") as f:',
    'with open(srdf_file, "r", encoding="utf-8") as f:',
)

mplib_root = Path(mplib.__file__).resolve().parent
replace_once(
    mplib_root / "planner.py",
    "if np.linalg.norm(delta_twist) < 1e-4 or collide or not within_joint_limit:",
    "if np.linalg.norm(delta_twist) < 1e-4 or not within_joint_limit:",
)
