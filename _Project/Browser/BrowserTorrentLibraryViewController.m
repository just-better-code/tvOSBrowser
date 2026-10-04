#import "BrowserTorrentLibraryViewController.h"

#import "BrowserTorrentManager.h"
#import "BrowserTorrentVLCPlayerViewController.h"
#import "BrowserWebView.h"

static NSArray<NSHTTPCookie *> *BrowserTorrentCookiesForURL(NSArray<NSHTTPCookie *> *cookies, NSURL *URL) {
    NSMutableArray<NSHTTPCookie *> *matching = [NSMutableArray array];
    NSString *host = URL.host.lowercaseString ?: @"";
    NSString *path = URL.path.length > 0 ? URL.path : @"/";
    for (NSHTTPCookie *cookie in cookies) {
        NSString *domain = cookie.domain.lowercaseString ?: @"";
        BOOL subdomains = [domain hasPrefix:@"."];
        if (subdomains) domain = [domain substringFromIndex:1];
        BOOL hostMatches = [host isEqualToString:domain] || (subdomains && [host hasSuffix:[@"." stringByAppendingString:domain]]);
        if (!hostMatches || ![path hasPrefix:cookie.path ?: @"/"] ||
            (cookie.isSecure && ![URL.scheme.lowercaseString isEqualToString:@"https"])) continue;
        [matching addObject:cookie];
    }
    return matching;
}

@interface BrowserTorrentDownloadDelegate : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy) NSArray<NSHTTPCookie *> *cookies;
@end

@implementation BrowserTorrentDownloadDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session; (void)task; (void)response;
    if (![@[@"http", @"https"] containsObject:request.URL.scheme.lowercaseString ?: @""]) {
        completionHandler(nil);
        return;
    }
    NSMutableURLRequest *next = [request mutableCopy];
    [next setValue:nil forHTTPHeaderField:@"Cookie"];
    NSArray *cookies = BrowserTorrentCookiesForURL(self.cookies, request.URL);
    if (cookies.count > 0) {
        [next setValue:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies][@"Cookie"] forHTTPHeaderField:@"Cookie"];
    }
    completionHandler(next);
}
@end

@interface BrowserTorrentLibraryViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) UILabel *heading;
@property (nonatomic) UILabel *subtitle;
@property (nonatomic) UITableView *tableView;
@property (nonatomic) UIButton *addButton;
@property (nonatomic) UIButton *cleanButton;
@property (nonatomic) UIButton *backButton;
@property (nonatomic) UIButton *pauseButton;
@property (nonatomic) UIButton *deleteButton;
@property (nonatomic) NSArray<BrowserTorrentSnapshot *> *torrents;
@property (nonatomic) NSArray<BrowserTorrentFile *> *files;
@property (nonatomic, copy) NSString *selectedIdentifier;
@property (nonatomic, copy) NSString *loadingMessage;
@property (nonatomic, copy) NSString *displayedIdentifier;
@property (nonatomic) NSInteger displayedRowCount;
@property (nonatomic) NSTimer *refreshTimer;
@property (nonatomic) BrowserTorrentFile *pendingPlaybackFile;
@property (nonatomic, copy) NSString *pendingPlaybackIdentifier;
@property (nonatomic) NSInteger focusedFileRow;
@end

@implementation BrowserTorrentLibraryViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        _focusedFileRow = NSNotFound;
    }
    return self;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    button.layer.cornerRadius = 16;
    button.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:UIColor.blackColor forState:UIControlStateFocused];
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.10 blue:0.17 alpha:1];
    self.heading = [UILabel new];
    self.heading.translatesAutoresizingMaskIntoConstraints = NO;
    self.heading.font = [UIFont systemFontOfSize:56 weight:UIFontWeightBold];
    self.heading.textColor = UIColor.whiteColor;
    [self.view addSubview:self.heading];
    self.subtitle = [UILabel new];
    self.subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitle.font = [UIFont systemFontOfSize:22];
    self.subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    [self.view addSubview:self.subtitle];

    self.addButton = [self button:@"Add Torrent" action:@selector(promptToAddTorrent)];
    self.cleanButton = [self button:@"Clean Cache" action:@selector(cleanPressed)];
    self.backButton = [self button:@"Back" action:@selector(backPressed)];
    self.pauseButton = [self button:@"Pause" action:@selector(pausePressed)];
    self.deleteButton = [self button:@"Remove" action:@selector(deletePressed)];
    UIButton *done = [self button:@"Done" action:@selector(donePressed)];
    for (UIButton *button in @[self.addButton, self.cleanButton, self.backButton, self.pauseButton, self.deleteButton, done]) {
        [self.view addSubview:button];
    }

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = 106;
    table.backgroundColor = UIColor.clearColor;
    [self.view addSubview:table];
    self.tableView = table;
    self.displayedRowCount = -1;

    [NSLayoutConstraint activateConstraints:@[
        [self.heading.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:110],
        [self.heading.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:70],
        [self.subtitle.leadingAnchor constraintEqualToAnchor:self.heading.leadingAnchor],
        [self.subtitle.topAnchor constraintEqualToAnchor:self.heading.bottomAnchor constant:8],
        [self.addButton.leadingAnchor constraintEqualToAnchor:self.heading.leadingAnchor],
        [self.addButton.topAnchor constraintEqualToAnchor:self.subtitle.bottomAnchor constant:30],
        [self.backButton.leadingAnchor constraintEqualToAnchor:self.addButton.trailingAnchor constant:18],
        [self.cleanButton.leadingAnchor constraintEqualToAnchor:self.backButton.leadingAnchor],
        [self.cleanButton.centerYAnchor constraintEqualToAnchor:self.addButton.centerYAnchor],
        [self.pauseButton.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:18],
        [self.deleteButton.leadingAnchor constraintEqualToAnchor:self.pauseButton.trailingAnchor constant:18],
        [done.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-110],
        [self.backButton.centerYAnchor constraintEqualToAnchor:self.addButton.centerYAnchor],
        [self.pauseButton.centerYAnchor constraintEqualToAnchor:self.addButton.centerYAnchor],
        [self.deleteButton.centerYAnchor constraintEqualToAnchor:self.addButton.centerYAnchor],
        [done.centerYAnchor constraintEqualToAnchor:self.addButton.centerYAnchor],
        [self.addButton.widthAnchor constraintEqualToConstant:240],
        [self.cleanButton.widthAnchor constraintEqualToConstant:240],
        [self.backButton.widthAnchor constraintEqualToConstant:160],
        [self.pauseButton.widthAnchor constraintEqualToConstant:160],
        [self.deleteButton.widthAnchor constraintEqualToConstant:170],
        [done.widthAnchor constraintEqualToConstant:150],
        [self.addButton.heightAnchor constraintEqualToConstant:68],
        [self.cleanButton.heightAnchor constraintEqualToAnchor:self.addButton.heightAnchor],
        [self.backButton.heightAnchor constraintEqualToAnchor:self.addButton.heightAnchor],
        [self.pauseButton.heightAnchor constraintEqualToAnchor:self.addButton.heightAnchor],
        [self.deleteButton.heightAnchor constraintEqualToAnchor:self.addButton.heightAnchor],
        [done.heightAnchor constraintEqualToAnchor:self.addButton.heightAnchor],
        [table.leadingAnchor constraintEqualToAnchor:self.heading.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:done.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:self.addButton.bottomAnchor constant:32],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-70],
    ]];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)refresh {
    self.torrents = [[BrowserTorrentManager sharedManager] torrents];
    if (self.selectedIdentifier.length > 0) {
        self.files = [[BrowserTorrentManager sharedManager] filesForTorrent:self.selectedIdentifier];
        BrowserTorrentSnapshot *selected = nil;
        for (BrowserTorrentSnapshot *torrent in self.torrents) {
            if ([torrent.identifier isEqualToString:self.selectedIdentifier]) { selected = torrent; break; }
        }
        if (!selected) { self.selectedIdentifier = nil; self.files = nil; }
        self.heading.text = selected.name.length > 0 ? selected.name : @"Torrents";
        self.subtitle.text = selected ? [NSString stringWithFormat:@"%@ • %.0f%% • %ld peers • %.1f MB/s", selected.state, selected.progress * 100, (long)selected.peers, selected.downloadRate / 1048576.0] : @"";
        if (self.pendingPlaybackFile && [self.pendingPlaybackIdentifier isEqualToString:self.selectedIdentifier]) {
            self.subtitle.text = [selected.state isEqualToString:@"Checking files"]
                ? [NSString stringWithFormat:@"Checking cached file before playback… %.0f%%", selected.progress * 100]
                : self.subtitle.text;
        }
        self.pauseButton.enabled = selected != nil;
        [self.pauseButton setTitle:[selected.state isEqualToString:@"Paused"] ? @"Resume" : @"Pause" forState:UIControlStateNormal];
    } else {
        self.heading.text = @"Torrents";
        self.subtitle.text = self.loadingMessage ?: @"Stored in Apple TV cache; tvOS may remove them when space is needed.";
    }
    BOOL details = self.selectedIdentifier.length > 0;
    self.backButton.hidden = !details;
    self.pauseButton.hidden = !details;
    self.deleteButton.hidden = !details;
    self.addButton.hidden = details;
    self.cleanButton.hidden = details;
    NSInteger count = details ? self.files.count : self.torrents.count;
    if (self.displayedRowCount != count || ![(self.displayedIdentifier ?: @"") isEqualToString:(self.selectedIdentifier ?: @"")]) {
        self.displayedRowCount = count;
        self.displayedIdentifier = self.selectedIdentifier;
        [self.tableView reloadData];
    } else {
        for (UITableViewCell *cell in self.tableView.visibleCells) {
            NSIndexPath *path = [self.tableView indexPathForCell:cell];
            if (path && path.row < count) [self configureCell:cell atIndexPath:path];
        }
    }
    if (self.pendingPlaybackFile) {
        BrowserTorrentSnapshot *pendingTorrent = nil;
        for (BrowserTorrentSnapshot *torrent in self.torrents) {
            if ([torrent.identifier isEqualToString:self.pendingPlaybackIdentifier]) { pendingTorrent = torrent; break; }
        }
        if (!pendingTorrent || ![self.pendingPlaybackIdentifier isEqualToString:self.selectedIdentifier]) {
            self.pendingPlaybackFile = nil;
            self.pendingPlaybackIdentifier = nil;
        } else if (![pendingTorrent.state isEqualToString:@"Checking files"]) {
            BrowserTorrentFile *file = self.pendingPlaybackFile;
            self.pendingPlaybackFile = nil;
            self.pendingPlaybackIdentifier = nil;
            [self launchPlayerForFile:file];
        }
    }
}

