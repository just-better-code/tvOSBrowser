#import "BrowserPreferencesStore.h"
#import "BrowserTorrentHTTPServer.h"

#import "BrowserTorrentManager.h"

#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <unistd.h>

static BOOL BrowserTorrentSendAll(int socketFD, const void *bytes, NSUInteger length) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t sent = send(socketFD, cursor, length, 0);
        if (sent <= 0) return NO;
        cursor += sent;
        length -= (NSUInteger)sent;
    }
    return YES;
}

@interface BrowserTorrentHTTPServer ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) NSInteger fileIndex;
@property (nonatomic) int64_t fileSize;
@property (nonatomic, copy) NSString *fileExtension;
@property (nonatomic, copy) NSString *requestPath;
@property (nonatomic, readwrite) NSURL *mediaURL;
@property (nonatomic) int listenFD;
@property (nonatomic) BOOL running;
@end

@implementation BrowserTorrentHTTPServer

- (instancetype)initWithTorrentIdentifier:(NSString *)identifier fileIndex:(NSInteger)index {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _fileIndex = index;
        _listenFD = -1;
    }
    return self;
}

- (BOOL)startWithError:(NSError **)error {
    BrowserTorrentFile *selected = nil;
    for (BrowserTorrentFile *file in [[BrowserTorrentManager sharedManager] filesForTorrent:self.identifier]) {
        if (file.index == self.fileIndex && !file.padFile) { selected = file; break; }
    }
    if (!selected || selected.size <= 0) {
        if (error) *error = [NSError errorWithDomain:@"BrowserTorrent" code:4 userInfo:@{NSLocalizedDescriptionKey: @"The selected torrent file is unavailable."}];
        return NO;
    }
    self.fileSize = selected.size;
    self.fileExtension = selected.name.pathExtension.lowercaseString ?: @"";
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 8) != 0) {
        close(fd);
        return NO;
    }
    socklen_t addressLength = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &addressLength) != 0) {
        close(fd);
        return NO;
    }
    NSString *token = NSUUID.UUID.UUIDString;
    self.requestPath = [NSString stringWithFormat:@"/%@/%ld.%@", token, (long)self.fileIndex, self.fileExtension];
    self.mediaURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u%@", ntohs(address.sin_port), self.requestPath]];
    @synchronized (self) { self.listenFD = fd; self.running = YES; }
    BrowserDebugLog(@"[TorrentHTTP] listening fileIndex=%ld size=%lld", (long)self.fileIndex, (long long)self.fileSize);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self acceptConnections];
    });
    return YES;
}

- (BOOL)isRunning {
    @synchronized (self) { return self.running; }
}

- (void)stop {
    @synchronized (self) {
        self.running = NO;
        if (self.listenFD >= 0) {
            shutdown(self.listenFD, SHUT_RDWR);
            close(self.listenFD);
            self.listenFD = -1;
        }
    }
}

- (void)acceptConnections {
    while ([self isRunning]) {
        int client = accept(self.listenFD, NULL, NULL);
        if (client < 0) break;
        int yes = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        struct timeval timeout = {.tv_sec = 15, .tv_usec = 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self serveClient:client];
            close(client);
        });
    }
}

- (void)sendStatus:(NSString *)status socket:(int)client {
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", status];
    NSData *data = [header dataUsingEncoding:NSUTF8StringEncoding];
    BrowserTorrentSendAll(client, data.bytes, data.length);
}

