//
// FlipBoardNavigationController.m
// iamkel.net
//
// Created by Michael henry Pantaleon on 4/30/13.
// Copyright (c) 2013 Michael Henry Pantaleon. All rights reserved.
// 
// Version 1.0
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "FlipBoardNavigationController.h"
#import <QuartzCore/QuartzCore.h>

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)


static const CGFloat kAnimationDuration = 0.5f;
static const CGFloat kAnimationDelay = 0.0f;
static const CGFloat kMaxBlackMaskAlpha = 0.5f;

typedef enum {
    PanDirectionNone = 0,
    PanDirectionLeft = 1,
    PanDirectionRight = 2
} PanDirection;


@interface FlipBoardNavigationController ()<UIGestureRecognizerDelegate>{
    UIView *_blackMask;
    CGPoint _panOrigin;
    BOOL _animationInProgress;
    CGFloat _percentageOffsetFromLeft;
    UIView *_tabBarContainer;
}

- (void) addPanGestureToView:(UIView*)view;
- (void) rollBackViewController;

- (UIViewController *)currentViewController;
- (UIViewController *)previousViewController;

- (void) transformAtPercentage:(CGFloat)percentage ;
- (void) completeSlidingAnimationWithDirection:(PanDirection)direction;
- (void) completeSlidingAnimationWithOffset:(CGFloat)offset;
- (CGRect) getSlidingRectWithPercentageOffset:(CGFloat)percentage orientation:(UIInterfaceOrientation)orientation ;
- (CGRect) viewBoundsWithOrientation:(UIInterfaceOrientation)orientation;

@end

@implementation FlipBoardNavigationController

- (id) initWithRootViewController:(UIViewController*)rootViewController {
    if (self = [super init]) {
        self.viewControllers = [NSMutableArray arrayWithObject:rootViewController];
        CGRect viewRect = [self viewBoundsWithOrientation:self.interfaceOrientation];
        
        UIViewController *rootViewController = [self.viewControllers objectAtIndex:0];
        [rootViewController willMoveToParentViewController:self];
        [self addChildViewController:rootViewController];
        
        UIView * rootView = rootViewController.view;
        rootView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        rootView.frame = viewRect;
        [self.view addSubview:rootView];
        [rootViewController didMoveToParentViewController:self];
        _blackMask = [[UIView alloc] initWithFrame:viewRect];
        _blackMask.backgroundColor = [UIColor blackColor];
        _blackMask.alpha = 0.0;
        _blackMask.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [self.view insertSubview:_blackMask atIndex:0];
        self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }
    return self;
}

- (void) dealloc {
    self.viewControllers = nil;
    _gestures  = nil;
    _blackMask = nil;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    _segue = nil;
}

#pragma mark - PushViewController With Completion Block
- (void) pushViewController:(UIViewController *)viewController completion:(FlipBoardNavigationControllerCompletionBlock)handler {
    _animationInProgress = YES;
    viewController.view.frame = CGRectOffset(self.view.bounds, self.view.bounds.size.width, 0);
    viewController.view.autoresizingMask =  UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _blackMask.alpha = 0.0;
    [viewController willMoveToParentViewController:self];
    [self addChildViewController:viewController];
    [self.view bringSubviewToFront:_blackMask];
    [self.view addSubview:viewController.view];
    UITabBar *tabBar;
    if (!self.currentViewController.hidesBottomBarWhenPushed) {
        //只有最外层显示bottomBar
        tabBar = self.currentViewController.tabBarController.tabBar;
        _tabBarContainer = tabBar.superview;
        [tabBar removeFromSuperview];
        [[self currentViewController].view addSubview:tabBar];
    }
    [self.viewControllers addObject:viewController];
    [UIView animateWithDuration:kAnimationDuration delay:kAnimationDelay options:0 animations:^{
        [self currentViewController].view.transform = CGAffineTransformIdentity;
        viewController.view.frame = self.view.bounds;
        _blackMask.alpha = kMaxBlackMaskAlpha;
    } completion:^(BOOL finished) {
        if (finished) {
            [viewController didMoveToParentViewController:self];
            _animationInProgress = NO;
            _gestures = [[NSMutableArray alloc] init];
            [self addPanGestureToView:[self currentViewController].view];
            if (tabBar) {
                [tabBar removeFromSuperview];
                [tabBar setHidden:YES];
                [_tabBarContainer addSubview:tabBar];
            }
            handler();
        }
    }];
}

- (void) pushViewController:(UIViewController *)viewController {
    [viewController setHidesBottomBarWhenPushed:YES];
    [viewController.view setClipsToBounds:YES];
    _segue = nil;
    [self pushViewController:viewController completion:^{}];
}

