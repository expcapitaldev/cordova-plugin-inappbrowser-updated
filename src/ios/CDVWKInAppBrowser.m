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

#import "CDVWKInAppBrowser.h"

#if __has_include("CDVWKProcessPoolFactory.h")
#import "CDVWKProcessPoolFactory.h"
#endif

#import <Cordova/CDVPluginResult.h>
#import <Cordova/CDVUserAgentUtil.h>

#define    kInAppBrowserTargetSelf @"_self"
#define    kInAppBrowserTargetSystem @"_system"
#define    kInAppBrowserTargetBlank @"_blank"

#define    kInAppBrowserToolbarBarPositionBottom @"bottom"
#define    kInAppBrowserToolbarBarPositionTop @"top"

#define    IAB_BRIDGE_NAME @"cordova_iab"

#define    TOOLBAR_HEIGHT 48.0

#define    LOCATIONBAR_HEIGHT 21.0
#define    FOOTER_HEIGHT ((TOOLBAR_HEIGHT) + (LOCATIONBAR_HEIGHT))

#pragma mark CDVWKInAppBrowser

@interface CDVWKInAppBrowser () {
    NSInteger _previousStatusBarStyle;
}
@end

@implementation CDVWKInAppBrowser

static CDVWKInAppBrowser* instance = nil;

+ (id) getInstance{
    return instance;
}

- (void)pluginInitialize
{
    instance = self;
    _previousStatusBarStyle = -1;
    _callbackIdPattern = nil;
    _beforeload = @"";
    _waitForBeforeload = NO;
}

- (id)settingForKey:(NSString*)key
{
    return [self.commandDelegate.settings objectForKey:[key lowercaseString]];
}

- (void)onReset
{
    [self close:nil];
}

- (void)close:(CDVInvokedUrlCommand*)command
{
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"IAB.close() called but it was already closed.");
        return;
    }
    
    // Things are cleaned up in browserExit.
    [self.inAppBrowserViewController close];
}

- (BOOL) isSystemUrl:(NSURL*)url
{
    if ([[url host] isEqualToString:@"itunes.apple.com"]) {
        return YES;
    }
    
    return NO;
}

