#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>


#define UVC_INPUT_TERMINAL_ID 0x01
#define UVC_PROCESSING_UNIT_ID 0x02

#define UVC_CONTROL_INTERFACE_CLASS 14
#define UVC_CONTROL_INTERFACE_SUBCLASS 1
	
#define UVC_SET_CUR	0x01
#define UVC_GET_CUR	0x81
#define UVC_GET_MIN	0x82
#define UVC_GET_MAX	0x83
#define UVC_GET_RES 0x84
#define UVC_GET_LEN 0x85
#define UVC_GET_INFO 0x86
#define UVC_GET_DEF 0x87

typedef struct {
	int min, max, res;
} uvc_range_t;

typedef struct {
    bool supports_get;
    bool supports_set;
    bool supports_autoupdate;
    bool asynchronous;
} uvc_control_capabilities_t;

typedef struct {
	int unit;
	int selector;
	int size;
} uvc_control_info_t;

typedef struct {
	uvc_control_info_t autoExposure;
	uvc_control_info_t exposure;
	uvc_control_info_t brightness;
	uvc_control_info_t contrast;
	uvc_control_info_t gain;
	uvc_control_info_t saturation;
	uvc_control_info_t sharpness;
	uvc_control_info_t whiteBalance;
	uvc_control_info_t autoWhiteBalance;
} uvc_controls_t ;


@interface UVCCameraControl : NSObject {
	long dataBuffer;
	IOUSBInterfaceInterface190 **interface;
    NSMutableDictionary<NSNumber*, NSValue*> *cacheCapabilities;
    NSMutableDictionary<NSNumber*, NSValue*> *cacheRange;
}


- (id)initWithLocationID:(UInt32)locationID;
- (id)initWithVendorID:(long)vendorID productID:(long)productID;
- (IOUSBInterfaceInterface190 **)getControlInferaceWithDeviceInterface:(IOUSBDeviceInterface **)deviceInterface;

- (BOOL)sendControlRequest:(IOUSBDevRequest)controlRequest;
- (BOOL)setData:(long)value withLength:(int)length forSelector:(int)selector at:(int)unitID;
- (long)getDataFor:(int)type withLength:(int)length fromSelector:(int)selector at:(int)unitID;

- (uvc_control_capabilities_t)getCapabilitiesForControl:(const uvc_control_info_t *)control;
- (uvc_range_t)getRangeForControl:(const uvc_control_info_t *)control;
- (float)mapValue:(float)value fromMin:(float)fromMin max:(float)fromMax toMin:(float)toMin max:(float)toMax;
- (float)getValueForControl:(const uvc_control_info_t *)control;
- (BOOL)setValue:(float)value forControl:(const uvc_control_info_t *)control;


// CONTROL: auto exposure
- (BOOL)canSetAutoExposure;
- (BOOL)canGetAutoExposure;
- (BOOL)setAutoExposure:(BOOL)enabled;
- (BOOL)getAutoExposure;

// CONTROL: exposure
- (BOOL)canSetExposure;
- (BOOL)canGetExposure;
- (BOOL)setExposure:(float)value;
- (float)getExposure;

// CONTROL: gain
- (BOOL)canSetGain;
- (BOOL)canGetGain;
- (BOOL)setGain:(float)value;
- (float)getGain;

// CONTROL: brightness
- (BOOL)canSetBrightness;
- (BOOL)canGetBrightness;
- (BOOL)setBrightness:(float)value;
- (float)getBrightness;

// CONTROL: contrast
- (BOOL)canSetContrast;
- (BOOL)canGetContrast;
- (BOOL)setContrast:(float)value;
- (float)getContrast;

// CONTROL: saturation;
- (BOOL)canSetSaturation;
- (BOOL)canGetSaturation;
- (BOOL)setSaturation:(float)value;
- (float)getSaturation;

// CONTROL: sharpness
- (BOOL)canSetSharpness;
- (BOOL)canGetSharpness;
- (BOOL)setSharpness:(float)value;
- (float)getSharpness;

// CONTROL: auto white balance
- (BOOL)canSetAutoWhiteBalance;
- (BOOL)canGetAutoWhiteBalance;
- (BOOL)setAutoWhiteBalance:(BOOL)enabled;
- (BOOL)getAutoWhiteBalance;

// CONTROL: white balance
- (BOOL)canSetWhiteBalance;
- (BOOL)canGetWhiteBalance;
- (BOOL)setWhiteBalance:(float)value;
- (float)getWhiteBalance;

@end
