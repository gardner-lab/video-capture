% Compile extract audio MEX helper

% In order to extract synchronized audio and video, a MEX file is required
% that relies on the macOS AVFoundation frameworks for parsing the audio
% and video to extract audio and timestamps. (Video is read using the
% standard MATLAB VideoReader class.)
% 
% Once compiled, you can use the EXTRACTMEDIA function to load a recorded
% file.

% Want compile warnings? Add the following to CXXFLAGS:
% -Weverything -Wno-c++98-compat -Wno-c++98-compat-pedantic -Wno-reserved-id-macro
mex CXXFLAGS='$CXXFLAGS -O3' ...
    LDFLAGS='$LDFLAGS -framework AVFoundation -framework CoreVideo -framework CoreMedia' ...
    extractaudio.mm;