- (void)open:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult;
    
    NSString* url = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1 withDefault:kInAppBrowserTargetSelf];
    NSString* options = [command argumentAtIndex:2 withDefault:@"" andClass:[NSString class]];
    
    self.callbackId = command.callbackId;
    
    if (url != nil) {
#ifdef __CORDOVA_4_0_0
        NSURL* baseUrl = [self.webViewEngine URL];
#else
        NSURL* baseUrl = [self.webView.request URL];
#endif
        NSURL* absoluteUrl = [[NSURL URLWithString:url relativeToURL:baseUrl] absoluteURL];
        
        if ([self isSystemUrl:absoluteUrl]) {
            target = kInAppBrowserTargetSystem;
        }
        
        if ([target isEqualToString:kInAppBrowserTargetSelf]) {
            [self openInCordovaWebView:absoluteUrl withOptions:options];
        } else if ([target isEqualToString:kInAppBrowserTargetSystem]) {
            [self openInSystem:absoluteUrl];
        } else { // _blank or anything else
            [self openInInAppBrowser:absoluteUrl withOptions:options];
        }
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"incorrect number of arguments"];
    }
    
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)openInInAppBrowser:(NSURL*)url withOptions:(NSString*)options
{
    CDVInAppBrowserOptions* browserOptions = [CDVInAppBrowserOptions parseOptions:options];
    
    WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
    if (browserOptions.cleardata) {
        
        NSDate* dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
        [dataStore removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] modifiedSince:dateFrom completionHandler:^{
            NSLog(@"Removed all WKWebView data");
            self.inAppBrowserViewController.webView.configuration.processPool = [[WKProcessPool alloc] init]; // create new process pool to flush all data
        }];
    }
    
    if (browserOptions.clearcache) {
        bool isAtLeastiOS11 = false;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
        if (@available(iOS 11.0, *)) {
            isAtLeastiOS11 = true;
        }
#endif
            
        if(isAtLeastiOS11){
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
            // Deletes all cookies
            WKHTTPCookieStore* cookieStore = dataStore.httpCookieStore;
            [cookieStore getAllCookies:^(NSArray* cookies) {
                NSHTTPCookie* cookie;
                for(cookie in cookies){
                    [cookieStore deleteCookie:cookie completionHandler:nil];
                }
            }];
#endif
        }else{
            // https://stackoverflow.com/a/31803708/777265
            // Only deletes domain cookies (not session cookies)
            [dataStore fetchDataRecordsOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
             completionHandler:^(NSArray<WKWebsiteDataRecord *> * __nonnull records) {
                 for (WKWebsiteDataRecord *record  in records){
                     NSSet<NSString*>* dataTypes = record.dataTypes;
                     if([dataTypes containsObject:WKWebsiteDataTypeCookies]){
                         [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:record.dataTypes
                               forDataRecords:@[record]
                               completionHandler:^{}];
                     }
                 }
             }];
        }
    }
    
    if (browserOptions.clearsessioncache) {
        bool isAtLeastiOS11 = false;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
        if (@available(iOS 11.0, *)) {
            isAtLeastiOS11 = true;
        }
#endif
        if (isAtLeastiOS11) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
            // Deletes session cookies
            WKHTTPCookieStore* cookieStore = dataStore.httpCookieStore;
            [cookieStore getAllCookies:^(NSArray* cookies) {
                NSHTTPCookie* cookie;
                for(cookie in cookies){
                    if(cookie.sessionOnly){
                        [cookieStore deleteCookie:cookie completionHandler:nil];
                    }
                }
            }];
#endif
        }else{
            NSLog(@"clearsessioncache not available below iOS 11.0");
        }
    }

    if (self.inAppBrowserViewController == nil) {
        NSString* userAgent = [CDVUserAgentUtil originalUserAgent];
        NSString* overrideUserAgent = [self settingForKey:@"OverrideUserAgent"];
        NSString* appendUserAgent = [self settingForKey:@"AppendUserAgent"];
        if(overrideUserAgent){
            userAgent = overrideUserAgent;
        }
        if(appendUserAgent){
            userAgent = [userAgent stringByAppendingString: appendUserAgent];
        }
        self.inAppBrowserViewController = [[CDVWKInAppBrowserViewController alloc] initWithUserAgent:userAgent prevUserAgent:[self.commandDelegate userAgent] browserOptions: browserOptions];
        self.inAppBrowserViewController.navigationDelegate = self;
        
        if ([self.viewController conformsToProtocol:@protocol(CDVScreenOrientationDelegate)]) {
            self.inAppBrowserViewController.orientationDelegate = (UIViewController <CDVScreenOrientationDelegate>*)self.viewController;
        }
    }
    
    [self.inAppBrowserViewController showLocationBar:browserOptions.location];
    [self.inAppBrowserViewController showToolBar:browserOptions.toolbar :browserOptions.toolbarposition];
    if (browserOptions.closebuttoncaption != nil || browserOptions.closebuttoncolor != nil) {
        int closeButtonIndex = browserOptions.lefttoright ? (browserOptions.hidenavigationbuttons ? 1 : 4) : 0;
        [self.inAppBrowserViewController setCloseButtonTitle:browserOptions.closebuttoncaption :browserOptions.closebuttoncolor :closeButtonIndex];
    }
    // Set Presentation Style
    UIModalPresentationStyle presentationStyle = UIModalPresentationFullScreen; // default
    if (browserOptions.presentationstyle != nil) {
        if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"pagesheet"]) {
            presentationStyle = UIModalPresentationPageSheet;
        } else if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"formsheet"]) {
            presentationStyle = UIModalPresentationFormSheet;
        }
    }
    self.inAppBrowserViewController.modalPresentationStyle = presentationStyle;
    
    // Set Transition Style
    UIModalTransitionStyle transitionStyle = UIModalTransitionStyleCoverVertical; // default
    if (browserOptions.transitionstyle != nil) {
        if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"fliphorizontal"]) {
            transitionStyle = UIModalTransitionStyleFlipHorizontal;
        } else if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"crossdissolve"]) {
            transitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    self.inAppBrowserViewController.modalTransitionStyle = transitionStyle;
    
    //prevent webView from bouncing
    if (browserOptions.disallowoverscroll) {
        if ([self.inAppBrowserViewController.webView respondsToSelector:@selector(scrollView)]) {
            ((UIScrollView*)[self.inAppBrowserViewController.webView scrollView]).bounces = NO;
        } else {
            for (id subview in self.inAppBrowserViewController.webView.subviews) {
                if ([[subview class] isSubclassOfClass:[UIScrollView class]]) {
                    ((UIScrollView*)subview).bounces = NO;
                }
            }
        }
    }
    
    // use of beforeload event
    if([browserOptions.beforeload isKindOfClass:[NSString class]]){
        _beforeload = browserOptions.beforeload;
    }else{
        _beforeload = @"yes";
    }
    _waitForBeforeload = ![_beforeload isEqualToString:@""];
    
    [self.inAppBrowserViewController navigateTo:url];
    if (!browserOptions.hidden) {
        [self show:nil withNoAnimate:browserOptions.hidden];
    }
}

- (void)show:(CDVInvokedUrlCommand*)command{
    [self show:command withNoAnimate:NO];
}