- (void)selectTorrent:(NSString *)identifier {
    self.loadingMessage = nil;
    self.selectedIdentifier = [identifier copy];
    [self refresh];
}

- (void)showImportError:(NSString *)message {
    self.loadingMessage = message.length > 0 ? message : @"Could not add torrent.";
    [self refresh];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.selectedIdentifier ? self.files.count : self.torrents.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TorrentRow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TorrentRow"];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    cell.textLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightMedium];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:20];
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (self.selectedIdentifier) {
        BrowserTorrentFile *file = self.files[indexPath.row];
        cell.textLabel.text = file.path;
        cell.detailTextLabel.text = file.padFile ? @"Padding file" : [NSString stringWithFormat:@"%@ • %.0f%% • %.1f MB", file.downloadEnabled ? @"Downloading" : @"Skipped", file.size > 0 ? 100.0 * file.downloaded / file.size : 0, file.size / 1048576.0];
    } else {
        BrowserTorrentSnapshot *torrent = self.torrents[indexPath.row];
        cell.textLabel.text = torrent.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %.0f%% • %.1f MB/s", torrent.state, torrent.progress * 100, torrent.downloadRate / 1048576.0];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.selectedIdentifier) {
        [self selectTorrent:self.torrents[indexPath.row].identifier];
        return;
    }
    BrowserTorrentFile *file = self.files[indexPath.row];
    if (file.padFile) return;
    UIAlertController *actions = [UIAlertController alertControllerWithTitle:file.name message:file.path preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    if ([self isPlayableFile:file]) {
        [actions addAction:[UIAlertAction actionWithTitle:@"Play Now (Priority)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf playFile:file];
        }]];
    }
    [actions addAction:[UIAlertAction actionWithTitle:file.downloadEnabled ? @"Skip Download" : @"Download File"
                                                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [[BrowserTorrentManager sharedManager] setDownloadEnabled:!file.downloadEnabled forTorrent:weakSelf.selectedIdentifier fileIndex:file.index];
        [weakSelf refresh];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:actions animated:YES completion:nil];
}

- (BOOL)isPlayableFile:(BrowserTorrentFile *)file {
    return file && !file.padFile && [@[@"mp4", @"m4v", @"mov", @"mp3", @"m4a", @"mkv", @"avi"]
        containsObject:file.name.pathExtension.lowercaseString];
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    UITableViewCell *focusedCell = nil;
    for (id item in @[context.previouslyFocusedView ?: [UIView new], context.nextFocusedView ?: [UIView new]]) {
        UIView *view = [item isKindOfClass:UIView.class] ? item : nil;
        while (view && ![view isKindOfClass:UITableViewCell.class] && ![view isKindOfClass:UIButton.class]) view = view.superview;
        BOOL focused = item == context.nextFocusedView;
        if ([view isKindOfClass:UITableViewCell.class]) {
            UITableViewCell *cell = (UITableViewCell *)view;
            cell.textLabel.textColor = focused ? UIColor.blackColor : UIColor.whiteColor;
            cell.detailTextLabel.textColor = focused ? [UIColor darkGrayColor] : [UIColor colorWithWhite:1 alpha:0.7];
            if (focused) focusedCell = cell;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            [button setTitleColor:focused ? UIColor.blackColor : UIColor.whiteColor forState:UIControlStateNormal];
        }
    }
    NSIndexPath *path = focusedCell ? [self.tableView indexPathForCell:focusedCell] : nil;
    self.focusedFileRow = path ? path.row : NSNotFound;
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (presses.anyObject.type == UIPressTypePlayPause && self.selectedIdentifier &&
        self.focusedFileRow >= 0 && self.focusedFileRow < self.files.count) {
        BrowserTorrentFile *file = self.files[self.focusedFileRow];
        if ([self isPlayableFile:file]) {
            [self playFile:file];
            return;
        }
    }
    [super pressesEnded:presses withEvent:event];
}

- (void)playFile:(BrowserTorrentFile *)file {
    if (!self.selectedIdentifier) return;
    for (BrowserTorrentSnapshot *torrent in [[BrowserTorrentManager sharedManager] torrents]) {
        if ([torrent.identifier isEqualToString:self.selectedIdentifier] && [torrent.state isEqualToString:@"Checking files"]) {
            self.pendingPlaybackFile = file;
            self.pendingPlaybackIdentifier = self.selectedIdentifier;
            [self refresh];
            return;
        }
    }
    [self launchPlayerForFile:file];
}

- (void)launchPlayerForFile:(BrowserTorrentFile *)file {
    [[BrowserTorrentManager sharedManager] prioritizePlaybackForTorrent:self.selectedIdentifier fileIndex:file.index];
    [self refresh];
    BrowserTorrentVLCPlayerViewController *player = [[BrowserTorrentVLCPlayerViewController alloc]
        initWithTorrentIdentifier:self.selectedIdentifier fileIndex:file.index title:file.name];
    [self presentViewController:player animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Torrents" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptToAddTorrent {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Torrent" message:@"Paste a magnet link or a .torrent URL" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"magnet:?xt=… or https://…/file.torrent";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf addInput:alert.textFields.firstObject.text ?: @""];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed.lowercaseString hasPrefix:@"magnet:"]) {
        NSError *error = nil;
        NSString *identifier = [[BrowserTorrentManager sharedManager] identifierForMagnetString:trimmed error:&error];
        if (identifier) [self selectTorrent:identifier]; else [self showMessage:error.localizedDescription];
        return;
    }
    NSURL *URL = [NSURL URLWithString:trimmed];
    if (![@[@"http", @"https"] containsObject:URL.scheme.lowercaseString ?: @""]) {
        [self showMessage:@"Enter a magnet link or an HTTP(S) .torrent URL."];
        return;
    }
    [self importTorrentRequest:[NSURLRequest requestWithURL:URL]];
}

