FROM eclipse-temurin:11 as jre-build

RUN $JAVA_HOME/bin/jlink \
    --add-modules \
        java.base,java.logging,java.xml,jdk.unsupported \
    --strip-debug \
    --no-man-pages \
    --no-header-files \
    --compress=2 \
    --output /javaruntime

FROM rust:latest as rust-build

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
        libdbus-1-3 \
        libdbus-1-dev \
        pkg-config 

COPY ./app /usr/local/bin/signaler

WORKDIR /usr/local/bin/signaler

RUN cargo build --release

FROM ubuntu:20.04 as runner
ARG SIGNAL_CLI_VER=0.9.2
ARG LIBSIGNAL_VER=0.11.0
ARG ZKGROUP_VER=0.8.2
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${PATH}:${JAVA_HOME}/bin"
ENV SIGNAL_SENDER="+11111111111"
ENV SIGNAL_RECIPIENT="+22222222222"
ENV SIGNALER_SECRET=""

VOLUME [ "/etc/signal-cli" ]
EXPOSE 8080/tcp

LABEL maintainer="Zack Linkletter <zack@linkletter.dev>"

COPY --from=jre-build /javaruntime $JAVA_HOME

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        libdbus-1-3 \
        supervisor \
        zip \
        < /dev/null > /dev/null && \
    rm -rf /var/lib/apt/lists/* && \
    curl -sL "https://github.com/exquo/signal-libs-build/releases/download/signal-cli_v${SIGNAL_CLI_VER}/signal-cli-v${SIGNAL_CLI_VER}-x86_64-Linux.tar.gz" -o /tmp/signal-cli-"${SIGNAL_CLI_VER}".tar.gz && \
    tar -xzf /tmp/signal-cli-"${SIGNAL_CLI_VER}".tar.gz -C /opt && \
    ln -sf /opt/signal-cli-"${SIGNAL_CLI_VER}"/bin/signal-cli /usr/local/bin/ && \
    curl -sL "https://github.com/AsamK/signal-cli/raw/master/data/org.asamk.Signal.conf" -o /etc/dbus-1/system.d/org.asamk.Signal.conf && \
    curl -sL "https://github.com/AsamK/signal-cli/raw/master/data/org.asamk.Signal.service" -o /usr/share/dbus-1/system-services/org.asamk.Signal.service && \
    sed -i -e 's|policy user="signal-cli"|policy user="root"|' /etc/dbus-1/system.d/org.asamk.Signal.conf && \
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
    ls -la /tmp/ && \
    zip -uj /opt/signal-cli-"${SIGNAL_CLI_VER}"/lib/signal-client-java-0.9.7.jar /tmp/libsignal_jni.so || \
    zip -uj /opt/signal-cli-"${SIGNAL_CLI_VER}"/lib/zkgroup-java-0.8.2.jar /tmp/libzkgroup.so || \
    apt-get remove ca-certificates curl zip -y && \
    rm -f /tmp/* && \
    mkfifo /dev/signal && \
    mkfifo /dev/webhook

WORKDIR /usr/local/bin/signaler

COPY --from=rust-build /usr/local/bin/signaler/target/release/signaler-webhook .
COPY --from=rust-build /usr/local/bin/signaler/Rocket.toml .

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENTRYPOINT [ "/usr/bin/dbus-run-session" ]

CMD [ "/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf" ]