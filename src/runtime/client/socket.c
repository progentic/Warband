#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdint.h>
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
