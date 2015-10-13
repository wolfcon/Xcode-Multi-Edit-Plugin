//
//  xcodeplugin.m
//  xcodeplugin
//
//  Created by Tim on 03/03/2015.
//  Copyright (c) 2015 Tim. All rights reserved.
//

#import "XcodeMultiEdit.h"

#import "RangeEditView.h"

static xcodeplugin *sharedPlugin;

@interface xcodeplugin(){
    NSTextView *mainTextView;
    IDESourceCodeDocument *mainDocument;
    DVTSourceTextStorage *mainTextStorage;
    
    NSMutableArray *editViewsBeforeSelected;
    NSMutableArray *editViewsAfterSelected;
    NSString *selectedString;
    NSRange selectedRange;
    NSView *containerView;
    NSTextField *textField;
}

@property (nonatomic, strong, readwrite) NSBundle *bundle;

@end

@implementation xcodeplugin

// future
// make faster
// settings panel
// alcatraz

+ (void)pluginDidLoad:(NSBundle *)pluginBundle {
    
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    
    static dispatch_once_t onceToken;
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:pluginBundle]; // init once
        });
    }
}

+ (instancetype)sharedPlugin {
    return sharedPlugin;
}

-(id)initWithBundle:(NSBundle *)plugin{
    if (self = [super init]) {
        // reference to plugin's bundle, for resource access
        self.bundle = plugin;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didApplicationFinishLaunchingNotification:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
    }
    return self;
}

-(void)didApplicationFinishLaunchingNotification:(NSNotification*)notification{
    
    // Sample Menu Item:
    NSMenuItem *menuItem = [[[NSApplication sharedApplication] mainMenu] itemWithTitle:@"Edit"];
    
    if (menuItem) {
        [[menuItem submenu] addItem:[NSMenuItem separatorItem]];
        // if the user wants a custom keybinding, that might be tricky
        NSMenuItem *actionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Do Action" action:@selector(doAction) keyEquivalent:@"d"];
        [actionMenuItem setTarget:self];
        [[menuItem submenu] addItem:actionMenuItem];
    }
    
    editViewsBeforeSelected = [[NSMutableArray alloc] init];
    editViewsAfterSelected = [[NSMutableArray alloc] init];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)doAction{
    IDEWorkspaceWindowController    *windowController = (IDEWorkspaceWindowController*)[[NSApp keyWindow] windowController];
    IDEEditorArea                   *editorArea = [windowController editorArea];
    IDEEditorContext                *editorAreaContext = [editorArea lastActiveEditorContext];
    id editor = [editorAreaContext editor];
    
    if (![[editor className] isEqualToString:@"IDESourceCodeEditor"]) { // if we're not looking at code, return
        return;
    }
    
    mainTextView = [editor textView];
    mainDocument = [editor sourceCodeDocument];
    mainTextStorage = [editor sourceCodeDocument].textStorage;
    
    if ((editViewsBeforeSelected.count == 0) && (editViewsAfterSelected.count == 0)) {
        
        selectedString = [mainTextView.string substringWithRange:mainTextView.selectedRange];
        selectedRange = mainTextView.selectedRange;
        [self createTextFieldViewForStringRange:selectedRange];
    }
    [self addNextRangeForStringRepeatingPage];
}

-(void)addNextRangeForStringRepeatingPage{
    
    NSRange lastRange;
    
    BOOL loopedAround = NO;
    
    if (editViewsBeforeSelected.count>0) {
        lastRange = [[editViewsBeforeSelected lastObject] presentedRange];
        loopedAround = YES;
    } else if (editViewsAfterSelected.count>0){
        lastRange = [[editViewsAfterSelected lastObject] presentedRange];
    } else {
        lastRange = selectedRange;
    }
    
    NSUInteger locationOfSearchRange = lastRange.location+lastRange.length;
    NSUInteger lengthOfSearchRange;
    
    if (loopedAround) { // if we're looped around to the beginning of the document
        lengthOfSearchRange = selectedRange.location-locationOfSearchRange;
    } else { // else we're still on the first read-through
        lengthOfSearchRange = mainTextView.string.length - locationOfSearchRange;
    }
    
    NSRange rangeToSearch = NSMakeRange(locationOfSearchRange, lengthOfSearchRange);
    
    // the search
    NSRange newRange = [mainTextView.string rangeOfString:selectedString options:0 range:rangeToSearch];
    
    BOOL foundResult = NO;
    // if a range is found, use it.
    if (newRange.location != NSNotFound) {
        foundResult = YES;
        [self createEditViewForStringRange:newRange];
    } else {
        if (!loopedAround) { // so we only loop around once
            NSRange rangeLoopedAround = NSMakeRange(0, selectedRange.location);
            NSRange newRange = [mainTextView.string rangeOfString:selectedString options:0 range:rangeLoopedAround];
            if (newRange.location != NSNotFound) {
                foundResult = YES;
                [self createEditViewForStringRange:newRange];
            }
        }
    }
    if (!foundResult) {
        NSBeep();
    }
}


