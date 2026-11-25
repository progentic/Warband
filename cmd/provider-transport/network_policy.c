#define _GNU_SOURCE
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <poll.h>
#include <resolv.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

/* Installed by the launcher after UID/namespace separation and before application code.
 * Connected stream operations and anonymous Unix pairs are sufficient for libcurl.
 * Keep new sockets, connect, exec and asynchronous syscall submission outside this profile. */
#define ALLOW(n) BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,__NR_##n,0,1), BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)
#define DENY BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM)
int wb_network_profile(void) {
    struct sock_filter rules[]={
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,arch)),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AUDIT_ARCH_X86_64,1,0),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,__NR_socketpair,0,4),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[0])),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AF_UNIX,0,1),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW), DENY,
        ALLOW(read),ALLOW(write),ALLOW(close),ALLOW(pread64),ALLOW(fstat),ALLOW(newfstatat),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,__NR_openat,0,4),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[2])),
        BPF_JUMP(BPF_JMP|BPF_JSET|BPF_K,O_ACCMODE|O_CREAT|O_TRUNC|O_APPEND,1,0),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW), DENY,
        ALLOW(statx),ALLOW(readlink),ALLOW(readlinkat),ALLOW(getdents64),ALLOW(lseek),
        ALLOW(mmap),ALLOW(mprotect),ALLOW(munmap),ALLOW(mremap),ALLOW(brk),ALLOW(madvise),
        ALLOW(futex),ALLOW(getrandom),ALLOW(getpid),ALLOW(gettid),ALLOW(getuid),ALLOW(geteuid),
        ALLOW(clock_gettime),ALLOW(poll),ALLOW(ppoll),ALLOW(pipe2),ALLOW(fcntl),
        ALLOW(recvfrom),ALLOW(sendto),ALLOW(recvmsg),ALLOW(sendmsg),ALLOW(shutdown),
        ALLOW(getsockopt),ALLOW(setsockopt),ALLOW(getpeername),ALLOW(getsockname),
        ALLOW(rt_sigaction),ALLOW(rt_sigprocmask),ALLOW(rt_sigreturn),ALLOW(exit),ALLOW(exit_group), DENY
    };
    struct sock_fprog p={(unsigned short)(sizeof rules/sizeof *rules),rules};
    if (prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&p)) return -1;
    /* Fail the launch unless ordinary Internet, DNS and local socket opens are
     * denied in the actual child. The external harness observes these syscalls. */
    const int family[]={AF_INET,AF_INET,AF_INET6,AF_UNIX};
    const int type[]={SOCK_STREAM,SOCK_DGRAM,SOCK_STREAM,SOCK_STREAM};
    for (unsigned i=0;i<4;i++) {
        int fd=socket(family[i],type[i]|SOCK_CLOEXEC,0);
        if (fd>=0) { close(fd); return -1; }
        if (errno!=EPERM) return -1;
    }
    int pair[2];
    if (socketpair(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0,pair)) return -1;
    struct sockaddr_un local={.sun_family=AF_UNIX,.sun_path="local.sock"};
    int refused=connect(pair[0],(struct sockaddr*)&local,sizeof local)<0 && errno==EPERM;
    close(pair[0]); close(pair[1]);
    return refused?0:-1;
}

/* One TCP question at a time to the trusted local resolver. No search domains,
 * NSS/environment inputs, alternative server, UDP truncation or fallback. */
#define HOST "api.openai.com"
#define MAX_ANSWERS 32
struct address { uint8_t family, bytes[16]; };
_Static_assert(sizeof(struct address)==17,"Odin DnsAddress ABI");
struct answer {
    struct address addr[MAX_ANSWERS];
    unsigned count;
    char names[2][9][256];
    unsigned depth[2];
};
static int remaining(int64_t end) {
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME,&ts)) return 0;
    int64_t ms=end-(ts.tv_sec*1000+ts.tv_nsec/1000000);
    return ms>0 && ms<=5000 ? (int)ms : 0;
}
static int wait_fd(int fd, short events, int64_t end) {
    struct pollfd p={fd,events,0};
    int ms=remaining(end);
    return ms && poll(&p,1,ms)==1 && (p.revents&events) && remaining(end);
}
static int dial(struct in_addr addr, unsigned port, int64_t end) {
    if (!remaining(end)) return -1;
    int fd=socket(AF_INET,SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC,IPPROTO_TCP);
    if (fd<0) return -1;
    struct sockaddr_in peer={.sin_family=AF_INET,.sin_addr=addr,.sin_port=htons(port)};
    int err=0;
    socklen_t len=sizeof err;
    if ((connect(fd,(struct sockaddr*)&peer,sizeof peer) &&
         (errno!=EINPROGRESS || !wait_fd(fd,POLLOUT,end) ||
          getsockopt(fd,SOL_SOCKET,SO_ERROR,&err,&len) || err)) || !remaining(end)) {
        close(fd); return -1;
    }
    return fd;
}
static int exact(int fd,uint8_t *p,size_t n,int writing,int64_t end) {
    while (n && wait_fd(fd,writing?POLLOUT:POLLIN,end)) {
        ssize_t k=writing?send(fd,p,n,MSG_NOSIGNAL):recv(fd,p,n,0);
        if (k<=0) return 0;
        p+=k; n-=(size_t)k;
    }
    return !n;
}
static unsigned word(const uint8_t *p) { return (p[0]<<8)|p[1]; }