- (void)show:(CDVInvokedUrlCommand*)command withNoAnimate:(BOOL)noAnimate
{
    BOOL initHidden = NO;
    if(command == nil && noAnimate == YES){
        initHidden = YES;
    }
    
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"Tried to show IAB after it was closed.");
        return;
    }
    if (_previousStatusBarStyle != -1) {
        NSLog(@"Tried to show IAB while already shown");
        return;
    }
    
    if(!initHidden){
        _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    }
    
    __block CDVInAppBrowserNavigationController* nav = [[CDVInAppBrowserNavigationController alloc]
                                                        initWithRootViewController:self.inAppBrowserViewController];
    nav.orientationDelegate = self.inAppBrowserViewController;
    nav.navigationBarHidden = YES;
    nav.modalPresentationStyle = self.inAppBrowserViewController.modalPresentationStyle;
    
    __weak CDVWKInAppBrowser* weakSelf = self;
    
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.inAppBrowserViewController != nil) {
            float osVersion = [[[UIDevice currentDevice] systemVersion] floatValue];
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf->tmpWindow) {
                CGRect frame = [[UIScreen mainScreen] bounds];
                if(initHidden && osVersion < 11){
                   frame.origin.x = -10000;
                }
                strongSelf->tmpWindow = [[UIWindow alloc] initWithFrame:frame];
            }
            UIViewController *tmpController = [[UIViewController alloc] init];

            [strongSelf->tmpWindow setRootViewController:tmpController];
            [strongSelf->tmpWindow setWindowLevel:UIWindowLevelNormal];

            if(!initHidden || osVersion < 11){
                [self->tmpWindow makeKeyAndVisible];
            }
            [tmpController presentViewController:nav animated:!noAnimate completion:nil];
        }
    });
}

- (void)hide:(CDVInvokedUrlCommand*)command
{
    // Set tmpWindow to hidden to make main webview responsive to touch again
    // https://stackoverflow.com/questions/4544489/how-to-remove-a-uiwindow
    self->tmpWindow.hidden = YES;

    if (self.inAppBrowserViewController == nil) {
        NSLog(@"Tried to hide IAB after it was closed.");
        return;
        
        
    }
    if (_previousStatusBarStyle == -1) {
        NSLog(@"Tried to hide IAB while already hidden");
        return;
    }
    
    _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.inAppBrowserViewController != nil) {
            _previousStatusBarStyle = -1;
            [self.inAppBrowserViewController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

- (void)openInCordovaWebView:(NSURL*)url withOptions:(NSString*)options
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];
    
#ifdef __CORDOVA_4_0_0
    // the webview engine itself will filter for this according to <allow-navigation> policy
    // in config.xml for cordova-ios-4.0
    [self.webViewEngine loadRequest:request];
#else
    if ([self.commandDelegate URLIsWhitelisted:url]) {
        [self.webView loadRequest:request];
    } else { // this assumes the InAppBrowser can be excepted from the white-list
        [self openInInAppBrowser:url withOptions:options];
    }
#endif
}

- (void)openInSystem:(NSURL*)url
{
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    [[UIApplication sharedApplication] openURL:url];
}

- (void)loadAfterBeforeload:(CDVInvokedUrlCommand*)command
{
    NSString* urlStr = [command argumentAtIndex:0];

    if ([_beforeload isEqualToString:@""]) {
        NSLog(@"unexpected loadAfterBeforeload called without feature beforeload=get|post");
    }
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"Tried to invoke loadAfterBeforeload on IAB after it was closed.");
        return;
    }
    if (urlStr == nil) {
        NSLog(@"loadAfterBeforeload called with nil argument, ignoring.");
        return;
    }

    NSURL* url = [NSURL URLWithString:urlStr];
    //_beforeload = @"";
    _waitForBeforeload = NO;
    [self.inAppBrowserViewController navigateTo:url];
}

// This is a helper method for the inject{Script|Style}{Code|File} API calls, which
// provides a consistent method for injecting JavaScript code into the document.
//
// If a wrapper string is supplied, then the source string will be JSON-encoded (adding
// quotes) and wrapped using string formatting. (The wrapper string should have a single
// '%@' marker).
//
// If no wrapper is supplied, then the source string is executed directly.

- (void)injectDeferredObject:(NSString*)source withWrapper:(NSString*)jsWrapper
{
    // Ensure a message handler bridge is created to communicate with the CDVWKInAppBrowserViewController
    [self evaluateJavaScript: [NSString stringWithFormat:@"(function(w){if(!w._cdvMessageHandler) {w._cdvMessageHandler = function(id,d){w.webkit.messageHandlers.%@.postMessage({d:d, id:id});}}})(window)", IAB_BRIDGE_NAME]];
    
    if (jsWrapper != nil) {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@[source] options:0 error:nil];
        NSString* sourceArrayString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (sourceArrayString) {
            NSString* sourceString = [sourceArrayString substringWithRange:NSMakeRange(1, [sourceArrayString length] - 2)];
            NSString* jsToInject = [NSString stringWithFormat:jsWrapper, sourceString];
            [self evaluateJavaScript:jsToInject];
        }
    } else {
        [self evaluateJavaScript:source];
    }
}


//Synchronus helper for javascript evaluation
- (void)evaluateJavaScript:(NSString *)script {
    __block NSString* _script = script;
    [self.inAppBrowserViewController.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error == nil) {
            if (result != nil) {
                NSLog(@"%@", result);
            }
        } else {
            NSLog(@"evaluateJavaScript error : %@ : %@", error.localizedDescription, _script);
        }
    }];
}

