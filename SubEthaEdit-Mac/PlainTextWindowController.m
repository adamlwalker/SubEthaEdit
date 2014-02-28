//
//  PlainTextWindowController.m
//  SubEthaEdit
//
//  Created by Dominik Wagner on Fri Mar 05 2004.
//  Copyright (c) 2004-2007 TheCodingMonkeys. All rights reserved.
//

#import "PlainTextWindowController.h"
#import "PlainTextDocument.h"
#import "DocumentMode.h"
#import "PlainTextEditor.h"
#import "FoldableTextStorage.h"
#import "TCMMillionMonkeys/TCMMillionMonkeys.h"
#import "TCMMMUserSEEAdditions.h"
#import "SelectionOperation.h"
#import "ImagePopUpButtonCell.h"
#import "LayoutManager.h"
#import "SEETextView.h"
#import "SplitView.h"
#import "GeneralPreferences.h"
#import "TCMMMSession.h"
#import "AppController.h"
#import "SEEDocumentDialog.h"
#import "EncodingDoctorDialog.h"
#import "DocumentController.h"
#import "PlainTextWindowControllerTabContext.h"
#import "NSMenuTCMAdditions.h"
#import "PlainTextLoadProgress.h"
#import <PSMTabBarControl/PSMTabBarControl.h>
#import <PSMTabBarControl/PSMTabStyle.h>
#import "URLBubbleWindow.h"
#import "SEEParticipantsOverlayViewController.h"
#import "SEETabStyle.h"
#import <objc/objc-runtime.h>			// for objc_msgSend


static NSPoint S_cascadePoint = {0.0,0.0};

@interface PlainTextWindowController ()
- (void)insertObject:(NSDocument *)document inDocumentsAtIndex:(NSUInteger)index;
- (void)removeObjectFromDocumentsAtIndex:(NSUInteger)index;
@end

#pragma mark -

@implementation PlainTextWindowController

+ (void)initialize {
	if (self == [PlainTextWindowController class]) {
		[PSMTabBarControl registerTabStyleClass:[SEETabStyle class]];
	}
}

- (id)init {
    if ((self = [super initWithWindowNibName:@"PlainTextWindow"])) {
		[self setShouldCascadeWindows:NO];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateForPortMapStatus) name:TCMPortMapperDidFinishWorkNotification object:[TCMPortMapper sharedInstance]];
    }
    return self;
}

- (void)updateForPortMapStatus {
    BOOL isAnnounced = [(PlainTextDocument *)[self document] isAnnounced];
    BOOL isServer = [[(PlainTextDocument *)[self document] session] isServer];
    if (isAnnounced) {
//        BOOL portMapped = ([[[[TCMPortMapper sharedInstance] portMappings] anyObject] mappingStatus] == TCMPortMappingStatusMapped);
//        NSString *URLString = [[[[[self document] documentURL] absoluteString] componentsSeparatedByString:@"?"] objectAtIndex:0];
//        [O_URLTextField setObjectValue:URLString];
    } else if (isServer) {
//        [O_URLTextField setObjectValue:NSLocalizedString(@"Document not announced.\nNo Document URL.",@"Text for document URL field when not announced")];
    } else {
//        [O_URLTextField setObjectValue:NSLocalizedString(@"Not your Document.\nNo Document URL.",@"Text for document URL field when not your document")];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    I_plainTextEditors = nil;
    I_editorSplitView = nil;
    I_dialogSplitView = nil;
    I_documentDialog = nil;
    
    [I_documents release];
    I_documents = nil;

	[I_tabBar setDelegate:nil];
	[I_tabBar setTabView:nil];
	[I_tabView setDelegate:nil];
	[I_tabBar release];
	[I_tabView release];
	 
    [[DocumentController sharedInstance] updateTabMenu];
            
    [super dealloc];
}

- (void)windowWillLoad {
    if ([self document]) {
        [[self document] windowControllerWillLoadNib:self];
    }
}

- (void)setInitialRadarStatusForPlainTextEditor:(PlainTextEditor *)editor {
    PlainTextDocument *document=(PlainTextDocument *)[self document];
    NSEnumerator *users=[[[[document session] participants] objectForKey:TCMMMSessionReadWriteGroupName] objectEnumerator];
    TCMMMUser *user=nil;
    while ((user=[users nextObject])) {
        if (user != [TCMMMUserManager me]) {
            [editor setRadarMarkForUser:user];
        }
    }
}

- (void)windowDidLoad {
	NSWindow *window = self.window;
    [[window contentView] setAutoresizesSubviews:YES];

	[window setMinSize:NSMakeSize(500,370)];
	
	NSRect contentFrame = [[window contentView] frame];
	 
	I_tabBar = [[PSMTabBarControl alloc] initWithFrame:NSMakeRect(0.0, NSHeight(contentFrame) - [SEETabStyle desiredTabBarControlHeight], NSWidth(contentFrame), [SEETabStyle desiredTabBarControlHeight])];
    [I_tabBar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [I_tabBar setStyleNamed:@"SubEthaEdit"];
	[I_tabBar setShowAddTabButton:YES];
    [[window contentView] addSubview:I_tabBar];

    I_tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(contentFrame), NSHeight(contentFrame) - [SEETabStyle desiredTabBarControlHeight])];
    [I_tabView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
    [I_tabView setTabViewType:NSNoTabsNoBorder];

    [[window contentView] addSubview:I_tabView];
    [I_tabBar setTabView:I_tabView];
    [I_tabView setDelegate:I_tabBar];
    [I_tabBar setDelegate:self];
    [I_tabBar setPartnerView:I_tabView];

    BOOL shouldHideTabBar = [[NSUserDefaults standardUserDefaults] boolForKey:AlwaysShowTabBarKey];
    [I_tabBar setHideForSingleTab:!shouldHideTabBar];
    [I_tabBar hideTabBar:!shouldHideTabBar animate:NO];
    [I_tabBar setCellOptimumWidth:300];
    [I_tabBar setCellMinWidth:140];

    [self updateForPortMapStatus];
}

- (IBAction)showFindAndReplaceInterface:(id)aSender {
	[[self activePlainTextEditor] showFindAndReplace:aSender];
}


- (void)takeSettingsFromDocument {
    [self setShowsBottomStatusBar:[(PlainTextDocument *)[self document] showsBottomStatusBar]];
    [[self plainTextEditors] makeObjectsPerformSelector:@selector(takeSettingsFromDocument)];
}

- (NSTabViewItem *)tabViewItemForDocument:(PlainTextDocument *)document
{
    unsigned count = [I_tabView numberOfTabViewItems];
    unsigned i;
    for (i = 0; i < count; i++) {
        NSTabViewItem *tabItem = [I_tabView tabViewItemAtIndex:i];
        id identifier = [tabItem identifier];
        if ([[identifier document] isEqual:document]) {
            return tabItem;
        }
    }
    return nil;
}

- (void)document:(PlainTextDocument *)document isReceivingContent:(BOOL)flag;
{
    if (![[self documents] containsObject:document])
        return;
        
    NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
    if (tabViewItem) {
        PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
        [tabContext setValue:[NSNumber numberWithBool:flag] forKeyPath:@"isReceivingContent"];
        [tabContext setValue:[NSNumber numberWithBool:flag] forKeyPath:@"isProcessing"];

        if (flag) {
            PlainTextLoadProgress *loadProgress = [tabContext loadProgress];
            if (!loadProgress) {
                loadProgress = [[PlainTextLoadProgress alloc] init];
                [tabContext setLoadProgress:loadProgress];
                [loadProgress release];
            }
            [tabViewItem setView:[loadProgress loadProgressView]];
            [loadProgress registerForSession:[document session]];
            [loadProgress startAnimation];

            
        } else {
            PlainTextLoadProgress *loadProgress = [tabContext loadProgress];

            [loadProgress stopAnimation];

            PlainTextEditor *editor = [[tabContext plainTextEditors] objectAtIndex:0];

            [tabViewItem setView:[editor editorView]];
            [tabViewItem setInitialFirstResponder:[editor textView]];
            [[editor textView] setSelectedRange:NSMakeRange(0, 0)];

            if ([I_tabView selectedTabViewItem] == tabViewItem) [[self window] makeFirstResponder:[editor textView]];
            if ([self window] == [[[NSApp orderedWindows] objectEnumerator] nextObject]) {
                [[self window] makeKeyWindow];
            }
        }
    }
}

- (void)documentDidLoseConnection:(PlainTextDocument *)document {
    NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
    if (tabViewItem) {
        PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
        [tabContext setValue:[NSNumber numberWithBool:NO] forKeyPath:@"isReceivingContent"];
        [tabContext setValue:[NSNumber numberWithBool:NO] forKeyPath:@"isProcessing"];
        PlainTextLoadProgress *loadProgress = [tabContext loadProgress];
        [loadProgress stopAnimation];
        [loadProgress setStatusText:NSLocalizedString(@"Did lose Connection!", @"Text in Proxy window")];
    }
}

- (void)setWindowFrame:(NSRect)aFrame constrainedToScreen:(NSScreen *)aScreen display:(BOOL)aFlag {
	if (!aScreen) {
		// search for a screen that fits most of the frame
		NSEnumerator *screens = [[NSScreen screens] objectEnumerator];
		NSScreen *screen = nil;
		double overlapArea = -1.0;
		while ((screen = [screens nextObject])) {
			NSRect intersectionRect = NSIntersectionRect(aFrame, [screen frame]);
			double thisOverlapArea = intersectionRect.size.width * intersectionRect.size.height;
			if (thisOverlapArea > overlapArea) {
				aScreen = screen;
				overlapArea = thisOverlapArea;
			}
		}
		// only do that when we don't have an associated screen
		NSRect targetScreenVisibleFrame = [aScreen visibleFrame];
		if (NSWidth(targetScreenVisibleFrame) < NSWidth(aFrame)) {
			aFrame.size.width = targetScreenVisibleFrame.size.width;
		}
		if (NSMinX(targetScreenVisibleFrame) > NSMinX(aFrame)) {
			aFrame.origin.x += NSMinX(targetScreenVisibleFrame) - NSMinX(aFrame);
		}
		if (NSMaxX(targetScreenVisibleFrame) < NSMaxX(aFrame)) {
			aFrame.origin.x -= NSMaxX(aFrame) - NSMaxX(targetScreenVisibleFrame);
		}
		I_doNotCascade = YES;
	}

    if (aScreen) {
        NSRect visibleFrame=[aScreen visibleFrame];
        if (NSHeight(aFrame)>NSHeight(visibleFrame)) {
            CGFloat heightDiff=aFrame.size.height-visibleFrame.size.height;
            aFrame.origin.y+=heightDiff;
            aFrame.size.height-=heightDiff;
        }
        if (NSMinY(aFrame)<NSMinY(visibleFrame)) {
            CGFloat positionDiff=NSMinY(visibleFrame)-NSMinY(aFrame);
            aFrame.origin.y+=positionDiff;
        }
    }
    [[self window] setFrame:aFrame display:YES];
}

- (void)setSizeByColumns:(NSInteger)aColumns rows:(NSInteger)aRows {
    NSSize contentSize=[[I_plainTextEditors objectAtIndex:0] desiredSizeForColumns:aColumns rows:aRows];
    contentSize.width  = (NSInteger)(contentSize.width + 0.5);
    contentSize.height = (NSInteger)(contentSize.height + 0.5);
    NSWindow *window=[self window];
    NSSize minSize=[window contentMinSize];
    NSRect contentRect=[window contentRectForFrameRect:[window frame]];
    contentSize=NSMakeSize(MAX(contentSize.width,minSize.width),
                             MAX(contentSize.height,minSize.height));
    contentRect.origin.y+=contentRect.size.height-contentSize.height;
    contentRect.size=contentSize;
    NSRect frameRect=[window frameRectForContentRect:contentRect];
    NSScreen *screen=[[self window] screen];
    [self setWindowFrame:frameRect constrainedToScreen:screen display:YES];
    
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL selector = [menuItem action];
    
    if (selector == @selector(toggleParticipantsOverlay:)) {
        [menuItem setTitle:
            [[[self plainTextEditors] lastObject] hasBottomOverlayView] ?
            NSLocalizedString(@"Hide Participants", nil) :
            NSLocalizedString(@"Show Participants", nil)];
        return YES;
    } else if (selector == @selector(toggleBottomStatusBar:)) {
        [menuItem setState:[[I_plainTextEditors lastObject] showsBottomStatusBar]?NSOnState:NSOffState];
        return YES;
    } else if (selector == @selector(toggleLineNumbers:)) {
        [menuItem setState:[self showsGutter]?NSOnState:NSOffState];
        return YES;
    } else if (selector == @selector(copyDocumentURL:)) {
        return [(PlainTextDocument *)[self document] isAnnounced];
    } else if (selector == @selector(toggleSplitView:)) {
        [menuItem setTitle:[I_plainTextEditors count]==1?
                           NSLocalizedString(@"Split View",@"Split View Menu Entry"):
                           NSLocalizedString(@"Collapse Split View",@"Collapse Split View Menu Entry")];
        
        BOOL isReceivingContent = NO;
        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:[self document]];
        if (tabViewItem) isReceivingContent = [[tabViewItem identifier] isReceivingContent];
        return !isReceivingContent;
    } else if (selector == @selector(changePendingUsersAccess:)) {
        TCMMMSession *session=[(PlainTextDocument *)[self document] session];
        [menuItem setState:([menuItem tag]==[session accessState])?NSOnState:NSOffState];
        return [session isServer];
    } else if (selector == @selector(readWriteButtonAction:) ||
               selector == @selector(followUser:) ||
               selector == @selector(kickButtonAction:) ||
               selector == @selector(readOnlyButtonAction:)) {
        return [menuItem isEnabled];
    } else if (selector == @selector(openInSeparateWindow:)) {
        return ([[self documents] count] > 1);
    } else if (selector == @selector(selectNextTab:)) {
        if ([self hasManyDocuments])
            return YES;
        else
            return NO;
    } else if (selector == @selector(selectPreviousTab:)) {
        if ([self hasManyDocuments])
            return YES;
        else
            return NO;
    } else if (selector == @selector(showDocumentAtIndex:)) {
        int documentNumberToShow = [[menuItem representedObject] intValue];
        id document = nil;
        NSArray *documents = [self orderedDocuments];
        if ([documents count] > documentNumberToShow) {
            document = [documents objectAtIndex:documentNumberToShow];
            if ([document isDocumentEdited]) {
                [menuItem setMark:kBulletCharCode];
            } else {
                [menuItem setMark:noMark];
            }
            if (([self document] == document) && 
                ([[self window] isKeyWindow] || 
                 [[self window] isMainWindow])) {
                [menuItem setState:NSOnState];
                [menuItem setMark:kCheckCharCode];
            }
        }
        return ![[self window] attachedSheet] || ([[self window] attachedSheet] && [self document] == document);
    }
    
    return YES;
}

