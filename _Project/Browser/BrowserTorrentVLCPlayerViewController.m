#import "BrowserTorrentVLCPlayerViewController.h"

#import "BrowserTorrentHTTPServer.h"
#import "BrowserTorrentManager.h"
#import "BrowserTVAppearance.h"

#import <TVVLCKit/TVVLCKit.h>

@interface BrowserTorrentVLCPlayerViewController () <VLCMediaPlayerDelegate>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) NSInteger fileIndex;
@property (nonatomic, copy) NSString *mediaTitle;
@property (nonatomic) BrowserTorrentHTTPServer *server;
@property (nonatomic) VLCMediaPlayer *vlcPlayer;
@property (nonatomic) UILabel *statusLabel;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *timeLabel;
@property (nonatomic) UIProgressView *progressView;
@property (nonatomic) UIView *controlsView;
@property (nonatomic) UIButton *playButton;
@property (nonatomic) NSTimer *progressTimer;
@property (nonatomic) NSUInteger controlsGeneration;
@property (nonatomic) NSInteger lastReportedState;
@property (nonatomic) UIView *headerView;
@property (nonatomic) NSTimeInterval lastDurationLogTime;
@property (nonatomic) UIView *videoView;
@property (nonatomic) int64_t lastPlaybackTime;
@property (nonatomic) NSTimeInterval lastPlaybackProgressTime;
@end

@implementation BrowserTorrentVLCPlayerViewController

static NSInteger const kBrowserVLCControlIconTag = 9797;

- (UIVisualEffectView *)glassBackdrop {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = BrowserTVPanelEffect();
    UIVisualEffectView *backdrop = [[UIVisualEffectView alloc] initWithEffect:effect];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    backdrop.layer.borderWidth = glassClass != Nil ? 0 : 1;
    backdrop.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    return backdrop;
}

