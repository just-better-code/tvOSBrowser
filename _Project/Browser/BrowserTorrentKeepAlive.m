#import "BrowserTorrentKeepAlive.h"

#import <AVFoundation/AVFoundation.h>

static NSString * const kKeepAliveDefaultsKey = @"TorrentKeepAliveEnabled";

static void AppendWord(NSMutableData *data, uint16_t value) {
    uint8_t bytes[] = {(uint8_t)value, (uint8_t)(value >> 8)};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void AppendDWord(NSMutableData *data, uint32_t value) {
    uint8_t bytes[] = {(uint8_t)value, (uint8_t)(value >> 8), (uint8_t)(value >> 16), (uint8_t)(value >> 24)};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static NSData *OneSecondOfSilence(void) {
    const uint32_t sampleRate = 8000;
    const uint32_t sampleBytes = sampleRate * 2;
    NSMutableData *wav = [NSMutableData dataWithCapacity:44 + sampleBytes];
    [wav appendBytes:"RIFF" length:4];
    AppendDWord(wav, 36 + sampleBytes);
    [wav appendBytes:"WAVEfmt " length:8];
    AppendDWord(wav, 16);
    AppendWord(wav, 1);
    AppendWord(wav, 1);
    AppendDWord(wav, sampleRate);
    AppendDWord(wav, sampleBytes);
    AppendWord(wav, 2);
    AppendWord(wav, 16);
    [wav appendBytes:"data" length:4];
    AppendDWord(wav, sampleBytes);
    [wav increaseLengthBy:sampleBytes];
    return wav;
}

@interface BrowserTorrentKeepAlive ()
@property (nonatomic) AVAudioPlayer *player;
@end

@implementation BrowserTorrentKeepAlive

+ (instancetype)sharedKeepAlive {
    static BrowserTorrentKeepAlive *keepAlive;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keepAlive = [BrowserTorrentKeepAlive new]; });
    return keepAlive;
}

- (BOOL)isEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeepAliveDefaultsKey];
}

- (void)setEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kKeepAliveDefaultsKey];
    if (enabled) [self start]; else [self stop];
}

- (void)start {
    if (self.player.isPlaying) return;
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error] ||
        ![session setActive:YES error:&error]) {
        NSLog(@"[TorrentKeepAlive] Audio session failed: %@", error);
        return;
    }
    self.player = [[AVAudioPlayer alloc] initWithData:OneSecondOfSilence() error:&error];
    self.player.numberOfLoops = -1;
    self.player.volume = 0.01;
    [self.player prepareToPlay];
    if (![self.player play]) NSLog(@"[TorrentKeepAlive] Silent playback failed: %@", error);
}

- (void)stop {
    [self.player stop];
    self.player = nil;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

@end
