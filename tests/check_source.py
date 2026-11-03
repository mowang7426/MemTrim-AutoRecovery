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
 assert f.read_bytes().startswith(b'#!/bin/sh'),name
ent=plistlib.loads((p/'entitlements.plist').read_bytes())
assert all(ent.get(k) is True for k in (
 'platform-application','com.apple.private.memorystatus',
 'com.apple.private.security.no-sandbox',
 'com.apple.private.security.storage.AppBundles',
 'com.apple.private.security.storage.AppDataContainers'))
script=(p/'layout/DEBIAN/postinst').read_text()
assert script.index('"$prefix/usr/libexec/memtrim-autorecovery" --configure') < script.index('bootout_label com.crctdd.memtrim.daemon')
launch=plistlib.loads((p/'layout/Library/LaunchDaemons/com.crctdd.memtrim.autorecovery.plist').read_bytes())
assert launch['UserName']=='root' and launch['GroupName']=='wheel'
assert launch['ProgramArguments']==['/usr/libexec/memtrim-autorecovery']
items=plistlib.loads((p/'Prefs/Resources/Root.plist').read_bytes())['items']
info=plistlib.loads((p/'Prefs/Resources/Info.plist').read_bytes())
assert info['NSPrincipalClass']=='MTARootListController'
switch=[x for x in items if x['cell']=='PSSwitchCell'][0]
assert switch['default'] is False and switch['defaults']=='com.local.memtrim.autorecovery'
slider=[x for x in items if x['cell']=='PSSliderCell'][0]
assert slider['key']=='CooldownMinutes' and slider['defaults']=='com.local.memtrim.autorecovery'
assert (slider['min'],slider['max'],slider['default'])==(5,120,15)
main=(p/'AutoRecovery/main.m').read_text()
controller=(p/'Prefs/MTARootListController.m').read_text()
assert 'minutes<5 || minutes>120' in controller and 'p[@"CooldownMinutes"]' in controller
assert 'wall+MTARCooldownSeconds' in main and 'MIN(120,MAX(5,minutes))' in main
assert 'system(' not in main and 'posix_spawn' not in main and 'kill(' not in main
assert main.index('MTARReady=MTARPersist(wall);',main.index('if(!ready) return;'))<main.index('notify_post("com.crctdd.memtrim.request.deep")')
assert 'sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&len,NULL,0)' in main
print('PASS: original payload hashes, canonical layout, plist schemas, scripts, default-off and durable admission')
