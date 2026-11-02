#import <Foundation/Foundation.h>
#import "../Shared/MTARPaths.h"
#include "../Shared/MTARPolicy.h"
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <notify.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

static MTARPolicy MTARPolicyState;
static int MTARTokens[3]={-1,-1,-1}, MTARStatusToken=-1;
static uint64_t MTARPrevious[3];
static double MTARHeartbeat=-1, MTARLastWall=0, MTARLastMono=0, MTARWallUntil=0;
static double MTARRequestTime=-1;
static bool MTARHaveBaseline=false, MTARReady=false, MTAREnabled=false;
static NSString *MTAROutcome=@"尚未发出自动请求";
static dispatch_source_t MTARTimer;
static mach_port_t MTARHost;
static vm_size_t MTARPageSize;
static uint64_t MTARRAM;
static double MTARNow(void) {
    struct timespec ts={0};
    return clock_gettime(CLOCK_MONOTONIC,&ts)==0 ? ts.tv_sec+ts.tv_nsec/1e9 : -1;
}
static void MTARReload(void) {
    id data=[NSDictionary dictionaryWithContentsOfFile:MTARPrefsPath()];
    id value=[data isKindOfClass:NSDictionary.class] ? data[@"Enabled"] : nil;
    MTAREnabled=[value isKindOfClass:NSNumber.class] && [value boolValue];
    MTARReset(&MTARPolicyState);
}
static bool MTARPersist(double wall) {
    NSString *path=[MTARRuntimePath() stringByAppendingPathComponent:@"cooldown"];
    NSString *tmp=[path stringByAppendingFormat:@".%d.tmp",getpid()];
    int fd=open(tmp.fileSystemRepresentation,O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0) return false;
    char b[80]; int n=snprintf(b,sizeof(b),"%.3f\n",wall+MTAR_COOLDOWN);
    bool ok=write(fd,b,(size_t)n)==n && fsync(fd)==0;
    close(fd);
    if(ok) ok=rename(tmp.fileSystemRepresentation,path.fileSystemRepresentation)==0;
    if(!ok) unlink(tmp.fileSystemRepresentation);
    if(ok) {
        int dir=open(MTARRuntimePath().fileSystemRepresentation,O_RDONLY|O_CLOEXEC);
        if(dir<0) return false;
        // Some filesystems do not support directory fsync. The file was synced
        // before atomic rename; a power loss still forces a fresh boot cooldown.
        int rc=fsync(dir), saved=errno; close(dir);
        ok=rc==0 || saved==EINVAL || saved==ENOTSUP;
    }
    if(ok) MTARWallUntil=wall+MTAR_COOLDOWN;
    return ok;
}
static void MTARPublish(unsigned code) {
    uint64_t value=((uint64_t)time(NULL)<<8)|(code&255);
    if(MTARStatusToken>=0) notify_set_state(MTARStatusToken,value);
}
static int MTARPressure(void) {
    int level=0; size_t len=sizeof(level);
    if(sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&len,NULL,0)!=0 || len!=sizeof(level)) return 0;
    return (level==1||level==2||level==4)?level:0;
}
static bool MTARHeadroom(bool *room) {
    vm_statistics64_data_t vm={0}; mach_msg_type_number_t n=HOST_VM_INFO64_COUNT;
    if(!MTARPageSize||!MTARRAM||host_statistics64(MTARHost,HOST_VM_INFO64,(host_info64_t)&vm,&n)!=KERN_SUCCESS) return false;
    // Free pages, not os_proc_available_memory (per-process allowance).
    uint64_t bytes=(uint64_t)vm.free_count*MTARPageSize;
    uint64_t threshold=MAX(128ULL*1024*1024,MTARRAM*3/100);
    *room=bytes>=threshold; return true;
}
static bool MTARService(double now,bool *idle,bool *activity) {
    const char *names[]={"com.crctdd.memtrim.state.service","com.crctdd.memtrim.state.normal","com.crctdd.memtrim.state.deep"};
    uint64_t states[3]={0};
    *activity=false; *idle=false;
    for(int i=0;i<3;i++) {
        if(MTARTokens[i]<0 && notify_register_check(names[i],&MTARTokens[i])!=NOTIFY_STATUS_OK) return false;
        if(notify_get_state(MTARTokens[i],&states[i])!=NOTIFY_STATUS_OK) return false;
    }
    if(MTARHaveBaseline) {
        if(states[0]!=MTARPrevious[0] && states[0]!=0) MTARHeartbeat=now;
        *activity=(states[1]!=MTARPrevious[1] || states[2]!=MTARPrevious[2]);
    }
    memcpy(MTARPrevious,states,sizeof(states)); MTARHaveBaseline=true;
    // Original daemon refreshes its packed service state every second. Observe movement,
    // not merely phase==0: an abandoned idle notification is not a living service.
    if(states[0]==0 || MTARHeartbeat<0 || now-MTARHeartbeat>5) return false;
    *idle=(states[0]&255)==0;
    if((states[0]&255)>1) return false;
    return true;
}
static void MTARTick(void) {
    @autoreleasepool {
        double now=MTARNow(),wall=(double)time(NULL);
        if(now<0||wall<=0) { MTARPublish(3); MTARReset(&MTARPolicyState); return; }
        if(MTARLastWall>0 && fabs((wall-MTARLastWall)-(now-MTARLastMono))>30) {
            MTARSuppress(&MTARPolicyState,now); MTARReady=MTARPersist(wall);
        }
        MTARLastWall=wall; MTARLastMono=now;
        if(!MTARReady) { MTARPublish(4); return; }
        bool idle=false,activity=false,room=false;
        bool alive=MTARService(now,&idle,&activity);
        bool vmOK=MTARHeadroom(&room); int pressure=MTARPressure();
        if(activity && MTARRequestTime>=0) {
            MTAROutcome=@"请求后观察到原服务状态变化；不能据此保证清理成功";
            NSLog(@"MemTrimAutoRecovery: %@",MTAROutcome); MTARRequestTime=-1;
        } else if(MTARRequestTime>=0 && now-MTARRequestTime>15) {
            MTAROutcome=@"请求后未观察到任务状态变化，可能被忽略；保持冷却";
            NSLog(@"MemTrimAutoRecovery: %@",MTAROutcome); MTARRequestTime=-1;
        }
        // Never learn a new low-memory episode from a manual or automatic worker.
        if(alive && (activity||!idle)) {
            MTARSuppress(&MTARPolicyState,now);
            if(MTARWallUntil<wall+MTAR_COOLDOWN-10) MTARReady=MTARPersist(wall);
        }
        bool cooldown=now<MTARPolicyState.until || wall<MTARWallUntil;
        bool ready=MTARStep(&MTARPolicyState,now,MTAREnabled,
                           alive&&vmOK&&pressure!=0&&MTARReady&&!cooldown,
                           pressure,room,idle,activity);
        if(!MTAREnabled) MTARPublish(1);
        else if(!MTARReady) MTARPublish(4);
        else if(!alive) MTARPublish(2);
        else if(!vmOK||!pressure) MTARPublish(3);
        else if(!idle||activity) MTARPublish(5);
        else if(cooldown) MTARPublish(6);
        else if(pressure!=1) MTARPublish(7);
        else if(MTARPolicyState.pending>=0) MTARPublish(room?9:8);
        else MTARPublish(10);
        if(!ready) return;
        // Snapshot gate again, then durable admission before IPC. The original daemon
        // supplies single-flight. Notification IPC has no transactional pressure gate.
        bool freshIdle=false,freshActivity=false,freshRoom=false;
        MTARReload();
        if(!MTAREnabled || MTARPressure()!=1 || !MTARHeadroom(&freshRoom) || !freshRoom ||
           !MTARService(now,&freshIdle,&freshActivity) || !freshIdle || freshActivity) return;
        MTARReady=MTARPersist(wall);
        if(!MTARReady) { MTARPublish(4); return; }
        uint32_t result=notify_post("com.crctdd.memtrim.request.deep");
        MTAROutcome=result==NOTIFY_STATUS_OK ? @"已发送请求，等待观察；不代表任务已接受或完成" : @"通知发送失败；保持冷却";
        MTARRequestTime=result==NOTIFY_STATUS_OK?now:-1;
        NSLog(@"MemTrimAutoRecovery: %@",MTAROutcome); MTARPublish(result==0?11:12);
    }
}
static int MTARConfigure(void) {
    if(geteuid()!=0) return 77;
    NSString *path=jbroot(@"/Library/LaunchDaemons/com.crctdd.memtrim.autorecovery.plist");
    NSMutableDictionary *p=[[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
    if(!p) return 65;
    p[@"ProgramArguments"]=@[jbroot(@"/usr/libexec/memtrim-autorecovery")];
    p[@"UserName"]=@"root"; p[@"GroupName"]=@"wheel";
    return [p writeToFile:path atomically:YES]?0:74;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc==2 && strcmp(argv[1],"--configure")==0) return MTARConfigure();
        if(argc!=1 || geteuid()!=0) return 77;
        double now=MTARNow(); if(now<0) return 69;
        const char *dir=MTARRuntimePath().fileSystemRepresentation;
        if(mkdir(dir,0700)!=0 && errno!=EEXIST) return 73;
        struct stat st;
        if(lstat(dir,&st)!=0 || !S_ISDIR(st.st_mode)||st.st_uid!=0||(st.st_mode&077)!=0) return 77;
        NSString *lockPath=[MTARRuntimePath() stringByAppendingPathComponent:@"lock"];
        int lock=open(lockPath.fileSystemRepresentation,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);
        if(lock<0||flock(lock,LOCK_EX|LOCK_NB)!=0) return 75;
        MTARInit(&MTARPolicyState,now);
        // Always restart with a fresh 15-minute guard, even after missing/corrupt state
        // or a wall-clock jump. No pending episode survives a daemon restart.
        MTARReady=MTARPersist(time(NULL));
        MTARReload();
        MTARHost=mach_host_self(); host_page_size(MTARHost,&MTARPageSize);
        MTARRAM=NSProcessInfo.processInfo.physicalMemory;
        notify_register_check(MTAR_STATUS,&MTARStatusToken);
        int prefToken=-1;
        notify_register_dispatch(MTAR_PREF_CHANGED,&prefToken,dispatch_get_main_queue(),^(int t){ (void)t; MTARReload(); });
        MTARTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        if(!MTARTimer) return 69;
        dispatch_source_set_timer(MTARTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),2*NSEC_PER_SEC,NSEC_PER_SEC/4);
        dispatch_source_set_event_handler(MTARTimer,^{ MTARTick(); });
        dispatch_resume(MTARTimer); dispatch_main();
    }
}
