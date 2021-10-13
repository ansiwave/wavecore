#include <emscripten.h>

EM_JS(char*, wavecore_fetch, (const char* url), {
  var request = new XMLHttpRequest();
  request.open('GET', UTF8ToString(url), false);  // `false` makes the request synchronous
  request.send(null);

  if (request.status === 200) {
    var lengthBytes = lengthBytesUTF8(request.responseText)+1;
    var stringOnWasmHeap = _malloc(lengthBytes);
    stringToUTF8(request.responseText, stringOnWasmHeap, lengthBytes);
    return stringOnWasmHeap;
  }
  else {
    return null;
  }
});
