#import "BrowserHistoryStore.h"
#import <sqlite3.h>

@interface BrowserHistoryStore ()
@property (nonatomic) sqlite3 *database;
@end

@implementation BrowserHistoryStore

- (BOOL)copyLegacyDatabaseIntoOpenDatabaseAtPath:(NSString *)destinationPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSNumber *kind in @[@(NSCachesDirectory), @(NSDocumentDirectory)]) {
        NSURL *directory = [[fileManager URLsForDirectory:kind.unsignedIntegerValue
                                               inDomains:NSUserDomainMask] firstObject];
        NSString *sourcePath = [[directory URLByAppendingPathComponent:@"BrowserHistory.sqlite"] path];
        if (sourcePath.length == 0 || [sourcePath isEqualToString:destinationPath] ||
            ![fileManager fileExistsAtPath:sourcePath]) continue;

        sqlite3 *source = NULL;
        int openResult = sqlite3_open_v2(sourcePath.UTF8String, &source, SQLITE_OPEN_READONLY, NULL);
        if (openResult != SQLITE_OK) {
            NSLog(@"[History] Cannot read legacy database %@: %s", sourcePath, source ? sqlite3_errmsg(source) : "open failed");
            if (source != NULL) sqlite3_close(source);
            continue;
        }
        sqlite3_backup *backup = sqlite3_backup_init(self.database, "main", source, "main");
        int copyResult = backup != NULL ? sqlite3_backup_step(backup, -1) : sqlite3_errcode(self.database);
        int finishResult = backup != NULL ? sqlite3_backup_finish(backup) : copyResult;
        sqlite3_close(source);
        if (copyResult == SQLITE_DONE && finishResult == SQLITE_OK) {
            NSLog(@"[History] Moved saved database from %@ to %@", sourcePath, destinationPath);
            return YES;
        }
        NSLog(@"[History] Cannot move database from %@: %s", sourcePath, sqlite3_errmsg(self.database));
        return NO;
    }
    return YES;
}

+ (instancetype)sharedStore {
    static BrowserHistoryStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [BrowserHistoryStore new]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray<NSNumber *> *directoryKinds = @[@(NSApplicationSupportDirectory), @(NSDocumentDirectory)];
        for (NSNumber *kind in directoryKinds) {
            NSURL *directory = [[[NSFileManager defaultManager] URLsForDirectory:kind.unsignedIntegerValue
                                                                        inDomains:NSUserDomainMask] firstObject];
            NSError *directoryError = nil;
            BOOL ready = directory != nil && [[NSFileManager defaultManager] createDirectoryAtURL:directory
                                       withIntermediateDirectories:YES attributes:nil error:&directoryError];
            if (!ready) {
                NSLog(@"[History] Directory %@ unavailable: %@", directory.path, directoryError);
                continue;
            }
            NSString *path = [[directory URLByAppendingPathComponent:@"BrowserHistory.sqlite"] path];
            BOOL existingDatabase = [[NSFileManager defaultManager] fileExistsAtPath:path];
            if (sqlite3_open(path.UTF8String, &_database) == SQLITE_OK) {
                if (!existingDatabase && ![self copyLegacyDatabaseIntoOpenDatabaseAtPath:path]) {
                    sqlite3_close(_database);
                    _database = NULL;
                    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                    continue;
                }
                break;
            }
            NSLog(@"[History] Cannot open %@: %s", path, sqlite3_errmsg(_database));
            sqlite3_close(_database);
            _database = NULL;
        }
        if (_database == NULL) return self;
        const char *schema = "CREATE TABLE IF NOT EXISTS visits (id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT NOT NULL, visited_at REAL NOT NULL);"
                             "CREATE INDEX IF NOT EXISTS visits_url ON visits(url);"
                             "CREATE INDEX IF NOT EXISTS visits_recent ON visits(visited_at DESC, id DESC);"
                             "CREATE TABLE IF NOT EXISTS favorites (position INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT NOT NULL);";
        if (sqlite3_exec(_database, schema, NULL, NULL, NULL) != SQLITE_OK) {
            NSLog(@"[History] Cannot create schema: %s", sqlite3_errmsg(_database));
        } else {
            [self migrateLegacyHistory];
            [self migrateLegacyFavorites];
        }
    }
    return self;
}

- (void)migrateLegacyFavorites {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *legacy = [defaults arrayForKey:@"FAVORITES"];
    if ([self favorites].count == 0 && legacy.count > 0) {
        [self saveFavorites:legacy];
    } else {
        [defaults setObject:[self favorites] forKey:@"FAVORITES"];
    }
}

- (void)dealloc {
    if (_database != NULL) sqlite3_close(_database);
}

