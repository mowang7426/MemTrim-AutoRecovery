#import <Foundation/Foundation.h>
#import <roothide.h>
#define MTAR_PREF_CHANGED "com.local.memtrim.autorecovery.changed"
#define MTAR_STATUS "com.local.memtrim.autorecovery.status"
static inline NSString *MTARPrefsPath(void) {
    return jbroot(@"/var/mobile/Library/Preferences/com.local.memtrim.autorecovery.plist");
}
static inline NSString *MTARRuntimePath(void) { return jbroot(@"/var/lib/memtrim-autorecovery"); }
