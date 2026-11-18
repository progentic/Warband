// Linux-only Low adapters. Callers serialize every operation with the data-directory lock.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int data = -1, endpoints = -1, journal = -1;
static uid_t operator_uid;
struct peer { int32_t pid; uint32_t uid, gid; };
_Static_assert(sizeof(struct peer) == sizeof(struct ucred), "Linux peer credential ABI");

static int owned_dir(int parent, const char *name, uid_t owner, int mode) {
    int fd = openat(parent, name, O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC|O_RDONLY);
    struct stat s;
    if (fd < 0) return -1;
    if (fstat(fd, &s) || s.st_uid != owner || (s.st_mode & 07777) != (unsigned)mode) {
        close(fd);
        return -1;
    }
    return fd;
}

// The configured root is one root-owned component below /var/lib.
// Root and the custodian are trusted; the operator owns only the quiesced journal.
int wb_lock(const char *name, uint32_t runtime, uint32_t operator) {
    if (!*name || strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, "..") ||
        !geteuid() || !runtime || !operator || runtime == operator ||
        geteuid() == runtime || geteuid() == operator) return -1;
    int fd = open("/", O_DIRECTORY|O_RDONLY|O_CLOEXEC);
    const char *parts[] = {"var", "lib", name};
    for (size_t i = 0; i < 3; i++) {
        int next = owned_dir(fd, parts[i], 0, 0755);
        close(fd);
        if (next < 0) return -1;
        fd = next;
    }
    data = owned_dir(fd, "data", geteuid(), 0700);
    endpoints = owned_dir(fd, "endpoints", geteuid(), 0755);
    // Evaluate the journal at enrollment, so an invalid directory cannot be enrolled.
    journal = fd;
    operator_uid = operator;
    return data >= 0 && endpoints >= 0 && flock(data, LOCK_EX|LOCK_NB) == 0 ? 0 : -1;
}

void wb_unlock(void) {
    if (journal >= 0) close(journal);
    if (endpoints >= 0) close(endpoints);
    if (data >= 0) close(data);
}

int wb_empty_journal(void) {
    int fd = owned_dir(journal, "journal", operator_uid, 0555);
    if (fd < 0) return 0;
    DIR *dir = fdopendir(fd);
    if (!dir) { close(fd); return 0; }
    errno = 0;
    struct dirent *entry;
    int empty = 1;
    while ((entry = readdir(dir))) {
        if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, "..")) { empty = 0; break; }
    }
    if (errno) empty = 0;
    return closedir(dir) == 0 && empty;
}

static int regular(int fd) {
    struct stat s;
    return fstat(fd, &s) == 0 && S_ISREG(s.st_mode) && s.st_nlink == 1 &&
           (s.st_mode & 07777) == 0600 && s.st_uid == geteuid();
}

static int open_file(const char *name, int flags) {
    int fd = openat(data, name, flags|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600);
    if (fd >= 0 && !regular(fd)) { close(fd); errno = EPERM; return -1; }
    return fd;
}

// -1 missing, -2 storage/boundary failure, -3 allocation limit.
int64_t wb_size(const char *name) {
    int fd = open_file(name, O_RDONLY);
    if (fd < 0) return errno == ENOENT ? -1 : -2;
    struct stat s;
    int ok = fstat(fd, &s) == 0;
    close(fd);
    return ok ? s.st_size : -2;
}

