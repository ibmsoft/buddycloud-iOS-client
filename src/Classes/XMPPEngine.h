//
//  XMPPEngine.h
//  Buddycloud
//
//  Created by Ross Savage on 4/7/10.
//  Copyright 2010 buddycloud. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FollowingDataModel.h"

@class XMPPStream;
@class XMPPRoster;
@class XMPPPubsub;
@class XMPPJID;
@class XMPPIQ;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public XMPPEngine definition
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface XMPPEngine : FollowingDataModel {
	XMPPStream *xmppStream;
	XMPPRoster *xmppRoster;
	XMPPPubsub *xmppPubsub;
	
	NSString *password;
	
	bool isConnectionCold;
	bool isPubsubAddedToRoster;
	int lastItemIdReceived;
}

@property(nonatomic, retain) XMPPStream *xmppStream;
@property(nonatomic, retain) XMPPRoster *xmppRoster;
@property(nonatomic, retain) NSString *password;
@property(readonly) int lastItemIdReceived;

- (void)connect;
- (void)disconnect;

@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private XMPPEngine definition
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface XMPPEngine (PrivateAPI)

- (void)sendPresenceToPubsubWithLastItemId:(int)itemId;

- (void)sendPingResultTo:(XMPPJID *)recipient withIQId:(NSString *)iqId;
- (void)sendVersionResultTo:(XMPPJID *)recipient withIQId:(NSString *)iqId;
- (void)sendFeatureDiscovery:(XMPPIQ *)iq;

@end

