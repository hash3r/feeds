#import "Account.h"

NSString *kAccountsChangedNotification = @"AccountsChangedNotification";

static NSMutableArray *allAccounts = nil;

@interface Account ()
+ (Account *)accountWithDictionary:(NSDictionary *)dict;
@end

@implementation Account
@synthesize delegate, name, domain, username, refreshInterval, request, tokenRequest, feeds, lastRefresh, lastTokenRefresh;

static NSMutableArray *registeredClasses = nil;

+ (NSArray *)registeredClasses { 
    NSArray *descriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"friendlyAccountName" ascending:YES]];
    return [registeredClasses sortedArrayUsingDescriptors:descriptors];
}
+ (void)registerClass:(Class)cls {
    if (!registeredClasses) registeredClasses = [NSMutableArray new];
    [registeredClasses addObject:cls];
}

// threadsafe
+ (NSData *)extraDataWithContentsOfURL:(NSURL *)URL {
    return [self extraDataWithContentsOfURLRequest:[NSMutableURLRequest requestWithURL:URL]];
}

+ (NSData *)extraDataWithContentsOfURLRequest:(NSMutableURLRequest *)request {
    static NSMutableDictionary *cache = nil;
    
    @synchronized (self) {
        if (!cache) cache = [NSMutableDictionary new];
        NSData *result = [cache objectForKey:request.URL];
        if (result) return result;
    }

    request.timeoutInterval = 5; // we could have a lot of these requests to make, don't let it take too long
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    if (error)
        DDLogError(@"Error while fetching extra data at (%@): %@", request.URL, error);
    else {
        DDLogInfo(@"Fetched extra for %@", NSStringFromClass(self));
        @synchronized (self) {
            [cache setObject:data forKey:request.URL];
        }
    }
    
    return data;
}

+ (NSString *)friendlyAccountName {
    return [NSStringFromClass(self) stringByReplacingOccurrencesOfString:@"Account" withString:@""];
}

+ (NSString *)shortAccountName {
    return [self friendlyAccountName];
}

+ (BOOL)requiresAuth { return NO; }
+ (BOOL)requiresDomain { return NO; }
+ (BOOL)requiresUsername { return NO; }
+ (BOOL)requiresPassword { return NO; }
+ (NSString *)usernameLabel { return @"User name:"; }
+ (NSString *)passwordLabel { return @"Password:"; }
+ (NSString *)domainLabel { return @"Domain:"; }
+ (NSString *)domainPrefix { return @"http://"; }
+ (NSString *)domainSuffix { return @""; }
+ (NSString *)domainPlaceholder { return @""; }
+ (NSTimeInterval)defaultRefreshInterval { return 10*60; } // 10 minutes

- (NSArray *)enabledFeeds {
    NSMutableArray *enabledFeeds = [NSMutableArray array];
    for (Feed *feed in feeds)
        if (!feed.disabled)
            [enabledFeeds addObject:feed];
    return enabledFeeds;
}

#pragma mark Account Persistence

+ (NSArray *)allAccounts {    
    if (!allAccounts) {
        // initial load
        NSArray *accountDicts = [[NSUserDefaults standardUserDefaults] objectForKey:@"accounts"];
        NSArray *accounts = [accountDicts selectUsingBlock:^id(NSDictionary *dict) { return [Account accountWithDictionary:dict]; }];
        allAccounts = [accounts mutableCopy]; // retained
    }
    
    // no saved data?
    if (!allAccounts)
        allAccounts = [NSMutableArray new]; // retained
    
    return allAccounts;
}

+ (void)saveAccounts { [self saveAccountsAndNotify:YES]; }

+ (void)saveAccountsAndNotify:(BOOL)notify {
#ifndef EXPIRATION_DATE
    NSArray *accounts = [allAccounts valueForKey:@"dictionaryRepresentation"];
    [[NSUserDefaults standardUserDefaults] setObject:accounts forKey:@"accounts"];
    [[NSUserDefaults standardUserDefaults] synchronize];
#endif
    if (notify)
        [[NSNotificationCenter defaultCenter] postNotificationName:kAccountsChangedNotification object:nil];
}

+ (void)addAccount:(Account *)account {
    [allAccounts addObject:account];
    [self saveAccounts];
}

+ (void)removeAccount:(Account *)account {
    [allAccounts removeObject:account];
    [self saveAccounts];
}

#pragma mark Account Implementation

+ (Account *)accountWithDictionary:(NSDictionary *)dict {
    NSString *type = [dict objectForKey:@"type"];
    Class class = NSClassFromString([type stringByAppendingString:@"Account"]);
    return [[[class alloc] initWithDictionary:dict] autorelease];
}

- (id)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    self.name = [dict objectForKey:@"name"];
    self.domain = [dict objectForKey:@"domain"];
    self.username = [dict objectForKey:@"username"];
    self.refreshInterval = [[dict objectForKey:@"refreshInterval"] integerValue];
    self.feeds = [[dict objectForKey:@"feeds"] selectUsingBlock:^id(NSDictionary *dict) { return [Feed feedWithDictionary:dict account:self]; }];
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:self.type forKey:@"type"];
    if (name) [dict setObject:name forKey:@"name"];
    if (domain) [dict setObject:domain forKey:@"domain"];
    if (username) [dict setObject:username forKey:@"username"];
    if (refreshInterval) [dict setObject:@(refreshInterval) forKey:@"refreshInterval"];
    if (feeds) [dict setObject:[feeds valueForKey:@"dictionaryRepresentation"] forKey:@"feeds"];
    return dict;
}

