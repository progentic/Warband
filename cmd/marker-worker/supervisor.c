// One-shot trusted launcher. The administrator supplies a fresh, preconfigured cgroup leaf.
#define _GNU_SOURCE
#include "wire.h"
#include <dirent.h>
#include <fcntl.h>
#include <grp.h>
#include <linux/magic.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <sys/wait.h>

static int contents(int dir,const char *name,char *buf,size_t size) {
    int fd=openat(dir,name,O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if (fd<0) return -1;
    ssize_t n=read(fd,buf,size-1);
    close(fd);
    if (n<0 || (size_t)n==size-1) return -1;
    buf[n]=0;
    return 0;
}
static int equals(int dir,const char *name,const char *value) {
    char buf[256];
    return !contents(dir,name,buf,sizeof(buf)) && !strcmp(buf,value);
}
static int event_value(int cg,const char *file,const char *key,int value) {
    char buf[1024],line[80];
    if (contents(cg,file,buf,sizeof(buf))) return 0;
    snprintf(line,sizeof(line),"%s %d\n",key,value);
    const char *pos=strstr(buf,line);
    return pos && (pos==buf || pos[-1]=='\n');
}
static int membership(pid_t pid,char *buf,size_t size) {
    char path[64];
    snprintf(path,sizeof(path),"/proc/%d/cgroup",pid);
    if (contents(AT_FDCWD,path,buf,size) || strncmp(buf,"0::",3)) return 0;
    buf[strcspn(buf,"\n")]=0;
    return 1;
}
static int setfile(int dir,const char *name,const char *value) {
    int fd=openat(dir,name,O_WRONLY|O_CLOEXEC|O_NOFOLLOW);
    if (fd<0) return -1;
    size_t len=strlen(value);
    int ok=write(fd,value,len)==(ssize_t)len;
    return close(fd) || !ok ? -1 : 0;
}
static int trusted(const char *name,int dir) {
    struct stat st;
    return !lstat(name,&st) && (dir ? S_ISDIR(st.st_mode) : S_ISREG(st.st_mode)) &&
           !st.st_uid && !(st.st_mode&022) && (dir || st.st_nlink==1);
}
static int roles(const char *name,void *ids,size_t n) {
    if (!trusted(name,0)) return 0;
    int fd=open(name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if (fd<0) return 0;
    char extra;
    int ok=read(fd,ids,n)==(ssize_t)n && read(fd,&extra,1)==0;
    close(fd);
    return ok;
}
static int accept_runtime(uid_t runtime,pid_t *pid) {
    struct sockaddr_un addr={.sun_family=AF_UNIX,.sun_path="worker.sock"};
    int fd=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC|SOCK_NONBLOCK,0), peer=-1;
    if (fd<0 || bind(fd,(void *)&addr,sizeof(addr))) return -1;
    if (chmod(addr.sun_path,0666) || listen(fd,4)) goto done;
    printf("SupervisorReady %d\n",getpid()); fflush(stdout);
    int64_t until=wb_now()+180000,now;
    while ((now=wb_now())>=0 && now<until) {
        struct pollfd p={fd,POLLIN,0};
        if (poll(&p,1,(int)(until-now))!=1) break;
        peer=accept4(fd,NULL,NULL,SOCK_CLOEXEC|SOCK_NONBLOCK);
        if (peer<0) break;
        struct ucred cred; socklen_t len=sizeof(cred);
        if (!getsockopt(peer,SOL_SOCKET,SO_PEERCRED,&cred,&len) && len==sizeof(cred) &&
            cred.uid==runtime && cred.pid>0) { *pid=cred.pid; break; }
        close(peer); peer=-1;
    }
done:
    unlink(addr.sun_path); close(fd);
    return peer;
}
static void launch(int channel,int output,int barrier,uid_t worker,pid_t runtime,uid_t uid,pid_t parent) {
    char go,pid[32],user[32];
    struct rlimit core={0,0};
    if (read(barrier,&go,1)!=1 || go!='G' || dup2(channel,0)<0 || dup2(output,1)<0 ||
        dup2(output,2)<0 || close_range(3,~0U,0) || setrlimit(RLIMIT_CORE,&core) ||
        setgroups(0,NULL) || setresgid(worker,worker,worker) || setresuid(worker,worker,worker) ||
        prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=parent || prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)) _exit(120);
    snprintf(pid,sizeof(pid),"%d",runtime); snprintf(user,sizeof(user),"%u",uid);
    char *args[]={"marker-worker",pid,user,NULL}, *env[]={NULL};
    execve("./marker-worker",args,env);
    _exit(121);
}
static int confined(pid_t pid,uid_t uid,int cg,const struct stat *control,const struct stat *output) {
    char name[96],buf[8192],expected[128];
    snprintf(expected,sizeof(expected),"%d\n",pid);
    if (!equals(cg,"cgroup.procs",expected)) return 0;
    snprintf(name,sizeof(name),"/proc/%d/status",pid);
    if (contents(AT_FDCWD,name,buf,sizeof(buf))) return 0;
    snprintf(expected,sizeof(expected),"Uid:\t%u\t%u\t%u\t%u\n",uid,uid,uid,uid);
    if (!strstr(buf,expected) || !strstr(buf,"NoNewPrivs:\t1\n") || !strstr(buf,"Seccomp:\t2\n") ||
        !strstr(buf,"CapEff:\t0000000000000000\n")) return 0;
    snprintf(name,sizeof(name),"/proc/%d/fd",pid);
    DIR *fds=opendir(name);
    if (!fds) return 0;
    unsigned mask=0;
    struct dirent *entry;
    while ((entry=readdir(fds))) {
        if (entry->d_name[0]=='.') continue;
        char *end; long fd=strtol(entry->d_name,&end,10);
        struct stat st;
        if (*end || fd<0 || fd>2 || fstatat(dirfd(fds),entry->d_name,&st,0)) break;
        const struct stat *want=fd==0 ? control : output;
        if (st.st_dev!=want->st_dev || st.st_ino!=want->st_ino) break;
        mask |= 1U<<fd;
    }
    int ok=!entry && mask==7;
    closedir(fds);
    return ok;
}
static int give_channel(int runtime,int channel,struct wb_launch *info) {
    union {struct cmsghdr align; char data[CMSG_SPACE(sizeof(int))];} c={0};
    struct iovec io={info,sizeof(*info)};
    struct msghdr m={.msg_iov=&io,.msg_iovlen=1,.msg_control=c.data,.msg_controllen=sizeof(c.data)};
    struct cmsghdr *h=CMSG_FIRSTHDR(&m);
    h->cmsg_level=SOL_SOCKET; h->cmsg_type=SCM_RIGHTS; h->cmsg_len=CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(h),&channel,sizeof(channel));
    return sendmsg(runtime,&m,MSG_NOSIGNAL)==sizeof(*info);
}
// Discard raw output at ingress. Only a saturated byte count can leave this function.
static int drain(int fd,unsigned *count) {
    char scratch[512];
    ssize_t n=read(fd,scratch,sizeof(scratch));
    if (n<0) return errno==EAGAIN || errno==EINTR ? 1 : -1;
    *count+=(unsigned)n;
    if (*count>4096) *count=4097;
    return n ? 2 : 0;
}
static int supervise(int rt,pid_t runtime,uid_t uid,uid_t worker,int cg,const char *cgpath,int64_t end) {
    int pair[2],out[2],go[2];
    struct stat control,output;
    if (socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,pair) || wb_passcred(pair[0]) || wb_passcred(pair[1]) ||
        pipe2(out,O_CLOEXEC|O_NONBLOCK) || pipe2(go,O_CLOEXEC) || fstat(pair[1],&control) || fstat(out[1],&output)) return WB_FAILURE;
    pid_t parent=getpid();
    int timer=timerfd_create(CLOCK_BOOTTIME,TFD_CLOEXEC);
    int64_t start=wb_now(), until=start+5000;
    if (end<until) until=end;
    struct itimerspec ts={.it_value={until/1000,(until%1000)*1000000}};
    if (start<0 || until<=start || timer<0 || timerfd_settime(timer,TFD_TIMER_ABSTIME,&ts,NULL)) return WB_FAILURE;
    pid_t pid=fork();
    if (pid<0) return WB_FAILURE;
    if (!pid) { close(go[1]); launch(pair[1],out[1],go[0],worker,runtime,uid,parent); }
    close(pair[1]); close(out[1]); close(go[0]);
    int pidfd=syscall(SYS_pidfd_open,pid,0), result=WB_FAILURE,status=0,ready=0;
    unsigned count=0;
    char member[40]; snprintf(member,sizeof(member),"%d",pid);
    if (pidfd<0 || setfile(cg,"cgroup.procs",member) || write(go[1],"G",1)!=1) goto stop;
    for (;;) {
        struct pollfd p[]={{timer,POLLIN,0},{rt,POLLIN,0},{pair[0],POLLIN,0},{out[0],POLLIN,0},{pidfd,POLLIN,0}};
        if (poll(p,5,-1)<0) { if (errno==EINTR) continue; break; }
        if (p[0].revents || wb_now()>=until) { result=WB_TIME; break; }
        if (p[1].revents) break; // runtime disconnected or sent an unexpected second launch
        if (p[3].revents && drain(out[0],&count)<0) break;
        if (count>4096) { result=WB_OUTPUT; break; }
        if (!ready && p[2].revents) {
            char ack;
            if (wb_from(pair[0],&ack,1,pid,worker)!=1 || ack!='R' || !confined(pid,worker,cg,&control,&output)) break;
            char supervisor_group[512],runtime_group[512],worker_group[512];
            if (!membership(parent,supervisor_group,sizeof(supervisor_group)) ||
                !membership(runtime,runtime_group,sizeof(runtime_group)) || !membership(pid,worker_group,sizeof(worker_group)) ||
                !strcmp(worker_group,supervisor_group) || !strcmp(worker_group,runtime_group)) break;
            printf("WorkerProfile supervisor=%d runtime=%d worker=%d uid=%u group=%s fds=0,1,2 memory=33554432 swap=0 pids=1 start=%lld until=%lld supervisor_group=%s runtime_group=%s worker_group=%s\n",
                   parent,runtime,pid,worker,cgpath,(long long)start,(long long)until,supervisor_group+3,runtime_group+3,worker_group+3);
            fflush(stdout);
            struct wb_launch info={pid,worker,until};
            if (!give_channel(rt,pair[0],&info)) break;
            close(pair[0]); pair[0]=-1; ready=1;
        }
        if (p[4].revents) { result=ready ? WB_CLEAN : WB_FAILURE; break; }
    }
