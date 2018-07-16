//
//  Streamer.h
//  Streamer
//
//  Created by Germán Leiva on 16/04/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>

//! Project version number for Streamer.
FOUNDATION_EXPORT double StreamerVersionNumber;

//! Project version string for Streamer.
FOUNDATION_EXPORT const unsigned char StreamerVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <Streamer/PublicHeader.h>

#elseif TARGET_OS_MAC

#import <Cocoa/Cocoa.h>

//! Project version number for Streamer_Mac.
FOUNDATION_EXPORT double Streamer_MacVersionNumber;

//! Project version string for Streamer_Mac.
FOUNDATION_EXPORT const unsigned char Streamer_MacVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <Streamer_Mac/PublicHeader.h>
#endif
