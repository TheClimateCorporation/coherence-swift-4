//
//  MGWSDL+HTTP.h
//  MGConnect
//
//  Created by Tony Stone on 4/11/13.
//  Copyright (c) 2013 Mobile Grid, Inc. All rights reserved.
//
#import <Foundation/Foundation.h>
//
// Methods
//
typedef NSString * MGWSDLHTTPExtensionMethod;

extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodGET;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodPOST;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodPUT;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodDELETE;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodOPTIONS;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodHEAD;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodTRACE;
extern MGWSDLHTTPExtensionMethod const MGWSDLHTTPExtensionMethodCONNECT;

//
// HTTP Extension property names
//
extern NSString * const MGWSDLHTTPExtensionPropertyCookies;
extern NSString * const MGWSDLHTTPExtensionPropertyMethod;
extern NSString * const MGWSDLHTTPExtensionPropertyLocation;
extern NSString * const MGWSDLHTTPExtensionPropertyIgnoreUncited;
extern NSString * const MGWSDLHTTPExtensionPropertyInputSerialization;
extern NSString * const MGWSDLHTTPExtensionPropertyOutputSerialization;
extern NSString * const MGWSDLHTTPExtensionPropertyTransferCodingDefault;
extern NSString * const MGWSDLHTTPExtensionPropertyTransferCoding;
extern NSString * const MGWSDLHTTPExtensionPropertyQueryParameterSeparator;

//
// HTTP Extension Element Names
//
extern NSString * const MGWSDLHTTPExtensionElementHeader;

//
// HTTP Extension default values
//
extern NSString * const MGWSDLHTTPExtensionValueQueryParameterSeparatorDefault;

// TODO: Implemnent other serialization types such as text/plain
extern NSString * const MGWSDLHTTPExtensionValueSerializationURLEncoded;
extern NSString * const MGWSDLHTTPExtensionValueSerializationXML;
extern NSString * const MGWSDLHTTPExtensionValueSerializationJSON;