- (NSArray *)plainTextEditors {
    return I_plainTextEditors;
}

- (PlainTextEditor *)activePlainTextEditor {
    if ([I_plainTextEditors count]!=1) {
        id responder=[[self window] firstResponder];
        if ([responder isKindOfClass:[NSTextView class]]) {
            if ([[I_plainTextEditors objectAtIndex:1] textView] == responder) {
                return [I_plainTextEditors objectAtIndex:1];
            }
        }
    } 
    if ([I_plainTextEditors count]>0) {
        return [I_plainTextEditors objectAtIndex:0];
    }
    return nil;
}

- (PlainTextEditor *)activePlainTextEditorForDocument:(PlainTextDocument *)aDocument {
	NSTabViewItem *tabViewItem = [self tabViewItemForDocument:aDocument];
    if (tabViewItem) {
        PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
        NSArray *plainTextEditors = [tabContext plainTextEditors];
//        if ([plainTextEditors count] != 1) {
//            id responder = [tabViewItem initialFirstResponder];
//            NSLog(@"%s %@ responder:%@",__FUNCTION__,aDocument,responder);
//            if ([responder isKindOfClass:[NSTextView class]]) {
//                if ([[plainTextEditors objectAtIndex:1] textView] == responder) {
//                    return [plainTextEditors objectAtIndex:1];
//                }
//            }
//        }
        if ([plainTextEditors count] > 0) {
            return [plainTextEditors objectAtIndex:0];
        }
    }
	return nil;
}


#pragma mark -

- (void)gotoLine:(unsigned)aLine {
	PlainTextEditor *activeEditor = [self activePlainTextEditor];
	[activeEditor gotoLine:aLine];
}

// selects a range of the fulltextstorage
- (void)selectRange:(NSRange)aRange {
	PlainTextEditor *activeEditor = [self activePlainTextEditor];
	[activeEditor selectRange:aRange];
}

- (void)selectRangeInBackground:(NSRange)aRange {
	PlainTextEditor *activeEditor = [self activePlainTextEditor];
	[activeEditor selectRangeInBackground:aRange];
}

#pragma mark -

- (IBAction)openInSeparateWindow:(id)sender
{
    PlainTextDocument *document = [self document];
    NSUInteger documentIndex = [[self documents] indexOfObject:document];
    NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
    
    [tabViewItem retain];
    [document retain];
    [document setKeepUndoManagerOnZeroWindowControllers:YES];
    [document removeWindowController:self];
    [self removeObjectFromDocumentsAtIndex:documentIndex];
    [I_tabView removeTabViewItem:tabViewItem];
    
    PlainTextWindowController *windowController = [[[PlainTextWindowController alloc] init] autorelease];
    
    NSRect contentRect = [[self window] contentRectForFrameRect:[[self window] frame]];
    NSRect frame = [[windowController window] frameRectForContentRect:contentRect];
    NSPoint cascadedTopLeft = [[self window] cascadeTopLeftFromPoint:NSZeroPoint];
    frame.origin.x = cascadedTopLeft.x;
    frame.origin.y = cascadedTopLeft.y - NSHeight(frame);
    NSScreen *screen = [[self window] screen];
    if (screen) {
        NSRect visibleFrame = [screen visibleFrame];
        if (NSHeight(frame) > NSHeight(visibleFrame)) {
            CGFloat heightDiff = frame.size.height - visibleFrame.size.height;
            frame.origin.y += heightDiff;
            frame.size.height -= heightDiff;
        }
        if (NSMinY(frame) < NSMinY(visibleFrame)) {
            CGFloat positionDiff = NSMinY(visibleFrame) - NSMinY(frame);
            frame.origin.y += positionDiff;
        }
    }
    [[windowController window] setFrame:frame display:YES];

    [[DocumentController sharedInstance] addWindowController:windowController];
    [windowController insertObject:document inDocumentsAtIndex:[[windowController documents] count]];
    [document addWindowController:windowController];
    [document setKeepUndoManagerOnZeroWindowControllers:NO];
    [[windowController tabView] addTabViewItem:tabViewItem];
    [[windowController tabView] selectTabViewItem:tabViewItem];

    [tabViewItem release];
    [document release];
    [[[tabViewItem identifier] dialogSplitView] setDelegate:windowController];
    [[[tabViewItem identifier] editorSplitView] setDelegate:windowController];
    [windowController setDocument:document];
    [windowController showWindow:self];

	PlainTextEditor *editor = [[self plainTextEditors] lastObject];
    if (editor.hasBottomOverlayView) {
        [windowController openParticipantsOverlay:self];
    }
}

