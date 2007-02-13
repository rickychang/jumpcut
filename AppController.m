//
//  AppController.m
//  Jumpcut
//
//  Created by Steve Cook on 4/3/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//
//  This code is open-source software subject to the MIT License; see the homepage
//  at <http://jumpcut.sourceforge.net/> for details.

#import "AppController.h"
#import "PTHotKey.h"
#import "PTHotKeyCenter.h"
#import "ShortcutRecorderCell.h"
#import "UKLoginItemRegistry.h"


#define _DISPLENGTH 40

@implementation AppController

- (void)init
{
	if ( ! [[NSUserDefaults standardUserDefaults] floatForKey:@"lastRun"] || [[NSUserDefaults standardUserDefaults] floatForKey:@"lastRun"] < 0.6  ) {
		// A decent starting value for the main hotkey is control-option-V
		[mainRecorder setKeyCombo:SRMakeKeyCombo(9, 786432)];
		
		// Something we'd really like is to transfer over info from 0.5x if we can get at it --
		if ( [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] ) {
			// We need to pull out the relevant objects and stuff them in as proper preferences for the net.sf.Jumpcut domain
			if ( [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"displayNum"] != nil )
			{
				[[NSUserDefaults standardUserDefaults] setValue:[ [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"displayNum"]
														 forKey:@"displayNum"];
			}
			if ( [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"savePreference"] != nil )
			{
				if ( [[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"savePreference"] isEqual:@"onChange"] )
				{
					[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:2]
															 forKey:@"savePreference"];
				} 
				else if ( [[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"savePreference"] isEqual:@"onExit"] )
				{
					[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:1]
															 forKey:@"savePreference"];
				}
				else
				{
					[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:0]
															 forKey:@"savePreference"];
				} // End save preference test
			} // End savePreference test
		} // End if/then that deals with 0.5x preferences
	} // End new-to-version check
	// If we don't have preferences defined, let's set some default values:
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:15],
		@"displayNum",
		[NSNumber numberWithInt:40],
		@"rememberNum",
		[NSNumber numberWithInt:1],
		@"savePreference",
		[NSNumber numberWithInt:0],
		@"menuIcon",
		[NSNumber numberWithFloat:.25],
		@"bezelAlpha",
		[NSNumber numberWithBool:NO],
		@"stickyBezel",
		[NSNumber numberWithBool:NO],
		@"launchOnStartup",
		[NSNumber numberWithBool:YES],
		@"menuSelectionPastes",
		nil]
		];
	[super init];
}

- (void)awakeFromNib
{
	// Hotkey default value
	if ( ! [[NSUserDefaults standardUserDefaults] floatForKey:@"lastRun"] || [[NSUserDefaults standardUserDefaults] floatForKey:@"lastRun"] < 0.6  ) {
		// A decent starting value for the main hotkey is control-option-V
		[mainRecorder setKeyCombo:SRMakeKeyCombo(9, 786432)];
		NSLog(@"Setting hotkey");
		if ( [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] ) {
			NSLog(@"Pulling old preference");
			// We need to pull out the relevant objects and stuff them in as proper preferences for the net.sf.Jumpcut domain
			if ( [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"hotkeyModifiers"] != nil )
			{
				NSLog(@"Setting hotkey");
				[mainRecorder setKeyCombo:SRMakeKeyCombo(9, [[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"Jumpcut"] objectForKey:@"hotkeyModifiers"] intValue])];
			}	
		}
	}
	// Initialize the JumpcutStore
	clippingStore = [[JumpcutStore alloc] initRemembering:[[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"]
											   displaying:[[NSUserDefaults standardUserDefaults] integerForKey:@"displayNum"]
										withDisplayLength:_DISPLENGTH];
	// Set up the bezel window
    NSSize windowSize = NSMakeSize(325.0, 325.0);
    NSSize screenSize = [[NSScreen mainScreen] frame].size;
	NSRect windowFrame = NSMakeRect( (screenSize.width - windowSize.width) / 2,
                                     (screenSize.height - windowSize.height) / 3,
									 windowSize.width, windowSize.height );
	bezel = [[BezelWindow alloc] initWithContentRect:windowFrame
										   styleMask:NSBorderlessWindowMask
											 backing:NSBackingStoreBuffered
											   defer:NO];
	[bezel setDelegate:self];

	// Create our pasteboard interface
    jcPasteboard = [NSPasteboard generalPasteboard];
    [jcPasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    pbCount = [[NSNumber numberWithInt:[jcPasteboard changeCount]] retain];

	// Build the statusbar menu
    statusItem = [[[NSStatusBar systemStatusBar]
            statusItemWithLength:NSVariableStatusItemLength] retain];
    [statusItem setHighlightMode:YES];
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"menuIcon"] == 1 ) {
		[statusItem setTitle:[NSString stringWithFormat:@"%C",0x2704]]; 
	} else if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"menuIcon"] == 2 ) {
		[statusItem setTitle:[NSString stringWithFormat:@"%C",0x2702]]; 
	} else {
		[statusItem setImage:[NSImage imageNamed:@"net.sf.jumpcut.scissors_bw16.png"]];
    }
	[statusItem setMenu:jcMenu];
    [statusItem setEnabled:YES];
	
    // If our preferences indicate that we are saving, load the dictionary from the saved plist
    // and use it to get everything set up.
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
		[self loadEngineFromPList];
	}
	// Build our listener timer
    pollPBTimer = [[NSTimer scheduledTimerWithTimeInterval:(1.0)
													target:self
												  selector:@selector(pollPB:)
												  userInfo:nil
												   repeats:YES] retain];
	
    // Finish up
    pbBlockCount = [[NSNumber numberWithInt:0] retain];
    [pollPBTimer fire];

	// Stack position starts @ 0 by default
	stackPosition = 0;

	// Make sure we only run the 0.5x transition once
	[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithFloat:0.6]
											 forKey:@"lastRun"];

									     								
	[NSApp activateIgnoringOtherApps: YES];

}

