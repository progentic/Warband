#define _GNU_SOURCE
#include "wire.h"
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

#define ALLOW(n) BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,__NR_##n,0,1), BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)
static int confine(void) {
    struct sock_filter rules[]={
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,arch)),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AUDIT_ARCH_X86_64,1,0),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
        ALLOW(read),ALLOW(write),ALLOW(recvmsg),ALLOW(exit),ALLOW(exit_group),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM)
    };
    struct sock_fprog prog={sizeof(rules)/sizeof(rules[0]),rules};
    return prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0) || prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&prog);
}
#ifdef WB_WORKER_PROBE
#include <netinet/in.h>
#include <stdio.h>
#include <sys/un.h>
static volatile uint8_t pressure[48*1024*1024];
static int probes(char mode,const uint8_t directory[16]) {
    if (mode=='m') for (size_t i=0;i<sizeof(pressure);i+=4096) pressure[i]=1;
    if (mode=='t') for (;;) {}
    if (mode=='o' || mode=='x') {
        char data[2048]={0};
        memcpy(data+2042,"SECRET",6);
        if (write(1,data,sizeof(data))!=sizeof(data)) return -1;
        memcpy(data,"-WB-CANARY",10);
        if (write(2,data,sizeof(data))!=sizeof(data)) return -1;
        if (mode=='x') { if (write(2,"!",1)!=1) return -1; for (;;) {} }
    }
    if (mode!='s') return 0;
    struct sockaddr_in net={.sin_family=AF_INET,.sin_port=__builtin_bswap16(39491),.sin_addr={__builtin_bswap32(0xc0000202)}};
    struct sockaddr_un local={.sun_family=AF_UNIX,.sun_path="probe.sock"};
#define DENIED(call) do { errno=0; if ((call)!=-1 || errno!=EPERM) return -1; } while (0)
    DENIED(socket(AF_INET,SOCK_STREAM,0));
    DENIED(connect(0,(void *)&net,sizeof(net)));
    DENIED(socket(AF_UNIX,SOCK_STREAM,0));
    DENIED(connect(0,(void *)&local,sizeof(local)));
    DENIED(open("probe-area/adjacent",O_WRONLY|O_CREAT,0600));
    DENIED(open("journal/active.db",O_RDONLY));
    DENIED(open("data/history",O_RDONLY));
    char target[64]="attempts/";
    for (int i=0;i<16;i++) snprintf(target+9+2*i,3,"%02x",directory[i]);
    strcpy(target+41,"/marker");
    DENIED(symlink("../../journal/active.db",target));
    DENIED(unlink("probe-area/protected"));
    DENIED(rename("probe-area/protected","probe-area/renamed"));
    DENIED(syscall(SYS_fork));
    char *argv[]={"/bin/true",NULL}, *env[]={NULL};
    DENIED(execve(argv[0],argv,env));
    return 0;
}
#endif
int main(int argc,char **argv) {
    if (argc!=3) return 2;
    pid_t runtime=atoi(argv[1]);
    uid_t uid=(uid_t)strtoul(argv[2],NULL,10);
#ifdef WB_WORKER_PROBE
    char mode=0;
    int config=open("worker.probe",O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if (config<0 || read(config,&mode,1)!=1 || close(config)) return 2;
#endif
    if (!uid || runtime<1 || confine() || write(0,"R",1)!=1) return 2;
    uint8_t packet[WB_HEADER+WB_MAX+1];
    int n=wb_from(0,packet,sizeof(packet)-1,runtime,uid);
    if (n<(int)WB_HEADER) return 3;
#ifdef WB_WORKER_PROBE
    if (probes(mode,packet+96)) return 4;
    if (mode=='b') packet[0]='?';
    if (mode=='i') packet[96]^=1; // bound directory ID
    if (mode=='p') packet[n-1]^=1;
    if (mode=='z') { uint32_t over=WB_MAX+1; memcpy(packet+4,&over,4); n=sizeof(packet); packet[n-1]=0; }
#endif
    if (write(0,packet,n)!=n) return 5;
    uint8_t reply=0;
    if (wb_from(0,&reply,1,runtime,uid)!=1 || reply<WB_CREATED || reply>WB_STORAGE) return 6;
#ifdef WB_WORKER_PROBE
    if (mode=='d' && (write(0,packet,n)!=n || wb_from(0,&reply,1,runtime,uid)!=1 || reply!=WB_DUPLICATE)) return 7;
#endif
    return 0;
}