- (BOOL)showsBottomStatusBar {
    return [[I_plainTextEditors lastObject] showsBottomStatusBar];
}

- (void)setShowsBottomStatusBar:(BOOL)aFlag {
    BOOL showsBottomStatusBar=[self showsBottomStatusBar];
    if (showsBottomStatusBar!=aFlag) {
        [[I_plainTextEditors lastObject] setShowsBottomStatusBar:aFlag];
        [[self document] setShowsBottomStatusBar:aFlag];
    }
}

- (IBAction)openParticipantsOverlay:(id)aSender {

	PlainTextEditor *editor = [[self plainTextEditors] lastObject];
	if (editor) {
		NSTabViewItem *tab = [I_tabView selectedTabViewItem];
        PlainTextWindowControllerTabContext *context = (PlainTextWindowControllerTabContext *)[tab identifier];
		SEEParticipantsOverlayViewController *participantsOverlay = [[[SEEParticipantsOverlayViewController alloc] initWithTabContext:context] autorelease];
		[editor displayViewControllerInBottomArea:participantsOverlay];
	}
	
	// just for now
	editor = self.activePlainTextEditor;
	[editor toggleFindAndReplace:self];
}

- (IBAction)closeParticipantsOverlay:(id)aSender {
	PlainTextEditor *editor = [[self plainTextEditors] lastObject];
	if (editor) {
		[editor displayViewControllerInBottomArea:nil];
	}
}

- (IBAction)toggleParticipantsOverlay:(id)sender {
	PlainTextEditor *editor = [[self plainTextEditors] lastObject];
	if (editor) {
		if (editor.hasBottomOverlayView) {
			[editor displayViewControllerInBottomArea:nil];
		} else {
			NSTabViewItem *tab = [I_tabView selectedTabViewItem];
			PlainTextWindowControllerTabContext *context = (PlainTextWindowControllerTabContext *)[tab identifier];
			SEEParticipantsOverlayViewController *participantsOverlay = [[[SEEParticipantsOverlayViewController alloc] initWithTabContext:context] autorelease];
			[editor displayViewControllerInBottomArea:participantsOverlay];
		}
	}
}

- (IBAction)changePendingUsersAccess:(id)aSender {
    [(PlainTextDocument *)[self document] changePendingUsersAccess:aSender];
}

- (IBAction)toggleBottomStatusBar:(id)aSender {
    [self setShowsBottomStatusBar:![self showsBottomStatusBar]];
    [(PlainTextDocument *)[self document] setShowsBottomStatusBar:[self showsBottomStatusBar]];
}

- (BOOL)showsGutter {
    return [[I_plainTextEditors objectAtIndex:0] showsGutter];
}

- (void)setShowsGutter:(BOOL)aFlag {
    for (id loopItem in I_plainTextEditors) {
        [loopItem setShowsGutter:aFlag];
    }
    [[self document] setShowsGutter:aFlag];
}

- (IBAction)toggleLineNumbers:(id)aSender {
    [self setShowsGutter:![self showsGutter]];
}


- (IBAction)jumpToNextSymbol:(id)aSender {
    [[self activePlainTextEditor] jumpToNextSymbol:aSender];
}

- (IBAction)jumpToPreviousSymbol:(id)aSender {
    [[self activePlainTextEditor] jumpToPreviousSymbol:aSender];
}


- (IBAction)jumpToNextChange:(id)aSender {
    [[self activePlainTextEditor] jumpToNextChange:aSender];
}

- (IBAction)jumpToPreviousChange:(id)aSender {
    [[self activePlainTextEditor] jumpToPreviousChange:aSender];
}


- (IBAction)copyDocumentURL:(id)aSender {

    NSURL *documentURL = [[self document] documentURL];    
    
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSArray *pbTypes = [NSArray arrayWithObjects:NSStringPboardType, NSURLPboardType, @"CorePasteboardFlavorType 0x75726C20", @"CorePasteboardFlavorType 0x75726C6E", nil];
    [pboard declareTypes:pbTypes owner:self];
    const char *dataUTF8 = [[documentURL absoluteString] UTF8String];
    [pboard setData:[NSData dataWithBytes:dataUTF8 length:strlen(dataUTF8)] forType:@"CorePasteboardFlavorType 0x75726C20"];
    dataUTF8 = [[[self document] displayName] UTF8String];
    [pboard setData:[NSData dataWithBytes:dataUTF8 length:strlen(dataUTF8)] forType:@"CorePasteboardFlavorType 0x75726C6E"];
    [pboard setString:[documentURL absoluteString] forType:NSStringPboardType];
    [documentURL writeToPasteboard:pboard];
}

#pragma mark -


- (IBAction)toggleShowInvisibleCharacters:(id)aSender {
    [[self activePlainTextEditor] setShowsInvisibleCharacters:![[self activePlainTextEditor] showsInvisibleCharacters]];
}

- (IBAction)toggleShowsChangeMarks:(id)aSender {
    [[self activePlainTextEditor] toggleShowsChangeMarks:aSender];
}

#pragma mark -

- (void)sessionWillChange:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TCMMMSessionParticipantsDidChangeNotification object:[(PlainTextDocument *)[self document] session]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TCMMMSessionPendingUsersDidChangeNotification object:[(PlainTextDocument *)[self document] session]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TCMMMSessionDidChangeNotification object:[(PlainTextDocument *)[self document] session]];
}

- (void)sessionDidChange:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(participantsDidChange:)
                                                 name:TCMMMSessionParticipantsDidChangeNotification 
                                               object:[(PlainTextDocument *)[self document] session]];

    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(pendingUsersDidChange:)
                                                 name:TCMMMSessionPendingUsersDidChangeNotification 
                                               object:[(PlainTextDocument *)[self document] session]];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(MMSessionDidChange:)
                                                 name:TCMMMSessionDidChangeNotification 
                                               object:[(PlainTextDocument *)[self document] session]];
                                                       
    BOOL isEditable=[(PlainTextDocument *)[self document] isEditable];
    NSEnumerator *plainTextEditors=[[self plainTextEditors] objectEnumerator];
    PlainTextEditor *editor=nil;
    while ((editor=[plainTextEditors nextObject])) {
        [[editor textView] setEditable:isEditable];
    }
}

- (void)MMSessionDidChange:(NSNotification *)aNotifcation {
    [self synchronizeWindowTitleWithDocumentName];
}


- (void)participantsDataDidChange:(NSNotification *)aNotifcation {
}

- (void)participantsDidChange:(NSNotification *)aNotifcation {
    [self synchronizeWindowTitleWithDocumentName]; // update the lock
    [self refreshDisplay];
}

- (void)pendingUsersDidChange:(NSNotification *)aNotifcation {
    [self synchronizeWindowTitleWithDocumentName];
}

- (void)displayNameDidChange:(NSNotification *)aNotification {
    [self synchronizeWindowTitleWithDocumentName];
}

- (void)refreshDisplay {
    NSEnumerator *plainTextEditors=[[self plainTextEditors] objectEnumerator];
    PlainTextEditor *editor=nil;
    while ((editor=[plainTextEditors nextObject])) {
        [[editor textView] setNeedsDisplay:YES];
    }
}

#pragma mark -

- (void)updateLock {
    BOOL showLock=NO;
    PlainTextDocument *document = (PlainTextDocument *)[self document];
    TCMMMSession *session = [document session];
    showLock = [session isSecure] && ([document isAnnounced] || [session participantCount] + [session openInvitationCount]>1);
    [I_lockImageView setHidden:!showLock];
}

