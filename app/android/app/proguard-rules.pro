# ONNX Runtime uses JNI; its entry points must survive release shrinking.
-keep class ai.onnxruntime.** { *; }
