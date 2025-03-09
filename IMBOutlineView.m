/*
 iMedia Browser Framework <http://karelia.com/imedia/>
 
 Copyright (c) 2005-2012 by Karelia Software et al.
 
 iMedia Browser is based on code originally developed by Jason Terhorst,
 further developed for Sandvox by Greg Hulands, Dan Wood, and Terrence Talbot.
 The new architecture for version 2.0 was developed by Peter Baumgartner.
 Contributions have also been made by Matt Gough, Martin Wennerberg and others
 as indicated in source files.
 
 The iMedia Browser Framework is licensed under the following terms:
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in all or substantial portions of the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to permit
 persons to whom the Software is furnished to do so, subject to the following
 conditions:
 
	Redistributions of source code must retain the original terms stated here,
	including this list of conditions, the disclaimer noted below, and the
	following copyright notice: Copyright (c) 2005-2012 by Karelia Software et al.
 
	Redistributions in binary form must include, in an end-user-visible manner,
	e.g., About window, Acknowledgments window, or similar, either a) the original
	terms stated here, including this list of conditions, the disclaimer noted
	below, and the aforementioned copyright notice, or b) the aforementioned
	copyright notice and a link to karelia.com/imedia.
 
	Neither the name of Karelia Software, nor Sandvox, nor the names of
	contributors to iMedia Browser may be used to endorse or promote products
	derived from the Software without prior and express written permission from
	Karelia Software or individual contributors, as appropriate.
 
 Disclaimer: THE SOFTWARE IS PROVIDED BY THE COPYRIGHT OWNER AND CONTRIBUTORS
 "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
 AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH, THE
 SOFTWARE OR THE USE OF, OR OTHER DEALINGS IN, THE SOFTWARE.
*/


// Author: Peter Baumgartner


//----------------------------------------------------------------------------------------------------------------------


#pragma mark HEADERS

#import "IMBOutlineView.h"
#import "IMBNodeViewController.h"
#import "IMBLibraryController.h"
#import "IMBNode.h"
#import "NSCell+iMedia.h"
#import "IMBNodeCell.h"
#import "IMBTextFieldCell.h"
#import "IMBTableViewAppearance+iMediaPrivate.h"


//----------------------------------------------------------------------------------------------------------------------


#pragma mark

@implementation IMBOutlineView

@synthesize draggingPromptTextField = _draggingPromptTextField;
@synthesize imb_Appearance = _appearance;

- (void)setImb_Appearance:(IMBTableViewAppearance *)inAppearance
{
    if (_appearance == inAppearance) {
        return;
    }
    if (_appearance) {
        [_appearance unsetView];
    }
    [_appearance release];
    _appearance = inAppearance;
    [_appearance retain];
}


//----------------------------------------------------------------------------------------------------------------------


- (id) initWithFrame:(NSRect)inFrame
{
	if (self = [super initWithFrame:inFrame])
	{
		_subviewsInVisibleRows = [[NSMutableDictionary alloc] init];
        self.imb_Appearance = [self defaultAppearance];
	}
	
	return self;
}


- (id) initWithCoder:(NSCoder*)inCoder
{
	if (self = [super initWithCoder:inCoder])
	{
		_subviewsInVisibleRows = [[NSMutableDictionary alloc] init];
        self.imb_Appearance = [self defaultAppearance];
	}
	
	return self;
}


- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	IMBRelease(_subviewsInVisibleRows);
	IMBRelease(_draggingPromptTextField);

    if (_appearance)
    {
        [_appearance unsetView];
        IMBRelease(_appearance);
    }
 
	[super dealloc];
}


//----------------------------------------------------------------------------------------------------------------------


- (void) awakeFromNib
{
	[self updateDraggingPrompt];

	// We need to save preferences before tha app quits...
	
	[[NSNotificationCenter defaultCenter] 
		addObserver:self 
		selector:@selector(_redraw) 
		name:kIMBNodesWillReloadNotification 
		object:nil];

	[[NSNotificationCenter defaultCenter] 
		addObserver:self 
		selector:@selector(_redraw) 
		name:kIMBNodesDidChangeNotification 
		object:nil];
}

