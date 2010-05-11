//
//  XMPPPubsub.m
//  Buddycloud
//
//  Created by Ross Savage on 4/20/10.
//  Copyright 2010 buddycloud. All rights reserved.
//

#import "XMPPPubsub.h"
#import "XMPPStream.h"
#import "XMPPJID.h"
#import "XMPPIQ.h"
#import "NSXMLElementAdditions.h"

#define RSM_MAX 50

typedef enum {
	kIqId_none = 0,
	kIqId_getOwnSubscriptions,
	kIqId_getNodeMetadata,
	kIqId_getNodeAffiliations,
	kIqId_getNodeItems,
	kIqId_setSubscription,
	kIqId_setAffiliation,
	kIqId_publishItem
} iqIdTypes;

@implementation XMPPPubsub
@synthesize serverName;


- (id)initWithStream:(XMPPStream *)aXmppStream toServer:(NSString *)aServerName
{
	if ((self = [super initWithStream:aXmppStream]))
	{
		collectionArray = [[NSMutableArray alloc] initWithCapacity: 0];
		
		serverName = [aServerName retain];
	}
	
	return self;
}

- (void)dealloc
{
	[collectionArray release];
	
	[serverName release];
	
	[super dealloc];
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
	BOOL result = NO;
	
	if ([[[iq attributeForName: @"from"] stringValue] isEqualToString: serverName]) {
		NSString *iqType = [[iq attributeForName: @"type"] stringValue];
		
		result = YES;
		
		if([iqType isEqualToString: @"result"]) {
			// Process IQ result
			NSArray *iqIdData = [[[iq attributeForName: @"id"] stringValue] componentsSeparatedByString: @":"];
			
			if ([iqIdData count] >= 2) {
				int iqIdType = [(NSString *) [iqIdData objectAtIndex: 0] intValue];
				
				if (iqIdType == kIqId_getOwnSubscriptions) {
					// Own subscriptions packet received
					[self handleOwnSubscriptionsResult: iq];
				}
				else if (iqIdType == kIqId_getNodeMetadata) {
					// Node metadata packet received
					[self handleNodeMetadataResult: iq];
				}
				else if (iqIdType == kIqId_getNodeAffiliations) {
					// Node affiliations packet received
					[self handleNodeAffiliationsResult: iq];
				}
			}
		}
		else if ([iqType isEqualToString: @"set"]) {
			// TODO: handle specific set data
			
			
			// Acknowledge IQ set
			NSXMLElement *iqElement = [NSXMLElement elementWithName: @"iq"];
			[iqElement addAttributeWithName: @"to" stringValue: [[iq attributeForName: @"from"] stringValue]];
			[iqElement addAttributeWithName: @"id" stringValue: [[iq attributeForName: @"id"] stringValue]];
			[iqElement addAttributeWithName: @"type" stringValue: @"result"];
			
			[xmppStream sendElement: iqElement];
		}
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Service Discovery & User Node Retrieval
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchOwnSubscriptions
{
	// Fetch the users own node subscriptions
	// http://xmpp.org/extensions/xep-0060.html#entity-subscriptions
	NSLog(@"--- XMPPPubsub fetchOwnSubscriptions");
	
	[collectionArray removeAllObjects];
	
	[self fetchOwnSubscriptionsAfter: nil];
}

- (void)fetchOwnSubscriptionsAfter:(NSString *)node
{
	// Fetch the users own node subscriptions
	// http://xmpp.org/extensions/xep-0060.html#entity-subscriptions
	NSLog(@"--- XMPPPubsub fetchOwnSubscriptionsAfter: %@", node);
	
	// Build & send subscriptions stanza
	NSXMLElement *pubsubElement = [NSXMLElement elementWithName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub"];
	[pubsubElement addChild: [NSXMLElement elementWithName: @"subscriptions"]];
	
	NSXMLElement *setElement = [NSXMLElement elementWithName: @"set" xmlns: @"http://jabber.org/protocol/rsm"];
	[setElement addChild: [NSXMLElement elementWithName: @"max" stringValue: [NSString stringWithFormat: @"%d", RSM_MAX]]];
	
	if ([node length] > 0) {
		[setElement addChild: [NSXMLElement elementWithName: @"after" stringValue: node]];
	}
	
	[pubsubElement addChild: setElement];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"get"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_getOwnSubscriptions, iqIdCounter++]];
	[iqStanza addChild: pubsubElement];
	
	[xmppStream sendElement: iqStanza];
}

- (void)handleOwnSubscriptionsResult:(XMPPIQ *)iq
{
	NSXMLElement *pubsubElement = [iq elementForName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub"];
	NSXMLElement *subscriptionsElement = [pubsubElement elementForName: @"subscriptions"];
	NSArray *subscriptions = [subscriptionsElement elementsForName: @"subscription"];
	
	[collectionArray addObjectsFromArray: subscriptions];
		
	// Process RSM data
	NSXMLElement *setElement = [subscriptionsElement elementForName: @"set" xmlns: @"http://jabber.org/protocol/rsm"];
	
	if ([collectionArray count] > 0 && setElement) {
		if ([collectionArray count] >= [[[setElement elementForName: @"count"] stringValue] intValue]) {
			// Notify delegate of result
			[multicastDelegate xmppPubsub: self didReceiveOwnSubscriptions: collectionArray];
		}
		else {
			// Fetch next packet of subscriptions
			[self fetchOwnSubscriptionsAfter: [[setElement elementForName: @"last"] stringValue]];
		}
	}
	else {
		// Notify delegate of result
		[multicastDelegate xmppPubsub: self didReceiveOwnSubscriptions: collectionArray];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Data Retrieval
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchMetadataForNode:(NSString *)node
{
	// Fetch the metadata of a node
	// http://xmpp.org/extensions/xep-0060.html#entity-metadata
	NSLog(@"--- XMPPPubsub fetchMetadataForNode: %@", node);
		
	// Build & send metadata stanza
	NSXMLElement *metadataElement = [NSXMLElement elementWithName: @"query" xmlns: @"http://jabber.org/protocol/disco#info"];
	[metadataElement addAttributeWithName: @"node" stringValue: node];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"get"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_getNodeMetadata, iqIdCounter++]];
	[iqStanza addChild: metadataElement];
	
	[xmppStream sendElement: iqStanza];
}

- (void)handleNodeMetadataResult:(XMPPIQ *)iq
{	
	NSXMLElement *queryElement = [iq elementForName: @"query" xmlns: @"http://jabber.org/protocol/disco#info"];
	NSXMLElement *xElement = [queryElement elementForName: @"x" xmlns: @"jabber:x:data"];
	NSString *node = [[queryElement attributeForName: @"node"] stringValue];
	NSArray *fields = [xElement elementsForName: @"field"];
	
	NSMutableDictionary *metadata = [[NSMutableDictionary alloc] initWithCapacity: [fields count]];
	
	for (NSXMLElement *fieldElement in fields) {
		[metadata setObject: [[fieldElement elementForName: @"value"] stringValue] 
					 forKey: [[fieldElement attributeForName: @"var"] stringValue]];
	}
	
	if ([metadata count] > 0) {
		// Notify delegate of result
		[multicastDelegate xmppPubsub: self didReceiveMetadata: metadata forNode: node];
	}
	
}

- (void)fetchAffiliationsForNode:(NSString *)node
{
	// Fetch the affiliation list of a node
	// http://xmpp.org/extensions/xep-0060.html#owner-affiliations-retrieve
	NSLog(@"--- XMPPPubsub fetchAffiliationsForNode: %@", node);
	
	[collectionArray removeAllObjects];
	
	[self fetchAffiliationsForNode: node afterJid: nil];
}

- (void)fetchAffiliationsForNode:(NSString *)node afterJid:(NSString *)jid
{
	// Fetch the affiliation list of a node
	// http://xmpp.org/extensions/xep-0060.html#owner-affiliations-retrieve
	NSLog(@"--- XMPPPubsub fetchAffiliationsForNode: %@ afterJid: %@", node, jid);
	
	// Build & send affiliations stanza
	NSXMLElement *affiliationsElement = [NSXMLElement elementWithName: @"affiliations"];
	[affiliationsElement addAttributeWithName: @"node" stringValue: node];
	
	NSXMLElement *pubsubElement = [NSXMLElement elementWithName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub#owner"];
	[pubsubElement addChild: affiliationsElement];
	
	NSXMLElement *setElement = [NSXMLElement elementWithName: @"set" xmlns: @"http://jabber.org/protocol/rsm"];
	[setElement addChild: [NSXMLElement elementWithName: @"max" stringValue: [NSString stringWithFormat: @"%d", RSM_MAX]]];
	
	if ([jid length] > 0) {
		[setElement addChild: [NSXMLElement elementWithName: @"after" stringValue: jid]];
	}
	
	[pubsubElement addChild: setElement];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"get"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_getNodeAffiliations, iqIdCounter++]];
	[iqStanza addChild: pubsubElement];
	
	[xmppStream sendElement: iqStanza];
}

- (void)handleNodeAffiliationsResult:(XMPPIQ *)iq
{
	NSXMLElement *pubsubElement = [iq elementForName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub#owner"];
	NSXMLElement *affiliationsElement = [pubsubElement elementForName: @"affiliations"];
	NSString *node = [[affiliationsElement attributeForName: @"node"] stringValue];
	NSArray *affiliations = [affiliationsElement elementsForName: @"affiliation"];
	
	[collectionArray addObjectsFromArray: affiliations];
	
	// Process RSM data
	NSXMLElement *setElement = [pubsubElement elementForName: @"set" xmlns: @"http://jabber.org/protocol/rsm"];
	
	if ([collectionArray count] > 0 && setElement) {
		if ([collectionArray count] >= [[[setElement elementForName: @"count"] stringValue] intValue]) {
			// Notify delegate of result
			[multicastDelegate xmppPubsub: self didReceiveAffiliations: collectionArray forNode: node];
		}
		else {
			// Fetch next packet of subscriptions
			[self fetchAffiliationsForNode: node afterJid: [[setElement elementForName: @"last"] stringValue]];
		}
	}
	else {
		// Notify delegate of result
		[multicastDelegate xmppPubsub: self didReceiveAffiliations: collectionArray forNode: node];
	}
}

- (void)fetchItemsForNode:(NSString *)node
{
	// Fetch all items for a node
	// http://xmpp.org/extensions/xep-0060.html#subscriber-retrieve
	NSLog(@"--- XMPPPubsub fetchItemsForNode: %@", node);
	
	[self fetchItemsForNode: node afterItemId: 0];
}

- (void)fetchItemsForNode:(NSString *)node afterItemId:(int)itemId
{
	// Fetch all items for a node
	// http://xmpp.org/extensions/xep-0060.html#subscriber-retrieve
	NSLog(@"--- XMPPPubsub fetchItemsForNode: %@ afterItemId: %d", node, itemId);
	
	// Build & send items stanza
	NSXMLElement *itemsElement = [NSXMLElement elementWithName: @"items"];
	[itemsElement addAttributeWithName: @"node" stringValue: node];
	
	if (itemId > 0) {
		NSXMLElement *setElement = [NSXMLElement elementWithName: @"set" xmlns: @"http://jabber.org/protocol/rsm"];
		[setElement addChild: [NSXMLElement elementWithName: @"after" stringValue: [NSString stringWithFormat: @"%d", itemId]]];

		[itemsElement addChild: setElement];
	}
	
	NSXMLElement *pubsubElement = [NSXMLElement elementWithName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub"];
	[pubsubElement addChild: itemsElement];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"get"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_getNodeItems, iqIdCounter++]];
	[iqStanza addChild: pubsubElement];
	
	[xmppStream sendElement: iqStanza];	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node User Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setSubscriptionForUser:(NSString *)jid onNode:(NSString *)node toSubscription:(NSString *)subscription
{
	// Set a users subscription to a pubsub node
	// http://xmpp.org/extensions/xep-0060.html#owner-subscriptions-modify
	NSLog(@"--- XMPPPubsub setSubscriptionForUser: %@ onNode: %@ toSubscription: %@", jid, node, subscription);
	
	// Build & send subscription stanza
	NSXMLElement *subscriptionElement = [NSXMLElement elementWithName: @"subscription"];
	[subscriptionElement addAttributeWithName: @"jid" stringValue: jid];
	[subscriptionElement addAttributeWithName: @"subscription" stringValue: subscription];
	
	NSXMLElement *subscriptionsElement = [NSXMLElement elementWithName: @"subscriptions"];
	[subscriptionsElement addAttributeWithName: @"node" stringValue: node];
	[subscriptionsElement addChild: subscriptionElement];
	
	NSXMLElement *pubsubElement = [NSXMLElement elementWithName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub#owner"];
	[pubsubElement addChild: subscriptionsElement];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"set"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_setSubscription, iqIdCounter++]];
	[iqStanza addChild: pubsubElement];
	
	[xmppStream sendElement: iqStanza];
}

- (void)setAffiliationForUser:(NSString *)jid onNode:(NSString *)node toAffiliation:(NSString *)affiliation
{
	// Set a users affiliation to a pubsub node
	// http://xmpp.org/extensions/xep-0060.html#owner-affiliations-modify
	NSLog(@"--- XMPPPubsub setAffiliationForUser: %@ onNode: %@ toAffiliation: %@", jid, node, affiliation);
	
	// Build & send affiliation stanza
	NSXMLElement *affiliationElement = [NSXMLElement elementWithName: @"affiliation"];
	[affiliationElement addAttributeWithName: @"jid" stringValue: jid];
	[affiliationElement addAttributeWithName: @"affiliation" stringValue: affiliation];
	
	NSXMLElement *affiliationsElement = [NSXMLElement elementWithName: @"affiliations"];
	[affiliationsElement addAttributeWithName: @"node" stringValue: node];
	[affiliationsElement addChild: affiliationElement];
	
	NSXMLElement *pubsubElement = [NSXMLElement elementWithName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub#owner"];
	[pubsubElement addChild: affiliationsElement];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"set"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_setAffiliation, iqIdCounter++]];
	[iqStanza addChild: pubsubElement];
	
	[xmppStream sendElement: iqStanza];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)publishItemToNode:(NSString *)node withItem:(NSXMLElement *)itemElement
{
	// Publish an item to a pubsub node
	// http://xmpp.org/extensions/xep-0060.html#publisher-publish
	NSLog(@"--- XMPPPubsub publishItemToNode: %@", node);

	// Build & send affiliation stanza
	NSXMLElement *publishElement = [NSXMLElement elementWithName: @"publish"];
	[publishElement addAttributeWithName: @"node" stringValue: node];
	[publishElement addChild: itemElement];
	
	NSXMLElement *pubsubElement = [NSXMLElement elementWithName: @"pubsub" xmlns: @"http://jabber.org/protocol/pubsub"];
	[pubsubElement addChild: publishElement];
	
	NSXMLElement *iqStanza = [NSXMLElement elementWithName: @"iq"];
	[iqStanza addAttributeWithName: @"to" stringValue: serverName];
	[iqStanza addAttributeWithName: @"type" stringValue: @"set"];
	[iqStanza addAttributeWithName: @"id" stringValue: [NSString stringWithFormat: @"%d:%d", kIqId_publishItem, iqIdCounter++]];
	[iqStanza addChild: pubsubElement];
	
	[xmppStream sendElement: iqStanza];	
}

@end
