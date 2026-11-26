#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <fcntl.h>
#include <time.h>
#include <unistd.h>

int64_t wb_elapsed_ms(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_BOOTTIME, &t)) return -1;
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
int64_t wb_recorded_us(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_REALTIME, &t) || t.tv_sec < 0) return -1;
    return (int64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000;
}
int wb_writer_gate(const char *path) {
    int fd = open(path, O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_nlink != 1 ||
        flock(fd, LOCK_EX|LOCK_NB)) { close(fd); return -1; }
    return fd;
}
void wb_release_gate(int fd) { close(fd); }

static int wait_io(int fd, short events, int64_t deadline) {
    struct pollfd p = {fd, events, 0};
    for (;;) {
        int64_t now = wb_elapsed_ms();
        if (now < 0 || now >= deadline) return -1;
        int n = poll(&p, 1, (int)(deadline-now));
        if (n < 0 && errno == EINTR) continue;
        return n > 0 ? 0 : -1;
    }
}
int wb_exchange(const char *path, uint32_t uid, const uint8_t *data, int len,
                uint8_t *reply, int cap, int64_t deadline) {
    struct sockaddr_un addr = {.sun_family=AF_UNIX};
    if (strlen(path) >= sizeof(addr.sun_path)) return -1;
    strcpy(addr.sun_path, path);
    int fd = socket(AF_UNIX, SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    int result = -1, used = 0;
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr))) goto done;
    struct ucred peer;
    socklen_t size = sizeof(peer);
    if (getsockopt(fd,SOL_SOCKET,SO_PEERCRED,&peer,&size) ||
        size != sizeof(peer) || peer.pid <= 0 || peer.uid != uid || peer.uid == geteuid()) goto done;
    while (len) {
        if (wait_io(fd,POLLOUT,deadline)) goto done;
        ssize_t n = send(fd,data,len,MSG_NOSIGNAL);
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        if (n <= 0) goto done;
        data += n; len -= (int)n;
    }
    if (shutdown(fd,SHUT_WR)) goto done;
    while (used < cap) {
        if (wait_io(fd,POLLIN,deadline)) goto done;
        ssize_t n = recv(fd,reply+used,cap-used,0);
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        if (n < 0) goto done;
        if (!n) { result = used; break; }
        used += (int)n;
    }
done:
    close(fd);
    return result;
}

// The launcher selects a root-owned store. Its root-controlled role file contains
// the runtime and operator UIDs as two little-endian u32s on Linux x64.
int wb_approval_roles(int server, uint32_t *expected_uid) {
    struct stat root, st;
    if (stat(".", &root) || root.st_uid || (root.st_mode & 022)) return -1;
    int roles = open("approval.ids", O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);
    if (roles < 0) return -1;
    uint32_t uid[2];
    int trusted = !fstat(roles, &st) && S_ISREG(st.st_mode) && !st.st_uid &&
        !(st.st_mode & 022) && st.st_nlink == 1 && st.st_size == sizeof(uid) &&
        read(roles, uid, sizeof(uid)) == sizeof(uid);
    close(roles);
    if (!trusted || !uid[0] || !uid[1] || uid[0] == uid[1] ||
        geteuid() != uid[server ? 0 : 1]) return -1;
    *expected_uid = uid[server ? 1 : 0];
    return 0;
}
int wb_approval_socket(int server, uint32_t *expected_uid) {
    struct stat root;
    if (wb_approval_roles(server,expected_uid) || stat(".", &root)) return -1;
    struct sockaddr_un addr = {.sun_family=AF_UNIX};
    int n = snprintf(addr.sun_path+1, sizeof(addr.sun_path)-1, "warband.approval.%llu.%llu",
                     (unsigned long long)root.st_dev, (unsigned long long)root.st_ino);
    if (n < 0 || (size_t)n >= sizeof(addr.sun_path)-1) return -1;
    socklen_t len = offsetof(struct sockaddr_un, sun_path)+1+n;
    int fd = socket(AF_UNIX, SOCK_SEQPACKET|SOCK_CLOEXEC|SOCK_NONBLOCK, 0);
    if (fd < 0) return -1;
    int failed = server ? (bind(fd,(struct sockaddr *)&addr,len) || listen(fd,1))
                        : connect(fd,(struct sockaddr *)&addr,len);
    if (failed) { close(fd); return -1; }
    return fd;
}
int wb_approval_peer(int fd, uint32_t expected, uint32_t *actual) {
    struct ucred peer;
    socklen_t size = sizeof(peer);
    if (getsockopt(fd,SOL_SOCKET,SO_PEERCRED,&peer,&size) ||
        size != sizeof(peer) || peer.pid <= 0 || peer.uid != expected) return -1;
    *actual = peer.uid;
    return 0;
}
// A foreign peer cannot consume the issuer's only review opportunity.
int wb_approval_accept(int listener, uint32_t expected, int64_t deadline) {
    while (!wait_io(listener,POLLIN,deadline)) {
        int fd = accept4(listener,NULL,NULL,SOCK_CLOEXEC|SOCK_NONBLOCK);
        if (fd < 0) return -1;
        uint32_t uid;
        if (!wb_approval_peer(fd,expected,&uid)) return fd;
        close(fd);
    }
    return -1;
}
// SEQPACKET preserves message boundaries. MSG_TRUNC exposes oversized input.
int wb_approval_packet(int fd, void *buf, int size, int writing, int64_t deadline) {
    if (wait_io(fd,writing ? POLLOUT : POLLIN,deadline)) return -1;
    return writing ? (int)send(fd,buf,size,MSG_NOSIGNAL) : (int)recv(fd,buf,size,MSG_TRUNC);
}
