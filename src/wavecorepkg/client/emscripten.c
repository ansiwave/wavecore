#include <emscripten.h>

EM_JS(char*, wavecore_fetch, (const char* url, const char* headers), {
  var request = new XMLHttpRequest();
  request.open('GET', UTF8ToString(url), false);  // `false` makes the request synchronous

  var headerMap = JSON.parse(UTF8ToString(headers));
  for (key in headerMap) {
    request.setRequestHeader(key, headerMap[key]);
  }

  request.responseType = "arraybuffer";
  request.send(null);

  // convert response to a binary string
  var binary = '';
  var bytes = new Uint8Array(request.response);
  var len = bytes.byteLength;
  for (var i = 0; i < len; i++) {
      binary += String.fromCharCode(bytes[i]);
  }

  var response = {
    "body": "",
    "code": request.status,
    "headers": {
      "Content-Length": request.getResponseHeader("Content-Length"),
      "Content-Range": request.getResponseHeader("Content-Range"),
      "Content-Type": request.getResponseHeader("Content-Type")
    }
  };
  if (request.status === 200 || request.status == 206) {
    response["body"] = btoa(binary);
  }

  var json = JSON.stringify(response);
  var lengthBytes = lengthBytesUTF8(json)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(json, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, wavecore_set_innerhtml, (const char* selector, const char* html), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.innerHTML = UTF8ToString(html);
});

EM_JS(void, wavecore_set_display, (const char* selector, const char* display), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.style.display = UTF8ToString(display);
});

EM_JS(void, wavecore_set_size_max, (const char* selector), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.width = document.documentElement.clientWidth;
  elem.height = document.documentElement.clientHeight;
});
