/** Main-thread AppKit glass for live Electron getNativeWindowHandle() buffers. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <node_api.h>
#include <cmath>
#include <cstring>

namespace {

NSString* const kGlassIdentifier = @"skill.glass-ui.native-liquid-glass";

NSView* IgnoreGlassHitTest(id view, SEL selector, NSPoint point) {
  return nil;
}

API_AVAILABLE(macos(26.0))
NSGlassEffectView* CreateGlassView(NSRect frame) {
  Class type = NSClassFromString(@"SkillGlassPassthroughView");
  if (!type) {
    type = objc_allocateClassPair([NSGlassEffectView class], "SkillGlassPassthroughView", 0);
    if (!type) return nil;
    Method hit_test = class_getInstanceMethod([NSView class], @selector(hitTest:));
    if (!class_addMethod(type, @selector(hitTest:), reinterpret_cast<IMP>(IgnoreGlassHitTest), method_getTypeEncoding(hit_test))) {
      objc_disposeClassPair(type);
      return nil;
    }
    objc_registerClassPair(type);
  }
  return [[type alloc] initWithFrame:frame];
}

bool Check(napi_env env, napi_status status) {
  if (status == napi_ok) return true;
  napi_throw_error(env, nullptr, "Native glass could not create its JavaScript result");
  return false;
}

bool RequireMainThread(napi_env env) {
  if (![NSThread isMainThread] || NSApp == nil) {
    napi_throw_error(env, nullptr, "Native glass requires the Electron main process UI thread");
    return false;
  }
  return true;
}

NSWindow* WindowFromHandle(napi_env env, napi_value value) {
  bool is_buffer = false;
  if (napi_is_buffer(env, value, &is_buffer) != napi_ok || !is_buffer) {
    napi_throw_type_error(env, nullptr, "Expected a getNativeWindowHandle() Buffer");
    return nil;
  }
  void* data = nullptr;
  size_t length = 0;
  if (napi_get_buffer_info(env, value, &data, &length) != napi_ok || length != sizeof(void*)) {
    napi_throw_type_error(env, nullptr, "Native window handle has an invalid pointer size");
    return nil;
  }
  void* address = nullptr;
  std::memcpy(&address, data, sizeof(address));
  if (address == nullptr) {
    napi_throw_type_error(env, nullptr, "Native window handle is null");
    return nil;
  }
  // Handles belong to a live BrowserWindow; callers must not retain them after close.
  NSView* view = (__bridge NSView*)address;
  if (![view isKindOfClass:[NSView class]] || view.window == nil) {
    napi_throw_type_error(env, nullptr, "Native window handle is not attached to a live NSWindow");
    return nil;
  }
  return view.window;
}

NSDictionary* Frame(NSRect frame) {
  return @{ @"x": @(frame.origin.x), @"y": @(frame.origin.y),
            @"width": @(frame.size.width), @"height": @(frame.size.height) };
}

double ColorAlpha(NSColor* color) {
  if (color == nil) return 0;
  NSColor* rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  return rgb ? rgb.alphaComponent : color.alphaComponent;
}

NSDictionary* ViewDetails(NSView* view, NSUInteger depth) {
  NSMutableDictionary* result = [@{
    @"class": NSStringFromClass(view.class), @"frame": Frame(view.frame),
    @"bounds": Frame(view.bounds), @"hidden": @(view.hidden),
    @"alpha": @(view.alphaValue), @"opaque": @(view.opaque),
    @"identifier": view.identifier ?: @"", @"wantsLayer": @(view.wantsLayer),
    @"appearance": view.effectiveAppearance.name ?: @""
  } mutableCopy];
  if (view.layer) {
    result[@"layer"] = @{
      @"class": NSStringFromClass(view.layer.class), @"opaque": @(view.layer.opaque),
      @"opacity": @(view.layer.opacity),
      @"cornerRadius": @(view.layer.cornerRadius), @"masksToBounds": @(view.layer.masksToBounds),
      @"backgroundAlpha": @(view.layer.backgroundColor ? CGColorGetAlpha(view.layer.backgroundColor) : 0)
    };
  }
  if ([view isKindOfClass:[NSVisualEffectView class]]) {
    NSVisualEffectView* effect = (NSVisualEffectView*)view;
    result[@"visualEffect"] = @{ @"material": @(effect.material),
                               @"state": @(effect.state), @"blend": @(effect.blendingMode),
                               @"emphasized": @(effect.emphasized) };
  }
  if (@available(macOS 26.0, *)) {
    if ([view isKindOfClass:[NSGlassEffectView class]]) {
      NSGlassEffectView* glass = (NSGlassEffectView*)view;
      result[@"glassEffect"] = @{ @"style": @(glass.style),
                                 @"cornerRadius": @(glass.cornerRadius),
                                 @"tintAlpha": @(ColorAlpha(glass.tintColor)) };
    }
  }
  if (depth < 7) {
    NSMutableArray* children = [NSMutableArray array];
    for (NSView* child in view.subviews) {
      if (children.count == 40) break;
      [children addObject:ViewDetails(child, depth + 1)];
    }
    result[@"children"] = children;
  }
  return result;
}

napi_value ToJavaScript(napi_env env, id value) {
  napi_value result;
  if (value == nil || value == [NSNull null]) {
    return Check(env, napi_get_null(env, &result)) ? result : nullptr;
  }
  if ([value isKindOfClass:[NSString class]]) {
    const char* text = [(NSString*)value UTF8String];
    return Check(env, napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &result)) ? result : nullptr;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    const bool boolean = CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
    napi_status status = boolean ? napi_get_boolean(env, [(NSNumber*)value boolValue], &result)
                                 : napi_create_double(env, [(NSNumber*)value doubleValue], &result);
    return Check(env, status) ? result : nullptr;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSArray* array = (NSArray*)value;
    if (!Check(env, napi_create_array_with_length(env, array.count, &result))) return nullptr;
    for (NSUInteger index = 0; index < array.count; index++) {
      napi_value child = ToJavaScript(env, array[index]);
      if (!child || !Check(env, napi_set_element(env, result, static_cast<uint32_t>(index), child))) return nullptr;
    }
    return result;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    if (!Check(env, napi_create_object(env, &result))) return nullptr;
    for (NSString* key in (NSDictionary*)value) {
      napi_value child = ToJavaScript(env, [(NSDictionary*)value objectForKey:key]);
      if (!child || !Check(env, napi_set_named_property(env, result, key.UTF8String, child))) return nullptr;
    }
    return result;
  }
  napi_throw_error(env, nullptr, "Native glass diagnostic value is unsupported");
  return nullptr;
}

// Match the web panel contour at the ancestor of every native backdrop/content layer.
napi_value SetContour(napi_env env, napi_callback_info info) {
  @autoreleasepool {
    if (!RequireMainThread(env)) return nullptr;
    size_t argc = 2;
    napi_value args[2];
    if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
    double radius;
    if (argc != 2 || napi_get_value_double(env, args[1], &radius) != napi_ok || !std::isfinite(radius) || radius < 0 || radius > 100) {
      napi_throw_type_error(env, nullptr, "setContour requires a live native handle and radius between 0 and 100");
      return nullptr;
    }
    NSWindow* window = WindowFromHandle(env, args[0]);
    if (!window) return nullptr;
    NSView* content = window.contentView;
    content.wantsLayer = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    content.layer.cornerRadius = radius;
    content.layer.cornerCurve = kCACornerCurveCircular;
    content.layer.masksToBounds = radius > 0;
    // Explicitly mask all four corners; NSView flipping does not change this contour.
    content.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    [CATransaction commit];
    return args[1];
  }
}

napi_value SetGlass(napi_env env, napi_callback_info info) {
  @autoreleasepool {
    if (!RequireMainThread(env)) return nullptr;
    size_t argc = 2;
    napi_value args[2];
    if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
    if (argc != 2) {
      napi_throw_type_error(env, nullptr, "setGlass requires a native handle and an enabled boolean");
      return nullptr;
    }
    bool enabled;
    if (napi_get_value_bool(env, args[1], &enabled) != napi_ok) {
      napi_throw_type_error(env, nullptr, "Glass enabled must be a boolean");
      return nullptr;
    }
    NSWindow* window = WindowFromHandle(env, args[0]);
    if (!window) return nullptr;
    NSView* content = window.contentView;
    for (NSView* child in [content.subviews copy]) {
      if ([child.identifier isEqualToString:kGlassIdentifier]) [child removeFromSuperview];
    }
    if (!enabled) {
      napi_value result;
      return Check(env, napi_get_boolean(env, false, &result)) ? result : nullptr;
    }
    if (@available(macOS 26.0, *)) {
      window.opaque = NO;
      window.backgroundColor = [NSColor clearColor];
      NSGlassEffectView* glass = CreateGlassView(content.bounds);
      if (!glass) {
        napi_throw_error(env, nullptr, "Could not create the native passthrough glass view");
        return nullptr;
      }
      glass.identifier = kGlassIdentifier;
      glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
      glass.style = NSGlassEffectViewStyleClear;
      glass.tintColor = nil;
      glass.cornerRadius = 28;
      // A direct bottom sibling samples the desktop instead of the web CALayerHost.
      [content addSubview:glass positioned:NSWindowBelow relativeTo:nil];
      napi_value result;
      return Check(env, napi_get_boolean(env, enabled, &result)) ? result : nullptr;
    }
    napi_throw_error(env, nullptr, "Native Liquid Glass requires macOS 26 or newer");
    return nullptr;
  }
}

NSUInteger SetIndependentEffectOpacity(NSView* view, CGFloat opacity) {
  NSUInteger adjusted = 0;
  if ([view isKindOfClass:[NSVisualEffectView class]]) {
    NSVisualEffectView* effect = (NSVisualEffectView*)view;
    // Alpha affects descendants too, so only change separate background leaves.
    if (effect.blendingMode == NSVisualEffectBlendingModeBehindWindow && effect.subviews.count == 0) {
      effect.alphaValue = opacity;
      adjusted++;
    }
  }
  for (NSView* child in view.subviews) adjusted += SetIndependentEffectOpacity(child, opacity);
  return adjusted;
}

napi_value SetFrostedOpacity(napi_env env, napi_callback_info info) {
  @autoreleasepool {
    if (!RequireMainThread(env)) return nullptr;
    size_t argc = 2;
    napi_value args[2];
    if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
    if (argc != 2) {
      napi_throw_type_error(env, nullptr, "setFrostedOpacity requires a native handle and an opacity number");
      return nullptr;
    }
    double opacity;
    if (napi_get_value_double(env, args[1], &opacity) != napi_ok || !std::isfinite(opacity) || opacity < 0.0 || opacity > 1.0) {
      napi_throw_type_error(env, nullptr, "Frosted opacity must be a finite number between zero and one");
      return nullptr;
    }
    NSWindow* window = WindowFromHandle(env, args[0]);
    if (!window) return nullptr;
    const NSUInteger adjusted = SetIndependentEffectOpacity(window.contentView, static_cast<CGFloat>(opacity));
    napi_value result;
    return Check(env, napi_create_double(env, static_cast<double>(adjusted), &result)) ? result : nullptr;
  }
}

napi_value LeftMouseDown(napi_env env, napi_callback_info info) {
  napi_value result;
  return Check(env, napi_get_boolean(env, CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft), &result)) ? result : nullptr;
}

napi_value SetReveal(napi_env env, napi_callback_info info) {
  @autoreleasepool {
    if (!RequireMainThread(env)) return nullptr;
    size_t argc = 3; napi_value args[3];
    if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
    double width, height;
    if (argc != 3 || napi_get_value_double(env, args[1], &width) != napi_ok || napi_get_value_double(env, args[2], &height) != napi_ok || !std::isfinite(width) || !std::isfinite(height)) {
      napi_throw_type_error(env, nullptr, "setReveal requires a handle and finite reveal dimensions"); return nullptr;
    }
    NSWindow* window = WindowFromHandle(env, args[0]); if (!window) return nullptr;
    NSView* content = window.contentView; content.wantsLayer = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (width <= 0 || height <= 0) { content.layer.mask = nil; }
    else {
      const CGFloat w = MIN(width, content.bounds.size.width), h = MIN(height, content.bounds.size.height);
      const CGFloat y = content.layer.geometryFlipped ? 0 : content.bounds.size.height - h;
      CAShapeLayer* mask = [content.layer.mask isKindOfClass:[CAShapeLayer class]] ? (CAShapeLayer*)content.layer.mask : [CAShapeLayer layer];
      mask.frame = content.bounds;
      CGPathRef path = CGPathCreateWithRoundedRect(CGRectMake((content.bounds.size.width-w)/2, y, w, h), MIN(28, h/2), MIN(28, h/2), NULL);
      mask.path = path; CGPathRelease(path); content.layer.mask = mask;
    }
    // The native glass rim must follow the revealed drawer, not the offscreen full panel.
    if (@available(macOS 26.0, *)) {
      for (NSView* child in content.subviews) {
        if ([child.identifier isEqualToString:kGlassIdentifier]) {
          const BOOL reveal = width > 0 && height > 0;
          const CGFloat w = reveal ? MIN(width, content.bounds.size.width) : content.bounds.size.width;
          const CGFloat h = reveal ? MIN(height, content.bounds.size.height) : content.bounds.size.height;
          const CGFloat y = content.isFlipped ? 0 : content.bounds.size.height - h;
          child.frame = NSMakeRect((content.bounds.size.width-w)/2, y, w, h);
          ((NSGlassEffectView*)child).cornerRadius = MIN(28, h/2);
        }
      }
    }
    [CATransaction commit]; return args[1];
  }
}

napi_value SetAppearance(napi_env env, napi_callback_info info) {
  @autoreleasepool {
    if (!RequireMainThread(env)) return nullptr;
    size_t argc = 2;
    napi_value args[2];
    if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
    if (argc != 2) {
      napi_throw_type_error(env, nullptr, "setAppearance requires a native handle and a light, dark, or system tone");
      return nullptr;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, args[1], nullptr, 0, &length) != napi_ok || length > 6) {
      napi_throw_type_error(env, nullptr, "Native appearance must be light, dark, or system");
      return nullptr;
    }
    char tone[7];
    if (!Check(env, napi_get_value_string_utf8(env, args[1], tone, sizeof(tone), &length))) return nullptr;
    const bool light = length == 5 && std::memcmp(tone, "light", 5) == 0;
    const bool dark = length == 4 && std::memcmp(tone, "dark", 4) == 0;
    const bool system = length == 6 && std::memcmp(tone, "system", 6) == 0;
    if (!light && !dark && !system) {
      napi_throw_type_error(env, nullptr, "Native appearance must be light, dark, or system");
      return nullptr;
    }
    NSWindow* window = WindowFromHandle(env, args[0]);
    if (!window) return nullptr;
    NSAppearance* appearance = system ? nil : [NSAppearance appearanceNamed:light ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    if (!system && appearance == nil) {
      napi_throw_error(env, nullptr, "Could not resolve the native glass appearance");
      return nullptr;
    }
    window.appearance = appearance;
    return args[1];
  }
}

napi_value Inspect(napi_env env, napi_callback_info info) {
  @autoreleasepool {
    if (!RequireMainThread(env)) return nullptr;
    size_t argc = 1;
    napi_value args[1];
    if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
    if (argc != 1) {
      napi_throw_type_error(env, nullptr, "inspect requires a native window handle");
      return nullptr;
    }
    NSWindow* window = WindowFromHandle(env, args[0]);
    if (!window) return nullptr;
    bool supported = false;
    if (@available(macOS 26.0, *)) supported = true;
    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    return ToJavaScript(env, @{
      @"glassSupported": @(supported), @"windowNumber": @(window.windowNumber),
      @"windowClass": NSStringFromClass(window.class), @"windowOpaque": @(window.opaque),
      @"windowAppearance": window.appearance.name ?: @"", @"effectiveAppearance": window.effectiveAppearance.name ?: @"",
      @"windowBackgroundAlpha": @(ColorAlpha(window.backgroundColor)),
      @"windowAlpha": @(window.alphaValue), @"windowVisible": @(window.visible),
      @"windowKey": @(window.keyWindow), @"windowMain": @(window.mainWindow),
      @"titlebarTransparent": @(window.titlebarAppearsTransparent),
      @"reduceTransparency": @(workspace.accessibilityDisplayShouldReduceTransparency),
      @"increaseContrast": @(workspace.accessibilityDisplayShouldIncreaseContrast),
      @"frame": Frame(window.frame), @"contentView": ViewDetails(window.contentView, 0)
    });
  }
}

napi_value Initialize(napi_env env, napi_value exports) {
  const napi_property_descriptor properties[] = {
    { "setGlass", nullptr, SetGlass, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "setFrostedOpacity", nullptr, SetFrostedOpacity, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "setAppearance", nullptr, SetAppearance, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "setContour", nullptr, SetContour, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "leftMouseDown", nullptr, LeftMouseDown, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "setReveal", nullptr, SetReveal, nullptr, nullptr, nullptr, napi_default, nullptr },
    { "inspect", nullptr, Inspect, nullptr, nullptr, nullptr, napi_default, nullptr }
  };
  return Check(env, napi_define_properties(env, exports, 7, properties)) ? exports : nullptr;
}

}  // namespace

NAPI_MODULE(native_glass, Initialize)
