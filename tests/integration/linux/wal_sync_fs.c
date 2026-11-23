// Single-threaded fixture for a private SQLite journal directory. Locks and SHM
// mappings are local to this mount; only the WAL uses uncached, per-handle writes.
#define _GNU_SOURCE
#define FUSE_USE_VERSION 31
#include <fuse3/fuse.h>
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int backing, armed, fired, commit_fd = -1;
static off_t commit_offset;
static const char *wal = "/active.db-wal";

static int allowed(const char *p) {
    return !strcmp(p, "/active.db") || !strcmp(p, wal) ||
           !strcmp(p, "/active.db-shm") || !strcmp(p, "/active.db-journal");
}
static int attrs(const char *p, struct stat *st, struct fuse_file_info *fi) {
    if (fi) return fstat(fi->fh, st) ? -errno : 0;
    if (!strcmp(p, "/")) return fstat(backing, st) ? -errno : 0;
    if (!allowed(p)) return -ENOENT;
    return fstatat(backing, p+1, st, AT_SYMLINK_NOFOLLOW) ? -errno : 0;
}
static int file_open(const char *p, mode_t mode, struct fuse_file_info *fi, int create) {
    if (!allowed(p)) return -ENOENT;
    int fd = openat(backing, p+1, fi->flags | O_NOFOLLOW | O_CLOEXEC | (create ? O_CREAT|O_EXCL : 0), mode);
    if (fd < 0) return -errno;
    const struct fuse_context *ctx = fuse_get_context();
    if (create && fchown(fd, ctx->uid, ctx->gid)) {
        int err = errno;
        close(fd);
        return -err;
    }
    fi->fh = fd;
    fi->direct_io = !strcmp(p, wal);
    return 0;
}
static int open_existing(const char *p, struct fuse_file_info *fi) { return file_open(p,0,fi,0); }
static int create_file(const char *p, mode_t mode, struct fuse_file_info *fi) { return file_open(p,mode,fi,1); }
static int release(const char *p, struct fuse_file_info *fi) {
    (void)p;
    if ((int)fi->fh == commit_fd) commit_fd = -1;
    return close(fi->fh) ? -errno : 0;
}
static int read_file(const char *p, char *buf, size_t n, off_t off, struct fuse_file_info *fi) {
    (void)p;
    ssize_t got = pread(fi->fh,buf,n,off);
    return got < 0 ? -errno : (int)got;
}
static uint32_t word(const char *p) {
    uint32_t v;
    memcpy(&v,p,sizeof v);
    return be32toh(v);
}
static int write_file(const char *p, const char *buf, size_t n, off_t off, struct fuse_file_info *fi) {
    int fd = (int)fi->fh;
    ssize_t count = pwrite(fd,buf,n,off);
    if (count < 0) return -errno;
    if (!strcmp(p,wal)) {
        int marker = 0;
        if (n == 24 && count == 24 && off >= 32 && word(buf) && word(buf+4)) {
            char header[32];
            if (pread(fd,header,32,0)==32 && word(header+8)==4096 &&
                (off-32)%(24+4096)==0 && !memcmp(buf+8,header+16,8)) {
                commit_fd = fd;
                commit_offset = off;
                marker = 1;
            }
        }
        fprintf(stderr,"wal_write %d %d %lld %zu %zd %d\n",fuse_get_context()->pid,fd,(long long)off,n,count,marker);
    }
    return (int)count;
}
static int sync_file(const char *p, int datasync, struct fuse_file_info *fi) {
    int fd = (int)fi->fh;
    int commit = !strcmp(p,wal) && fd==commit_fd;
    int rc;
    if (commit && armed && !fired) {
        fired = 1;
        rc = -EIO;
    } else {
        rc = (datasync ? fdatasync(fd) : fsync(fd)) ? -errno : 0;
    }
    if (!strcmp(p,wal)) fprintf(stderr,"wal_sync %d %d %d %lld %d\n",
        fuse_get_context()->pid,fd,datasync,commit ? (long long)commit_offset : -1LL,rc);
    if (commit) commit_fd = -1;
    return rc;
}
static int sync_dir(const char *p,int datasync,struct fuse_file_info *fi) {
    (void)p; (void)datasync; (void)fi;
    return fsync(backing) ? -errno : 0;
}
static int resize(const char *p, off_t size, struct fuse_file_info *fi) {
    if (!allowed(p)) return -ENOENT;
    int fd = fi ? (int)fi->fh : openat(backing,p+1,O_WRONLY|O_NOFOLLOW);
    if (fd<0) return -errno;
    int rc = ftruncate(fd,size) ? -errno : 0;
    if (!fi) close(fd);
    return rc;
}
static int remove_file(const char *p) {
    if (!allowed(p)) return -ENOENT;
    return unlinkat(backing,p+1,0) ? -errno : 0;
}
int main(int argc, char **argv) {
    if (argc!=3 || (strcmp(argv[2],"healthy") && strcmp(argv[2],"fault"))) return 2;
    armed = !strcmp(argv[2],"fault");
    backing = open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if (backing<0) return 2;
    struct fuse_operations ops = {.getattr=attrs,.open=open_existing,.create=create_file,.release=release,
        .read=read_file,.write=write_file,.fsync=sync_file,.fsyncdir=sync_dir,.truncate=resize,.unlink=remove_file};
    char *args[] = {argv[0],"-f","-s","-o","allow_other,default_permissions,attr_timeout=0,entry_timeout=0,negative_timeout=0",argv[1]};
    return fuse_main(6,args,&ops,NULL);
}