- (void)injectScriptCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper = nil;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"_cdvMessageHandler('%@',JSON.stringify([eval(%%@)]));", command.callbackId];
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectScriptFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('script'); c.src = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('script'); c.src = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('style'); c.innerHTML = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('style'); c.innerHTML = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('link'); c.rel='stylesheet', c.type='text/css'; c.href = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (BOOL)isValidCallbackId:(NSString *)callbackId
{
    NSError *err = nil;
    // Initialize on first use
    if (self.callbackIdPattern == nil) {
        self.callbackIdPattern = [NSRegularExpression regularExpressionWithPattern:@"^InAppBrowser[0-9]{1,10}$" options:0 error:&err];
        if (err != nil) {
            // Couldn't initialize Regex; No is safer than Yes.
            return NO;
        }
    }
    if ([self.callbackIdPattern firstMatchInString:callbackId options:0 range:NSMakeRange(0, [callbackId length])]) {
        return YES;
    }
    return NO;
}

/**
 * The message handler bridge provided for the InAppBrowser is capable of executing any oustanding callback belonging
 * to the InAppBrowser plugin. Care has been taken that other callbacks cannot be triggered, and that no
 * other code execution is possible.
 */
- (void)webView:(WKWebView *)theWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL* url = navigationAction.request.URL;
    NSURL* mainDocumentURL = navigationAction.request.mainDocumentURL;
    BOOL isTopLevelNavigation = [url isEqual:mainDocumentURL];
    BOOL shouldStart = YES;
    BOOL useBeforeLoad = NO;
    NSString* httpMethod = navigationAction.request.HTTPMethod;
    NSString* errorMessage = nil;
    
    if([_beforeload isEqualToString:@"post"]){
        //TODO handle POST requests by preserving POST data then remove this condition
        errorMessage = @"beforeload doesn't yet support POST requests";
    }
    else if(isTopLevelNavigation && (
           [_beforeload isEqualToString:@"yes"]
       || ([_beforeload isEqualToString:@"get"] && [httpMethod isEqualToString:@"GET"])
    // TODO comment in when POST requests are handled
    // || ([_beforeload isEqualToString:@"post"] && [httpMethod isEqualToString:@"POST"])
    )){
        useBeforeLoad = YES;
    }

    // When beforeload, on first URL change, initiate JS callback. Only after the beforeload event, continue.
    if (_waitForBeforeload && useBeforeLoad) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"beforeload", @"url":[url absoluteString]}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    if(errorMessage != nil){
        NSLog(errorMessage);
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsDictionary:@{@"type":@"loaderror", @"url":[url absoluteString], @"code": @"-1", @"message": errorMessage}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
    
    //if is an app store link, let the system handle it, otherwise it fails to load it
    if ([[ url scheme] isEqualToString:@"itms-appss"] || [[ url scheme] isEqualToString:@"itms-apps"]) {
        [theWebView stopLoading];
        [self openInSystem:url];
        shouldStart = NO;
    }
    else if ((self.callbackId != nil) && isTopLevelNavigation) {
        // Send a loadstart event for each top-level navigation (includes redirects).
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }

    if (useBeforeLoad) {
        _waitForBeforeload = YES;
    }
    
    if(shouldStart){
        // Fix GH-417 & GH-424: Handle non-default target attribute
        // Based on https://stackoverflow.com/a/25713070/777265
        if (!navigationAction.targetFrame){
            [theWebView loadRequest:navigationAction.request];
            decisionHandler(WKNavigationActionPolicyCancel);
        }else{
            decisionHandler(WKNavigationActionPolicyAllow);
        }
    }else{
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

#pragma mark WKScriptMessageHandler delegate
- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
    
    CDVPluginResult* pluginResult = nil;
    
    if([message.body isKindOfClass:[NSDictionary class]]){
        NSDictionary* messageContent = (NSDictionary*) message.body;
        NSString* scriptCallbackId = messageContent[@"id"];
        
        if([messageContent objectForKey:@"d"]){
            NSString* scriptResult = messageContent[@"d"];
            NSError* __autoreleasing error = nil;
            NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[scriptResult dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
            if ((error == nil) && [decodedResult isKindOfClass:[NSArray class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:(NSArray*)decodedResult];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_JSON_EXCEPTION];
            }
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:scriptCallbackId];
    }else if(self.callbackId != nil){
        // Send a message event
        NSString* messageContent = (NSString*) message.body;
        NSError* __autoreleasing error = nil;
        NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[messageContent dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
        if (error == nil) {
            NSMutableDictionary* dResult = [NSMutableDictionary new];
            [dResult setValue:@"message" forKey:@"type"];
            [dResult setObject:decodedResult forKey:@"data"];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dResult];
            [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        }
    }
}

- (void)didStartProvisionalNavigation:(WKWebView*)theWebView
{
    NSLog(@"didStartProvisionalNavigation");
//    self.inAppBrowserViewController.currentURL = theWebView.URL;
}

- (void)didFinishNavigation:(WKWebView*)theWebView
{
    if (self.callbackId != nil) {
        NSString* url = [theWebView.URL absoluteString];
        if(url == nil){
            if(self.inAppBrowserViewController.currentURL != nil){
                url = [self.inAppBrowserViewController.currentURL absoluteString];
            }else{
                url = @"";
            }
        }
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstop", @"url":url}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)webView:(WKWebView*)theWebView didFailNavigation:(NSError*)error
{
    if (self.callbackId != nil) {
        NSString* url = [theWebView.URL absoluteString];
        if(url == nil){
            if(self.inAppBrowserViewController.currentURL != nil){
                url = [self.inAppBrowserViewController.currentURL absoluteString];
            }else{
                url = @"";
            }
        }
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsDictionary:@{@"type":@"loaderror", @"url":url, @"code": [NSNumber numberWithInteger:error.code], @"message": error.localizedDescription}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)browserExit
{
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"exit"}];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    }
    
    [self.inAppBrowserViewController.configuration.userContentController removeScriptMessageHandlerForName:IAB_BRIDGE_NAME];
    self.inAppBrowserViewController.configuration = nil;
    
    [self.inAppBrowserViewController.webView stopLoading];
    [self.inAppBrowserViewController.webView removeFromSuperview];
    [self.inAppBrowserViewController.webView setUIDelegate:nil];
    [self.inAppBrowserViewController.webView setNavigationDelegate:nil];
    self.inAppBrowserViewController.webView = nil;
    
    // Set navigationDelegate to nil to ensure no callbacks are received from it.
    self.inAppBrowserViewController.navigationDelegate = nil;
    self.inAppBrowserViewController = nil;

    // Set tmpWindow to hidden to make main webview responsive to touch again
    // Based on https://stackoverflow.com/questions/4544489/how-to-remove-a-uiwindow
    self->tmpWindow.hidden = YES;
    
    if (IsAtLeastiOSVersion(@"7.0")) {
        if (_previousStatusBarStyle != -1) {
            [[UIApplication sharedApplication] setStatusBarStyle:_previousStatusBarStyle];
            
        }
    }
    
    _previousStatusBarStyle = -1; // this value was reset before reapplying it. caused statusbar to stay black on ios7
}

@end //CDVWKInAppBrowser

#pragma mark CDVWKInAppBrowserViewController

@interface CDVWKInAppBrowserViewController()

@property (nonatomic, strong) NSLayoutConstraint *topConstraint;
@property (nonatomic, strong) NSLayoutConstraint *toolBarContainerHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *toolBarControlsTopConstraint;

@end

@implementation CDVWKInAppBrowserViewController

@synthesize currentURL;

BOOL isExiting = FALSE;

- (id)initWithUserAgent:(NSString*)userAgent prevUserAgent:(NSString*)prevUserAgent browserOptions: (CDVInAppBrowserOptions*) browserOptions
{
    self = [super init];
    if (self != nil) {
        _userAgent = userAgent;
        _prevUserAgent = prevUserAgent;
        _browserOptions = browserOptions;
        self.webViewUIDelegate = [[CDVWKInAppBrowserUIDelegate alloc] initWithTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]];
        [self.webViewUIDelegate setViewController:self];
        
        [self createViews];
    }
    
    return self;
}

-(void)dealloc {
    //NSLog(@"dealloc");
}

- (void)createViews
{
    self.view.backgroundColor = [UIColor clearColor];
    
    // We create the views in code for primarily for ease of upgrades and not requiring an external .xib to be included
    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;
#if __has_include("CDVWKProcessPoolFactory.h")
    configuration.processPool = [[CDVWKProcessPoolFactory sharedFactory] sharedProcessPool];
#endif
    [configuration.userContentController addScriptMessageHandler:self name:IAB_BRIDGE_NAME];
    
    //WKWebView options
    configuration.allowsInlineMediaPlayback = _browserOptions.allowinlinemediaplayback;
    if (IsAtLeastiOSVersion(@"10.0")) {
        configuration.ignoresViewportScaleLimits = _browserOptions.enableviewportscale;
        if(_browserOptions.mediaplaybackrequiresuseraction == YES){
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        }else{
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        }
    }else{ // iOS 9
        configuration.mediaPlaybackRequiresUserAction = _browserOptions.mediaplaybackrequiresuseraction;
    }
    
    self.mainStackView = [UIStackView new];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    [self.view addSubview:self.mainStackView];
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.topConstraint = [self.mainStackView.topAnchor constraintEqualToAnchor:self.view.topAnchor];
    [NSLayoutConstraint activateConstraints: @[
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        self.topConstraint,
     ]];
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self configureWebView];
    [self.mainStackView addArrangedSubview:self.webView];
    
    self.addressContainerView = [UIView new];
    [self configureAddressBar];
    [self.mainStackView addArrangedSubview:self.addressContainerView];
    
    self.toolbarContainerView = [UIView new];
    [self configureToolBarContainerView];
    [self.mainStackView addArrangedSubview:self.toolbarContainerView];
    self.toolbarContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolBarContainerHeightConstraint = [self.toolbarContainerView.heightAnchor constraintEqualToConstant:TOOLBAR_HEIGHT];
    self.toolBarContainerHeightConstraint.active = YES;
    
    self.addressContainerView.hidden = !_browserOptions.location;
    [self updateToolBarPosition:_browserOptions.toolbarIsBottomPosition];
}

- (void)updateToolBarPosition:(BOOL)toolbarIsBottomPosition {
    [self.mainStackView insertArrangedSubview:self.toolbarContainerView atIndex:toolbarIsBottomPosition ? 2 : 0];
    [self.mainStackView insertArrangedSubview:self.addressContainerView atIndex:1];
    self.topConstraint.constant = toolbarIsBottomPosition || self.toolbarContainerView.isHidden ? [self getStatusBarOffset] : 0.0;
    
    CGFloat statusBarHeight = [self getStatusBarOffset];
    CGFloat toolBarHeight = TOOLBAR_HEIGHT;
    toolBarHeight += toolbarIsBottomPosition ? UIApplication.sharedApplication.keyWindow.safeAreaInsets.bottom : statusBarHeight;
    self.toolBarContainerHeightConstraint.constant = toolBarHeight;
    
    self.toolBarControlsTopConstraint.constant = toolbarIsBottomPosition ? 0 : statusBarHeight;
}

- (void)configureWebView {
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self.webViewUIDelegate;
    self.webView.backgroundColor = [UIColor whiteColor];
        
    self.webView.clipsToBounds = YES;
    self.webView.multipleTouchEnabled = YES;
    self.webView.userInteractionEnabled = YES;
    self.webView.allowsLinkPreview = NO;
    self.webView.allowsBackForwardNavigationGestures = NO;
        
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (@available(iOS 11.0, *)) {
        [self.webView.scrollView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
    }
#endif
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [self.webView addSubview:self.spinner];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.widthAnchor constraintEqualToConstant:20.0],
        [self.spinner.heightAnchor constraintEqualToConstant:20.0],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.webView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.webView.centerYAnchor]
    ]];
}

