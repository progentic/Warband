// One connected SEQPACKET channel per attempt. Linux x86-64 wire integers are little-endian.
#ifndef WB_WORKER_WIRE_H
#define WB_WORKER_WIRE_H
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define WB_MAX 4096
struct wb_request {
    char tag[4];
    uint32_t length;
    uint64_t device, inode;
    int64_t deadline;
    uint8_t claim[32], attempt[16], capability[16], directory[16], binding[32], digest[32], payload[WB_MAX];
};
#define WB_HEADER __builtin_offsetof(struct wb_request,payload)
_Static_assert(WB_HEADER==176,"marker request header");
struct wb_launch { int32_t pid; uint32_t uid; int64_t until; };
enum wb_effect { WB_CREATED=1, WB_OCCUPIED, WB_REFUSED, WB_STORAGE, WB_DUPLICATE };
enum wb_stop { WB_CLEAN=1, WB_TIME, WB_OUTPUT, WB_MEMORY, WB_FAILURE };
static inline int64_t wb_now(void) {
    struct timespec ts;
    return clock_gettime(CLOCK_BOOTTIME,&ts) ? -1 : ts.tv_sec*1000+ts.tv_nsec/1000000;
}
static inline int wb_passcred(int fd) {
    int yes=1;
    return setsockopt(fd,SOL_SOCKET,SO_PASSCRED,&yes,sizeof(yes));
}
// Fail on missing/extra control data, truncation, wrong identity or excessive length.
static inline int wb_from(int fd,void *buf,size_t cap,pid_t pid,uid_t uid) {
    union { struct cmsghdr align; char buf[CMSG_SPACE(sizeof(struct ucred))]; } c;
    struct iovec io={buf,cap};
    struct msghdr m={.msg_iov=&io,.msg_iovlen=1,.msg_control=c.buf,.msg_controllen=sizeof(c.buf)};
    ssize_t n=recvmsg(fd,&m,MSG_TRUNC|MSG_CMSG_CLOEXEC);
    struct cmsghdr *h=CMSG_FIRSTHDR(&m);
    if (!n) return 0;
    if (n<0 || (size_t)n>cap || m.msg_flags&(MSG_TRUNC|MSG_CTRUNC) || !h ||
        h->cmsg_level!=SOL_SOCKET || h->cmsg_type!=SCM_CREDENTIALS ||
        h->cmsg_len!=CMSG_LEN(sizeof(struct ucred)) || CMSG_NXTHDR(&m,h)) return -1;
    struct ucred who;
    memcpy(&who,CMSG_DATA(h),sizeof(who));
    return who.pid==pid && who.uid==uid ? (int)n : -1;
}
#endif
