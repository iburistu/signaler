# Generate minimal JRE for signal-cli
FROM eclipse-temurin:17 as jre-build

RUN $JAVA_HOME/bin/jlink \
    --add-modules \
        java.base,java.logging,java.xml,jdk.unsupported,jdk.security.auth \
    --strip-debug \
    --no-man-pages \
    --no-header-files \
    --compress=2 \
    --output /javaruntime

# Build webhook server code
FROM rust:latest as rust-build

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
        libdbus-1-3 \
        libdbus-1-dev \
        pkg-config 

COPY ./app /usr/local/bin/signaler

WORKDIR /usr/local/bin/signaler

RUN cargo build --release

# Build signal-cli with most up-to-date & compatible libraries
FROM ubuntu:20.04 as signal-cli-build

ARG SIGNAL_CLI_VER=0.10.1
ARG LIBSIGNAL_VER=0.11.0
ARG ZKGROUP_VER=0.8.2

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
        ca-certificates \
        curl \
        zip && \
    curl -sL "https://github.com/exquo/signal-libs-build/releases/download/signal-cli_v${SIGNAL_CLI_VER}/signal-cli-v${SIGNAL_CLI_VER}-x86_64-Linux.tar.gz" -o /tmp/signal-cli-"${SIGNAL_CLI_VER}".tar.gz && \
    tar -xzf /tmp/signal-cli-"${SIGNAL_CLI_VER}".tar.gz -C /opt && \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) \
            echo "Downloading x86_64 specific library files" && \
            curl -sL "https://github.com/exquo/signal-libs-build/releases/download/libsignal-client_v${LIBSIGNAL_VER}/libsignal_jni.so-v${LIBSIGNAL_VER}-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/libsignal_jni.so-v"${LIBSIGNAL_VER}"-x86_64-unknown-linux-gnu.tar.gz && \
            tar -xzf /tmp/libsignal_jni.so-v"${LIBSIGNAL_VER}"-x86_64-unknown-linux-gnu.tar.gz -C /tmp && \
            curl -sL "https://github.com/exquo/signal-libs-build/releases/download/zkgroup_v${ZKGROUP_VER}/libzkgroup.so-v${ZKGROUP_VER}-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/libzkgroup.so-v"${ZKGROUP_VER}"-x86_64-unknown-linux-gnu.tar.gz && \
            tar -xzf /tmp/libzkgroup.so-v"${ZKGROUP_VER}"-x86_64-unknown-linux-gnu.tar.gz -C /tmp \
        ;; \
        aarch64) \
            echo "Downloading aarch64 specific library files" && \
            curl -sL "https://github.com/exquo/signal-libs-build/releases/download/libsignal-client_v${LIBSIGNAL_VER}/libsignal_jni.so-v${LIBSIGNAL_VER}-aarch64-unknown-linux-gnu.tar.gz" -o /tmp/libsignal_jni.so-v"${LIBSIGNAL_VER}"-aarch64-unknown-linux-gnu.tar.gz && \
            tar -xzf /tmp/libsignal_jni.so-v"${LIBSIGNAL_VER}"-aarch64-unknown-linux-gnu.tar.gz -C /tmp && \
            curl -sL "https://github.com/exquo/signal-libs-build/releases/download/zkgroup_v${ZKGROUP_VER}/libzkgroup.so-v${ZKGROUP_VER}-aarch64-unknown-linux-gnu.tar.gz" -o /tmp/libzkgroup.so-v"${ZKGROUP_VER}"-aarch64-unknown-linux-gnu.tar.gz && \
            tar -xzf /tmp/libzkgroup.so-v"${ZKGROUP_VER}"-aarch64-unknown-linux-gnu.tar.gz -C /tmp \
        ;; \
        armv7l) \
            echo "Downloading armv7l specific library files" && \
            curl -sL "https://github.com/exquo/signal-libs-build/releases/download/libsignal-client_v${LIBSIGNAL_VER}/libsignal_jni.so-v${LIBSIGNAL_VER}-armv7-unknown-linux-gnueabihf.tar.gz" -o /tmp/libsignal_jni.so-v"${LIBSIGNAL_VER}"-armv7-unknown-linux-gnueabihf.tar.gz && \
            tar -xzf /tmp/libsignal_jni.so-v"${LIBSIGNAL_VER}"-armv7-unknown-linux-gnueabihf.tar.gz -C /tmp && \
            curl -sL "https://github.com/exquo/signal-libs-build/releases/download/zkgroup_v${ZKGROUP_VER}/libzkgroup.so-v${ZKGROUP_VER}-armv7-unknown-linux-gnueabihf.tar.gz" -o /tmp/libzkgroup.so-v"${ZKGROUP_VER}"-armv7-unknown-linux-gnueabihf.tar.gz && \
            tar -xzf /tmp/libzkgroup.so-v"${ZKGROUP_VER}"-armv7-unknown-linux-gnueabihf.tar.gz -C /tmp \
        ;; \
    esac; \
    zip -uj /opt/signal-cli-"${SIGNAL_CLI_VER}"/lib/signal-client-java-"${LIBSIGNAL_VER}".jar /tmp/libsignal_jni.so || \
    zip -uj /opt/signal-cli-"${SIGNAL_CLI_VER}"/lib/zkgroup-java-"${ZKGROUP_VER}".jar /tmp/libzkgroup.so || true

# Runtime image
FROM ubuntu:20.04 as runner

ARG SIGNAL_CLI_VER=0.10.1
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${PATH}:${JAVA_HOME}/bin"
ENV SIGNAL_SENDER="+11111111111"
ENV SIGNAL_RECIPIENT="+22222222222"
ENV SIGNALER_SECRET=""

VOLUME [ "/etc/signal-cli" ]
EXPOSE 8080/tcp

LABEL maintainer="Zack Linkletter <zack@linkletter.dev>"

COPY --from=signal-cli-build /opt/signal-cli-"${SIGNAL_CLI_VER}" /opt/signal-cli-"${SIGNAL_CLI_VER}"

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
        dbus \
        libdbus-1-3 \
        supervisor \
        < /dev/null > /dev/null && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /opt/signal-cli-"${SIGNAL_CLI_VER}"/bin/signal-cli /usr/local/bin/ && \
    useradd signaler

WORKDIR /usr/local/bin/signaler

COPY --from=jre-build /javaruntime "${JAVA_HOME}"
COPY --from=rust-build /usr/local/bin/signaler/target/release/signaler-webhook .
COPY --from=rust-build /usr/local/bin/signaler/Rocket.toml .

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY session-local.conf /etc/dbus-1/session-local.conf
COPY org.asamk.Signal.conf /etc/dbus-1/system.d/org.asamk.Signal.conf

USER signaler:signaler

ENTRYPOINT [ "/usr/bin/dbus-run-session", "--config-file", "/etc/dbus-1/session-local.conf" ]

CMD [ "/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf" ]