int wb_read(const char *name, uint8_t *buf, size_t size) {
    int fd = open_file(name, O_RDONLY);
    if (fd < 0) return -1;
    size_t done = 0;
    while (done < size) {
        ssize_t n = read(fd, buf+done, size-done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { close(fd); return -1; }
        done += n;
    }
    unsigned char extra;
    int ok = read(fd, &extra, 1) == 0;
    return close(fd) == 0 && ok ? 0 : -1;
}

static int write_all(int fd, const uint8_t *buf, size_t size) {
    while (size) {
        ssize_t n = write(fd, buf, size);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        buf += n; size -= n;
    }
    return 0;
}

int wb_append(const uint8_t *buf, size_t size, int first, int sync_directory) {
    int fd = open_file("history", O_WRONLY|O_APPEND|(first ? O_CREAT : 0));
    if (fd < 0) return -1;
    int ok = write_all(fd, buf, size) == 0 && fsync(fd) == 0;
    if (close(fd) || !ok) return -1;
    if (!sync_directory) return 0;
#ifdef WB_TEST_DIRSYNC_FAILURE
    return fsync(-1);
#else
    return fsync(data);
#endif
}

int wb_publish(const uint8_t *buf, size_t size) {
    if (unlinkat(data, "head.tmp", 0) && errno != ENOENT) return -1;
    int fd = open_file("head.tmp", O_CREAT|O_EXCL|O_WRONLY);
    if (fd < 0) return -1;
    int ok = write_all(fd, buf, size) == 0 && fsync(fd) == 0;
    if (close(fd) || !ok || renameat(data,"head.tmp",data,"head")) return -1;
    return fsync(data);
}

int wb_sync_history(int64_t truncate_to) {
    int fd = open_file("history", O_RDWR);
    if (fd < 0) return -1;
    int ok = (truncate_to < 0 || ftruncate(fd, truncate_to) == 0) && fsync(fd) == 0;
    return close(fd) == 0 && ok ? 0 : -1;
}

static const char *socket_name(int admin) { return admin ? "operator.sock" : "runtime.sock"; }

int wb_listen(int admin) {
    const char *name = socket_name(admin);
    struct stat s;
    if (fstatat(endpoints,name,&s,AT_SYMLINK_NOFOLLOW) == 0) {
        if (!S_ISSOCK(s.st_mode) || s.st_uid != geteuid() || unlinkat(endpoints,name,0)) return -1;
    } else if (errno != ENOENT) return -1;
    struct sockaddr_un addr = {.sun_family=AF_UNIX};
    snprintf(addr.sun_path,sizeof(addr.sun_path),"/proc/self/fd/%d/%s",endpoints,name);
    int fd = socket(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0);
    if (fd < 0) return -1;
    mode_t old = umask(0111);
    int rc = bind(fd,(struct sockaddr *)&addr,sizeof(addr));
    umask(old);
    if (rc || listen(fd,16)) { close(fd); return -1; }
    return fd;
}

int wb_wait(int runtime, int admin) {
    struct pollfd fds[2] = {{runtime,POLLIN,0},{admin,POLLIN,0}};
    int n;
    do { n = poll(fds,2,-1); } while (n < 0 && errno == EINTR);
    if (n > 0 && (fds[0].revents & POLLIN)) return runtime;
    if (n > 0 && (fds[1].revents & POLLIN)) return admin;
    return -1;
}
int wb_accept(int fd) { return accept4(fd,NULL,NULL,SOCK_CLOEXEC|SOCK_NONBLOCK); }
void wb_close(int fd) { close(fd); }
int wb_peer(int fd, struct peer *p) {
    struct ucred u;
    socklen_t len = sizeof(u);
    if (getsockopt(fd,SOL_SOCKET,SO_PEERCRED,&u,&len) || len != sizeof(u) || u.pid <= 0) return -1;
    p->uid=u.uid; p->gid=u.gid; p->pid=u.pid;
    return 0;
}

int64_t wb_millis(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME,&ts)) return -1;
    return ts.tv_sec*1000 + ts.tv_nsec/1000000;
}

// One bounded WBCR request per connection. Retain the actually observed prefix.
size_t wb_request(int fd, uint8_t *buf, size_t cap, int *complete, int64_t deadline) {
    size_t used = 0, needed = 11;
    *complete = 0;
    while (used < needed) {
        int64_t now = wb_millis();
        if (now < deadline - 30000 || now >= deadline) return used;
        struct pollfd p = {fd,POLLIN,0};
        if (poll(&p,1,(int)(deadline-now)) <= 0) return used;
        ssize_t n = recv(fd,buf+used,needed-used,0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return used;
        used += n;
        if (used == 11) {
            uint32_t len = (uint32_t)buf[7] | (uint32_t)buf[8]<<8 | (uint32_t)buf[9]<<16 | (uint32_t)buf[10]<<24;
            needed = len > cap-11 ? cap : 11+len;
            if (len > cap-11) return used;
        }
    }
    if (used < cap) {
        ssize_t more = recv(fd,buf+used,cap-used,MSG_DONTWAIT);
        if (more > 0) return used+(size_t)more;
        if (more < 0 && errno != EAGAIN && errno != EWOULDBLOCK) return used;
    }
    *complete = 1;
    return used;
}

int wb_reply(int fd,const uint8_t *buf,size_t size, int64_t deadline) {
    while (size) {
        int64_t now = wb_millis();
        if (now < deadline - 30000 || now >= deadline) return -1;
        struct pollfd p = {fd,POLLOUT,0};
        if (poll(&p,1,(int)(deadline-now)) <= 0) return -1;
        ssize_t n = send(fd,buf,size,MSG_NOSIGNAL);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) return -1;
        buf += n;
        size -= n;
    }
    return 0;
}
