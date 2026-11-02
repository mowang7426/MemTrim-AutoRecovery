from pathlib import Path
import hashlib,json,plistlib,subprocess
p=Path(__file__).resolve().parents[1]
for name,digest in json.loads((p/'tests/original-sha256.json').read_text()).items():
 f=p/'layout'/name
 assert f.is_file(),name
 assert hashlib.sha256(f.read_bytes()).hexdigest()==digest,name
for name in ['LaunchDaemons','MobileSubstrate','PreferenceBundles','PreferenceLoader']:
 assert not (p/'layout'/name).exists(),name
for f in p.rglob('*.plist'):
 if '.theos' not in str(f): plistlib.loads(f.read_bytes())
for name in ['postinst','prerm']:
 f=p/'layout/DEBIAN'/name
 subprocess.run(['sh','-n',str(f)],check=True)
 assert f.stat().st_mode&0o111,name
launch=plistlib.loads((p/'layout/Library/LaunchDaemons/com.crctdd.memtrim.autorecovery.plist').read_bytes())
assert launch['UserName']=='root' and launch['GroupName']=='wheel'
assert launch['ProgramArguments']==['/usr/libexec/memtrim-autorecovery']
items=plistlib.loads((p/'Prefs/Resources/Root.plist').read_bytes())
switch=[x for x in items if x['cell']=='PSSwitchCell'][0]
assert switch['default'] is False and switch['defaults']=='com.local.memtrim.autorecovery'
main=(p/'AutoRecovery/main.m').read_text()
assert 'system(' not in main and 'posix_spawn' not in main and 'kill(' not in main
assert main.index('MTARReady=MTARPersist(wall);',main.index('if(!ready) return;'))<main.index('notify_post("com.crctdd.memtrim.request.deep")')
assert 'sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&len,NULL,0)' in main
print('PASS: original payload hashes, canonical layout, plist schemas, scripts, default-off and durable admission')