- (void) setSegue:(UIViewController *)segue
{
    __block BOOL shouldHide = NO;
    [self.viewControllers enumerateObjectsUsingBlock:^(UIViewController *vc, NSUInteger idx, BOOL *stop) {
        if (shouldHide && (idx != self.viewControllers.count-1)) {
            [vc.view setHidden:YES];
        }
        if ([vc isEqual:segue]) {
            shouldHide = YES;
        }
    }];
    _segue = segue;
}

#pragma mark - PopViewController With Completion Block
- (void) popViewControllerWithCompletion:(FlipBoardNavigationControllerCompletionBlock)handler {
    _animationInProgress = YES;
    if (self.viewControllers.count < 2) {
        return;
    }
    
    if (![self previousViewController].hidesBottomBarWhenPushed) {
        UITabBar *tabBar = [self previousViewController].tabBarController.tabBar;
        if (tabBar.hidden) {
            [tabBar removeFromSuperview];
            [[self previousViewController].view addSubview:tabBar];
            [tabBar setHidden:NO];
        }
    }
    
    UIViewController *currentVC = [self currentViewController];
    [currentVC.view setClipsToBounds:YES];
    UIViewController *previousVC = [self previousViewController];
    if (_segue) {
        previousVC = _segue;
    }
    [previousVC viewWillAppear:NO];
    [UIView animateWithDuration:kAnimationDuration delay:kAnimationDelay options:0 animations:^{
        currentVC.view.frame = CGRectOffset(self.view.bounds, self.view.bounds.size.width, 0);
        previousVC.view.transform = CGAffineTransformIdentity;
        previousVC.view.frame = self.view.bounds;
        _blackMask.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (finished) {
            [currentVC.view removeFromSuperview];
            [currentVC willMoveToParentViewController:nil];
            [self.view bringSubviewToFront:previousVC.view];
            [currentVC removeFromParentViewController];
            [currentVC didMoveToParentViewController:nil];
            do {
                [self.viewControllers removeLastObject];
            } while (_segue && ![self.currentViewController isEqual:_segue]);
            _animationInProgress = NO;
            [previousVC viewDidAppear:NO];
            if (!previousVC.hidesBottomBarWhenPushed) {
                UITabBar *tabBar = previousVC.tabBarController.tabBar;
                [tabBar removeFromSuperview];
                [_tabBarContainer addSubview:tabBar];
            }
            handler();
        }
    }];
}

- (void) popViewController {
    [self transformAtPercentage:0];
    [self completeSlidingAnimationWithDirection:PanDirectionRight];
}

- (void) popToRootViewController
{
    self.segue = _viewControllers[0];
    [self popViewController];
}

- (void) rollBackViewController {
    _animationInProgress = YES;
    
    UIViewController *vc = [self currentViewController];
    CGRect rect = CGRectMake(0, 0, vc.view.frame.size.width, vc.view.frame.size.height);

    [UIView animateWithDuration:0.3f
                          delay:kAnimationDelay
                        options:0
                     animations:^{
                         vc.view.frame = rect;
                         _blackMask.alpha = kMaxBlackMaskAlpha;
                     }
                     completion:^(BOOL finished) {
                         if (finished) {
                             _animationInProgress = NO;
                         }
                     }];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
 
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {

}

#pragma mark - ChildViewController
- (UIViewController *)currentViewController {
    UIViewController *result = nil;
    if ([self.viewControllers count]>0) {
        result = [self.viewControllers lastObject];
    }
    return result;
}

#pragma mark - ParentViewController
- (UIViewController *)previousViewController {
    UIViewController *result = nil;
    if ([self.viewControllers count]>1) {
        result = [self.viewControllers objectAtIndex:self.viewControllers.count - 2];
    }
    return result;
}

#pragma mark - Add Pan Gesture
- (void) addPanGestureToView:(UIView*)view
{
    UIScreenEdgePanGestureRecognizer *panGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self
                                                                                                     action:@selector(gestureRecognizerDidPan:)];
    panGesture.cancelsTouchesInView = YES;
    panGesture.delegate = self;
    panGesture.edges = UIRectEdgeLeft;
    [view addGestureRecognizer:panGesture];
    [_gestures addObject:panGesture];
}

# pragma mark - Avoid Unwanted Vertical Gesture
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)panGestureRecognizer {
    if ([panGestureRecognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) {
        return YES;
    }
    return NO;
}

#pragma mark - Gesture recognizer
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIViewController * vc =  [self.viewControllers lastObject];
    _panOrigin = vc.view.frame.origin;
    gestureRecognizer.enabled = YES;
    return !_animationInProgress;
}