- (instancetype)initWithTorrentIdentifier:(NSString *)identifier fileIndex:(NSInteger)index title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _identifier = [identifier copy];
        _fileIndex = index;
        _mediaTitle = [title copy] ?: @"";
        _lastReportedState = -1;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UIView *videoView = [UIView new];
    videoView.translatesAutoresizingMaskIntoConstraints = NO;
    videoView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:videoView];
    self.videoView = videoView;
    [NSLayoutConstraint activateConstraints:@[
        [videoView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [videoView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [videoView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [videoView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.clearColor;
    [self.view addSubview:header];
    self.headerView = header;
    UIVisualEffectView *headerBackdrop = [self glassBackdrop];
    [header addSubview:headerBackdrop];
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = self.mediaTitle;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    [header addSubview:title];
    self.titleLabel = title;
    UILabel *status = [UILabel new];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.text = @"Preparing torrent playback…";
    status.textColor = UIColor.whiteColor;
    status.font = [UIFont systemFontOfSize:22];
    [header addSubview:status];
    self.statusLabel = status;
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [header.heightAnchor constraintEqualToConstant:145],
        [headerBackdrop.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [headerBackdrop.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [headerBackdrop.topAnchor constraintEqualToAnchor:header.topAnchor],
        [headerBackdrop.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:80],
        [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:55],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-80],
        [status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
    ]];

    UIView *controls = [UIView new];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    controls.backgroundColor = UIColor.clearColor;
    [self.view addSubview:controls];
    self.controlsView = controls;
    UIVisualEffectView *controlsBackdrop = [self glassBackdrop];
    [controls addSubview:controlsBackdrop];
    UIProgressView *progress = [UIProgressView new];
    progress.translatesAutoresizingMaskIntoConstraints = NO;
    progress.progressTintColor = UIColor.whiteColor;
    progress.trackTintColor = [UIColor colorWithWhite:1 alpha:0.35];
    [controls addSubview:progress];
    self.progressView = progress;
    UILabel *time = [UILabel new];
    time.translatesAutoresizingMaskIntoConstraints = NO;
    time.textColor = UIColor.whiteColor;
    time.font = [UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightMedium];
    time.text = @"0:00 / --:--";
    [controls addSubview:time];
    self.timeLabel = time;

    UIButton *close = [self controlButtonWithSymbol:@"xmark" label:@"Close" action:@selector(closePressed)];
    UIButton *previous = [self controlButtonWithSymbol:@"backward.end.fill" label:@"Start or previous file" action:@selector(startOrPreviousPressed)];
    UIButton *back30 = [self controlButtonWithSymbol:@"gobackward.30" label:@"Back 30 seconds" action:@selector(seekBackThirtyPressed)];
    UIButton *back = [self controlButtonWithSymbol:@"gobackward.10" label:@"Back 10 seconds" action:@selector(seekBackPressed)];
    UIButton *play = [self controlButtonWithSymbol:@"pause.fill" label:@"Pause" action:@selector(playPausePressed)];
    UIButton *forward = [self controlButtonWithSymbol:@"goforward.10" label:@"Forward 10 seconds" action:@selector(seekForwardPressed)];
    UIButton *forward30 = [self controlButtonWithSymbol:@"goforward.30" label:@"Forward 30 seconds" action:@selector(seekForwardThirtyPressed)];
    UIButton *next = [self controlButtonWithSymbol:@"forward.end.fill" label:@"Next file" action:@selector(nextFilePressed)];
    self.playButton = play;
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[close, previous, back30, back, play, forward, forward30, next]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 16;
    [controls addSubview:buttons];
    [NSLayoutConstraint activateConstraints:@[
        [controls.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controls.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [controls.heightAnchor constraintEqualToConstant:205],
        [controlsBackdrop.leadingAnchor constraintEqualToAnchor:controls.leadingAnchor],
        [controlsBackdrop.trailingAnchor constraintEqualToAnchor:controls.trailingAnchor],
        [controlsBackdrop.topAnchor constraintEqualToAnchor:controls.topAnchor],
        [controlsBackdrop.bottomAnchor constraintEqualToAnchor:controls.bottomAnchor],
        [progress.leadingAnchor constraintEqualToAnchor:controls.leadingAnchor constant:80],
        [progress.trailingAnchor constraintEqualToAnchor:controls.trailingAnchor constant:-80],
        [progress.topAnchor constraintEqualToAnchor:controls.topAnchor constant:28],
        [time.leadingAnchor constraintEqualToAnchor:progress.leadingAnchor],
        [time.topAnchor constraintEqualToAnchor:progress.bottomAnchor constant:12],
        [buttons.centerXAnchor constraintEqualToAnchor:controls.centerXAnchor],
        [buttons.widthAnchor constraintEqualToConstant:1320],
        [buttons.topAnchor constraintEqualToAnchor:time.bottomAnchor constant:12],
        [buttons.heightAnchor constraintEqualToConstant:72],
    ]];

    UILongPressGestureRecognizer *contextPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                               action:@selector(handleContextPress:)];
    contextPress.minimumPressDuration = 0.6;
    contextPress.allowedPressTypes = @[@(UIPressTypeSelect)];
    contextPress.cancelsTouchesInView = YES;
    [self.view addGestureRecognizer:contextPress];

    [self prepareCurrentFile];
}

- (void)handleContextPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self showControls];
    UIAlertController *actions = [UIAlertController alertControllerWithTitle:self.mediaTitle
                                                                     message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [actions addAction:[UIAlertAction actionWithTitle:self.vlcPlayer.isPlaying ? @"Pause" : @"Play"
                                                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf playPausePressed];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"Start of File" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        weakSelf.vlcPlayer.time = [VLCTime timeWithNumber:@0];
        [weakSelf showControls];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"Close Player" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf closePressed];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:actions animated:YES completion:nil];
}

- (void)prepareCurrentFile {
    BrowserTorrentManager *manager = [BrowserTorrentManager sharedManager];
    NSURL *mediaURL = nil;
    if ([manager isFileCompleteForTorrent:self.identifier fileIndex:self.fileIndex]) {
        mediaURL = [manager fileURLForTorrent:self.identifier fileIndex:self.fileIndex];
        if (![[NSFileManager defaultManager] fileExistsAtPath:mediaURL.path]) mediaURL = nil;
    }
    if (!mediaURL) {
        self.server = [[BrowserTorrentHTTPServer alloc] initWithTorrentIdentifier:self.identifier fileIndex:self.fileIndex];
        NSError *error = nil;
        if (![self.server startWithError:&error]) {
            self.statusLabel.text = error.localizedDescription ?: @"Cannot open the selected torrent file.";
            return;
        }
        mediaURL = self.server.mediaURL;
    }
    VLCMedia *media = [VLCMedia mediaWithURL:mediaURL];
    [media addOption:@":network-caching=3000"];
    self.vlcPlayer = [[VLCMediaPlayer alloc] initWithOptions:@[]];
    self.vlcPlayer.delegate = self;
    self.vlcPlayer.drawable = self.videoView;
    self.vlcPlayer.media = media;
    self.lastPlaybackTime = 0;
    self.lastPlaybackProgressTime = NSDate.date.timeIntervalSince1970;
    NSLog(@"[TorrentVLC] prepared fileIndex=%ld local=%d", (long)self.fileIndex, mediaURL.isFileURL);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    if (self.vlcPlayer) [self.vlcPlayer play];
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshProgress) userInfo:nil repeats:YES];
    [self refreshProgress];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.vlcPlayer.delegate = nil;
    [self.vlcPlayer stop];
    [self.server stop];
    [self.progressTimer invalidate];
    self.progressTimer = nil;
    self.controlsGeneration++;
}

- (BOOL)canBecomeFirstResponder { return YES; }

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return self.controlsView.hidden ? @[] : @[self.playButton];
}

