"""Installer regression: optional daemon dyld failure must not break dpkg."""
from pathlib import Path
import tempfile,subprocess
src=(Path(__file__).resolve().parents[1]/'layout/DEBIAN/postinst').read_text()
with tempfile.TemporaryDirectory() as d:
 root=Path(d)
 for relative in ('usr/libexec','Library/LaunchDaemons','bin'):
  (root/relative).mkdir(parents=True,exist_ok=True)
 log=root/'calls'
 original=root/'usr/libexec/memtrimd'
 extra=root/'usr/libexec/memtrim-autorecovery'
 launch=root/'bin/launchctl'
 original.write_text('#!/bin/sh\necho original >> "'+str(log)+'"\n')
 extra.write_text('#!/bin/sh\necho broken-companion >> "'+str(log)+'"\nexit 134\n')
 launch.write_text('#!/bin/sh\necho "$*" >> "'+str(log)+'"\nexit 0\n')
 for f in (original,extra,launch): f.chmod(0o755)
 for label in ('com.crctdd.memtrim.daemon','com.crctdd.memtrim.autorecovery'):
  (root/'Library/LaunchDaemons'/f'{label}.plist').touch()
 script=root/'postinst'
 # Mock both absolute paths and runtime directory, no calls to installed system.
 script.write_text(src.replace("prefix=''",f"prefix='{root}'").replace("launchctl='/bin/launchctl'",f"launchctl='{launch}'"))
 proc=subprocess.run(['sh',str(script),'configure'],capture_output=True,text=True)
 assert proc.returncode==0,(proc.returncode,proc.stderr)
 calls=log.read_text().splitlines()
 assert calls.index('original')<calls.index('broken-companion')
 assert any('bootstrap ' in x and 'memtrim.daemon' in x for x in calls)
 assert not any('bootstrap ' in x and 'memtrim.autorecovery' in x for x in calls)
print('PASS: optional daemon load failure does not interrupt dpkg or disable original service')
