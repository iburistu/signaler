# signaler

signaler is an application that extends [signal-cli](https://github.com/AsamK/signal-cli) with a simple webhook API. The primary focus of this application is to provide a webhook interface for secure messaging over the Signal network. I wasn't super comfortable with sending webhook notifications for events from Grafana over Slack or other webhook providers, so I decided to build my own.

This application uses the DBus bindings in signal-cli to send messages quickly and efficiently. [Rocket](https://rocket.rs/) is used as the web server, and [dbus-rs](https://github.com/diwic/dbus-rs) is the interface between the Rocket webhook & signal-cli. [supervisord](http://supervisord.org/) is the process manager used to launch and control both processes within the container.

This project is __not__ designed to be a full REST API for all of signal-cli's features. If you're looking for something like that, morph027 has an excellent [signal-cli-dbus-rest-api](https://gitlab.com/morph027/signal-cli-dbus-rest-api) project that you can use.

## Getting Started

You'll need the following:

- amd64, arm64, or armv7l architecture CPU
- Docker or other OCI containerization software
- A registered or linked Signal account with signal-cli that will send messages on your behalf
- A Signal account to receive messages

signaler has a fully functioning signal-cli binary included - with that you can create or link a Signal account to use as the sending party. More details can be found in the [signal-cli wiki](https://github.com/AsamK/signal-cli/wiki). To access the signal-cli binary, use the following:

> $ docker run -it --rm iburistu/signaler signal-cli \<command line options\>

If you decide use the built-in signal-cli to create your signaler configuration, you could use a Docker volume, or just use a bind mount when linking / creating your account. You'd have to do something similar to the following:

> $ docker run -it --rm -v named-volume-or-bind-mount:$HOME/.local/share/signal-cli iburistu/signaler signal-cli -a +11111111111 register

and 

> $ docker run -it --rm -v named-volume-or-bind-mount:$HOME/.local/share/signal-cli iburistu/signaler signal-cli -a +11111111111 verify ###-####

Refer to the [wiki](https://github.com/AsamK/signal-cli/wiki/Quickstart#set-up-an-account) for more information.

## Building From Source

signaler isn't currently on Docker Hub because of a bug with Cargo, buildx, and armv7l builds (more details [here](https://github.com/docker/buildx/issues/395)). Fortunately, it's straightforward to build from source with the following:

> $ docker build https://github.com/iburistu/signaler.git\#main -t iburistu/signaler

Depending on your machine...this may take a while. On a RPi 4 8GB version it took about 10 minutes and results in an image file of around 177MB. On my amd64 machine it took about 100s and results in an image file of around 191MB.

## Launching Signaler

The easiest way to launch signaler is to use docker-compose. You need to set three environment variables for signaler to run:

- SIGNAL_SENDER
    - Phone number of the Signal account to send messages on behalf of the webhook
- SIGNAL_RECIPIENT
    - Phone number of the Signal account to receive messages from the bot (currently only supports a single number - groups pending). Make sure that any usage of signaler follows the [Signal TOS](https://signal.org/legal/#terms-of-service).
- SIGNALER_SECRET
    - Secret key to secure the webhook. You need to include this secret in the `Authorization` header of your webhook request as `Bearer <SECRET>`. I suggest using something like the following command as a starting point for a secure secret string: 
      > $ cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1

You'll also need to mount the configuration of the sender account to `/etc/signal-cli`. Typically this is `$HOME/.local/share/signal-cli` but YMMV depending on how you linked or created a Signal account using signal-cli.

Here's an example `docker-compose.yaml` configuration:

```yaml
version: '3.9'

services:
  signaler:
    container_name: signaler
    environment:
      - SIGNAL_SENDER="+11111111111"
      - SIGNAL_RECIPIENT="+22222222222"
      - SIGNALER_SECRET=supersecretpassword
    image: iburistu/signaler
    ports:
      - 8080:8080
    volumes:
      - $HOME/.local/share/signal-cli:/etc/signal-cli
    restart: unless-stopped
```

## Sending Messages

Sending messages using signaler is relatively straightforward - send a POST request to the service with a valid `Authorization` and `Content-Type` header, with a JSON body that has the property `message`, with the value matching the sent message to the recipient. An example request is show below:

```sh
$ curl -X POST 'http://192.168.1.1:8080' \
    -H 'Authorization: Bearer supersecretpassword' \
    -H 'Content-Type: application/json' \
    -d '{
          "message": "hi from signaler!"
        }'
```

You'll receive a timestamp back from signaler to confirm the message was sent successfully. Your recipient number should receive a message shortly with the `message` value.

You can format the `message` value with emoji, newlines, etc. Get creative!

## Debugging

Two named FIFO pipes are created within the container, `/dev/signal` & `/dev/webhook`. You can read logs from either process using the following:

> $ docker exec --it \<container name\> tail -F /dev/\<FIFO pipe\>

I decided to pipe the outputs of both processes into named pipes because I originally intended to have a reader that could read incoming messages...but that may have been too ambitious & does not fit within the limited scope of this project. This may change in the future.