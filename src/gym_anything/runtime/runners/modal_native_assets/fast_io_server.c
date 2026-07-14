#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xdamage.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <omp.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#if defined(__x86_64__) || defined(__i386__)
#include <tmmintrin.h>
#endif

#define GA_MAGIC 0x47414649U
#define GA_VERSION 1U

#define OP_HELLO 1U
#define OP_PING 2U
#define OP_SCREENSHOT 3U
#define OP_ACTION 4U

#define EVENT_MOTION 1U
#define EVENT_BUTTON 2U
#define EVENT_KEY 3U

#define FRAME_DATA_FOLLOWS 1U
#define CAPABILITY_NATIVE_X11 1U

#define STATUS_OK 0U
#define STATUS_PROTOCOL 1U
#define STATUS_AUTH 2U
#define STATUS_INPUT 3U
#define STATUS_INTERNAL 4U

#define REQUEST_HEADER_SIZE 12U
#define RESPONSE_HEADER_SIZE 16U
#define SCREENSHOT_META_SIZE 40U
#define WIRE_EVENT_SIZE 16U
#define FRAME_SLOTS 3
#define MAX_EVENTS 4096U
#define MAX_REQUEST_SIZE (4U + MAX_EVENTS * WIRE_EVENT_SIZE)
#define LOCAL_FRAME_PATH "/dev/shm/gym-anything-modal-native-fast-io"
#define LOCAL_HEADER_SIZE 4096U
#define LOCAL_CURRENT_OFFSET 24U
#define LOCAL_SLOT_META_OFFSET 32U
#define LOCAL_SLOT_META_SIZE 32U

typedef struct {
    uint8_t *rgb;
    unsigned int readers;
    uint64_t id;
    uint64_t captured_ns;
    uint64_t capture_elapsed_ns;
} FrameSlot;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t changed;
    FrameSlot slots[FRAME_SLOTS];
    int current;
    int next_slot;
    int ready;
    int stopping;
    unsigned int width;
    unsigned int height;
    unsigned int stride;
    char error[256];
} FrameCache;

typedef struct {
    uint8_t kind;
    uint8_t down;
    uint32_t code;
    int32_t x;
    int32_t y;
    KeyCode keycode;
} InputEvent;

static FrameCache frame_cache = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .changed = PTHREAD_COND_INITIALIZER,
    .current = -1,
};
static pthread_mutex_t input_mutex = PTHREAD_MUTEX_INITIALIZER;
static Display *input_display = NULL;
static int input_screen = 0;
static const char *auth_token = NULL;
static uint8_t *local_frames = NULL;
static size_t local_frames_size = 0;
static volatile sig_atomic_t running = 1;
static int listen_fd = -1;

static uint16_t read_u16(const uint8_t *data) {
    uint16_t value;
    memcpy(&value, data, sizeof(value));
    return ntohs(value);
}

static uint32_t read_u32(const uint8_t *data) {
    uint32_t value;
    memcpy(&value, data, sizeof(value));
    return ntohl(value);
}

static uint64_t read_u64(const uint8_t *data) {
    return ((uint64_t)read_u32(data) << 32U) | read_u32(data + 4);
}

static void write_u16(uint8_t *data, uint16_t value) {
    value = htons(value);
    memcpy(data, &value, sizeof(value));
}

static void write_u32(uint8_t *data, uint32_t value) {
    value = htonl(value);
    memcpy(data, &value, sizeof(value));
}

static void write_u64(uint8_t *data, uint64_t value) {
    write_u32(data, (uint32_t)(value >> 32U));
    write_u32(data + 4, (uint32_t)value);
}

static void write_native_u32(uint8_t *data, uint32_t value) {
    memcpy(data, &value, sizeof(value));
}

static void write_native_u64(uint8_t *data, uint64_t value) {
    memcpy(data, &value, sizeof(value));
}

static uint64_t load_local_u64(size_t offset) {
    return __atomic_load_n((uint64_t *)(local_frames + offset), __ATOMIC_ACQUIRE);
}

static void store_local_u64(size_t offset, uint64_t value) {
    __atomic_store_n((uint64_t *)(local_frames + offset), value, __ATOMIC_RELEASE);
}

