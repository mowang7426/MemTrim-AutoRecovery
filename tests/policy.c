#include "../Shared/MTARPolicy.h"
#include <assert.h>
#include <stdio.h>
static MTARPolicy p;
static double t;
static int sends;
static bool step(bool enabled,bool valid,int pressure,bool room,bool idle,bool act) {
    t+=2; bool r=MTARStep(&p,t,enabled,valid,pressure,room,idle,act); sends+=r; return r;
}
static void reset(void) { t=100; sends=0; MTARCooldownSeconds=900.0; MTARInit(&p,t); }
static void warm(void) { for(int i=0;i<451;i++) assert(!step(true,true,1,true,true,false)); }
static void low(void) { for(int i=0;i<6;i++) assert(!step(true,true,2,false,true,false)); }
static void recovery(void) { for(int i=0;i<11;i++) step(true,true,1,true,true,false); }
int main(void) {
 reset(); low(); recovery(); assert(sends==0); // restart guard
 reset(); warm(); low(); assert(p.pending>=0); recovery(); assert(sends==1);
 low(); recovery(); assert(sends==1); // no self-pressure repeat
 reset(); warm(); for(int i=0;i<1000;i++) step(false,true,2,true,true,false); recovery(); assert(sends==0);
 reset(); warm(); for(int i=0;i<1000;i++) step(true,true,1,true,true,false); assert(sends==0);
 reset(); warm(); for(int i=0;i<1000;i++) step(true,true,4,true,true,false); assert(sends==0);
 reset(); warm(); for(int i=0;i<3;i++) step(true,true,2,true,true,false); recovery(); assert(sends==0);
 reset(); warm(); low(); step(true,false,1,true,true,false); recovery(); assert(sends==0);
 reset(); warm(); low(); step(true,true,0,true,true,false); recovery(); assert(sends==0);
 reset(); warm(); low(); step(true,true,1,true,false,false); recovery(); assert(sends==0);
 reset(); warm(); low(); step(true,true,1,true,true,true); recovery(); assert(sends==0);
 reset(); warm(); low(); step(false,true,1,true,true,false); recovery(); assert(sends==0);
 reset(); warm(); low(); for(int i=0;i<100;i++) step(true,true,1,false,true,false); assert(sends==0); recovery(); assert(sends==1);
 reset(); warm(); low(); for(int i=0;i<5;i++) step(true,true,1,true,true,false); step(true,true,1,false,true,false);
 for(int i=0;i<10;i++) { step(true,true,1,true,true,false); }
 assert(sends==0); step(true,true,1,true,true,false); assert(sends==1);
 reset(); warm(); low(); for(int i=0;i<5;i++) step(true,true,1,true,true,false); step(true,true,2,true,true,false);
 recovery(); assert(sends==1);
 reset(); warm(); low(); t+=10; recovery(); assert(sends==0); // polling gap discards stability
 reset(); warm(); low(); t-=100; recovery(); assert(sends==0); // monotonic rollback
 reset(); warm(); low(); for(int i=0;i<901;i++) step(true,true,1,false,true,false); recovery(); assert(sends==0); // expired pending
 reset(); warm(); low(); MTARInit(&p,t); recovery(); assert(sends==0); // restart drops pending
 reset(); warm(); low(); assert(!MTARStep(&p,NAN,true,true,1,true,true,false)); recovery(); assert(sends==0);
 // Each failure after admission still consumes the cooldown (no post retry loop).
 reset(); warm(); low(); recovery(); assert(sends==1); warm(); recovery(); assert(sends==1); low(); recovery(); assert(sends==2);
 // Configurable cooldown is honored across boot initialization and activity suppression.
 MTARCooldownSeconds=300.0; t=100; MTARInit(&p,t); assert(p.until==400.0);
 MTARSuppress(&p,200.0); assert(p.until==500.0);
 MTARCooldownSeconds=7200.0; MTARSuppress(&p,600.0); assert(p.until==7800.0);
 MTARCooldownSeconds=900.0;
 puts("PASS: 21 policy scenarios plus custom 5/120-minute cooldown timing");
}
