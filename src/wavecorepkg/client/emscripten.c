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

EM_JS(char*, wavecore_get_innerhtml, (const char* selector), {
  var elem = document.querySelector(UTF8ToString(selector));
  var content = elem.innerHTML;
  var lengthBytes = lengthBytesUTF8(content)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(content, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, wavecore_set_innerhtml, (const char* selector, const char* html), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.innerHTML = UTF8ToString(html);
});

EM_JS(int, wavecore_set_location, (const char* selector, int left, int top), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.style.left = left + "px";
  elem.style.top = top + "px";
});

EM_JS(int, wavecore_set_size, (const char* selector, int width, int height), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.style.width = width + "px";
  elem.style.height = height + "px";
});

EM_JS(int, wavecore_get_client_width, (), {
  return document.documentElement.clientWidth;
});

EM_JS(int, wavecore_get_client_height, (), {
  return document.documentElement.clientHeight;
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

EM_JS(char*, wavecore_localstorage_list, (), {
  var arr = [];
  Object.keys(localStorage).forEach(function(key){
    arr.push(key);
  });
  var json = JSON.stringify(arr);
  var lengthBytes = lengthBytesUTF8(json)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(json, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, wavecore_play_audio, (const char* src), {
  try {
    wavecoreAudio.pause();
  } catch (e) {}
  try {
    wavecoreAudio = new Audio(UTF8ToString(src));
    wavecoreAudio.play();
  } catch (e) {
    console.error(e);
  }
});

EM_JS(void, wavecore_stop_audio, (), {
  try {
    wavecoreAudio.pause();
  } catch (e) {
    console.error(e);
  }
});

EM_JS(char*, wavecore_get_hash, (), {
  var hash = window.location.hash.slice(1);
  var lengthBytes = lengthBytesUTF8(hash)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(hash, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, wavecore_set_hash, (const char* hash), {
  window.location.hash = UTF8ToString(hash);
});

EM_JS(void, wavecore_open_new_tab, (const char* url), {
  window.open(UTF8ToString(url), "_blank");
});

EM_JS(void, wavecore_set_display, (const char* selector, const char* display), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.style.display = UTF8ToString(display);
});

EM_JS(void, wavecore_focus, (const char* selector), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.focus();
});

EM_JS(void, wavecore_scroll_down, (const char* selector), {
  var elem = document.querySelector(UTF8ToString(selector));
  elem.scrollTop = elem.scrollHeight;
});

EM_JS(int, wavecore_get_cursor_line, (const char* selector), {
  function uuidv4() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  var selection = document.getSelection();
  if (selection.rangeCount < 1) {
    return -1;
  }
  var range = selection.getRangeAt(0);
  range.collapse(true);
  var span = document.createElement('span');
  var id = uuidv4();
  span.appendChild(document.createTextNode(id));
  range.insertNode(span);

  var elem = document.querySelector(UTF8ToString(selector));
  var text = elem.innerText;
  var newLines = 0;
  var lastNewline = null;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n' && lastNewline != i - 1) {
      newLines += 1;
      lastNewline = i;
    } else {
      if (text.substring(i).startsWith(id)) break;
    }
  }

  span.remove();
  return newLines;
});