- (void) updateDraggingPrompt
{
	BOOL acceptsFiles = [[self registeredDraggedTypes] containsObject:NSFilenamesPboardType];
	NSScrollView* scrollView = self.enclosingScrollView;

	// Draw the prompt only when the content doesn't fill the view
	const CGFloat MARGIN_BELOW_DATA = 20.0;
	const CGFloat FADE_AREA = 20.0;
	CGFloat viewHeight = scrollView.contentView.bounds.size.height;
	CGFloat dataHeight = self.rowHeight * self.numberOfRows;
	BOOL shouldPrompt = acceptsFiles && (dataHeight+MARGIN_BELOW_DATA <= viewHeight);
	if (shouldPrompt || (self.draggingPromptTextField != nil)) {
		// Create the text field as needed
		if (self.draggingPromptTextField == nil) {
			NSString* promptText = NSLocalizedStringWithDefaultValue(
			 @"IMBOutlineView.draggingPrompt",
			 nil,IMBBundle(),
			 @"Drag additional folders here to add them to the media browser.",
			 @"String that is displayed in the IMBOutlineView");

			CGFloat fontSize = [NSFont systemFontSizeForControlSize:NSControlSizeSmall];
			NSFont* promptFont = [NSFont boldSystemFontOfSize:fontSize];

			NSRect draggingPromptFrame = [[self enclosingScrollView] bounds];
			draggingPromptFrame.size.height = [promptText sizeWithAttributes:@{NSFontAttributeName: promptFont}].height;
			self.draggingPromptTextField = [[NSTextField alloc] initWithFrame:draggingPromptFrame];

			IMBTextFieldCell* textCell = [[[IMBTextFieldCell alloc] initTextCell:promptText] autorelease];
			[textCell setAlignment:NSTextAlignmentCenter];
			[textCell setVerticalAlignment:kIMBBottomTextAlignment];
			[textCell setFont:promptFont];
			[textCell setTextColor:[NSColor grayColor]];
			self.draggingPromptTextField.cell = textCell;

			self.draggingPromptTextField.stringValue = promptText;
			self.draggingPromptTextField.editable = NO;
			self.draggingPromptTextField.selectable = NO;

			const CGFloat MARGIN_FROM_BOTTOM = 10.0;
			[scrollView addFloatingSubview:self.draggingPromptTextField forAxis:NSEventGestureAxisVertical];
			self.draggingPromptTextField.translatesAutoresizingMaskIntoConstraints = NO;
			[scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.draggingPromptTextField attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0]];
			[scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.draggingPromptTextField attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-MARGIN_FROM_BOTTOM]];
		}

		NSColor* draggingPromptColor = [NSColor grayColor];

		CGFloat fadeHeight = MIN(viewHeight-dataHeight,MARGIN_BELOW_DATA+FADE_AREA) - MARGIN_BELOW_DATA;
		CGFloat alpha = shouldPrompt ? (float)fadeHeight / FADE_AREA : 0.0;

		// If header has a customized color then use it but with 0.6 of its alpha value

		NSColor* appearanceTextColor = [self.imb_Appearance.sectionHeaderTextAttributes objectForKey:NSForegroundColorAttributeName];
		if (appearanceTextColor) {
			CGFloat appearanceAlpha = [appearanceTextColor alphaComponent];
			draggingPromptColor = [appearanceTextColor colorWithAlphaComponent:appearanceAlpha * 0.6 * alpha];
		} else {
			CGFloat whiteValue = 0.66667;
			if (@available(macOS 10.14, *)) {
				BOOL isDarkMode = [[[self effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:@"NSAppearanceNameDarkAqua"];
				whiteValue = isDarkMode ? 1.0 : 0.66667;
			}
			draggingPromptColor = [NSColor colorWithCalibratedWhite:whiteValue alpha:alpha];
		}
		self.draggingPromptTextField.textColor = draggingPromptColor;
	}
}

- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)newTypes
{
	[super registerForDraggedTypes:newTypes];
	[self updateDraggingPrompt];
}

