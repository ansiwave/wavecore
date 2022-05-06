#include <emscripten.h>

EM_JS(char*, wavecore_fetch, (const char* url, const char* verb, const char* headers, const char* body), {
  var request = new XMLHttpRequest();
  request.open(UTF8ToString(verb), UTF8ToString(url), false);  // `false` makes the request synchronous

  var headerMap = JSON.parse(UTF8ToString(headers));
  for (key in headerMap) {
    request.setRequestHeader(key, headerMap[key]);
  }

  request.responseType = "arraybuffer";
  request.send(UTF8ToString(body));

  // convert response to a binary string
  var binary = '';
  var bytes = new Uint8Array(request.response);
  var len = bytes.byteLength;
  for (var i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }

  var response = {
    "body": btoa(binary),
    "code": request.status,
    "headers": {
      "Content-Length": request.getResponseHeader("Content-Length"),
      "Content-Range": request.getResponseHeader("Content-Range"),
      "Content-Type": request.getResponseHeader("Content-Type")
    }
  };

  var json = JSON.stringify(response);
  var lengthBytes = lengthBytesUTF8(json)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(json, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});