-(void)createEditViewForStringRange:(NSRange)range{
    NSRect rangeRect = [[mainTextView layoutManager] boundingRectForGlyphRange:range inTextContainer:mainTextView.textContainer];
    RangeEditView *editView = [[RangeEditView alloc] initWithFrame:rangeRect];
    [editView setPresentedRange:range];
    [mainTextView addSubview:editView];
    if ((range.location+range.length)<selectedRange.location) {
        [editViewsBeforeSelected addObject:editView];
    } else {
        [editViewsAfterSelected addObject:editView];
    }
    [mainTextView scrollRangeToVisible:range];
}

-(void)createTextFieldViewForStringRange:(NSRange)range{
    
    NSRect rangeRect = [[mainTextView layoutManager] boundingRectForGlyphRange:range inTextContainer:mainTextView.textContainer];
    
    containerView = [[NSView alloc] initWithFrame:rangeRect];
    [containerView setWantsLayer:YES];
    [containerView.layer setBackgroundColor:CGColorCreateGenericGray(1.0, 1.0)];
    [containerView.layer setBorderColor:CGColorCreateGenericGray(0.0, 1.0)];
    [containerView.layer setBorderWidth:1.0];
    [containerView.layer setCornerRadius:2.0];
    [mainTextView addSubview:containerView];
    
    textField = [[NSTextField alloc] init];
    [textField setStringValue:selectedString];
    [textField setFont:mainTextView.font];
    [textField setBezeled:NO];
    [textField setDrawsBackground:NO];
    [textField setUsesSingleLineMode:YES];
    
    [textField sizeToFit];
    CGRect textFrame = CGRectMake(-2, 0, textField.frame.size.width, textField.frame.size.height);
    
    [textField setFrame:NSRectFromCGRect(textFrame)];
    
    [containerView addSubview:textField];
    [textField setDelegate:self];
    [[NSApp mainWindow] makeFirstResponder:textField];
    
    [textField setTarget:self];
    [textField setAction:@selector(enterKeyPressed)];
}

-(void)controlTextDidChange:(NSNotification *)obj{
    [textField setStringValue:textField.stringValue];
    if (![textField.stringValue hasSuffix:@" "]) {
        [textField sizeToFit];
    }
    [containerView setFrame:NSRectFromCGRect(CGRectMake(containerView.frame.origin.x,
                                                        containerView.frame.origin.y,
                                                        textField.frame.size.width,
                                                        containerView.frame.size.height))];
    
    
    
    
    
    [editViewsBeforeSelected enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        int locationOffset = (int)textField.stringValue.length - (int)selectedString.length;
        locationOffset = locationOffset * (int)idx;
        NSRange rangeToEdit = NSMakeRange([obj presentedRange].location+locationOffset, [obj presentedRange].length);
        [mainTextStorage replaceCharactersInRange:rangeToEdit withString:textField.stringValue withUndoManager:mainDocument.undoManager];
        [obj setPresentedRange:NSMakeRange([obj presentedRange].location, textField.stringValue.length)];
        NSRect rangeRect = [[mainTextView layoutManager] boundingRectForGlyphRange:rangeToEdit inTextContainer:mainTextView.textContainer];
        [obj setFrame:NSRectFromCGRect(CGRectMake(rangeRect.origin.x, rangeRect.origin.y, containerView.frame.size.width, containerView.frame.size.height))];
    }];
    
    // calculate new range for edit box
    int locationOffset = (int)textField.stringValue.length - (int)selectedString.length;
    locationOffset = locationOffset * (int)editViewsBeforeSelected.count;
    NSRange rangeToEdit = NSMakeRange(selectedRange.location+locationOffset, selectedRange.length);
    [mainTextStorage replaceCharactersInRange:rangeToEdit withString:textField.stringValue withUndoManager:mainDocument.undoManager];
    selectedRange = NSMakeRange(selectedRange.location, textField.stringValue.length);
    
    [editViewsAfterSelected enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        int locationOffset = (int)textField.stringValue.length - (int)selectedString.length;
        locationOffset = locationOffset * ((int)idx+(int)editViewsBeforeSelected.count+1);
        NSRange rangeToEdit = NSMakeRange([obj presentedRange].location+locationOffset, [obj presentedRange].length);
        [mainTextStorage replaceCharactersInRange:rangeToEdit withString:textField.stringValue withUndoManager:mainDocument.undoManager];
        [obj setPresentedRange:NSMakeRange([obj presentedRange].location, textField.stringValue.length)];
        
        NSRect rangeRect = [[mainTextView layoutManager] boundingRectForGlyphRange:rangeToEdit inTextContainer:mainTextView.textContainer];
        [obj setFrame:NSRectFromCGRect(CGRectMake(rangeRect.origin.x, rangeRect.origin.y, containerView.frame.size.width, containerView.frame.size.height))];
    }];
}

-(void)enterKeyPressed{
    [editViewsBeforeSelected enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj removeFromSuperview];
        obj = nil;
    }];
    [editViewsAfterSelected enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj removeFromSuperview];
        obj = nil;
    }];
    [editViewsBeforeSelected removeAllObjects];
    [editViewsAfterSelected removeAllObjects];
    [textField removeFromSuperview];
    textField = nil;
    [containerView removeFromSuperview];
    containerView = nil;
    [[NSApp mainWindow] makeFirstResponder:mainTextView];
}

@end