#import "UVCCameraControl.h"


const uvc_controls_t uvc_controls = {
	.autoExposure = {
		.unit = UVC_INPUT_TERMINAL_ID,
		.selector = 0x02,
		.size = 1,
	},
	.exposure = {
		.unit = UVC_INPUT_TERMINAL_ID,
		.selector = 0x04,
		.size = 4,
	},
	.brightness = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x02,
		.size = 2,
	},
	.contrast = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x03,
		.size = 2,
	},
	.gain = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x04,
		.size = 2,
	},
	.saturation = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x07,
		.size = 2,
	},
	.sharpness = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x08,
		.size = 2,
	},
	.whiteBalance = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x0A,
		.size = 2,
	},
	.autoWhiteBalance = {
		.unit = UVC_PROCESSING_UNIT_ID,
		.selector = 0x0B,
		.size = 1,
	},
};


@implementation UVCCameraControl


- (id)initWithLocationID:(UInt32)locationID {
	if( self = [super init] ) {
		interface = NULL;
		
		// Find All USB Devices, get their locationId and check if it matches the requested one
		CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
		io_iterator_t serviceIterator;
		IOServiceGetMatchingServices( kIOMasterPortDefault, matchingDict, &serviceIterator );
		
		io_service_t camera;
        while ((camera = IOIteratorNext(serviceIterator))) {
            
			// Get DeviceInterface
			IOUSBDeviceInterface **deviceInterface = NULL;
			IOCFPlugInInterface	**plugInInterface = NULL;
			SInt32 score;
			kern_return_t kr = IOCreatePlugInInterfaceForService( camera, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score );
			if( (kIOReturnSuccess != kr) || !plugInInterface ) {
				NSLog( @"CameraControl Error: IOCreatePlugInInterfaceForService returned 0x%08x.", kr );
				continue;
			}
			
			HRESULT res = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*) &deviceInterface );
			(*plugInInterface)->Release(plugInInterface);
			if( res || deviceInterface == NULL ) {
				NSLog( @"CameraControl Error: QueryInterface returned %d.\n", (int)res );
				continue;
			}
			
			UInt32 currentLocationID = 0;
			(*deviceInterface)->GetLocationID(deviceInterface, &currentLocationID);
			
			if( currentLocationID == locationID ) {
				// Yep, this is the USB Device that was requested!
				interface = [self getControlInferaceWithDeviceInterface:deviceInterface];
				return self;
			}
		} // end while
		
	}
	return self;
}


- (id)initWithVendorID:(long)vendorID productID:(long)productID {
	if( self = [super init] ) {
		interface = NULL;
		
		// Find USB Device
		CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
		CFNumberRef numberRef;
		
		numberRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &vendorID);
		CFDictionarySetValue( matchingDict, CFSTR(kUSBVendorID), numberRef );
		CFRelease(numberRef);
		
		numberRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &productID);
		CFDictionarySetValue( matchingDict, CFSTR(kUSBProductID), numberRef );
		CFRelease(numberRef);
		io_service_t camera = IOServiceGetMatchingService( kIOMasterPortDefault, matchingDict );
		
		
		// Get DeviceInterface
		IOUSBDeviceInterface **deviceInterface = NULL;
		IOCFPlugInInterface	**plugInInterface = NULL;
		SInt32 score;
		kern_return_t kr = IOCreatePlugInInterfaceForService( camera, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score );
        if( (kIOReturnSuccess != kr) || !plugInInterface ) {
            NSLog( @"CameraControl Error: IOCreatePlugInInterfaceForService returned 0x%08x.", kr );
			return self;
        }
		
        HRESULT res = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*) &deviceInterface );
        (*plugInInterface)->Release(plugInInterface);
        if( res || deviceInterface == NULL ) {
            NSLog( @"CameraControl Error: QueryInterface returned %d.\n", (int)res );
            return self;
        }
		
		interface = [self getControlInferaceWithDeviceInterface:deviceInterface];
	}
	return self;
}