-(IBAction) setBezelAlpha:(id)sender
{
	// In a masterpiece of poorly-considered design--because I want to eventually 
	// allow users to select from a variety of bezels--I've decided to create the
	// bezel programatically, meaning that I have to go through AppController as
	// a cutout to allow the user interface to interact w/the bezel.
	[bezel setAlpha:[sender floatValue]];
}

-(IBAction) switchMenuIcon:(id)sender
{
	if ([sender indexOfSelectedItem] == 1 ) {
		[statusItem setImage:nil];
		[statusItem setTitle:[NSString stringWithFormat:@"%C",0x2704]]; 
	} else if ( [sender indexOfSelectedItem] == 2 ) {
		[statusItem setImage:nil];
		[statusItem setTitle:[NSString stringWithFormat:@"%C",0x2702]]; 
	} else {
		[statusItem setTitle:@""];
		[statusItem setImage:[NSImage imageNamed:@"net.sf.jumpcut.scissors_bw16.png"]];
    }
}

-(IBAction) setRememberNumPref:(id)sender
{
	int choice;
	int newRemember = [sender intValue];
	if ( newRemember < [clippingStore jcListCount] &&
		 ! issuedRememberResizeWarning &&
		 ! [[NSUserDefaults standardUserDefaults] boolForKey:@"stifleRememberResizeWarning"]
		 ) {
		choice = NSRunAlertPanel(@"Resize Stack", 
								 @"Resizing the stack to a value below its present size will cause clippings to be lost.",
								 @"Resize", @"Cancel", @"Don't Warn Me Again");
		if ( choice == NSAlertAlternateReturn ) {
			[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:[clippingStore jcListCount]]
													 forKey:@"rememberNum"];
			[self updateMenu];
			return;
		} else if ( choice == NSAlertOtherReturn ) {
			[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES]
													 forKey:@"stifleRememberResizeWarning"];
		} else {
			issuedRememberResizeWarning = YES;
		}
	}
	if ( newRemember < [[NSUserDefaults standardUserDefaults] integerForKey:@"displayNum"] ) {
		[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:newRemember]
												 forKey:@"displayNum"];
	}
	[clippingStore setRememberNum:newRemember];
	[self updateMenu];
}

-(IBAction) setDisplayNumPref:(id)sender
{
	[self updateMenu];
}

-(IBAction) showPreferencePanel:(id)sender
{                                    
	int checkLoginRegistry = [UKLoginItemRegistry indexForLoginItemWithPath:[[NSBundle mainBundle] bundlePath]];
//    if ( ![prefsPanel isVisible] ) {
	// Synchronize checkbox with login items -- changes could be made manually outside Jumpcut
	if ( checkLoginRegistry >= 1 ) {
		[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES]
												 forKey:@"loadOnStartup"];
	} else {
		[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:NO]
												 forKey:@"loadOnStartup"];
	}
	
	[NSApp activateIgnoringOtherApps: YES];
	[prefsPanel makeKeyAndOrderFront:self];
	issuedRememberResizeWarning = NO;
}

