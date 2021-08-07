//
//  TwilioVoiceReactNative.m
//  TwilioVoiceReactNative
//
//  Copyright © 2021 Twilio, Inc. All rights reserved.
//

#import "TwilioVoicePushRegistry.h"
#import "TwilioVoiceReactNative.h"
#import "TwilioVoiceReactNativeConstants.h"

NSString * const kTwilioVoiceReactNativeEventScopeVoice = @"Voice";
NSString * const kTwilioVoiceReactNativeEventScopeCall = @"Call";

NSString * const kTwilioVoiceReactNativeEventKeyType = @"type";
NSString * const kTwilioVoiceReactNativeEventKeyError = @"error";
NSString * const kTwilioVoiceReactNativeEventKeyCall = @"call";
NSString * const kTwilioVoiceReactNativeEventKeyCallInvite = @"callInvite";
NSString * const kTwilioVoiceReactNativeEventKeyCancelledCallInvite = @"cancelledCallInvite";

NSString * const kTwilioVoiceReactNativeEventCallInviteReceived = @"callInvite";
NSString * const kTwilioVoiceReactNativeEventCallInviteCancelled = @"cancelledCallInvite";
NSString * const kTwilioVoiceReactNativeEventCallInviteAccepted = @"callInviteAccepted";
NSString * const kTwilioVoiceReactNativeEventCallInviteRejected = @"callInviteRejected";

NSString * const kTwilioVoiceCallInfoUuid = @"uuid";
NSString * const kTwilioVoiceCallInfoFrom = @"from";
NSString * const kTwilioVoiceCallInfoIsMuted = @"isMuted";
NSString * const kTwilioVoiceCallInfoInOnHold = @"isOnHold";
NSString * const kTwilioVoiceCallInfoSid = @"sid";
NSString * const kTwilioVoiceCallInfoTo = @"to";

NSString * const kTwilioVoiceCallInviteInfoUuid = @"uuid";
NSString * const kTwilioVoiceCallInviteInfoCallSid = @"callSid";
NSString * const kTwilioVoiceCallInviteInfoFrom = @"from";
NSString * const kTwilioVoiceCallInviteInfoTo = @"to";

static TVODefaultAudioDevice *sAudioDevice;

@import TwilioVoice;

@interface TwilioVoiceReactNative ()

@property(nonatomic, strong) NSData *deviceTokenData;

@end


@implementation TwilioVoiceReactNative

- (instancetype)init {
    if (self = [super init]) {
        _callMap = [NSMutableDictionary dictionary];
        _callInviteMap = [NSMutableDictionary dictionary];
        _cancelledCallInviteMap = [NSMutableDictionary dictionary];
        
        sAudioDevice = [TVODefaultAudioDevice audioDevice];
        TwilioVoiceSDK.audioDevice = sAudioDevice;
        
        TwilioVoiceSDK.logLevel = TVOLogLevelTrace;
        
        [self subscribeToNotifications];
        [self initializeCallKit];
    }

    return self;
}

- (void)subscribeToNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePushRegistryNotification:)
                                                 name:kTwilioVoicePushRegistryNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handlePushRegistryNotification:(NSNotification *)notification {
    NSMutableDictionary *eventBody = [notification.userInfo mutableCopy];
    if ([eventBody[kTwilioVoiceReactNativeEventKeyType] isEqualToString:kTwilioVoicePushRegistryNotificationDeviceTokenUpdated]) {
        NSAssert(eventBody[kTwilioVoicePushRegistryNotificationDeviceTokenKey] != nil, @"Missing device token. Please check the body of NSNotification.userInfo,");
        self.deviceTokenData = eventBody[kTwilioVoicePushRegistryNotificationDeviceTokenKey];
        
        // Skip the event emitting since 1, the listener has not registered and 2, the app does not need to know about this
        return;
    } else if ([eventBody[kTwilioVoiceReactNativeEventKeyType] isEqualToString:kTwilioVoiceReactNativeEventCallInviteReceived]) {
        TVOCallInvite *callInvite = eventBody[kTwilioVoicePushRegistryNotificationCallInviteKey];
        NSAssert(callInvite != nil, @"Invalid call invite");
        [self reportNewIncomingCall:callInvite];
        
        eventBody[kTwilioVoiceReactNativeEventKeyCallInvite] = [self callInviteInfo:callInvite];
    } else if ([eventBody[kTwilioVoiceReactNativeEventKeyType] isEqualToString:kTwilioVoiceReactNativeEventCallInviteCancelled]) {
        TVOCancelledCallInvite *cancelledCallInvite = eventBody[kTwilioVoicePushRegistryNotificationCancelledCallInviteKey];
        NSAssert(cancelledCallInvite != nil, @"Invalid cancelled call invite");
        self.cancelledCallInvite = cancelledCallInvite;
        self.cancelledCallInviteMap[self.callInvite.uuid.UUIDString] = cancelledCallInvite;
        [self endCallWithUuid:self.callInvite.uuid];
        
        eventBody[kTwilioVoiceReactNativeEventKeyCancelledCallInvite] = [self cancelledCallInviteInfo:cancelledCallInvite];
    }
    
    [self sendEventWithName:kTwilioVoiceReactNativeEventScopeVoice body:eventBody];
}

