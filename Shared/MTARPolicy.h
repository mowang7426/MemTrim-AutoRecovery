#ifndef MTAR_POLICY_H
#define MTAR_POLICY_H
#include <stdbool.h>
#include <math.h>
// Callers load this from the validated user preference (minimum five minutes).
static double MTARCooldownSeconds=900.0;
#define MTAR_CONFIRM 8.0
#define MTAR_STABLE 20.0
#define MTAR_TTL 1800.0
// Pressure is XNU's exported NOTE_MEMORYSTATUS_PRESSURE_* value, not process allowance.
typedef struct { double low, pending, stable, until, last; } MTARPolicy;
static inline void MTARReset(MTARPolicy *p) { p->low=p->pending=p->stable=-1; }
static inline void MTARInit(MTARPolicy *p,double now) {
    *p=(MTARPolicy){.until=now+MTARCooldownSeconds,.last=now}; MTARReset(p);
}
static inline void MTARSuppress(MTARPolicy *p,double now) {
    p->until=fmax(p->until,now+MTARCooldownSeconds); MTARReset(p);
}
static inline bool MTARStep(MTARPolicy *p,double now,bool enabled,bool valid,
                            int pressure,bool room,bool idle,bool activity) {
    if(!isfinite(now)||now<0) { MTARReset(p); return false; }
    if(now<p->last) { p->until=now+MTARCooldownSeconds; MTARReset(p); }
    if(now-p->last>5) MTARReset(p); // sleep or delayed polling is not observed stability
    p->last=now;
    if(activity||!idle) MTARSuppress(p,now);
    if(!enabled||!valid||now<p->until||!idle) { MTARReset(p); return false; }
    if(pressure!=1&&pressure!=2&&pressure!=4) { MTARReset(p); return false; }
    if(p->pending>=0&&now-p->pending>MTAR_TTL) { MTARReset(p); return false; }
    if(pressure==2||pressure==4) {
        p->stable=-1;
        if(p->low<0) p->low=now;
        if(p->pending<0&&now-p->low>=MTAR_CONFIRM) p->pending=now;
        return false;
    }
    p->low=-1;
    if(p->pending<0) return false;
    if(!room) { p->stable=-1; return false; }
    if(p->stable<0) p->stable=now;
    if(now-p->stable<MTAR_STABLE) return false;
    MTARSuppress(p,now); // caller must persist BEFORE posting; failure still suppresses
    return true;
}
#endif