static uint64_t monotonic_ns(void) {
    struct timespec now;
#ifdef CLOCK_MONOTONIC_RAW
    clock_gettime(CLOCK_MONOTONIC_RAW, &now);
#else
    clock_gettime(CLOCK_MONOTONIC, &now);
#endif
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

static int read_full(int fd, void *buffer, size_t size) {
    uint8_t *cursor = buffer;
    while (size > 0) {
        ssize_t count = recv(fd, cursor, size, 0);
        if (count == 0) {
            return 0;
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        cursor += (size_t)count;
        size -= (size_t)count;
    }
    return 1;
}

static int write_full(int fd, const void *buffer, size_t size) {
    const uint8_t *cursor = buffer;
    while (size > 0) {
        ssize_t count = send(fd, cursor, size, MSG_NOSIGNAL);
        if (count == 0) {
            return -1;
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        cursor += (size_t)count;
        size -= (size_t)count;
    }
    return 0;
}

static int send_header(
    int fd,
    uint16_t opcode,
    uint32_t status,
    uint32_t payload_size
) {
    uint8_t header[RESPONSE_HEADER_SIZE];
    write_u32(header, GA_MAGIC);
    write_u16(header + 4, GA_VERSION);
    write_u16(header + 6, opcode);
    write_u32(header + 8, status);
    write_u32(header + 12, payload_size);
    return write_full(fd, header, sizeof(header));
}

static int send_response(
    int fd,
    uint16_t opcode,
    uint32_t status,
    const void *payload,
    uint32_t payload_size
) {
    if (send_header(fd, opcode, status, payload_size) < 0) {
        return -1;
    }
    if (payload_size > 0 && write_full(fd, payload, payload_size) < 0) {
        return -1;
    }
    return 0;
}

static int send_error(int fd, uint16_t opcode, uint32_t status, const char *message) {
    size_t length = strlen(message);
    if (length > UINT32_MAX) {
        length = UINT32_MAX;
    }
    return send_response(fd, opcode, status, message, (uint32_t)length);
}

static void set_capture_error(const char *message) {
    pthread_mutex_lock(&frame_cache.mutex);
    snprintf(frame_cache.error, sizeof(frame_cache.error), "%s", message);
    frame_cache.ready = -1;
    pthread_cond_broadcast(&frame_cache.changed);
    pthread_mutex_unlock(&frame_cache.mutex);
}

static unsigned int component_shift(unsigned long mask) {
    unsigned int shift = 0;
    if (mask == 0) {
        return 0;
    }
    while ((mask & 1UL) == 0) {
        mask >>= 1U;
        shift++;
    }
    return shift;
}

static uint8_t scale_component(unsigned long pixel, unsigned long mask) {
    if (mask == 0) {
        return 0;
    }
    unsigned int shift = component_shift(mask);
    unsigned long maximum = mask >> shift;
    unsigned long value = (pixel & mask) >> shift;
    return (uint8_t)((value * 255UL + maximum / 2UL) / maximum);
}

static int conversion_threads(void) {
    long processors = sysconf(_SC_NPROCESSORS_ONLN);
    if (processors < 1) {
        return 1;
    }
    return processors > 4 ? 4 : (int)processors;
}

static unsigned long image_pixel(const uint8_t *source, int bytes, int byte_order) {
    unsigned long pixel = 0;
    if (byte_order == LSBFirst) {
        for (int index = 0; index < bytes; index++) {
            pixel |= (unsigned long)source[index] << (8U * (unsigned int)index);
        }
    } else {
        for (int index = 0; index < bytes; index++) {
            pixel = (pixel << 8U) | source[index];
        }
    }
    return pixel;
}

#if defined(__x86_64__) || defined(__i386__)
__attribute__((target("ssse3")))
static void convert_xrgb_ssse3(
    const XImage *image,
    uint8_t *destination,
    int source_is_bgr,
    unsigned int first_row,
    unsigned int last_row
) {
    const __m128i shuffle = source_is_bgr
        ? _mm_setr_epi8(
            2, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12,
            (char)0x80, (char)0x80, (char)0x80, (char)0x80
        )
        : _mm_setr_epi8(
            0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14,
            (char)0x80, (char)0x80, (char)0x80, (char)0x80
        );
    const unsigned int width = (unsigned int)image->width;
    for (unsigned int y = first_row; y < last_row; y++) {
        const uint8_t *source =
            (const uint8_t *)image->data + (size_t)y * image->bytes_per_line;
        uint8_t *target = destination + (size_t)y * width * 3U;
        unsigned int x = 0;
        for (; x + 16U <= width; x += 16U) {
            __m128i first = _mm_shuffle_epi8(
                _mm_loadu_si128((const __m128i *)(source + x * 4U)),
                shuffle
            );
            __m128i second = _mm_shuffle_epi8(
                _mm_loadu_si128((const __m128i *)(source + x * 4U + 16U)),
                shuffle
            );
            __m128i third = _mm_shuffle_epi8(
                _mm_loadu_si128((const __m128i *)(source + x * 4U + 32U)),
                shuffle
            );
            __m128i fourth = _mm_shuffle_epi8(
                _mm_loadu_si128((const __m128i *)(source + x * 4U + 48U)),
                shuffle
            );
            _mm_storeu_si128(
                (__m128i *)(target + x * 3U),
                _mm_or_si128(first, _mm_slli_si128(second, 12))
            );
            _mm_storeu_si128(
                (__m128i *)(target + x * 3U + 16U),
                _mm_or_si128(
                    _mm_srli_si128(second, 4),
                    _mm_slli_si128(third, 8)
                )
            );
            _mm_storeu_si128(
                (__m128i *)(target + x * 3U + 32U),
                _mm_or_si128(
                    _mm_srli_si128(third, 8),
                    _mm_slli_si128(fourth, 4)
                )
            );
        }
        for (; x + 4U <= width; x += 4U) {
            __m128i pixels = _mm_loadu_si128((const __m128i *)(source + x * 4U));
            __m128i rgb = _mm_shuffle_epi8(pixels, shuffle);
            _mm_storel_epi64((__m128i *)(target + x * 3U), rgb);
            uint32_t tail = (uint32_t)_mm_cvtsi128_si32(_mm_srli_si128(rgb, 8));
            memcpy(target + x * 3U + 8U, &tail, sizeof(tail));
        }
        for (; x < width; x++) {
            if (source_is_bgr) {
                target[x * 3U] = source[x * 4U + 2U];
                target[x * 3U + 1U] = source[x * 4U + 1U];
                target[x * 3U + 2U] = source[x * 4U];
            } else {
                target[x * 3U] = source[x * 4U];
                target[x * 3U + 1U] = source[x * 4U + 1U];
                target[x * 3U + 2U] = source[x * 4U + 2U];
            }
        }
    }
}
#endif

static void convert_to_rgb(const XImage *image, uint8_t *destination) {
    const unsigned int width = (unsigned int)image->width;
    const unsigned int height = (unsigned int)image->height;
    const int bytes_per_pixel = (image->bits_per_pixel + 7) / 8;
    const int threads = conversion_threads();

    int source_is_bgr =
        image->red_mask == 0x00ff0000UL &&
        image->green_mask == 0x0000ff00UL &&
        image->blue_mask == 0x000000ffUL;
    int source_is_rgb =
        image->red_mask == 0x000000ffUL &&
        image->green_mask == 0x0000ff00UL &&
        image->blue_mask == 0x00ff0000UL;
    if (image->bits_per_pixel == 32 && image->byte_order == LSBFirst &&
        (source_is_bgr || source_is_rgb)) {
#if defined(__x86_64__) || defined(__i386__)
        if (__builtin_cpu_supports("ssse3")) {
            #pragma omp parallel num_threads(threads)
            {
                unsigned int thread = (unsigned int)omp_get_thread_num();
                unsigned int count = (unsigned int)omp_get_num_threads();
                unsigned int first_row = height * thread / count;
                unsigned int last_row = height * (thread + 1U) / count;
                convert_xrgb_ssse3(
                    image,
                    destination,
                    source_is_bgr,
                    first_row,
                    last_row
                );
            }
            return;
        }
#endif
        #pragma omp parallel for num_threads(threads) schedule(static)
        for (unsigned int y = 0; y < height; y++) {
            const uint8_t *source =
                (const uint8_t *)image->data + (size_t)y * image->bytes_per_line;
            uint8_t *target = destination + (size_t)y * width * 3U;
            for (unsigned int x = 0; x < width; x++) {
                target[x * 3U] = source[x * 4U + (source_is_bgr ? 2U : 0U)];
                target[x * 3U + 1U] = source[x * 4U + 1U];
                target[x * 3U + 2U] = source[x * 4U + (source_is_bgr ? 0U : 2U)];
            }
        }
        return;
    }

    #pragma omp parallel for num_threads(threads) schedule(static)
    for (unsigned int y = 0; y < height; y++) {
        const uint8_t *source =
            (const uint8_t *)image->data + (size_t)y * image->bytes_per_line;
        uint8_t *target = destination + (size_t)y * width * 3U;
        for (unsigned int x = 0; x < width; x++) {
            unsigned long pixel = image_pixel(
                source + (size_t)x * (size_t)bytes_per_pixel,
                bytes_per_pixel,
                image->byte_order
            );
            target[x * 3U] = scale_component(pixel, image->red_mask);
            target[x * 3U + 1U] = scale_component(pixel, image->green_mask);
            target[x * 3U + 2U] = scale_component(pixel, image->blue_mask);
        }
    }
}

static int writable_frame_slot(void) {
    pthread_mutex_lock(&frame_cache.mutex);
    for (;;) {
        for (int offset = 0; offset < FRAME_SLOTS; offset++) {
            int index = (frame_cache.next_slot + offset) % FRAME_SLOTS;
            if (index != frame_cache.current && frame_cache.slots[index].readers == 0) {
                frame_cache.next_slot = (index + 1) % FRAME_SLOTS;
                pthread_mutex_unlock(&frame_cache.mutex);
                return index;
            }
        }
        if (frame_cache.stopping) {
            pthread_mutex_unlock(&frame_cache.mutex);
            return -1;
        }
        pthread_cond_wait(&frame_cache.changed, &frame_cache.mutex);
    }
}

static int initialize_local_frames(
    unsigned int width,
    unsigned int height,
    unsigned int stride
) {
    size_t frame_size = (size_t)stride * height;
    if (frame_size > (SIZE_MAX - LOCAL_HEADER_SIZE) / FRAME_SLOTS) {
        return -1;
    }
    local_frames_size = LOCAL_HEADER_SIZE + frame_size * FRAME_SLOTS;
    int fd = open(LOCAL_FRAME_PATH, O_CREAT | O_RDWR, 0600);
    if (fd < 0) {
        return -1;
    }
    if (fchmod(fd, 0600) < 0 || ftruncate(fd, (off_t)local_frames_size) < 0) {
        close(fd);
        return -1;
    }
    local_frames = mmap(
        NULL,
        local_frames_size,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        fd,
        0
    );
    close(fd);
    if (local_frames == MAP_FAILED) {
        local_frames = NULL;
        return -1;
    }
    memset(local_frames, 0, LOCAL_HEADER_SIZE);
    memcpy(local_frames, "GAFS", 4);
    write_native_u32(local_frames + 4, GA_VERSION);
    write_native_u32(local_frames + 8, width);
    write_native_u32(local_frames + 12, height);
    write_native_u32(local_frames + 16, stride);
    write_native_u32(local_frames + 20, FRAME_SLOTS);
    store_local_u64(LOCAL_CURRENT_OFFSET, UINT64_MAX);
    for (int index = 0; index < FRAME_SLOTS; index++) {
        frame_cache.slots[index].rgb =
            local_frames + LOCAL_HEADER_SIZE + (size_t)index * frame_size;
    }
    return 0;
}

static int capture_frame(Display *display, Drawable root, XImage *image) {
    int slot_index = writable_frame_slot();
    if (slot_index < 0) {
        return -1;
    }
    size_t local_meta =
        LOCAL_SLOT_META_OFFSET + (size_t)slot_index * LOCAL_SLOT_META_SIZE;
    uint64_t local_sequence = 0;
    if (local_frames != NULL) {
        local_sequence = load_local_u64(local_meta);
        if (local_sequence & 1U) {
            local_sequence++;
        }
        store_local_u64(local_meta, local_sequence + 1U);
    }
    uint64_t started_ns = monotonic_ns();
    if (!XShmGetImage(display, root, image, 0, 0, AllPlanes)) {
        if (local_frames != NULL) {
            store_local_u64(local_meta, local_sequence + 2U);
        }
        set_capture_error("XShmGetImage failed");
        return -1;
    }
    convert_to_rgb(image, frame_cache.slots[slot_index].rgb);
    uint64_t captured_ns = monotonic_ns();
    uint64_t capture_elapsed_ns = captured_ns - started_ns;

    pthread_mutex_lock(&frame_cache.mutex);
    uint64_t next_id = frame_cache.current < 0
        ? 1
        : frame_cache.slots[frame_cache.current].id + 1;
    frame_cache.slots[slot_index].id = next_id;
    frame_cache.slots[slot_index].captured_ns = captured_ns;
    frame_cache.slots[slot_index].capture_elapsed_ns = capture_elapsed_ns;
    if (local_frames != NULL) {
        write_native_u64(local_frames + local_meta + 8, next_id);
        write_native_u64(local_frames + local_meta + 16, captured_ns);
        write_native_u64(local_frames + local_meta + 24, capture_elapsed_ns);
        store_local_u64(local_meta, local_sequence + 2U);
        store_local_u64(LOCAL_CURRENT_OFFSET, (uint64_t)slot_index);
    }
    frame_cache.current = slot_index;
    frame_cache.ready = 1;
    pthread_cond_broadcast(&frame_cache.changed);
    pthread_mutex_unlock(&frame_cache.mutex);
    return 0;
}

static void destroy_shm_image(
    Display *display,
    XImage *image,
    XShmSegmentInfo *shm_info,
    int attached
) {
    if (attached && display != NULL && image != NULL) {
        XShmDetach(display, shm_info);
        XSync(display, False);
    }
    if (shm_info->shmaddr != NULL && shm_info->shmaddr != (char *)-1) {
        shmdt(shm_info->shmaddr);
    }
    if (image != NULL) {
        image->data = NULL;
        XDestroyImage(image);
    }
}

static void *capture_thread_main(void *unused) {
    (void)unused;
    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        set_capture_error("could not open the X11 display for capture");
        return NULL;
    }
    if (!XShmQueryExtension(display)) {
        set_capture_error("the X11 display does not support MIT-SHM");
        XCloseDisplay(display);
        return NULL;
    }

    int damage_event_base = 0;
    int damage_error_base = 0;
    if (!XDamageQueryExtension(display, &damage_event_base, &damage_error_base)) {
        set_capture_error("the X11 display does not support XDamage");
        XCloseDisplay(display);
        return NULL;
    }

    int screen = DefaultScreen(display);
    Window root = RootWindow(display, screen);
    XWindowAttributes attributes;
    if (!XGetWindowAttributes(display, root, &attributes)) {
        set_capture_error("could not read the X11 root-window geometry");
        XCloseDisplay(display);
        return NULL;
    }

    XShmSegmentInfo shm_info;
    memset(&shm_info, 0, sizeof(shm_info));
    shm_info.shmid = -1;
    shm_info.shmaddr = (char *)-1;
    XImage *image = XShmCreateImage(
        display,
        attributes.visual,
        (unsigned int)attributes.depth,
        ZPixmap,
        NULL,
        &shm_info,
        (unsigned int)attributes.width,
        (unsigned int)attributes.height
    );
    if (image == NULL) {
        set_capture_error("XShmCreateImage failed");
        XCloseDisplay(display);
        return NULL;
    }

    size_t image_size = (size_t)image->bytes_per_line * (size_t)image->height;
    shm_info.shmid = shmget(IPC_PRIVATE, image_size, IPC_CREAT | 0600);
    if (shm_info.shmid < 0) {
        set_capture_error("could not allocate the XShm segment");
        destroy_shm_image(display, image, &shm_info, 0);
        XCloseDisplay(display);
        return NULL;
    }
    shm_info.shmaddr = shmat(shm_info.shmid, NULL, 0);
    if (shm_info.shmaddr == (char *)-1) {
        set_capture_error("could not attach the XShm segment");
        shmctl(shm_info.shmid, IPC_RMID, NULL);
        destroy_shm_image(display, image, &shm_info, 0);
        XCloseDisplay(display);
        return NULL;
    }
    image->data = shm_info.shmaddr;
    shm_info.readOnly = False;
    if (!XShmAttach(display, &shm_info)) {
        set_capture_error("could not attach XShm to the X server");
        shmctl(shm_info.shmid, IPC_RMID, NULL);
        destroy_shm_image(display, image, &shm_info, 0);
        XCloseDisplay(display);
        return NULL;
    }
    XSync(display, False);
    shmctl(shm_info.shmid, IPC_RMID, NULL);

    pthread_mutex_lock(&frame_cache.mutex);
    frame_cache.width = (unsigned int)attributes.width;
    frame_cache.height = (unsigned int)attributes.height;
    frame_cache.stride = (unsigned int)attributes.width * 3U;
    if (initialize_local_frames(
        frame_cache.width,
        frame_cache.height,
        frame_cache.stride
    ) < 0) {
        unlink(LOCAL_FRAME_PATH);
        fprintf(stderr, "local shared-memory frames unavailable; using private buffers\n");
        size_t rgb_size = (size_t)frame_cache.stride * frame_cache.height;
        for (int index = 0; index < FRAME_SLOTS; index++) {
            frame_cache.slots[index].rgb = malloc(rgb_size);
            if (frame_cache.slots[index].rgb != NULL) {
                continue;
            }
            snprintf(
                frame_cache.error,
                sizeof(frame_cache.error),
                "could not allocate RGB frame buffers"
            );
            frame_cache.ready = -1;
            pthread_cond_broadcast(&frame_cache.changed);
            pthread_mutex_unlock(&frame_cache.mutex);
            destroy_shm_image(display, image, &shm_info, 1);
            XCloseDisplay(display);
            return NULL;
        }
    }
    pthread_mutex_unlock(&frame_cache.mutex);

    Damage damage = XDamageCreate(display, root, XDamageReportNonEmpty);
    XSync(display, False);
    if (capture_frame(display, root, image) < 0) {
        XDamageDestroy(display, damage);
        destroy_shm_image(display, image, &shm_info, 1);
        XCloseDisplay(display);
        return NULL;
    }

    while (running) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type != damage_event_base + XDamageNotify) {
            continue;
        }
        XDamageSubtract(display, damage, None, None);
        XSync(display, False);
        if (capture_frame(display, root, image) < 0) {
            break;
        }
    }

    XDamageDestroy(display, damage);
    destroy_shm_image(display, image, &shm_info, 1);
    XCloseDisplay(display);
    return NULL;
}

