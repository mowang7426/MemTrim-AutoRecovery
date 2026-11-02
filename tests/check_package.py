import sys,struct,tarfile,io,hashlib,json,plistlib
from pathlib import Path
p=Path(sys.argv[1]); data=p.read_bytes()
assert data[:8]==b'!<arch>\n'; pos=8; members={}
while pos<len(data):
 h=data[pos:pos+60]; assert h[58:60]==b'`\n'
 name=h[:16].decode().strip().rstrip('/'); n=int(h[48:58]); pos+=60
 members[name]=data[pos:pos+n]; pos+=n+(n%2)
def unpack(prefix):
 b=next(v for k,v in members.items() if k.startswith(prefix+'.tar'))
 t=tarfile.open(fileobj=io.BytesIO(b),mode='r:*')
 return {m.name.removeprefix('./').lstrip('/'):t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
files=unpack('data'); control=unpack('control')
text=control['control'].decode(); assert 'Architecture: iphoneos-arm64e' in text
assert 'Package: com.crctdd.memtrim\n' in text
for n in ['postinst','prerm']: assert n in control
root=Path(__file__).resolve().parents[1]
for name,digest in json.loads((root/'tests/original-sha256.json').read_text()).items():
 assert name in files,'missing original '+name
 assert hashlib.sha256(files[name]).hexdigest()==digest,'changed original '+name
required=['usr/libexec/memtrim-autorecovery','Library/PreferenceBundles/MemTrimAutoRecoveryPrefs.bundle/MemTrimAutoRecoveryPrefs','Library/PreferenceBundles/MemTrimAutoRecoveryPrefs.bundle/Root.plist','Library/LaunchDaemons/com.crctdd.memtrim.autorecovery.plist','Library/PreferenceLoader/Preferences/MemTrimAutoRecovery.plist']
for n in required: assert n in files,n
for n in files: assert not n.startswith(('LaunchDaemons/','MobileSubstrate/','PreferenceBundles/','var/jb/'))
def codecheck(b):
 assert struct.unpack_from('<I',b)[0]==0xfeedfacf
 cpu,sub=struct.unpack_from('<II',b,4); assert cpu==0x100000c
 nc=struct.unpack_from('<I',b,16)[0]; off=32; sig=None
 for _ in range(nc):
  cmd,size=struct.unpack_from('<II',b,off); assert size>=8
  if cmd==0x1d: sig=struct.unpack_from('<II',b,off+8)
  off+=size
 assert sig,'unsigned Mach-O'
 start,n=sig; s=b[start:start+n]; magic,length,count=struct.unpack_from('>III',s)
 assert magic==0xfade0cc0 and length<=len(s)
 checked=0
 for i in range(count):
  typ,at=struct.unpack_from('>II',s,12+8*i)
  if typ!=0 and not (0x1000<=typ<=0x1005): continue
  c=s[at:]; magic,length,version,flags,ho,ident,special,slots,limit=struct.unpack_from('>9I',c)
  assert magic==0xfade0c02 and length<=len(c)
  hs,ht,platform,page=struct.unpack_from('4B',c,36)
  if version>=0x20300 and limit==0: limit=struct.unpack_from('>Q',c,56)[0]
  assert limit<=start
  chunk=(1<<page) if page else limit
  assert slots==(limit+chunk-1)//chunk
  alg={1:'sha1',2:'sha256',3:'sha256',4:'sha384'}[ht]
  for j in range(slots):
   expected=c[ho+j*hs:ho+(j+1)*hs]
   actual=hashlib.new(alg,b[j*chunk:min((j+1)*chunk,limit)]).digest()[:hs]
   assert actual==expected,('bad CodeDirectory page',j)
  checked+=1
 assert checked
 return sub,checked
count=0
for name,b in files.items():
 magic=b[:4]
 slices=[]
 if magic==b'\xcf\xfa\xed\xfe': slices=[b]
 elif magic==b'\xca\xfe\xba\xbe':
  n=struct.unpack_from('>I',b,4)[0]
  for i in range(n):
   cpu,sub,off,size,align=struct.unpack_from('>5I',b,8+i*20); slices.append(b[off:off+size])
 if slices:
  verified=[codecheck(x) for x in slices]; count+=len(slices)
  print('PASS Mach-O code pages:',name,verified)
print('PASS:',len(files),'files;',count,'Mach-O slices; all original payload bytes preserved')
print('SHA256',hashlib.sha256(data).hexdigest(),p.name)
print('Not a runtime compatibility, entitlement authorization, or full trust-chain test.')