stop:
    if (result!=WB_CLEAN) { (void)setfile(cg,"cgroup.kill","1"); kill(pid,SIGKILL); }
    pid_t reaped; do { reaped=waitpid(pid,&status,0); } while (reaped<0 && errno==EINTR);
    int more;
    do { more=drain(out[0],&count); } while (more==2);
    int empty=event_value(cg,"cgroup.events","populated",0) && equals(cg,"cgroup.procs","");
    if (more!=0 || reaped!=pid || !empty) result=0; // no stop proof leaves the runtime channel silent
    else if (count>4096) result=WB_OUTPUT;
    else if (event_value(cg,"memory.events.local","oom_kill",1)) result=WB_MEMORY;
    else if (result==WB_CLEAN && (!WIFEXITED(status) || WEXITSTATUS(status))) result=WB_FAILURE;
    printf("WorkerStop pid=%d reaped=%d populated_empty=%d output=%u result=%d elapsed=%lld\n",
           pid,reaped==pid,empty,count,result,(long long)(wb_now()-start));
    close(go[1]); if (pair[0]>=0) close(pair[0]); close(out[0]); close(timer); if (pidfd>=0) close(pidfd);
    return result;
}
int main(int argc,char **argv) {
    uid_t ids[2],worker,cust;
    uint8_t anchor[68];
    if (argc!=2 || geteuid() || !trusted(".",1) || !trusted("marker-worker",0) ||
        !roles("approval.ids",ids,sizeof(ids)) || !roles("worker.uid",&worker,sizeof(worker)) ||
        !roles("intake.anchor",anchor,sizeof(anchor))) return 2;
    memcpy(&cust,anchor+64,4);
    if (!worker || !ids[0] || worker==cust || worker==ids[0] || worker==ids[1]) return 2;
    int cg=open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    struct statfs fs;
    if (cg<0 || fstatfs(cg,&fs) || fs.f_type!=CGROUP2_SUPER_MAGIC || !equals(cg,"cgroup.procs","") ||
        !event_value(cg,"cgroup.events","populated",0) || !event_value(cg,"cgroup.stat","nr_descendants",0) ||
        !event_value(cg,"memory.events.local","oom_kill",0) || !equals(cg,"memory.max","33554432\n") || !equals(cg,"memory.swap.max","0\n") || !equals(cg,"pids.max","1\n")) return 3;
    pid_t runtime=0;
    int rt=accept_runtime(ids[0],&runtime);
    if (rt<0) return 4;
    int64_t end; struct pollfd p={rt,POLLIN,0};
    if (poll(&p,1,180000)!=1 || recv(rt,&end,sizeof(end),MSG_TRUNC)!=sizeof(end)) return 4;
    uint8_t result=supervise(rt,runtime,ids[0],worker,cg,argv[1],end);
    int suppress=0;
#ifdef WB_COMPLETION_PROOF
    char mode=0;
    suppress=roles("completion.probe",&mode,1) && mode=='u';
#endif
    // Receipt of this byte proves reaping and an empty worker cgroup; silence withholds that proof.
    int sent=result && !suppress && send(rt,&result,1,MSG_NOSIGNAL)==1;
    return result==WB_CLEAN && sent ? 0 : 1;
}
