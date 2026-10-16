#!/usr/bin/env python3
"""Test the production halo kernel; optionally render its UIKit image in Simulator."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--simulator')
parser.add_argument('--gallery', type=Path, default=ROOT.parent / 'Eagle-Gallery')
args = parser.parse_args()
work = Path(tempfile.mkdtemp(prefix='eagle-glow-qa-'))
header = ROOT / 'lara/views/new/DockGalleryGlow.h'
test = r'''
#include <assert.h>
#include <stdio.h>
int main(void) {
    double h = EAGLE_DOCK_GLOW_HEIGHT;
    for (double w = 250; w <= 570; w += 20) {
        for (double x = -w / 2 - 56; x <= w / 2 + 56; x += 2) {
            for (double y = -h / 2 - 56; y <= h / 2 + 56; y += 2) {
                double a = eagle_dock_glow_alpha(x, y, w, h);
                assert(isfinite(a) && a >= 0 && a <= 1);
                assert(fabs(a - eagle_dock_glow_alpha(-x, y, w, h)) < 1e-12);
                assert(fabs(a - eagle_dock_glow_alpha(x, -y, w, h)) < 1e-12);
            }
            assert(eagle_dock_glow_alpha(x, h / 2 + 56, w, h) == 0);
            assert(eagle_dock_glow_alpha(x, -h / 2 - 56, w, h) == 0);
        }
        double last = 1;
        for (double d = 0; d <= 56; d += 0.1) {
            double a = eagle_dock_glow_alpha(0, h / 2 + d, w, h);
            assert(a <= last + 1e-12);
            last = a;
        }
        assert(eagle_dock_glow_alpha(w / 2 + 56, 0, w, h) == 0);
        assert(eagle_dock_glow_alpha(-w / 2 - 56, 0, w, h) == 0);
        assert(eagle_dock_glow_alpha(0, h / 2 + 8, w, h) > 0.8);
        assert(eagle_dock_glow_alpha(0, h / 2 + 25, w, h) > 0.25);
        assert(eagle_dock_glow_alpha(0, h / 2 + 55.9, w, h) < 0.00001);
    }
    puts("PASS: 17 device widths; bounded/symmetric/monotonic halo; transparent edges; visible light");
}
'''
cfile = work / 'kernel.c'
cfile.write_text(f'#include "{header}"\n' + test)
subprocess.run(['clang', str(cfile), '-o', str(work / 'kernel')], check=True)
subprocess.run([str(work / 'kernel')], check=True)

source = (ROOT / 'lara/kexploit/pe/rc.m').read_text()
swift = (ROOT / 'lara/views/new/DockGalleryView.swift').read_text()
assert 'eagle_dock_gallery_glow_image(' in swift
assert 'eagle_dock_gallery_glow_image(red, green, blue, outlineWidth, outlineHeight)' in source
assert 'glowView, "alpha", galleryShadowOpacity' in source
flow = (ROOT / 'lara/EagleCore/DockGallery/EagleDockGalleryApplyFlow.swift').read_text()
assert 'let requestedIntensity = intensity()' in flow and 'intensity: requestedIntensity' in flow
assert 'intensity: { glowIntensity }' in swift
assert 'outlineY = -3.0;' in source and 'outlineHeight = 102.333333;' in source
print('PASS: preview/application share renderer and captured intensity; calibrated footprint retained')
if not args.simulator:
    raise SystemExit(0)

start = source.index('double eagle_dock_gallery_glow_padding(void)')
end = source.index('static char eagle_remote_dock_directory', start)
renderer = source[start:end]
main = r'''
static void require(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(int argc, char **argv) { @autoreleasepool {
    NSString *gallery = @(argv[1]), *output = @(argv[2]);
    NSDictionary *catalog = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:[gallery stringByAppendingPathComponent:@"catalogs/dock-v1.json"]]
        options:0 error:nil];
    NSArray *themes = catalog[@"themes"];
    NSArray *ids = @[@"bubblegum", @"springfield", @"bikini-bottom", @"walking-flame"];
    NSMutableArray *chosen = [NSMutableArray new];
    for (NSDictionary *theme in themes) if ([ids containsObject:theme[@"id"]]) [chosen addObject:theme];
    require(chosen.count >= 3, @"Need representative artwork");
    double width = 372, height = 102.333333, pad = eagle_dock_gallery_glow_padding();
    require(eagle_dock_gallery_glow_image(1,2,3,NAN,height) == nil, @"Reject invalid geometry");
    for (BOOL dark = NO; ; dark = YES) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 2;
        UIGraphicsImageRenderer *sheet = [[UIGraphicsImageRenderer alloc]
            initWithSize:CGSizeMake(3 * 500, chosen.count * 250) format:format];
        UIImage *result = [sheet imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [(dark ? UIColor.blackColor : UIColor.whiteColor) setFill];
            UIRectFill(CGRectMake(0,0,1500,chosen.count * 250));
            for (NSUInteger row = 0; row < chosen.count; row++) {
                NSDictionary *theme = chosen[row];
                unsigned int hex = 0;
                [[NSScanner scannerWithString:[theme[@"accent"] substringFromIndex:1]] scanHexInt:&hex];
                int r = hex >> 16 & 255, g = hex >> 8 & 255, b = hex & 255;
                UIImage *halo = eagle_dock_gallery_glow_image(r,g,b,width,height);
                require(halo != nil && halo.scale == 3, @"Render @3x halo");
                require(halo == eagle_dock_gallery_glow_image(r,g,b,width,height), @"Cache identical image");
                NSData *png = UIImagePNGRepresentation(halo);
                UIImage *remoteCopy = [UIImage imageWithData:png];
                require(remoteCopy != nil, @"PNG transfer survives decode");
                CFDataRef raw = CGDataProviderCopyData(CGImageGetDataProvider(halo.CGImage));
                const UInt8 *pixels = CFDataGetBytePtr(raw);
                size_t pw = CGImageGetWidth(halo.CGImage), ph = CGImageGetHeight(halo.CGImage);
                for (size_t y=0; y<ph; y++) for (size_t x=0; x<pw; x++) {
                    size_t i = (y*pw+x)*4;
                    int a = pixels[i+3];
                    require(pixels[i] <= a && pixels[i+1] <= a && pixels[i+2] <= a, @"Premultiplied RGBA");
                    if (a > 32) {
                        require(abs(pixels[i]*255-r*a) <= 255, @"Preserve red hue");
                        require(abs(pixels[i+1]*255-g*a) <= 255, @"Preserve green hue");
                        require(abs(pixels[i+2]*255-b*a) <= 255, @"Preserve blue hue");
                    }
                    if (x==0 || y==0 || x==pw-1 || y==ph-1) require(a==0, @"No rectangular halo edge");
                }
                CFRelease(raw);
                NSString *artPath = [gallery stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"previews/%@.png", theme[@"id"]]];
                UIImage *art = [UIImage imageWithContentsOfFile:artPath];
                require(art != nil, @"Artwork exists");
                for (int col = 0; col < 3; col++) {
                    CGFloat amount = col / 2.0;
                    CGRect dock = CGRectMake(col*500+64,row*250+75,width,height);
                    [remoteCopy drawInRect:CGRectInset(dock,-pad,-pad) blendMode:kCGBlendModeNormal alpha:amount];
                    CGContextSaveGState(ctx.CGContext);
                    [[UIBezierPath bezierPathWithRoundedRect:dock cornerRadius:40] addClip];
                    CGFloat scale = MAX(width/art.size.width,height/art.size.height);
                    CGSize size = CGSizeMake(art.size.width*scale, art.size.height*scale);
                    [art drawInRect:CGRectMake(CGRectGetMidX(dock)-size.width/2,CGRectGetMidY(dock)-size.height/2,size.width,size.height)];
                    CGContextRestoreGState(ctx.CGContext);
                    NSString *label = [NSString stringWithFormat:@"%@ · %.0f%% · %@",theme[@"title"],amount*100,theme[@"accent"]];
                    [label drawAtPoint:CGPointMake(col*500+30,row*250+20) withAttributes:@{
                        NSFontAttributeName:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold],
                        NSForegroundColorAttributeName:dark ? UIColor.whiteColor : UIColor.blackColor}];
                }
            }
        }];
        require([UIImagePNGRepresentation(result) writeToFile:[output stringByAppendingPathComponent:
            dark ? @"dark.png" : @"light.png"] atomically:YES], @"Save visual QA");
        if (dark) break;
    }
    puts("PASS: production UIKit raster, PNG transfer, exact RGB, alpha boundaries, cache, light/dark 0/50/100 previews");
} return 0; }
'''
objc = work / 'render.m'
objc.write_text('#import <UIKit/UIKit.h>\n#include "' + str(header) + '"\n' + renderer + main)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
binary = work / 'render'
subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'clang', '-fobjc-arc', '-fmodules',
    '-target', 'arm64-apple-ios16.0-simulator', '-isysroot', sdk, '-framework', 'UIKit',
    '-framework', 'Foundation', str(objc), '-o', str(binary)], check=True)
subprocess.run(['xcrun', 'simctl', 'spawn', args.simulator, str(binary), str(args.gallery), str(work)], check=True)
print(f'Visual QA: {work}')
