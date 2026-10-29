/// Stage A only. No experiment can activate in a trace-disabled product build.
const _requested = String.fromEnvironment('VIDEO_FRAME_EXPERIMENT');
const videoFrameExperiment =
    bool.fromEnvironment('VIDEO_TRANSITION_TRACE') &&
        (_requested == 'X0' ||
            _requested == 'X1' ||
            _requested == 'X2' ||
            _requested == 'X3')
    ? _requested
    : '';
const videoFrameExperimentLivePaint =
    videoFrameExperiment == '' ||
    videoFrameExperiment == 'X1' ||
    videoFrameExperiment == 'X3';
const videoFrameExperimentDefaultListener =
    videoFrameExperiment == '' ||
    videoFrameExperiment == 'X2' ||
    videoFrameExperiment == 'X3';