- (void)configureToolBarContainerView {
    [self configureToolBarContainerBackgroundView];
    [self configureToolBarControls];
    
    NSLayoutConstraint *centerLabelConstraint = [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.toolbarContainerView.centerXAnchor];
    centerLabelConstraint.priority = UILayoutPriorityDefaultHigh;
    centerLabelConstraint.active = YES;
}

- (void)configureToolBarContainerBackgroundView {
    UIToolbar *toolbar = [self styledToolBar];
    
    [self.toolbarContainerView addSubview:toolbar];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.leadingAnchor constraintEqualToAnchor:self.toolbarContainerView.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.toolbarContainerView.trailingAnchor],
        [toolbar.topAnchor constraintEqualToAnchor:self.toolbarContainerView.topAnchor],
        [toolbar.bottomAnchor constraintEqualToAnchor:self.toolbarContainerView.bottomAnchor]
    ]];
}

- (UIToolbar *)styledToolBar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:self.toolbarContainerView.bounds];
    toolbar.barStyle = UIBarStyleBlackOpaque;
    toolbar.contentMode = UIViewContentModeBottom;
    toolbar.opaque = NO;
    if (_browserOptions.toolbarcolor != nil) { // Set toolbar color if user sets it in options
        toolbar.barTintColor = [self colorFromHexString:_browserOptions.toolbarcolor];
    }
    if (!_browserOptions.toolbartranslucent) { // Set toolbar translucent to no if user sets it in options
      toolbar.translucent = NO;
    }
    return toolbar;
}