- (IOUSBInterfaceInterface190 **)getControlInferaceWithDeviceInterface:(IOUSBDeviceInterface **)deviceInterface {
	IOUSBInterfaceInterface190 **controlInterface;
	
	io_iterator_t interfaceIterator;
	IOUSBFindInterfaceRequest interfaceRequest;
	interfaceRequest.bInterfaceClass = UVC_CONTROL_INTERFACE_CLASS;
	interfaceRequest.bInterfaceSubClass = UVC_CONTROL_INTERFACE_SUBCLASS;
	interfaceRequest.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
	interfaceRequest.bAlternateSetting = kIOUSBFindInterfaceDontCare;
	
	IOReturn success = (*deviceInterface)->CreateInterfaceIterator( deviceInterface, &interfaceRequest, &interfaceIterator );
	if( success != kIOReturnSuccess ) {
		return NULL;
	}
	
	io_service_t usbInterface;
	HRESULT result;
	
	
    if ((usbInterface = IOIteratorNext(interfaceIterator))) {
		IOCFPlugInInterface **plugInInterface = NULL;
		
		//Create an intermediate plug-in
		SInt32 score;
		kern_return_t kr = IOCreatePlugInInterfaceForService( usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score );
		
		//Release the usbInterface object after getting the plug-in
		kr = IOObjectRelease(usbInterface);
		if( (kr != kIOReturnSuccess) || !plugInInterface ) {
			NSLog( @"CameraControl Error: Unable to create a plug-in (%08x)\n", kr );
			return NULL;
		}
		
		//Now create the device interface for the interface
		result = (*plugInInterface)->QueryInterface( plugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID *) &controlInterface );
		
		//No longer need the intermediate plug-in
		(*plugInInterface)->Release(plugInInterface);
		
		if( result || !controlInterface ) {
			NSLog( @"CameraControl Error: Couldn’t create a device interface for the interface (%08x)", (int) result );
			return NULL;
		}
		
		return controlInterface;
	}
	
	return NULL;
}


- (void)dealloc {
	if( interface ) {
		(*interface)->USBInterfaceClose(interface);
		(*interface)->Release(interface);
	}
}


- (BOOL)sendControlRequest:(IOUSBDevRequest)controlRequest {
	if( !interface ){
		NSLog( @"CameraControl Error: No interface to send request" );
		return NO;
	}
	
	//Now open the interface. This will cause the pipes associated with
	//the endpoints in the interface descriptor to be instantiated
	kern_return_t kr = (*interface)->USBInterfaceOpen(interface);
	if (kr != kIOReturnSuccess)	{
		NSLog( @"CameraControl Error: Unable to open interface (%08x)\n", kr );
		return NO;
	}
	
	kr = (*interface)->ControlRequest( interface, 0, &controlRequest );
	if( kr != kIOReturnSuccess ) {
        NSLog( @"CameraControl Error: Control request failed: %08x", kr );
		kr = (*interface)->USBInterfaceClose(interface);
		return NO;
	}
	
	kr = (*interface)->USBInterfaceClose(interface);
	
	return YES;
}


- (BOOL)setData:(long)value withLength:(int)length forSelector:(int)selector at:(int)unitId {
	IOUSBDevRequest controlRequest;
	controlRequest.bmRequestType = USBmakebmRequestType( kUSBOut, kUSBClass, kUSBInterface );
	controlRequest.bRequest = UVC_SET_CUR;
	controlRequest.wValue = (selector << 8) | 0x00;
	controlRequest.wIndex = (unitId << 8) | 0x00;
	controlRequest.wLength = length;
	controlRequest.wLenDone = 0;
	controlRequest.pData = &value;
	return [self sendControlRequest:controlRequest];
}


- (long)getDataFor:(int)type withLength:(int)length fromSelector:(int)selector at:(int)unitId {
	long value = 0;
	IOUSBDevRequest controlRequest;
	controlRequest.bmRequestType = USBmakebmRequestType( kUSBIn, kUSBClass, kUSBInterface );
	controlRequest.bRequest = type;
	controlRequest.wValue = (selector << 8) | 0x00;
	controlRequest.wIndex = (unitId << 8) | 0x00;
	controlRequest.wLength = length;
	controlRequest.wLenDone = 0;
	controlRequest.pData = &value;
	BOOL success = [self sendControlRequest:controlRequest];
	return ( success ? value : 0 );
}

