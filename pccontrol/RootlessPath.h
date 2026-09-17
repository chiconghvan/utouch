#ifndef ROOTLESS_PATH_H
#define ROOTLESS_PATH_H

// DEPRECATED for jailbreak-binary lookup: ROOTLESS_PREFIX is the fixed
// rootless path (/var/jb) and breaks under roothide's randomized prefix.
// New code must use jbroot() from <roothide.h> first with /var/jb kept only
// as a rootless fallback (see ZXPythonPath/ZXShellPath in ScriptPlayer.xm).
// /var/mobile/... data paths are outside the jbroot and stay valid on both
// schemes, so they are intentionally NOT rewritten.
#define ROOTLESS_PREFIX "/var/jb"
#define ROOTLESS_PATH(path) ROOTLESS_PREFIX path
#define ROOTLESS_PATH_NS(path) @ROOTLESS_PREFIX path

#endif