- (void)migrateLegacyHistory {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *snapshot = [defaults arrayForKey:@"HISTORY_BACKUP_V2"];
    NSArray *legacy = snapshot ?: [defaults arrayForKey:@"HISTORY"];
    NSUInteger storedCount = [self allVisits].count;
    if (storedCount > 0 || legacy.count == 0) {
        NSLog(@"[History] Opened %lu saved visits; backup has %lu", (unsigned long)storedCount, (unsigned long)legacy.count);
        [self syncHistoryBackup];
        return;
    }
    if (sqlite3_exec(self.database, "BEGIN TRANSACTION", NULL, NULL, NULL) != SQLITE_OK) return;
    sqlite3_stmt *statement = NULL;
    BOOL success = sqlite3_prepare_v2(self.database,
        "INSERT INTO visits (url,title,visited_at) VALUES (?,?,?)", -1, &statement, NULL) == SQLITE_OK;
    NSTimeInterval time = [NSDate date].timeIntervalSince1970 - legacy.count;
    for (id raw in [legacy reverseObjectEnumerator]) {
        if (!success) break;
        if (![raw isKindOfClass:[NSArray class]]) continue;
        NSArray *entry = raw;
        NSString *url = entry.count > 0 && [entry[0] isKindOfClass:NSString.class] ? entry[0] : @"";
        NSString *title = entry.count > 1 && [entry[1] isKindOfClass:NSString.class] ? entry[1] : @"";
        if (url.length == 0) continue;
        sqlite3_bind_text(statement, 1, url.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 2, title.UTF8String, -1, SQLITE_TRANSIENT);
        NSTimeInterval visitedAt = entry.count > 2 && [entry[2] isKindOfClass:NSNumber.class]
            ? [entry[2] doubleValue] : time;
        sqlite3_bind_double(statement, 3, visitedAt);
        time += 1;
        success = sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_reset(statement);
        sqlite3_clear_bindings(statement);
    }
    sqlite3_finalize(statement);
    if (sqlite3_exec(self.database, success ? "COMMIT" : "ROLLBACK", NULL, NULL, NULL) == SQLITE_OK && success) {
        NSLog(@"[History] Restored %lu visits from preferences", (unsigned long)legacy.count);
        [self syncHistoryBackup];
    }
}

- (void)syncHistoryBackup {
    if (self.database == NULL) return;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database,
            "SELECT url,title,visited_at FROM visits ORDER BY visited_at DESC,id DESC LIMIT 2000",
            -1, &statement, NULL) != SQLITE_OK) return;
    NSMutableArray *snapshot = [NSMutableArray array];
    NSMutableArray *backup = [NSMutableArray arrayWithCapacity:200];
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const char *url = (const char *)sqlite3_column_text(statement, 0);
        const char *title = (const char *)sqlite3_column_text(statement, 1);
        NSString *URLString = url ? [NSString stringWithUTF8String:url] : @"";
        NSString *pageTitle = title ? [NSString stringWithUTF8String:title] : @"";
        [snapshot addObject:@[URLString, pageTitle, @(sqlite3_column_double(statement, 2))]];
        if (backup.count < 200) [backup addObject:@[URLString, pageTitle]];
    }
    sqlite3_finalize(statement);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:snapshot forKey:@"HISTORY_BACKUP_V2"];
    [defaults setObject:backup forKey:@"HISTORY"];
    [defaults synchronize];
}

- (void)recordURLString:(NSString *)URLString title:(NSString *)title {
    if (self.database == NULL || URLString.length == 0) return;
    NSURL *url = [NSURL URLWithString:URLString];
    if (url.host.length == 0 || ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString]) return;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "INSERT INTO visits (url,title,visited_at) VALUES (?,?,?)", -1, &statement, NULL) != SQLITE_OK) return;
    sqlite3_bind_text(statement, 1, URLString.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, (title ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(statement, 3, [NSDate date].timeIntervalSince1970);
    BOOL success = sqlite3_step(statement) == SQLITE_DONE;
    if (!success) NSLog(@"[History] Cannot save visit: %s", sqlite3_errmsg(self.database));
    sqlite3_finalize(statement);
    if (success) [self syncHistoryBackup];
}

- (NSArray<NSDictionary *> *)recordsForSQL:(const char *)SQL limit:(NSUInteger)limit {
    if (self.database == NULL) return @[];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, SQL, -1, &statement, NULL) != SQLITE_OK) return @[];
    if (limit > 0) sqlite3_bind_int64(statement, 1, (sqlite3_int64)limit);
    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const char *url = (const char *)sqlite3_column_text(statement, 1);
        const char *title = (const char *)sqlite3_column_text(statement, 2);
        NSMutableDictionary *record = [@{@"id": @(sqlite3_column_int64(statement, 0)),
                                         @"url": url ? [NSString stringWithUTF8String:url] : @"",
                                         @"title": title ? [NSString stringWithUTF8String:title] : @"",
                                         @"count": @(sqlite3_column_int64(statement, 3))} mutableCopy];
        if (sqlite3_column_count(statement) > 4) record[@"visitedAt"] = @(sqlite3_column_double(statement, 4));
        [records addObject:record];
    }
    sqlite3_finalize(statement);
    return records;
}

- (NSArray<NSDictionary *> *)recentActiveWeekWithLimit:(NSUInteger)limit {
    return [self recordsForSQL:"SELECT v.id,v.url,v.title,counts.visits,counts.latest FROM visits v "
                               "JOIN (SELECT url,COUNT(*) visits,MAX(id) last_id,MAX(visited_at) latest FROM visits "
                               "WHERE visited_at >= (SELECT MAX(visited_at) - 604800 FROM visits) GROUP BY url) counts "
                               "ON v.id=counts.last_id ORDER BY counts.latest DESC, v.id DESC LIMIT ?"
                        limit:limit];
}

