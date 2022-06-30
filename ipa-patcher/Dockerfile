ARG alpine=3.16

FROM alpine:${alpine}
ARG curl=7.83.1-r1
ARG libarchive=3.6.1-r0
ARG file=5.41-r0
ARG mksh=59c-r3
RUN apk add \
    curl=${curl} \
    file=${file} \
    libarchive-tools=${libarchive} \
    mksh=${mksh}
RUN ln -vsf /bin/mksh /bin/sh

COPY ipa-patcher.sh /usr/local/bin/
VOLUME [ "/mnt/inputs", "/mnt/outputs" ]

ENTRYPOINT [ "/usr/local/bin/ipa-patcher.sh" ]