- (void)synchronizeWindowTitleWithDocumentName {
    [super synchronizeWindowTitleWithDocumentName];
    [self updateForPortMapStatus];
    [self updateLock];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName document:(PlainTextDocument *)document {
    TCMMMSession *session = [document session];
    
	NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
    if (tabViewItem) [tabViewItem setLabel:displayName];

    if ([[document ODBParameters] objectForKey:@"keyFileCustomPath"]) {
        displayName = [[document ODBParameters] objectForKey:@"keyFileCustomPath"];
    } else {
        NSArray *pathComponents = [[document fileURL] pathComponents];
        int count = [pathComponents count];
        if (count != 0) {
            NSMutableString *result = [NSMutableString string];
            int i = 0;
            int pathComponentsToShow = [[NSUserDefaults standardUserDefaults] integerForKey:AdditionalShownPathComponentsPreferenceKey] + 1;
            for (i = count-1; i >= 1 && i > count-pathComponentsToShow-1; i--) {
                if (i != count-1) {
                    [result insertString:@"/" atIndex:0];
                }
                [result insertString:[pathComponents objectAtIndex:i] atIndex:0];
            }
            if (pathComponentsToShow>1 && i<1 && [[pathComponents objectAtIndex:0] isEqualToString:@"/"]) {
                [result insertString:@"/" atIndex:0];
            }
            displayName = result;
        } else {
            if (session && ![session isServer]) {
                displayName = [session filename];
            }
        }
    }

    if (session && ![session isServer]) {
        displayName = [displayName stringByAppendingFormat:@" - %@", [[[TCMMMUserManager sharedInstance] userForUserID:[session hostID]] name]];
        if ([document fileURL]) {
            if (![[[session filename] lastPathComponent] isEqualToString:[[document fileURL] lastPathComponent]]) {
                displayName = [displayName stringByAppendingFormat:@" (%@)", [session filename]];
            }
            displayName = [displayName stringByAppendingString:@" *"];
        }
    }
    
    NSUInteger requests;
    if ((requests=[[[(PlainTextDocument *)[self document] session] pendingUsers] count])>0) {
        displayName=[displayName stringByAppendingFormat:@" (%@)", [NSString stringWithFormat:NSLocalizedString(@"%d pending", @"Pending Users Display in Menu Title Bar"), requests]];
    }

    NSString *jobDescription = [(PlainTextDocument *)[self document] jobDescription];
    if (jobDescription && [jobDescription length] > 0) {
        displayName = [displayName stringByAppendingFormat:@" [%@]", jobDescription];
    }
    
    NSArray *windowControllers=[document windowControllers];
    if ([windowControllers count]>1) {
        displayName = [displayName stringByAppendingFormat:@" - %lu/%lu",
                        [windowControllers indexOfObject:self]+1,
                        (unsigned long)[windowControllers count]];
    }
    
    return displayName;
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName {
    return [self windowTitleForDocumentDisplayName:displayName document:(PlainTextDocument *)[self document]];
}

#pragma mark -

#define SPLITMINHEIGHTTEXT   46.
#define SPLITMINHEIGHTDIALOG 95.

-(void)splitView:(NSSplitView *)aSplitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    CGFloat splitminheight = (aSplitView==I_dialogSplitView) ? SPLITMINHEIGHTDIALOG : SPLITMINHEIGHTTEXT;
    if (aSplitView != I_dialogSplitView) {
        NSRect frame=[aSplitView bounds];
        NSArray *subviews=[aSplitView subviews];
        NSRect frametop=[[subviews objectAtIndex:0] frame];
        NSRect framebottom=[[subviews objectAtIndex:1] frame];
        CGFloat newHeight1=frame.size.height-[aSplitView dividerThickness];
        CGFloat topratio=frametop.size.height/(oldSize.height-[aSplitView dividerThickness]);
        frametop.size.height=(CGFloat)((int)(newHeight1*topratio));
        if (frametop.size.height<splitminheight) {
            frametop.size.height=splitminheight;
        } else if (newHeight1-frametop.size.height<splitminheight) {
            frametop.size.height=newHeight1-splitminheight;
        }
    
        framebottom.size.height=newHeight1-frametop.size.height;
        framebottom.size.width=frametop.size.width=frame.size.width;
        
        frametop.origin.x=framebottom.origin.x=frame.origin.x;
        frametop.origin.y=frame.origin.y;
        framebottom.origin.y=frame.origin.y+[aSplitView dividerThickness]+frametop.size.height;
        
        [[subviews objectAtIndex:0] setFrame:frametop];
        [[subviews objectAtIndex:1] setFrame:framebottom];
    } else {
        // just keep the height of the first view (dialog)
        NSView *view2 = [[aSplitView subviews] objectAtIndex:1];
        NSSize newSize = [aSplitView bounds].size;
        NSSize frameSize = [view2 frame].size;
        frameSize.height += newSize.height - oldSize.height;
        if (frameSize.height <= splitminheight) {
            frameSize.height = splitminheight;
        }
        [view2 setFrameSize:frameSize];
        [aSplitView adjustSubviews];
    }
}

- (BOOL)splitView:(NSSplitView *)aSplitView canCollapseSubview:(NSView *)aView {
    return NO;
}

- (CGFloat)splitView:(NSSplitView *)aSplitView constrainSplitPosition:(CGFloat)proposedPosition 
       ofSubviewAt:(NSInteger)offset {

    CGFloat height=[aSplitView frame].size.height;
    CGFloat minHeight=(aSplitView==I_dialogSplitView) ? SPLITMINHEIGHTDIALOG : SPLITMINHEIGHTTEXT;;
    if (proposedPosition<minHeight) {
        return minHeight;
    } else if (proposedPosition+minHeight+[aSplitView dividerThickness]>height) {
        return height-minHeight-[aSplitView dividerThickness];
    } else {
        return proposedPosition;
    }
}

- (id)documentDialog {
    return I_documentDialog;
}

- (void)documentDialogFadeInTimer:(NSTimer *)aTimer {
    NSMutableDictionary *info = [aTimer userInfo];
    NSTimeInterval timeInterval     = [[[aTimer userInfo] objectForKey:@"stop"] 
                                        timeIntervalSinceDate:[[aTimer userInfo] objectForKey:@"start"]];
    NSTimeInterval timeSinceStart   = [[[aTimer userInfo] objectForKey:@"start"] timeIntervalSinceNow] * -1.;
//    NSLog(@"sinceStart: %f, timeInterval: %f, %@ %@",timeSinceStart,timeInterval,[[aTimer userInfo] objectForKey:@"stop"],[[aTimer userInfo] objectForKey:@"start"]);
    CGFloat factor = timeSinceStart / timeInterval;
    if (factor > 1.) factor = 1.;
    if (![[info objectForKey:@"type"] isEqualToString:@"BlindDown"]) {
        factor = 1.-factor;
    }
    // make transition sinoidal
    factor = (-cos(factor*M_PI)/2.)+0.5;
    
    
    NSView *dialogView = [[I_dialogSplitView subviews] objectAtIndex:0];
    NSRect targetFrame = [dialogView frame];
    CGFloat newHeight = (int)(factor * [[info objectForKey:@"targetHeight"] floatValue]);
    CGFloat difference = newHeight - targetFrame.size.height;
    targetFrame.size.height = newHeight;
    [dialogView setFrame:targetFrame];
    NSView *contentView = [[I_dialogSplitView subviews] objectAtIndex:1];
    NSRect contentFrame = [contentView frame];
    contentFrame.size.height -= difference;
    [contentView setFrame:contentFrame];
    [I_dialogSplitView setNeedsDisplay:YES];
    
    if (timeSinceStart >= timeInterval) {
        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:[self document]];
        if (![[info objectForKey:@"type"] isEqualToString:@"BlindDown"]) {
            NSTabViewItem *tab = [I_tabView selectedTabViewItem];
            [tab setView:[[I_dialogSplitView subviews] objectAtIndex:1]];
            I_dialogSplitView = nil;
            
            if (tabViewItem) [[tabViewItem identifier] setDialogSplitView:nil];

            NSSize minSize = [[self window] contentMinSize];
            minSize.height -= 100;
            minSize.width -= 63;
            [[self window] setContentMinSize:minSize];
            if (tabViewItem) [[tabViewItem identifier] setDocumentDialog:nil];
            I_documentDialog = nil;
            [[self window] makeFirstResponder:[[self activePlainTextEditor] textView]];
        } else {
            if (tabViewItem) [[self window] makeFirstResponder:[[self documentDialog] initialFirstResponder]];
        }
        [dialogView setAutoresizesSubviews:YES];
        [I_dialogAnimationTimer invalidate];
        [I_dialogAnimationTimer autorelease];
        I_dialogAnimationTimer = nil;
    }
}

- (void)setDocumentDialog:(id)aDocumentDialog {
    [aDocumentDialog setDocument:[self document]];
    if (aDocumentDialog) {
        if (!I_dialogSplitView) {
            NSTabViewItem *tab = [self tabViewItemForDocument:[self document]];

            //NSView *contentView = [[[self window] contentView] retain];
            NSView *tabItemView = [[tab view] retain];
            NSView *dialogView = [aDocumentDialog mainView];
            //I_dialogSplitView = [[SplitView alloc] initWithFrame:[contentView frame]];
            I_dialogSplitView = [[[SplitView alloc] initWithFrame:[tabItemView frame]] autorelease];
            
            [[tab identifier] setDialogSplitView:I_dialogSplitView];

            [(SplitView *)I_dialogSplitView setDividerThickness:3.];
            NSRect mainFrame = [dialogView frame];
            //[[self window] setContentView:I_dialogSplitView];
            [tab setView:I_dialogSplitView];

            [I_dialogSplitView setDelegate:self];
            [I_dialogSplitView addSubview:dialogView];
            mainFrame.size.width = [I_dialogSplitView frame].size.width;
            [dialogView setFrame:mainFrame];
            CGFloat targetHeight = mainFrame.size.height;
            [dialogView resizeSubviewsWithOldSize:mainFrame.size];
            mainFrame.size.height = 0;
            [dialogView setAutoresizesSubviews:NO];
            [dialogView setFrame:mainFrame];
            //[I_dialogSplitView addSubview:[contentView autorelease]];
            [I_dialogSplitView addSubview:[tabItemView autorelease]];
            NSSize minSize = [[self window] contentMinSize];
            minSize.height+=100;
            minSize.width+=63;
            [[self window] setContentMinSize:minSize];
            I_dialogAnimationTimer = [[NSTimer scheduledTimerWithTimeInterval:0.01 
                target:self 
                selector:@selector(documentDialogFadeInTimer:) 
                userInfo:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                            [NSDate dateWithTimeIntervalSinceNow:0.20], @"stop", 
                            [NSDate date], @"start",
                            [NSNumber numberWithFloat:targetHeight],@"targetHeight",
                            @"BlindDown",@"type",nil] 
                repeats:YES] retain];
        } else {
            NSRect frame = [[[I_dialogSplitView subviews] objectAtIndex:0] frame];
            [[[I_dialogSplitView subviews] objectAtIndex:0] removeFromSuperviewWithoutNeedingDisplay];
            [I_dialogSplitView addSubview:[aDocumentDialog mainView] positioned:NSWindowBelow relativeTo:[[I_dialogSplitView subviews] objectAtIndex:0]];
            [[aDocumentDialog mainView] setFrame:frame];
            [I_dialogSplitView setNeedsDisplay:YES];
        }
        //[I_documentDialog autorelease];
        //I_documentDialog = [aDocumentDialog retain];
    
        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:[self document]];
         if (tabViewItem) {
            [[tabViewItem identifier] setDocumentDialog:aDocumentDialog];
            I_documentDialog = aDocumentDialog;
        }
    } else if (!aDocumentDialog && I_dialogSplitView) {
        [[[I_dialogSplitView subviews] objectAtIndex:0] setAutoresizesSubviews:NO];
        I_dialogAnimationTimer = [[NSTimer scheduledTimerWithTimeInterval:0.01 
            target:self 
            selector:@selector(documentDialogFadeInTimer:) 
            userInfo:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                        [NSDate dateWithTimeIntervalSinceNow:0.20], @"stop", 
                        [NSDate date], @"start",
                        [NSNumber numberWithFloat:[[[I_dialogSplitView subviews] objectAtIndex:0] frame].size.height],@"targetHeight",
                        @"BlindUp",@"type",nil] 
            repeats:YES] retain];
    }
}