- (UIButton *)controlButtonWithSymbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = BrowserTVRestingSurfaceColor();
    button.layer.cornerRadius = 18;
    button.accessibilityLabel = label;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tag = kBrowserVLCControlIconTag;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.whiteColor;
    icon.userInteractionEnabled = NO;
    [button addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:44],
        [icon.heightAnchor constraintEqualToConstant:44],
    ]];
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    for (UIView *view in @[context.previouslyFocusedView ?: [UIView new], context.nextFocusedView ?: [UIView new]]) {
        if (![view isKindOfClass:UIButton.class] || ![view isDescendantOfView:self.controlsView]) continue;
        BOOL focused = view == context.nextFocusedView;
        [coordinator addCoordinatedAnimations:^{
            view.backgroundColor = focused ? BrowserTVFocusedSurfaceColor() : BrowserTVRestingSurfaceColor();
            UIImageView *icon = (UIImageView *)[view viewWithTag:kBrowserVLCControlIconTag];
            icon.tintColor = focused ? BrowserTVFocusedTextColor() : UIColor.whiteColor;
        } completion:nil];
    }
    if ([context.nextFocusedView isKindOfClass:UIButton.class] &&
        [context.nextFocusedView isDescendantOfView:self.controlsView]) [self showControls];
}

- (NSString *)timeText:(int64_t)milliseconds {
    NSInteger seconds = MAX(0, milliseconds / 1000);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

- (void)refreshProgress {
    int64_t elapsed = self.vlcPlayer.time.value.longLongValue;
    int64_t duration = self.vlcPlayer.media.length.value.longLongValue;
    int64_t remaining = self.vlcPlayer.remainingTime.value.longLongValue;
    if (duration <= 0 && remaining < 0) duration = elapsed - remaining;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (elapsed > self.lastPlaybackTime) {
        self.lastPlaybackProgressTime = now;
        if (self.vlcPlayer.isPlaying) self.statusLabel.text = @"";
    } else if (self.vlcPlayer.state == VLCMediaPlayerStateBuffering &&
               now - self.lastPlaybackProgressTime > 2.5) {
        self.statusLabel.text = @"Buffering torrent…";
    }
    self.lastPlaybackTime = elapsed;
    if (now - self.lastDurationLogTime >= 15) {
        NSLog(@"[TorrentVLC] elapsedMs=%lld durationMs=%lld remainingMs=%lld playing=%d",
            (long long)elapsed, (long long)duration, (long long)remaining, self.vlcPlayer.isPlaying);
        self.lastDurationLogTime = now;
    }
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self timeText:elapsed],
        duration > 0 ? [self timeText:duration] : @"--:--"];
    self.progressView.progress = duration > 0 ? MIN(1.0, MAX(0.0, (double)elapsed / duration)) : 0;
    BOOL playing = self.vlcPlayer.isPlaying;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightSemibold];
    UIImageView *playIcon = (UIImageView *)[self.playButton viewWithTag:kBrowserVLCControlIconTag];
    playIcon.image = [UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"
                                  withConfiguration:configuration];
    self.playButton.accessibilityLabel = playing ? @"Pause" : @"Play";
}

- (void)showControls {
    self.controlsView.hidden = NO;
    self.headerView.hidden = NO;
    self.controlsGeneration++;
    [self scheduleControlsHideForGeneration:self.controlsGeneration after:5];
}

- (void)scheduleControlsHideForGeneration:(NSUInteger)generation after:(NSTimeInterval)delay {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf || weakSelf.controlsGeneration != generation || !weakSelf.view.window) return;
        if (!weakSelf.vlcPlayer.isPlaying ||
            NSDate.date.timeIntervalSince1970 - weakSelf.lastPlaybackProgressTime > 2.5) {
            [weakSelf scheduleControlsHideForGeneration:generation after:1];
            return;
        }
        weakSelf.controlsView.hidden = YES;
        weakSelf.headerView.hidden = YES;
        [weakSelf setNeedsFocusUpdate];
        [weakSelf updateFocusIfNeeded];
    });
}

- (void)closePressed { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)playPausePressed {
    if (self.vlcPlayer.isPlaying) [self.vlcPlayer pause]; else [self.vlcPlayer play];
    [self showControls];
    [self refreshProgress];
}
- (void)seekBackPressed { [self seekByMilliseconds:-10000]; }
- (void)seekForwardPressed { [self seekByMilliseconds:10000]; }
- (void)seekBackThirtyPressed { [self seekByMilliseconds:-30000]; }
- (void)seekForwardThirtyPressed { [self seekByMilliseconds:30000]; }

