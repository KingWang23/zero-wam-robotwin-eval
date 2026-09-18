#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


VIDEO_NAME = re.compile(r"^(?P<episode>\d+)_(?P<prompt>.+)_(?:True|False)\.mp4$")


def build_manifest(visualization_root: Path) -> dict:
    tasks = {}
    for task_dir in sorted(path for path in visualization_root.iterdir() if path.is_dir()):
        prompts = {}
        for video_path in sorted(task_dir.glob("*.mp4")):
            match = VIDEO_NAME.match(video_path.name)
            if match is None:
                raise ValueError(f"Cannot parse video filename: {video_path}")
            episode = match.group("episode")
            prompt = match.group("prompt").replace("_", " ")
            if episode in prompts and prompts[episode] != prompt:
                raise ValueError(
                    f"Conflicting prompts for {task_dir.name} episode {episode}"
                )
            prompts[episode] = prompt
        if prompts:
            tasks[task_dir.name] = dict(
                sorted(prompts.items(), key=lambda item: int(item[0]))
            )
    return {
        "source": str(visualization_root.resolve()),
        "tasks": tasks,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Build an episode prompt manifest from RoboTwin videos."
    )
    parser.add_argument("visualization_root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    manifest = build_manifest(args.visualization_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    task_count = len(manifest["tasks"])
    prompt_count = sum(len(prompts) for prompts in manifest["tasks"].values())
    print(f"Wrote {prompt_count} prompts for {task_count} tasks to {args.output}")


if __name__ == "__main__":
    main()
