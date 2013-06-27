//
//  QiniuSDKTests.m
//  QiniuSDKTests
//
//  Created by Hugh Lv on 12-11-14.
//  Copyright (c) 2012 Shanghai Qiniu Information Technologies Co., Ltd. All rights reserved.
//

#import "QiniuSDKTests.h"
#import "QiniuSimpleUploader.h"
#import "QiniuResumableUploader.h"
#import "QiniuAuthPolicy.h"
#import "QiniuConfig.h"
#import <zlib.h>

// FOR TEST ONLY!
//
// Note: AccessKey/SecretKey should not be included in client app.

// NOTE: Please replace with your own accessKey/secretKey.
// You can find your keys on https://dev.qiniutek.com/ ,
static NSString *AccessKey = @"<Please specify your access key>";
static NSString *SecretKey = @"<Please specify your secret key>";

// NOTE: You need to replace value of kBucketValue with the key of an existing bucket.
// You can create a new bucket on https://dev.qiniutek.com/ .
static NSString *BucketName = @"<Please specify your bucket name>";

#define kWaitTime 10 // seconds

@implementation QiniuSDKTests

- (void)setUp
{
    [super setUp];
    
    AccessKey = @"dbsrtUEWFt_HMlY59qw5KqaydbvML1zxtxsvioUX";
    SecretKey = @"EZUwWLGLfbq0y94SLteofzzqKc60Dxg5kc1Rv2ct";
    BucketName = @"shijy";
    
    _filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test1.png"];
    NSLog(@"Test file: %@", _filePath);
    
    // Download a file and save to local path.
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:_filePath])
    {
        NSURL *url = [NSURL URLWithString:@"http://qiniuphotos.qiniudn.com/gogopher.jpg"];
        NSData *data = [NSData dataWithContentsOfURL:url];
        
        [data writeToFile:_filePath atomically:TRUE];
    }
    
    // Prepare the uptoken
    
    QiniuAuthPolicy *policy = [[QiniuAuthPolicy new] autorelease];
    policy.expires = 3600;
    policy.scope = BucketName;
    
    _token = [policy makeToken:AccessKey secretKey:SecretKey];

    _done = false;
    _progressReceived = false;
}

- (void)tearDown
{
    // Tear-down code here.
    [super tearDown];
}

- (void)testAuthPolicyMarshal
{
    QiniuAuthPolicy *policy = [[QiniuAuthPolicy new] autorelease];
    policy.expires = 3600;
    policy.scope = @"bucket";
    
    NSString *policyJson = [policy makeToken:AccessKey secretKey:SecretKey];
    
    STAssertNotNil(policyJson, @"Marshal of QiniuAuthPolicy failed.");
    
    NSString *thisToken = [policy makeToken:AccessKey secretKey:SecretKey];
    
    STAssertNotNil(thisToken, @"Failed to create token based on QiniuAuthPolicy.");
}

- (void)uploadProgressUpdated:(NSString *)theFilePath percent:(float)percent
{
    _progressReceived = true;
    
    NSLog(@"Progress Updated: %@ - %f", theFilePath, percent);
}

// Upload completed successfully.
- (void)uploadSucceeded:(NSString *)theFilePath ret:(NSDictionary *)ret
{
    _done = true;
    
    NSLog(@"Upload Succeeded: %@ - Ret: %@", theFilePath, ret);
}

// Upload failed.
- (void)uploadFailed:(NSString *)theFilePath error:(NSError *)error
{
    _done = true;
    
    NSLog(@"Upload Failed: %@ - Reason: %@", theFilePath, error);
}

- (void) testSimpleUpload
{
    QiniuSimpleUploader *uploader = [QiniuSimpleUploader uploaderWithToken:_token];
    uploader.delegate = self;
    
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd-HH-mm-ss-zzz"];
    
    NSString *timeDesc = [formatter stringFromDate:[NSDate date]];
    
    [uploader uploadFile:_filePath key:[NSString stringWithFormat:@"test-%@.png", timeDesc] extraParams:nil];

    int waitLoop = 0;
    while (!_done && waitLoop < 10) // Wait for 10 seconds.
    {
        NSLog(@"Waiting for the result...");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        waitLoop++;
    }
    
    if (waitLoop == 10) {
        STFail(@"Failed to receive expected delegate messages.");
    }
}

