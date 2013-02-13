//
//  SPTask.m
//  SPAsync
//
//  Created by Joachim Bengtsson on 2012-12-26.
//
//

#import <SPAsync/SPTask.h>

@interface SPTask ()
{
    NSMutableArray *_callbacks;
    NSMutableArray *_errbacks;
    BOOL _isCompleted;
    id _completedValue;
    NSError *_completedError;
}

@end

@implementation SPTask
- (id)init
{
    if(!(self = [super init]))
        return nil;
    _callbacks = [NSMutableArray new];
    _errbacks = [NSMutableArray new];
    return self;
}

- (instancetype)addCallback:(SPTaskCallback)callback on:(dispatch_queue_t)queue
{
    @synchronized(_callbacks) {
        if(_isCompleted) {
            if(!_completedError) {
                dispatch_async(queue, ^{
                    callback(_completedValue);
                });
            }
        } else {
            [_callbacks addObject:[[SPCallbackHolder alloc] initWithCallback:callback onQueue:queue]];
        }
    }
    return self;
}

- (instancetype)addErrback:(SPTaskErrback)errback on:(dispatch_queue_t)queue
{
    @synchronized(_errbacks) {
        if(_isCompleted) {
            if(_completedError) {
                dispatch_async(queue, ^{
                    errback(_completedError);
                });
            }
        } else {
            [_errbacks addObject:[[SPCallbackHolder alloc] initWithCallback:errback onQueue:queue]];
        }
    }
    return self;
}

- (instancetype)then:(SPTaskThenCallback)worker on:(dispatch_queue_t)queue
{
    SPTask *then = [SPTask new];
    
    [self addCallback:^(id value) {
        id result = worker(value);
        [then completeWithValue:result];
    } on:queue];
    [self addErrback:^(NSError *error) {
        [then failWithError:error];
    } on:queue];
    
    return then;
}

- (instancetype)chain:(SPTaskChainCallback)chainer on:(dispatch_queue_t)queue
{
    SPTask *chain = [SPTask new];
    
    [self addCallback:^(id value) {
        SPTask *workToBeProvided = chainer(value);
        [workToBeProvided addCallback:^(id value) {
            [chain completeWithValue:value];
        } on:queue];
        [workToBeProvided addErrback:^(NSError *error) {
            [chain failWithError:error];
        } on:queue];
    } on:queue];
    [self addErrback:^(NSError *error) {
        [chain failWithError:error];
    } on:queue];
    
    return chain;
}

- (instancetype)chain
{
    return [self chain:^SPTask *(id value) {
        return value;
    } on:dispatch_get_global_queue(0, 0)];
}

+ (instancetype)awaitAll:(NSArray*)tasks
{
    SPTaskCompletionSource *source = [SPTaskCompletionSource new];
    
    NSMutableArray *values = [NSMutableArray new];
    NSMutableSet *remainingTasks = [NSMutableSet setWithArray:tasks];
    
    int i = 0;
    for(SPTask *task in tasks) {
        __weak SPTask *weakTask = task;
        
        [values addObject:[NSNull null]];
        [[task addCallback:^(id value) {
            
            if(value)
                [values replaceObjectAtIndex:i withObject:value];
            
            [remainingTasks removeObject:weakTask];
            if([remainingTasks count] == 0)
                [source completeWithValue:values];
        } on:dispatch_get_main_queue()] addErrback:^(NSError *error) {
            [values removeAllObjects];
            [remainingTasks removeAllObjects];
            [source failWithError:error];
        } on:dispatch_get_main_queue()];
        
        i++;
    }
    return source.task;
}

- (void)completeWithValue:(id)value
{
    @synchronized(_callbacks) {
        NSAssert(!_isCompleted, @"Can't complete a task twice");
        if(_isCompleted)
            return;
        
        _isCompleted = YES;
        _completedValue = value;
        for(SPCallbackHolder *holder in _callbacks) {
            dispatch_async(holder.callbackQueue, ^{
                holder.callback(value);
            });
        }
        [_callbacks removeAllObjects];
        [_errbacks removeAllObjects];
    }
}

- (void)failWithError:(NSError*)error
{
    @synchronized(_errbacks) {
        _isCompleted = YES;
        _completedError = error;
        for(SPCallbackHolder *holder in _errbacks) {
            dispatch_async(holder.callbackQueue, ^{
                holder.callback(error);
            });
        }
        [_callbacks removeAllObjects];
        [_errbacks removeAllObjects];
    }
}
@end

@implementation SPTaskCompletionSource
{
    SPTask *_task;
}

- (SPTask*)task
{
    if(!_task)
        _task = [SPTask new];
    return _task;
}

- (void)completeWithValue:(id)value
{
    [self.task completeWithValue:value];
}

- (void)failWithError:(NSError*)error
{
    [self.task failWithError:error];
}
@end

@implementation SPCallbackHolder
- (id)initWithCallback:(SPTaskCallback)callback onQueue:(dispatch_queue_t)callbackQueue
{
    if(!(self = [super init]))
        return nil;
    
    self.callback = callback;
    self.callbackQueue = callbackQueue;
    
    return self;
}

- (void)dealloc
{
    self.callbackQueue = nil;
}

- (void)setCallbackQueue:(dispatch_queue_t)callbackQueue
{
    if(callbackQueue)
        dispatch_retain(callbackQueue);
    if(_callbackQueue)
        dispatch_release(_callbackQueue);
    _callbackQueue = callbackQueue;
}
@end