- (IBAction)toggleDialogView:(id)aSender {
    [self setDocumentDialog:[[[EncodingDoctorDialog alloc] initWithEncoding:NSASCIIStringEncoding] autorelease]];
}

- (IBAction)toggleSplitView:(id)aSender {
    if ([I_plainTextEditors count] == 1) {
        NSTabViewItem *tab = [I_tabView selectedTabViewItem];

        PlainTextWindowControllerTabContext *context = (PlainTextWindowControllerTabContext *)[tab identifier];
        PlainTextEditor *plainTextEditor = [[PlainTextEditor alloc] initWithWindowControllerTabContext:context splitButton:NO];
        [I_plainTextEditors addObject:plainTextEditor];
        [plainTextEditor release];

        I_editorSplitView = [[[SplitView alloc] initWithFrame:[[[I_plainTextEditors objectAtIndex:0] editorView] frame]] autorelease];
        [context setEditorSplitView:I_editorSplitView];

        if (!I_dialogSplitView) {
            [tab setView:I_editorSplitView];
        } else {
            [I_dialogSplitView addSubview:I_editorSplitView positioned:NSWindowBelow relativeTo:[[I_dialogSplitView subviews] objectAtIndex:1]];
        }

        NSSize splitSize = [I_editorSplitView frame].size;
        splitSize.height = splitSize.height / 2.;

        [[[I_plainTextEditors objectAtIndex:0] editorView] setFrameSize:splitSize];
        [[[I_plainTextEditors objectAtIndex:1] editorView] setFrameSize:splitSize];

        [I_editorSplitView addSubview:[[I_plainTextEditors objectAtIndex:0] editorView]];
        [I_editorSplitView addSubview:[[I_plainTextEditors objectAtIndex:1] editorView]];
        [I_editorSplitView setDelegate:self];

		[[I_plainTextEditors objectAtIndex:1] setShowsBottomStatusBar: [[I_plainTextEditors objectAtIndex:0] showsBottomStatusBar]];
        [[I_plainTextEditors objectAtIndex:0] setShowsBottomStatusBar:NO];
		[[I_plainTextEditors objectAtIndex:1] setShowsGutter:[[I_plainTextEditors objectAtIndex:0] showsGutter]];

		[self setInitialRadarStatusForPlainTextEditor:[I_plainTextEditors objectAtIndex:1]];

		// show participant overlay if split gets toggled
		if ([[I_plainTextEditors objectAtIndex:0] hasBottomOverlayView]) {
			[[I_plainTextEditors objectAtIndex:0] displayViewControllerInBottomArea:nil];
			SEEParticipantsOverlayViewController *participantsOverlay = [[[SEEParticipantsOverlayViewController alloc] initWithTabContext:context] autorelease];
			[[I_plainTextEditors objectAtIndex:1] displayViewControllerInBottomArea:participantsOverlay];
		}

    } else if ([I_plainTextEditors count] == 2) {
		//Preserve scroll position of second editor, if it is currently the selected one.
        id fr = [[self window] firstResponder];
        NSRect visibleRect = NSZeroRect;
        if (fr == [[I_plainTextEditors objectAtIndex:1] textView]) {
            visibleRect = [[[I_plainTextEditors objectAtIndex:1] textView] visibleRect];
            [[[I_plainTextEditors objectAtIndex:0] textView] setSelectedRange:[[[I_plainTextEditors objectAtIndex:1] textView] selectedRange]];
        }

        if (! I_dialogSplitView) {
            NSTabViewItem *tab = [I_tabView selectedTabViewItem];
            [tab setView:[[I_plainTextEditors objectAtIndex:0] editorView]];
            [tab setInitialFirstResponder:[[I_plainTextEditors objectAtIndex:0] editorView]];
        } else {
            NSView *editorView = [[I_plainTextEditors objectAtIndex:0] editorView];
            [editorView setFrame:[I_editorSplitView frame]];
            [I_dialogSplitView addSubview:[[I_plainTextEditors objectAtIndex:0] editorView] positioned:NSWindowBelow relativeTo:I_editorSplitView];
            [I_editorSplitView removeFromSuperview];
        }

        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:[self document]];
        if (tabViewItem) {
			[[tabViewItem identifier] setEditorSplitView:nil];
		}

		PlainTextEditor *editorToClose = [I_plainTextEditors objectAtIndex:1];
		
		// show participant overlay if split gets toggled
 		if ([editorToClose hasBottomOverlayView]) {
			[editorToClose displayViewControllerInBottomArea:nil];
			SEEParticipantsOverlayViewController *participantsOverlay = [[[SEEParticipantsOverlayViewController alloc] initWithTabContext:[tabViewItem identifier]] autorelease];
			[[I_plainTextEditors objectAtIndex:0] displayViewControllerInBottomArea:participantsOverlay];
		}

		[[I_plainTextEditors objectAtIndex:0] setShowsBottomStatusBar:[editorToClose showsBottomStatusBar]];
		[editorToClose prepareForDealloc];
        [I_plainTextEditors removeObjectAtIndex:1];
        I_editorSplitView = nil;

		// restore scroll position of second editor if it was the selected one
        if (!NSEqualRects(NSZeroRect,visibleRect)) {
            [[[I_plainTextEditors objectAtIndex:0] textView] scrollRectToVisible:visibleRect];
        }
    }

    [[I_plainTextEditors objectAtIndex:0] setIsSplit:[I_plainTextEditors count] != 1];

    NSTextView *textView = [[I_plainTextEditors objectAtIndex:0] textView];
    NSRange selectedRange = [textView selectedRange];
    [textView scrollRangeToVisible:selectedRange];

    if ([I_plainTextEditors count] == 2) {
        [[[I_plainTextEditors objectAtIndex:1] textView] scrollRangeToVisible:selectedRange];
    }
    [[self window] makeFirstResponder:textView];
}

#pragma mark -
#pragma mark ### window delegation  ###

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame {
    if (!([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)) {
        NSRect windowFrame=[[self window] frame];
        I_flags.zoomFix_defaultFrameHadEqualWidth = (defaultFrame.size.width==windowFrame.size.width);
        defaultFrame.size.width=windowFrame.size.width;
        defaultFrame.origin.x=windowFrame.origin.x;
    }
    return defaultFrame;
}

- (BOOL)windowShouldZoom:(NSWindow *)sender toFrame:(NSRect)newFrame {
  return [sender frame].size.width == newFrame.size.width || ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) || I_flags.zoomFix_defaultFrameHadEqualWidth;
}

- (void)windowDidBecomeMain:(NSNotification *)aNotification {
    [self updateLock];
    // switch mode menu on becoming main
    [(PlainTextDocument *)[self document] adjustModeMenu];
    // also make sure the tab menu is updated correctly
    [[DocumentController sharedInstance] updateTabMenu];
    
    NSTabViewItem *tabViewItem = [I_tabView selectedTabViewItem];
    if (tabViewItem) {
        PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
        if ([tabContext isAlertScheduled]) {
            [[tabContext document] presentScheduledAlertForWindow:[self window]];
            [tabContext setIsAlertScheduled:NO];
        }
    }
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    NSMenu *fileMenu = [[[NSApp mainMenu] itemWithTag:FileMenuTag] submenu];
    NSInteger index = [fileMenu indexOfItemWithTarget:nil andAction:@selector(closeTab:)];
    if (index) {
        NSMenuItem *item = [fileMenu itemAtIndex:index];
        [item setKeyEquivalent:@"w"];
        [item setKeyEquivalentModifierMask:NSCommandKeyMask];
    }
    index = [fileMenu indexOfItemWithTarget:nil andAction:@selector(performClose:)];
    if (index) {
        NSMenuItem *item = [fileMenu itemAtIndex:index];
        [item setKeyEquivalent:@"W"];
    }
    index = [fileMenu indexOfItemWithTarget:nil andAction:@selector(closeAllDocuments:)];
    if (index) {
        NSMenuItem *item = [fileMenu itemAtIndex:index];
        [item setKeyEquivalent:@"W"];
        [item setKeyEquivalentModifierMask:NSShiftKeyMask | NSAlternateKeyMask | NSCommandKeyMask];
    }
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    NSMenu *fileMenu = [[[NSApp mainMenu] itemWithTag:FileMenuTag] submenu];
    NSInteger index = [fileMenu indexOfItemWithTarget:nil andAction:@selector(closeTab:)];
    if (index) {
        NSMenuItem *item = [fileMenu itemAtIndex:index];
        [item setKeyEquivalent:@""];
    }
    index = [fileMenu indexOfItemWithTarget:nil andAction:@selector(performClose:)];
    if (index) {
        NSMenuItem *item = [fileMenu itemAtIndex:index];
        [item setKeyEquivalent:@"w"];
    }
    index = [fileMenu indexOfItemWithTarget:nil andAction:@selector(closeAllDocuments:)];
    if (index) {
        NSMenuItem *item = [fileMenu itemAtIndex:index];
        [item setKeyEquivalent:@"w"];
        [item setKeyEquivalentModifierMask:NSAlternateKeyMask | NSCommandKeyMask];
    }
}

#pragma mark -

- (void)cascadeWindow {
    NSWindow *window = [self window];
    S_cascadePoint = [window cascadeTopLeftFromPoint:S_cascadePoint];
    [window setFrameTopLeftPoint:S_cascadePoint];
}

