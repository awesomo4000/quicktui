#ifndef QUICKTUI_MESSAGE_ENDPOINT_H
#define QUICKTUI_MESSAGE_ENDPOINT_H
#include <stddef.h>
#include <stdint.h>
// Matches the public Zig MessageEndpoint in root.zig.
typedef struct {
    void *context;
    int wake_fd;
    int (*send)(void *, const unsigned char *, size_t);
    ptrdiff_t (*receive)(void *, unsigned char *, size_t);
    const unsigned char *(*borrow_buffer)(void *, uint32_t, size_t *);
    void (*release_buffer)(void *);
} MessageEndpoint;
#endif