- (void)configureToolBarControls {
    self.backButton = [self buttonWithImageName:@"ic_action_previous"
                                         action:@selector(goBack:)
                                          color:_browserOptions.navigationbuttoncolor
                                          theme:_browserOptions.iconbuttoncolor];
    self.forwardButton = [self buttonWithImageName:@"ic_action_next"
                                            action:@selector(goForward:)
                                             color:_browserOptions.navigationbuttoncolor
                                             theme:_browserOptions.iconbuttoncolor];
    self.closeButton = [self defaultCloseButton];
    
    self.titleLabel = [UILabel new];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.textColor = _browserOptions.titlecolor ? [self colorFromHexString:_browserOptions.titlecolor] : [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    
    self.titleContainerView = [UIView new];
    [self.titleContainerView addSubview:self.titleLabel];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints: @[
        [self.titleLabel.heightAnchor constraintEqualToAnchor:self.titleContainerView.heightAnchor],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.titleContainerView.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.titleContainerView.trailingAnchor]
    ]];
    
    // Filter out Navigation Buttons if user requests so
    NSArray *controls = @[self.backButton, self.forwardButton, self.titleContainerView, self.closeButton];
    if (!_browserOptions.lefttoright) {
        controls = @[self.closeButton, self.titleContainerView, self.forwardButton, self.backButton];
    }
    
    if (_browserOptions.hidenavigationbuttons) {
        self.forwardButton.hidden = YES;
        self.backButton.hidden = YES;
    }
    
    self.controlsStackView = [[UIStackView alloc] initWithArrangedSubviews:controls];
    self.controlsStackView.spacing = 11.0;
    [self.toolbarContainerView addSubview:self.controlsStackView];
    
    self.controlsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolBarControlsTopConstraint = [self.controlsStackView.topAnchor constraintEqualToAnchor:self.toolbarContainerView.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.controlsStackView.heightAnchor constraintEqualToConstant:TOOLBAR_HEIGHT],
        [self.controlsStackView.leadingAnchor constraintEqualToAnchor:self.toolbarContainerView.leadingAnchor constant:11],
        [self.controlsStackView.trailingAnchor constraintEqualToAnchor:self.toolbarContainerView.trailingAnchor constant:-11],
        self.toolBarControlsTopConstraint
    ]];
}