static int token_matches(const uint8_t *candidate, uint32_t length) {
    size_t expected_length = strlen(auth_token);
    unsigned int difference = (unsigned int)(expected_length ^ length);
    size_t maximum = expected_length > length ? expected_length : length;
    for (size_t index = 0; index < maximum; index++) {
        uint8_t expected = index < expected_length ? (uint8_t)auth_token[index] : 0;
        uint8_t received = index < length ? candidate[index] : 0;
        difference |= expected ^ received;
    }
    return difference == 0;
}

static int handle_hello(int fd, uint16_t opcode, const uint8_t *payload, uint32_t length) {
    if (!token_matches(payload, length)) {
        send_error(fd, opcode, STATUS_AUTH, "fast-I/O authentication failed");
        return -1;
    }

    uint8_t response[16];
    pthread_mutex_lock(&frame_cache.mutex);
    write_u32(response, frame_cache.width);
    write_u32(response + 4, frame_cache.height);
    pthread_mutex_unlock(&frame_cache.mutex);
    write_u32(response + 8, 3);
    write_u32(response + 12, CAPABILITY_NATIVE_X11);
    return send_response(fd, opcode, STATUS_OK, response, sizeof(response));
}

static int handle_screenshot(
    int fd,
    uint16_t opcode,
    const uint8_t *payload,
    uint32_t length
) {
    if (length != 8) {
        return send_error(fd, opcode, STATUS_PROTOCOL, "invalid screenshot request");
    }
    uint64_t client_frame_id = read_u64(payload);

    pthread_mutex_lock(&frame_cache.mutex);
    while (frame_cache.ready == 0) {
        pthread_cond_wait(&frame_cache.changed, &frame_cache.mutex);
    }
    if (frame_cache.ready < 0 || frame_cache.current < 0) {
        char message[256];
        snprintf(message, sizeof(message), "%s", frame_cache.error);
        pthread_mutex_unlock(&frame_cache.mutex);
        return send_error(fd, opcode, STATUS_INTERNAL, message);
    }
    int slot_index = frame_cache.current;
    FrameSlot *slot = &frame_cache.slots[slot_index];
    slot->readers++;
    unsigned int width = frame_cache.width;
    unsigned int height = frame_cache.height;
    unsigned int stride = frame_cache.stride;
    uint64_t frame_id = slot->id;
    uint64_t captured_ns = slot->captured_ns;
    uint64_t capture_elapsed_ns = slot->capture_elapsed_ns;
    int include_data = client_frame_id != frame_id;
    pthread_mutex_unlock(&frame_cache.mutex);

    uint8_t metadata[SCREENSHOT_META_SIZE];
    write_u32(metadata, width);
    write_u32(metadata + 4, height);
    write_u32(metadata + 8, stride);
    write_u32(metadata + 12, include_data ? FRAME_DATA_FOLLOWS : 0);
    write_u64(metadata + 16, frame_id);
    write_u64(metadata + 24, captured_ns);
    write_u64(metadata + 32, capture_elapsed_ns);

    uint64_t frame_bytes = (uint64_t)stride * height;
    uint64_t response_bytes = SCREENSHOT_META_SIZE + (include_data ? frame_bytes : 0);
    int result = -1;
    if (response_bytes <= UINT32_MAX &&
        send_header(fd, opcode, STATUS_OK, (uint32_t)response_bytes) == 0 &&
        write_full(fd, metadata, sizeof(metadata)) == 0 &&
        (!include_data || write_full(fd, slot->rgb, (size_t)frame_bytes) == 0)) {
        result = 0;
    }

    pthread_mutex_lock(&frame_cache.mutex);
    slot->readers--;
    pthread_cond_broadcast(&frame_cache.changed);
    pthread_mutex_unlock(&frame_cache.mutex);
    return result;
}