- (IBAction)showWindow:(id)aSender {
    if (![[self window] isVisible] && !I_doNotCascade) {
    	[self cascadeWindow];
    }
    [super showWindow:aSender];
    
    if (!I_lockImageView) {
        id superview = [[[self window] standardWindowButton:NSWindowToolbarButton] superview];
        NSRect toolbarButtonFrame = [[[self window] standardWindowButton:NSWindowToolbarButton] frame];
        NSImage *lockImage = [NSImage imageNamed:@"LockTitlebar"];
        NSRect iconFrame = toolbarButtonFrame;
    
        iconFrame.size = [lockImage size];
        iconFrame.origin.x =NSMinX(toolbarButtonFrame) - iconFrame.size.width - 3.;
        iconFrame.origin.y =NSMaxY(toolbarButtonFrame) - iconFrame.size.height + 1.;

        if (superview) {
            
            I_lockImageView = [[NSImageView alloc] initWithFrame:iconFrame];
            [I_lockImageView setEditable:NO];
            [I_lockImageView setImageFrameStyle:NSImageFrameNone];
            [I_lockImageView setImageScaling:NSScaleNone];
            [I_lockImageView setImageAlignment:NSImageAlignCenter];
            [I_lockImageView setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
            [superview addSubview:I_lockImageView];
            [I_lockImageView release];
            [I_lockImageView setImage:lockImage];
            [I_lockImageView setToolTip:NSLocalizedString(@"All participants of this document are connected using secure connections",@"Tooltip for ssl lock at top of the window")];
        }
        }
    [self updateLock];

}

- (NSRect)dissolveToFrame {
	if ([self hasManyDocuments]) {
	 	NSWindow *window = [self window];
		 NSRect bounds = [[I_tabBar performSelector:@selector(lastVisibleTab)] frame];
		 bounds = [[window contentView] convertRect:bounds fromView:I_tabBar];
		 bounds.size.height += 25.;
		 bounds.origin.y -= 32.;
		 bounds = NSInsetRect(bounds,-8.,-9.);
		 bounds.origin.x +=1;
		 NSPoint point1 = bounds.origin;
		 NSPoint point2 = NSMakePoint(NSMaxX(bounds),NSMaxY(bounds));
		 point1 = [window convertBaseToScreen:point1];
		 point2 = [window convertBaseToScreen:point2];
		 bounds = NSMakeRect(MIN(point1.x,point2.x),MIN(point1.y,point2.y),ABS(point1.x-point2.x),ABS(point1.y-point2.y));
		 return bounds;
	 } else {
	 	return NSOffsetRect(NSInsetRect([[self window] frame],-9.,-9.),0.,-4.);
	 }
}

- (void)documentUpdatedChangeCount:(PlainTextDocument *)document
{
    NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
    if (tabViewItem) {
        PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
        if ([tabContext isEdited] != [document isDocumentEdited])
            [tabContext setIsEdited:[document isDocumentEdited]];
    }
}

- (void)moveAllTabsToWindowController:(PlainTextWindowController *)windowController
{
    PlainTextDocument *document;
    for (document in I_documents)
    {
        NSUInteger documentIndex = [[self documents] indexOfObject:document];
        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
        
        [tabViewItem retain];
        [document retain];
	    [document setKeepUndoManagerOnZeroWindowControllers:YES];
        [document removeWindowController:self];
        [self removeObjectFromDocumentsAtIndex:documentIndex];
        [I_tabView removeTabViewItem:tabViewItem];

        if (![[windowController documents] containsObject:document]) {
            [windowController insertObject:document inDocumentsAtIndex:[[windowController documents] count]];
            [document addWindowController:windowController];
            [[windowController tabView] addTabViewItem:tabViewItem];
            [[[tabViewItem identifier] dialogSplitView] setDelegate:windowController];
            [[[tabViewItem identifier] editorSplitView] setDelegate:windowController];
        }

        [tabViewItem release];
	    [document setKeepUndoManagerOnZeroWindowControllers:NO];
        [document release];

		PlainTextEditor *editor = [[self plainTextEditors] lastObject];
		if (editor.hasBottomOverlayView) {
			[windowController openParticipantsOverlay:self];
		}

        [[windowController tabBar] hideTabBar:NO animate:YES];
    }
}

- (BOOL)hasManyDocuments
{
    return [[self documents] count] > 1;
}

- (PSMTabBarControl *)tabBar
{
	return I_tabBar;
}

- (NSTabView *)tabView
{
    return I_tabView;
}

- (IBAction)selectNextTab:(id)sender
{
    NSTabViewItem *item = [I_tabView selectedTabViewItem];
    [I_tabView selectNextTabViewItem:self];
    if ([item isEqual:[I_tabView selectedTabViewItem]]) {
        [I_tabView selectFirstTabViewItem:self];
    }
}

- (IBAction)selectPreviousTab:(id)sender
{
    NSTabViewItem *item = [I_tabView selectedTabViewItem];
    [I_tabView selectPreviousTabViewItem:self];
    if ([item isEqual:[I_tabView selectedTabViewItem]]) {
        [I_tabView selectLastTabViewItem:self];
    }
}

- (IBAction)showDocumentAtIndex:(id)aMenuEntry {
    int documentNumberToShow = [[aMenuEntry representedObject] intValue];
    NSArray *documents = [self orderedDocuments];
    if ([documents count] > documentNumberToShow) {
        id document = [documents objectAtIndex:documentNumberToShow];
        [self selectTabForDocument:document];
        [self showWindow:nil];
        [document showWindows];
    }
}

- (NSArray *)plainTextEditorsForDocument:(id)aDocument
{
    NSMutableArray *editors = [NSMutableArray array];
    unsigned count = [[self documents] count];
    unsigned i;
    for (i = 0; i < count; i++) {
        PlainTextDocument *document = [[self documents] objectAtIndex:i];
        if ([document isEqual:aDocument]) {
            NSTabViewItem *tabViewItem = [self tabViewItemForDocument:document];
            if (tabViewItem) {
                PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
                [editors addObjectsFromArray:[tabContext plainTextEditors]];
            }
        }
    }
    
    return editors;
}

- (BOOL)selectTabForDocument:(id)aDocument {
    NSTabViewItem *tabViewItem = [self tabViewItemForDocument:aDocument];
    if (tabViewItem) {
        [I_tabView selectTabViewItem:tabViewItem];
        return YES;
    } else {
        return NO;
    }
}

- (IBAction)closeTab:(id)sender
{
    [[self document] canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:nil];
}

- (void)closeAllTabsAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [[alert window] orderOut:self];

    if (returnCode == NSAlertFirstButtonReturn) {
        [self reviewChangesAndQuitEnumeration:YES];
    } else if (returnCode == NSAlertThirdButtonReturn) {
        NSArray *documents = [self documents];
        unsigned count = [documents count];
        while (count--) {
            PlainTextDocument *document = [documents objectAtIndex:count];
            [self documentWillClose:document];
            [document close];
        }
    }
}

- (void)closeAllTabs
{
    NSArray *documents = [self documents];
    unsigned count = [documents count];
    unsigned needsSaving = 0;
    unsigned hasMultipleViews = 0;
 
    // Determine if there are any unsaved documents...

    while (count--) {
        PlainTextDocument *document = [documents objectAtIndex:count];
        if (document &&
            [document isDocumentEdited])
        {
            needsSaving++;

            if ([[document windowControllers] count] > 1)
                hasMultipleViews++;
        }
    }
    if (needsSaving > 0) {
        needsSaving -= hasMultipleViews;
        if (needsSaving > 1) {	// If we only have 1 unsaved document, we skip the "review changes?" panel
        
            NSString *title = [NSString stringWithFormat:NSLocalizedString(@"You have %d documents in this window with unsaved changes. Do you want to review these changes?", nil), needsSaving];
            
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert setMessageText:title];
            [alert setInformativeText:NSLocalizedString(@"If you don\\U2019t review your documents, all your changes will be lost.", @"Warning in the alert panel which comes up when user chooses Quit and there are unsaved documents.")];
            [alert addButtonWithTitle:NSLocalizedString(@"Review Changes\\U2026", @"Choice (on a button) given to user which allows him/her to review all unsaved documents if he/she quits the application without saving them all first.")];
            [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Button choice allowing user to cancel.")];
            [alert addButtonWithTitle:NSLocalizedString(@"Discard Changes", @"Choice (on a button) given to user which allows him/her to quit the application even though there are unsaved documents.")];
            [alert beginSheetModalForWindow:[self window]
                              modalDelegate:self
                             didEndSelector:@selector(closeAllTabsAlertDidEnd:returnCode:contextInfo:)
                                contextInfo:nil];
        } else {
            [self reviewChangesAndQuitEnumeration:YES];
        }
    } else {
        documents = [self documents];
        count = [documents count];
        while (count--) {
            PlainTextDocument *document = [documents objectAtIndex:count];
            [self documentWillClose:document];
            [document close];
        }
    }
}

- (void)reviewedDocument:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{      
    NSWindow *sheet = [[self window] attachedSheet];
    if (sheet) [sheet orderOut:self];
    
    if (shouldClose) {
        NSArray *windowControllers = [doc windowControllers];
        NSUInteger windowControllerCount = [windowControllers count];
        if (windowControllerCount > 1) {
            [self documentWillClose:doc];
            [self close];
        } else {
            [doc close];
        }
        
        if (contextInfo) ((void (*)(id, SEL, BOOL))objc_msgSend)(self, (SEL)contextInfo, YES);
    } else {
        if (contextInfo) ((void (*)(id, SEL, BOOL))objc_msgSend)(self, (SEL)contextInfo, NO);
    }
    
}