-(IBAction)toggleLoadOnStartup:(id)sender {
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"loadOnStartup"] ) {
		[UKLoginItemRegistry addLoginItemWithPath:[[NSBundle mainBundle] bundlePath] hideIt:NO];
	} else {
		[UKLoginItemRegistry removeLoginItemWithPath:[[NSBundle mainBundle] bundlePath]];
	}
}


- (void)pasteFromStack
{
	if ( [clippingStore jcListCount] > stackPosition ) {
		[self addClipToPasteboardFromCount:stackPosition];
		[self performSelector:@selector(hideApp) withObject:nil afterDelay:0.2];
		[self performSelector:@selector(fakeCommandV) withObject:nil afterDelay:0.2];
	} else {
		[self performSelector:@selector(hideApp) withObject:nil afterDelay:0.2];
	}
}

- (void)metaKeysReleased
{
	if ( ! isBezelPinned ) {
		[self pasteFromStack];
	}
}

-(void)fakeCommandV
	/*" +fakeCommandV synthesizes keyboard events for Cmd-v Paste 
	shortcut. "*/ 
	// Code from a Mark Mason post to Cocoadev-l
	// What are the flaws in this approach?
	//  We don't know whether we can really accept the paste
	//  We have no way of judging whether it's gone through
	//  Simulating keypresses could have oddball consequences (for instance, if something else was trapping control v)
	//  Not all apps may take Command-V as a paste command (xemacs, for instance?)
	// Some sort of AE-based (or System Events-based, or service-based) paste would be preferable in many circumstances.
	// On the other hand, this doesn't require scripting support, should work for Carbon, etc.
	// Ideally, in the future, we will be able to tell from what environment JC was passed the trigger
	// and have different behavior from each.
{ 
	CGPostKeyboardEvent( (CGCharCode)0, (CGKeyCode)55, true ); // Command down
	CGPostKeyboardEvent( (CGCharCode)'v', (CGKeyCode)9, true ); // V down 
	CGPostKeyboardEvent( (CGCharCode)'v', (CGKeyCode)9, false ); //  V up 
	CGPostKeyboardEvent( (CGCharCode)0, (CGKeyCode)55, false ); // Command up
} 

-(void)pollPB:(NSTimer *)timer
{
    NSString *type = [jcPasteboard availableTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]];
    if ( [pbCount intValue] != [jcPasteboard changeCount] ) {
        // Reload pbCount with the current changeCount
        // Probably poor coding technique, but pollPB should be the only thing messing with pbCount, so it should be okay
        [pbCount release];
        pbCount = [[NSNumber numberWithInt:[jcPasteboard changeCount]] retain];
        if ( type != nil ) {
			NSString *contents = [jcPasteboard stringForType:type];
			if ( contents == nil ) {
//                NSLog(@"Contents: Empty");
            } else {
				if (( [clippingStore jcListCount] == 0 || ! [contents isEqualToString:[clippingStore clippingContentsAtPosition:0]])
					&&  ! [pbCount isEqualTo:pbBlockCount] ) {
                    [clippingStore addClipping:contents
										ofType:type	];
//					The below tracks our position down down down... Maybe as an option?
//					if ( [clippingStore jcListCount] > 1 ) stackPosition++;
					stackPosition = 0;
                    [self updateMenu];
					if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 2 ) {
                        [self saveEngine];
                    }
                }
            }
        } else {
            // NSLog(@"Contents: Non-string");
        }
    }
	
}