- (UIButton *)defaultCloseButton {
    return [self buttonWithImageName:@"ic_action_close"
                              action:@selector(close)
                               color:_browserOptions.closebuttoncolor
                               theme:_browserOptions.iconbuttoncolor];
}

- (void)configureAddressBar {
    UIToolbar *toolbar = [self styledToolBar];
    [self.addressContainerView addSubview:toolbar];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.leadingAnchor constraintEqualToAnchor:self.addressContainerView.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.addressContainerView.trailingAnchor],
        [toolbar.topAnchor constraintEqualToAnchor:self.addressContainerView.topAnchor],
        [toolbar.bottomAnchor constraintEqualToAnchor:self.addressContainerView.bottomAnchor]
    ]];

    self.addressLabel = [UILabel new];
    self.addressLabel.backgroundColor = [UIColor clearColor];
    self.addressLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.addressLabel.opaque = NO;
    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.addressLabel.textColor = [UIColor whiteColor];
    
    if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumScaleFactor:")]) {
        [self.addressLabel setValue:@(10.0/[UIFont labelFontSize]) forKey:@"minimumScaleFactor"];
    } else if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumFontSize:")]) {
        [self.addressLabel setValue:@(10.0) forKey:@"minimumFontSize"];
    }
    
    [self.addressContainerView addSubview:self.addressLabel];
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints: @[
        [self.addressLabel.leadingAnchor constraintEqualToAnchor:self.addressContainerView.leadingAnchor constant:5.0],
        [self.addressLabel.trailingAnchor constraintEqualToAnchor:self.addressContainerView.trailingAnchor],
        [self.addressLabel.topAnchor constraintEqualToAnchor:self.addressContainerView.topAnchor],
        [self.addressLabel.heightAnchor constraintEqualToConstant:LOCATIONBAR_HEIGHT],
    ]];
}

- (void)setCloseButtonTitle:(NSString*)title : (NSString*) colorString : (int) buttonIndex
{
    UIButton *previousClose = self.closeButton;
    NSInteger closeButtonIndex = [self.controlsStackView.arrangedSubviews indexOfObject:previousClose];
    if (title.length > 0) {
        self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [self.closeButton setTitle:title forState:UIControlStateNormal];
        if (colorString.length > 0) {
            self.closeButton.titleLabel.textColor = [self colorFromHexString:colorString];
        }
    } else {
        self.closeButton = [self defaultCloseButton];
    }
    
    [self.controlsStackView insertArrangedSubview:self.closeButton atIndex:closeButtonIndex];
    [self.controlsStackView removeArrangedSubview:previousClose];
    [previousClose removeFromSuperview];
}

- (void)showLocationBar:(BOOL)show
{
    self.addressContainerView.hidden = !show;
}