- (NSArray<NSDictionary *> *)allVisits {
    return [self recordsForSQL:"SELECT id,url,title,1,visited_at FROM visits ORDER BY visited_at DESC,id DESC" limit:0];
}

- (void)pruneOldVisits {
    if (self.database == NULL) return;
    NSDate *cutoff = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitMonth
                                                               value:-1 toDate:[NSDate date] options:0];
    if (cutoff == nil) return;
    sqlite3_stmt *statement = NULL;
    const char *SQL = "DELETE FROM visits WHERE visited_at < ? "
                      "AND id NOT IN (SELECT id FROM visits ORDER BY visited_at DESC,id DESC LIMIT 100)";
    if (sqlite3_prepare_v2(self.database, SQL, -1, &statement, NULL) != SQLITE_OK) return;
    sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970);
    int result = sqlite3_step(statement);
    int changed = sqlite3_changes(self.database);
    sqlite3_finalize(statement);
    if (result == SQLITE_DONE && changed > 0) [self syncHistoryBackup];
}

- (void)deleteVisitsWithIdentifiers:(NSArray<NSNumber *> *)identifiers {
    if (self.database == NULL || identifiers.count == 0) return;
    sqlite3_exec(self.database, "BEGIN TRANSACTION", NULL, NULL, NULL);
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "DELETE FROM visits WHERE id=?", -1, &statement, NULL) == SQLITE_OK) {
        for (NSNumber *identifier in identifiers) {
            sqlite3_bind_int64(statement, 1, identifier.longLongValue);
            sqlite3_step(statement);
            sqlite3_reset(statement);
            sqlite3_clear_bindings(statement);
        }
    }
    sqlite3_finalize(statement);
    sqlite3_exec(self.database, "COMMIT", NULL, NULL, NULL);
    [self syncHistoryBackup];
}

- (void)deleteVisitsForURLString:(NSString *)URLString {
    if (self.database == NULL || URLString.length == 0) return;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "DELETE FROM visits WHERE url=?", -1, &statement, NULL) != SQLITE_OK) return;
    sqlite3_bind_text(statement, 1, URLString.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_step(statement);
    sqlite3_finalize(statement);
    [self syncHistoryBackup];
}

- (void)deleteAllVisits {
    if (self.database == NULL) return;
    if (sqlite3_exec(self.database, "DELETE FROM visits", NULL, NULL, NULL) != SQLITE_OK) {
        NSLog(@"[History] Cannot clear visits: %s", sqlite3_errmsg(self.database));
        return;
    }
    [self syncHistoryBackup];
}

- (NSArray<NSArray<NSString *> *> *)favorites {
    if (self.database == NULL) return @[];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "SELECT url,title FROM favorites ORDER BY position", -1, &statement, NULL) != SQLITE_OK) return @[];
    NSMutableArray *items = [NSMutableArray array];
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const char *url = (const char *)sqlite3_column_text(statement, 0);
        const char *title = (const char *)sqlite3_column_text(statement, 1);
        [items addObject:@[url ? [NSString stringWithUTF8String:url] : @"",
                           title ? [NSString stringWithUTF8String:title] : @""]];
    }
    sqlite3_finalize(statement);
    return items;
}

- (void)saveFavorites:(NSArray<NSArray<NSString *> *> *)favorites {
    if (self.database == NULL) return;
    if (sqlite3_exec(self.database, "BEGIN TRANSACTION", NULL, NULL, NULL) != SQLITE_OK) return;
    BOOL success = sqlite3_exec(self.database, "DELETE FROM favorites", NULL, NULL, NULL) == SQLITE_OK;
    sqlite3_stmt *statement = NULL;
    if (success) success = sqlite3_prepare_v2(self.database,
        "INSERT INTO favorites (position,url,title) VALUES (?,?,?)", -1, &statement, NULL) == SQLITE_OK;
    NSUInteger position = 0;
    for (id raw in favorites) {
        if (!success) break;
        if (![raw isKindOfClass:NSArray.class]) continue;
        NSArray *entry = raw;
        NSString *url = entry.count > 0 && [entry[0] isKindOfClass:NSString.class] ? entry[0] : @"";
        NSString *title = entry.count > 1 && [entry[1] isKindOfClass:NSString.class] ? entry[1] : @"";
        if (url.length == 0) continue;
        sqlite3_bind_int64(statement, 1, (sqlite3_int64)position++);
        sqlite3_bind_text(statement, 2, url.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, title.UTF8String, -1, SQLITE_TRANSIENT);
        success = sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_reset(statement);
        sqlite3_clear_bindings(statement);
    }
    sqlite3_finalize(statement);
    if (sqlite3_exec(self.database, success ? "COMMIT" : "ROLLBACK", NULL, NULL, NULL) == SQLITE_OK && success)
        [[NSUserDefaults standardUserDefaults] setObject:[self favorites] forKey:@"FAVORITES"];
}

@end
