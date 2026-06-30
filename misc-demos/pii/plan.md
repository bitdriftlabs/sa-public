customer wants to test this regex:

(?ix)
(
  (?:authorization|proxy-authorization)\s*[:=]\s*bearer\s+[A-Za-z0-9._~+/=-]{8,}
 | (?:access[_-]?token|refresh[_-]?token|auth[_-]?token|id[_-]?token|session[_-]?token|bearer|api[_-]?key|secret)\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{8,}
 | (?:device[_-]?id|client[_-]?device[_-]?id|oai[_-]?device[_-]?id)\s*[:=]\s*["']?[A-Za-z0-9._:-]{8,}
 | Bearer\s+[A-Za-z0-9._~+/=-]{8,}
 | eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}
 | encdvc_[0-9a-f]{32,}
 | ua-[0-9a-fA-F-]{8,}
 | [0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}
)

we need an app that generates custom logs that contain values that will be filtered by this
use /Volumes/external/code/bitdrift/storage/crashdemo/android as a base app- same format of app just generating logs/events instead of crashes

bitdrift instrumented with current sdk version

examples are here: /Volumes/external/code/bitdrift/storage/pii/regex-validation.md