+ (TVODefaultAudioDevice *)audioDevice {
    return sAudioDevice;
}

// TODO: Move to separate utility file someday
- (NSDictionary *)callInfo:(TVOCall *)call {
    return @{kTwilioVoiceCallInfoUuid: call.uuid? call.uuid.UUIDString : @"",
             kTwilioVoiceCallInfoFrom: call.from? call.from : @"",
             kTwilioVoiceCallInfoIsMuted: @(call.isMuted),
             kTwilioVoiceCallInfoInOnHold: @(call.isOnHold),
             kTwilioVoiceCallInfoSid: call.sid,
             kTwilioVoiceCallInfoTo: call.to? call.to : @""};
}

- (NSDictionary *)callInviteInfo:(TVOCallInvite *)callInvite {
    return @{kTwilioVoiceCallInviteInfoUuid: callInvite.uuid.UUIDString,
             kTwilioVoiceCallInviteInfoCallSid: callInvite.callSid,
             kTwilioVoiceCallInviteInfoFrom: callInvite.from,
             kTwilioVoiceCallInviteInfoTo: callInvite.to};
}

- (NSDictionary *)cancelledCallInviteInfo:(TVOCancelledCallInvite *)cancelledCallInvite {
    return @{kTwilioVoiceCallInviteInfoCallSid: cancelledCallInvite.callSid,
             kTwilioVoiceCallInviteInfoFrom: cancelledCallInvite.from,
             kTwilioVoiceCallInviteInfoTo: cancelledCallInvite.to};
}

RCT_EXPORT_MODULE();

#pragma mark - React Native

- (NSArray<NSString *> *)supportedEvents
{
  return @[kTwilioVoiceReactNativeEventScopeVoice, kTwilioVoiceReactNativeEventScopeCall];
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

#pragma mark - Bingings (Voice methods)

RCT_EXPORT_METHOD(voice_getVersion:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve(TwilioVoiceSDK.sdkVersion);
}

RCT_EXPORT_METHOD(voice_register:(NSString *)accessToken
                  deviceToken:(NSString *)deviceToken
                  channelType:(NSString *)channelType
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [TwilioVoiceSDK registerWithAccessToken:accessToken
                                deviceToken:self.deviceTokenData
                                 completion:^(NSError *error) {
        if (error) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to register: %@", error];
            NSLog(@"%@", errorMessage);
            reject(@"Voice error", errorMessage, nil);
        } else {
            resolve(nil);
        }
    }];
}

RCT_EXPORT_METHOD(voice_unregister:(NSString *)accessToken
                  deviceToken:(NSString *)deviceToken
                  channelType:(NSString *)channelType
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [TwilioVoiceSDK unregisterWithAccessToken:accessToken
                                  deviceToken:self.deviceTokenData
                                   completion:^(NSError *error) {
        if (error) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to unregister: %@", error];
            NSLog(@"%@", errorMessage);
            reject(@"Voice error", errorMessage, nil);
        } else {
            resolve(nil);
        }
    }];
}

RCT_EXPORT_METHOD(voice_connect:(NSString *)accessToken
                  params:(NSDictionary *)params
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self makeCallWithAccessToken:accessToken params:params];
    self.callPromiseResolver = resolve;
}

RCT_EXPORT_METHOD(voice_getCalls:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSMutableArray *callInfoArray = [NSMutableArray array];
    for (NSString *uuid in [self.callMap allKeys]) {
        TVOCall *call = self.callMap[uuid];
        [callInfoArray addObject:[self callInfo:call]];
    }
    resolve(callInfoArray);
}

RCT_EXPORT_METHOD(voice_getCallInvites:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSMutableArray *callInviteInfoArray = [NSMutableArray array];
    for (NSString *uuid in [self.callInviteMap allKeys]) {
        TVOCallInvite *callInvite = self.callInviteMap[uuid];
        [callInviteInfoArray addObject:[self callInviteInfo:callInvite]];
    }
    resolve(callInviteInfoArray);
}

#pragma mark - Bingings (Call)

RCT_EXPORT_METHOD(call_disconnect:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.callMap[uuid]) {
        [self endCallWithUuid:[[NSUUID alloc] initWithUUIDString:uuid]];
        resolve(nil);
    } else {
        reject(@"Voice error", [NSString stringWithFormat:@"Call with %@ not found", uuid], nil);
    }
}