static int handle_action(
    int fd,
    uint16_t opcode,
    const uint8_t *payload,
    uint32_t length
) {
    if (length < 4) {
        return send_error(fd, opcode, STATUS_PROTOCOL, "invalid action request");
    }
    uint32_t count = read_u32(payload);
    if (count > MAX_EVENTS || length != 4U + count * WIRE_EVENT_SIZE) {
        return send_error(fd, opcode, STATUS_PROTOCOL, "invalid action event batch");
    }

    InputEvent *events = calloc(count, sizeof(*events));
    if (count > 0 && events == NULL) {
        return send_error(fd, opcode, STATUS_INTERNAL, "could not allocate input batch");
    }
    for (uint32_t index = 0; index < count; index++) {
        const uint8_t *wire = payload + 4U + index * WIRE_EVENT_SIZE;
        events[index].kind = wire[0];
        events[index].down = wire[1];
        events[index].code = read_u32(wire + 4);
        events[index].x = (int32_t)read_u32(wire + 8);
        events[index].y = (int32_t)read_u32(wire + 12);
    }

    char error[160] = "";
    pthread_mutex_lock(&input_mutex);
    for (uint32_t index = 0; index < count; index++) {
        InputEvent *event = &events[index];
        if (event->kind == EVENT_MOTION) {
            if (event->x < 0) {
                event->x = 0;
            } else if ((unsigned int)event->x >= frame_cache.width) {
                event->x = (int32_t)frame_cache.width - 1;
            }
            if (event->y < 0) {
                event->y = 0;
            } else if ((unsigned int)event->y >= frame_cache.height) {
                event->y = (int32_t)frame_cache.height - 1;
            }
        } else if (event->kind == EVENT_BUTTON) {
            if (event->code < 1 || event->code > 7 || event->down > 1) {
                snprintf(error, sizeof(error), "invalid X11 button event at index %u", index);
                break;
            }
        } else if (event->kind == EVENT_KEY) {
            if (event->down > 1) {
                snprintf(error, sizeof(error), "invalid X11 key event at index %u", index);
                break;
            }
            event->keycode = XKeysymToKeycode(input_display, (KeySym)event->code);
            if (event->keycode == 0) {
                snprintf(
                    error,
                    sizeof(error),
                    "X11 keyboard map has no keycode for keysym 0x%08x",
                    event->code
                );
                break;
            }
        } else {
            snprintf(error, sizeof(error), "unknown input event type at index %u", index);
            break;
        }
    }

    uint64_t elapsed_ns = 0;
    if (error[0] == '\0') {
        uint64_t started_ns = monotonic_ns();
        for (uint32_t index = 0; index < count; index++) {
            InputEvent *event = &events[index];
            Bool accepted;
            if (event->kind == EVENT_MOTION) {
                accepted = XTestFakeMotionEvent(
                    input_display,
                    input_screen,
                    event->x,
                    event->y,
                    CurrentTime
                );
            } else if (event->kind == EVENT_BUTTON) {
                accepted = XTestFakeButtonEvent(
                    input_display,
                    event->code,
                    event->down,
                    CurrentTime
                );
            } else {
                accepted = XTestFakeKeyEvent(
                    input_display,
                    event->keycode,
                    event->down,
                    CurrentTime
                );
            }
            if (!accepted) {
                snprintf(error, sizeof(error), "XTest rejected input event at index %u", index);
                break;
            }
        }
        XSync(input_display, False);
        elapsed_ns = monotonic_ns() - started_ns;
    }
    pthread_mutex_unlock(&input_mutex);
    free(events);

    if (error[0] != '\0') {
        return send_error(fd, opcode, STATUS_INPUT, error);
    }
    uint8_t response[8];
    write_u64(response, elapsed_ns);
    return send_response(fd, opcode, STATUS_OK, response, sizeof(response));
}