- (void)importTorrentRequest:(NSURLRequest *)request {
    if (!request.URL) return;
    self.loadingMessage = @"Fetching .torrent file…";
    [self refresh];
    NSArray<NSHTTPCookie *> *cookies = [BrowserWebView allCookies];
    NSMutableURLRequest *downloadRequest = [request mutableCopy];
    if ([downloadRequest valueForHTTPHeaderField:@"Cookie"].length == 0) {
        NSArray *matching = BrowserTorrentCookiesForURL(cookies, request.URL);
        if (matching.count > 0) {
            [downloadRequest setValue:[NSHTTPCookie requestHeaderFieldsWithCookies:matching][@"Cookie"] forHTTPHeaderField:@"Cookie"];
        }
    }
    BrowserTorrentDownloadDelegate *delegate = [BrowserTorrentDownloadDelegate new];
    delegate.cookies = cookies;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPShouldSetCookies = NO;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:nil];
    __weak typeof(self) weakSelf = self;
    [[session downloadTaskWithRequest:downloadRequest completionHandler:^(NSURL *temporaryURL, NSURLResponse *response, NSError *downloadError) {
        NSError *error = downloadError;
        NSData *data = nil;
        if (!error && [response isKindOfClass:NSHTTPURLResponse.class]) {
            NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
            if (status < 200 || status >= 300) {
                error = [NSError errorWithDomain:@"BrowserTorrent" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Torrent server returned HTTP %ld.", (long)status]}];
            }
        }
        if (!error && temporaryURL) {
            NSNumber *size = [[[NSFileManager defaultManager] attributesOfItemAtPath:temporaryURL.path error:&error] objectForKey:NSFileSize];
            if (!error && size.unsignedLongLongValue > 16 * 1024 * 1024) {
                error = [NSError errorWithDomain:@"BrowserTorrent" code:3 userInfo:@{NSLocalizedDescriptionKey: @"The .torrent file is larger than 16 MB."}];
            }
            if (!error) data = [NSData dataWithContentsOfURL:temporaryURL options:0 error:&error];
        }
        NSError *fetchError = error;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *importError = fetchError;
            NSString *resultIdentifier = data && !importError ? [[BrowserTorrentManager sharedManager] identifierForTorrentData:data error:&importError] : nil;
            NSString *message = importError.localizedDescription ?: @"Could not add torrent.";
            weakSelf.loadingMessage = nil;
            if (resultIdentifier) [weakSelf selectTorrent:resultIdentifier];
            else [weakSelf showImportError:message];
        });
        [session finishTasksAndInvalidate];
    }] resume];
}

