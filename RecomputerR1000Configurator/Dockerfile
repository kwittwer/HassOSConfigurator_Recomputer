ARG BUILD_FROM=ghcr.io/home-assistant/base:latest
FROM ${BUILD_FROM}

ENV LANG C.UTF-8

COPY run.sh /
COPY server.py /
COPY vendor/ /opt/vendor/
WORKDIR /data

RUN chmod a+x /run.sh \
    && apk add --no-cache util-linux coreutils python3 procps py3-paho-mqtt \
    && apk add --no-cache --virtual .build-deps dtc \
    && cp /opt/vendor/seeed/overlays/rpi/reComputer-R100x-overlay.dts /tmp/reComputer-R100x-overlay-build.dts \
    && sed -i '/dt-bindings\/gpio\/gpio.h/d' /tmp/reComputer-R100x-overlay-build.dts \
    && sed -i 's/GPIO_ACTIVE_HIGH/0/g' /tmp/reComputer-R100x-overlay-build.dts \
    && sed -i 's/GPIO_ACTIVE_LOW/1/g' /tmp/reComputer-R100x-overlay-build.dts \
    && dtc -@ -I dts -O dtb -o /opt/vendor/seeed/overlays/rpi/reComputer-R100x.dtbo /tmp/reComputer-R100x-overlay-build.dts \
    && rm -f /tmp/reComputer-R100x-overlay-build.dts \
    && apk del .build-deps

CMD [ "/run.sh" ]