- (void)serveClient:(int)client {
    NSMutableData *requestData = [NSMutableData data];
    const char *terminator = "\r\n\r\n";
    while (requestData.length < 8192) {
        uint8_t buffer[1024];
        ssize_t count = recv(client, buffer, sizeof(buffer), 0);
        if (count <= 0) return;
        [requestData appendBytes:buffer length:(NSUInteger)count];
        if ([requestData rangeOfData:[NSData dataWithBytes:terminator length:4] options:0 range:NSMakeRange(0, requestData.length)].location != NSNotFound) break;
    }
    NSString *request = [[NSString alloc] initWithData:requestData encoding:NSASCIIStringEncoding];
    NSArray<NSString *> *lines = [request componentsSeparatedByString:@"\r\n"];
    NSArray<NSString *> *first = [lines.firstObject componentsSeparatedByString:@" "];
    BOOL head = [first.firstObject isEqualToString:@"HEAD"];
    if (first.count < 2 || (!head && ![first.firstObject isEqualToString:@"GET"]) ||
        ![first[1] isEqualToString:self.requestPath]) {
        [self sendStatus:@"404 Not Found" socket:client];
        return;
    }
    int64_t start = 0;
    int64_t end = self.fileSize - 1;
    BOOL ranged = NO;
    for (NSString *line in lines) {
        if (![line.lowercaseString hasPrefix:@"range: bytes="]) continue;
        NSString *specification = [[line substringFromIndex:13] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSArray<NSString *> *parts = [specification componentsSeparatedByString:@"-"];
        if (parts.count != 2 || [specification containsString:@","]) {
            [self sendStatus:@"416 Range Not Satisfiable" socket:client];
            return;
        }
        NSScanner *scanner = [NSScanner scannerWithString:parts[0]];
        long long parsed = 0;
        if (parts[0].length == 0) {
            scanner = [NSScanner scannerWithString:parts[1]];
            if (parts[1].length == 0 || ![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed <= 0) {
                [self sendStatus:@"416 Range Not Satisfiable" socket:client];
                return;
            }
            start = MAX(0, self.fileSize - parsed);
        } else {
            if (![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed < 0) {
                [self sendStatus:@"416 Range Not Satisfiable" socket:client];
                return;
            }
            start = parsed;
        }
        if (parts[0].length > 0 && parts[1].length > 0) {
            scanner = [NSScanner scannerWithString:parts[1]];
            if (![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed < start) {
                [self sendStatus:@"416 Range Not Satisfiable" socket:client];
                return;
            }
            end = MIN(self.fileSize - 1, parsed);
        }
        ranged = YES;
        break;
    }
    if (start >= self.fileSize) {
        [self sendStatus:@"416 Range Not Satisfiable" socket:client];
        return;
    }
    NSString *contentType = @"application/octet-stream";
    if ([@[@"mp4", @"m4v", @"mov"] containsObject:self.fileExtension]) contentType = @"video/mp4";
    else if ([self.fileExtension isEqualToString:@"mkv"]) contentType = @"video/x-matroska";
    else if ([self.fileExtension isEqualToString:@"mp3"]) contentType = @"audio/mpeg";
    else if ([self.fileExtension isEqualToString:@"m4a"]) contentType = @"audio/mp4";
    NSString *rangeHeader = ranged ? [NSString stringWithFormat:@"Content-Range: bytes %lld-%lld/%lld\r\n",
        (long long)start, (long long)end, (long long)self.fileSize] : @"";
    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 %@\r\nContent-Type: %@\r\nContent-Length: %lld\r\nAccept-Ranges: bytes\r\n%@Connection: close\r\n\r\n",
        ranged ? @"206 Partial Content" : @"200 OK", contentType, (long long)(end - start + 1), rangeHeader];
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    if (!BrowserTorrentSendAll(client, headerData.bytes, headerData.length) || head) return;
    BrowserDebugLog(@"[TorrentHTTP] range start=%lld end=%lld", (long long)start, (long long)end);
    BrowserTorrentManager *manager = [BrowserTorrentManager sharedManager];
    int64_t offset = start;
    NSDate *lastProgress = NSDate.date;
    while ([self isRunning] && offset <= end) {
        NSUInteger length = (NSUInteger)MIN((int64_t)(64 * 1024), end - offset + 1);
        NSData *data = [manager availableDataForTorrent:self.identifier fileIndex:self.fileIndex offset:offset length:length];
        if (data.length > 0) {
            if (!BrowserTorrentSendAll(client, data.bytes, data.length)) break;
            offset += data.length;
            lastProgress = NSDate.date;
        } else {
            if (![manager fileURLForTorrent:self.identifier fileIndex:self.fileIndex] ||
                -[lastProgress timeIntervalSinceNow] > 120.0) break;
            [manager prioritizeTorrent:self.identifier fileIndex:self.fileIndex offset:offset];
            usleep(200000);
        }
    }
    BrowserDebugLog(@"[TorrentHTTP] range sent=%lld requested=%lld", (long long)(offset - start), (long long)(end - start + 1));
}

- (void)dealloc { [self stop]; }

@end
