// Linux-only Low adapters. Callers serialize every operation with the data-directory lock.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <endian.h>
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

#ifdef WB_TEST_APPEND_MODE
_Static_assert(WB_TEST_APPEND_KIND >= 1 && WB_TEST_APPEND_KIND <= 4, "unsupported append kind");
_Static_assert(WB_TEST_APPEND_MODE >= 1 && WB_TEST_APPEND_MODE <= 3, "expected append error mode");
static int proof_fd = -1;
static size_t proof_size;
static ssize_t proof_write(int fd, const uint8_t *buf, size_t size) {
    if (fd != proof_fd) return write(fd, buf, size);
    size_t count = size;
    if (WB_TEST_APPEND_MODE != 3) {
        if (size == proof_size) count = WB_TEST_APPEND_KIND == 2 ? 250 : 83;
        else if (WB_TEST_APPEND_MODE == 2) {
            fprintf(stderr, "append_write %zu -1 ENOSPC\n", size);
            errno = ENOSPC;
            return -1;
        }
    }
    ssize_t n = write(fd, buf, count);
    int saved = errno;
    fprintf(stderr, "append_write %zu %zd\n", size, n);
    errno = saved;
    return n;
}
static int proof_fsync(int fd) {
    if (fd == proof_fd && WB_TEST_APPEND_MODE == 3) {
        fprintf(stderr, "append_fsync -1 EIO\n");
        errno = EIO;
        return -1;
    }
    return fsync(fd);
}
#elif defined(WB_TEST_HEAD_ERROR)
_Static_assert(WB_TEST_HEAD_ERROR >= 1 && WB_TEST_HEAD_ERROR <= 5, "unsupported publication error");
static int head_fd = -1, first_commit_appended;
static ssize_t proof_write(int fd, const uint8_t *buf, size_t size) {
    if (fd != head_fd) return write(fd, buf, size);
    size_t count = size;
    if (WB_TEST_HEAD_ERROR <= 2) {
        if (size == 134) count = 102;
        else if (WB_TEST_HEAD_ERROR == 2) {
            fprintf(stderr, "tmp_write %zu -1 ENOSPC\n", size);
            errno = ENOSPC;
            return -1;
        }
    }
    ssize_t n = write(fd, buf, count);
    int saved = errno;
    fprintf(stderr, "tmp_write %zu %zd\n", size, n);
    errno = saved;
    return n;
}
#define proof_fsync fsync
#else
#define proof_write write
#define proof_fsync fsync
#endif

static int write_all(int fd, const uint8_t *buf, size_t size) {
    while (size) {
        ssize_t n = proof_write(fd, buf, size);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        buf += n; size -= n;
    }
    return 0;
}

#if defined(WB_TEST_PUBLISH_STOP) || defined(WB_TEST_PENDING_BYTES) || defined(WB_TEST_COMMITTED_STOP) || defined(WB_TEST_ADMIN_STOP)
#include <signal.h>
#endif
#if defined(WB_TEST_PUBLISH_STOP) || defined(WB_TEST_COMMITTED_STOP) || defined(WB_TEST_HEAD_ERROR)
static int is_first_commit(const uint8_t *buf, size_t size) {
    static const uint8_t one_le[8] = {1};
    return size == 251 && buf[6] == 2 && !memcmp(buf+83+64, one_le, 8);
}
#endif
#ifdef WB_TEST_PUBLISH_STOP
static int first_commit_appended;
static void publication_stop(int edge) {
    if (first_commit_appended && edge == WB_TEST_PUBLISH_STOP) raise(SIGSTOP);
}
#else
#define publication_stop(edge) ((void)0)
#endif

#ifdef WB_TEST_ADMIN_STOP
// 1..3 select GENESIS. 4..5 select EPOCH; startup republishes without appending.
_Static_assert(WB_TEST_ADMIN_STOP >= 1 && WB_TEST_ADMIN_STOP <= 5, "unsupported admin stop");
static int epoch_appended;
#endif

