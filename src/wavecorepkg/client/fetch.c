#include <emscripten/fetch.h>

emscripten_fetch_t* wavecore_fetch(const char *url) {
  emscripten_fetch_attr_t attr;
  emscripten_fetch_attr_init(&attr);
  strcpy(attr.requestMethod, "GET");
  attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY | EMSCRIPTEN_FETCH_SYNCHRONOUS;
  emscripten_fetch_t *fetch = emscripten_fetch(&attr, url);
  return fetch;
}