static int question(struct answer *out,unsigned type,int64_t end) {
    uint8_t query[]={0,0, 0,0,1,0,0,1,0,0,0,0,0,0, 3,'a','p','i',6,'o','p','e','n','a','i',3,'c','o','m',0,0,1,0,1};
    query[1]=sizeof query-2;
    query[sizeof query-3]=(uint8_t)type;
    if (getrandom(query+2,2,0)!=2) return 0;
    struct in_addr stub={htonl(0x7f000035)};
    int fd=dial(stub,53,end);
    if (fd<0) return 0;
    uint8_t size[2],buf[8192];
    int ok=exact(fd,query,sizeof query,1,end) && exact(fd,size,2,0,end);
    unsigned n=ok?word(size):0;
    ok=n>=sizeof query-2 && n<=sizeof buf && exact(fd,buf,n,0,end);
    close(fd);
    if (!ok || memcmp(buf,query+2,2) || (word(buf+2)&0xfacf)!=0x8080 ||
        word(buf+4)!=1 || word(buf+6)>MAX_ANSWERS || memcmp(buf+12,query+14,sizeof query-14)) return 0;
    const uint8_t *p=buf+sizeof query-2, *limit=buf+n;
    unsigned family=type==28;
    char owner[256],(*names)[256]=out->names[family];
    char *name=names[0];
    strcpy(name,HOST);
    int addresses=0, soa=0;
    for (unsigned i=0;i<word(buf+6);++i) {
        int k=dn_expand(buf,limit,p,owner,sizeof owner);
        if (k<0 || limit-p<k+10 || strcasecmp(owner,name)) return 0;
        p+=k;
        unsigned rr=word(p),len=word(p+8);
        if (word(p+2)!=1 || limit-p-10<len) return 0;
        p+=10;
        if (rr==5 && !addresses) {
            if (out->depth[family]>=8) return 0;
            name=names[++out->depth[family]];
            if (dn_expand(buf,limit,p,name,256)!=(int)len || !*name) return 0;
            for (unsigned j=0;j<out->depth[family];++j) if (!strcasecmp(name,names[j])) return 0;
        } else if (rr==type && len==(type==1?4u:16u) && out->count<MAX_ANSWERS) {
            struct address *a=&out->addr[out->count++];
            a->family=(uint8_t)type;
            memcpy(a->bytes,p,len);
            addresses++;
        } else return 0;
        p+=len;
    }
    /* Authority/additional records are not connection candidates. Still check
     * their boundaries and require the full message to have been consumed. */
    for (unsigned i=0;i<word(buf+8)+word(buf+10);++i) {
        int k=dn_expand(buf,limit,p,owner,sizeof owner);
        if (k<0 || limit-p<k+10) return 0;
        p+=k;
        unsigned len=word(p+8);
        if (i<word(buf+8) && word(p)==6 && word(p+2)==1 && len>=22) soa=1;
        if (limit-p-10<len) return 0;
        p+=10+len;
    }
    return p==limit && (addresses || soa) && remaining(end)>0;
}
static int cmp(const void *a,const void *b) { return memcmp(a,b,sizeof(struct address)); }
static int sample(struct answer *a,int64_t end) {
    if (!question(a,1,end) || !question(a,28,end) || a->depth[0]!=a->depth[1]) return 0;
    for (unsigned i=0;i<=a->depth[0];++i) if (strcasecmp(a->names[0][i],a->names[1][i])) return 0;
    qsort(a->addr,a->count,sizeof *a->addr,cmp);
    return 1;
}
/* Odin checks all families before the single numeric connect. */
int wb_resolve_fixed(uint8_t *addresses,int64_t end) {
    /* This profile trusts a privileged loopback stub. Refuse a namespace in
     * which an ordinary UID could replace its listener on TCP port 53. */
    FILE *config=fopen("/proc/sys/net/ipv4/ip_unprivileged_port_start","re");
    unsigned first=0;
    if (!config) return -1;
    int valid=fscanf(config,"%u",&first)==1 && first>53;
    fclose(config);
    if (!valid) return -1;
    struct answer x={0},y={0};
    if (!sample(&x,end) || !sample(&y,end)) return -1;
    if (x.count!=y.count || memcmp(x.addr,y.addr,x.count*sizeof *x.addr) || x.depth[0]!=y.depth[0]) return 0;
    for (unsigned i=0;i<=x.depth[0];++i) if (strcasecmp(x.names[0][i],y.names[0][i])) return 0;
    memcpy(addresses,x.addr,x.count*sizeof *x.addr);
    return (int)x.count;
}
int wb_connect_fixed(const uint8_t *bytes,int64_t end) {
    struct in_addr addr;
    memcpy(&addr,bytes,sizeof addr);
    return dial(addr,443,end);
}