- (void)processBezelKeyDown:(NSEvent *)theEvent
{
	int newStackPosition;
	// AppControl should only be getting these directly from bezel via delegation
	if ( [theEvent type] == NSKeyDown )
	{
		if ( [theEvent keyCode] == [mainRecorder keyCombo].code )
		{
			if ( [theEvent modifierFlags] & NSShiftKeyMask )
			{
				stackPosition--; if ( stackPosition < 0 ) stackPosition = 0;
				if ( [clippingStore jcListCount] > stackPosition ) {
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
			} else {
				stackPosition++;
				if ( [clippingStore jcListCount] > stackPosition ) {
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				} else {
					stackPosition--;
				}
			}
			return;
		}
		unichar pressed = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
		switch ( pressed ) {
			case 0x1B:
				[self hideApp];
				break;
			case 0x3: case 0xD: // Enter or Return
				[self pasteFromStack];
				break;
			case NSUpArrowFunctionKey: 
			case NSLeftArrowFunctionKey: 
				stackPosition--; if ( stackPosition < 0 ) stackPosition = 0;
				if ( [clippingStore jcListCount] > stackPosition ) {
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
				break;
			case NSDownArrowFunctionKey: 
			case NSRightArrowFunctionKey:
				stackPosition++;
				if ( [clippingStore jcListCount] > stackPosition ) {
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				} else {
					stackPosition--;
				}
				break;
            case NSHomeFunctionKey:
				if ( [clippingStore jcListCount] > 0 ) {
					stackPosition = 0;
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
				break;
            case NSEndFunctionKey:
				if ( [clippingStore jcListCount] > 0 ) {
					stackPosition = [clippingStore jcListCount] - 1;
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
				break;
            case NSPageUpFunctionKey:
				if ( [clippingStore jcListCount] > 0 ) {
					stackPosition = stackPosition - 10; if ( stackPosition < 0 ) stackPosition = 0;
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
				break;
			case NSPageDownFunctionKey:
				if ( [clippingStore jcListCount] > 0 ) {
					stackPosition = stackPosition + 10; if ( stackPosition >= [clippingStore jcListCount] ) stackPosition = [clippingStore jcListCount] - 1;
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
				break;
			case NSBackspaceCharacter: break;
            case NSDeleteCharacter: break;
            case NSDeleteFunctionKey: break;
			case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: 				// Numeral 
			case 0x35: case 0x36: case 0x37: case 0x38: case 0x39:
				// We'll currently ignore the possibility that the user wants to do something with shift.
				// First, let's set the new stack count to "10" if the user pressed "0"
				newStackPosition = pressed == 0x30 ? 9 : [[NSString stringWithCharacters:&pressed length:1] intValue] - 1;
				if ( [clippingStore jcListCount] >= newStackPosition ) {
					stackPosition = newStackPosition;
					[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
					[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
				}
				break;
            default: // It's not a navigation/application-defined thing, so let's figure out what to do with it.
				NSLog(@"PRESSED %d", pressed);
				NSLog(@"CODE %d", [mainRecorder keyCombo].code);
				break;
		}		
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	//Create our hot key
	mainHotKey = [[PTHotKey alloc] initWithIdentifier:@"mainHotKey"
											   keyCombo:[PTKeyCombo keyComboWithKeyCode:[mainRecorder keyCombo].code
																			  modifiers:[mainRecorder cocoaToCarbonFlags: [mainRecorder keyCombo].flags]]];
	// mainHotkeyModifiers = [mainRecorder cocoaToCarbonFlags:[mainRecorder keyCombo].flags];
	// NSLog(@"Hotkey modifiers: %d", mainHotkeyModifiers);
	[mainHotKey setName: @"Activate Bezel HotKey"]; //This is typically used by PTKeyComboPanel
	[mainHotKey setTarget: self];
	[mainHotKey setAction: @selector( hitMainHotKey: ) ];
	
	//Register it
	[[PTHotKeyCenter sharedCenter] registerHotKey: mainHotKey];
}

- (void) showBezel
{
	if ( [clippingStore jcListCount] > 0 && [clippingStore jcListCount] > stackPosition ) {
		[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
		[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
	} 
	[bezel makeKeyAndOrderFront:nil];
	isBezelDisplayed = YES;
}

- (void) hideBezel
{
	[bezel orderOut:nil];
	[bezel setCharString:@""];
	isBezelDisplayed = NO;
}

-(void)hideApp
{
    [self hideBezel];
	isBezelPinned = NO;
	[NSApp hide:self];
}

- (void) applicationWillResignActive:(NSApplication *)app; {
	// This should be hidden anyway, but just in case it's not.
    [self hideBezel];
}


- (void)hitMainHotKey:(PTHotKey *)hotKey
{
	if ( ! isBezelDisplayed ) {
		[NSApp activateIgnoringOtherApps:YES];
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"stickyBezel"] ) {
			isBezelPinned = YES;
		}
		[self showBezel];
	} else {
		stackPosition++;
		if ( [clippingStore jcListCount] > stackPosition ) {
			[bezel setCharString:[NSString stringWithFormat:@"%d", stackPosition + 1]];
			[bezel setText:[clippingStore clippingContentsAtPosition:stackPosition]];
		} else {
			stackPosition--;
		}
	}
}

- (IBAction)toggleMainHotKey:(id)sender
{
	if (mainHotKey != nil)
	{
		[[PTHotKeyCenter sharedCenter] unregisterHotKey:mainHotKey];
		[mainHotKey release];
		mainHotKey = nil;
	}
	
	mainHotKey = [[PTHotKey alloc] initWithIdentifier:@"mainHotKey"
											   keyCombo:[PTKeyCombo keyComboWithKeyCode:[mainRecorder keyCombo].code
																			  modifiers:[mainRecorder cocoaToCarbonFlags: [mainRecorder keyCombo].flags]]];
	
	[mainHotKey setTarget: self];
	[mainHotKey setAction: @selector(hitMainHotKey:)];
	
	[[PTHotKeyCenter sharedCenter] registerHotKey:mainHotKey];
}

-(IBAction)clearClippingList:(id)sender {
    int choice;
	
	[NSApp activateIgnoringOtherApps:YES];
    choice = NSRunAlertPanel(@"Clear Clipping List", 
							 @"Do you want to clear all recent clippings?",
							 @"Clear", @"Cancel", nil);
	
    // on clear, zap the list and redraw the menu
    if ( choice == NSAlertDefaultReturn ) {
        [clippingStore clearList];
        [self updateMenu];
		if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
			[self saveEngine];
		}
		[bezel setText:@""];
    }
}

- (void)updateMenu {
    int passedSeparator = 0;
    NSMenuItem *oldItem;
    NSMenuItem *item;
    NSString *pbMenuTitle;
    NSArray *returnedDisplayStrings = [clippingStore previousDisplayStrings:[[NSUserDefaults standardUserDefaults] integerForKey:@"displayNum"]];
    NSEnumerator *menuEnumerator = [[jcMenu itemArray] reverseObjectEnumerator];
    NSEnumerator *clipEnumerator = [returnedDisplayStrings reverseObjectEnumerator];
	
    //remove clippings from menu
    while( oldItem = [menuEnumerator nextObject] ) {
		if( [oldItem isSeparatorItem]) {
            passedSeparator++;
        } else if ( passedSeparator == 2 ) {
            [jcMenu removeItem:oldItem];
        }
    }
	
	
    while( pbMenuTitle = [clipEnumerator nextObject] ) {
        item = [[NSMenuItem alloc] initWithTitle:pbMenuTitle
										  action:@selector(processMenuClippingSelection:)
								   keyEquivalent:@""];
        [item setTarget:self];
        [item setEnabled:YES];
        [jcMenu insertItem:item atIndex:0];
        // Way back in 0.2, failure to release the new item here was causing a quite atrocious memory leak.
        [item release];
	} 
}

-(IBAction)processMenuClippingSelection:(id)sender
{
    int index=[[sender menu] indexOfItem:sender];
    [self addClipToPasteboardFromCount:index];
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"menuSelectionPastes"] ) {
		[self performSelector:@selector(hideApp) withObject:nil];
		[self performSelector:@selector(fakeCommandV) withObject:nil afterDelay:0.2];
	}
}

-(BOOL) isValidClippingNumber:(NSNumber *)number {
    return ( ([number intValue] + 1) <= [clippingStore jcListCount] );
}

-(NSString *) clippingStringWithCount:(int)count {
    if ( [self isValidClippingNumber:[NSNumber numberWithInt:count]] ) {
        return [clippingStore clippingContentsAtPosition:count];
    } else { // It fails -- we shouldn't be passed this, but...
        NSLog(@"Asked for non-existant clipping count: %d");
        return @"";
    }
}

-(void) setPBBlockCount:(NSNumber *)newPBBlockCount
{
    [newPBBlockCount retain];
    [pbBlockCount release];
    pbBlockCount = newPBBlockCount;
}

-(BOOL)addClipToPasteboardFromCount:(int)indexInt
{
    NSString *pbFullText;
    NSArray *pbTypes;
    if ( (indexInt + 1) > [clippingStore jcListCount] ) {
        // We're asking for a clipping that isn't there yet
		// This only tends to happen immediately on startup when not saving, as the entire list is empty.
        NSLog(@"Out of bounds request to jcList ignored.");
        return false;
    }
    pbFullText = [self clippingStringWithCount:indexInt];
    pbTypes = [NSArray arrayWithObjects:@"NSStringPboardType",NULL];
    
    [jcPasteboard declareTypes:pbTypes owner:NULL];
	
    [jcPasteboard setString:pbFullText forType:@"NSStringPboardType"];
    [self setPBBlockCount:[NSNumber numberWithInt:[jcPasteboard changeCount]]];
    return true;
}

-(void) loadEngineFromPList
{
    NSString *path = [[NSString stringWithString:@"~/Library/Application Support/Jumpcut/JCEngine.save"] 					stringByExpandingTildeInPath];
    NSDictionary *loadDict = [[NSDictionary alloc] initWithContentsOfFile:path];
    NSEnumerator *enumerator;
    NSDictionary *aSavedClipping;
    NSArray *savedJCList;
	NSRange loadRange;
	int rangeCap;
	if ( loadDict != nil ) {
        savedJCList = [loadDict objectForKey:@"jcList"];
        if ( [savedJCList isKindOfClass:[NSArray class]] ) {
			// There's probably a nicer way to prevent the range from going out of bounds, but this works.
			rangeCap = [savedJCList count] < [[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"] ? [savedJCList count] : [[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"];
			loadRange = NSMakeRange(0, rangeCap);
			enumerator = [[savedJCList subarrayWithRange:loadRange] reverseObjectEnumerator];
			while ( aSavedClipping = [enumerator nextObject] ) {
				[clippingStore addClipping:[aSavedClipping objectForKey:@"Contents"]
									ofType:[aSavedClipping objectForKey:@"Type"]];
            }
        } else {
			NSLog(@"Not array");
		}
        [self updateMenu];
        [loadDict release];
    }
}

-(void) saveEngine
{
    NSMutableDictionary *saveDict;
    NSMutableArray *jcListArray = [NSMutableArray array];
    int i;
    BOOL isDir;
    NSString *path;
    path = [[NSString stringWithString:@"~/Library/Application Support/Jumpcut"] stringByExpandingTildeInPath];
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || ! isDir ) {
        NSLog(@"Creating Application Support directory");
        [[NSFileManager defaultManager] createDirectoryAtPath:path
												   attributes:[NSDictionary dictionaryWithObjectsAndKeys:
													   @"NSFileModificationDate", [NSNull null],
													   @"NSFileOwnerAccountName", [NSNull null],
													   @"NSFileGroupOwnerAccountName", [NSNull null],
													   @"NSFilePosixPermissions", [NSNull null],
													   @"NSFileExtensionsHidden", [NSNull null],
													   nil]
			];
    }
	
    saveDict = [NSMutableDictionary dictionaryWithCapacity:3];
    [saveDict setObject:@"0.6" forKey:@"version"];
    [saveDict setObject:[NSNumber numberWithInt:[[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"]]
                 forKey:@"rememberNum"];
    [saveDict setObject:[NSNumber numberWithInt:_DISPLENGTH]
                 forKey:@"displayLen"];
    [saveDict setObject:[NSNumber numberWithInt:[[NSUserDefaults standardUserDefaults] integerForKey:@"displayNum"]]
                 forKey:@"displayNum"];
    for ( i = 0 ; i < [clippingStore jcListCount]; i++) {
		[jcListArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			[clippingStore clippingContentsAtPosition:i], @"Contents",
			[clippingStore clippingTypeAtPosition:i], @"Type",
			[NSNumber numberWithInt:i], @"Position",
			nil
			]
			];
    }
    [saveDict setObject:jcListArray forKey:@"jcList"];
	
    if ( [saveDict writeToFile:[path stringByAppendingString:@"/JCEngine.save"] atomically:true] ) {
		// NSLog(@"Engine contents saved.");
    } else {
		NSLog(@"Engine contents NOT saved.");
    }
}


- (BOOL)shortcutRecorder:(ShortcutRecorder *)aRecorder isKeyCode:(signed short)keyCode andFlagsTaken:(unsigned int)flags reason:(NSString **)aReason
{
	if (aRecorder == mainRecorder)
	{
		BOOL isTaken = NO;
/*		
		KeyCombo kc = [delegateDisallowRecorder keyCombo];
		
		if (kc.code == keyCode && kc.flags == flags) isTaken = YES;
		
		*aReason = [delegateDisallowReasonField stringValue];
*/		
		return isTaken;
	}
	
	return NO;
}

- (void)shortcutRecorder:(ShortcutRecorder *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo
{
	if (aRecorder == mainRecorder)
	{
		[self toggleMainHotKey: aRecorder];
	}
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
		NSLog(@"Saving on exit");
        [self saveEngine] ;
    }
	//Unregister our hot key (not required)
	[[PTHotKeyCenter sharedCenter] unregisterHotKey: mainHotKey];
	[mainHotKey release];
	mainHotKey = nil;
	[nc removeObserver:self];
	[self hideBezel];
}

- (void) dealloc
{
	[bezel release];
	[super dealloc];
}

@end