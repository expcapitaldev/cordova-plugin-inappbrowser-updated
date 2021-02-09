/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import <Cordova/CDVPlugin.h>
#import <Cordova/CDVInvokedUrlCommand.h>
#import <Cordova/CDVScreenOrientationDelegate.h>
#import "CDVWKInAppBrowserUIDelegate.h"
#import "CDVInAppBrowserOptions.h"
#import "CDVInAppBrowserNavigationController.h"

@class CDVWKInAppBrowserViewController;

@interface CDVWKInAppBrowser : CDVPlugin {
    UIWindow * tmpWindow;

    @private
    NSString* _beforeload;
    BOOL _waitForBeforeload;
}

@property (nonatomic, retain) CDVWKInAppBrowser* instance;
@property (nonatomic, retain) CDVWKInAppBrowserViewController* inAppBrowserViewController;
@property (nonatomic, copy) NSString* callbackId;
@property (nonatomic, copy) NSRegularExpression *callbackIdPattern;

+ (id) getInstance;
- (void)open:(CDVInvokedUrlCommand*)command;
- (void)close:(CDVInvokedUrlCommand*)command;
- (void)injectScriptCode:(CDVInvokedUrlCommand*)command;
- (void)show:(CDVInvokedUrlCommand*)command;
- (void)hide:(CDVInvokedUrlCommand*)command;
- (void)loadAfterBeforeload:(CDVInvokedUrlCommand*)command;

@end

@interface CDVWKInAppBrowserViewController : UIViewController <CDVScreenOrientationDelegate,WKNavigationDelegate,WKUIDelegate,WKScriptMessageHandler,UIAdaptivePresentationControllerDelegate>{
    @private
    CDVInAppBrowserOptions *_browserOptions;
    NSDictionary *_settings;
}

@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) WKWebViewConfiguration* configuration;
@property (nonatomic, strong) UIStackView* mainStackView;
@property (nonatomic, strong) UIView* addressContainerView;
@property (nonatomic, strong) UILabel* addressLabel;
@property (nonatomic, strong) UIButton* closeButton;
@property (nonatomic, strong) UIButton* safariButton;
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UIView* titleContainerView;
@property (nonatomic, strong) UIButton* backButton;
@property (nonatomic, strong) UIButton* forwardButton;
@property (nonatomic, strong) UIStackView* controlsStackView;
@property (nonatomic, strong) UIView* toolbarContainerView;
@property (nonatomic, strong) UIActivityIndicatorView* spinner;
@property (nonatomic, strong) CDVWKInAppBrowserUIDelegate* webViewUIDelegate;

@property (nonatomic, weak) id <CDVScreenOrientationDelegate> orientationDelegate;
@property (nonatomic, weak) CDVWKInAppBrowser* navigationDelegate;
@property (nonatomic) NSURL* currentURL;

- (void)close;
- (void)openSafari;
- (void)openInSystem:(NSURL*)url;
- (void)navigateTo:(NSURL*)url;
- (void)showLocationBar:(BOOL)show;
- (void)showToolBar:(BOOL)show : (NSString *) toolbarPosition;
- (void)setCloseButtonTitle:(NSString*)title : (NSString*) colorString : (int) buttonIndex;

- (id)initWithBrowserOptions: (CDVInAppBrowserOptions*) browserOptions andSettings:(NSDictionary*) settings;

@end