- (void)reviewChangesAndQuitEnumeration:(BOOL)cont
{
    if (cont) {
        NSArray *documents = [self documents];
        unsigned count = [documents count];
        while (count--) {
            PlainTextDocument *document = [documents objectAtIndex:count];
            if ([document isDocumentEdited] && [self selectTabForDocument:document])
			{
                [document canCloseDocumentWithDelegate:self
                                   shouldCloseSelector:@selector(reviewedDocument:shouldClose:contextInfo:)
                                           contextInfo:@selector(reviewChangesAndQuitEnumeration:)];
                return;
            }
        }
        
        documents = [self documents];
        count = [documents count];
        while (count--) {
            PlainTextDocument *document = [documents objectAtIndex:count];
            [self documentWillClose:document];
            [document close];
        }
    }
    
    // if we get to here, either cont was YES and we reviewed all documents, or cont was NO and we don't want to quit
}


#pragma mark -
#pragma mark  A Method That PlainTextDocument Invokes 


- (void)documentWillClose:(NSDocument *)document 
{
    // Record the document that's closing. We'll just remove it from our list when this object receives a -close message.
    I_documentBeingClosed = document;
}

#pragma mark  Private KVC-Compliance for Public Properties 

- (void)insertObject:(NSDocument *)document inDocumentsAtIndex:(NSUInteger)index
{
    // Instantiate the documents array lazily.
    if (!I_documents) {
        I_documents = [[NSMutableArray alloc] init];
    }
    [I_documents insertObject:document atIndex:index];
}


- (void)removeObjectFromDocumentsAtIndex:(NSUInteger)index
{
    // Instantiate the documents array lazily, if only to get a useful exception thrown.
    if (!I_documents) {
        I_documents = [[NSMutableArray alloc] init];
    }
    // Forget about the document.
    [I_documents removeObjectAtIndex:index];
}


#pragma mark Simple Property Getting 

- (NSArray *)orderedDocuments {
    NSMutableArray *result = [NSMutableArray array];
    NSEnumerator *tabViewItems = [[[self tabBar] representedTabViewItems] objectEnumerator];
    id identifier;
    while ((identifier = [[tabViewItems nextObject] identifier])) {
        id document = [identifier document];
        if ([[self documents] containsObject:document]) {
            [result addObject:document];
        }
    }
    return result;
}

- (NSArray *)documents 
{
    // Instantiate the documents array lazily.
    if (!I_documents) {
        I_documents = [[NSMutableArray alloc] init];
    }
    return I_documents;
}


#pragma mark Overrides of NSWindowController Methods 

- (NSTabViewItem *)addDocument:(NSDocument *)document {
    NSArray *documents = [self documents];
    if (![documents containsObject:document]) {
        // No. Record it, in a KVO-compliant way.
        [self insertObject:document inDocumentsAtIndex:[documents count]];
        PlainTextWindowControllerTabContext *tabContext = [[[PlainTextWindowControllerTabContext alloc] init] autorelease];
        [tabContext setDocument:(PlainTextDocument *)document];
        [tabContext setIsEdited:[(PlainTextDocument *)document isDocumentEdited]];
        
        PlainTextLoadProgress *loadProgress = [[PlainTextLoadProgress alloc] init];
        [tabContext setLoadProgress:loadProgress];
        [loadProgress release];

        PlainTextEditor *plainTextEditor = [[PlainTextEditor alloc] initWithWindowControllerTabContext:tabContext splitButton:YES];
        [[self window] setInitialFirstResponder:[plainTextEditor textView]];
                    
        [[tabContext plainTextEditors] addObject:plainTextEditor];
        I_plainTextEditors = [tabContext plainTextEditors];

        I_editorSplitView = nil;
        I_dialogSplitView = nil;

        NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:tabContext];
        [tab setLabel:[document displayName]];
        [tab setView:[plainTextEditor editorView]];
        [tab setInitialFirstResponder:[plainTextEditor textView]];
        [plainTextEditor release];
        [I_tabView addTabViewItem:tab];
        [tab release];
        if ([documents count] > 1) {
			[I_tabBar hideTabBar:NO animate:YES];
        }
        return tab;
    }
    return nil;
}

- (void)setDocument:(NSDocument *)document 
{
    if (document == [self document]) {
        [super setDocument:document];
        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:(PlainTextDocument *)document];
        if (tabViewItem) {
            PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
            I_plainTextEditors = [tabContext plainTextEditors];
            I_editorSplitView = [tabContext editorSplitView];
            I_dialogSplitView = [tabContext dialogSplitView];
        } 
        return;
    }
	[[URLBubbleWindow sharedURLBubbleWindow] hideIfNecessary];
    
    BOOL isNew = NO;
    [super setDocument:document];
    // A document has been told that this window controller belongs to it.

    // Every document sends it window controllers -setDocument:nil when it's closed. We ignore such messages for some purposes.
    if (document) {
        // Have we already recorded this document in our list?
        NSArray *documents = [self documents];
        if (![documents containsObject:document]) {
            // No. Record it, in a KVO-compliant way.
            NSTabViewItem *tab = [self addDocument:document];
            [I_tabView selectTabViewItem:tab];
            
            isNew = [I_tabView numberOfTabViewItems] == 1 ? YES : NO;
        } else {
			// document is already there
            NSTabViewItem *tabViewItem = [self tabViewItemForDocument:(PlainTextDocument *)document];
            if (tabViewItem) {
                PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
                I_plainTextEditors = [tabContext plainTextEditors];
                I_editorSplitView = [tabContext editorSplitView];
                I_dialogSplitView = [tabContext dialogSplitView];
                if ([I_plainTextEditors count] > 0) {
                    [[self window] setInitialFirstResponder:[[I_plainTextEditors objectAtIndex:0] textView]];
                }
                [I_tabView selectTabViewItem:tabViewItem];
            } else {
                I_plainTextEditors = nil;
                I_editorSplitView = nil;
                I_dialogSplitView = nil;
            }
        }
    } else {
        I_plainTextEditors = nil;
        I_editorSplitView = nil;
        I_dialogSplitView = nil;
        //[I_tabView selectTabViewItemAtIndex:0];
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center removeObserver:self 
                      name:PlainTextDocumentSessionWillChangeNotification
                    object:[self document]];

    [center removeObserver:self 
                      name:PlainTextDocumentSessionDidChangeNotification
                    object:[self document]];
                    
    [center removeObserver:self 
                      name:PlainTextDocumentParticipantsDataDidChangeNotification
                    object:[self document]];

    [center removeObserver:self 
                      name:TCMMMSessionParticipantsDidChangeNotification
                    object:[(PlainTextDocument *)[self document] session]];

    [center removeObserver:self 
                      name:TCMMMSessionPendingUsersDidChangeNotification 
                    object:[(PlainTextDocument *)[self document] session]];

    [center removeObserver:self 
                      name:TCMMMSessionDidChangeNotification 
                    object:[(PlainTextDocument *)[self document] session]];

    [center removeObserver:self 
                      name:PlainTextDocumentDidChangeDisplayNameNotification 
                    object:[self document]];

    [center removeObserver:self 
                      name:PlainTextDocumentDidChangeDocumentModeNotification 
                    object:[self document]];        
                                                   
    [super setDocument:document];
    
    if (document) {
        if ([[self window] isKeyWindow]) {
            [(PlainTextDocument *)document adjustModeMenu];
            [[DocumentController sharedInstance] updateTabMenu];
        }
        [self refreshDisplay];

        NSEnumerator *editors = [[self plainTextEditors] objectEnumerator];
        PlainTextEditor *editor = nil;
        while ((editor = [editors nextObject])) {
            [editor updateViews];
        }
    
        if (isNew) {            
            DocumentMode *mode = [(PlainTextDocument *)document documentMode];
            [self setSizeByColumns:[[mode defaultForKey:DocumentModeColumnsPreferenceKey] intValue] 
                              rows:[[mode defaultForKey:DocumentModeRowsPreferenceKey] intValue]];
        }
        
        [center addObserver:self 
                                                 selector:@selector(sessionWillChange:)
                                                     name:PlainTextDocumentSessionWillChangeNotification 
                                                   object:[self document]];
        [center addObserver:self 
                                                 selector:@selector(sessionDidChange:)
                                                     name:PlainTextDocumentSessionDidChangeNotification 
                                                   object:[self document]];

        [center addObserver:self 
                                                 selector:@selector(participantsDataDidChange:)
                                                     name:PlainTextDocumentParticipantsDataDidChangeNotification 
                                                   object:[self document]];

        [center addObserver:self 
                                                 selector:@selector(participantsDidChange:)
                                                     name:TCMMMSessionParticipantsDidChangeNotification 
                                                   object:[(PlainTextDocument *)[self document] session]];

        [center addObserver:self 
                                                 selector:@selector(pendingUsersDidChange:)
                                                     name:TCMMMSessionPendingUsersDidChangeNotification 
                                                   object:[(PlainTextDocument *)[self document] session]];

        [center addObserver:self 
                                                 selector:@selector(MMSessionDidChange:)
                                                     name:TCMMMSessionDidChangeNotification 
                                                   object:[(PlainTextDocument *)[self document] session]];
                                                   
        [center addObserver:self 
                                                 selector:@selector(displayNameDidChange:)
                                                     name:PlainTextDocumentDidChangeDisplayNameNotification 
                                                   object:[self document]];

        [center postNotificationName:@"PlainTextWindowControllerDocumentDidChangeNotification" object:self];
    }
}


