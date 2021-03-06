//
//  Util.h
//  Buddycloud
//
//  Created by Ben on 7/22/10.
//  Copyright 2010 buddycloud. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface Util : NSObject {

}

+ (UIImage *) imageWithImage:(UIImage *)image scaledToSize:(CGSize)newSize;

+ (NSString*) getPrettyDate:(NSDate*)date;

+ (NSUInteger) loadFonts;
+ (UIFont*) fontContent;
+ (UIFont*) fontLocationTime;

+ (UIColor*) appBKGroundBeigeColor;
+ (UIColor*) appBKGroundLightGreyColor;

+ (NSURL*) generateURL:(NSString*)baseURL params:(NSDictionary*)params;
+ (NSMutableDictionary*) getQueryPramsDict:(NSString*)urlQueryString;

@end