- (void)unregisterDraggedTypes
{
	[super unregisterDraggedTypes];
	[self updateDraggingPrompt];
}

//----------------------------------------------------------------------------------------------------------------------


// Calculate the frame rect for progress indicator wheels...

- (NSRect) badgeRectForRow:(NSInteger)inRow
{
	IMBNodeCell* cell = (IMBNodeCell*)[self preparedCellAtColumn:0 row:inRow];

	// To correctly place the badge rect, we need to account for the table's intercellSpacing.
	// This can be done either by taking the whole rect of the row and subtracting the pertinent
	// spacing, but in this case we would still have to be assuming there is only one column
	// in order to be confident that the rect is on the right edge of the appropriate column.
	// It doesn't really matter which of these options we take but either one relies on the
	// assumption that we haven't added an additional column:

	NSAssert([self numberOfColumns] == 1, @"We must reconsider placement of the badge rect in the row, because we've added an additional column to the outline view.");

//	NSRect bounds = NSInsetRect([self rectOfRow:inRow],[self intercellSpacing].width / 2.0,0.0);
	NSRect bounds = [self frameOfCellAtColumn:0 row:inRow];

	return [cell badgeRectForBounds:bounds flipped:YES];
}


//----------------------------------------------------------------------------------------------------------------------


- (void) _redraw
{
	[self setNeedsDisplay:YES];
}


//----------------------------------------------------------------------------------------------------------------------


- (void) viewWillDraw
{
	[super viewWillDraw];
	[self showProgressWheels];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	[super resizeSubviewsWithOldSize:oldSize];
	[self updateDraggingPrompt];
}

//----------------------------------------------------------------------------------------------------------------------


// This method is asking us to draw the backgrounds for all rows that are visible inside theClipRect.
// If possible delegate task to appearance object

- (void) drawBackgroundInClipRect:(NSRect)inClipRect
{
    if (!self.imb_Appearance || ![self.imb_Appearance drawBackgroundInClipRect:inClipRect])
    {
		[super drawBackgroundInClipRect:inClipRect];
    }
}


// This method is asking us to draw the hightlights for all of the selected rows that are visible inside theClipRect.
// If possible delegate task to appearance object

- (void)highlightSelectionInClipRect:(NSRect)inClipRect
{
    if (!self.imb_Appearance || ![self.imb_Appearance highlightSelectionInClipRect:inClipRect])
    {
        [super highlightSelectionInClipRect:inClipRect];
    }
}


// If we are using custom background and highlight colors, we may have to adjust the text colors accordingly,
// to make sure that text is always clearly readable...

- (NSCell*) preparedCellAtColumn:(NSInteger)inColumn row:(NSInteger)inRow
{
	NSCell* cell = [super preparedCellAtColumn:inColumn row:inRow];
	
    if (self.imb_Appearance) {
        [self.imb_Appearance prepareCell:cell atColumn:inColumn row:inRow];
    }
	
	return cell;
}


//----------------------------------------------------------------------------------------------------------------------