- (void)backPressed { self.pendingPlaybackFile = nil; self.pendingPlaybackIdentifier = nil; self.selectedIdentifier = nil; self.files = nil; [self refresh]; }
- (void)donePressed { self.pendingPlaybackFile = nil; self.pendingPlaybackIdentifier = nil; [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)pausePressed {
    BrowserTorrentSnapshot *selected = nil;
    for (BrowserTorrentSnapshot *torrent in self.torrents) {
        if ([torrent.identifier isEqualToString:self.selectedIdentifier]) { selected = torrent; break; }
    }
    [[BrowserTorrentManager sharedManager] setPaused:![selected.state isEqualToString:@"Paused"] forTorrent:self.selectedIdentifier];
    [self refresh];
}

- (void)deletePressed {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Torrent" message:@"Remove the torrent and its cached files?" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[BrowserTorrentManager sharedManager] removeTorrent:weakSelf.selectedIdentifier deleteFiles:YES];
        weakSelf.selectedIdentifier = nil;
        [weakSelf refresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)cleanPressed {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clean Torrent Cache"
        message:@"Remove cached files that are not used by any torrent in this library? Browser history and website data are not affected."
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clean" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSUInteger count = 0;
        uint64_t freed = [[BrowserTorrentManager sharedManager] cleanUnlistedCacheFilesWithRemovedCount:&count];
        [weakSelf showMessage:[NSString stringWithFormat:@"Removed %lu unlisted files and freed %.1f MB.",
            (unsigned long)count, freed / 1048576.0]];
        [weakSelf refresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