- (uvc_control_capabilities_t)getCapabilitiesForControl:(const uvc_control_info_t *)control {
    uvc_control_capabilities_t capabilities = { false, false , false, false };
    
    // check cache
    NSNumber *cacheKey = [NSNumber numberWithInt:(control->selector << 8) + control->unit];
    NSValue *cacheValue = [cacheCapabilities objectForKey:cacheKey];
    if (cacheValue) {
        [cacheValue getValue:&capabilities];
        return capabilities;
    }
    
    // fetch capabilities
    long response = [self getDataFor:UVC_GET_INFO withLength:control->size fromSelector:control->selector at:control->unit];
    capabilities.supports_get = (response & 0x1) > 0;
    capabilities.supports_set = (response & 0x2) > 0;
    capabilities.supports_autoupdate = (response & 0x8) > 0;
    capabilities.asynchronous = (response & 0x16) > 0;
    
    // add to cache
    cacheValue = [NSValue valueWithBytes:&capabilities objCType:@encode(uvc_control_capabilities_t)];
    [cacheCapabilities setObject:cacheValue forKey:cacheKey];
    
    return capabilities;
}


// Get Range (min, max)
- (uvc_range_t)getRangeForControl:(const uvc_control_info_t *)control {
    uvc_range_t range = { 0, 0, 0 };
    
    // check cache
    NSNumber *cacheKey = [NSNumber numberWithInt:(control->selector << 8) + control->unit];
    NSValue *cacheValue = [cacheRange objectForKey:cacheKey];
    if (cacheValue) {
        [cacheValue getValue:&range];
        return range;
    }
    
    // fetch range data
	range.min = (int)[self getDataFor:UVC_GET_MIN withLength:control->size fromSelector:control->selector at:control->unit];
	range.max = (int)[self getDataFor:UVC_GET_MAX withLength:control->size fromSelector:control->selector at:control->unit];
    range.res = (int)[self getDataFor:UVC_GET_RES withLength:control->size fromSelector:control->selector at:control->unit];
    
    // add to cache
    cacheValue = [NSValue valueWithBytes:&range objCType:@encode(uvc_range_t)];
    [cacheRange setObject:cacheValue forKey:cacheKey];
    
	return range;
}


// Used to de-/normalize values
- (float)mapValue:(float)value fromMin:(float)fromMin max:(float)fromMax toMin:(float)toMin max:(float)toMax {
	return toMin + (toMax - toMin) * ((value - fromMin) / (fromMax - fromMin));
}


// Get a normalized value
- (float)getValueForControl:(const uvc_control_info_t *)control {
	uvc_range_t range = [self getRangeForControl:control];
	
	int intval = (int)[self getDataFor:UVC_GET_CUR withLength:control->size fromSelector:control->selector at:control->unit];
	return [self mapValue:intval fromMin:range.min max:range.max toMin:0 max:1];
}


// Set a normalized value
- (BOOL)setValue:(float)value forControl:(const uvc_control_info_t *)control {
	uvc_range_t range = [self getRangeForControl:control];
	
	int intval = [self mapValue:value fromMin:0 max:1 toMin:range.min max:range.max];
	return [self setData:intval withLength:control->size forSelector:control->selector at:control->unit];
}





// ================================================================

// Set/Get the actual values for the camera
//

// CONTROL: auto exposure

- (BOOL)canSetAutoExposure {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.autoExposure];
    return capabilities.supports_set;
}

- (BOOL)canGetAutoExposure {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.autoExposure];
    return capabilities.supports_get;
}

- (BOOL)setAutoExposure:(BOOL)enabled {
    // 0x01: manual
    // 0x02: auto exposure, auto iris
    // 0x04: shutter priority (manual exposure, auto iris)
    // 0x08: aperture priority (auto exposure, manual iris)
    
    int intval;
    
    // figure out auto exposure value based on what is supported (resolution contains bit mask)
    if (enabled) {
        uvc_range_t range = [self getRangeForControl:&uvc_controls.autoExposure];
        if (range.res & 0x02) { // fully auto
            intval = 0x02;
        }
        else if (range.res & 0x08) { // aperture priority
            intval = 0x08;
        }
        else { // last resort: shutter priority
            intval = 0x04;
        }
    }
    else {
        intval = 0x01;
    }
    
	return [self setData:intval 
			  withLength:uvc_controls.autoExposure.size 
			 forSelector:uvc_controls.autoExposure.selector 
					  at:uvc_controls.autoExposure.unit];
}

- (BOOL)getAutoExposure {
	int intval = (int)[self getDataFor:UVC_GET_CUR
                            withLength:uvc_controls.autoExposure.size
                          fromSelector:uvc_controls.autoExposure.selector
                                    at:uvc_controls.autoExposure.unit];
	
	return ( intval & 0x0e ? YES : NO );
}

