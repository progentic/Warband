// Trusted Linux broker: the worker can only echo its one bounded order on its private fd.
#define _GNU_SOURCE
#include "../../cmd/marker-worker/wire.h"
#include <fcntl.h>
#include <linux/if_alg.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/un.h>

struct wb_outcome { uint8_t delivery, stopped, writer_closed, effect; };
#ifdef WB_COMPLETION_PROOF
#define wb_execute_marker wb_execute_marker_proof
static char proof_mode(void) {
    struct stat st;
    char mode=0,extra;
    int fd=open("completion.probe",O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if (fd<0 || fstat(fd,&st) || !S_ISREG(st.st_mode) || st.st_uid || st.st_nlink!=1 || st.st_mode&022 || st.st_size!=1 ||
        read(fd,&mode,1)!=1 || read(fd,&extra,1)!=0 || close(fd)) return 0;
    return mode;
}
#else
static char proof_mode(void) { return 0; }
#endif

static int readable(int fd,int64_t until) {
    int64_t now=wb_now();
    if (now<0 || now>=until) return 0;
    struct pollfd p={fd,POLLIN,0};
    return poll(&p,1,(int)(until-now))==1;
}
static int payload_matches(const struct wb_request *q) {
    struct sockaddr_alg a={.salg_family=AF_ALG,.salg_type="hash",.salg_name="sha256"};
    int alg=socket(AF_ALG,SOCK_SEQPACKET|SOCK_CLOEXEC,0), op=-1, ok=0;
    uint8_t digest[32];
    if (alg>=0 && !bind(alg,(void *)&a,sizeof(a)) && (op=accept4(alg,NULL,NULL,SOCK_CLOEXEC))>=0)
        ok=send(op,q->payload,q->length,MSG_NOSIGNAL)==q->length && read(op,digest,sizeof(digest))==sizeof(digest) &&
           !memcmp(digest,q->digest,sizeof(digest));
    if (op>=0) close(op);
    if (alg>=0) close(alg);
    return ok;
}
static int directory_matches(int fd,const struct wb_request *q) {
    struct stat held,named,st;
    if (fstat(fd,&held) || !S_ISDIR(held.st_mode) || (held.st_mode&07777)!=0700 || held.st_uid!=geteuid() ||
        held.st_dev!=q->device || held.st_ino!=q->inode) return 0;
    char name[33];
    for (int i=0;i<16;i++) snprintf(name+i*2,3,"%02x",q->directory[i]);
    int parent=open("attempts",O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
    if (parent<0) return 0;
    int same=!fstat(parent,&st) && st.st_uid==geteuid() && (st.st_mode&07777)==0700 &&
        !fstatat(parent,name,&named,AT_SYMLINK_NOFOLLOW) && named.st_dev==held.st_dev && named.st_ino==held.st_ino;
    close(parent);
    return same;
}
// The independent occupancy test calls this same operation with the first inode still present.
static int exclusive_create(int directory,const uint8_t *bytes,size_t n,int64_t until,int *closed) {
    int64_t now=wb_now();
    if (n>WB_MAX || now<0 || now>=until) return WB_REFUSED;
    int fd=openat(directory,"marker",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd<0) return errno==EEXIST ? WB_OCCUPIED : WB_STORAGE;
    *closed=0;
    size_t at=0;
    while (at<n) {
        now=wb_now();
        if (now<0 || now>=until) break;
        ssize_t written=write(fd,bytes+at,n-at);
        if (written<=0) break;
        at+=(size_t)written;
    }
    int synced=at==n && !fsync(fd);
    *closed=close(fd)==0;
    if (!synced || !*closed || fsync(directory) || wb_now()>=until) return WB_STORAGE;
    return WB_CREATED;
}
#ifdef WB_COMPLETION_PROOF
static int fault_create(int directory,const uint8_t *bytes,size_t n,int64_t until,int *closed,char mode) {
    if (mode=='a') { *closed=1; return WB_STORAGE; }
    if (mode!='p' && mode!='c') return exclusive_create(directory,bytes,n,until,closed);
    int fd=openat(directory,"marker",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd<0) return errno==EEXIST ? WB_OCCUPIED : WB_STORAGE;
    *closed=0;
    uint8_t changed[WB_MAX];
    size_t count=n;
    if (mode=='p') count=n>1 ? n-1 : 0;
    else { memcpy(changed,bytes,n); if (n) changed[0]^=1; else { changed[0]=1; count=1; } bytes=changed; }
    int complete=(count==0 || write(fd,bytes,count)==(ssize_t)count) && !fsync(fd);
    *closed=close(fd)==0;
    if (complete && *closed) (void)fsync(directory);
    return WB_STORAGE;
}
#endif
#ifdef WB_OCCUPANCY_TEST
int main(int argc,char **argv) {
    int fd=(argc==2 || argc==3) ? open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC) : -1, closed=1;
    if (fd<0) return 2;
    int result=exclusive_create(fd,(const uint8_t *)"different",9,wb_now()+(argc==3 ? -1 : 1000),&closed);
    printf("ExclusiveResult %d\n",result);
    return result==(argc==3 ? WB_REFUSED : WB_OCCUPIED) ? 0 : 1;
}
#endif
static int worker_channel(int rt,struct wb_launch *worker) {
    union {struct cmsghdr align; char data[CMSG_SPACE(sizeof(int))];} c;
    struct iovec io={worker,sizeof(*worker)};
    struct msghdr m={.msg_iov=&io,.msg_iovlen=1,.msg_control=c.data,.msg_controllen=sizeof(c.data)};
    ssize_t n=recvmsg(rt,&m,MSG_CMSG_CLOEXEC|MSG_TRUNC);
    struct cmsghdr *h=CMSG_FIRSTHDR(&m);
    if (n!=sizeof(*worker) || m.msg_flags&(MSG_TRUNC|MSG_CTRUNC) || !h || h->cmsg_level!=SOL_SOCKET ||
        h->cmsg_type!=SCM_RIGHTS || h->cmsg_len!=CMSG_LEN(sizeof(int)) || CMSG_NXTHDR(&m,h)) return -1;
    int fd;
    memcpy(&fd,CMSG_DATA(h),sizeof(fd));
    return fd;
}
int wb_execute_marker(int directory,const struct wb_request *q,struct wb_outcome *outcome) {
    *outcome=(struct wb_outcome){.delivery=5,.writer_closed=1};
    if (geteuid()==0 || memcmp(q->tag,"WBM1",4) || q->length>WB_MAX || !directory_matches(directory,q) ||
        !payload_matches(q)) return 0;
    int64_t now=wb_now();
    if (now<0 || now>=q->deadline) return 0;
    int rt=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC|SOCK_NONBLOCK,0), fd=-1, ok=0;
    struct sockaddr_un addr={.sun_family=AF_UNIX,.sun_path="worker.sock"};
    struct ucred supervisor; socklen_t len=sizeof(supervisor);
    struct wb_launch w;
    if (rt<0 || connect(rt,(void *)&addr,sizeof(addr)) || getsockopt(rt,SOL_SOCKET,SO_PEERCRED,&supervisor,&len) ||
        len!=sizeof(supervisor) || supervisor.uid!=0 || supervisor.pid<=0 ||
        send(rt,&q->deadline,sizeof(q->deadline),MSG_NOSIGNAL)!=sizeof(q->deadline) || !readable(rt,q->deadline) ||
        (fd=worker_channel(rt,&w))<0 || w.pid<=0 || !w.uid || w.uid==geteuid() ||
        w.until>q->deadline || wb_now()>=w.until) goto done;
    size_t size=WB_HEADER+q->length;
    if (send(fd,q,size,MSG_NOSIGNAL)!= (ssize_t)size) goto done;
    char proof=proof_mode();
    unsigned attempts=0;
    int effect=0, closed=1, offered=-1, delivered=0;
    while (readable(fd,w.until)) {
        union {struct wb_request q; uint8_t bytes[sizeof(struct wb_request)+1];} received;
        int n=wb_from(fd,received.bytes,sizeof(received.bytes),w.pid,w.uid);
        if (n<=0) { if (n<0) delivered=0; break; }
        uint8_t reply=WB_DUPLICATE;
        if (!attempts) {
            effect=WB_REFUSED;
            offered=n>=(int)WB_HEADER ? n-(int)WB_HEADER : -1;
            if (n==(int)size && received.q.length<=WB_MAX && !memcmp(received.bytes,q,size) &&
                payload_matches(&received.q) && directory_matches(directory,q)) {
#ifdef WB_COMPLETION_PROOF
                effect=fault_create(directory,received.q.payload,received.q.length,w.until,&closed,proof);
#else
                effect=exclusive_create(directory,received.q.payload,received.q.length,w.until,&closed);
#endif
            }
            reply=(uint8_t)effect;
        }
        attempts++;
        delivered=proof!='l' && send(fd,&reply,1,MSG_NOSIGNAL)==1;
        if (!delivered || attempts>=2) break;
    }
    close(fd); fd=-1;
    uint8_t stop=0;
    if (!readable(rt,w.until+2000) || recv(rt,&stop,1,MSG_TRUNC)!=1) stop=0;
    printf("BrokerStop worker=%d effect=%d writer_closed=%d requests=%u stop=%u offered_bytes=%d\n",w.pid,effect,closed,attempts,stop,offered);
    fflush(stdout);
    outcome->effect=(uint8_t)effect;
    outcome->writer_closed=(uint8_t)closed;
    outcome->stopped=(uint8_t)(stop!=0);
    if (delivered) outcome->delivery=1;
    else if (effect==WB_CREATED) outcome->delivery=2;
    else if (stop==WB_TIME) outcome->delivery=3;
    else if (stop) outcome->delivery=4;
    ok=effect==WB_CREATED && delivered && closed && stop==WB_CLEAN;
done:
    if (fd>=0) close(fd);
    if (rt>=0) close(rt);
    return ok;
}