- (void)dealloc {
    self.delegate = nil;
    self.name = self.domain = self.username = nil;
    self.request = self.tokenRequest = nil;
    self.feeds = nil;
    self.lastRefresh = self.lastTokenRefresh = nil;
    [super dealloc];
}

- (void)setRequest:(SMWebRequest *)request_ {
    [request removeTarget:self];
    [request release], request = [request_ retain];
}

- (void)setTokenRequest:(SMWebRequest *)tokenRequest_ {
    [tokenRequest removeTarget:self];
    [tokenRequest release], tokenRequest = [tokenRequest_ retain];
}

- (NSString *)type {
    return [NSStringFromClass([self class]) stringByReplacingOccurrencesOfString:@"Account" withString:@""];
}

- (NSImage *)menuIconImage {
    return [NSImage imageNamed:[self.type stringByAppendingString:@".png"]] ?: [NSImage imageNamed:@"Default.png"];
}

- (NSImage *)accountIconImage {
    return [NSImage imageNamed:[self.type stringByAppendingString:@"Account.png"]];
}

- (NSData *)notifyIconData {
    return [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForImageResource:[self.type stringByAppendingString:@"Notify.png"]]];
}

- (const char *)serviceName {
    return [[self description] cStringUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)description {
    return [domain length] ? [self.type stringByAppendingFormat:@" (%@)",self.friendlyDomain] : self.type;
}

- (NSString *)friendlyDomain {
    if ([self.domain beginsWithString:@"http://"] || [self.domain beginsWithString:@"https://"]) {
        NSURL *URL = [NSURL URLWithString:self.domain];
        return URL.host;
    }
    else return self.domain;
}

- (NSTimeInterval)refreshIntervalOrDefault {
    return refreshInterval ?: [[self class] defaultRefreshInterval];
}

- (void)validateWithPassword:(NSString *)password {
    // no default implementation
}

- (void)cancelValidation {
    self.request = nil;
}

- (void)beginAuth {
}

- (void)authWasFinishedWithURL:(NSURL *)url {
    // no default implementation
}

- (NSString *)findPassword:(SecKeychainItemRef *)itemRef {
    const char *serviceName = [self serviceName];
    void *passwordData;
    UInt32 passwordLength;
    
    OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                     (UInt32)strlen(serviceName), serviceName,
                                                     (UInt32)[username lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [username UTF8String],
                                                     &passwordLength, &passwordData,
                                                     itemRef);
    
    if (status != noErr) {
        if (status != errSecItemNotFound)
            DDLogWarn(@"Find password failed. (OSStatus: %d)\n", (int)status);
        return nil;
    }
    
    NSString *password = [[[NSString alloc] initWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding] autorelease];
    SecKeychainItemFreeContent(NULL, passwordData);
    return password;
}

- (NSString *)findPassword {
    return [self findPassword:NULL];
}

- (void)savePassword:(NSString *)password {
    
    if ([password length] == 0) {
        [self deletePassword];
        return;
    }

    SecKeychainItemRef itemRef;
    
    if ([self findPassword:&itemRef]) {
        
        OSStatus status = SecKeychainItemModifyAttributesAndData(itemRef,NULL,
                                                                 (UInt32)[password lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                                                 [password UTF8String]);
        
        if (status != noErr)
            DDLogError(@"Update password failed. (OSStatus: %d)\n", (int)status);
    }
    else {
        const char *serviceName = [self serviceName];
        
        OSStatus status = SecKeychainAddGenericPassword (NULL,
                                                         (UInt32)strlen(serviceName), serviceName,
                                                         (UInt32)[username lengthOfBytesUsingEncoding: NSUTF8StringEncoding],
                                                         [username UTF8String],
                                                         (UInt32)[password lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                                         [password UTF8String],
                                                         NULL);
        
        if (status != noErr)
            DDLogError(@"Add password failed. (OSStatus: %d)\n", (int)status);
    }
}

- (void)deletePassword {
    SecKeychainItemRef itemRef;
    if ([self findPassword:&itemRef])
        SecKeychainItemDelete(itemRef);
}

#pragma mark NSTableViewDataSource, exposes Feeds

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return feeds.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    Feed *feed = [feeds objectAtIndex:row];
    if ([tableColumn.identifier isEqual:@"showColumn"])
        return [NSNumber numberWithBool:!feed.disabled];
    else if ([tableColumn.identifier isEqual:@"feedColumn"])
        return feed.title;
    else
        return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    Feed *feed = [feeds objectAtIndex:row];
    if ([tableColumn.identifier isEqual:@"showColumn"]) {
        feed.disabled = ![object boolValue];
        self.lastRefresh = nil; // force refresh on this feed
        [Account saveAccounts];
    }
}

#pragma mark Feed Refreshing

- (void)refreshEnabledFeeds {
    DDLogInfo(@"Refreshing feeds for account %@", self);
    self.lastRefresh = [NSDate date];
    [self refreshFeeds:self.enabledFeeds];
}

- (void)refreshFeeds:(NSArray *)feedsToRefresh {
    [feedsToRefresh makeObjectsPerformSelector:@selector(refresh)];
}

@end
