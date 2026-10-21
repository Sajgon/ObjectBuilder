"""Package a compiled build into a separate portable app with isolated preferences."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--air-sdk', type=Path, required=True)
parser.add_argument('--java-home', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
stage = repo / 'bin-release'
if args.output.exists():
    raise SystemExit('Refusing to overwrite an existing portable application directory.')
descriptor = (stage / 'ObjectBuilder-app.xml').read_text(encoding='utf-8-sig')
descriptor = descriptor.replace('<id>com.mignari.ObjectBuilder</id>', '<id>com.mignari.ObjectBuilder.SaveFix</id>')
descriptor = descriptor.replace('<name>Object Builder</name>', '<name>Object Builder Save Fix</name>')
pack_descriptor = stage / 'ObjectBuilder-SaveFix-app.xml'
pack_descriptor.write_text(descriptor, encoding='utf-8')

# A throwaway local AIR signing identity; no password is passed in process arguments.
# This is not an Authenticode signature or an upstream release signing certificate.
with tempfile.TemporaryDirectory(prefix='objectbuilder-sign-') as temp:
    keystore = Path(temp) / 'local-signing.p12'
    password = secrets.token_urlsafe(32)
    env = os.environ.copy()
    env['OBJECTBUILDER_SIGNING_PASSWORD'] = password
    subprocess.run([str(args.java_home/'bin/keytool.exe'), '-genkeypair', '-alias', 'savefix',
                    '-keyalg', 'RSA', '-keysize', '2048', '-sigalg', 'SHA256withRSA',
                    '-validity', '3650', '-dname', 'CN=Object Builder Local Save Fix',
                    '-ext', 'EKU=codeSigning', '-storetype', 'PKCS12', '-keystore', str(keystore),
                    '-storepass:env', 'OBJECTBUILDER_SIGNING_PASSWORD', '-noprompt'],
                   env=env, check=True)
    command = [str(args.java_home/'bin/java.exe'), '-jar', str(args.air_sdk/'lib/adt.jar'),
               '-package', '-storetype', 'pkcs12', '-keystore', str(keystore), '-tsa', 'none',
               '-target', 'bundle', str(args.output), str(pack_descriptor),
               'ObjectBuilder.swf', 'ObjectBuilderWorker.swf', 'config', 'icon']
    result = subprocess.run(command, cwd=stage, input=password+'\n'+password+'\n',
                            text=True, capture_output=True)
    print(result.stdout)
    print(result.stderr)
    if result.returncode:
        raise SystemExit(result.returncode)

shutil.copy2(repo/'LICENSE', args.output/'LICENSE')
if (repo/'SAVE-FIX.md').exists():
    shutil.copy2(repo/'SAVE-FIX.md', args.output/'SAVE-FIX.md')
manifest = {}
for filename in ['ObjectBuilder.exe','ObjectBuilder.swf','ObjectBuilderWorker.swf']:
    file = args.output/filename
    manifest[filename] = {'bytes': file.stat().st_size, 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()}
(args.output/'BUILD-HASHES.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('PACKAGED:', args.output)
