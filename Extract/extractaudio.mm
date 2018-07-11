#include <iostream>
#include <vector>
#include <Cocoa/Cocoa.h>
#include <AVFoundation/AVFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <CoreMedia/CoreMedia.h>
#include <mex.h>

/* prototypes */
NSString *charToNSString(const mxArray *char_array_ptr);
mxArray *extractAudio(NSString *file);

NSString *charToNSString(const mxArray *char_array_ptr) {
    char *buf;
    mwSize number_of_dimensions, buflen;
    const mwSize *dims;
    NSString *ret;
    
    /* Confirm type */
    if (mxGetClassID(char_array_ptr) != mxCHAR_CLASS) {
        return nil;
    }
    
    /* Get the shape of the input mxArray. */
    dims = mxGetDimensions(char_array_ptr);
    number_of_dimensions = mxGetNumberOfDimensions(char_array_ptr);
    if (number_of_dimensions != 2) {
        return nil;
    }
    if (dims[0] != 1) {
        return nil;
    }
    
    /* allocate buffer to hold string */
    buflen = mxGetNumberOfElements(char_array_ptr) + 1;
    buf = static_cast<char *>(mxCalloc(buflen, sizeof(char)));
    
    /* Copy the string data from string_array_ptr and place it into buf. */
    if (mxGetString(char_array_ptr, buf, buflen) != 0) {
        /* free buffer */
        mxFree(buf);
        
        return nil;
    }
    
    // create nsstring
    ret = [NSString stringWithUTF8String:buf];
    
    /* free buffer */
    mxFree(buf);
    
    return ret;
}

