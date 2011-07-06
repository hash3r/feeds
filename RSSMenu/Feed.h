
extern NSString *kFeedUpdatedNotification;

@interface Feed : NSObject {
    NSURL *URL;
    NSArray *items; // of FeedItem
    SMWebRequest *request;
}
@property (nonatomic, retain) NSURL *URL;
@property (nonatomic, copy) NSArray *items;

- (void)refresh;

@end

@interface FeedItem : NSObject {
    NSString *title, *author, *content, *strippedContent;
    NSURL *link, *comments;
    NSDate *published, *updated;
    BOOL notified, viewed;
}
@property (nonatomic, copy) NSString *title, *author, *content, *strippedContent;
@property (nonatomic, retain) NSURL *link, *comments;
@property (nonatomic, retain) NSDate *published, *updated;
@property (nonatomic, assign) BOOL notified, viewed;

// creates a new FeedItem by parsing an XML element
+ (FeedItem *)itemWithRSSItemElement:(SMXMLElement *)element formatter:(NSDateFormatter *)formatter;
+ (FeedItem *)itemWithATOMEntryElement:(SMXMLElement *)element formatter:(NSDateFormatter *)formatter;

- (NSComparisonResult)compareItemByPublishedDate:(FeedItem *)item;

@end