int wb_append(const uint8_t *buf, size_t size, int first, int sync_directory) {
    int fd = open_file("history", O_WRONLY|O_APPEND|(first ? O_CREAT : 0));
    if (fd < 0) return -1;
#ifdef WB_TEST_ADMIN_STOP
    const int admin = size >= 83 && buf[6] == (WB_TEST_ADMIN_STOP <= 3 ? 3 : 4);
    if (admin && (WB_TEST_ADMIN_STOP <= 2 || WB_TEST_ADMIN_STOP == 4)) {
        const size_t prefix = WB_TEST_ADMIN_STOP == 1 ? 0 : 83;
        if ((prefix && write_all(fd, buf, prefix)) || raise(SIGSTOP)) {
            close(fd);
            return -1;
        }
        buf += prefix;
        size -= prefix;
    }
#endif
#ifdef WB_TEST_PENDING_BYTES
    _Static_assert(WB_TEST_PENDING_BYTES == 0 || WB_TEST_PENDING_BYTES == 83, "unsupported PENDING stop");
    static const uint8_t first_sequence[8] = {1};
    if (size == 251 && buf[6] == 1 && !memcmp(buf+83+64, first_sequence, 8)) {
        const size_t prefix = WB_TEST_PENDING_BYTES;
        if ((prefix && write_all(fd, buf, prefix)) || raise(SIGSTOP)) {
            close(fd);
            return -1;
        }
        buf += prefix;
        size -= prefix;
    }
#endif
#ifdef WB_TEST_COMMITTED_STOP
    _Static_assert(WB_TEST_COMMITTED_STOP >= 1 && WB_TEST_COMMITTED_STOP <= 4, "unsupported COMMITTED stop");
    const int armed = is_first_commit(buf, size);
    if (armed && WB_TEST_COMMITTED_STOP <= 2) {
        const size_t prefix = WB_TEST_COMMITTED_STOP == 1 ? 0 : 250;
        if ((prefix && write_all(fd, buf, prefix)) || raise(SIGSTOP)) {
            close(fd);
            return -1;
        }
        buf += prefix;
        size -= prefix;
    }
#endif
#ifdef WB_TEST_APPEND_MODE
#if WB_TEST_APPEND_KIND <= 2
    static const uint8_t seq_one[8] = {1};
    int match = size == 251 && buf[6] == WB_TEST_APPEND_KIND && !memcmp(buf+83+64, seq_one, 8);
#else
    const size_t expected = WB_TEST_APPEND_KIND == 3 ? 171 : 291;
    uint32_t payload = htole32((uint32_t)(expected - 115));
    int match = size == expected && buf[6] == WB_TEST_APPEND_KIND && !memcmp(buf+7, &payload, 4);
#endif
    if (match) { proof_fd = fd; proof_size = size; }
#endif
    int ok = write_all(fd, buf, size) == 0;
#ifdef WB_TEST_COMMITTED_STOP
    if (ok && armed && WB_TEST_COMMITTED_STOP == 3) ok = raise(SIGSTOP) == 0;
#endif
    if (ok) ok = proof_fsync(fd) == 0;
#ifdef WB_TEST_APPEND_MODE
    proof_fd = -1;
#endif
    if (close(fd) || !ok) return -1;
#if defined(WB_TEST_PUBLISH_STOP) || defined(WB_TEST_HEAD_ERROR)
    first_commit_appended = is_first_commit(buf, size);
#endif
#ifdef WB_TEST_COMMITTED_STOP
    if (armed && WB_TEST_COMMITTED_STOP == 4 && raise(SIGSTOP)) return -1;
#endif
#ifdef WB_TEST_ADMIN_STOP
    epoch_appended = admin && WB_TEST_ADMIN_STOP == 5;
#endif
    if (!sync_directory) return 0;
#ifdef WB_TEST_DIRSYNC_FAILURE
    return fsync(-1);
#else
    int rc = fsync(data);
#ifdef WB_TEST_ADMIN_STOP
    if (rc == 0 && admin && WB_TEST_ADMIN_STOP == 3 && raise(SIGSTOP)) return -1;
#endif
    return rc;
#endif
}

#ifdef WB_TEST_HEAD_ERROR
static int head_result(const char *operation, int result) {
    int saved = errno;
    fprintf(stderr, "%s %d %d\n", operation, result, result < 0 ? saved : 0);
    errno = saved;
    return result;
}
// Evaluate the syscall once, or inject EIO without performing it. Close always runs.
#define HEAD_CALL(name, mode, call) (first_commit_appended ? head_result(name, \
    WB_TEST_HEAD_ERROR == (mode) ? (errno = EIO, -1) : (call)) : (call))
#else
#define HEAD_CALL(name, mode, call) (call)
#endif

int wb_publish(const uint8_t *buf, size_t size) {
    if (unlinkat(data, "head.tmp", 0) && errno != ENOENT) return -1;
    int fd = open_file("head.tmp", O_CREAT|O_EXCL|O_WRONLY);
    if (fd < 0) return -1;
#ifdef WB_TEST_HEAD_ERROR
    if (first_commit_appended) head_fd = fd;
#endif
    int ok = write_all(fd, buf, size) == 0;
    if (ok) {
        publication_stop(1);
        ok = HEAD_CALL("tmp_sync", 3, fsync(fd)) == 0;
    }
#ifdef WB_TEST_HEAD_ERROR
    head_fd = -1;
#endif
    if (HEAD_CALL("tmp_close", 0, close(fd)) || !ok) return -1;
    publication_stop(2);
    if (HEAD_CALL("head_rename", 4, renameat(data,"head.tmp",data,"head"))) return -1;
    publication_stop(3);
    int rc = HEAD_CALL("directory_sync", 5, fsync(data));
#ifdef WB_TEST_ADMIN_STOP
    if (rc == 0 && epoch_appended && raise(SIGSTOP)) return -1;
#endif
    if (rc == 0) publication_stop(4);
    return rc;
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