mxArray *extractAudio(NSString *file) {
    /* get file pointer */
    NSURL *url = [NSURL fileURLWithPath:file];
    if (!url) {
        mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidInput", "Invalid file name.");
    }
    
    /* CREATE ASSET */
    AVAsset *assetToRead = [AVAsset assetWithURL:url];
    
    /* CREATE ASSET READER */
    NSError *outError;
    AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:assetToRead error:&outError];
    if (!assetReader) {
        mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidInput", "Unable to read AV asset.");
    }
    
    /* GET TRACKS */
    NSArray<AVAssetTrack *> *tracksAudio = [assetToRead tracksWithMediaType:AVMediaTypeAudio];
    NSArray<AVAssetTrack *> *tracksVideo = [assetToRead tracksWithMediaType:AVMediaTypeVideo];
    if ([tracksAudio count] > 1 || [tracksVideo count] > 1 || ([tracksAudio count] == 0 && [tracksVideo count] == 0)) {
        mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidMedia", "AV asset must have one audio or video track or one of each.");
    }
    
    // actual outputs
    AVAssetReaderOutput *outputAudio = nil;
    AVAssetReaderOutput *outputVideo = nil;
    
    /* track audio */
    if ([tracksAudio count]) {
        NSDictionary *outputSettings = @{AVFormatIDKey: [NSNumber numberWithUnsignedInt:kAudioFormatLinearPCM], AVLinearPCMBitDepthKey: [NSNumber numberWithInt:32], AVLinearPCMIsFloatKey: @true, AVLinearPCMIsNonInterleaved: @true};
        
        outputAudio = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[tracksAudio objectAtIndex:0] outputSettings:outputSettings];
        
        if (![assetReader canAddOutput:outputAudio]) {
            mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidMedia", "Can not read audio track.");
        }
        [assetReader addOutput:outputAudio];
    }
    
    /* track video */
    if ([tracksVideo count]) {
        NSDictionary *outputSettings = @{static_cast<NSString *>(kCVPixelBufferPixelFormatTypeKey): [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB]};
        
        outputVideo = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[tracksVideo objectAtIndex:0] outputSettings:outputSettings];
        
        if (![assetReader canAddOutput:outputVideo]) {
            mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidMedia", "Can not read video track.");
        }
        [assetReader addOutput:outputVideo];
    }
    
    /* START */
    if (![assetReader startReading]) {
        mexErrMsgIdAndTxt("MATLAB:extractaudio:readingFailed", "Unable to start reading media.");
    }
    
    /* create the return variable */
    mxArray *ret;
    ret = mxCreateStructMatrix(1, 1, 0, {});
    
    /* audio */
    if (outputAudio) {
        // output holders
        std::vector<double> audioTimes;
        std::vector<std::vector<float>> audioData;
        double audioFrameRate = 0;
        
        BOOL done = NO;
        while (!done) {
            CMSampleBufferRef sampleBuffer = [outputAudio copyNextSampleBuffer];
            if (sampleBuffer) {
                // get count
                CMItemCount count = CMSampleBufferGetNumSamples(sampleBuffer);
                if (count == 0) {
                    CFRelease(sampleBuffer);
                    continue;
                }
                
                // get format
                CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
                const AudioStreamBasicDescription *audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format);
                
                // create channels
                if (audioData.size()) {
                    if (audioData.size() != audioDescription[0].mChannelsPerFrame) {
                        mexErrMsgIdAndTxt("MATLAB:extractaudio:readingFailed", "The number of channels changed during reading");
                    }
                }
                else {
                    // approximate capacity
                    CMTimeRange trackTime = [[tracksAudio objectAtIndex:0] timeRange];
                    unsigned int approximateLength = static_cast<unsigned int>(CMTimeGetSeconds(trackTime.duration) * audioDescription[0].mSampleRate);
                    
                    // store audio frame rate
                    audioFrameRate = audioDescription[0].mSampleRate;
                    
                    // initalize channel pattern
                    audioTimes.reserve(approximateLength);
                    for (unsigned int i = 0; i < audioDescription[0].mChannelsPerFrame; i++) {
                        audioData.push_back(std::vector<float>());
                        audioData[i].reserve(approximateLength);
                    }
                }
                
                // get timing information
                CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                
                // get buffer
                size_t lengthAtOffset, totalLength;
                CMBlockBufferRef audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                float *samples;
                CMBlockBufferGetDataPointer(audioBuffer, 0, &lengthAtOffset, &totalLength, reinterpret_cast<char **>(&samples));
                
                // for each channel
                for (unsigned int i = 0; i < audioDescription[0].mChannelsPerFrame; i++) {
                    // append data
                    audioData[i].insert(audioData[i].end(), samples + (i * count), samples + (i * count) + count);
                }
                
                // for each time step
                for (unsigned int i = 0; i < count; i++) {
                    audioTimes.push_back(CMTimeGetSeconds(CMTimeMake(time.value + i, time.timescale)));
                }
                
                // clean up
                CMSampleBufferInvalidate(sampleBuffer);
                CFRelease(sampleBuffer);
                sampleBuffer = nullptr;
            }
            else {
                if (assetReader.status == AVAssetReaderStatusFailed) {
                    mexErrMsgIdAndTxt("MATLAB:extractaudio:readingFailed", "Reading failed during audio.");
                }
                else {
                    // all done!
                    done = YES;
                }
            }
        }
        
        if (audioData.size() && audioTimes.size()) {
            // add audio frame rate
            int fieldAudioFrameRate = mxAddField(ret, "audio_fs");
            mxArray *matrixAudioFrameRate = mxCreateDoubleMatrix(1, 1, mxREAL);
            double *ptrAudioFrameRate = static_cast<double *>(mxGetData(matrixAudioFrameRate));
            ptrAudioFrameRate[0] = audioFrameRate;
            mxSetFieldByNumber(ret, 0, fieldAudioFrameRate, matrixAudioFrameRate);
            
            // add audio times
            int fieldAudioTimes = mxAddField(ret, "audio_t");
            mxArray *matrixAudioTimes = mxCreateDoubleMatrix(audioTimes.size(), 1, mxREAL);
            double *ptrAudioTimes = static_cast<double *>(mxGetData(matrixAudioTimes));
            memcpy(ptrAudioTimes, &audioTimes[0], audioTimes.size() * sizeof(double));
            mxSetFieldByNumber(ret, 0, fieldAudioTimes, matrixAudioTimes);
            
            // add audio data
            int fieldAudioData = mxAddField(ret, "audio");
            mxArray *matrixAudioData = mxCreateNumericMatrix(audioTimes.size(), audioData.size(), mxSINGLE_CLASS, mxREAL);
            float *ptrAudioData = static_cast<float *>(mxGetData(matrixAudioData));
            for (unsigned int i = 0; i < audioData.size(); i++) {
                memcpy(ptrAudioData + (i * audioTimes.size()), &audioData[i][0], audioTimes.size() * sizeof(float));
            }
            mxSetFieldByNumber(ret, 0, fieldAudioData, matrixAudioData);
        }
    }
    
    /* video */
    if (outputVideo) {
        // output holders
        std::vector<double> videoTimes;
//        std::vector<char> videoData;
//        int width, height;
        CMTimeRange trackTime = [[tracksVideo objectAtIndex:0] timeRange];
        double videoFrameRate = static_cast<double>([[tracksVideo objectAtIndex:0] nominalFrameRate]);
        unsigned int approximateLength = static_cast<unsigned int>(CMTimeGetSeconds(trackTime.duration) * videoFrameRate);
        
        // reserve space
        videoTimes.reserve(approximateLength);
        
        BOOL done = NO;
        while (!done) {
            CMSampleBufferRef sampleBuffer = [outputVideo copyNextSampleBuffer];
            if (sampleBuffer) {
                // get count
                CMItemCount count = CMSampleBufferGetNumSamples(sampleBuffer);
                if (count == 0) {
                    CFRelease(sampleBuffer);
                    continue;
                }
                
                // more than one frame?
                if (count > 1) {
                    CFRelease(sampleBuffer);
                    mexErrMsgIdAndTxt("MATLAB:extractaudio:readingFailed", "More than one frame returned per sample buffer.");
                }
                
                // add timing information
                CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                videoTimes.push_back(CMTimeGetSeconds(time));
                
                // POTENTIALLY extract video data
                // imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                // image = CIImage(cvImageBuffer: imageBuffer)
                
                // clean up
                CMSampleBufferInvalidate(sampleBuffer);
                CFRelease(sampleBuffer);
                sampleBuffer = nullptr;
            }
            else {
                if (assetReader.status == AVAssetReaderStatusFailed) {
                    mexErrMsgIdAndTxt("MATLAB:extractaudio:readingFailed", "Reading failed during video.");
                }
                else {
                    // all done!
                    done = YES;
                }
            }
        }
        
        if (videoTimes.size()) {
            // add video frame rate
            int fieldVideoFrameRate = mxAddField(ret, "video_fs");
            mxArray *matrixVideoFrameRate = mxCreateDoubleMatrix(1, 1, mxREAL);
            double *ptrVideoFrameRate = static_cast<double *>(mxGetData(matrixVideoFrameRate));
            ptrVideoFrameRate[0] = videoFrameRate;
            mxSetFieldByNumber(ret, 0, fieldVideoFrameRate, matrixVideoFrameRate);
            
            // add video times
            int fieldVideoTimes = mxAddField(ret, "video_t");
            mxArray *matrixVideoTimes = mxCreateDoubleMatrix(videoTimes.size(), 1, mxREAL);
            double *ptrVideoTimes = static_cast<double *>(mxGetData(matrixVideoTimes));
            memcpy(ptrVideoTimes, &videoTimes[0], videoTimes.size() * sizeof(double));
            mxSetFieldByNumber(ret, 0, fieldVideoTimes, matrixVideoTimes);
            
//            // add video data
//            int fieldVideoData = mxAddField(ret, "video");
//            mxArray *matrixVideoData = mxCreateNumericMatrix(videoTimes.size(), videoData.size(), mxSINGLE_CLASS, mxREAL);
//            float *ptrVideoData = static_cast<float *>(mxGetPr(matrixVideoData));
//            for (unsigned int i = 0; i < videoData.size(); i++) {
//                memcpy(ptrVideoData + (i * videoTimes.size()), &videoData[i][0], videoTimes.size() * sizeof(float));
//            }
//            mxSetFieldByNumber(ret, 0, fieldVideoData, matrixVideoData);
        }
    }
    
    /* RETURN */
    return ret;
}

/* the gateway function */
void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    NSString *file;
	
	/*  check for proper number of arguments */
	if (nrhs != 1) {
		mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidNumInputs", "One input required.");
	}
	if (nlhs != 1) {
		mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidNumOutputs", "One output required.");
	}
	
	/* validate input */
    file = charToNSString(prhs[0]);
    if (!file) {
        mexErrMsgIdAndTxt("MATLAB:extractaudio:invalidFileName", "Input argument should be a file name.");
    }
	
	/* run the function */
    plhs[0] = extractAudio(file);
	
	return;
}
