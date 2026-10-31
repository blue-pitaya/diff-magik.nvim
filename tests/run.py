import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC_DIR = ROOT / "tests" / "spec"
RUNNER = ROOT / "tests" / "runner.lua"
CASE_TIMEOUT = 60

GITCONFIG = """[user]
\tname = diff-magik tests
\temail = tests@diff-magik.invalid
[init]
\tdefaultBranch = master
[commit]
\tgpgsign = false
"""


def prepare_env(tmp):
    home = tmp / "home"
    dirs = {name: home / name for name in ("config", "data", "state", "cache", "tmp")}
    for path in dirs.values():
        path.mkdir(parents=True)

    gitconfig = home / "gitconfig"
    gitconfig.write_text(GITCONFIG)

    env = dict(os.environ)
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(dirs["config"]),
            "XDG_DATA_HOME": str(dirs["data"]),
            "XDG_STATE_HOME": str(dirs["state"]),
            "XDG_CACHE_HOME": str(dirs["cache"]),
            "TMPDIR": str(dirs["tmp"]),
            "GIT_CONFIG_GLOBAL": str(gitconfig),
            "GIT_CONFIG_NOSYSTEM": "1",
        }
    )
    return env


def nvim(env, *args):
    return subprocess.run(
        ["nvim", "--headless", "--clean", "-l", str(RUNNER), *args],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=CASE_TIMEOUT,
    )


def output_of(result):
    return textwrap.indent((result.stdout + result.stderr).rstrip(), "    ")


if __name__ == "__main__":
    missing = [tool for tool in ("nvim", "git") if shutil.which(tool) is None]
    if missing:
        print(f"Cannot run the tests, {', '.join(missing)} is not on PATH.")
        sys.exit(2)

    filters = sys.argv[1:]
    specs = sorted(SPEC_DIR.glob("*_spec.lua"))
    if filters:
        specs = [spec for spec in specs if any(f in spec.stem for f in filters)]

    passed = 0
    failed = 0

    with tempfile.TemporaryDirectory(prefix="diff-magik-tests-") as tmp:
        env = prepare_env(Path(tmp))

        for spec in specs:
            listing = nvim(env, str(spec))
            if listing.returncode != 0:
                failed += 1
                print(f"{spec.stem} failed to load:")
                print(output_of(listing))
                continue

            for case in listing.stdout.splitlines():
                try:
                    result = nvim(env, str(spec), case)
                except subprocess.TimeoutExpired:
                    failed += 1
                    print(f"{spec.stem}: {case} timed out after {CASE_TIMEOUT}s")
                    continue

                if result.returncode == 0:
                    passed += 1
                    print(f"{spec.stem}: {case} passed")
                else:
                    failed += 1
                    print(f"{spec.stem}: {case} failed:")
                    print(output_of(result))

    print(f"{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
