#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "../Shared/MTARPaths.h"
#include <notify.h>
#include <math.h>
@interface MTARootListController : PSListController
@end
@implementation MTARootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *p=[NSDictionary dictionaryWithContentsOfFile:MTARPrefsPath()];
    NSString *key=[specifier propertyForKey:@"key"];
    id v=p[key];
    if([key isEqualToString:@"CooldownMinutes"]) {
        NSInteger minutes=[v respondsToSelector:@selector(integerValue)]?[v integerValue]:15;
        return @(MIN(120,MAX(5,minutes)));
    }
    return [v isKindOfClass:NSNumber.class] ? @([v boolValue]) : @NO;
}
- (void)mtar_show:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"MemTrim 自动恢复" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    NSString *path=MTARPrefsPath();
    NSDictionary *old=[NSDictionary dictionaryWithContentsOfFile:path];
    if([[NSFileManager defaultManager] fileExistsAtPath:path] && !old) {
        [self mtar_show:@"配置文件无法读取，未覆盖。请检查文件权限或备份后修复。"]; [self reloadSpecifiers]; return;
    }
    NSMutableDictionary *p=old?[old mutableCopy]:[NSMutableDictionary dictionary];
    if([key isEqualToString:@"CooldownMinutes"]) {
        NSInteger minutes=(NSInteger)lround([value respondsToSelector:@selector(doubleValue)]?[value doubleValue]:15.0);
        if(minutes<5 || minutes>120) {
            [self mtar_show:@"冷却时间可设置为 5–120 分钟，至少保留 5 分钟保护。"];
            [self reloadSpecifiers]; return;
        }
        p[@"CooldownMinutes"]=@(minutes);
    } else if([key isEqualToString:@"Enabled"]) {
        p[@"Enabled"]=@([value boolValue]);
    } else {
        [self mtar_show:@"未知设置项，未保存。"]; return;
    }
    NSError *error=nil;
    BOOL dir=[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
    if(!dir || ![p writeToFile:path atomically:YES]) {
        [self mtar_show:@"开关保存失败，未向守护程序发送更新。"]; [self reloadSpecifiers]; return;
    }
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:@"com.local.memtrim.autorecovery"];
    [defaults setPersistentDomain:p forName:@"com.local.memtrim.autorecovery"];
    [defaults synchronize];
    notify_post(MTAR_PREF_CHANGED);
    [self reloadSpecifiers];
}
- (void)mtar_status {
    NSArray *messages=@[@"未知状态", @"自动开关关闭", @"原 MemTrim 服务心跳不可确认，自动任务暂停", @"系统压力或 VM 指标不可读取，自动任务暂停", @"冷却记录写入失败，自动任务暂停", @"原服务正在执行或刚结束任务", @"冷却中", @"当前内存压力升高，仅观察，绝不启动深度清理", @"已标记低内存，等待足够的空闲内存", @"恢复稳定计时中，需连续 20 秒", @"监测正常，等待新的持续低内存事件", @"已发送请求；不代表原任务已接受或完成", @"请求发送失败，保留冷却"];
    int token=-1; uint64_t state=0;
    if(notify_register_check(MTAR_STATUS,&token)!=NOTIFY_STATUS_OK) { [self mtar_show:@"无法读取状态"]; return; }
    uint32_t rc=notify_get_state(token,&state); notify_cancel(token);
    long long age=(long long)time(NULL)-(long long)(state>>8);
    if(rc!=NOTIFY_STATUS_OK||state==0||age<0||age>10) { [self mtar_show:@"自动守护程序心跳不可确认，可能未运行。没有因此判定为优化成功。"]; return; }
    NSUInteger code=(NSUInteger)(state&255);
    NSString *message=code<messages.count?messages[code]:messages[0];
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:MTARPrefsPath()];
    NSInteger minutes=[prefs[@"CooldownMinutes"] respondsToSelector:@selector(integerValue)]?[prefs[@"CooldownMinutes"] integerValue]:15;
    minutes=MIN(120,MAX(5,minutes));
    if(code==6) message=[NSString stringWithFormat:@"%ld 分钟冷却中（重启后至少重新等待一次冷却）",(long)minutes];
    [self mtar_show:[NSString stringWithFormat:@"%@\n当前冷却设置：%ld 分钟。\n\n原 MemTrim 总开关也必须开启。深度清理仍可能导致后台重载。",message,(long)minutes]];
}
@end
