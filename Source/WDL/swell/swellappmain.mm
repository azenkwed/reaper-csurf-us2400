#import "swellappmain.h"

#include "swell.h"
#include "swell-internal.h"


HMENU SWELL_app_stocksysmenu; // exposed to app, simply the contents of the default system menu (as defined in the nib)
static bool IsMultiLineEditControl(NSView *cv, id fs)
{
  if (fs && [fs isKindOfClass:[NSTextView class]])
  {
    NSTextView *v = (NSTextView *)fs;
    if ([v isEditable])
    {
      NSView *a=[v superview];
      while (a && a != cv)
      {
        if ([a isKindOfClass:[NSTextField class]]) return false;
        a = [a superview];
      }
      return true;
    }
  }
  return false;
}

@implementation SWELLApplication
- (void)sendEvent:(NSEvent *)anEvent
{
  int etype = [anEvent type];
  NSWindow *modalWindow = [NSApp modalWindow];
  
  NSWindow *focwnd=[anEvent window];  
  NSView *dest_view=NULL;    // only valid when key message
  
	if (etype==NSKeyDown||etype==NSKeyUp)
	{
    int msgtype = etype==NSKeyDown ? WM_KEYDOWN : WM_KEYUP;
    int flag,code=SWELL_MacKeyToWindowsKey(anEvent,&flag);
    
    if (focwnd)
    {      
      if (flag&(FCONTROL|FALT))
      {
        NSWindow *f = focwnd;    
        // handle carbon windows, sending all cmd/alt modified keys to their parent NSView (to be handled later)
        // perhaps it'd be good to have a flag on these to see if they want it .. i.e. SWELL_SetCarbonHostView_WantKeyFlgs()..
        while (f)
        {
          if ((dest_view=[f delegate]) && [dest_view respondsToSelector:@selector(swellIsCarbonHostingView)] && [(SWELL_hwndCarbonHost*)dest_view swellIsCarbonHostingView])
          {
            focwnd = [dest_view window]; 
            break;
          }
          dest_view=0;
          f=[f parentWindow];
        }
      } 
      if (!dest_view)  // get default dest_view, and validate it as a NSView
      {
        if ((dest_view=(NSView *)[focwnd firstResponder]) && ![dest_view isKindOfClass:[NSView class]]) dest_view=NULL;
      }       
    }       
    if (!modalWindow && (!focwnd || dest_view))
    {          
      MSG msg={(HWND)dest_view,msgtype,(WPARAM)code,(LPARAM)flag}; // LPARAM is treated differently (giving modifier flags/FVIRTKEY etc) in sWELL's WM_KEYDOWN than in windows, deal with it
      
      if (SWELLAppMain(SWELLAPP_PROCESSMESSAGE,(INT_PTR)&msg,(INT_PTR)anEvent)>0) return; 
    }  
  }
  // default window handling:
  if (etype == NSKeyDown && focwnd && dest_view)
  {
    NSView *cv = [focwnd contentView];
    if (cv && [cv respondsToSelector:@selector(onSwellMessage:p1:p2:)]) //only work for swell windows
    {
      int flag,code=SWELL_MacKeyToWindowsKey(anEvent,&flag);
      int cmdid=0;
      
      // todo: other keys (such as shift+insert?)
      if (((flag&~FVIRTKEY)==FCONTROL && (code=='V'||code=='C' ||code=='X')) && [dest_view isKindOfClass:[NSText class]])
      {         
        if (code=='V') [(NSText *)dest_view paste:(id)cv];
        else if (code=='C') [(NSText *)dest_view copy:(id)cv];
        else if (code=='X') [(NSText *)dest_view cut:(id)cv];
        return;
      }
      
      if ((!(flag&~(FVIRTKEY|FSHIFT)) && code == VK_ESCAPE) ||
          ((flag&~FVIRTKEY)==FCONTROL && code=='W'))
      {
        if (code == 'W') cmdid= IDCANCEL; // cmd+w always idcancel's
        else if (!dest_view || ![dest_view isKindOfClass:[NSTextView class]]) cmdid=IDCANCEL; // not text view, idcancel
        else if (!(flag&FSHIFT) && !IsMultiLineEditControl(cv,dest_view)) cmdid=IDCANCEL; // if singleline edit and shift not set, idcancel
        
        if (!cmdid) 
        {
          SetFocus((HWND)cv);
          return;
        }
      }
      else if (!(flag&~FVIRTKEY) && code == VK_RETURN) 
      {      
        // get default button command id, if any, if enabled
        if (!IsMultiLineEditControl(cv,dest_view))
        {            
            cmdid = SWELL_GetDefaultButtonID((HWND)cv,true); 
            
            if (!cmdid) // no action, set focus to parent
            {
              SetFocus((HWND)cv);
              return;
            }
        }
      }
      
      if (cmdid)
      {
        SendMessage((HWND)cv,WM_COMMAND,cmdid,0);
        return;
      }
    } // is swell CV
  } // key down
  
  [super sendEvent:anEvent];
}
@end


@implementation SWELLAppController

- (void)awakeFromNib
{      
  SWELL_EnsureMultithreadedCocoa();
  [NSApp setDelegate:self];

  SWELL_POSTMESSAGE_INIT
  
  HMENU stockMenu=(HMENU)[NSApp mainMenu];
  if (stockMenu)
  {
    HMENU nf = GetSubMenu(stockMenu,0);
    if (nf) SWELL_app_stocksysmenu = SWELL_DuplicateMenu(nf);
  }
  
  SWELLAppMain(SWELLAPP_ONLOAD,0,0);
}

-(IBAction)onSysMenuCommand:(id)sender
{
  int a = [sender tag];
  if (a) SWELLAppMain(SWELLAPP_ONCOMMAND,a,(INT_PTR)sender);
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
  char buf[4096];
  buf[0]=0;
  SWELL_CFStringToCString(filename,buf,sizeof(buf));
  return buf[0] && SWELLAppMain(SWELLAPP_OPENFILE,(INT_PTR)buf,0)>0;
}
- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication
{
  return SWELLAppMain(SWELLAPP_NEWFILE,0,0)>0; 
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
  return SWELLAppMain(SWELLAPP_SHOULDOPENNEWFILE,0,0)>0;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  SWELLAppMain(SWELLAPP_LOADED,0,0);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
  return SWELLAppMain(SWELLAPP_SHOULDDESTROY,0,0) > 0 ? NSTerminateLater : NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
  SWELLAppMain(SWELLAPP_DESTROY,0,0);
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
  if (!SWELLAppMain(SWELLAPP_ACTIVATE,TRUE,0))
    SWELL_BroadcastMessage(WM_ACTIVATEAPP,TRUE,0);
}

- (void)applicationDidResignActive:(NSNotification *)aNotification
{
  if (!SWELLAppMain(SWELLAPP_ACTIVATE,FALSE,0))
    SWELL_BroadcastMessage(WM_ACTIVATEAPP,FALSE,0);
}

SWELL_APPAPI_DELEGATE_IMPL

SWELL_POSTMESSAGE_DELEGATE_IMPL


@end
