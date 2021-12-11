This is the server implementation of ANSIWAVE BBS, along with the client networking / database code so they can be tested together. To build an executable ready for running on a server, do:

```
nimble build -d:release
```

Then run the `wavecore` executable without any arguments. You can change the port by editing the value near the top of `src/wavecore.nim`.

When it runs for the first time, it will create a directory called `bbs` in the current working directory, which is where all the public files will be stored.

Never expose the wavecore server directly to external connections. Instead, put it behind a proxy server like nginx.

Make your proxy server serve the `bbs` directory as static files, and additionally forward the `/ansiwave` endpoint to the wavecore server. For example, if you're using nginx, edit the config at `/etc/nginx/sites-enabled/default` and somewhere in the `server` block add:

```
server {
        ...

        location /ansiwave {
                proxy_pass  http://127.0.0.1:3000/ansiwave;
        }

        root /path/to/bbs;

        ...
}
```

Assuming nginx is serving on port 80, you should then be able to connect to it with the ansiwave terminal client like this:

```
ansiwave http://localhost:80
```

Replace `localhost` with your public IP or hostname to connect to it remotely.
