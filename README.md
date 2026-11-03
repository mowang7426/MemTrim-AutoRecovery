# MemTrim AutoRecovery（实验版，RootHide）

在用户提供的 MemTrim 0.0.2 上增加**默认关闭**的独立自动恢复调度组件。原插件作者为 **crctdd**；这是非官方修改版，原二进制不改写，不代表原作者认可。原文件权利仍归原作者；未给原组件重新授权。

## 行为
- 系统压力连续升高约 8 秒，仅建立待处理标记，不在警告/临界压力快照下发送请求。
- 压力恢复 normal，同时系统空闲页大于等于 `max(128 MiB, 物理内存 3%)`，原服务持续存活且空闲，连续观测至少 20 秒才请求原深度优化一次。
- 任意自动请求（包括失败/被原服务忽略）按用户选择的 **5–120 分钟冷却**（默认 15 分钟）处理；手动/自动任务活动也抑制自动触发。不能关闭冷却或设到 5 分钟以下。
- 每次监控守护程序启动都按**当前设置值**重新冷却，重启、缺失/损坏的记录不能缩短保护。系统时间突变也按当前设置重新冷却。正在进行的冷却不会被调短设置提前结束。
- 运行期间/冷却期不收集新的低内存事件，避免把原清理施加的压力作为新触发条件。待处理事件 30 分钟失效；观测间隔超过 5 秒则丢弃，睡眠时间不算稳定时间。
- 原服务没有新鲜心跳、压力读取失败、VM 查询失败、持久化失败时**跳过而不是猜测正常**。
- 两秒一次轻量观测，保留原手动功能。原 MemTrim 总开关需要开启。

阈值是保守初始设置，不是经过设备实测的最优参数。空闲页少不必然等于设备卡顿，不保证每次内存不足都触发。

## 必须了解的边界
原深度算法通过大量申请并触碰内存推动回收。恢复后执行仍可能引发 Jetsam、后台应用重载、耗电和卡顿；不能承诺提升性能。
新增组件只调度原公开通知，不修改原 worker 的内存限额和分配量。最终压力检查与通知处理之间仍存在竞态；新组件无法提供跨进程原子压力门禁。原 worker 自己的 critical 中止保护保留，不等于能避免所有影响。

`notify_post` 返回成功只表示发送成功，**不代表任务被接受或清理完成**。状态变化只能说明观察到原服务活动，不能归因给某一次请求。系统日志保留该区分。

## 安装与使用
1. 先保留原 `MemTrim-0.0.2-iphoneos-arm64e.deb` 作为回退包。此包使用相同包标识 `com.crctdd.memtrim`，安装是升级替换，不是另装一个完全独立的包。
2. 仅提供 **RootHide / iphoneos-arm64e** 包，目标 iOS 16.2、17.0；不要按 iOS 版本误选普通 Rootless。未安装测试，不保证设备适配。
3. 手动通过包管理器安装。包安装脚本注册原服务和新服务，不强制注销，也不强制执行优化。
4. 重新打开设置，进入 **MemTrim 自动恢复**，用滑块将冷却设为 **5–120 分钟**（每分钟调节，默认 15 分钟）；之后再按需开启自动功能。为避免连续施压，不能低于 5 分钟。原 MemTrim 总开关也须开启。
5. 点击 **查看运行状态**。守护进程启动/重启时按当前所设时间冷却；没有新的持续低内存事件不会执行。
6. 关闭自动开关停止新的自动请求，不取消已经进入原 worker 的任务。若要停止原 worker，使用原 MemTrim 主开关。

卸载升级包会卸载原 MemTrim；回退请在包管理器重新安装保留的 0.0.2 包（可能需要允许降级）。卸载脚本停止两个服务，保留用户设置。后续重装仍需自己检查开关。

## 实现和权限
- 附加守护程序 `memtrim-autorecovery` 以 root 运行，仅为读取受保护的 `kern.memorystatus_vm_pressure_level` 和维护自己的冷却记录；不注入 App、不改内存限额、不杀进程、不启动任意命令。
- 原 `memtrimd` 仍以 mobile 运行；新增程序和设置通过 RootHide `jbroot()` 解析各自路径。
- 新设置独立于原插件：`/var/mobile/Library/Preferences/com.local.memtrim.autorecovery.plist`，唯一写入方是设置面板。
- 运行状态目录：`/var/lib/memtrim-autorecovery`（root，0700）；通知心跳用于面板查看状态。
- 原服务状态低 8 位为忙碌标志，时间戳部分每秒变化。监控要求实际观察到状态更新，不把旧 idle 值当作服务存活。
- 参考 Apple XNU `xnu-8792.61.2/bsd/kern/kern_memorystatus_notify.c`：导出的压力返回 NOTE_MEMORYSTATUS_PRESSURE_*，iOS 上读取受 PRIV_VM_PRESSURE 权限控制。接口不可用则不自动执行。

## 构建与验证
```sh
cc -std=c11 -Wall -Wextra -Werror tests/policy.c -lm -o /tmp/mtar-policy-test
/tmp/mtar-policy-test
python3 tests/check_source.py
make package FINALPACKAGE=1 DEBUG=0 THEOS_PACKAGE_SCHEME=roothide
python3 tests/check_package.py packages/*.deb
```

使用 RootHide Theos + iPhoneOS 16.5 SDK；附加二进制同时编译 arm64/arm64e。工作流仅 feature 分支和手动触发，上传 Actions artifact，不自动创建 Release。
验包验证原负载 SHA-256 不变、布局/设置/依赖及全部 Mach-O slice 的 CodeDirectory 代码页散列。不是完整签名信任链验证，也不是越狱 entitlement 授权或真机性能验证。

## 从 autorecovery1 安装失败恢复
旧测试包 `0.0.3+autorecovery1` 的新增守护程序空权限签名导致 RootHide 动态库加载被拒，`postinst` 返回 134，dpkg 留在未配置状态，Sileo 每次刷新都会提示“Dpkg 被中断”并提供移除队列。不要重复安装该旧包。
新版 `0.0.3+autorecovery2` 为新增守护进程签入与原 MemTrim 相同的 RootHide 基础权限，并在新增组件不可用时保持原版服务可启动，不因可选组件错误让包处于未配置状态；这仍未取代设备实测。
旧包若处于 `iF`/未配置状态，请在越狱终端用**新版 deb 的实际绝对路径**安装：`dpkg -i /实际路径/com.crctdd.memtrim_0.0.3+autorecovery2_iphoneos-arm64e.deb`。成功后检查 `dpkg --audit` 是否空、`dpkg -s com.crctdd.memtrim` 为 `Status: install ok installed`，Sileo 的移除队列应清除，必要时点“清除队列”但不要点确认移除。若仍无法配置，可先卸载失败包再装回已备份的原版 0.0.2；不要运行 `dpkg --configure -a` 去反复配置旧版。