- (BOOL) gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - Handle Panning Activity
- (void) gestureRecognizerDidPan:(UIPanGestureRecognizer*)panGesture {
    if (_animationInProgress) {
        return;
    }
    PanDirection panDirection = PanDirectionNone;
    static UIViewController *currentVC;
    if (panGesture.state == UIGestureRecognizerStateBegan) {
        currentVC = [self currentViewController];
        if (![self previousViewController].hidesBottomBarWhenPushed) {
            UITabBar *tabBar = [self previousViewController].tabBarController.tabBar;
            [tabBar removeFromSuperview];
            [[self previousViewController].view addSubview:tabBar];
            [tabBar setHidden:NO];
        }
    } else {
        CGPoint currentPoint = [panGesture translationInView:self.view];
        CGFloat x = currentPoint.x + _panOrigin.x;
        CGPoint vel = [panGesture velocityInView:self.view];
        if (vel.x > 0) {
            panDirection = PanDirectionRight;
        } else {
            panDirection = PanDirectionLeft;
        }
        CGFloat offset = CGRectGetWidth(self.view.frame) - x;
        _percentageOffsetFromLeft = offset / CGRectGetWidth(self.view.bounds);
        currentVC.view.frame = [self getSlidingRectWithPercentageOffset:_percentageOffsetFromLeft orientation:self.interfaceOrientation];
        [self transformAtPercentage:_percentageOffsetFromLeft];
        
        if (panGesture.state == UIGestureRecognizerStateEnded || panGesture.state == UIGestureRecognizerStateCancelled) {
            // If velocity is greater than 100 the Execute the Completion base on pan direction
            if(abs(vel.x) > 100) {
                [self completeSlidingAnimationWithDirection:panDirection];
            }else { 
                [self completeSlidingAnimationWithOffset:offset];
            }
        }
        
    }
}

#pragma mark - Set the required transformation based on percentage
- (void) transformAtPercentage:(CGFloat)percentage {
    CGFloat newAlphaValue = percentage * kMaxBlackMaskAlpha;
    [self previousViewController].view.transform = CGAffineTransformIdentity;
    _blackMask.alpha = newAlphaValue;
}

#pragma mark - This will complete the animation base on pan direction
- (void) completeSlidingAnimationWithDirection:(PanDirection)direction {
    if(direction==PanDirectionRight){
        [self popViewControllerWithCompletion:^{}];
    }else {
        [self rollBackViewController];
    }
}

#pragma mark - This will complete the animation base on offset
- (void) completeSlidingAnimationWithOffset:(CGFloat)offset{
   
    if(offset<[self viewBoundsWithOrientation:self.interfaceOrientation].size.width/2) {
         [self popViewController];
    }else {
        [self rollBackViewController];
    }
}

#pragma mark - Get the origin and size of the visible viewcontrollers(child)
- (CGRect) getSlidingRectWithPercentageOffset:(CGFloat)percentage orientation:(UIInterfaceOrientation)orientation {
    CGRect rectToReturn = self.view.bounds;
    rectToReturn.origin = CGPointMake(MAX(0, (1-percentage)*CGRectGetWidth(rectToReturn)), 0);
    return rectToReturn;
}

#pragma mark - Get the size of view in the main screen
- (CGRect) viewBoundsWithOrientation:(UIInterfaceOrientation)orientation{
	CGRect bounds = [UIScreen mainScreen].bounds;
    if([[UIApplication sharedApplication]isStatusBarHidden]){
        return bounds;
    } else if(UIInterfaceOrientationIsLandscape(orientation)){
		CGFloat width = bounds.size.width;
		bounds.size.width = bounds.size.height;
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))  {
            bounds.size.height = width - 20;
        }else {
            bounds.size.height = width;
        }
        return bounds;
	}else{
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))  {
            bounds.size.height-=20;
        }
        return bounds;
    }
}

@end



#pragma mark - UIViewController Category
//For Global Access of flipViewController
@implementation UIViewController (FlipBoardNavigationController)
@dynamic flipboardNavigationController;

- (FlipBoardNavigationController *)flipboardNavigationController
{
    if([self.parentViewController isKindOfClass:[FlipBoardNavigationController class]]){
        return (FlipBoardNavigationController*)self.parentViewController;
    }
    else if([self.parentViewController isKindOfClass:[UINavigationController class]] &&
            [self.parentViewController.parentViewController isKindOfClass:[FlipBoardNavigationController class]]){
        return (FlipBoardNavigationController*)[self.parentViewController parentViewController];
    }
    else{
        return nil;
    }
    
}


@end