RCT_EXPORT_METHOD(call_getState:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    NSString *state = @"";
    if (call) {
        state = [self stringOfState:call.state];
    }
    
    resolve(state);
}

RCT_EXPORT_METHOD(call_getSid:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    NSString *callSid = (call && call.state != TVOCallStateConnecting)? call.sid : @"";
    
    resolve(callSid);
}

RCT_EXPORT_METHOD(call_getFrom:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    NSString *from = (call && [call.from length] > 0)? call.from : @"";
    
    resolve(from);
}

RCT_EXPORT_METHOD(call_getTo:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    NSString *to = (call && [call.to length] > 0)? call.to : @"";
    
    resolve(to);
}

RCT_EXPORT_METHOD(call_hold:(NSString *)uuid
                  onHold:(BOOL)onHold
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call setOnHold:onHold];
        resolve(nil);
    } else {
        reject(@"Voice error", [NSString stringWithFormat:@"Call with %@ not found", uuid], nil);
    }
}

RCT_EXPORT_METHOD(call_isOnHold:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        resolve(@(call.isOnHold));
    } else {
        resolve(@(NO));
    }
}

RCT_EXPORT_METHOD(call_mute:(NSString *)uuid
                  muted:(BOOL)muted
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call setMuted:muted];
        resolve(nil);
    } else {
        reject(@"Voice error", [NSString stringWithFormat:@"Call with %@ not found", uuid], nil);
    }
}

RCT_EXPORT_METHOD(call_isMuted:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        resolve(@(call.isMuted));
    } else {
        resolve(@(NO));
    }
}

RCT_EXPORT_METHOD(call_sendDigits:(NSString *)uuid
                  digits:(NSString *)digits
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call sendDigits:digits];
        resolve(nil);
    } else {
        reject(@"Voice error", [NSString stringWithFormat:@"Call with %@ not found", uuid], nil);
    }
}

#pragma mark - Bingings (Call Invite)

RCT_EXPORT_METHOD(callInvite_accept:(NSString *)callInviteUuid
                  acceptOptions:(NSDictionary *)acceptOptions
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self answerCallInvite:[[NSUUID alloc] initWithUUIDString:callInviteUuid]
                completion:^(BOOL success, NSError *error) {
        if (success) {
            resolve([self callInfo:self.activeCall]);
        } else {
            reject(@"Voice error", @"Failed to answer the call invite", error);
        }
    }];
}

RCT_EXPORT_METHOD(callInvite_reject:(NSString *)callInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self endCallWithUuid:[[NSUUID alloc] initWithUUIDString:callInviteUuiid]];
    resolve(nil);
}

RCT_EXPORT_METHOD(callInvite_isValid:(NSString *)callInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve(@(YES));
}

RCT_EXPORT_METHOD(callInvite_getCallSid:(NSString *)callInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.callInvite) {
        resolve(self.callInvite.callSid);
    } else {
        reject(@"Voice error", @"No matching call invite", nil);
    }
}

RCT_EXPORT_METHOD(callInvite_getFrom:(NSString *)callInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.callInvite) {
        resolve(self.callInvite.from);
    } else {
        reject(@"Voice error", @"No matching call invite", nil);
    }
}

RCT_EXPORT_METHOD(callInvite_getTo:(NSString *)callInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.callInvite) {
        resolve(self.callInvite.to);
    } else {
        reject(@"Voice error", @"No matching call invite", nil);
    }
}

RCT_EXPORT_METHOD(cancelledCallInvite_getCallSid:(NSString *)cancelledCallInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.cancelledCallInvite) {
        resolve(self.cancelledCallInvite.callSid);
    } else {
        reject(@"Voice error", @"No matching cancelled call invite", nil);
    }
}

RCT_EXPORT_METHOD(cancelledCallInvite_getFrom:(NSString *)cancelledCallInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.cancelledCallInvite) {
        resolve(self.cancelledCallInvite.from);
    } else {
        reject(@"Voice error", @"No matching cancelled call invite", nil);
    }
}

RCT_EXPORT_METHOD(cancelledCallInvite_getTo:(NSString *)cancelledCallInviteUuiid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.cancelledCallInvite) {
        resolve(self.cancelledCallInvite.to);
    } else {
        reject(@"Voice error", @"No matching cancelled call invite", nil);
    }
}

#pragma mark - utility

RCT_EXPORT_METHOD(util_generateId:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve([NSUUID UUID].UUIDString);
}

- (NSString *)stringOfState:(TVOCallState)state {
    switch (state) {
        case TVOCallStateConnecting:
            return @"connecting";
        case TVOCallStateRinging:
            return @"ringing";
        case TVOCallStateConnected:
            return @"conencted";
        case TVOCallStateReconnecting:
            return @"reconnecting";
        case TVOCallStateDisconnected:
            return @"disconnected";
        default:
            return @"connecting";
    }
}

@end
