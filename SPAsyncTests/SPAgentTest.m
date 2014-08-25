//
//  SPAgentTest.m
//  SPAsync
//
//  Created by Joachim Bengtsson on 2012-12-26.
//
//

#import "SPAgentTest.h"
#import "SPTaskTest.h"
#import <SPAsync/SPAgent.h>
#import <SPAsync/SPTask.h>

@interface TestAgent : NSObject <SPAgent>
- (id)leet;
@end

@implementation SPAgentTest

- (void)testAgentAsyncTask
{
    TestAgent *agent = [TestAgent new];
    
    SPTask *leetTask = [[agent sp_agentAsync] leet];
    __block BOOL gotLeet = NO;
    [leetTask addCallback:^(id value) {
        XCTAssertEqualObjects(value, @(1337), @"Got an unexpected value");
        gotLeet = YES;
    } on:dispatch_get_main_queue()];
    
    // Spin the runloop
    SPTestSpinRunloopWithCondition(gotLeet, 1.0);
    XCTAssertEqual(gotLeet, YES, @"Expected to have gotten leet by now");
}

@end

@implementation TestAgent
{
    dispatch_queue_t _workQueue;
}
- (id)init
{
    if(!(self = [super init]))
        return nil;
    
    _workQueue = dispatch_queue_create("SPAsync.testworkqueue", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

- (void)dealloc
{
    dispatch_release(_workQueue);
}

- (dispatch_queue_t)workQueue
{
    return _workQueue;
}

- (id)leet
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    NSAssert(_workQueue == dispatch_get_current_queue(), @"Expected getter to be called on work queue");
#pragma clang diagnostic pop

    return @(1337);
}
@end