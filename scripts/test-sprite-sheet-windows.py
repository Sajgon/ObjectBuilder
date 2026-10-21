"""Run AIR sprite-sheet regression checks, optionally including a private 544x32 PNG."""
import argparse
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--air-sdk', type=Path, required=True)
parser.add_argument('--image', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = repo / 'bin-debug' / ('sprite-sheet-test-' + uuid.uuid4().hex)
output.mkdir()
command = [str(args.air_sdk / 'bin' / 'adl.exe'),
           str(repo / 'bin-debug' / 'SpriteSheetRegression-app.xml'), '--', str(output)]
if args.image:
    command.append(str(args.image.resolve(strict=True)))
with (output / 'stdout.log').open('w') as stdout, (output / 'stderr.log').open('w') as stderr:
    result = subprocess.run(command, cwd=repo, stdout=stdout, stderr=stderr,
                            timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
print('Test output:', output)
report = output / 'RESULT.txt'
text = report.read_text() if report.exists() else 'FAIL: missing result'
print(text)
if result.returncode or not text.startswith('PASS:'):
    print((output / 'stderr.log').read_text(errors='replace'))
    raise SystemExit(result.returncode or 1)