- (void)close
{
    //NSLog(@"%s",__FUNCTION__);
    // A document is being closed, and trying to close this window controller. Is it the last document for this window controller?
    NSArray *documents = [self documents];
    NSUInteger oldDocumentCount = [documents count];
	
	PlainTextWindowControllerTabContext *contextToClose = nil;
	
    if (I_documentBeingClosed && oldDocumentCount > 1) {
        NSTabViewItem *tabViewItem = [self tabViewItemForDocument:(PlainTextDocument *)I_documentBeingClosed];
        if (tabViewItem) {
			contextToClose = [(PlainTextWindowControllerTabContext *)tabViewItem.identifier retain];
			[I_tabView removeTabViewItem:tabViewItem];
		}

        id document = nil;
        BOOL keepCurrentDocument = ![[self document] isEqual:I_documentBeingClosed];
        if (keepCurrentDocument) document = [self document];
        
        [I_documentBeingClosed removeWindowController:self];

        // There are other documents open. Just remove the document being closed from our list.
        NSUInteger documentIndex = [documents indexOfObject:I_documentBeingClosed];
        [self removeObjectFromDocumentsAtIndex:documentIndex];

        I_documentBeingClosed = nil;

        // If that was the current document (and it probably was) then pick another one. Don't forget that [self documents] has now changed.
        if (!keepCurrentDocument) {
            documents = [self documents];
            NSUInteger newDocumentCount = [documents count];
            if (documentIndex > (newDocumentCount - 1)) {
                // We closed the last document in the list. Display the new last document.
                documentIndex = newDocumentCount - 1;
            }
            document = [documents objectAtIndex:documentIndex];
        }
        [self setDocument:document];
    } else {
        // That was the last document. Do the regular NSWindowController thing.
        if ([I_documents count] > 0) {
            [[I_documents objectAtIndex:0] removeWindowController:self];
            [self removeObjectFromDocumentsAtIndex:0];
        }
        if ([I_tabView numberOfTabViewItems] > 0) {
			NSTabViewItem *tabViewItem = [I_tabView tabViewItemAtIndex:0];
			contextToClose = [(PlainTextWindowControllerTabContext *)tabViewItem.identifier retain];
			[I_tabView removeTabViewItem:tabViewItem];
		}
        [self setDocument:nil];
		
        [[DocumentController sharedDocumentController] removeWindowController:self];
        [super close];
    }
	[contextToClose.plainTextEditors makeObjectsPerformSelector:@selector(prepareForDealloc)];
	[contextToClose release];
}

#pragma mark PSMTabBarControl Delegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
    id document = [tabContext document];
    if ([[self documents] containsObject:document]) {
        [self setDocument:document];
        if ([tabContext isAlertScheduled]) {
            [document presentScheduledAlertForWindow:[self window]];
            [tabContext setIsAlertScheduled:NO];
        }
    }
}

- (void)document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{
    if (shouldClose) {
        NSArray *windowControllers = [doc windowControllers];
        NSUInteger windowControllerCount = [windowControllers count];
        if (windowControllerCount > 1) {
            [self documentWillClose:doc];
            [self close];
        } else {
            [doc close];
        }
        // updateTabMenu
        [[DocumentController sharedInstance] updateTabMenu];
    }
}

- (BOOL)tabView:(NSTabView *)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    id document = [[tabViewItem identifier] document];
    [document canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:nil];

    return NO;
}

- (BOOL)tabView:(NSTabView*)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl
{
	return YES;
}

- (BOOL)tabView:(NSTabView*)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl
{
    if ([[tabBarControl window] attachedSheet]) {
        return NO;
    }

    if (![aTabView isEqual:I_tabView]) {
        PlainTextWindowController *windowController = (PlainTextWindowController *)[[tabBarControl window] windowController];
        id document = [[tabViewItem identifier] document];
        if ([[windowController documents] containsObject:document]) {
            return NO;
        }
    }
        
	return YES;
}

- (NSImage *)tabView:(NSTabView *)aTabView imageForTabViewItem:(NSTabViewItem *)tabViewItem offset:(NSSize *)offset styleMask:(NSUInteger *)styleMask
{
	[[self window] disableFlushWindow];
    NSTabViewItem *oldItem = [aTabView selectedTabViewItem];
    [aTabView selectTabViewItem:tabViewItem];
    [aTabView display];

	// get the view chache
	NSView *contentView = [[self window] contentView];
	NSBitmapImageRep *viewCache = [contentView bitmapImageRepForCachingDisplayInRect:contentView.frame];
	[contentView cacheDisplayInRect:contentView.frame toBitmapImageRep:viewCache];

    [aTabView selectTabViewItem:oldItem];
    [aTabView display];
	[[self window] enableFlushWindow];

	NSImage *viewImage = [NSImage imageWithSize:viewCache.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
		[viewCache drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0 respectFlipped:NO hints:nil];

		//draw over where the tab bar would usually be
		NSRect tabFrame = [I_tabBar frame];
		[[NSColor clearColor] set];
		NSRectFill(tabFrame);

		//draw the background flipped, which is actually the right way up
		NSAffineTransform *transform = [NSAffineTransform transform];
		[transform scaleXBy:1.0 yBy:-1.0];
		[transform concat];
		tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
		[[((PSMTabBarControl *)[aTabView delegate]) style] drawBezelOfTabBarControl:I_tabBar inRect:tabFrame];
		[transform invert];
		[transform concat];

		return YES;
	}];

	if (offset != NULL) {
		PSMTabBarControl *tabItem = (PSMTabBarControl *)[aTabView delegate];
		if ([tabItem orientation] == PSMTabBarHorizontalOrientation) {
			offset->width = [(id <PSMTabStyle>)[tabItem style] leftMarginForTabBarControl:tabItem];
			offset->height = 24;
		} else {
			offset->width = 0;
			offset->height = 24 + [(id <PSMTabStyle>)[tabItem style] leftMarginForTabBarControl:tabItem];
		}
	}

	if (styleMask != NULL) {
		*styleMask = NSBorderlessWindowMask; //NSTitledWindowMask;
	}

	return viewImage;
}

- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point
{
	//create a new window controller with no tab items
	PlainTextWindowController *controller = [[[PlainTextWindowController alloc] init] autorelease];
	PSMTabBarControl *tabBarControl = (PSMTabBarControl *)[aTabView delegate];
    id <PSMTabStyle> style = [tabBarControl style];
    BOOL hideForSingleTab = [(PSMTabBarControl *)[aTabView delegate] hideForSingleTab];
	
	NSRect windowFrame = [[controller window] frame];
	point.y += windowFrame.size.height - [[[controller window] contentView] frame].size.height;
	point.x -= [style leftMarginForTabBarControl:tabBarControl];
	
    NSRect contentRect = [[self window] contentRectForFrameRect:[[self window] frame]];
    NSRect frame = [[controller window] frameRectForContentRect:contentRect];
    [[controller window] setFrame:frame display:NO];
            
    [[controller window] setFrameTopLeftPoint:point];
	[[controller tabBar] setStyle:style];
    [[controller tabBar] setHideForSingleTab:hideForSingleTab];
	
    [[DocumentController sharedInstance] addWindowController:controller];

	return [controller tabBar];
}

- (void)tabView:(NSTabView *)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl
{
    if ([[self window] isMainWindow]) {
        // update window menu
        [[DocumentController sharedInstance] updateTabMenu];
    }
    if (![tabBarControl isEqual:I_tabBar]) {
        
        PlainTextWindowController *windowController = (PlainTextWindowController *)[[tabBarControl window] windowController];
        id document = [[tabViewItem identifier] document];
        NSUInteger documentIndex = [[self documents] indexOfObject:document];
        [document retain];
	    [document setKeepUndoManagerOnZeroWindowControllers:YES];
        [document removeWindowController:self];
        [self removeObjectFromDocumentsAtIndex:documentIndex];
        
        if ([[self documents] count] == 0) {
            [[self retain] autorelease];
            [[DocumentController sharedInstance] removeWindowController:self];
        } else {
            [self setDocument:[[[[self tabView] selectedTabViewItem] identifier] document]];
        } 
        
        [windowController insertObject:document inDocumentsAtIndex:[[windowController documents] count]];
        [document addWindowController:windowController];
	    [document setKeepUndoManagerOnZeroWindowControllers:NO];

        [document release];
        [[[tabViewItem identifier] dialogSplitView] setDelegate:windowController];
        [[[tabViewItem identifier] editorSplitView] setDelegate:windowController];
        [windowController setDocument:document];
        
		PlainTextEditor *editor = [[self plainTextEditors] lastObject];
		if (editor.hasBottomOverlayView) {
			[windowController openParticipantsOverlay:self];
		}

        if (![windowController hasManyDocuments]) {
            [tabBarControl setHideForSingleTab:![[NSUserDefaults standardUserDefaults] boolForKey:AlwaysShowTabBarKey]];
            [tabBarControl hideTabBar:![[NSUserDefaults standardUserDefaults] boolForKey:AlwaysShowTabBarKey] animate:NO];
        }
    }
}


- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem
{
	[[self window] close];
}

- (BOOL)tabView:(NSTabView *)aTabView validateOverflowMenuItem:(NSMenuItem *)menuItem forTabViewItem:(NSTabViewItem *)tabViewItem
{
/* TODO: compatiblity fix
    int offset = floor(NSAppKitVersionNumber)>NSAppKitVersionNumber10_4 ? 1 : 0 ;//NSAppKitVersionNumber10_4 - need an offset for leopard
    PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
    PlainTextDocument *document = [tabContext document];
    if ([document isDocumentEdited]) {
        SetItemMark(_NSGetCarbonMenu([menuItem menu]), [[menuItem menu] indexOfItem:menuItem]+offset, kBulletCharCode);
    } else {
        SetItemMark(_NSGetCarbonMenu([menuItem menu]), [[menuItem menu] indexOfItem:menuItem]+offset, noMark);
    }

    if ([I_tabView selectedTabViewItem] == tabViewItem)
        SetItemMark(_NSGetCarbonMenu([menuItem menu]), [[menuItem menu] indexOfItem:menuItem]+offset, checkMark);
*/
    return YES;
}

- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)tabViewItem
{
    PlainTextWindowControllerTabContext *tabContext = [tabViewItem identifier];
    PlainTextDocument *document = [tabContext document];
    return [self windowTitleForDocumentDisplayName:[document displayName] document:document];
}

@end
