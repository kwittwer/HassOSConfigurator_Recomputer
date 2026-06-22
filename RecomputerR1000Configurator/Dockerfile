ARG BUILD_FROM=ghcr.io/home-assistant/base:latest
FROM ${BUILD_FROM}

ENV LANG C.UTF-8

COPY run.sh /
WORKDIR /data

RUN chmod a+x /run.sh \
    && apk add --no-cache util-linux coreutils

CMD [ "/run.sh" ]
