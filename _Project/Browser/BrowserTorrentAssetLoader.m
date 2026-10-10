#import "BrowserPreferencesStore.h"
#import "BrowserTorrentAssetLoader.h"
#import "BrowserTorrentManager.h"

#import <AVFoundation/AVFoundation.h>

@interface BrowserTorrentAssetLoader () <AVAssetResourceLoaderDelegate>
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic) dispatch_source_t pollTimer;
@property (nonatomic) NSMutableSet<AVAssetResourceLoadingRequest *> *requests;
@property (nonatomic) NSMutableSet<AVAssetResourceLoadingRequest *> *waitingRequests;
@property (nonatomic) BrowserTorrentFile *selectedFile;
@property (nonatomic, copy) NSString *selectedHash;
@end

@implementation BrowserTorrentAssetLoader

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.browser.torrent.assetloader", DISPATCH_QUEUE_SERIAL);
        _requests = [NSMutableSet set];
        _waitingRequests = [NSMutableSet set];
        _pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        dispatch_source_set_timer(_pollTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_pollTimer, ^{ [weakSelf processRequests]; });
        dispatch_resume(_pollTimer);
    }
    return self;
}

- (BOOL)attachToAsset:(AVURLAsset *)asset {
    [asset.resourceLoader setDelegate:self queue:self.queue];
    return YES;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader
shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    [self.requests addObject:loadingRequest];
    BrowserLog(@"[TorrentLoader] request started pending=%lu", (unsigned long)self.requests.count);
    [self processRequests];
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader
didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    [self.requests removeObject:loadingRequest];
    [self.waitingRequests removeObject:loadingRequest];
    BrowserLog(@"[TorrentLoader] request cancelled pending=%lu", (unsigned long)self.requests.count);
}

- (void)processRequests {
    BrowserTorrentManager *manager = [BrowserTorrentManager sharedManager];
    for (AVAssetResourceLoadingRequest *request in self.requests.allObjects) {
        NSURL *URL = request.request.URL;
        NSString *hash = URL.host;
        NSString *indexText = URL.path.lastPathComponent.stringByDeletingPathExtension;
        NSScanner *scanner = [NSScanner scannerWithString:indexText];
        NSInteger index = -1;
        if (indexText.length > 0 && [scanner scanInteger:&index] && !scanner.isAtEnd) index = -1;
        BrowserTorrentFile *file = nil;
        if (index >= 0 && [self.selectedHash isEqualToString:hash] && self.selectedFile.index == index) {
            file = self.selectedFile;
        } else if (index >= 0) {
            for (BrowserTorrentFile *candidate in [manager filesForTorrent:hash]) {
                if (candidate.index == index) { file = candidate; break; }
            }
            self.selectedHash = hash;
            self.selectedFile = file;
        }
        if (!file || file.size <= 0 || ![manager fileURLForTorrent:hash fileIndex:index]) {
            BrowserLog(@"[TorrentLoader] unavailable index=%ld fileFound=%d size=%lld", (long)index, file != nil, file.size);
            [request finishLoadingWithError:[NSError errorWithDomain:@"BrowserTorrent" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Torrent file is unavailable"}]];
            [self.requests removeObject:request];
            [self.waitingRequests removeObject:request];
            continue;
        }
        AVAssetResourceLoadingContentInformationRequest *content = request.contentInformationRequest;
        if (content) {
            content.contentLength = file.size;
            content.byteRangeAccessSupported = YES;
            NSString *ext = file.name.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"mov"]) content.contentType = @"com.apple.quicktime-movie";
            else if ([ext isEqualToString:@"mp3"]) content.contentType = @"public.mp3";
            else if ([ext isEqualToString:@"m4a"]) content.contentType = @"public.mpeg-4-audio";
            else content.contentType = @"public.mpeg-4";
        }
        AVAssetResourceLoadingDataRequest *dataRequest = request.dataRequest;
        if (!dataRequest) {
            BrowserLog(@"[TorrentLoader] content information completed index=%ld size=%lld", (long)index, file.size);
            [request finishLoading];
            [self.requests removeObject:request];
            [self.waitingRequests removeObject:request];
            continue;
        }
        int64_t offset = MAX(dataRequest.currentOffset, dataRequest.requestedOffset);
        int64_t end = dataRequest.requestsAllDataToEndOfResource
            ? file.size
            : MIN(file.size, dataRequest.requestedOffset + dataRequest.requestedLength);
        if (offset >= end) {
            BrowserLog(@"[TorrentLoader] range completed index=%ld offset=%lld end=%lld", (long)index, offset, end);
            [request finishLoading];
            [self.requests removeObject:request];
            [self.waitingRequests removeObject:request];
            continue;
        }
        NSUInteger length = (NSUInteger)MIN((int64_t)(256 * 1024), end - offset);
        NSData *data = [manager availableDataForTorrent:hash fileIndex:index offset:offset length:length];
        if (data.length > 0) {
            if ([self.waitingRequests containsObject:request]) {
                BrowserLog(@"[TorrentLoader] data arrived index=%ld offset=%lld bytes=%lu", (long)index, offset, (unsigned long)data.length);
                [self.waitingRequests removeObject:request];
            }
            [dataRequest respondWithData:data];
            if (offset + data.length >= end) {
                BrowserLog(@"[TorrentLoader] request completed index=%ld end=%lld", (long)index, end);
                [request finishLoading];
                [self.requests removeObject:request];
            }
        } else {
            if (![self.waitingRequests containsObject:request]) {
                BrowserLog(@"[TorrentLoader] waiting for pieces index=%ld offset=%lld length=%lu", (long)index, offset, (unsigned long)length);
                [self.waitingRequests addObject:request];
            }
            [manager prioritizeTorrent:hash fileIndex:index offset:offset];
        }
    }
}

@end