- (void) testSimpleUploadWithReturnBodyAndUserParams
{
    QiniuAuthPolicy *policy = [[QiniuAuthPolicy new] autorelease];
    policy.expires = 3600;
    policy.scope = BucketName;
    policy.endUser = @"ios-sdk-test";
    policy.returnBody = @"{\"bucket\":$(bucket),\"key\":$(key),\"type\":$(mimeType),\"w\":$(imageInfo.width),\"xfoo\":$(x:foo),\"endUser\":$(endUser)}";
    _token = [policy makeToken:AccessKey secretKey:SecretKey];
    
    QiniuSimpleUploader *uploader = [QiniuSimpleUploader uploaderWithToken:_token];
    uploader.delegate = self;
    
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd-HH-mm-ss-zzz"];
    
    NSString *timeDesc = [formatter stringFromDate:[NSDate date]];
    
    NSDictionary *params = @{@"params": @{@"x:foo": @"fooName"}};
    [uploader uploadFile:_filePath key:[NSString stringWithFormat:@"test-%@.png", timeDesc] extraParams:params];
    
    int waitLoop = 0;
    while (!_done && waitLoop < 10) // Wait for 10 seconds.
    {
        NSLog(@"Waiting for the result...");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        waitLoop++;
    }
    
    if (waitLoop == 10) {
        STFail(@"Failed to receive expected delegate messages.");
    }
}

// Test case: CRC parameter. This case is to verify that a wrong CRC should cause a failure.
- (void) testSimpleUploadWithWrongCrc32
{
    QiniuSimpleUploader *uploader = [QiniuSimpleUploader uploaderWithToken:_token];
    uploader.delegate = self;
    
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd-HH-mm-ss-zzz"];
    
    NSString *timeDesc = [formatter stringFromDate:[NSDate date]];
    
    // An incorrect CRC string.
    NSDictionary *params = @{@"crc32": @"1234567"};
    
    [uploader uploadFile:_filePath key:[NSString stringWithFormat:@"test-%@.png", timeDesc] extraParams:params];
    
    int waitLoop = 0;
    while (!_done && waitLoop < 10) // Wait for 10 seconds.
    {
        NSLog(@"Waiting for the result...");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        waitLoop++;
    }
    
    if (waitLoop == 10) {
        STFail(@"Failed to receive expected delegate messages.");
    }
}

// Test case: CRC parameter. This case is to verify that a wrong CRC should cause a failure.
- (void) testSimpleUploadWithRightCrc32
{
    QiniuSimpleUploader *uploader = [QiniuSimpleUploader uploaderWithToken:_token];
    uploader.delegate = self;
    
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd-HH-mm-ss-zzz"];
    
    NSString *timeDesc = [formatter stringFromDate:[NSDate date]];
    
    NSData *buffer = [NSData dataWithContentsOfFile:_filePath];
    
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, [buffer bytes], [buffer length]);
    
    NSString *crcStr = [NSString stringWithFormat:@"%lu", crc];

    // A correct CRC string.
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:crcStr, kCrc32Key, nil];
    
    [uploader uploadFile:_filePath key:[NSString stringWithFormat:@"test-%@.png", timeDesc] extraParams:params];
    
    int waitLoop = 0;
    while (!_done && waitLoop < 10) // Wait for 10 seconds.
    {
        NSLog(@"Waiting for the result...");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        waitLoop++;
    }
    
    if (waitLoop == 10) {
        STFail(@"Failed to receive expected delegate messages.");
    }
}

//- (void) testResumableUpload
//{
//    QiniuResumableUploader *uploader = [[QiniuResumableUploader alloc] initWithToken:_token];
//    uploader.delegate = self;
//
//    NSDateFormatter *formatter = [[NSDateFormatter new] autorelease];
//    [formatter setDateFormat: @"yyyy-MM-dd-HH-mm-ss"];
//    
//    NSString *timeDesc = [formatter stringFromDate:[NSDate date]];
//    
//    NSDictionary *params = @{@"bucket": BucketName};
//    [uploader uploadFile:_filePath key:[NSString stringWithFormat:@"test-%@.png", timeDesc] extraParams:params];
//    
//    NSLog(@"File: http://<bucketbind>.qiniudn.com/test-%@.png", timeDesc);
//    
//    int waitLoop = 0;
//    while (!_done && waitLoop < kWaitTime) // Wait for 10 seconds.
//    {
//        waitLoop++;
//        NSLog(@"Waiting for the result... %d", waitLoop);
//        [NSThread sleepForTimeInterval:1];
//    }
//    
//    if (waitLoop == kWaitTime) {
//        //STFail(@"Failed to receive expected delegate messages.");
//    }
//    
//    [uploader release];
//}

@end