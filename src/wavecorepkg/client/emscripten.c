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

EM_JS(void, wavecore_set_size_max, (const char* selector, int xadd, int yadd), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.width = document.documentElement.clientWidth * window.devicePixelRatio + xadd;
  elem.height = document.documentElement.clientHeight * window.devicePixelRatio + yadd;
});

EM_JS(void, wavecore_browse_file, (const char* callback), {
  var elem = document.createElement("input");
  elem.type = "file";
  var importImage = function(e) {
    var file = e.target.files[0];
    var reader = new FileReader();

    reader.onload = function(e) {
      // convert response to an array
      var bytes = new Uint8Array(e.target.result);

      var arrayOnWasmHeap = _malloc(bytes.byteLength);
      writeArrayToMemory(bytes, arrayOnWasmHeap);

      // call c function
      Module.ccall(UTF8ToString(callback), null, ['string', 'number', 'number'], [file.name, arrayOnWasmHeap, bytes.byteLength]);
    };
    if (file instanceof File) {
      reader.readAsArrayBuffer(file);
    }
    elem.value = '';
  };
  elem.addEventListener('change', importImage);
  elem.click();
});

EM_JS(float, wavecore_get_pixel_density, (), {
  return window.devicePixelRatio;
});

EM_JS(void, wavecore_start_download, (const char* data_uri, const char* filename), {
  var elem = document.createElement("a");
  elem.href = UTF8ToString(data_uri);
  elem.download = UTF8ToString(filename);
  elem.click();
});

EM_JS(int, wavecore_localstorage_set, (const char* key, const char* val), {
  try {
    window.localStorage.setItem(UTF8ToString(key), UTF8ToString(val));
    return 1;
  } catch (e) {
    return 0;
  }
});

EM_JS(char*, wavecore_localstorage_get, (const char* key), {
  var val = window.localStorage.getItem(UTF8ToString(key));
  if (val == null) {
    val = "";
  }
  var lengthBytes = lengthBytesUTF8(val)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(val, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, wavecore_localstorage_remove, (const char* key), {
  window.localStorage.removeItem(UTF8ToString(key));
});

