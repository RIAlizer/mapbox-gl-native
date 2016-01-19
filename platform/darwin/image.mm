#include <mbgl/util/image.hpp>

#import <ImageIO/ImageIO.h>

#import <webp/decode.h>

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

namespace mbgl {

std::string encodePNG(const PremultipliedImage& src) {
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, src.data.get(), src.size(), NULL);
    if (!provider) {
        return "";
    }

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    if (!color_space) {
        CGDataProviderRelease(provider);
        return "";
    }

    CGImageRef image = CGImageCreate(src.width, src.height, 8, 32, 4 * src.width, color_space,
        kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast, provider, NULL, false,
        kCGRenderingIntentDefault);
    if (!image) {
        CGColorSpaceRelease(color_space);
        CGDataProviderRelease(provider);
        return "";
    }

    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    if (!data) {
        CGImageRelease(image);
        CGColorSpaceRelease(color_space);
        CGDataProviderRelease(provider);
        return "";
    }

    CGImageDestinationRef image_destination = CGImageDestinationCreateWithData(data, kUTTypePNG, 1, NULL);
    if (!image_destination) {
        CFRelease(data);
        CGImageRelease(image);
        CGColorSpaceRelease(color_space);
        CGDataProviderRelease(provider);
        return "";
    }

    CGImageDestinationAddImage(image_destination, image, NULL);
    CGImageDestinationFinalize(image_destination);

    const std::string result {
        reinterpret_cast<const char *>(CFDataGetBytePtr(data)),
        static_cast<size_t>(CFDataGetLength(data))
    };

    CFRelease(image_destination);
    CFRelease(data);
    CGImageRelease(image);
    CGColorSpaceRelease(color_space);
    CGDataProviderRelease(provider);

    return result;
}

CGImageRef decodeWebP(CFDataRef data) {
    int width = 0, height = 0;
    void* webp = WebPDecodeARGB(CFDataGetBytePtr(data), CFDataGetLength(data), &width, &height);

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    if (!color_space) {
        free(webp);
        throw std::runtime_error("CGColorSpaceCreateDeviceRGB failed");
    }

    CGContextRef context = CGBitmapContextCreate(webp, width, height, 8, width * 4, color_space, kCGImageAlphaNoneSkipFirst);
    if (!context) {
        CGColorSpaceRelease(color_space);
        free(webp);
        throw std::runtime_error("CGBitmapContextCreate failed");
    }

    CGImageRef image = CGBitmapContextCreateImage(context);
    if (!image) {
        CGContextRelease(context);
        CGColorSpaceRelease(color_space);
        free(webp);
        throw std::runtime_error("CGBitmapContextCreateImage failed");
    }

    return image;
}

PremultipliedImage decodeImage(const std::string &source_data) {
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<const unsigned char *>(source_data.data()), source_data.size(), kCFAllocatorNull);
    if (!data) {
        throw std::runtime_error("CFDataCreateWithBytesNoCopy failed");
    }

    CGImageSourceRef image_source = CGImageSourceCreateWithData(data, NULL);
    if (!image_source) {
        CFRelease(data);
        throw std::runtime_error("CGImageSourceCreateWithData failed");
    }

    CGImageRef image = nil;

    // CoreFoundation does not decode WebP natively.
    if (CFDataGetLength(data) >= 12) {
        const uint8_t* dataPtr = CFDataGetBytePtr(data);
        uint32_t riff_magic = (dataPtr[0] << 24) | (dataPtr[1] << 16) | (dataPtr[2] << 8) | dataPtr[3];
        uint32_t webp_magic = (dataPtr[8] << 24) | (dataPtr[9] << 16) | (dataPtr[10] << 8) | dataPtr[11];
        if (riff_magic == 0x52494646 && webp_magic == 0x57454250) {
            image = decodeWebP(data);
        }
    }

    if (!image) {
        image = CGImageSourceCreateImageAtIndex(image_source, 0, NULL);
        if (!image) {
            CFRelease(image_source);
            CFRelease(data);
            throw std::runtime_error("CGImageSourceCreateImageAtIndex failed");
        }
    }

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    if (!color_space) {
        CGImageRelease(image);
        CFRelease(image_source);
        CFRelease(data);
        throw std::runtime_error("CGColorSpaceCreateDeviceRGB failed");
    }

    PremultipliedImage result { CGImageGetWidth(image), CGImageGetHeight(image) };

    CGContextRef context = CGBitmapContextCreate(result.data.get(), result.width, result.height, 8, result.stride(),
        color_space, kCGImageAlphaPremultipliedLast);
    if (!context) {
        CGColorSpaceRelease(color_space);
        CGImageRelease(image);
        CFRelease(image_source);
        CFRelease(data);
        throw std::runtime_error("CGBitmapContextCreate failed");
    }

    CGContextSetBlendMode(context, kCGBlendModeCopy);

    CGRect rect = {{ 0, 0 }, { static_cast<CGFloat>(result.width), static_cast<CGFloat>(result.height) }};
    CGContextDrawImage(context, rect, image);

    CGContextRelease(context);
    CGColorSpaceRelease(color_space);
    CGImageRelease(image);
    CFRelease(image_source);
    CFRelease(data);

    return result;
}

}