// CONTROL: exposure

- (BOOL)canSetExposure {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.exposure];
    return capabilities.supports_set;
}

- (BOOL)canGetExposure {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.exposure];
    return capabilities.supports_get;
}

- (BOOL)setExposure:(float)value {
	value = 1 - value;
	return [self setValue:value forControl:&uvc_controls.exposure];
}

- (float)getExposure {
	float value = [self getValueForControl:&uvc_controls.exposure];
	return 1 - value;
}

// CONTROL: gain

- (BOOL)canSetGain {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.gain];
    return capabilities.supports_set;
}

- (BOOL)canGetGain {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.gain];
    return capabilities.supports_get;
}

- (BOOL)setGain:(float)value {
	return [self setValue:value forControl:&uvc_controls.gain];
}

- (float)getGain {
	return [self getValueForControl:&uvc_controls.gain];
}

// CONTROL: brightness

- (BOOL)canSetBrightness {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.brightness];
    return capabilities.supports_set;
}

- (BOOL)canGetBrightness {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.brightness];
    return capabilities.supports_get;
}

- (BOOL)setBrightness:(float)value {
	return [self setValue:value forControl:&uvc_controls.brightness];
}

- (float)getBrightness {
	return [self getValueForControl:&uvc_controls.brightness];
}

// CONTROL: contrast

- (BOOL)canSetContrast {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.contrast];
    return capabilities.supports_set;
}

- (BOOL)canGetContrast {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.contrast];
    return capabilities.supports_get;
}

- (BOOL)setContrast:(float)value {
	return [self setValue:value forControl:&uvc_controls.contrast];
}

- (float)getContrast {
	return [self getValueForControl:&uvc_controls.contrast];
}

// CONTROL: saturation

- (BOOL)canSetSaturation {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.saturation];
    return capabilities.supports_set;
}

- (BOOL)canGetSaturation {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.saturation];
    return capabilities.supports_get;
}

- (BOOL)setSaturation:(float)value {
	return [self setValue:value forControl:&uvc_controls.saturation];
}

- (float)getSaturation {
	return [self getValueForControl:&uvc_controls.saturation];
}

// CONTROL: sharpness

- (BOOL)canSetSharpness {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.sharpness];
    return capabilities.supports_set;
}

- (BOOL)canGetSharpness {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.sharpness];
    return capabilities.supports_get;
}

- (BOOL)setSharpness:(float)value {
	return [self setValue:value forControl:&uvc_controls.sharpness];
}

- (float)getSharpness {
	return [self getValueForControl:&uvc_controls.sharpness];
}

// CONTROL: auto white balance

- (BOOL)canSetAutoWhiteBalance {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.autoWhiteBalance];
    return capabilities.supports_set;
}

- (BOOL)canGetAutoWhiteBalance {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.autoWhiteBalance];
    return capabilities.supports_get;
}

- (BOOL)setAutoWhiteBalance:(BOOL)enabled {
	int intval = (enabled ? 0x01 : 0x00);
	return [self setData:intval 
			  withLength:uvc_controls.autoWhiteBalance.size 
			 forSelector:uvc_controls.autoWhiteBalance.selector 
					  at:uvc_controls.autoWhiteBalance.unit];
}

- (BOOL)getAutoWhiteBalance {
	int intval = (int)[self getDataFor:UVC_GET_CUR
                            withLength:uvc_controls.autoWhiteBalance.size
                          fromSelector:uvc_controls.autoWhiteBalance.selector
                                    at:uvc_controls.autoWhiteBalance.unit];
	
	return ( intval ? YES : NO );
}

// CONTROL: white balance

- (BOOL)canSetWhiteBalance {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.whiteBalance];
    return capabilities.supports_set;
}

- (BOOL)canGetWhiteBalance {
    uvc_control_capabilities_t capabilities = [self getCapabilitiesForControl:&uvc_controls.whiteBalance];
    return capabilities.supports_get;
}

- (BOOL)setWhiteBalance:(float)value {
	return [self setValue:value forControl:&uvc_controls.whiteBalance];
}

- (float)getWhiteBalance {
	return [self getValueForControl:&uvc_controls.whiteBalance];
}


@end
