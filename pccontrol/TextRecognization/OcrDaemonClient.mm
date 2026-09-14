#import "OcrDaemonClient.h"
#include <arpa/inet.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static NSString *const kZXOcrSocketPath = @"/var/mobile/Library/ZXTouch/ocrd.sock";

static BOOL ZXReadExact(int fd, void *buffer, size_t length) {
    uint8_t *bytes = (uint8_t *)buffer;
    while (length > 0) {
        ssize_t count = recv(fd, bytes, length, 0);
        if (count <= 0) return NO;
        bytes += count;
        length -= (size_t)count;
    }
    return YES;
}

static BOOL ZXWriteExact(int fd, const void *buffer, size_t length) {
    const uint8_t *bytes = (const uint8_t *)buffer;
    while (length > 0) {
        ssize_t count = send(fd, bytes, length, MSG_NOSIGNAL);
        if (count <= 0) return NO;
        bytes += count;
        length -= (size_t)count;
    }
    return YES;
}

int ZXPerformOcrThroughDaemon(UInt8 *eventData, NSString **result, NSError **error) {
    if (result) *result = nil;
    if (error) *error = nil;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return 0;

    struct timeval timeout = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    const char *path = kZXOcrSocketPath.UTF8String;
    if (strlen(path) >= sizeof(address.sun_path)) {
        close(fd);
        return 0;
    }
    strlcpy(address.sun_path, path, sizeof(address.sun_path));

    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return 0;
    }

    uint32_t requestLength = (uint32_t)strlen((char *)eventData);
    uint32_t networkLength = htonl(requestLength);
    BOOL ok = ZXWriteExact(fd, &networkLength, sizeof(networkLength)) &&
        ZXWriteExact(fd, eventData, requestLength);
    if (!ok) {
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:2
            userInfo:@{NSLocalizedDescriptionKey:@"OCR daemon write failed"}];
        return -1;
    }

    uint32_t responseNetworkLength = 0;
    if (!ZXReadExact(fd, &responseNetworkLength, sizeof(responseNetworkLength))) {
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:3
            userInfo:@{NSLocalizedDescriptionKey:@"OCR daemon response timeout"}];
        return -1;
    }
    uint32_t responseLength = ntohl(responseNetworkLength);
    if (responseLength > 1024 * 1024) {
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:4
            userInfo:@{NSLocalizedDescriptionKey:@"OCR daemon response too large"}];
        return -1;
    }

    NSMutableData *response = [NSMutableData dataWithLength:responseLength + 1];
    if (!ZXReadExact(fd, response.mutableBytes, responseLength)) {
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:5
            userInfo:@{NSLocalizedDescriptionKey:@"OCR daemon response read failed"}];
        return -1;
    }
    ((char *)response.mutableBytes)[responseLength] = '\0';
    close(fd);

    NSString *value = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    if (!value) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:6
            userInfo:@{NSLocalizedDescriptionKey:@"OCR daemon returned invalid UTF-8"}];
        return -1;
    }
    if ([value hasPrefix:@"-1;;"]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:7
            userInfo:@{NSLocalizedDescriptionKey:value}];
        return -1;
    }
    if (result) *result = value;
    return 1;
}