- (void)startOrPreviousPressed {
    if (self.vlcPlayer.time.value.longLongValue > 5000) {
        self.vlcPlayer.time = [VLCTime timeWithNumber:@0];
        [self showControls];
        return;
    }
    [self switchToAdjacentFileInDirection:-1];
}

- (void)nextFilePressed { [self switchToAdjacentFileInDirection:1]; }

- (void)switchToAdjacentFileInDirection:(NSInteger)direction {
    NSArray<NSString *> *extensions = @[@"mp4", @"m4v", @"mov", @"mp3", @"m4a", @"mkv", @"avi"];
    BrowserTorrentFile *candidate = nil;
    for (BrowserTorrentFile *file in [[BrowserTorrentManager sharedManager] filesForTorrent:self.identifier]) {
        if (file.padFile || ![extensions containsObject:file.name.pathExtension.lowercaseString]) continue;
        if (direction > 0 && file.index > self.fileIndex && (!candidate || file.index < candidate.index)) candidate = file;
        if (direction < 0 && file.index < self.fileIndex && (!candidate || file.index > candidate.index)) candidate = file;
    }
    if (!candidate) {
        if (direction < 0) self.vlcPlayer.time = [VLCTime timeWithNumber:@0];
        [self showControls];
        return;
    }
    self.vlcPlayer.delegate = nil;
    [self.vlcPlayer stop];
    [self.server stop];
    self.fileIndex = candidate.index;
    self.mediaTitle = candidate.name;
    self.titleLabel.text = candidate.name;
    self.statusLabel.text = @"Preparing torrent playback…";
    self.lastReportedState = -1;
    self.lastDurationLogTime = 0;
    [[BrowserTorrentManager sharedManager] prioritizePlaybackForTorrent:self.identifier fileIndex:self.fileIndex];
    [self prepareCurrentFile];
    [self.vlcPlayer play];
    [self showControls];
    [self refreshProgress];
}
- (void)seekByMilliseconds:(int64_t)delta {
    int64_t target = MAX(0, self.vlcPlayer.time.value.longLongValue + delta);
    self.vlcPlayer.time = [VLCTime timeWithNumber:@(target)];
    [self showControls];
    [self refreshProgress];
}

- (void)mediaPlayerStateChanged:(NSNotification *)notification {
    (void)notification;
    VLCMediaPlayerState state = self.vlcPlayer.state;
    if (self.lastReportedState == state) return;
    self.lastReportedState = state;
    NSLog(@"[TorrentVLC] state=%ld", (long)state);
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (state) {
            case VLCMediaPlayerStateOpening: self.statusLabel.text = @"Opening media…"; break;
            case VLCMediaPlayerStateBuffering:
                if (NSDate.date.timeIntervalSince1970 - self.lastPlaybackProgressTime > 2.5)
                    self.statusLabel.text = @"Buffering torrent…";
                break;
            case VLCMediaPlayerStatePlaying: self.statusLabel.text = @""; [self showControls]; break;
            case VLCMediaPlayerStatePaused: self.statusLabel.text = @"Paused"; break;
            case VLCMediaPlayerStateError: self.statusLabel.text = @"Playback failed. Check torrent availability or file format."; break;
            case VLCMediaPlayerStateEnded: self.statusLabel.text = @"Playback finished"; break;
            default: break;
        }
        if (state == VLCMediaPlayerStateOpening || state == VLCMediaPlayerStateBuffering ||
            state == VLCMediaPlayerStatePaused || state == VLCMediaPlayerStateError) [self showControls];
        [self refreshProgress];
    });
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    UIPressType type = presses.anyObject.type;
    if (type == UIPressTypeMenu) {
        [self closePressed];
        return;
    }
    if (type == UIPressTypeSelect && self.controlsView.hidden) {
        [self showControls];
        [self setNeedsFocusUpdate];
        [self updateFocusIfNeeded];
        return;
    }
    if (type == UIPressTypeSelect) {
        [super pressesEnded:presses withEvent:event];
        return;
    }
    if (type == UIPressTypePlayPause) {
        [self playPausePressed];
        return;
    }
    if (type == UIPressTypeLeftArrow || type == UIPressTypeRightArrow) {
        if (!self.controlsView.hidden) {
            [super pressesEnded:presses withEvent:event];
            return;
        }
        [self seekByMilliseconds:type == UIPressTypeLeftArrow ? -10000 : 10000];
        return;
    }
    if (type == UIPressTypeUpArrow || type == UIPressTypeDownArrow) {
        [self showControls];
        [self setNeedsFocusUpdate];
        [self updateFocusIfNeeded];
        return;
    }
    [super pressesEnded:presses withEvent:event];
}

@end