- (void) showProgressWheels
{
	if (self.dataSource)
	{
		// First get rid of any progress indicators that are not currently visible or no longer needed...
		
		NSRect visibleRect = self.visibleRect;
		NSRange visibleRows = [self rowsInRect:visibleRect];
		NSMutableArray* keysToRemove = [NSMutableArray array];
		
		for (NSString* row in _subviewsInVisibleRows)
		{
			NSInteger i = [row intValue];
			IMBNode* node = [self nodeAtRow:i];
			
			if (!NSLocationInRange(i,visibleRows) || node.badgeTypeNormal != kIMBBadgeTypeLoading)
			{
				NSProgressIndicator* wheel = [_subviewsInVisibleRows objectForKey:row];
				[wheel stopAnimation:nil];
				[wheel removeFromSuperview];
				[keysToRemove addObject:row];
			}
		}
		
		[_subviewsInVisibleRows removeObjectsForKeys:keysToRemove];

		// Then add progress indicators for all nodes that need one (currently loading) and are currently visible...
		
		for (NSInteger i=visibleRows.location; i<visibleRows.location+visibleRows.length; i++)
		{
			IMBNode* node = [self nodeAtRow:i];
			NSString* row = [NSString stringWithFormat:@"%ld",(long)i];
			NSProgressIndicator* wheel = [_subviewsInVisibleRows objectForKey:row];
			
			if (node != nil && (node.badgeTypeNormal == kIMBBadgeTypeLoading))
			{
				NSRect badgeRect = [self badgeRectForRow:i];

				if (wheel == nil)
				{
					NSProgressIndicator* wheel = [[NSProgressIndicator alloc] initWithFrame:badgeRect];
					
					[wheel setAutoresizingMask:NSViewNotSizable];
					[wheel setStyle:NSProgressIndicatorSpinningStyle];
					[wheel setControlSize:NSSmallControlSize];
					[wheel setUsesThreadedAnimation:YES];
					[wheel setIndeterminate:YES];
					
					[_subviewsInVisibleRows setObject:wheel forKey:row];
					[self addSubview:wheel];
					[wheel startAnimation:nil];
					[wheel release];
				}
				else
				{
					// Update the frame in case we for instance just showed the scroll bar and require an offset
					[wheel setFrame:badgeRect];
				}
			}
		}
	}
}


//----------------------------------------------------------------------------------------------------------------------


- (void) drawRect:(NSRect)inRect	
{
	// First draw the NSOutlineView...
	
	[super drawRect:inRect];
}


//----------------------------------------------------------------------------------------------------------------------


// Ask the IMBNodeViewController (which is our delegate) to return a context menu for the clicked node. If  
// the user clicked on the background node is nil...

- (NSMenu*) menuForEvent:(NSEvent*)inEvent
{
	NSPoint mouse = [self convertPoint:[inEvent locationInWindow] fromView:nil];
	NSInteger i = [self rowAtPoint:mouse];
	NSInteger n = [self numberOfRows];
	IMBNode* node = nil;
	
	if (i>=0 && i<n)
	{
		node = [self nodeAtRow:i];
	}

	IMBNodeViewController* controller = (IMBNodeViewController*) self.delegate;
	[controller selectNode:node];
	return [controller menuForNode:node];
}
			

//----------------------------------------------------------------------------------------------------------------------


- (IMBNode*) nodeAtRow:(NSInteger)inRow
{
	id item = [self itemAtRow:inRow];
	return (IMBNode*)item;
}


/**
 */
- (NSInteger)rowForNode:(IMBNode **)pNode withIdentifier:(NSString *)identifier
{
    NSInteger rows = [self numberOfRows];
    IMBNode *node;
    for (NSInteger row=0; row<rows; row++)
    {
        node = [self nodeAtRow:row];
        if ([node.identifier isEqualToString:identifier]) {
            if (pNode) *pNode = node;
            return row;
        }
    }
    return -1;
}

//----------------------------------------------------------------------------------------------------------------------


#pragma mark
#pragma mark Appearance

NSString* IMBIsDefaultAppearanceAttributeName = @"IMBIsDefaultAppearanceAttributeName";

- (IMBTableViewAppearance*) defaultAppearance
{
    IMBTableViewAppearance* appearance = [[[IMBTableViewAppearance alloc] initWithView:self] autorelease];
    
    NSShadow* shadow = [[[NSShadow alloc] init] autorelease];
    [shadow setShadowColor:[NSColor whiteColor]];
    [shadow setShadowOffset:NSMakeSize(0.0, -1.0)];
    
    appearance.sectionHeaderTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                              [NSColor disabledControlTextColor], NSForegroundColorAttributeName,
                                              [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
                                              shadow, NSShadowAttributeName,
                                              [NSNumber numberWithBool:YES], IMBIsDefaultAppearanceAttributeName,
                                              nil];
    
    appearance.rowTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
                                    nil];
    
    appearance.rowTextHighlightAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                             [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
                                             nil];
    
    return appearance;
}


// If we do have an appearance set, then disable Yosemite style translucency, as it interferres too much...

- (BOOL) allowsVibrancy
{
	return _appearance != nil ? NO : YES;
}


@end