static void *client_thread_main(void *argument) {
    int fd = (int)(intptr_t)argument;
    int authenticated = 0;

    for (;;) {
        uint8_t header[REQUEST_HEADER_SIZE];
        int read_result = read_full(fd, header, sizeof(header));
        if (read_result <= 0) {
            break;
        }
        uint32_t magic = read_u32(header);
        uint16_t version = read_u16(header + 4);
        uint16_t opcode = read_u16(header + 6);
        uint32_t length = read_u32(header + 8);
        if (magic != GA_MAGIC || version != GA_VERSION || length > MAX_REQUEST_SIZE) {
            send_error(fd, opcode, STATUS_PROTOCOL, "invalid fast-I/O request header");
            break;
        }

        uint8_t *payload = NULL;
        if (length > 0) {
            payload = malloc(length);
            if (payload == NULL || read_full(fd, payload, length) <= 0) {
                free(payload);
                break;
            }
        }

        int result;
        if (!authenticated) {
            if (opcode != OP_HELLO) {
                result = send_error(fd, opcode, STATUS_AUTH, "hello is required first");
            } else {
                result = handle_hello(fd, opcode, payload, length);
                if (result == 0) {
                    authenticated = 1;
                }
            }
        } else if (opcode == OP_PING && length == 0) {
            result = send_response(fd, opcode, STATUS_OK, NULL, 0);
        } else if (opcode == OP_SCREENSHOT) {
            result = handle_screenshot(fd, opcode, payload, length);
        } else if (opcode == OP_ACTION) {
            result = handle_action(fd, opcode, payload, length);
        } else {
            result = send_error(fd, opcode, STATUS_PROTOCOL, "unknown fast-I/O operation");
        }
        free(payload);
        if (result < 0) {
            break;
        }
    }

    close(fd);
    return NULL;
}