- (void)showToolBar:(BOOL)show : (NSString *) toolbarPosition
{
    self.toolbarContainerView.hidden = !show;
    [self updateToolBarPosition:![toolbarPosition isEqualToString:kInAppBrowserToolbarBarPositionTop]];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    if (isExiting && (self.navigationDelegate != nil) && [self.navigationDelegate respondsToSelector:@selector(browserExit)]) {
        [self.navigationDelegate browserExit];
        isExiting = FALSE;
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIApplication.sharedApplication.statusBarStyle;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (void)close
{
    [CDVUserAgentUtil releaseLock:&_userAgentLockToken];
    self.currentURL = nil;

    __weak UIViewController* weakSelf = self;

    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        isExiting = TRUE;
        if ([weakSelf respondsToSelector:@selector(presentingViewController)]) {
            [[weakSelf presentingViewController] dismissViewControllerAnimated:YES completion:nil];
        } else {
            [[weakSelf parentViewController] dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

- (void)navigateTo:(NSURL*)url
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];

    if (_userAgentLockToken != 0) {
        [self.webView loadRequest:request];
    } else {
        __weak CDVWKInAppBrowserViewController* weakSelf = self;
        [CDVUserAgentUtil acquireLock:^(NSInteger lockToken) {
            _userAgentLockToken = lockToken;
            [CDVUserAgentUtil setUserAgent:_userAgent lockToken:lockToken];
            [weakSelf.webView loadRequest:request];
        }];
    }
}

- (void)goBack:(id)sender
{
    [self.webView goBack];
}

- (void)goForward:(id)sender
{
    [self.webView goForward];
}

//
// On iOS 7 the status bar is part of the view's dimensions, therefore it's height has to be taken into account.
// The height of it could be hardcoded as 20 pixels, but that would assume that the upcoming releases of iOS won't
// change that value.
//
- (float) getStatusBarOffset {
    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    float statusBarOffset = IsAtLeastiOSVersion(@"7.0") ? MIN(statusBarFrame.size.width, statusBarFrame.size.height) : 0.0;
    return statusBarOffset;
}

// Helper function to convert hex color string to UIColor
// Assumes input like "#00FF00" (#RRGGBB).
// Taken from https://stackoverflow.com/questions/1560081/how-can-i-create-a-uicolor-from-a-hex-string
- (UIColor *)colorFromHexString:(NSString *)hexString {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

#pragma mark WKNavigationDelegate

- (void)webView:(WKWebView *)theWebView didStartProvisionalNavigation:(WKNavigation *)navigation{

    // loading url, start spinner, update back/forward

    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;

    NSLog(_browserOptions.hidespinner ? @"Yes" : @"No");
    if(!_browserOptions.hidespinner) {
        [self.spinner startAnimating];
    }

    return [self.navigationDelegate didStartProvisionalNavigation:theWebView];
}

- (void)webView:(WKWebView *)theWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    NSURL *mainDocumentURL = navigationAction.request.mainDocumentURL;

    BOOL isTopLevelNavigation = [url isEqual:mainDocumentURL];

    if (isTopLevelNavigation) {
        self.currentURL = url;
    }

    [self.navigationDelegate webView:theWebView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
}

- (void)webView:(WKWebView *)theWebView didFinishNavigation:(WKNavigation *)navigation
{
    // update url, stop spinner, update back/forward

    self.addressLabel.text = [self.currentURL absoluteString];
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
    theWebView.scrollView.contentInset = UIEdgeInsetsZero;

 	[self.spinner stopAnimating];

	[self.webView evaluateJavaScript:@"document.title" completionHandler:^(id _Nullable title, NSError * _Nullable error) {

        self.titleLabel.text = title;

		[self.webView evaluateJavaScript:@"document.body==null" completionHandler:^(id _Nullable _isPDF, NSError * _Nullable error) {
			if([_isPDF boolValue]){
			   [CDVUserAgentUtil setUserAgent:_prevUserAgent lockToken:_userAgentLockToken];
			}
		}];
    }];

    // Work around a bug where the first time a PDF is opened, all UIWebViews
    // reload their User-Agent from NSUserDefaults.
    // This work-around makes the following assumptions:
    // 1. The app has only a single Cordova Webview. If not, then the app should
    //    take it upon themselves to load a PDF in the background as a part of
    //    their start-up flow.
    // 2. That the PDF does not require any additional network requests. We change
    //    the user-agent here back to that of the CDVViewController, so requests
    //    from it must pass through its white-list. This *does* break PDFs that
    //    contain links to other remote PDF/websites.
    // More info at https://issues.apache.org/jira/browse/CB-2225

   [self.navigationDelegate didFinishNavigation:theWebView];
}
    
- (void)webView:(WKWebView*)theWebView failedNavigation:(NSString*) delegateName withError:(nonnull NSError *)error{
    // log fail message, stop spinner, update back/forward
    NSLog(@"webView:%@ - %ld: %@", delegateName, (long)error.code, [error localizedDescription]);
    
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
    [self.spinner stopAnimating];
    
    self.addressLabel.text = NSLocalizedString(@"Load Error", nil);
    
    [self.navigationDelegate webView:theWebView didFailNavigation:error];
}

- (void)webView:(WKWebView*)theWebView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error
{
    [self webView:theWebView failedNavigation:@"didFailNavigation" withError:error];
}
    
- (void)webView:(WKWebView*)theWebView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error
{
    [self webView:theWebView failedNavigation:@"didFailProvisionalNavigation" withError:error];
}

#pragma mark WKScriptMessageHandler delegate
- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
    if (![message.name isEqualToString:IAB_BRIDGE_NAME]) {
        return;
    }
    //NSLog(@"Received script message %@", message.body);
    [self.navigationDelegate userContentController:userContentController didReceiveScriptMessage:message];
}

#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }
    
    return 1 << UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
    
    return YES;
}

- (UIImage *)themedIconImage:(NSString *)name theme:(NSString *)theme {
    NSString *imageName = [NSString stringWithFormat:@"%@_%@", name, theme.length > 0 ? theme : @"white"];
    return [UIImage imageNamed:imageName];
}

- (UIButton *)buttonWithImageName:(NSString *)imageName action:(SEL)selector color:(NSString *)color theme:(NSString *)theme {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button.widthAnchor constraintEqualToConstant:35].active = YES;
    
    UIImage *iconImage = [self themedIconImage:imageName theme:theme];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    
    if (color.length > 0) {
        iconImage = [iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        button.tintColor = [self colorFromHexString:color];
    }
    [button setImage:iconImage forState:UIControlStateNormal];
    return button;
}

@end //CDVWKInAppBrowserViewController
