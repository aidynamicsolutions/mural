#import "FireRedRuntime.h"
#include "onnxruntime_c_api.h"

// Runtime identity only. No probe UI, asset copying or model initialization.
NSString *MuralFireRedORTVersion(void) {
    return @(OrtGetApiBase()->GetVersionString());
}