static void stop_server(int signal_number) {
    (void)signal_number;
    running = 0;
    int fd = listen_fd;
    if (fd >= 0) {
        close(fd);
    }
}

static int parse_port(int argc, char **argv) {
    int port = 5902;
    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--port") == 0 && index + 1 < argc) {
            port = atoi(argv[++index]);
        } else {
            fprintf(stderr, "usage: %s [--port PORT]\n", argv[0]);
            return -1;
        }
    }
    if (port < 1 || port > 65535) {
        fprintf(stderr, "invalid port: %d\n", port);
        return -1;
    }
    return port;
}

int main(int argc, char **argv) {
    int port = parse_port(argc, argv);
    if (port < 0) {
        return 2;
    }
    auth_token = getenv("GA_FAST_IO_TOKEN");
    if (auth_token == NULL || auth_token[0] == '\0') {
        fprintf(stderr, "GA_FAST_IO_TOKEN is required\n");
        return 2;
    }

    signal(SIGPIPE, SIG_IGN);
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_server;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);

    if (!XInitThreads()) {
        fprintf(stderr, "XInitThreads failed\n");
        return 1;
    }
    pthread_t capture_thread;
    if (pthread_create(&capture_thread, NULL, capture_thread_main, NULL) != 0) {
        fprintf(stderr, "could not start the X11 capture thread\n");
        return 1;
    }

    pthread_mutex_lock(&frame_cache.mutex);
    while (frame_cache.ready == 0) {
        pthread_cond_wait(&frame_cache.changed, &frame_cache.mutex);
    }
    if (frame_cache.ready < 0) {
        fprintf(stderr, "fast screenshot initialization failed: %s\n", frame_cache.error);
        pthread_mutex_unlock(&frame_cache.mutex);
        return 1;
    }
    pthread_mutex_unlock(&frame_cache.mutex);

    input_display = XOpenDisplay(NULL);
    if (input_display == NULL) {
        fprintf(stderr, "could not open the X11 display for input\n");
        return 1;
    }
    int event_base, error_base, major, minor;
    if (!XTestQueryExtension(input_display, &event_base, &error_base, &major, &minor)) {
        fprintf(stderr, "the X11 display does not support XTest\n");
        return 1;
    }
    input_screen = DefaultScreen(input_display);

    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        return 1;
    }
    int enabled = 1;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons((uint16_t)port);
    if (bind(listen_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind");
        return 1;
    }
    if (listen(listen_fd, 16) < 0) {
        perror("listen");
        return 1;
    }

    while (running) {
        int client_fd = accept(listen_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR || !running) {
                continue;
            }
            perror("accept");
            break;
        }
        setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled));
        setsockopt(client_fd, SOL_SOCKET, SO_KEEPALIVE, &enabled, sizeof(enabled));
        pthread_t client_thread;
        if (pthread_create(
            &client_thread,
            NULL,
            client_thread_main,
            (void *)(intptr_t)client_fd
        ) != 0) {
            close(client_fd);
            continue;
        }
        pthread_detach(client_thread);
    }

    pthread_mutex_lock(&frame_cache.mutex);
    frame_cache.stopping = 1;
    pthread_cond_broadcast(&frame_cache.changed);
    pthread_mutex_unlock(&frame_cache.mutex);
    XCloseDisplay(input_display);
    return 0;
}
