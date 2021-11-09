{.compile: "ed25519/add_scalar.c".}
{.compile: "ed25519/fe.c".}
{.compile: "ed25519/keypair.c".}
{.compile: "ed25519/sc.c".}
{.compile: "ed25519/seed.c".}
{.compile: "ed25519/verify.c".}
{.compile: "ed25519/ge.c".}
{.compile: "ed25519/key_exchange.c".}
{.compile: "ed25519/sha512.c".}
{.compile: "ed25519/sign.c".}

proc ed25519_create_seed*(seed: pointer): cint {.importc.}
proc ed25519_create_keypair*(public_key: pointer; private_key: pointer;
                            seed: pointer) {.importc.}
proc ed25519_sign*(signature: pointer; message: cstring; message_len: csize_t;
                  public_key: pointer; private_key: pointer) {.importc.}
proc ed25519_verify*(signature: pointer; message: cstring; message_len: csize_t;
                    public_key: pointer): cint {.importc.}
proc ed25519_add_scalar*(public_key: pointer; private_key: pointer;
                        scalar: pointer) {.importc.}
proc ed25519_key_exchange*(shared_secret: pointer; public_key: pointer;
                          private_key: pointer) {.importc.}

