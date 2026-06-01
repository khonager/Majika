# flutter_gemma pulls in MediaPipe graph APIs that reference optional profiler
# and graph-template protos not packaged in the Android dependency set.
-dontwarn com.google.mediapipe.proto.**
